`timescale 1ns/1ps
// gmii_rx_cdc — 把 RGMII 收回来的 GMII 字节流从恢复时钟搬到 MMCM 的 125 MHz 逻辑域。
//
// 为什么要有这一层：原来整个 ETH 栈（MAC/ARP/ICMP/UDP/重组/统计）全跑在 `gmii_rx_clk`
// （PHY 恢复出来的时钟）上，那一路没有 MMCM、抖动与时钟不确定性都大，布局也不好；
// 数据链一深，WNS 就全压在这条 125 MHz 的恢复钟上。现在只让 IDDR 和这个 FIFO 的写侧留在
// 恢复钟域，其余逻辑统一吃 clk_eth。
//
// 协议：写侧在 `dv` 为高的每一拍写 {dv,data}，并在 dv 落下的后一拍补一个 {0,0}
// （把"帧结束"这个空隙也送过去）。读侧 `rd_en = !empty` 连续取，输出打一拍。
// 不推空闲拍：否则两个 125 MHz 的 ppm 差会让 FIFO 在长时间空闲里单向涨/跌。
// 一帧最长 1522 字节，两个钟 ±150 ppm ⇒ 帧内漂移 < 0.01 字节，不会在帧中途假空。
module gmii_rx_cdc (
    input  wire       rx_clk,
    input  wire       rx_rst_n,
    input  wire       rx_dv,
    input  wire [7:0] rx_d,

    input  wire       clk,
    input  wire       rst_n,

    output reg        out_dv,
    output reg  [7:0] out_d
);
    // rx_rst_n 来自 sys_clk 域的复位桥（eth_rst_async）。原来把它直接当异步复位用，
    // report_cdc 把 `sys_clk→eth_rxc` 这 1 个端点判成 Critical（复位路径没有共同主钟）。
    // 现在只把它当**数据**送进本域 3 级 ASYNC_REG 链，得到同步释放的本地电平，再用它做
    // 同步复位。CDC 上它是"带 ASYNC_REG 的 1 bit 同步器"，不是异步复位端；复位仍在
    // rx_clk 域内连贯（FIFO 写指针和读侧复位都由本域电平驱动）。
    (* ASYNC_REG = "TRUE" *) reg [2:0] rst_rx_sync;
    always @(posedge rx_clk) begin
        rst_rx_sync <= {rst_rx_sync[1:0], rx_rst_n};
    end
    wire rst_rx_n = rst_rx_sync[2];

    reg dv_d;
    always @(posedge rx_clk) begin
        if (!rst_rx_n) dv_d <= 1'b0;
        else           dv_d <= rx_dv;
    end
    wire        push = rx_dv | dv_d;
    wire [8:0]  wdat = rx_dv ? {1'b1, rx_d} : 9'h000;

    wire [8:0]  q;
    wire        empty, full;

    // 预灌 8 条再开闸。原因不是"怕丢"，是**指针同步有 2~3 拍延迟**：读侧刚看见非空时
    // FIFO 里只有 1~2 条，若立刻连续读，读指针会追到同步后的写指针上、瞬时空一拍，
    // 在 gmii 流里就是一个假 dv=0（tb_gmii_rx_cdc 第一版 308 字节的帧被劈成 232+76）。
    // 预灌后帧内占用 ≈ 8 + 同步延迟 − ppm 漂移（1522B/±150ppm 只有 0.2 条）⇒ 不再触底。
    reg [3:0] pf;
    reg       stream;
    wire      rd_en = stream && !empty;
    reg       rd_v;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pf <= 4'd0; stream <= 1'b0;
        end else if (!stream) begin
            if (!empty) begin
                if (pf == 4'd8) stream <= 1'b1;
                else            pf <= pf + 1'b1;
            end else begin
                pf <= 4'd0;
            end
        end else if (rd_v && !q[8]) begin
            // 帧尾的空隙字出来了：等下一帧的预灌重新开闸。
            stream <= 1'b0;
            pf     <= 4'd0;
        end
    end

    dc_fifo #(.DATA_W(9), .ADDR_W(11)) u_fifo (
        .wr_clk(rx_clk), .wr_rst_n(rst_rx_n),
        .wr_en(push), .wr_data(wdat), .wr_full(full),
        .rd_clk(clk), .rd_rst_n(rst_n),
        .rd_en(rd_en), .rd_data(q), .rd_empty(empty)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_v <= 1'b0; out_dv <= 1'b0; out_d <= 8'd0;
        end else begin
            rd_v <= rd_en;
            if (rd_v) begin
                out_dv <= q[8];
                out_d  <= q[7:0];
            end else begin
                out_dv <= 1'b0;
            end
        end
    end
endmodule
