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
    // 指针是 ADDR_W+1 位的二进制，跨域只传**格雷码**版本（相邻两位才可能同时变）；
    // full 用"对端格雷码的最高两位取反、其余相等"判，省掉一次二进制比较。
    wire [ADDR_W:0] wbin_n  = wbin + 1'b1;
    wire [ADDR_W:0] wgray_n = bin2gray(wbin_n);
    // #105 第一刀**已回滚**（2026-09-28 深夜，实测无效）：给 `wr_full` 加 `max_fanout=12` 想让综合
    //   复制本地缓冲，结果 WNS 从 r81 的 − 0.062 掉到 − 0.192、失败端点 28 → 34（凭据 build/r83_gates.txt
    //   与 build/timing_summary.rpt）。**说明瓶颈不是扇出，是锥体本身**：14 位加法 → 二进制转格雷 →
    //   14 位等值比较，全压在写域一拍里。剩下的两条真修法（降深度 / 留一格余量）与为什么不能把满判据
    //   搬到读域算，写在 `docs/log/OVERNIGHT_LOG.md` 00:56 那一节。
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

    // 格雷码指针跨域：各在**对方**时钟域打两拍（s0→s1），二进制指针永不跨域
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
