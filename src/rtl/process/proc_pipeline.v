`timescale 1ns/1ps
// Cascaded effect pipeline. enable[i]=1 means module i is active (not bypassed).
// effect_en[0]=gray, [1]=binary, [2]=blur, [3]=sobel, [4]=invert
// Serial string "00111" => en[2],en[3],en[4] on (left char = en[0])
module proc_pipeline #(
    parameter H_ACTIVE = 640
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  effect_en,
    input  wire [7:0]  threshold,
    input  wire        rotate_active, // retained for status; window filters run in target domain
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire        de_in,
    input  wire [11:0] x_in,
    input  wire [11:0] y_in,
    input  wire [15:0] din,
    output wire        de_out,
    output wire [15:0] dout
);
    // Point ops + window ops all operate on the already inverse-mapped raster
    // (screen/canvas domain). 3x3 neighborhood is valid for any rotation angle.
    wire by0 = ~effect_en[0];
    wire by1 = ~effect_en[1];
    wire by2 = ~effect_en[2];
    wire by3 = ~effect_en[3];
    wire by4 = ~effect_en[4];

    wire        de0; wire [15:0] d0;
    wire        de1; wire [15:0] d1;
    wire        de2; wire [15:0] d2;
    wire        de3; wire [15:0] d3;

    proc_gray u_gray (
        .clk(clk), .rst_n(rst_n), .bypass(by0),
        .de_in(de_in), .din(din), .de_out(de0), .dout(d0)
    );

    proc_binary u_bin (
        .clk(clk), .rst_n(rst_n), .bypass(by1), .threshold(threshold),
        .de_in(de0), .din(d0), .de_out(de1), .dout(d1)
    );

    proc_box_blur #(.H_ACTIVE(H_ACTIVE)) u_blur (
        .clk(clk), .rst_n(rst_n), .bypass(by2),
        .hs_in(hs_in), .vs_in(vs_in), .de_in(de1),
        .x_in(x_in), .y_in(y_in), .din(d1),
        .de_out(de2), .dout(d2)
    );

    proc_sobel #(.H_ACTIVE(H_ACTIVE)) u_sobel (
        .clk(clk), .rst_n(rst_n), .bypass(by3),
        .vs_in(vs_in), .de_in(de2),
        .x_in(x_in), .y_in(y_in), .din(d2),
        .de_out(de3), .dout(d3)
    );

    proc_invert u_inv (
        .clk(clk), .rst_n(rst_n), .bypass(by4),
        .de_in(de3), .din(d3), .de_out(de_out), .dout(dout)
    );
endmodule
