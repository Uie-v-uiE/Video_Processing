`timescale 1ns/1ps
// tb_udp_telemetry — 真 udp_tx + crc32_d8 的字节级闭环（不是只读内部 pay[]）。
// 板上前一版就是"单测读 pay[] 绿、线上却整体右移一字节"：telemetry 里多插了一级 q，
// 而 udp_tx 只在 IP 头最后一个字节提前一拍拉 tx_req，数据下一拍就要上 GMII。
// 这里把 GMII 口上的字节按帧偏移抓下来逐字节比对：DA/SA/type/IP-dst/UDP 头/32B 载荷。
// 判据：两包都逐字节相等（tick 四个字节除外）、en=0 不起包、包与包之间靠 tx_done 退忙。
module tb_udp_telemetry;
    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk;

    localparam [47:0] DES_MAC   = 48'h00_aa_bb_cc_dd_ee;
    localparam [31:0] DES_IP    = 32'hc0a80164;   // 192.168.1.100
    localparam [47:0] BOARD_MAC = 48'h00_11_22_33_44_55;
    localparam [31:0] BOARD_IP  = 32'hc0a8010a;   // 192.168.1.10

    reg         en = 1'b1;
    reg  [31:0] s_frames = 32'h0000_1234;
    reg  [31:0] s_pkts   = 32'h0000_5678;
    reg  [31:0] s_bad    = 32'h0000_0009;
    reg  [15:0] rows     = 16'h0002;
    reg  [15:0] aborts   = 16'h0003;
    reg  [15:0] lat_ms   = 16'd1234;
    reg         lat_ok   = 1'b1;
    reg  [15:0] pane_bad = 16'd7;
    reg         pane_valid = 1'b1;
    reg         link     = 1'b1;

    wire        start_en, tx_req, tx_done;
    wire [15:0] tx_len;
    wire [7:0]  tx_data;
    wire [47:0] out_mac;
    wire [31:0] out_ip;
    wire        gmii_tx_en;
    wire [7:0]  gmii_txd;

    udp_telemetry #(.TICK_DIV(20)) u_tel (
        .clk(clk), .rst_n(rst_n), .en(en), .des_mac(DES_MAC), .des_ip(DES_IP),
        .stat_frames(s_frames), .stat_pkts(s_pkts), .stat_bad(s_bad), .rows_missed(rows),
        .aborts(aborts), .lat_ms(lat_ms), .lat_ok(lat_ok),
        .pane_bad(pane_bad), .pane_valid(pane_valid), .link_active(link),
        .start_en(start_en), .tx_byte_num(tx_len), .tx_data(tx_data),
        .tx_req(tx_req), .tx_done(tx_done), .out_des_mac(out_mac), .out_des_ip(out_ip)
    );

    wire [31:0] crc_data, crc_next;
    wire        crc_en, crc_clr;
    udp_tx #(.BOARD_MAC(BOARD_MAC), .BOARD_IP(BOARD_IP)) u_tx (
        .clk(clk), .rst_n(rst_n),
        .tx_start_en(start_en), .tx_data(tx_data), .tx_byte_num(tx_len),
        .des_mac(out_mac), .des_ip(out_ip),
        .crc_data(crc_data), .crc_next(crc_next[31:24]),
        .tx_done(tx_done), .tx_req(tx_req),
        .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd),
        .crc_en(crc_en), .crc_clr(crc_clr)
    );
    crc32_d8 u_crc (
        .clk(clk), .rst_n(rst_n), .data(gmii_txd),
        .crc_en(crc_en), .crc_clr(crc_clr), .crc_data(crc_data), .crc_next(crc_next)
    );

    // GMII 口抓帧：前导码 8 -> DA/SA/type 14 -> IP 20 -> UDP 8 -> 载荷 32 -> FCS 4
    reg [7:0] frame [0:127];
    integer   fidx = 0;
    integer   pkts = 0, starts = 0, errors = 0;
    reg [31:0] tick_seen [0:1];

    always @(posedge clk) begin
        if (start_en) begin
            starts = starts + 1;
            if (starts > 1) fidx = 0;   // 第二包覆盖同一抓取缓冲
        end
        if (gmii_tx_en) begin
            if (fidx < 128) frame[fidx] <= gmii_txd;
            fidx = fidx + 1;
        end
    end

    task check_pkt;
        input integer tag;
        integer k, e, j;
        reg [31:0] sum;
        reg [7:0] exp [0:31];
        begin
            e = 0;
            if (frame[0] !== 8'h55 || frame[6] !== 8'h55 || frame[7] !== 8'hd5)
                begin $display("FAIL T%0d preamble", tag); e = e + 1; end
            // DA = ARP 学到的 PC MAC；SA = 板卡 MAC
            if ({frame[8],frame[9],frame[10],frame[11],frame[12],frame[13]} !== DES_MAC)
                begin $display("FAIL T%0d DA %02x%02x%02x%02x%02x%02x", tag,
                    frame[8],frame[9],frame[10],frame[11],frame[12],frame[13]); e = e + 1; end
            if ({frame[14],frame[15],frame[16],frame[17],frame[18],frame[19]} !== BOARD_MAC)
                begin $display("FAIL T%0d SA", tag); e = e + 1; end
            if ({frame[20],frame[21]} !== 16'h0800)
                begin $display("FAIL T%0d ethertype", tag); e = e + 1; end
            if ({frame[38],frame[39],frame[40],frame[41]} !== DES_IP)
                begin $display("FAIL T%0d dst ip %02x.%02x.%02x.%02x", tag,
                    frame[38],frame[39],frame[40],frame[41]); e = e + 1; end
            if ({frame[42],frame[43]} !== 16'h04d2 || {frame[44],frame[45]} !== 16'h04d2)
                begin $display("FAIL T%0d udp port %02x%02x/%02x%02x", tag,
                    frame[42],frame[43],frame[44],frame[45]); e = e + 1; end
            if ({frame[46],frame[47]} !== 16'd40)
                begin $display("FAIL T%0d udp len %02x%02x", tag, frame[46],frame[47]); e = e + 1; end
            // IPv4 header checksum: sum the ten 16-bit words of frame[22..41]
            // (checksum field included) and fold; a valid header leaves 0xFFFF.
            sum = 32'd0;
            for (j = 0; j < 10; j = j + 1)
                sum = sum + {frame[22 + 2*j], frame[23 + 2*j]};
            sum = (sum & 32'h0000ffff) + (sum >> 16);
            sum = (sum & 32'h0000ffff) + (sum >> 16);
            if (sum[15:0] !== 16'hffff)
                begin $display("FAIL T%0d ip checksum sum=%04x", tag, sum[15:0]); e = e + 1; end

            exp[0]=8'h56; exp[1]=8'h44; exp[2]=8'h45; exp[3]=8'h4F;
            exp[4]=8'd1;  exp[5]={7'd0,link};
            exp[6]=s_frames[7:0]; exp[7]=s_frames[15:8]; exp[8]=s_frames[23:16]; exp[9]=s_frames[31:24];
            exp[10]=s_pkts[7:0]; exp[11]=s_pkts[15:8]; exp[12]=s_pkts[23:16]; exp[13]=s_pkts[31:24];
            exp[14]=s_bad[7:0]; exp[15]=s_bad[15:8]; exp[16]=s_bad[23:16]; exp[17]=s_bad[31:24];
            exp[18]=rows[7:0]; exp[19]=rows[15:8];
            for (k=20;k<24;k=k+1) exp[k]=frame[50+k];   // tick：活计数器，不比数值
            exp[24]=aborts[7:0]; exp[25]=aborts[15:8];
            exp[26]=lat_ms[7:0]; exp[27]=lat_ms[15:8];
            exp[28]=8'hD2; exp[29]=8'h04;                // sport 字段（小端 1234）
            exp[30]={6'd0,pane_valid,lat_ok}; exp[31]=pane_bad[7:0];
            for (k=0;k<32;k=k+1) begin
                if (frame[50+k] !== exp[k]) begin
                    $display("FAIL T%0d payload byte %0d got %02x exp %02x", tag, k, frame[50+k], exp[k]);
                    e = e + 1;
                end
            end
            tick_seen[tag-1] = {frame[70],frame[71],frame[72],frame[73]};
            if (e == 0) $display("PKT%0d ok frame_bytes=%0d magic=%02x%02x%02x%02x tick=%08x",
                                 tag, fidx, frame[50],frame[51],frame[52],frame[53], tick_seen[tag-1]);
            errors = errors + e;
        end
    endtask

    integer waited;
    initial begin
        repeat (5) @(posedge clk); rst_n = 1;
        en = 0; repeat (80) @(posedge clk);
        if (starts != 0) begin $display("FAIL start while en=0 (%0d)", starts); errors=errors+1; end
        en = 1;
        waited = 0;
        while (starts == 0 && waited < 200) begin @(posedge clk); waited = waited + 1; end
        waited = 0;
        while (pkts == 0 && waited < 400) begin
            @(posedge clk);
            if (tx_done) begin pkts = 1; check_pkt(1); end
            waited = waited + 1;
        end
        if (pkts == 0) begin $display("FAIL first packet timeout fidx=%0d", fidx); errors=errors+1; end

        waited = 0;
        while (starts < 2 && waited < 400) begin @(posedge clk); waited = waited + 1; end
        if (starts < 2) begin $display("FAIL second start missing"); errors=errors+1; end
        waited = 0;
        while (pkts == 1 && waited < 400) begin
            @(posedge clk);
            if (tx_done) begin pkts = 2; check_pkt(2); end
            waited = waited + 1;
        end
        if (pkts < 2) begin $display("FAIL second packet timeout fidx=%0d", fidx); errors=errors+1; end
        if (tick_seen[1] == tick_seen[0]) begin
            $display("FAIL tick did not advance between packets"); errors=errors+1; end

        if (errors == 0) $display("PASS tb_udp_telemetry starts=%0d pkts=%0d", starts, pkts);
        else             $display("FAIL tb_udp_telemetry errors=%0d", errors);
        $finish;
    end
    initial begin #200000; $display("FAIL tb_udp_telemetry timeout starts=%0d pkts=%0d fidx=%0d", starts, pkts, fidx); $finish; end
endmodule
