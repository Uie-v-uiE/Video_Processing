`timescale 1ns/1ps
// RGB invert
module proc_invert (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bypass,
    input  wire        de_in,
    input  wire [15:0] din,
    output reg         de_out,
    output reg  [15:0] dout
);
    wire [4:0] r5 = ~din[15:11];
    wire [5:0] g6 = ~din[10:5];
    wire [4:0] b5 = ~din[4:0];
    wire [15:0] inv = {r5, g6, b5};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_out <= 1'b0;
            dout   <= 16'd0;
        end else begin
            de_out <= de_in;
            dout   <= bypass ? din : inv;
        end
    end
endmodule
