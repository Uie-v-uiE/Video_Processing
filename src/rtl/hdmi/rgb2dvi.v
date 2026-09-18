`timescale 1ns/1ps
// RGB888 + sync -> HDMI TMDS differential
module rgb2dvi (
    input  wire       clk_pix,
    input  wire       clk_pix5x,
    input  wire       rst_n,
    input  wire [7:0] r,
    input  wire [7:0] g,
    input  wire [7:0] b,
    input  wire       hs,
    input  wire       vs,
    input  wire       de,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_data_p,
    output wire [2:0] tmds_data_n
);
    wire [9:0] tmds_r, tmds_g, tmds_b;

    // DVI: channel0=Blue+HS/VS, channel1=Green, channel2=Red
    tmds_encoder u_enc_b (
        .clk(clk_pix), .rst_n(rst_n),
        .din(b), .c0(hs), .c1(vs), .de(de), .dout(tmds_b)
    );
    tmds_encoder u_enc_g (
        .clk(clk_pix), .rst_n(rst_n),
        .din(g), .c0(1'b0), .c1(1'b0), .de(de), .dout(tmds_g)
    );
    tmds_encoder u_enc_r (
        .clk(clk_pix), .rst_n(rst_n),
        .din(r), .c0(1'b0), .c1(1'b0), .de(de), .dout(tmds_r)
    );

    tmds_serializer u_ser0 (
        .clk_pix(clk_pix), .clk_pix5x(clk_pix5x), .rst_n(rst_n),
        .din(tmds_b), .data_p(tmds_data_p[0]), .data_n(tmds_data_n[0])
    );
    tmds_serializer u_ser1 (
        .clk_pix(clk_pix), .clk_pix5x(clk_pix5x), .rst_n(rst_n),
        .din(tmds_g), .data_p(tmds_data_p[1]), .data_n(tmds_data_n[1])
    );
    tmds_serializer u_ser2 (
        .clk_pix(clk_pix), .clk_pix5x(clk_pix5x), .rst_n(rst_n),
        .din(tmds_r), .data_p(tmds_data_p[2]), .data_n(tmds_data_n[2])
    );

    // clock channel: constant 0x3FF pattern = pixel clock
    tmds_serializer u_ser_clk (
        .clk_pix(clk_pix), .clk_pix5x(clk_pix5x), .rst_n(rst_n),
        .din(10'b1111100000), .data_p(tmds_clk_p), .data_n(tmds_clk_n)
    );
endmodule
