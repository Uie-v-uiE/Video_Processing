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
    reg        eof_pend;     // 载荷已发完、等帧尾的真/假判定再发 p_eof
    reg [15:0] pay_len_q;    // 那一包的字节数（判定到达时要用）

    wire [3:0] ihl_nib = s_data; // only valid when sampling byte14 — use stored
    reg  [3:0] ihl;
    reg  [7:0] b14, b20, b21, b23;
    reg [15:0] dport;
    reg [15:0] proto_chk;

    // 本拍的字节是不是这一包的最后一个载荷字节（按 udp_len 口径，不含 FCS 与填充）。
    // 需要它是因为厂商风格的 s_eof 与最后一个字节同拍，那一拍 eof_pend 还来不及置上。
    // 声明必须放在上面这几个 reg **之后** —— xvlog 不允许标识符先用后声明（第一次就踩在这）。
    wire last_pay_now = accept && s_valid && (bcnt >= (udp_off + 16'd8)) &&
                        (bcnt == (udp_off + udp_len - 16'd1));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bcnt <= 16'd0;
            udp_off <= 16'd0;
            udp_len <= 16'd0;
            pay_cnt <= 16'd0;
            accept <= 1'b0;
            in_pay <= 1'b0;
            eof_pend <= 1'b0;
            pay_len_q <= 16'd0;
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
            // V7.9.5（#38 第 2 步）：这两个统计位**原来只有复位时的 0，运行中没有默认值** ——
            // 于是它们不是脉冲，而是"这辈子见过一次坏帧就永远为 1"的粘连电平。
            // 接顶层时如果拿它们去 ++ 计数，第一帧坏包之后计数就会每拍加一，数字完全不可信。
            // （`stat_udp_ok` 当时是每拍清 0 的，三条同类信号两种口径 —— 台架一跑就露出来了。）
            stat_drop_bad  <= 1'b0;
            stat_drop_filt <= 1'b0;

            if (s_bad) begin
                stat_drop_bad <= 1'b1;
                // 坏帧也要把包**闭合**（p_good=0）：下游的 pkt_active 一直挂着的话，
                // 下一包的字节会接到这一包后面 —— 那比丢一帧更坏。
                // 注意条件里有 `in_pay`：载荷只发了一半就被 ER/FCS 判死的帧也要闭合，
                // 判据是"只要往外吐过字节，就必须给一个 p_eof"。
                if (eof_pend || in_pay) begin
                    p_eof    <= 1'b1;
                    p_good   <= 1'b0;
                    pay_len  <= eof_pend ? pay_len_q : pay_cnt;
                    eof_pend <= 1'b0;
                end
                bcnt <= 16'd0;
                in_pay <= 1'b0;
                accept <= 1'b0;
            end else begin
            if (s_valid) begin
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

                // V7.9.6 修：`ihl` 是在 bcnt==14 这一拍**才被存进去**的，同拍读到的还是复位值 0，
                // 于是 `bcnt == 14 + ihl*4` 在 bcnt==14 也成立 ⇒ 每个帧都会在这一拍提前做一次判定，
                // 而那时 b23(proto) 还没采到，判定必然失败 ⇒ **每帧都误发一次 stat_drop_filt**。
                // （载荷后来在真正的 bcnt==34 又被正确接受，所以这个假信号只污染统计、不影响画面 ——
                //  恰好是那种"功能看起来对、数字全是假的"的 bug。判据：tb_v795_rx_chain 的 C1"不误报丢弃"。）
                if ((ihl != 4'd0) && bcnt == (16'd14 + {10'd0, ihl, 2'b00})) begin
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

                // V7.9.5（#38 第 2 步）：**载荷按 UDP 长度字段收尾**，不能一路发到帧尾 ——
                // 原来的写法 `bcnt >= udp_off+8` 会把帧尾那 4 个 FCS 字节也当载荷吐出去
                // （32 字节的载荷吐出 36 个），接上 frame_reasm 就是每包多 4 字节的确定性错位。
                if (accept && (bcnt >= udp_off + 16'd8) &&
                    (bcnt < (udp_off + udp_len))) begin
                    p_data  <= s_data;
                    p_valid <= 1'b1;
                    if (bcnt == udp_off + 16'd8) p_sof <= 1'b1;
                    pay_cnt <= pay_cnt + 16'd1;
                    in_pay  <= 1'b1;
                    // 最后一个载荷字节：先**记账**，不当场发 p_eof —— 因为 FCS 的判定要等帧结束
                    // 那一拍（m_good/m_bad 与 m_eof 同拍）才知道。早发就得猜，猜错就是
                    // "把坏包当好包提交"，那是最坏的一种错。
                    if (bcnt == (udp_off + udp_len - 16'd1)) begin
                        eof_pend  <= 1'b1;
                        pay_len_q <= pay_cnt + 16'd1;
                    end
                end

                bcnt <= bcnt + 16'd1;      // 推进到下一个字节（s_eof 那一拍在顶层分支处理）
            end

            // ---- 帧尾收尾：放在字节处理**之后**，这样同一拍里收尾的清零压过 bcnt/pay_cnt 的推进 ----
            // 两种 s_eof 时序都必须认，否则换个例化方式就少一个字节：
            //   ① 厂商风格：s_eof 与**最后一个字节同拍**（那一拍 s_valid=1）—— `tb_udp_parser` 就是这么驱的；
            //   ② 本仓库 V7.9.5 的 gmii_rx_mac：最后一个字节上一拍已随 m_valid 出去，
            //      m_eof 与 m_good/m_bad 同拍、那一拍 m_valid=0。
            // 第一版只认 ②，`tb_udp_parser` 立刻报 `pay_bytes=9 exp 10` ——
            // 这是"改了契约就得把所有既有例化一起想清楚"的现场版（判据：那条 FAIL 本身就是回归）。
            if (s_eof) begin
                if (eof_pend || last_pay_now) begin
                    p_eof   <= 1'b1;
                    p_good  <= s_good;
                    pay_len <= eof_pend ? pay_len_q : (pay_cnt + 16'd1);
                    if (s_good) stat_udp_ok <= 1'b1;
                end else if (in_pay && accept) begin
                    // 帧到了尾、但 udp_len 声明的字节还没发完 ⇒ 畸形包：闭合，但判坏
                    p_eof   <= 1'b1;
                    p_good  <= 1'b0;
                    pay_len <= pay_cnt;
                end
                bcnt     <= 16'd0;
                in_pay   <= 1'b0;
                accept   <= 1'b0;
                pay_cnt  <= 16'd0;
                eof_pend <= 1'b0;
            end
            end
        end
    end
endmodule
