`timescale 1ns/1ps
// 1280x720@60-ish timing (pixel clock 75 MHz on this board)
module video_timing_720p (
    input  wire        clk,      // 75 MHz
    input  wire        rst_n,
    output wire [11:0] x,
    output wire [11:0] y,
    output wire        hs,
    output wire        vs,
    output wire        de,
    output wire        frame_start,
    output wire        frame_done
);
    // Standard 720p totals; refresh ~60.6 Hz at 75 MHz
    video_timing #(
        .H_ACTIVE(1280), .V_ACTIVE(720),
        .H_FP(110), .H_SYNC(40), .H_BP(220),
        .V_FP(5),  .V_SYNC(5),  .V_BP(20),
        .H_POL(1'b1), .V_POL(1'b1)
    ) u_t (
        .clk(clk), .rst_n(rst_n),
        .x(x), .y(y), .hs(hs), .vs(vs), .de(de),
        .frame_start(frame_start), .frame_done(frame_done)
    );
endmodule
