// tb_icmp_len_wrap —— ISSUES #206 的尺子：`icmp_rx` 的"载荷长度 = IP 总长 − 28"没有下界。
//
// 危险形状（逐行见 src/rtl/eth/icmp_rx.v:188/245/261 与状态跳转 :101）：
//   一个 IP 总长 < 28 的畸形包让 16 位减法绕成 ~65516 ⇒ `st_rx_data` 那两个"数到长度减一/减二"
//   的比较永远追不上，而离开 st_rx_data 只有 skip_en / error_en 两条路，st_rx_data 里没人置 error_en
//   ⇒ 解析器留在原地**继续吃后面的包**（算出来的量级：65535 字节 = 524 µs 的 dv 时间）。
//
// 三条判据的形状是特意配对的：R3 先演"合法包本身没问题"（改前改后都必须绿，红了就是我激励的错），
// R1 演"畸形包过去之后解析器必须已经回Idle"，R2 演"紧跟其后的合法 ping 必须仍然被正常应答"。
// ⚠ 激励必须是真栅格：前导码 7×55 + D5、帧里带 4 个 FCS 字节、然后**真的拉低 dv 一段**（帧间隙），
//   否则"畸形包已经被吃完"这件事根本没被演到（#206 上一版候选就是因为没有间隙而空转）。
`timescale 1ns/1ps
// 功能：被测模块 `icmp_rx`（BOARD_MAC=00:11:22:33:44:55、BOARD_IP=192.168.1.10）；覆盖点＝IP 总长 <28 的
//        畸形包让"载荷长度 = 总长 − 28"下溢回绕后，解析器会不会楔在 st_rx_data 里把紧跟的合法包吃掉。
// 激励与检查：时钟 #4 翻转（8 ns，GMII 125 MHz），所有激励打在 negedge；rst_n 低 4 个沿后拉高再等 4 个沿；
//        每帧按真栅格发：7 个 8'h55 前导 + 8'hD5 + 6 字节 DA + 6 字节 SA(8'h01) + 类型 08 00 + 20 字节
//        IP 头 + ICMP 头 8 字节（type 8 / code 0 / checksum 0000 / id / seq）+ ndata 个数据字节
//        （i+8'h10）+ 4 个 8'hAA 当 FCS，然后 dv 拉低 40 个沿留帧间隙；
//        R3 先发合法包（ndata=8、id=16'h1234、seq=16'h0001，IP 总长 = 28+8）要求 done_total==1、
//        rec_byte_num==16'd8 且 dut.icmp_data_length==16'd8；R1 发畸形包（bogus=1 ⇒ IP 总长写 16'd20、
//        ndata=0）并要求间隙结束时 (dut.cur_state == S_RX_DATA) 为假（st_after_gap==0）；R1b 用跨这两帧开着的
//        计数器数 rec_en 拍数，要求 en_bytes==8（>8 说明畸形帧把下一整帧当自己的载荷吐了）；
//        R2 要求紧跟的合法 ping（id=16'h4321、seq=16'h0003）仍被应答：done_total==2 且 icmp_id==16'h4321
//        且 icmp_seq==16'h0003。
// 预期结果：通过时打印 `PASS R3 legit frame completes | ...`、`PASS R1 wrapped length must not park the
//        parser | ...`、`PASS R1b only the legit frame emits payload | ...`、
//        `PASS R2 next legit frame still answered | ...`，并带 `R3 raw:`/`R1 raw(after bogus frame gap):`
//        两行原始量（cur_state、en_bytes、done_total、icmp_data_length、icmp_rx_cnt），末行
//        `RESULT tb_icmp_len_wrap PASS`；失败时对应条目改打 `FAIL <名字> | <说明>` 并把 nfail 加一
//        （R1 红 = 仍停在 S_RX_DATA=7'b010_0000；R1b 红 = en_bytes>8；R2 红 = done_total/icmp_id/icmp_seq
//        对不上），末行 `RESULT tb_icmp_len_wrap FAIL nfail=<n>`。
module tb_icmp_len_wrap;

    // 与 src/rtl/eth/icmp_rx.v:31-37 一致的编码（这里抄一份是为了不依赖层次化取 localparam）
    localparam [6:0] S_IDLE     = 7'b000_0001;
    localparam [6:0] S_RX_DATA  = 7'b010_0000;
    localparam [6:0] S_RX_END   = 7'b100_0000;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        gmii_rx_dv = 1'b0;
    reg  [7:0] gmii_rxd = 8'h00;
    always #4 clk = ~clk;              // 125 MHz GMII

    wire        rec_pkt_done, rec_en;
    wire  [7:0] rec_data;
    wire [15:0] rec_byte_num;
    wire [15:0] icmp_id, icmp_seq;
    wire [31:0] reply_checksum;

    icmp_rx #(.BOARD_MAC(48'h00_11_22_33_44_55), .BOARD_IP({8'd192,8'd168,8'd1,8'd10})) dut (
        .clk(clk), .rst_n(rst_n),
        .gmii_rx_dv(gmii_rx_dv), .gmii_rxd(gmii_rxd),
        .rec_pkt_done(rec_pkt_done), .rec_en(rec_en), .rec_data(rec_data),
        .rec_byte_num(rec_byte_num),
        .icmp_id(icmp_id), .icmp_seq(icmp_seq), .reply_checksum(reply_checksum)
    );

    integer nfail = 0;
    task line(input [8*140:1] name, input ok, input [8*140:1] detail);
        begin
            if (ok) $display("PASS %0s | %0s", name, detail);
            else begin nfail = nfail + 1; $display("FAIL %0s | %0s", name, detail); end
        end
    endtask

    // ---- 帧发射器：唯一写入者都在 negedge（一根线不许有两个写入者）----
    task send_frame2(input integer ndata, input [15:0] idv, input [15:0] seqv, input integer bogus);
        integer i; reg [15:0] tlen; reg [7:0] da[0:5]; reg [7:0] ip[0:19];
        begin
            da[0]=8'h00; da[1]=8'h11; da[2]=8'h22; da[3]=8'h33; da[4]=8'h44; da[5]=8'h55;
            tlen = bogus ? 16'd20 : (16'd28 + ndata[15:0]);
            ip[0]=8'h45; ip[1]=8'h00; ip[2]=tlen[15:8]; ip[3]=tlen[7:0];
            ip[4]=8'h00; ip[5]=8'h01; ip[6]=8'h00; ip[7]=8'h00;
            ip[8]=8'h40; ip[9]=8'h01; ip[10]=8'h77; ip[11]=8'h88;
            ip[12]=8'hC0; ip[13]=8'hA8; ip[14]=8'h01; ip[15]=8'h65;   // src 192.168.1.101
            ip[16]=8'hC0; ip[17]=8'hA8; ip[18]=8'h01; ip[19]=8'h0A;   // dst 192.168.1.10 = BOARD_IP
            @(negedge clk);
            for (i = 0; i < 7; i = i + 1) begin gmii_rx_dv = 1'b1; gmii_rxd = 8'h55; @(negedge clk); end
            gmii_rxd = 8'hD5; @(negedge clk);
            for (i = 0; i < 6; i = i + 1) begin gmii_rxd = da[i]; @(negedge clk); end
            for (i = 0; i < 6; i = i + 1) begin gmii_rxd = 8'h01; @(negedge clk); end   // SA
            gmii_rxd = 8'h08; @(negedge clk); gmii_rxd = 8'h00; @(negedge clk);        // eth_type
            for (i = 0; i < 20; i = i + 1) begin gmii_rxd = ip[i]; @(negedge clk); end
            gmii_rxd = 8'h08; @(negedge clk);   // ICMP type = echo request
            gmii_rxd = 8'h00; @(negedge clk);   // code
            gmii_rxd = 8'h00; @(negedge clk);   // checksum hi
            gmii_rxd = 8'h00; @(negedge clk);
            gmii_rxd = idv[15:8]; @(negedge clk); gmii_rxd = idv[7:0]; @(negedge clk);
            gmii_rxd = seqv[15:8]; @(negedge clk); gmii_rxd = seqv[7:0]; @(negedge clk);
            for (i = 0; i < ndata; i = i + 1) begin gmii_rxd = i[7:0] + 8'h10; @(negedge clk); end
            for (i = 0; i < 4; i = i + 1) begin gmii_rxd = 8'hAA; @(negedge clk); end
            gmii_rx_dv = 1'b0; gmii_rxd = 8'h00;
            for (i = 0; i < 40; i = i + 1) @(negedge clk);
        end
    endtask

    // 唯一的事件计数器：`rec_pkt_done` 是一拍脉冲，自由跑一个 always 数它，
    // 比在每个 fork 里各起一个 forever 少两处状态泄漏（本仓为"上一场景的状态漏进下一场景"付过学费）
    integer done_total = 0;
    always @(posedge rec_pkt_done) done_total = done_total + 1;

    integer st_after_gap, en_bytes;
    initial begin : main
        st_after_gap = 0; en_bytes = 0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (4) @(negedge clk);

        // ---- R3 控制：合法包（载荷 8 字节）本身必须被正常收完 ----
        send_frame2(8, 16'h1234, 16'h0001, 0);
        $display("R3 raw: done_total=%0d rec_byte_num=%0d icmp_data_length=%0d icmp_id=%h icmp_seq=%h",
                 done_total, rec_byte_num, dut.icmp_data_length, icmp_id, icmp_seq);
        line("R3 legit frame completes", (done_total == 1) && (rec_byte_num == 16'd8) && (dut.icmp_data_length == 16'd8),
             "a well-formed echo request (payload 8) must give exactly one rec_pkt_done with 8 bytes; if this is red the STIMULUS is wrong, not the DUT");

        // ---- R1 畸形包（IP 总长 20）之后，间隙结束时必须已经离开 st_rx_data ----
        // en_bytes 这个计数器**跨两帧开着**（畸形帧 + 紧跟的合法帧）：R1b 要判的是"畸形帧让解析器
        // 停在 st_rx_data 里，于是下一整帧的字节都被当成本帧载荷吐出去"。只在畸形帧窗口里数字节的话，
        // 它改前改后都是 0 —— 一条永远不会红的判据（rule 4：零样本分支是空转）。
        fork : f2
            begin
                forever @(posedge clk) if (rec_en) en_bytes = en_bytes + 1;   // 计数分支必须有控制事件：`forever if(...)` 是零延迟死循环（我自己第一版就卡在这）
            end
            begin
                send_frame2(0, 16'h1234, 16'h0002, 1);
                st_after_gap = (dut.cur_state == S_RX_DATA);
        $display("R1 raw(after bogus frame gap): cur_state=%b parked_in_rx_data=%0d en_bytes_so_far=%0d done_total=%0d icmp_data_length=%0d icmp_rx_cnt=%0d",
                 dut.cur_state, st_after_gap, en_bytes, done_total, dut.icmp_data_length, dut.icmp_rx_cnt);
                send_frame2(8, 16'h4321, 16'h0003, 0);
                disable f2;
            end
        join
        line("R1 wrapped length must not park the parser", (st_after_gap == 0),
             "after a bogus IP total_length=20 the 16-bit minus wraps to ~65516; leaving st_rx_data needs skip_en/error_en and st_rx_data never sets error_en");
        line("R1b only the legit frame emits payload", (en_bytes == 8),
             "counted rec_en cycles across the bogus frame AND the following legit one: 8 means only the real payload shipped, >8 means the parked parser ate the next frame");

        // ---- R2 紧跟其后的合法 ping 必须仍然被应答（畸形包不许把下一包吃掉）----
        line("R2 next legit frame still answered", (done_total == 2) && (icmp_id == 16'h4321) && (icmp_seq == 16'h0003),
             "the wrapped parser keeps consuming the FOLLOWING frame; a legit ping behind it must still finish with its own id/seq");

        if (nfail == 0) $display("RESULT tb_icmp_len_wrap PASS");
        else           $display("RESULT tb_icmp_len_wrap FAIL nfail=%0d", nfail);
        $finish;
    end
endmodule
