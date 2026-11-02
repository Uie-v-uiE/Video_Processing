`timescale 1ns/1ps
// RGB565 -> luminance gray -> RGB565
module proc_gray (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bypass,
    input  wire        de_in,
    input  wire [15:0] din,
    output reg         de_out,
    output reg  [15:0] dout
);
    wire [4:0] r5 = din[15:11];
    wire [5:0] g6 = din[10:5];
    wire [4:0] b5 = din[4:0];
    // expand to 8b
    wire [7:0] r8 = {r5, r5[4:2]};
    wire [7:0] g8 = {g6, g6[5:4]};
    wire [7:0] b8 = {b5, b5[4:2]};
    // ITU-R BT.601 approx: 0.299R+0.587G+0.114B => *77 + *150 + *29 >> 8
    wire [15:0] y16 = r8 * 8'd77 + g8 * 8'd150 + b8 * 8'd29;
    wire [7:0]  y8  = y16[15:8];
    wire [15:0] gray = {y8[7:3], y8[7:2], y8[7:3]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_out <= 1'b0;
            dout   <= 16'd0;
        end else begin
            de_out <= de_in;
            dout   <= bypass ? din : gray;
        end
    end
endmodule
