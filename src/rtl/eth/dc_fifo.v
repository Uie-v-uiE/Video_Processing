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
    // #105 第一刀**已回滚**（2026-09-28 深夜，实测无效）：给 `wr_full` 加 `max_fanout=12` 想让综合
    //   复制本地缓冲，结果 WNS 从 r81 的 −0.062 掉到 −0.192、失败端点 28 → 34（凭据 build/r83_gates.txt
    //   与 build/timing_summary.rpt）。⇒ 扇出不是瓶颈。
    // #105 第二刀（2026-09-29，r88）：满判据从"下一个写指针 wgray_n"改成"**当前**写指针 wgray"，
    //   和读侧 `rd_empty = (rgray == wgray_s1)` 对称。原来那一式把 14 位加法 + 二进制转格雷 +
    //   比较整条锥体挂在了 `wr_en → ENARDEN` 上（r87 最差路径 8 级逻辑、0.152 ns，见 build/r87_timing_summary.rpt）；
    //   现在锥体只剩比较。副作用是满提前一格的毛病一起没了：可用深度从 DEPTH−1 变成 DEPTH，
    //   由 sim/tb_cdc_capacity 的 C1 钉住（改前 8191、改后 8192）。
    wire [ADDR_W:0] wbin_n  = wbin + 1'b1;
    wire [ADDR_W:0] wgray_n = bin2gray(wbin_n);
    assign wr_full = (wgray == {~rgray_s1[ADDR_W:ADDR_W-1], rgray_s1[ADDR_W-2:0]});

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
