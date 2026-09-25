`timescale 1ns/1ps
// 效果选择解码 + 跨域同步：AXI GPIO(GP0, 100 MHz) → 像素域(50 MHz)。
//
// 两件活：
//  1) **同步**：三对寄存器都是跨域入口，必须 ASYNC_REG，否则工具会把它们当普通逻辑优化掉
//     （同文件里 src_sel / eth_link 的正确写法可对照；这条踩过，见 ISSUES #24/#49）。
//  2) **两套控制源折成一套**：V7 的 5 个使能位与 V8 的 9 位算法选择字同时存在，
//     规则是"新字非 0 就用新字，否则用老位翻出来的等价形式"。
//     为什么是这个方向而不是"两个 OR 起来"：两个都能开的话就再也关不掉了（老位为 0 时新字想关也关不掉），
//     而"老工具还能用"与"新命令能精确控"这两条要同时成立。
//     老位 → 新字的翻译表是**组合逻辑**，因此可台架验证（`tb_v86_pipe_sel` 的 T9 钉映射、
//     T13 钉"新字非 0 时老五位完全不起作用"）。
module effect_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [4:0] effect_en_async,      // V7：0=图卡/灰度…按位（gpio_o[4:0]）
    input  wire [8:0] stage_sel_async,      // V8：新控制字 gpio_cfg[8:0]，0 = "PS 没意见"
    input  wire [2:0] zoom_sel_async,       // V8-8：手动缩放档号 —— **同一个字的 [28:26]**
    input  wire       zoom_manual_async,    // V8-8：[29] 1=停在手动档，0=呼吸（自动）
    input  wire [7:0] threshold_async,
    input  wire [31:0] gamma_async,         // 第二个控制字的**通道 2**：{en, wr, data[7:0], idx[7:0], 其余留}
    output wire [8:0] stage_sel,
    output wire [2:0] zoom_sel,             // 已同步到本域（与 stage_sel **同源同深度**）
    output wire       zoom_manual,          // 同上
    output reg  [4:0] effect_en,            // 给 OSD 显示用的"实际生效"五位（从 stage_sel 反翻）
    output reg  [7:0] threshold,
    output reg         gamma_en,
    output reg         gamma_wr,            // 已同步的**翻转位**（边沿检测在 gamma_lut 里做）
    output reg  [7:0]  gamma_idx,
    output reg  [7:0]  gamma_data,
    output reg  [5:0]  gamma_disp           // V8-5：只给 OSD 看的"当前 gamma ×10"（不参与运算）
    // 说明：OSD 要的"五级实际生效的九位"**已经在 `stage_sel` 这个输出口上**
    //（它就是"新字非 0 用新字、否则用老五位翻出来的等价形式"那道合流之后的值），
    // 所以这里不再另开一个口 —— 开两个口迟早会出现两个口给两个不同答案的那天。
);
    (* ASYNC_REG = "TRUE" *) reg [4:0] en_meta, en_sync;
    // V8-8：缩放的两个位**并进这一条**，不另开一组 —— 理由与 gamma 那四位一样：
    // PS 用**一次整字写**改 `stage_sel`/`zsel`/`manual`，而 `zoom_ctrl` 把 `manual` 与 `zsel`
    // 当一对用（manual=1 时必须看见对应档号）。分两组同步就会出现"旗标到了、档号还是上一次的"，
    // 那正好是 #58/#59 一路在防的那类错拍。同一条链 ⇒ 同源同深度。
    (* ASYNC_REG = "TRUE" *) reg [12:0] sel_meta, sel_sync;   // {manual, zsel[2:0], stage[8:0]}
    (* ASYNC_REG = "TRUE" *) reg [7:0] th_meta, th_sync;
    // gamma 那四个字段一起过同一对同步器：`wr` 是边沿标志，协议要求"idx/data 在 wr 翻转之前
    // 已经稳定至少一次 AXI 写"，所以它们必须与 wr **同源同深度** —— 分两组同步就会出现在
    // 本域里"边沿到了、数据还是上一次的"那种错拍（spec §6b D4 方案②的前提条件）。
    (* ASYNC_REG = "TRUE" *) reg [23:0] gm_meta, gm_sync;   // {en, wr, data, idx, disp[5:0]}

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en_meta <= 5'd0;  en_sync  <= 5'd0;
            sel_meta <= 13'd0; sel_sync <= 13'd0;
            th_meta <= 8'd80; th_sync  <= 8'd80;
            gm_meta <= 24'd0; gm_sync  <= 24'd0;
        end else begin
            en_meta  <= effect_en_async;
            en_sync  <= en_meta;
            sel_meta <= {zoom_manual_async, zoom_sel_async, stage_sel_async};
            sel_sync <= sel_meta;
            th_meta  <= threshold_async;
            th_sync  <= th_meta;
            gm_meta  <= {gamma_async[31], gamma_async[30], gamma_async[29:22],
                         gamma_async[21:14], gamma_async[13:8]};
            gm_sync  <= gm_meta;
        end
    end

    // 位序照 `PLAN_V8_SPEC.md` §6b 的字：[31] en、[30] wr（翻转=写一项）、[29:22] data、
    // [21:14] idx、[13:8] **gamma_disp**（V8-5 新加的 6 位，只给 OSD 看，不参与任何运算）。
    // 为什么并进这一条链而不是另开一组：§7a 的第三条规矩"新增的位一律走 effect_ctrl 已有的
    // 那条 ASYNC_REG 链" —— 新开一组就多一对跨域配对，`cdc.rpt` 的基线就要重画，
    // 而那 3 行 Critical 是唯一能挡住"新代码悄悄裸采样"的门禁。
    always @(*) begin
        {gamma_en, gamma_wr, gamma_data, gamma_idx, gamma_disp} = gm_sync;
    end

    // 老五位 → 新九位（invert 从 bit4 挪到 bit1、binary 从 bit1 挪到 bit5，其余原位）
    reg [8:0] legacy_sel;
    always @(*) begin
        legacy_sel      = 9'd0;
        legacy_sel[0]   = en_sync[0];   // gray
        legacy_sel[1]   = en_sync[4];   // invert
        legacy_sel[2]   = en_sync[2];   // blur
        legacy_sel[4]   = en_sync[3];   // sobel
        legacy_sel[5]   = en_sync[1];   // binary
    end

    wire [8:0] sel_pix = sel_sync[8:0];
    assign stage_sel   = (sel_pix != 9'd0) ? sel_pix : legacy_sel;
    // V8-8 的两个新出口：与 `stage_sel` **同一条链、同一深度**（见上面 sel_meta 的注释）
    assign zoom_sel    = sel_sync[11:9];
    assign zoom_manual = sel_sync[12];

    // 反翻给 OSD：新字里的锐化([3])与形态学([7]/[8])在这一行放不下，等 V8-5 换四行 OSD 时补
    wire [8:0] s = stage_sel;
    always @(*) begin
        effect_en = {s[4], s[1], s[2], s[5], s[0]};   // 位序照 V7：[0]gray [1]binary [2]blur [3]sobel [4]invert
        threshold = th_sync;
    end
endmodule
