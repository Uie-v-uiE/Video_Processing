`timescale 1ns/1ps
// test_card —— 会动的测试图卡（第三源占位，也是"通路是否活着"的可视证据）。
//
// 为什么不用现成的 `color_bar`：静止彩条**分不清"通路在刷新"和"卡在最后一帧"**。
// 而本作品的核心主张恰恰是"宁可掉帧，也不让半张坏帧上屏"——那就必须有一个东西在动，
// 而且动得可判读。所以这张卡上有四样东西，每样都对应一个真实问题：
//   ① 8 条彩条（与 color_bar 同一套颜色）—— 颜色/通道是否接对、有没有串色
//   ② 一条 2 像素周期的梳齿带 —— 缩放/插值的参照（以后接双线性就看这里）
//   ③ 每帧位移 8 像素的**黄块**（模 H_ACTIVE）—— 一眼看出"在不在动"，也能数出丢帧
//   ④ 底部 8 个二值格 = 帧号低 8 位（白=1，黑=0，每格左沿 4 像素画黑标当对齐基准）
//      —— **不需要字库**，拍照即可读出"屏上这一帧是第几帧"，于是丢帧/重复帧变成可核对的数
//
// 时序契约与 `color_bar` **逐位一致**：输入 (x,y,de)，输出在 `de` 有效时打一拍。
// 这不是洁癖——顶层的 PROC_LAT 与延迟抽头（bar_l_d4 / bar_r_d2）是按 1 拍延迟配好的，
// 换成 2 拍会整体错一行，而那种错在屏幕上只是"偏了一点"，最难查。
//
// 实现上刻意**不出现除法/一般乘法**：格号用 8 个常数阈值比较（与 color_bar 同一手法），
// 格内偏移用一个 8 选 1 的起点 mux。综合友好，也免得在 50 MHz 像素域里挂一条乘法链。
module test_card #(
    parameter H_ACTIVE = 512,
    parameter V_ACTIVE = 300
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vs,          // 场同步：每个上升沿算一帧
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        de,
    output reg  [15:0] rgb565
);
    // ---- 帧号：只在场边界加一 ⇒ 一帧之内它是常量（③④ 都靠它）----
    reg [15:0] frame;
    reg        vs_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin frame <= 16'd0; vs_d <= 1'b0; end
        else begin
            vs_d <= vs;
            if (vs && !vs_d) frame <= frame + 16'd1;
        end
    end

    // ---- 纵向分区（按 V_ACTIVE 等比，改分辨率不用改代码）----
    localparam [11:0] Y_BAR  = (V_ACTIVE * 4) / 5;             // 240 @300
    localparam [11:0] Y_GRAY = Y_BAR + (V_ACTIVE / 16);        // +18
    localparam [11:0] Y_COMB = Y_GRAY + (V_ACTIVE / 32);       // +9
    localparam [11:0] Y_NUM  = Y_COMB + (V_ACTIVE / 25);       // +12
    localparam [11:0] BW     = H_ACTIVE / 8;                   // 条/格宽 64 @512

    // ---- 横向 8 等分：条号 ci 与"本格起点"都用常数阈值，不做除法 ----
    wire [11:0] t1 = BW, t2 = 2*BW, t3 = 3*BW, t4 = 4*BW,
                t5 = 5*BW, t6 = 6*BW, t7 = 7*BW;
    wire [2:0] ci = (x < t1) ? 3'd0 : (x < t2) ? 3'd1 : (x < t3) ? 3'd2 : (x < t4) ? 3'd3 :
                    (x < t5) ? 3'd4 : (x < t6) ? 3'd5 : (x < t7) ? 3'd6 : 3'd7;
    reg  [11:0] cstart;
    always @(*) case (ci)
        3'd0: cstart = 12'd0;    3'd1: cstart = t1;   3'd2: cstart = t2;   3'd3: cstart = t3;
        3'd4: cstart = t4;       3'd5: cstart = t5;   3'd6: cstart = t6;   default: cstart = t7;
    endcase
    wire [11:0] xin = x - cstart;                       // 格内偏移

    // ---- ① 彩条 ----
    reg [7:0] br, bg, bb;
    always @(*) case (ci)
        3'd0:    begin br=8'hFF; bg=8'hFF; bb=8'hFF; end
        3'd1:    begin br=8'hFF; bg=8'hFF; bb=8'h00; end
        3'd2:    begin br=8'h00; bg=8'hFF; bb=8'hFF; end
        3'd3:    begin br=8'h00; bg=8'hFF; bb=8'h00; end
        3'd4:    begin br=8'hFF; bg=8'h00; bb=8'hFF; end
        3'd5:    begin br=8'hFF; bg=8'h00; bb=8'h00; end
        3'd6:    begin br=8'h00; bg=8'h00; bb=8'hFF; end
        default: begin br=8'h10; bg=8'h10; bb=8'h10; end
    endcase

    // ---- ② 梳齿（2 像素周期）与 ③ 移动块 ----
    // 块宽与位移步长都按 H_ACTIVE 取比例：静止图案在低分辨率下会挤成一团，判据就假了。
    // `bx` 用"截位 + 移位"实现 (frame*8) mod H_ACTIVE —— 要求 H_ACTIVE/8 是 2 的幂
    // （64/512/1024 都满足，与 color_bar 用的是同一类假设），这样不需要除法器。
    localparam integer NSTEP = H_ACTIVE / 8;                        // 每 8 像素一步
    localparam integer NB    = $clog2(NSTEP);
    localparam [11:0] BLK_W = (H_ACTIVE / 16 > 4) ? H_ACTIVE / 16 : 4;   // 块宽 32 @512
    wire        comb_hi = ~x[0];
    wire [11:0] bx      = {{(12-NB-3){1'b0}}, frame[NB-1:0], 3'b000};    // frame*8 mod H
    wire [11:0] YB0     = V_ACTIVE / 6, YB1 = YB0 + (V_ACTIVE / 10);     // 块所在的两条横线
    wire        blk     = (x >= bx) && (x < bx + BLK_W) && (y >= YB0) && (y < YB1);

    // ---- ④ 帧号低 8 位：左起第 0 格 = bit7（高位在左，读法和写数一致）----
    wire bitv = frame[7 - ci];
    wire lead = xin < 12'd4;

    reg [7:0] r, g, b;
    always @(*) begin
        if (y < Y_BAR) begin                              // ① 彩条
            r = br; g = bg; b = bb;
        end else if (y < Y_GRAY) begin                    // 灰阶 8 档（通道线性参照）
            r = {ci, 5'b11111}; g = {ci, 5'b11111}; b = {ci, 5'b11111};
        end else if (y < Y_COMB) begin                    // ② 梳齿
            r = comb_hi ? 8'hFF : 8'h00;
            g = comb_hi ? 8'hFF : 8'h00;
            b = comb_hi ? 8'hFF : 8'h00;
        end else if (y < Y_NUM) begin                     // 黑底，让上面的块显眼
            r = 8'h00; g = 8'h00; b = 8'h00;
        end else begin                                    // ④ 帧号二值格
            r = lead ? 8'h00 : (bitv ? 8'hFF : 8'h20);
            g = lead ? 8'h00 : (bitv ? 8'hFF : 8'h20);
            b = lead ? 8'h00 : (bitv ? 8'hFF : 8'h20);
        end
        if (blk) begin r = 8'hFF; g = 8'hFF; b = 8'h00; end   // ③ 块压在最上层（黄块）
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)   rgb565 <= 16'h0000;
        else if (de)  rgb565 <= {r[7:3], g[7:2], b[7:3]};
    end
endmodule
