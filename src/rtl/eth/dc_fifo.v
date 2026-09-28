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
    // #105 第一刀（**纯物理，不改一个比特的语义**）：`wr_full` 要同时喂写指针 CE、BRAM 写使能、
    // 以及**另一个模块**里 `link_monitor` 的丢字计数器 CE。r81 的 28 条失败端点全是这一条：
    // 14 位加法 → 格雷 → 14 位等值比较，再跨模块拉一根长线（报告：25 级、数据路径 73 % 是布线）。
    // 这里让综合器把它**复制成多份本地缓冲**（每个扇出组一份），逻辑式一个字没动 ⇒
    // 所有台架与板上行为不变，变的只是布局布线。下一刀才是"寄存 full + 留一格余量"的结构性改法
    //（那会改变满判据的时序，必须配新判据，见 ISSUES #105）。
    (* max_fanout = 12 *) wire full_now = (wgray_n == {~rgray_s1[ADDR_W:ADDR_W-1], rgray_s1[ADDR_W-2:0]});
    assign wr_full = full_now;

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
