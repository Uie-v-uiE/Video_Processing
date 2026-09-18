`timescale 1ns/1ps
// Sync FIFO (same clock).
// OPT: 存储阵列去掉异步复位，便于推断 BRAM（大深度 icmp_fifo 原先落到寄存器堆，
// 导致 eth_rxc@125MHz 域内路径 WNS 为负）。
module sync_fifo #(
    parameter DATA_W = 8,
    parameter ADDR_W = 4   // depth = 2^ADDR_W
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              wr_en,
    input  wire [DATA_W-1:0] wr_data,
    output wire              full,
    input  wire              rd_en,
    output reg  [DATA_W-1:0] rd_data,
    output wire              empty,
    output wire [ADDR_W:0]   level
);
    localparam DEPTH = 1 << ADDR_W;

    (* ram_style = "block" *) reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg [ADDR_W:0]   wptr, rptr;

    assign empty = (wptr == rptr);
    assign full  = (wptr[ADDR_W] != rptr[ADDR_W]) &&
                   (wptr[ADDR_W-1:0] == rptr[ADDR_W-1:0]);
    assign level = wptr - rptr;

    // 存储：仅同步写，无复位 → BRAM
    always @(posedge clk) begin
        if (wr_en && !full)
            mem[wptr[ADDR_W-1:0]] <= wr_data;
    end

    // 指针与读出寄存器：异步复位
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr    <= 0;
            rptr    <= 0;
            rd_data <= 0;
        end else begin
            if (wr_en && !full)
                wptr <= wptr + 1'b1;
            if (rd_en && !empty) begin
                rd_data <= mem[rptr[ADDR_W-1:0]];
                rptr    <= rptr + 1'b1;
            end
        end
    end
endmodule
