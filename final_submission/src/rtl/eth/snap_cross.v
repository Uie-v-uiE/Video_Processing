`timescale 1ns/1ps
// snap_cross — 「准静态总线 + 跳变沿捕获」跨域器（ddr_bank_commit 用同一套路子）。
// 源域把宽总线**整拍**写好、同拍翻转 bus_tog；本模块在目的域（像素域 dst_clk）等同步过来的
// 跳变沿再采一次。边沿要 3 级同步才到目的域，而源总线至少保持到下一次写入（本项目 ≥1 ms），
// 所以采到的一定是完整值，不会撕烈。
// hb_tog 是独立心跳。只测"心跳有没有停"不够：RTL821 断链时不停供 RXC 而是拉到约 1/48 ⇒ 心跳
// 一直在、hb_gone 永不触发。关键方向：**源时钟变慢 ⇒ 目的域量到的心跳间隔变长**（不是变短）。
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
    // 声明初值 = 复位分支想要的那个值（ISSUES #257 第 2 条 / #256 那一族的最后一颗）。
    //   为什么必须有：这颗寄存器在 `pl_demo_top` 那棵树下，顶层把 `sys_rst_n` 绑成常量 1'b1
    //   （system_top.v:250 那条死复位，`snap_cross.dst_rst_n` 是它传下来的），于是
    //   `if (!dst_rst_n)` 分支**永远走不到** ⇒ 上电值只由位流里的 INIT 承载，不写声明初值它
    //   就是 1'b0，而复位分支写的是 1'b1 ⇒ "心跳没来过"这件事在配置完成后的一拍会被误报。
    //   尺子：build/scan_dead_reset_init.py（改前 WANT1 root=pl_demo_top init_miss=1，
    //   件 build/evidence/r113_dead_reset_scan.txt；改后必须 init_miss=0）。
    // ⚠ 这里只声明"修法与尺子"，不改任何时序结论：`pl_demo_top` **不在当前位流里**（正式构建的是
    //   `system_top`），所以这一处对 r114 的名册与 WNS 是无感的，不能拿来当收益讲。
    output reg             hb_gone = 1'b1,
    output reg             hb_slow
);
    localparam integer TW  = $clog2(DST_HZ/1000*HB_TO_MS + 1);
    localparam [TW-1:0] LIM = DST_HZ/1000*HB_TO_MS;
    localparam [TW-1:0] FAST_ENOUGH = LIM - (DST_HZ/1000*SLOW_MS);  // 高于它=间隔还正常；SLOW_MS=5 把 1 ms 与 ~50 ms 分居两侧（余量 5×/10×）

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
                // to_cnt 已降过 FAST_ENOUGH ⇒ 距上一个边沿超过 SLOW_MS ⇒ 源时基被拉慢 ⇒ 链路已断；
                // to_cnt 归零而始终没边沿 = hb_gone（时钟消失）。两条分开，因为时钟退化≠时钟停。
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
