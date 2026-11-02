`timescale 1ns/1ps
// OSD overlay: shows ANG=hex, EN=binary, FPS=hex at top-left.
module osd_overlay #(
    parameter X0 = 8,
    parameter Y0 = 8,
    parameter CHAR_W = 6,
    parameter CHAR_H = 8,
    parameter MAX_CHARS = 20
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        de,
    input  wire [8:0]  angle,
    input  wire [4:0]  effect_en,
    input  wire [7:0]  fps,
    input  wire [15:0] bg_pix,
    output reg  [15:0] out_pix
);
    wire [11:0] local_x = x - X0;
    wire [11:0] local_y = y - Y0;
    wire in_osd = de && (x >= X0) && (x < X0 + MAX_CHARS*CHAR_W) &&
                  (y >= Y0) && (y < Y0 + CHAR_H);

    wire [4:0] char_idx = local_x / CHAR_W;
    wire [2:0] pix_x    = local_x % CHAR_W;
    wire [2:0] pix_y    = local_y;

    function [7:0] hex_char;
        input [3:0] v;
        begin
            if (v < 10) hex_char = "0" + v;
            else hex_char = "A" + (v - 10);
        end
    endfunction

    reg [7:0] chars [0:MAX_CHARS-1];
    integer i;
    always @(*) begin
        for (i = 0; i < MAX_CHARS; i = i + 1)
            chars[i] = 8'h20;
        chars[0] = "A";
        chars[1] = hex_char(angle[11:8] & 4'hF);
        chars[2] = hex_char(angle[7:4]);
        chars[3] = hex_char(angle[3:0]);
        chars[4] = 8'h20;
        chars[5] = "E";
        chars[6] = effect_en[0] ? "1" : "0";
        chars[7] = effect_en[1] ? "1" : "0";
        chars[8] = effect_en[2] ? "1" : "0";
        chars[9] = effect_en[3] ? "1" : "0";
        chars[10] = effect_en[4] ? "1" : "0";
        chars[11] = 8'h20;
        chars[12] = "F";
        chars[13] = hex_char(fps[7:4]);
        chars[14] = hex_char(fps[3:0]);
    end

    // 5x7 font for 0-9 A-F
    reg [4:0] font [0:15][0:6];
    initial begin
        font[0][0]=5'b01110; font[0][1]=5'b10001; font[0][2]=5'b10011;
        font[0][3]=5'b10101; font[0][4]=5'b11001; font[0][5]=5'b10001; font[0][6]=5'b01110;
        font[1][0]=5'b00100; font[1][1]=5'b01100; font[1][2]=5'b00100;
        font[1][3]=5'b00100; font[1][4]=5'b00100; font[1][5]=5'b00100; font[1][6]=5'b01110;
        font[2][0]=5'b01110; font[2][1]=5'b10001; font[2][2]=5'b00001;
        font[2][3]=5'b00110; font[2][4]=5'b01000; font[2][5]=5'b10000; font[2][6]=5'b11111;
        font[3][0]=5'b11111; font[3][1]=5'b00010; font[3][2]=5'b00100;
        font[3][3]=5'b00010; font[3][4]=5'b00001; font[3][5]=5'b10001; font[3][6]=5'b01110;
        font[4][0]=5'b00010; font[4][1]=5'b00110; font[4][2]=5'b01010;
        font[4][3]=5'b10010; font[4][4]=5'b11111; font[4][5]=5'b00010; font[4][6]=5'b00010;
        font[5][0]=5'b11111; font[5][1]=5'b10000; font[5][2]=5'b11110;
        font[5][3]=5'b00001; font[5][4]=5'b00001; font[5][5]=5'b10001; font[5][6]=5'b01110;
        font[6][0]=5'b00110; font[6][1]=5'b01000; font[6][2]=5'b10000;
        font[6][3]=5'b11110; font[6][4]=5'b10001; font[6][5]=5'b10001; font[6][6]=5'b01110;
        font[7][0]=5'b11111; font[7][1]=5'b00001; font[7][2]=5'b00010;
        font[7][3]=5'b00100; font[7][4]=5'b01000; font[7][5]=5'b01000; font[7][6]=5'b01000;
        font[8][0]=5'b01110; font[8][1]=5'b10001; font[8][2]=5'b10001;
        font[8][3]=5'b01110; font[8][4]=5'b10001; font[8][5]=5'b10001; font[8][6]=5'b01110;
        font[9][0]=5'b01110; font[9][1]=5'b10001; font[9][2]=5'b10001;
        font[9][3]=5'b01111; font[9][4]=5'b00001; font[9][5]=5'b00010; font[9][6]=5'b01100;
        font[10][0]=5'b01110; font[10][1]=5'b10001; font[10][2]=5'b10001;
        font[10][3]=5'b11111; font[10][4]=5'b10001; font[10][5]=5'b10001; font[10][6]=5'b10001;
        font[11][0]=5'b11110; font[11][1]=5'b10001; font[11][2]=5'b10001;
        font[11][3]=5'b11110; font[11][4]=5'b10001; font[11][5]=5'b10001; font[11][6]=5'b11110;
        font[12][0]=5'b01110; font[12][1]=5'b10001; font[12][2]=5'b10000;
        font[12][3]=5'b10000; font[12][4]=5'b10000; font[12][5]=5'b10001; font[12][6]=5'b01110;
        font[13][0]=5'b11110; font[13][1]=5'b10001; font[13][2]=5'b10001;
        font[13][3]=5'b10001; font[13][4]=5'b10001; font[13][5]=5'b10001; font[13][6]=5'b11110;
        font[14][0]=5'b11111; font[14][1]=5'b10000; font[14][2]=5'b10000;
        font[14][3]=5'b11110; font[14][4]=5'b10000; font[14][5]=5'b10000; font[14][6]=5'b11111;
        font[15][0]=5'b11111; font[15][1]=5'b10000; font[15][2]=5'b10000;
        font[15][3]=5'b11110; font[15][4]=5'b10000; font[15][5]=5'b10000; font[15][6]=5'b10000;
    end

    function [3:0] ascii_to_idx;
        input [7:0] c;
        begin
            if (c >= "0" && c <= "9") ascii_to_idx = c - "0";
            else if (c >= "A" && c <= "F") ascii_to_idx = 4'd10 + (c - "A");
            else ascii_to_idx = 4'd15;
        end
    endfunction

    wire is_hex = (chars[char_idx] >= "0" && chars[char_idx] <= "9") ||
                  (chars[char_idx] >= "A" && chars[char_idx] <= "F");
    wire [3:0] fidx = ascii_to_idx(chars[char_idx]);
    wire [4:0] font_row = font[fidx][pix_y];
    wire pixel_on = in_osd && is_hex && pix_x < 5 && (font_row[4 - pix_x] == 1'b1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            out_pix <= 16'h0000;
        else if (pixel_on)
            out_pix <= 16'hFFFF;
        else
            out_pix <= bg_pix;
    end
endmodule
