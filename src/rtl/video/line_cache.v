`timescale 1ns/1ps
// Simple dual-port line buffer (write one clock, read another)
module line_cache #(
    parameter W = 640
)(
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [11:0] wr_addr,
    input  wire [15:0] wr_data,
    input  wire        rd_clk,
    input  wire [11:0] rd_addr,
    output reg  [15:0] rd_data
);
    (* ram_style = "block" *) reg [15:0] mem [0:W-1];

    always @(posedge wr_clk) begin
        if (wr_en && wr_addr < W)
            mem[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk) begin
        if (rd_addr < W)
            rd_data <= mem[rd_addr];
        else
            rd_data <= 16'h0000;
    end
endmodule
