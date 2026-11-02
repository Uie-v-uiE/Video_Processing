`timescale 1ns/1ps
// udp_telemetry — PL 侧网络遥测信标：每秒向最后一个 ARP 请求方（PC）发一包 32 字节 UDP 状态，
// 目的/源端口都是 1234（udp_tx 当前的固定头）。不经过 PS，也不需要新的时钟域：
// 统计量、ARP 捕获的 des_mac/des_ip、udp_tx 全在 ETH 逻辑时钟域。
//
// 为什么做：屏/串口/JTAG 已经能看到状态，但"网线这一路"目前只有收。把状态从同一个网口送回，
// 项目才是一个可远程观测/落地的视频处理节点，而不是只能接串口演示的板子。
//
// 载荷（小端；32 B）：
//   0..3  "VDEO"  4 ver=1  5 flags(bit0=link_active)
//   6..9  stat_frames  10..13 stat_pkts  14..17 stat_bad
//   18..19 rows_missed（**只在上一次作废时更新**）  24..25 累计作废帧数
//   20..23 秒计数   26..27 帧时延 ms（与屏上 LATENCY 同源）
//   28..29 UDP_SPORT   30 flags（bit0=时延有效, bit1=处理窗计数有效）  31 处理侧非灰像素数（饱和 255）
module udp_telemetry #(
    parameter integer TICK_DIV = 125_000_000,  // 1 s @ 125 MHz（TB 可覆盖）
    parameter [15:0]  UDP_SPORT = 16'd1234
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,             // 有 ARP 目标（|src_mac）才发
    input  wire [47:0] des_mac,
    input  wire [31:0] des_ip,
    input  wire [31:0] stat_frames,
    input  wire [31:0] stat_pkts,
    input  wire [31:0] stat_bad,
    input  wire [15:0] rows_missed,
    input  wire [15:0] aborts,
    input  wire [15:0] lat_ms,
    input  wire        lat_ok,
    input  wire [15:0] pane_bad,
    input  wire        pane_valid,
    input  wire        link_active,

    output reg         start_en,
    output reg  [15:0] tx_byte_num,
    output reg  [7:0]  tx_data,
    input  wire        tx_req,
    input  wire        tx_done,
    output reg  [47:0] out_des_mac,
    output reg  [31:0] out_des_ip
);
    reg [26:0] tick_cnt;
    reg [31:0] sec_cnt;
    reg [7:0]  pay [0:31];
    reg [5:0]  idx;
    reg        busy;

    wire tick = (tick_cnt == TICK_DIV - 1);
    wire take = en && tick && !busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin tick_cnt <= 27'd0; sec_cnt <= 32'd0; end
        else if (tick) begin tick_cnt <= 27'd0; sec_cnt <= sec_cnt + 1'b1; end
        else tick_cnt <= tick_cnt + 1'b1;
    end

    // 载荷在 tick 前就绪（统计量是慢变量）；tick 那一拍只是把寄存器拍下来。
    always @(posedge clk) begin
        if (take) begin
            pay[0]<=8'h56; pay[1]<=8'h44; pay[2]<=8'h45; pay[3]<=8'h4F;
            pay[4]<=8'd1;  pay[5]<={7'd0, link_active};
            pay[6]<=stat_frames[7:0];   pay[7]<=stat_frames[15:8];
            pay[8]<=stat_frames[23:16]; pay[9]<=stat_frames[31:24];
            pay[10]<=stat_pkts[7:0];   pay[11]<=stat_pkts[15:8];
            pay[12]<=stat_pkts[23:16]; pay[13]<=stat_pkts[31:24];
            pay[14]<=stat_bad[7:0];    pay[15]<=stat_bad[15:8];
            pay[16]<=stat_bad[23:16];  pay[17]<=stat_bad[31:24];
            pay[18]<=rows_missed[7:0]; pay[19]<=rows_missed[15:8];
            pay[20]<=sec_cnt[7:0];     pay[21]<=sec_cnt[15:8];
            pay[22]<=sec_cnt[23:16];   pay[23]<=sec_cnt[31:24];
            pay[24]<=aborts[7:0];     pay[25]<=aborts[15:8];
            pay[26]<=lat_ms[7:0];      pay[27]<=lat_ms[15:8];
            pay[28]<=UDP_SPORT[7:0]; pay[29]<=UDP_SPORT[15:8];
            pay[30]<={6'd0, pane_valid, lat_ok};
            pay[31]<=(pane_bad > 16'd255) ? 8'd255 : pane_bad[7:0];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_en<=0; tx_byte_num<=16'd32; tx_data<=8'd0;
            out_des_mac<=0; out_des_ip<=0; idx<=0; busy<=0;
        end else begin
            start_en <= 1'b0;
            if (take) begin
                out_des_mac <= des_mac;
                out_des_ip  <= des_ip;
                idx <= 6'd0;
                start_en <= 1'b1;
                busy <= 1'b1;
            end
            // udp_tx 在 IP 头最后一个字节就拉起 tx_req（预取一拍），第一个数据字节
            // 下一拍上 GMII ⇒ 这里只能寄存**一级**：req 当拍选 pay[idx]，下一拍即 tx_data。
            // 多插一级（曾经是 q + tx_data 两级）会把整包右移一字节、首字节变成 0。
            if (tx_req && busy) begin
                tx_data <= pay[idx];
                if (idx != 6'd31) idx <= idx + 1'b1;
            end
            if (tx_done) busy <= 1'b0;
        end
    end
endmodule
