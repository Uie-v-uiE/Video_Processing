`timescale 1ns/1ps
// ku5p_telem 台架：把"这包遥测 PC 到底收不收"做成可判据的形式。
//
// 链路 = ku5p_telem + ku5p_tx_arb + 真 udp（含厂商 crc32_d8），输出是 GMII 字节流；
// TB 自己把以太网帧拆出来核对，并**用与网卡相同的办法验 CRC**：
//   把"目的MAC…载荷 + 4 字节 FCS"整段喂进标准 CRC-32（反射、初值 FFFFFFFF、末异或 FFFFFFFF），
//   余数必须是常数 0x2144DF1C —— 这就是接收方"这帧没坏"的判据，不需要猜厂商的字节序。
//   先自校：同一函数对 "123456789" 必须给出 0xCBF43926；常数 0x2144DF1C 本身由
//   **另一份独立实现（node 里跑的同一算法）**算出，不是从被测对象回抄的。
//
// 八条判据：
//   C1 peer_known=0 时一个字节都不发（ARP 没学到对端 ⇒ 发往随机 MAC 是有害的）
//   C2 头部字段逐字节正确（dstMAC/srcMAC/ethertype/TTL/proto/源目IP/端口/UDP长度/IP总长）
//   C3 载荷 42 字节的线上格式与文档一致（含大端；v0x02 起的 6 个命令字段也在这一条里逐字节钉）
//   C4 **快照原子性**：发送途中继续改计数器，包里必须是发起前的值
//   C5 FCS 让整帧 CRC 余数 = 0x2144DF1C
//   C6 周期：两帧起点相差 TICK_CYC（±仲裁的几拍），且第二包的计数确实前进了
//   C7 命令改周期：period_s=3 ⇒ 间隔变成约 3 个 tick（证明周期不是摆设）
//   C8 CLR 只推基线（包里是差值，不是绝对值，也不是 0）+ SNAP 立刻出一包（不用等下一个 tick）
//      ⇒ 这两条合起来就是"PC 能命令这块板，而且回执看得见"
module tb_ku5p_telem;
    localparam [47:0] BOARD_MAC = 48'h00_11_22_33_44_66;
    localparam [31:0] BOARD_IP  = {8'd192, 8'd168, 8'd1, 8'd11};
    localparam [47:0] PC_MAC    = 48'h0A_BB_CC_DD_EE_01;
    localparam [31:0] PC_IP     = {8'd192, 8'd168, 8'd1, 8'd100};
    localparam [31:0] TICK      = 32'd400;

    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk;                 // 125 MHz GMII

    // ---- 被打包的观测值，TB 随时可改（C4 就靠这个）----
    reg [31:0] x_frames = 0, x_pkts = 0, x_bytes = 0, x_bad = 0, x_oob = 0;
    reg [15:0] x_rows = 0;
    reg link_up = 0, frames_seen = 0, abort_seen = 0, data_alive = 0, peer_known = 0;
    // ---- 命令通道（ku5p_cmd）那一侧的输入，本台架直接驱动 ----
    reg [7:0]  x_period = 8'd1;
    reg        x_clr = 0, x_snap = 0, x_seen = 0;
    reg [15:0] x_cok = 0, x_cbad = 0;

    wire        tlm_rqs;
    wire        udp_grant, udp_done, udp_tx_req;
    wire        udp_gmii_tx_en;
    wire [7:0]  udp_gmii_txd, tlm_data;
    wire [15:0] tlm_len;
    wire        gmii_tx_en;
    wire [7:0]  gmii_txd;

    ku5p_telem #(.IMG_W(16'd512), .IMG_H(16'd300), .TICK_CYC(TICK), .VERSION(8'h07)) u_tlm (
        .clk(clk), .rst_n(rst_n),
        .stat_frames(x_frames), .stat_pkts(x_pkts), .stat_bytes(x_bytes),
        .stat_bad(x_bad), .stat_oob(x_oob), .rows_missed(x_rows),
        .link_up(link_up), .frames_seen(frames_seen), .abort_seen(abort_seen),
        .data_alive(data_alive), .peer_known(peer_known),
        .period_s(x_period), .cmd_clr(x_clr), .cmd_snap(x_snap),
        .cmds_ok(x_cok), .cmds_bad(x_cbad), .cmd_seen(x_seen),
        .udp_rqs(tlm_rqs),
        .tx_start_en(udp_grant), .tx_req(udp_tx_req),
        .tx_data(tlm_data), .tx_byte_num(tlm_len)
    );

    ku5p_tx_arb u_arb (
        .clk(clk), .rst_n(rst_n),
        .arp_rqs(1'b0), .icmp_rqs(1'b0), .udp_rqs(tlm_rqs),
        .arp_grant(), .icmp_grant(), .udp_grant(udp_grant),
        .arp_done(1'b0), .icmp_done(1'b0), .udp_done(udp_done),
        .arp_tx_en(1'b0), .arp_txd(8'd0),
        .icmp_tx_en(1'b0), .icmp_txd(8'd0),
        .udp_tx_en(udp_gmii_tx_en), .udp_txd(udp_gmii_txd),
        .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd)
    );

    udp #(.BOARD_MAC(BOARD_MAC), .BOARD_IP(BOARD_IP)) u_udp (
        .rst_n(rst_n),
        .gmii_rx_clk(clk), .gmii_rx_dv(1'b0), .gmii_rxd(8'd0),
        .gmii_tx_clk(clk), .gmii_tx_en(udp_gmii_tx_en), .gmii_txd(udp_gmii_txd),
        .rec_pkt_done(), .rec_en(), .rec_data(), .rec_byte_num(),
        .tx_start_en(udp_grant), .tx_data(tlm_data), .tx_byte_num(tlm_len),
        .des_mac(PC_MAC), .des_ip(PC_IP),
        .tx_done(udp_done), .tx_req(udp_tx_req)
    );

    // ---- GMII 抓包 ----
    reg [7:0] cap [0:1023];
    integer   cap_n = 0, nframe = 0;
    integer   fstart[0:7], flen[0:7], ftime[0:7];
    reg       tx_en_d = 0;
    always @(posedge clk) begin : capture
        reg en_now, en_was;
        en_now = gmii_tx_en;
        en_was = tx_en_d;
        tx_en_d <= gmii_tx_en;
        if (en_now && !en_was && nframe < 8) begin
            fstart[nframe] = cap_n;
            ftime[nframe]  = $time;      // **时间**才是周期的度量；fstart 是字节下标，
        end                              // 用它算 tick 间距会得到"90"这种假数字
        if (en_now && cap_n < 1024) begin
            cap[cap_n] = gmii_txd;
            cap_n = cap_n + 1;
        end
        if (!en_now && en_was && nframe < 8) begin
            flen[nframe] = cap_n - fstart[nframe];
            nframe = nframe + 1;
        end
    end

    // ---- TB 自己的标准 CRC-32（反射式），先自校再当判据用 ----
    function [31:0] crc32_step;
        input [7:0]  b;
        input [31:0] seed;
        integer i;
        reg [31:0] c;
        begin
            c = seed ^ {24'd0, b};
            for (i = 0; i < 8; i = i + 1)
                if (c & 32'd1) c = (c >> 1) ^ 32'hEDB8_8320;
                else           c =  c >> 1;
            crc32_step = c;
        end
    endfunction

    task crc_over;                       // [lo,hi] 闭区间算标准 CRC（含末异或）
        input  integer lo, hi;
        output [31:0]  res;
        integer j; reg [31:0] c;
        begin
            c = 32'hFFFF_FFFF;
            for (j = lo; j <= hi; j = j + 1) c = crc32_step(cap[j], c);
            res = c ^ 32'hFFFF_FFFF;
        end
    endtask

    integer errors = 0;
    task chk32;
        input [95:0] name;
        input [31:0] got, exp;
        begin
            if (got !== exp) begin
                $display("FAIL %0s got=%h expect=%h", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask
    task chki;
        input [95:0] name;
        input integer got, exp;
        begin
            if (got !== exp) begin
                $display("FAIL %0s got=%0d expect=%0d", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    function integer find_magic;         // 帧内 'KU5P' 的偏移
        input integer base, len;
        integer j;
        begin
            find_magic = -1;
            for (j = 0; j <= len-4; j = j + 1)
                if (cap[base+j] === 8'h4B && cap[base+j+1] === 8'h55 &&
                    cap[base+j+2] === 8'h35 && cap[base+j+3] === 8'h50) find_magic = j;
        end
    endfunction

    integer i0;
    reg [31:0] e_frames, e_pkts, e_bytes, e_bad, e_oob, e_secs;
    reg [15:0] e_rows, e_cok, e_cbad;
    reg [7:0]  e_flags, e_flags2, e_period;

    task check_frame;
        input integer fi;
        integer base, p, q;
        reg [31:0] crc_res;
        begin
            base = fstart[fi];
            p    = find_magic(base, flen[fi]);
            if (p < 42) begin
                $display("FAIL frame %0d: KU5P 魔数缺失或偏移异常 (p=%0d len=%0d)", fi, p, flen[fi]);
                $write("     dump: ");
                for (q = 0; q < flen[fi]; q = q + 1) $write("%02h ", cap[base+q]);
                $display("");
                errors = errors + 1;
                disable check_frame;
            end
            i0 = base + p;                       // 载荷绝对下标
            if ({cap[i0-42], cap[i0-41], cap[i0-40], cap[i0-39], cap[i0-38], cap[i0-37]} !== PC_MAC) begin
                $display("FAIL dst MAC got=%h expect=%h",
                         {cap[i0-42], cap[i0-41], cap[i0-40], cap[i0-39], cap[i0-38], cap[i0-37]}, PC_MAC);
                errors = errors + 1;
            end
            if ({cap[i0-36], cap[i0-35], cap[i0-34], cap[i0-33], cap[i0-32], cap[i0-31]} !== BOARD_MAC) begin
                $display("FAIL src MAC got=%h expect=%h",
                         {cap[i0-36], cap[i0-35], cap[i0-34], cap[i0-33], cap[i0-32], cap[i0-31]}, BOARD_MAC);
                errors = errors + 1;
            end
            chk32("ethertype",   {8'd0, cap[i0-30], cap[i0-29]}, 32'h0800);
            chk32("ip ver/ihl",  {24'd0, cap[i0-28]}, 32'h45);
            chk32("ip tos",      {24'd0, cap[i0-27]}, 32'h00);
            chk32("ip total len",{16'd0, cap[i0-26], cap[i0-25]}, 32'd70);  // 20+8+42
            chk32("ip ttl",      {24'd0, cap[i0-20]}, 32'h40);
            chk32("ip proto",    {24'd0, cap[i0-19]}, 32'd17);
            begin : ip_csum                       // 一补数和：合法 IP 头（含自身校验和）应等于 FFFF
                integer m; reg [31:0] sum;
                sum = 32'd0;
                for (m = 0; m < 20; m = m + 2)
                    sum = sum + {cap[i0-28+m], cap[i0-27+m]};
                while (sum >> 16) sum = (sum & 32'h0000_FFFF) + (sum >> 16);
                chk32("ip hdr 1s-complement sum", sum & 32'hFFFF, 32'hFFFF);
            end
            chk32("ip src", {cap[i0-16], cap[i0-15], cap[i0-14], cap[i0-13]}, BOARD_IP);
            chk32("ip dst", {cap[i0-12], cap[i0-11], cap[i0-10], cap[i0-9]},  PC_IP);
            chk32("udp ports", {cap[i0-8], cap[i0-7], cap[i0-6], cap[i0-5]}, 32'h04D2_04D2);
            chk32("udp len",   {16'd0, cap[i0-4], cap[i0-3]}, 32'd50);       // 8+42
            chk32("magic",  {cap[i0], cap[i0+1], cap[i0+2], cap[i0+3]}, 32'h4B55_3550);
            chk32("version",   {24'd0, cap[i0+4]}, 32'h07);
            chk32("flags",     {24'd0, cap[i0+5]}, {24'd0, e_flags});
            chk32("img size",  {cap[i0+6], cap[i0+7], cap[i0+8], cap[i0+9]}, 32'h0200_012C);
            chk32("frames",  {cap[i0+10], cap[i0+11], cap[i0+12], cap[i0+13]}, e_frames);
            chk32("pkts",    {cap[i0+14], cap[i0+15], cap[i0+16], cap[i0+17]}, e_pkts);
            chk32("bytes",   {cap[i0+18], cap[i0+19], cap[i0+20], cap[i0+21]}, e_bytes);
            chk32("bad",     {cap[i0+22], cap[i0+23], cap[i0+24], cap[i0+25]}, e_bad);
            chk32("oob",     {cap[i0+26], cap[i0+27], cap[i0+28], cap[i0+29]}, e_oob);
            chk32("rows",    {16'd0, cap[i0+30], cap[i0+31]}, {16'd0, e_rows});
            chk32("uptime",  {cap[i0+32], cap[i0+33], cap[i0+34], cap[i0+35]}, e_secs);
            // ---- v0x02 的 6 个命令字段（逐字节钉，PC 解析器按同一张表读）----
            chk32("cmds_ok",   {16'd0, cap[i0+36], cap[i0+37]}, {16'd0, e_cok});
            chk32("cmds_bad",  {16'd0, cap[i0+38], cap[i0+39]}, {16'd0, e_cbad});
            chk32("period",    {24'd0, cap[i0+40]}, {24'd0, e_period});
            chk32("flags2",    {24'd0, cap[i0+41]}, {24'd0, e_flags2});
            crc_over(i0-42, i0+45, crc_res);
            // 常数 0x2144DF1C = "init FFFFFFFF + 末异或 FFFFFFFF 的 CRC-32 跑完 帧+FCS" 的余数，
            // 与帧内容无关 ⇒ 只要 FCS 是自算的、且字节序/异或约定与标准一致就会命中。
            // 这个数是**用另一份独立实现（node）算出来的**，不是从被验对象那里抄回来的。
            chk32("crc residue = PC 收帧判据", crc_res, 32'h2144_DF1C);
            chki("frame length", flen[fi], (i0 + 46) - base);   // 42 载荷 + 4 FCS
        end
    endtask

    integer t0, t1, sp, t2, sp2, nf, tn0;
    // 全局看门狗：跑不到断言就等于失败，不能让 xsim 永远等下去
    // （C7 要等 3 个 tick、C8 还要再看一帧 ⇒ 60 µs 不够，扩到 120 µs ≈ 15000 拍）
    initial begin : watchdog
        #120_000;
        $display("FAIL watchdog: 120us 内没跑到结尾（发了 %0d 帧、%0d 字节）", nframe, cap_n);
        errors = errors + 1;
        $display("FAIL tb_ku5p_telem");
        $finish;
    end

    initial begin : main
        begin : selftest
            reg [7:0] bb;
            reg [31:0] c;
            c = 32'hFFFF_FFFF;
            for (bb = 8'h31; bb <= 8'h39; bb = bb + 8'd1) c = crc32_step(bb, c);  // "123456789"
            c = c ^ 32'hFFFF_FFFF;
            chk32("TB CRC self-test", c, 32'hCBF4_3926);
        end

        rst_n = 0; repeat (4) @(posedge clk); rst_n = 1;
        x_frames = 100; x_pkts = 4200; x_bytes = 32'h00FA_0000;
        x_bad = 3; x_oob = 7; x_rows = 12;
        link_up = 1; frames_seen = 1; abort_seen = 1; data_alive = 1;
        peer_known = 0;

        // ---- C1：没学到对端 ⇒ 2.5 个 tick 之内一个字节都不发 ----
        repeat (TICK*2 + TICK/2) @(posedge clk);
        chki("C1 bytes before ARP", cap_n, 0);
        chki("C1 frames before ARP", nframe, 0);

        // ---- 第一帧：ARP 学到了对端 ----
        e_frames = x_frames; e_pkts = x_pkts; e_bytes = x_bytes;
        e_bad = x_bad;       e_oob = x_oob;    e_rows = x_rows;
        e_secs = 3;        // 心跳计数每个 tick 都涨（与 peer 无关）：C1 那 2.5 个 tick 已经涨到 2，
                           // 第一个真正发包的时刻落在第 3 个 tick 上
        e_flags = {4'd0, data_alive, abort_seen, frames_seen, link_up};
        e_cok = 0; e_cbad = 0; e_period = 1; e_flags2 = 8'h00;   // 还没下过任何命令
        peer_known = 1;
        wait (gmii_tx_en === 1'b1);
        // C4：帧已经开始发了才把计数器改大 —— 包里必须还是上面钉住的值
        x_frames = 9999; x_pkts = 9999; x_bytes = 32'hFFFF_FFFF;
        x_bad = 9999; x_oob = 9999; x_rows = 9999;
        wait (nframe >= 1);
        check_frame(0);
        t0 = ftime[0];

        // ---- 第二帧：计数真的前进了吗（C6）----
        e_frames = 1234; e_pkts = 5678; e_bytes = 32'h1234_5678;
        e_bad = 0; e_oob = 0; e_rows = 1; e_secs = 4;   // 下一个 tick
        e_flags = {4'd0, 1'b1, 1'b0, 1'b1, 1'b1};
        x_frames = 1234; x_pkts = 5678; x_bytes = 32'h1234_5678;
        x_bad = 0; x_oob = 0; x_rows = 1; abort_seen = 0;
        wait (nframe >= 2);
        check_frame(1);
        t1 = ftime[1];
        sp = (t1 - t0) / 8;                      // 8 ns = 一个 GMII 周期
        if (sp < TICK - 8 || sp > TICK + 16) begin
            $display("FAIL C6 tick spacing=%0d cycles expect around %0d", sp, TICK);
            errors = errors + 1;
        end else $display("INFO two frames %0d cycles apart (TICK=%0d)", sp, TICK);

        // ---- C7：命令把上报周期改成 3 tick ⇒ 间隔必须跟着变（证明 period 不是摆设）----
        x_period = 8'd3;
        e_secs = 7;                      // 第 4 拍发过之后数满 3 秒才再发
        e_period = 8'd3;                 // 包里的 [40] 必须回显**当前**周期（PC 靠它确认命令生效）
        wait (nframe >= 3);
        check_frame(2);
        t2  = ftime[2];
        sp2 = (t2 - t1) / 8;
        if (sp2 < 3*TICK - 8 || sp2 > 3*TICK + 16) begin
            errors = errors + 1;
            $display("FAIL C7 spacing after SPD3 = %0d cycles, expect ~%0d", sp2, 3*TICK);
        end else $display("PASS C7 period_s=3 -> %0d cycles apart (3*%0d)", sp2, TICK);
        // 反面对照：如果 period 根本没参与判断，这里就会是 ~1 个 tick —— 上面的区间挡得住它。
        if (sp2 < TICK + 8) begin
            errors = errors + 1;
            $display("FAIL C7b spacing still looks like a 1 s period (%0d)", sp2);
        end

        // ---- C8：CLR 只推基线（包里是差值）+ SNAP 不等 tick 立刻出一包 ----
        x_frames = 32'd2000; x_pkts = 32'd8000; x_bytes = 32'd500000;
        x_bad    = 32'd11;   x_oob  = 32'd22;    x_rows = 16'd5;
        @(posedge clk); x_clr = 1'b1;
        @(posedge clk); x_clr = 1'b0;
        x_frames = 32'd2100; x_pkts = 32'd8250; x_bytes = 32'd530700;
        x_bad    = 32'd13;   x_oob  = 32'd25;    x_rows = 16'd7;
        x_seen = 1'b1; x_cok = 16'd3; x_cbad = 16'd1;
        e_frames = 32'd100; e_pkts = 32'd250; e_bytes = 32'd30700;
        e_bad = 32'd2; e_oob = 32'd3; e_rows = 16'd7;
        e_secs = 7;                              // 就在上一包的同一秒内
        e_cok = 16'd3; e_cbad = 16'd1; e_period = 8'd3;
        e_flags2 = {6'd0, 1'b1, 1'b1};           // bit1=基线已推过，bit0=执行过命令
        nf  = nframe;
        tn0 = $time;
        @(posedge clk); x_snap = 1'b1;
        @(posedge clk); x_snap = 1'b0;
        wait (nframe > nf);
        check_frame(nf);
        // SNAP 的判据是"这包是命令换来的，不是等来的"：从脉冲到这一包的起点必须远小于一个 tick
        // （仲裁放行要几拍，给 100 拍的余量；而 period_s 现在是 3 tick = 1200 拍）。
        if ((ftime[nf] - tn0) / 8 > 100) begin
            errors = errors + 1;
            $display("FAIL C8b SNAP acked %0d cycles after the pulse - that looks like a tick wait",
                     (ftime[nf] - tn0) / 8);
        end else $display("PASS C8b SNAP acked %0d cycles after the pulse (period is %0d)",
                         (ftime[nf] - tn0) / 8, 3*TICK);
        $display("PASS C8 CLR reported deltas (%0d/%0d), not absolute counters", e_frames, e_pkts);

        repeat (20) @(posedge clk);
        if (errors == 0) $display("PASS tb_ku5p_telem");
        else             $display("FAIL tb_ku5p_telem errors=%0d", errors);
        $finish;
    end
endmodule
