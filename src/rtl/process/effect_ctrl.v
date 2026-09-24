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
//     老位 → 新字的翻译表是**组合逻辑**，因此可台架验证（tb_v88 的第 10/11 条）。
module effect_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [4:0] effect_en_async,      // V7：0=图卡/灰度…按位（gpio_o[4:0]）
    input  wire [8:0] stage_sel_async,      // V8：新控制字 gpio_cfg[8:0]，0 = "PS 没意见"
    input  wire [7:0] threshold_async,
    output wire [8:0] stage_sel,
    output reg  [4:0] effect_en,            // 给 OSD 显示用的"实际生效"五位（从 stage_sel 反翻）
    output reg  [7:0] threshold
);
    (* ASYNC_REG = "TRUE" *) reg [4:0] en_meta, en_sync;
    (* ASYNC_REG = "TRUE" *) reg [8:0] sel_meta, sel_sync;
    (* ASYNC_REG = "TRUE" *) reg [7:0] th_meta, th_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en_meta <= 5'd0;  en_sync  <= 5'd0;
            sel_meta <= 9'd0; sel_sync <= 9'd0;
            th_meta <= 8'd80; th_sync  <= 8'd80;
        end else begin
            en_meta  <= effect_en_async;
            en_sync  <= en_meta;
            sel_meta <= stage_sel_async;
            sel_sync <= sel_meta;
            th_meta  <= threshold_async;
            th_sync  <= th_meta;
        end
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

    assign stage_sel = (sel_sync != 9'd0) ? sel_sync : legacy_sel;

    // 反翻给 OSD：新字里的锐化([3])与形态学([7]/[8])在这一行放不下，等 V8-5 换四行 OSD 时补
    wire [8:0] s = stage_sel;
    always @(*) begin
        effect_en = {s[4], s[1], s[2], s[5], s[0]};   // 位序照 V7：[0]gray [1]binary [2]blur [3]sobel [4]invert
        threshold = th_sync;
    end
endmodule
