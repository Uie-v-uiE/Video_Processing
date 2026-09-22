`timescale 1ns/1ps
// ku5p_tx_arb —— KU5P 入口的 GMII 发送仲裁（自研，替代厂商 eth_ctrl 里那半段 mux）。
//
// 为什么要换掉厂商的 mux（这条必须写下来，它是读代码读出来的，不是猜的）：
// 厂商 `src/rtl/eth/eth_ctrl.v` 的协议切换是
//     if (udp_tx_start_en)            protocol_sw <= 2'b01;
//     else if (icmp_tx_start_en)      protocol_sw <= 2'b10;
//     else if (arp_rx_flag && (udp_tx_busy==0 || icmp_tx_busy==0)) protocol_sw <= 2'b00;
// 那个 `||` 意味着：**只要 ARP 和 ICMP 里有一个是空闲的，收到 ARP 请求就把 mux 抢走**，
// 而另一个正在发的帧还没结束 ⇒ 帧中间换源，后面那半截变成对方的字节。
// 今天主线只在"ping 回包"和"ARP 应答"之间来回，撞上的窗口很窄所以没暴露；
// 一旦加了每秒一次的遥测包，发送占空比从 ~0 变成常态，这条迟早会咬人。
//
// 这里的规则只有一条，而且是可台架的形式：**拿到介质的那帧发完之前，谁都不许换。**
// 请求用脉冲进来、内部存成 pending 电平，空闲时按 ARP > ICMP > UDP 的优先级发出 grant，
// 并只接受**属于当前 owner 的** done（这一句就是上面那个 `||` 的解药）。
module ku5p_tx_arb (
    input  wire        clk,
    input  wire        rst_n,

    // 请求（单拍脉冲，会被存进 pending，不会被丢掉）
    input  wire        arp_rqs,     // 收到 ARP 请求
    input  wire        icmp_rqs,    // 收到 ICMP echo
    input  wire        udp_rqs,     // 遥测想发

    // grant（单拍）——直接接到各协议的 start/tx_en 端口
    output reg         arp_grant,
    output reg         icmp_grant,
    output reg         udp_grant,

    // 各协议自己报告的"我这帧发完了"
    input  wire        arp_done,
    input  wire        icmp_done,
    input  wire        udp_done,

    // 三路基带输入
    input  wire        arp_tx_en,
    input  wire [7:0]  arp_txd,
    input  wire        icmp_tx_en,
    input  wire [7:0]  icmp_txd,
    input  wire        udp_tx_en,
    input  wire [7:0]  udp_txd,

    // 到 RGMII 桥
    output reg         gmii_tx_en,
    output reg  [7:0]  gmii_txd
);
    localparam [1:0] OWN_ARP  = 2'b00,
                     OWN_UDP  = 2'b01,
                     OWN_ICMP = 2'b10;

    reg        busy;
    reg [1:0]  owner;
    reg        p_arp, p_icmp, p_udp;

    wire idle = ~busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {p_arp, p_icmp, p_udp} <= 3'd0;
        end else begin
            if (arp_rqs)  p_arp  <= 1'b1;
            if (icmp_rqs) p_icmp <= 1'b1;
            if (udp_rqs)  p_udp  <= 1'b1;
            if (arp_grant)  p_arp  <= 1'b0;
            if (icmp_grant) p_icmp <= 1'b0;
            if (udp_grant)  p_udp  <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0; owner <= OWN_ARP;
            arp_grant <= 1'b0; icmp_grant <= 1'b0; udp_grant <= 1'b0;
        end else begin
            arp_grant <= 1'b0; icmp_grant <= 1'b0; udp_grant <= 1'b0;
            if (idle) begin
                if (p_arp)       begin arp_grant  <= 1'b1; owner <= OWN_ARP;  busy <= 1'b1; end
                else if (p_icmp) begin icmp_grant <= 1'b1; owner <= OWN_ICMP; busy <= 1'b1; end
                else if (p_udp)  begin udp_grant  <= 1'b1; owner <= OWN_UDP;  busy <= 1'b1; end
            end else begin
                // 只认 owner 的 done：别的协议在同一拍报 done 不能把介质抢走
                case (owner)
                    OWN_ARP:  if (arp_done)  busy <= 1'b0;
                    OWN_ICMP: if (icmp_done) busy <= 1'b0;
                    OWN_UDP:  if (udp_done)  busy <= 1'b0;
                    default:  busy <= 1'b0;
                endcase
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gmii_tx_en <= 1'b0; gmii_txd <= 8'd0;
        end else begin
            case (owner)
                OWN_ARP:  begin gmii_tx_en <= arp_tx_en;   gmii_txd <= arp_txd;   end
                OWN_ICMP: begin gmii_tx_en <= icmp_tx_en;  gmii_txd <= icmp_txd;  end
                OWN_UDP:  begin gmii_tx_en <= udp_tx_en;   gmii_txd <= udp_txd;   end
                default:  begin gmii_tx_en <= 1'b0;        gmii_txd <= 8'd0;      end
            endcase
        end
    end
endmodule
