`timescale 1ns/1ps
// Dual-clock FIFO (gray code). Width = DATA_W, depth = 2**ADDR_W.
module dc_fifo #(
    parameter DATA_W = 32,
    parameter ADDR_W = 4
)(
    input  wire              wr_clk,
    input  wire              wr_rst_n,
    input  wire              wr_en,
    input  wire [DATA_W-1:0] wr_data,
    output wire              wr_full,

    input  wire              rd_clk,
    input  wire              rd_rst_n,
    input  wire              rd_en,
    output reg  [DATA_W-1:0] rd_data,
    output wire              rd_empty
);
    localparam DEPTH = (1 << ADDR_W);
    (* ram_style = "block" *) reg [DATA_W-1:0] mem [0:DEPTH-1];

    reg [ADDR_W:0] wbin, wgray, rbin, rgray;
    reg [ADDR_W:0] wgray_s0, wgray_s1, rgray_s0, rgray_s1;

    function [ADDR_W:0] bin2gray;
        input [ADDR_W:0] b;
        bin2gray = b ^ (b >> 1);
    endfunction

    // write
    wire [ADDR_W:0] wbin_n  = wbin + 1'b1;
    wire [ADDR_W:0] wgray_n = bin2gray(wbin_n);
    assign wr_full = (wgray_n == {~rgray_s1[ADDR_W:ADDR_W-1], rgray_s1[ADDR_W-2:0]});

    // write pointer (async rst)
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wbin <= 0; wgray <= 0;
        end else if (wr_en && !wr_full) begin
            wbin  <= wbin_n;
            wgray <= wgray_n;
        end
    end

    // memory write: no reset → BRAM-friendly
    always @(posedge wr_clk) begin
        if (wr_en && !wr_full)
            mem[wbin[ADDR_W-1:0]] <= wr_data;
    end

    // read
    wire [ADDR_W:0] rbin_n  = rbin + 1'b1;
    wire [ADDR_W:0] rgray_n = bin2gray(rbin_n);
    assign rd_empty = (rgray == wgray_s1);

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rbin <= 0; rgray <= 0;
            rd_data <= 0;
        end else if (rd_en && !rd_empty) begin
            rd_data <= mem[rbin[ADDR_W-1:0]];
            rbin  <= rbin_n;
            rgray <= rgray_n;
        end
    end

    // sync
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rgray_s0 <= 0; rgray_s1 <= 0;
        end else begin
            rgray_s0 <= rgray; rgray_s1 <= rgray_s0;
        end
    end
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wgray_s0 <= 0; wgray_s1 <= 0;
        end else begin
            wgray_s0 <= wgray; wgray_s1 <= wgray_s0;
        end
    end
endmodule
