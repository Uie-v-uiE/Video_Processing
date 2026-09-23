`timescale 1ns/1ps
// tb_v795_rx_chain —— #38 第 2 步的**接顶层之前**的判据：
// 自研 `gmii_rx_mac`（V7.9.5 起自己算 FCS）+ 自研 `udp_rx_parser`（带目的端口过滤）这一对，
// 从 GMII 字节流一直验到 `p_data/p_sof/p_eof/p_good` 与三个统计脉冲。
//
// 为什么单独写这一台：仓库里 `tb_udp_parser.v` 的判据是**照着期望值手算的**，
// 而 `udp_rx_parser` 从来没有被任何顶层例化过（见 report/ISSUES.md #38 与学习文档 §0 的"三种绿色"）——
// 也就是说这个模块的真实行为一直没被人看过一眼。这一台就是要先看一眼。
//
// 帧由 TB 用独立实现的标准 CRC-32 造（口径同 tb_v795_rx_fcs 的 T0），所以"好帧/坏帧"是真好坏。
module tb_v795_rx_chain;
    localparam [15:0] PORT_VIDEO = 16'd5001;
    localparam [15:0] PORT_WRONG = 16'd5002;

    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk;                      // 125 MHz

    reg [7:0] rxd = 8'h00;
    reg       dv = 0, er = 0;

    wire [7:0] m_data;  wire m_valid, m_sof, m_eof, m_good, m_bad;
    gmii_rx_mac u_mac (
        .clk(clk), .rst_n(rst_n), .gmii_rxd(rxd), .gmii_rx_dv(dv), .gmii_rx_er(er),
        .m_data(m_data), .m_valid(m_valid), .m_sof(m_sof), .m_eof(m_eof),
        .m_good(m_good), .m_bad(m_bad));

    wire [7:0] p_data; wire p_valid, p_sof, p_eof, p_good;
    wire [15:0] pay_len;
    wire st_bad, st_filt, st_ok;
    udp_rx_parser #(.UDP_PORT(PORT_VIDEO)) u_par (
        .clk(clk), .rst_n(rst_n),
        .s_data(m_data), .s_valid(m_valid), .s_sof(m_sof), .s_eof(m_eof),
        .s_good(m_good), .s_bad(m_bad),
        .p_data(p_data), .p_valid(p_valid), .p_sof(p_sof), .p_eof(p_eof), .p_good(p_good),
        .pay_len(pay_len), .stat_drop_bad(st_bad), .stat_drop_filt(st_filt), .stat_udp_ok(st_ok));

    // ---- 独立实现的标准 CRC-32 ----
    function [31:0] crc32_step;
        input [7:0] b; input [31:0] seed;
        integer i; reg [31:0] c;
        begin
            c = seed ^ {24'd0, b};
            for (i = 0; i < 8; i = i + 1)
                if (c & 32'd1) c = (c >> 1) ^ 32'hEDB8_8320; else c = c >> 1;
            crc32_step = c;
        end
    endfunction

    // ---- 帧：preamble+SFD+ETH(14)+IPv4(20)+UDP(8)+PAYLOAD+FCS(4) ----
    localparam integer PAYN = 32;
    localparam integer HDRP = 7 + 1 + 14 + 20 + 8;          // 前导到载荷前
    localparam integer FLEN = HDRP + PAYN + 4;
    reg [7:0] fr [0:FLEN-1];
    reg [7:0] pay [0:PAYN-1];

    task build;
        input [15:0] dport;
        integer k; reg [31:0] c;
        begin
            for (k = 0; k < 7; k = k + 1) fr[k] = 8'h55;
            fr[7] = 8'hD5;
            // DA / SA / type
            fr[8]=8'h01; fr[9]=8'h23; fr[10]=8'h45; fr[11]=8'h67; fr[12]=8'h89; fr[13]=8'hab;
            fr[14]=8'hc0; fr[15]=8'ha8; fr[16]=8'h00; fr[17]=8'h01; fr[18]=8'h12; fr[19]=8'h34;
            fr[20]=8'h08; fr[21]=8'h00;
            // IPv4 头 = 帧内偏移 22..41（parser 眼里的 bcnt 14..33）
            fr[22]=8'h45; fr[23]=8'h00;
            fr[24]=8'h00; fr[25]=PAYN + 8 + 20;              // total len（赋给 8 位自然截断）
            fr[26]=8'h00; fr[27]=8'h00;                      // id
            fr[28]=8'h00; fr[29]=8'h00;                      // flags/frag = 0（parser 要求 b20,b21==0）
            fr[30]=8'h40; fr[31]=8'd17; fr[32]=8'h00; fr[33]=8'h00;  // ttl proto=17 csum(不校验)
            fr[34]=8'hc0; fr[35]=8'ha8; fr[36]=8'h00; fr[37]=8'h7b;  // src 192.168.0.123
            fr[38]=8'hc0; fr[39]=8'ha8; fr[40]=8'h00; fr[41]=8'h0a;  // dst 192.168.0.10
            // UDP 头 = 帧内偏移 42..49（parser 的 udp_off = 14 + ihl*4 = 34，即 bcnt 34..41）
            fr[42]=8'h04; fr[43]=8'hD2;                      // sport 1234
            fr[44]=dport[15:8]; fr[45]=dport[7:0];           // dport —— 端口过滤看的就是这两个字节
            fr[46]=8'h00; fr[47]=PAYN + 8; fr[48]=8'h00; fr[49]=8'h00;  // len, csum(发 0，合法)
            c = 32'hFFFF_FFFF;
            for (k = 8; k < HDRP + PAYN; k = k + 1) begin    // CRC 从 DA[0]（下标 8）起
                if (k >= HDRP) begin
                    pay[k - HDRP] = 8'hA0 + (k - HDRP);
                    fr[k] = pay[k - HDRP];
                end
                c = crc32_step(fr[k], c);
            end
            c = c ^ 32'hFFFF_FFFF;
            fr[HDRP+PAYN+0]=c[7:0]; fr[HDRP+PAYN+1]=c[15:8];
            fr[HDRP+PAYN+2]=c[23:16]; fr[HDRP+PAYN+3]=c[31:24];
        end
    endtask

    integer pl_cnt, pl_bad, pl_sof, pl_eof, pl_good, sb, sf, so, mge, mbe, k;
    reg [7:0] got [0:PAYN-1];
    always @(posedge clk) begin
        if (p_valid) begin
            if (pl_cnt < PAYN) got[pl_cnt] = p_data;
            pl_cnt = pl_cnt + 1;
        end
        if (p_sof) pl_sof = pl_sof + 1;
        if (p_eof) begin pl_eof = pl_eof + 1; if (p_good) pl_good = pl_good + 1; end
        if (st_bad)  sb = sb + 1;
        if (st_filt) sf = sf + 1;
        if (st_ok)   so = so + 1;
        if (m_good)  mge = mge + 1;
        if (m_bad)   mbe = mbe + 1;
    end

    task send;
        input integer len; input integer flip;
        integer j;
        begin
            for (j = 0; j < len; j = j + 1) begin
                @(negedge clk);
                rxd = fr[j];
                if (j == flip) rxd = rxd ^ 8'h01;
                dv = 1'b1;
            end
            @(negedge clk); dv = 1'b0;
            repeat (8) @(posedge clk);
        end
    endtask

    task clr; begin pl_cnt=0; pl_sof=0; pl_eof=0; pl_good=0; sb=0; sf=0; so=0; mge=0; mbe=0; end endtask

    integer errors = 0;
    task chk(input [255:0] n, input integer g, input integer e);
        begin if (g !== e) begin $display("FAIL %0s got=%0d expect=%0d", n, g, e); errors = errors + 1; end end
    endtask

    initial begin
        rst_n = 0; repeat (3) @(posedge clk); #1 rst_n = 1; repeat (3) @(posedge clk); #1;

        // C1：好帧、端口对 ⇒ PAYN 个字节、逐字节等于发出去的内容、p_good=1、udp_ok=1
        clr(); build(PORT_VIDEO); send(FLEN, -1);
        chk("C1 mac 判好", mge, 1);
        chk("C1 载荷字节数", pl_cnt, PAYN);
        chk("C1 sof 次数", pl_sof, 1);
        chk("C1 eof 次数", pl_eof, 1);
        chk("C1 eof 带 good", pl_good, 1);
        chk("C1 udp_ok", so, 1);
        chk("C1 不误报丢弃", sb + sf, 0);
        for (k = 0; k < PAYN; k = k + 1)
            if (got[k] !== 8'hA0 + k[7:0]) begin
                $display("FAIL C1 第 %0d 字节 = %h，应为 %h", k, got[k], 8'hA0 + k[7:0]);
                errors = errors + 1; k = PAYN;
            end
        $display("INFO C1 pay_len=%0d", pay_len);

        // C2：载荷翻一 bit（FCS 不再匹配）。**约定要说清楚**：字节是流式转发的，
        // FCS 的判定要到帧尾才知道，所以坏帧的字节仍会流出去 —— 关键是
        // p_eof 会带着 p_good=0 闭合这一包，frame_reasm 于是 stat_bad++ / frame_err=1，
        // 整帧不提交（屏上保持上一好帧）。"坏帧不吐字节"这种契约在这里做不到，也不该假装做到。
        clr(); build(PORT_VIDEO); send(FLEN, HDRP + 5);
        chk("C2 mac 判坏", mbe, 1);
        chk("C2 字节仍流式转发", pl_cnt, PAYN);
        chk("C2 但包被闭合", pl_eof, 1);
        chk("C2 闭合时 p_good=0", pl_good, 0);
        chk("C2 drop_bad 计数", sb, 1);
        chk("C2 udp_ok 不该响", so, 0);

        // C3：FCS 正确但目的端口不对 ⇒ 过滤掉（这就是 P0-C 最后那条债的判据）
        clr(); build(PORT_WRONG); send(FLEN, -1);
        chk("C3 mac 判好（帧本身没坏）", mge, 1);
        chk("C3 不吐载荷", pl_cnt, 0);
        chk("C3 drop_filt 计数", sf, 1);
        chk("C3 不该算 udp_ok", so, 0);

        // C4：帧在载荷中段就结束了（不够 64 字节 ⇒ MAC 判坏；同时 udp_len 声明的字节没发完）。
        // 判据："吐过字节就必须给 p_eof"，否则下游那一包永远不闭合。
        clr(); build(PORT_VIDEO); send(HDRP + 10, -1);
        chk("C4 短帧判坏", mbe, 1);
        chk("C4 drop_bad", sb, 1);
        chk("C4 已到达的 10 字节转发", pl_cnt, 10);
        chk("C4 仍然闭合", pl_eof, 1);
        chk("C4 闭合判坏", pl_good, 0);

        // C5：两帧连发（第一帧好、第二帧坏），计数器必须各记各的
        clr(); build(PORT_VIDEO); send(FLEN, -1);
        build(PORT_VIDEO); send(FLEN, 30);
        chk("C5 两帧各 32 字节（第一帧）", pl_cnt, 2*PAYN);
        chk("C5 第二帧进 drop_bad", sb, 1);
        chk("C5 第一帧进 udp_ok", so, 1);
        chk("C5 两包都闭合", pl_eof, 2);

        $display("INFO C5 got[0]=%h got[1]=%h（第二帧的头两字节，必须是 A0/A1 而不是重复第一帧）",
                 got[0], got[1]);

        if (errors == 0) $display("PASS tb_v795_rx_chain");
        else             $display("FAIL tb_v795_rx_chain errors=%0d", errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL watchdog");
        $finish;
    end
endmodule
