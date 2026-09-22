`timescale 1ns/1ps
// snap_cross — 「准静态总线 + 跳变沿捕获」跨域器。
//
// 用法：源域把一个宽总线**整拍**写好，并在同一拍翻转 bus_tog；本模块在目的域
// 等同步过来的跳变沿，再采一次总线。因为边沿要 3 级同步才到达目的域，而源总线
// 至少保持到下一次写入（本项目里 ≥1 ms，正常是一帧），所以采到的一定是完整值，
// 不会撕烈。这和 ddr_bank_commit 用同一套路子。
//
// hb_tog 是独立的心跳（源域每「125000 个 eth_rxc 周期」翻转一次）。
// 只测「心跳有没有停」是不够的：2026-09-22 的拔线实验证明 RTL8211F 在链路断开时
// 并不停掉 RXC，而是把它拉到约 1/48（板级证据：断流那 13 s 里 stall_ms 只走了 286 个
// 计数 = +20.5/s，而不是 1000/s）⇒ 心跳一直在，hb_gone 永不触发。
// 关键方向：**源时钟变慢 ⇒ 目的域量到的心跳间隔变长**（不是变短）。所以
//   正常      间隔 1 ms   → to_cnt 只从 LIM 降下一点点
//   时钟退化  间隔 ~50 ms → to_cnt 已经降下来很多  ⇒ hb_slow
//   时钟消失  永远没边沿  → to_cnt 归零            ⇒ hb_gone
// 门限取 SLOW_MS=5：1 ms 与 50 ms 分居两侧，余量各 5 倍与 10 倍。
module snap_cross #(
    parameter W            = 320,
    parameter integer DST_HZ   = 25_175_000,
    parameter integer HB_TO_MS = 100,
    parameter integer SLOW_MS  = 5
)(
    input  wire            dst_clk,
    input  wire            dst_rst_n,
    input  wire [W-1:0]    bus,
    input  wire            bus_tog,
    input  wire            hb_tog,
    output reg  [W-1:0]    bus_q,
    output reg             hb_gone,
    output reg             hb_slow
);
    localparam integer TW  = $clog2(DST_HZ/1000*HB_TO_MS + 1);
    localparam [TW-1:0] LIM = DST_HZ/1000*HB_TO_MS;
    localparam [TW-1:0] FAST_ENOUGH = LIM - (DST_HZ/1000*SLOW_MS);  // 高于它=间隔还正常

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
            hb_slow <= 1'b0;
        end else begin
            if (hb_edge)     to_cnt <= LIM;
            else if (to_cnt) to_cnt <= to_cnt - 1'b1;

            if (hb_edge) begin
                // to_cnt 已经降过 FAST_ENOUGH ⇒ 距上一个边沿超过 SLOW_MS ⇒ 源时基被拉慢
                // ⇒ 链路已断（RXC 被 PHY 降到 ~2.5 MHz 的情形就落在这里）
                hb_slow <= (to_cnt < FAST_ENOUGH);
                hb_gone <= 1'b0;
            end else if (!to_cnt) begin
                hb_gone <= 1'b1;
            end
        end
    end

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) bus_q <= 0;
        else if (bus_edge) bus_q <= bus;
    end
endmodule
