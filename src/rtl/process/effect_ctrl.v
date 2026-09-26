`timescale 1ns/1ps
// 效果选择解码 + 跨域同步：AXI GPIO(GP0, 100 MHz) → 像素域(50 MHz)。
//
// 两件活：
//  1) **同步**：下面三对寄存器都是跨域入口，必须 ASYNC_REG，否则工具会把它们当普通逻辑优化掉
//     （同文件里 src_sel / eth_link 的正确写法可对照；这条踩过，见 ISSUES #24/#49）。
//  2) **只有一套控制源**：九级算法选择字 `stage_sel`（一位一级）。
//     V7 那五位 `effect_en` 的兜底合流与"反翻五位给 OSD"的第二出口在 2026-09-26 一起删了
//     （#66：九级命令层 V8-1 之后老五位只剩"新字为 0 时顶上"这一条活路，而 PS 早就每次都写新字，
//     那位 `status` 输出更是从头没人读）。留着它，`pipe 00111` 与 `pipe 000000111` 就是两种答案，
//     而"同一个意思只能有一套写法"是这一版验收过的口径。
module effect_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [8:0] stage_sel_async,      // 唯一的控制字 gpio_cfg[8:0]（九级，一位一级）
    input  wire [2:0] zoom_sel_async,       // V8-8：手动缩放档号 —— **同一个字的 [28:26]**
    input  wire       zoom_manual_async,    // V8-8：[29] 1=停在手动档，0=呼吸（自动）
    input  wire [7:0] threshold_async,
    input  wire [31:0] gamma_async,         // 第二个控制字的**通道 2**：{en, wr, data[7:0], idx[7:0], disp[5:0], temp_bcd[7:0]}
    output wire [8:0] stage_sel,
    output wire [2:0] zoom_sel,             // 已同步到本域（与 stage_sel **同源同深度**）
    output wire       zoom_manual,          // 同上
    output reg  [7:0] threshold,
    output reg         gamma_en,
    output reg         gamma_wr,            // 已同步的**翻转位**（边沿检测在 gamma_lut 里做）
    output reg  [7:0]  gamma_idx,
    output reg  [7:0]  gamma_data,
    output reg  [5:0]  gamma_disp,          // V8-5：只给 OSD 看的"当前 gamma ×10"（不参与运算）
    output reg  [7:0]  temp_disp            // V9-6：只给 OSD 看的片上温度 BCD（同样不参与运算）
    // 说明：OSD 要的"哪几级实际生效"就是 `stage_sel` 这一个出口，不再另开第二个口 ——
    // 开两个口迟早会出现两个口给两个不同答案的那天（五位那个口就是这么废掉的，见文件头）。
);
    // 三对同步器，全是跨域入口 ⇒ 必须 ASYNC_REG（这条踩过，见 ISSUES #24/#49）。
    // V8-8：缩放的两个位**并进 sel 这一条**，不另开一组 —— 理由与 gamma 那四位一样：
    // PS 用**一次整字写**改 `stage_sel`/`zsel`/`manual`，而 `zoom_ctrl` 把 `manual` 与 `zsel`
    // 当一对用（manual=1 时必须看见对应档号）。分两组同步就会出现"旗标到了、档号还是上一次的"，
    // 那正好是 #58/#59 一路在防的那类错拍。同一条链 ⇒ 同源同深度。
    (* ASYNC_REG = "TRUE" *) reg [12:0] sel_meta, sel_sync;   // {manual, zsel[2:0], stage[8:0]}
    (* ASYNC_REG = "TRUE" *) reg [7:0] th_meta, th_sync;
    // gamma 那四个字段一起过同一对同步器：`wr` 是边沿标志，协议要求"idx/data 在 wr 翻转之前
    // 已经稳定至少一次 AXI 写"，所以它们必须与 wr **同源同深度** —— 分两组同步就会出现在
    // 本域里"边沿到了、数据还是上一次的"那种错拍（spec §6b D4 方案②的前提条件）。
    (* ASYNC_REG = "TRUE" *) reg [31:0] gm_meta, gm_sync;   // {en, wr, data, idx, disp[5:0], temp[7:0]}

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sel_meta <= 13'd0; sel_sync <= 13'd0;
            th_meta <= 8'd80; th_sync  <= 8'd80;
            // 复位值低字节是 0xFF 而不是 0：**两位都不是十进制数字 = "还没有可信读数"**，
            // OSD 那一格据此画 `--`。若复位成 0，屏上会在 PS app 起来之前画出 `Temp:00C`——
            // 那是一条没人测过的数，而这一格的本分恰恰是"只画真的测到的"（与 Latency 同一规矩）。
            gm_meta <= 32'h0000_00FF; gm_sync <= 32'h0000_00FF;
        end else begin
            sel_meta <= {zoom_manual_async, zoom_sel_async, stage_sel_async};
            sel_sync <= sel_meta;
            th_meta  <= threshold_async;
            th_sync  <= th_meta;
            gm_meta  <= {gamma_async[31], gamma_async[30], gamma_async[29:22],
                         gamma_async[21:14], gamma_async[13:8], gamma_async[7:0]};
            gm_sync  <= gm_meta;
        end
    end

    // 位序照 `PLAN_V8_SPEC.md` §6b 的字：[31] en、[30] wr（翻转=写一项）、[29:22] data、
    // [21:14] idx、[13:8] **gamma_disp**（V8-5 新加的 6 位，只给 OSD 看，不参与运算）、
    // [7:0] **temp_disp**（V9-6：PS 的 XADC 读数编成 BCD 十进制两位，见下面那条注释）。
    // 为什么并进这一条链而不是另开一组：§7a 的第三条规矩"新增的位一律走 effect_ctrl 已有的
    // 那条 ASYNC_REG 链" —— 新开一组就多一对跨域配对，`cdc.rpt` 的基线就要重画，
    // 而那 3 行 Critical 是唯一能挡住"新代码悄悄裸采样"的门禁。
    //
    // ⚠ **为什么这一格要 PS 侧先算成 BCD 再跨，而不是把二进制温度传过来在这里除**：
    //   OSD 那五行字符是一整块组合逻辑，而 `u_pipe/xd_reg → u_osd/g_reg/D` 正是 clkout0_1
    //   那条 27 级的关键路径（r63b/r63c/r64b 三份报告都指着它）—— 在这里多一次 /100 与 /10
    //   就是往全设计最差的那条链上再加深度。同一件事的先例：Latency 那一格从 #59 起就是
    //   "换算在 axi 域用逐次除法做完再按翻转位跨域"。
    //   代价说清楚：温度这一格的十进制口径由 PS 说了算，PL 只照画 —— 所以"屏上写的数"与
    //   `temp` 打印的数必然同源（判据 tb_osd_lines T15 钉的就是"画的是编码，不是猜的"）。
    always @(*) begin
        {gamma_en, gamma_wr, gamma_data, gamma_idx, gamma_disp, temp_disp} = gm_sync;
    end

    wire [8:0] sel_pix = sel_sync[8:0];
    // 九级控制字**逐位直连**，不再有"老五位兜底"那道合流（#66：五位与九级两套口径并存的最后一天）。
    assign stage_sel   = sel_pix;
    // V8-8 的两个新出口：与 `stage_sel` **同一条链、同一深度**（见上面 sel_meta 的注释）
    assign zoom_sel    = sel_sync[11:9];
    assign zoom_manual = sel_sync[12];

    always @(*) begin
        threshold = th_sync;
    end
endmodule
