`timescale 1ns/1ps
// Built-in color bar + diagonal stripe (RGB565). Synthesis-friendly (no div).
// 定位（09:4x 重扫后据实改口）：**不在综合树里** —— `src/rtl` 内无人例化它，SRC0 那格在 V9 换成会动的
//         测试图卡 `video/test_card.v`（见 `top/pl_video_top.v:714` 那句"位置原来是静止彩条"）。
//         但它**仍被台架用着**：`sim/tb_v81_test_card.v:34` 拿它当"静止对照"的参考实例（`ref_static`），
//         用来证明"图卡在跨帧变"这件事是真的 ⇒ 要删它得先给那支台架换对照。别按 #93 的删除候选处理。
//         功能本身：按 `x/y` 画彩条 + 对角带，坐标由例化者的扫描时序给，刻意不用除法 ⇒ 只成连线/移位。
module color_bar #(
    parameter H_ACTIVE = 640,
    parameter V_ACTIVE = 360
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        de,
    output reg  [15:0] rgb565
);
    // 8 bars: bar index = x * 8 / H_ACTIVE ≈ (x * 8 * inv) with inv=1/640
    // For H_ACTIVE=640: x[9:7] gives 0..4 for 0..639 — use x / 80 instead
    // Generic: compare against thresholds k*H/8
    wire [12:0] x8 = {x, 3'b000}; // x*8
    // Approximate /H_ACTIVE via multiply for common sizes
    // Use shifted comparisons: thresholds at H/8, 2H/8, ...
    wire [12:0] th1 = H_ACTIVE / 8;
    wire [12:0] th2 = (H_ACTIVE * 2) / 8;
    wire [12:0] th3 = (H_ACTIVE * 3) / 8;
    wire [12:0] th4 = (H_ACTIVE * 4) / 8;
    wire [12:0] th5 = (H_ACTIVE * 5) / 8;
    wire [12:0] th6 = (H_ACTIVE * 6) / 8;
    wire [12:0] th7 = (H_ACTIVE * 7) / 8;

    reg [2:0] bar;
    always @(*) begin
        if      (x < th1) bar = 3'd0;
        else if (x < th2) bar = 3'd1;
        else if (x < th3) bar = 3'd2;
        else if (x < th4) bar = 3'd3;
        else if (x < th5) bar = 3'd4;
        else if (x < th6) bar = 3'd5;
        else if (x < th7) bar = 3'd6;
        else              bar = 3'd7;
    end

    reg [7:0] r, g, b;
    always @(*) begin
        case (bar)
            3'd0: begin r=8'hFF; g=8'hFF; b=8'hFF; end
            3'd1: begin r=8'hFF; g=8'hFF; b=8'h00; end
            3'd2: begin r=8'h00; g=8'hFF; b=8'hFF; end
            3'd3: begin r=8'h00; g=8'hFF; b=8'h00; end
            3'd4: begin r=8'hFF; g=8'h00; b=8'hFF; end
            3'd5: begin r=8'hFF; g=8'h00; b=8'h00; end
            3'd6: begin r=8'h00; g=8'h00; b=8'hFF; end
            default: begin r=8'h10; g=8'h10; b=8'h10; end
        endcase
        if (((x + y) & 13'h001F) < 13'h0002) begin
            r = 8'h30; g = 8'h30; b = 8'h30;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rgb565 <= 16'h0000;
        else if (de)
            rgb565 <= {r[7:3], g[7:2], b[7:3]};
        else
            rgb565 <= 16'h0000;
    end
endmodule
