`timescale 1ns/1ps
// 整帧双端口 BRAM（顺序写、随机读）。⚠ **本树无人例化**：现役显示帧缓存是 frame_buffer_w64
//（64bit 写口，包在 fb_bilin/fb_rd5x 里）。遗留件。
// ADDR = y*W + x
module frame_buffer #(
    parameter W = 640,
    parameter H = 360
)(
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,
    input  wire [15:0] wr_data,

    input  wire        rd_clk,
    input  wire [18:0] rd_addr,
    output reg  [15:0] rd_data
);
    localparam DEPTH = W * H;

    (* ram_style = "block" *) reg [15:0] mem [0:DEPTH-1];

    always @(posedge wr_clk) begin
        if (wr_en && wr_addr < DEPTH)
            mem[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk) begin
        if (rd_addr < DEPTH)
            rd_data <= mem[rd_addr];
        else
            rd_data <= 16'h0000;
    end
endmodule
