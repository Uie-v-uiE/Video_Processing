`timescale 1ns/1ps
// 1024x600 @ ~60Hz, pixel clock 50 MHz (spec 50.25MHz, 0.5% ok)
// H: 1024 + 44 + 88 + 188 = 1344
// V: 600  + 3  + 6  + 16  = 625
// HSYNC +, VSYNC -
module video_timing_1024x600 (
    input  wire        clk,
    input  wire        rst_n,
    output wire [11:0] x,
    output wire [11:0] y,
    output wire        hs,
    output wire        vs,
    output wire        de,
    output wire        frame_start,
    output wire        frame_done
);
    video_timing #(
        .H_ACTIVE(1024), .V_ACTIVE(600),
        .H_FP(44), .H_SYNC(88), .H_BP(188),
        .V_FP(3),  .V_SYNC(6),  .V_BP(16),
        .H_POL(1'b1), .V_POL(1'b0)
    ) u_t (
        .clk(clk), .rst_n(rst_n),
        .x(x), .y(y), .hs(hs), .vs(vs), .de(de),
        .frame_start(frame_start), .frame_done(frame_done)
    );
endmodule
