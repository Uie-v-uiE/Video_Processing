`timescale 1ns/1ps
// ⚠ **本模块目前没有被任何顶层例化**（2026-09-25 凌晨）。它连同 `sim/tb_v93_split_ctrl.v`
//   是 V8-4 的第一块，先单独做完、单独判住；接上去的前提写在 **ISSUES #62**：
//   "缝 0~100 % 可调"与现在"左右各 512、每半屏各画一整幅"的几何在数学上不相容，
//   必须先统一成"一条地址流覆盖全屏 + 逐像素选原图/处理图"。
//   在那之前 `main.c` 的 `split ...` 仍然明说"语法已收、硬件待接"，不许静默收下。
//
// V8-4 分割线发生器：手工位置 + 自动三角扫描 + 端点(range)/速度(speed)/交换(swap)/跟随(follow)。
//
// 为什么单独成模块：`split_display` 里那根 `x < PANE_W` 把缝写死在 512，且顺手画了一根
// 硬编码 2 像素蓝线（用户报的"缝周围颜色条"里那根**故意的**成分）。位置/扫描这些**时序**
// 行为要能在台架里判，就得有一个只吃"像素有效性"的独立模块，而不是把计数器塞进混色级。
//
// 三条照仓库旧账写死的规矩：
//  1) **扫描计数按有效像素走**（`de` 才动），不按"第几拍"。这是 #54/#56 那一课：任何拿
//     每拍计数器与 0/末列比的判据，换一种消隐宽度或占空比就挡住不同的列 —— 台架与板子会
//     给出两个不一样的答案（tb_rotate_window 的 SLOT_LAG 假红、"分割线旁边的颜色条"）。
//  2) **不许有 `% 扫描周期`，也不许有运行时的非 2 幂除法**（#58：100 MHz 域的组合除法器
//     把 WNS 打到 −5.014）。往返用"先加后减 + 端点夹紧"的三角波；百分比是
//     `eff * PCT >> 14`，`PCT = 100*16384/W` 是**参数在 elaboration 阶段算好的常数**
//     （综合折成常量，不落进任何硬件），所以 RTL 里没有除法器。
//     这一版能这么算是因为两个宽度都是 2 的幂：DISP_W=1024 ⇒ PCT=1600 精确，
//     SRC_W=512 ⇒ PCT=3200 精确。换成非 2 幂宽度时这里必须改成"每帧一次逐次除法"，
//     台架 T5 会先一步变红（它按整数除法独立算一遍期望值，不抄这里的乘子）。
//  3) **端点用 1/16 宽度作单位**（`lo16/hi16`，0..16）⇒ 换算成像素就是一位移位；
//     不给"端点落在哪一像素"留二义性，也不需要除法。
module split_ctrl #(
    parameter integer DISP_W    = 1024,        // 显示域宽度（缝不跟随时的坐标空间）
    parameter integer SRC_W     = 512,         // 源域宽度（split_follow=1 时的坐标空间）
    parameter integer TICK_BITS = 16           // 扫描一步 = 2^TICK_BITS 个**有效像素**
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de,             // 有效像素旗标（与 split_display 看到的是同一根）
    input  wire [11:0] pos_px,         // 手工位置，单位 = 当前坐标空间的像素
    input  wire        auto_en,
    input  wire        follow,         // 1 = 缝在**源坐标**里量（旋转时跟着画面转）
    input  wire [3:0]  speed,          // 每扫描一步走几个像素；0 = 钉住不动
    input  wire [4:0]  lo16,           // 扫描下端点，1/16 宽度，0..16
    input  wire [4:0]  hi16,           // 扫描上端点，1/16 宽度，0..16
    input  wire        swap,           // 1 = 原图放右边（只换内容，不换缝位）
    output wire [11:0] split_eff,      // 缝位（当前坐标空间的像素）
    output wire        raw_on_left,    // 混色级用：缝左边的内容是原图还是处理图
    output wire [11:0] shown_pct       // 给 OSD 的百分比（同一坐标空间，向下取整）
);
    // 当前坐标空间的宽度。两个分支都是 elaboration 常数 ⇒ 综合出来是 2:1 选线，
    // 既不是除法器也不是桶形移位器。
    // （写成带位宽的 localparam 而不是 `DISP_W[16:0]`：参数是 32 位 integer，对无位宽的
    //   参数做部分选择，xvlog 与 Icarus 的接受度不一样，不值得赌。）
    localparam [16:0] DISP_W17 = DISP_W;
    localparam [16:0] SRC_W17  = SRC_W;
    wire [16:0] W = follow ? SRC_W17 : DISP_W17;

    // ---- 端点：像素 = (u * W) >> 4，u 先夹到 [0,16] ----
    wire [4:0]  lo_c = (lo16 > 5'd16) ? 5'd16 : lo16;
    wire [4:0]  hi_c = (hi16 > 5'd16) ? 5'd16 : hi16;
    wire [20:0] lo_full = {16'd0, lo_c} * W;
    wire [20:0] hi_full = {16'd0, hi_c} * W;
    wire [16:0] lo_px   = lo_full[20:4];                    // >>4：纯接线
    wire [16:0] hi_px   = hi_full[20:4];
    // hi < lo 是**合法输入**（`split range 80 20` 就会这样），不许它把三角波甩出界：
    // 这里把两个端点折成 [min,max]，台架 T3 单独判这一条。
    wire        crossed = (hi_px < lo_px);
    wire [16:0] lo_use  = crossed ? hi_px : lo_px;
    wire [16:0] hi_use  = crossed ? lo_px : hi_px;

    // ---- 三角波（13 bit 够放 W≤4095 且加得下一步长，不会回绕）----
    reg  [TICK_BITS-1:0] tcnt;
    reg  [12:0]          swp;
    reg                  dir;                    // 0 = 向 hi，1 = 向 lo
    wire [12:0] lo13 = {0'd0, lo_use[12:0]};
    wire [12:0] hi13 = {0'd0, hi_use[12:0]};
    wire [12:0] step = {9'd0, speed};
    // "再加一步就到/越过 hi" 的判据。先减后比，不把 swp+step 放到会溢出的位宽里算。
    // 减法要防下溢：hi 很小而 speed 很大时（range 0 0 + speed 15 是合法输入），
    // hi13-step 回绕成一个巨大数 ⇒ "永远没到端点" ⇒ swp 一路涨出去。夹一次。
    wire [12:0] up_lim   = (hi13 >= step) ? (hi13 - step) : 13'd0;
    wire [12:0] down_lim = lo13 + step;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tcnt <= {TICK_BITS{1'b0}};
            swp  <= 13'd0;
            dir  <= 1'b0;
        end else if (de) begin
            if (!auto_en) begin
                // 手工模式下把扫描值**跟住**手工位置 ⇒ 打开 auto 的那一瞬间不跳位
                //（演示里"扫起来先跳一下"会被当成 bug）。夹到 [0,W]，端点由 eff 那一级管。
                swp <= ({5'd0, pos_px} > W) ? W[12:0] : {1'd0, pos_px};
            end else if (tcnt == {TICK_BITS{1'b1}}) begin
                tcnt <= {TICK_BITS{1'b0}};
                if (speed != 4'd0) begin
                    if (!dir) swp <= (swp > up_lim) ? hi13 : swp + step;
                    else      swp <= (swp < down_lim) ? lo13 : swp - step;
                    // 到端点的那一拍同时换向 ⇒ 波形在 lo/hi 各停一拍，绝不越界（T1/T2 判）
                    if (!dir && (swp >= up_lim))   dir <= 1'b1;
                    if ( dir && (swp <= down_lim)) dir <= 1'b0;
                end
            end else begin
                tcnt <= tcnt + 1'b1;
            end
        end
    end

    // ---- 位置选择 + 夹紧到 [0, W] ----
    // 手工位置允许合法地等于 W（"缝推到最右"= 整屏都是缝左侧那一半），所以夹到 W 不是 W−1。
    wire [16:0] raw_sel = auto_en ? {4'd0, swp} : {5'd0, pos_px};
    reg  [12:0] eff_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) eff_r <= 13'd0;
        else        eff_r <= (raw_sel > W) ? W[12:0] : raw_sel[12:0];
    end
    // 扫描值也再夹一次：swp 的端点已经夹在 [lo,hi]⊂[0,W]，这一道是给"中途改 range"用的
    //（改了 lo16/hi16 之后，旧 swp 可能暂时在新端点之外，下一拍才被拉回来）。
    wire [12:0] eff = auto_en ? ((swp > hi13) ? hi13 : ((swp < lo13) ? lo13 : swp))
                              : eff_r;
    assign split_eff   = {1'b0, eff[11:0]};
    assign raw_on_left = ~swap;

    // ---- 百分比：eff*100/W。W 是 2 的幂 ⇒ 乘常数 + 固定移位，无除法硬件 ----
    localparam [13:0] PCT_DISP = (100 * 16384) / DISP_W;
    localparam [13:0] PCT_SRC  = (100 * 16384) / SRC_W;
    wire [26:0] prod_disp = eff * PCT_DISP;      // 左边给足宽度，否则乘法在 14 bit 里截断
    wire [26:0] prod_src  = eff * PCT_SRC;
    wire [7:0]  pct_disp  = prod_disp >> 14;
    wire [7:0]  pct_src   = prod_src  >> 14;
    assign shown_pct = follow ? {4'd0, pct_src} : {4'd0, pct_disp};
endmodule
