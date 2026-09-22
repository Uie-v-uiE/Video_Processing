`timescale 1ns/1ps
// snap_cross — 「准静态总线 + 跳变沿捕获」跨域器。
//
// 用法：源域把一个宽总线**整拍**写好，并在同一拍翻转 bus_tog；本模块在目的域
// 等同步过来的跳变沿，再采一次总线。因为边沿要 3 级同步才到达目的域，而源总线
// 至少保持到下一次写入（本项目里 ≥1 ms，正常是一帧），所以采到的一定是完整值，
// 不会撕烈。这和 ddr_bank_commit 用同一套路子。
//
// hb_tog 是独立的心跳（源域每 ms 翻转一次）。目的域在 HB_TO_MS 内没看到沿就
// 置 hb_gone——这唯一能区分「源时钟还在、只是没数据」和「源时钟已经停了」，
// 而后者正是拔掉网线后 PHY 停供 RXC 的表现。
module snap_cross #(
    parameter W            = 320,
    parameter integer DST_HZ   = 25_175_000,
    parameter integer HB_TO_MS = 100
)(
    input  wire            dst_clk,
    input  wire            dst_rst_n,
    input  wire [W-1:0]    bus,
    input  wire            bus_tog,
    input  wire            hb_tog,
    output reg  [W-1:0]    bus_q,
    output reg             hb_gone
);
    localparam integer TW  = $clog2(DST_HZ/1000*HB_TO_MS + 1);
    localparam [TW-1:0] LIM = DST_HZ/1000*HB_TO_MS;

    (* ASYNC_REG = "TRUE" *) reg [2:0] ts;
    (* ASYNC_REG = "TRUE" *) reg [2:0] hs;
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin ts <= 0; hs <= 0; end
        else begin
            ts <= {ts[1:0], bus_tog};
            hs <= {hs[1:0], hb_tog};
        end
    end
    wire bus_edge = ts[2] ^ ts[1];
    wire hb_edge  = hs[2] ^ hs[1];

    reg [TW-1:0] to_cnt;
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            to_cnt  <= LIM;
            hb_gone <= 1'b1;
        end else begin
            if (hb_edge)     to_cnt <= LIM;
            else if (to_cnt) to_cnt <= to_cnt - 1'b1;

            if (hb_edge)     hb_gone <= 1'b0;
            else if (!to_cnt && !hb_gone) hb_gone <= 1'b1;
        end
    end

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) bus_q <= 0;
        else if (bus_edge) bus_q <= bus;
    end
endmodule
