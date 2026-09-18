`timescale 1ns/1ps
// Ethernet/IPv4/UDP filter. Byte-index state machine (easier to verify).
// Emits UDP payload with sof/eof/good. Non-matching frames are dropped.
module udp_rx_parser #(
    parameter [15:0] UDP_PORT = 16'd5001
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  s_data,
    input  wire        s_valid,
    input  wire        s_sof,
    input  wire        s_eof,
    input  wire        s_good,
    input  wire        s_bad,
    output reg  [7:0]  p_data,
    output reg         p_valid,
    output reg         p_sof,
    output reg         p_eof,
    output reg         p_good,
    output reg  [15:0] pay_len,      // bytes emitted this UDP datagram
    output reg         stat_drop_bad,
    output reg         stat_drop_filt,
    output reg         stat_udp_ok
);
    // indices into frame (after MAC)
    // 0-13  eth (da,sa,type)
    // 14..  ipv4
    localparam integer ETH_HDR = 14;

    reg [15:0] bcnt;       // byte index in frame
    reg [15:0] udp_off;    // start of UDP header
    reg [15:0] udp_len;    // UDP length field
    reg [15:0] pay_cnt;
    reg        accept;
    reg        in_pay;

    wire [3:0] ihl_nib = s_data; // only valid when sampling byte14 — use stored
    reg  [3:0] ihl;
    reg  [7:0] b14, b20, b21, b23;
    reg [15:0] dport;
    reg [15:0] proto_chk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bcnt <= 16'd0;
            udp_off <= 16'd0;
            udp_len <= 16'd0;
            pay_cnt <= 16'd0;
            accept <= 1'b0;
            in_pay <= 1'b0;
            p_data <= 8'd0;
            p_valid <= 1'b0;
            p_sof <= 1'b0;
            p_eof <= 1'b0;
            p_good <= 1'b0;
            pay_len <= 16'd0;
            stat_drop_bad <= 1'b0;
            stat_drop_filt <= 1'b0;
            stat_udp_ok <= 1'b0;
            ihl <= 4'd0;
            b14 <= 8'd0;
            b20 <= 8'd0;
            b21 <= 8'd0;
            b23 <= 8'd0;
            dport <= 16'd0;
            proto_chk <= 16'd0;
        end else begin
            p_valid <= 1'b0;
            p_sof   <= 1'b0;
            p_eof   <= 1'b0;
            p_good  <= 1'b0;
            stat_udp_ok <= 1'b0;

            if (s_bad) begin
                stat_drop_bad <= 1'b1;
                bcnt <= 16'd0;
                in_pay <= 1'b0;
                accept <= 1'b0;
            end else if (s_valid) begin
                if (s_sof) begin
                    bcnt <= 16'd0;
                    in_pay <= 1'b0;
                    accept <= 1'b0;
                    pay_cnt <= 16'd0;
                end

                // sample header fields
                if (bcnt == 16'd12) proto_chk[15:8] <= s_data;
                if (bcnt == 16'd13) proto_chk[7:0]  <= s_data;
                if (bcnt == 16'd14) begin
                    b14 <= s_data;
                    ihl <= s_data[3:0];
                end
                if (bcnt == 16'd20) b20 <= s_data;
                if (bcnt == 16'd21) b21 <= s_data;
                if (bcnt == 16'd23) b23 <= s_data;

                // decide accept at UDP header start
                // udp_off = 14 + ihl*4
                // When bcnt == 14+ihl*4 (first UDP byte = src port hi)
                // We have ihl from byte14 collected when bcnt was 14;
                // so decision at bcnt == 14 + 4*ihl is safe (ihl known one cycle earlier).

                if (bcnt == (16'd14 + {10'd0, ihl, 2'b00})) begin
                    udp_off <= bcnt;
                    // verify IPv4/UDP/no-frag using stored fields
                    if (proto_chk == 16'h0800 && b14[7:4] == 4'h4 && b23 == 8'd17 &&
                        {b20, b21} == 16'h0000)
                        accept <= 1'b1;
                    else begin
                        accept <= 1'b0;
                        stat_drop_filt <= 1'b1;
                    end
                end

                // dest port at udp_off+2,+3 ; length at udp_off+4,+5
                if (accept && bcnt == udp_off + 16'd3) begin
                    // dport low byte this cycle; high was at +2
                    if ({dport[15:8], s_data} != UDP_PORT) begin
                        accept <= 1'b0;
                        stat_drop_filt <= 1'b1;
                    end
                end
                if (bcnt == udp_off + 16'd2 && accept) dport[15:8] <= s_data;
                if (bcnt == udp_off + 16'd4 && accept) udp_len[15:8] <= s_data;
                if (bcnt == udp_off + 16'd5 && accept) udp_len[7:0]  <= s_data;

                // payload starts at udp_off+8
                if (accept && bcnt == udp_off + 16'd7) begin
                    // next byte is payload
                end

                if (accept && bcnt >= udp_off + 16'd8) begin
                    p_data  <= s_data;
                    p_valid <= 1'b1;
                    if (bcnt == udp_off + 16'd8) p_sof <= 1'b1;
                    pay_cnt <= pay_cnt + 16'd1;
                    in_pay  <= 1'b1;
                end

                if (s_eof) begin
                    if (in_pay && accept) begin
                        p_eof    <= 1'b1;
                        p_good   <= s_good;
                        pay_len  <= pay_cnt;
                        if (s_good) stat_udp_ok <= 1'b1;
                    end
                    bcnt   <= 16'd0;
                    in_pay <= 1'b0;
                    accept <= 1'b0;
                    pay_cnt <= 16'd0;
                end else begin
                    bcnt <= bcnt + 16'd1;
                end
            end
        end
    end
endmodule
