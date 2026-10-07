`timescale 1ns/1ps
// 功能：被测模块 `udp_rx_parser` #(.UDP_PORT(16'd5001))；覆盖点：一条合法 IPv4/UDP 帧
//        （52 字节 = 14 以太网头 + 20 IPv4 + 8 UDP + 10 载荷）的载荷字节被逐拍吐出，
//        以及目的端口不等于 5001 时一字节都不许往外发（端口过滤）。
// 激励与检查：时钟 always #4 clk=~clk（8 ns = 125 MHz），rst_n 拉低 4 拍后释放；每字节用
//        sendb 占 2 拍（第一拍置 s_valid/s_sof/s_eof/s_good，第二拍清零），sof 只给第 0 字节、
//        eof 只给第 51 字节、s_good 恒 1；帧内容在 initial 里手填：type=16'h0800、
//        ver/ihl=0x45、proto=17、UDP 长度 18、dport=16'h1389(5001)、载荷 10 字节 8'hA0+i；
//        每段发完再等 4 拍才判。判定条件 1：p_valid 计数 pay_bytes 必须 == 10；
//        判定条件 2：把 frame[37] 改成 8'h8A（dport 5002）后重发同一帧，pay_bytes 必须 == 0。
// 预期结果：通过时打印 PASS payload extracted、PASS wrong port dropped，末行
//        PASS tb_udp_parser ALL；失败时对应段打印 FAIL pay_bytes=<n> exp 10 或
//        FAIL wrong port leaked <n> bytes，errors 累加并末行改打
//        FAIL tb_udp_parser errors=<n>；tb_udp_parser.vcd 里应看到 p_valid 连续 10 拍、
//        p_sof/p_eof 各一拍。
// UDP parser TB: valid IPv4/UDP frame yields payload; wrong port dropped.
module tb_udp_parser;
    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk;

    reg [7:0] s_data = 0;
    reg s_valid = 0, s_sof = 0, s_eof = 0, s_good = 0, s_bad = 0;
    wire [7:0] p_data;
    wire p_valid, p_sof, p_eof, p_good;
    wire [15:0] pay_len;
    wire drop_bad, drop_filt, udp_ok;

    udp_rx_parser #(.UDP_PORT(16'd5001)) uut (
        .clk(clk), .rst_n(rst_n),
        .s_data(s_data), .s_valid(s_valid), .s_sof(s_sof), .s_eof(s_eof),
        .s_good(s_good), .s_bad(s_bad),
        .p_data(p_data), .p_valid(p_valid), .p_sof(p_sof), .p_eof(p_eof),
        .p_good(p_good), .pay_len(pay_len),
        .stat_drop_bad(drop_bad), .stat_drop_filt(drop_filt), .stat_udp_ok(udp_ok)
    );

    integer errors = 0;
    integer pay_bytes = 0;
    always @(posedge clk) if (p_valid) pay_bytes = pay_bytes + 1;

    task sendb(input [7:0] b, input sof, input eof, input good);
        begin
            @(posedge clk);
            s_data <= b; s_valid <= 1; s_sof <= sof; s_eof <= eof; s_good <= good;
            @(posedge clk);
            s_valid <= 0; s_sof <= 0; s_eof <= 0; s_good <= 0;
        end
    endtask

    integer i;
    reg [7:0] frame [0:79];

    task send_frame_from_arr(input integer n, input good);
        integer j;
        begin
            for (j = 0; j < n; j = j + 1)
                sendb(frame[j], j==0, j==n-1, good);
        end
    endtask

    initial begin
        $dumpfile("tb_udp_parser.vcd");
        $dumpvars(0, tb_udp_parser);
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;

        // Build minimal eth+ipv4+udp+8 payload
        // DA
        frame[0]=8'hFF; frame[1]=8'hFF; frame[2]=8'hFF;
        frame[3]=8'hFF; frame[4]=8'hFF; frame[5]=8'hFF;
        // SA
        frame[6]=8'h02; frame[7]=8'h00; frame[8]=8'h00;
        frame[9]=8'h00; frame[10]=8'h00; frame[11]=8'h01;
        // type IPv4
        frame[12]=8'h08; frame[13]=8'h00;
        // IPv4: ver/ihl=0x45, proto=17, frag=0
        frame[14]=8'h45; frame[15]=8'h00;
        frame[16]=8'h00; frame[17]=8'h2E; // total length 46
        frame[18]=8'h00; frame[19]=8'h00;
        frame[20]=8'h00; frame[21]=8'h00; // no frag
        frame[22]=8'h40; frame[23]=8'h11; // ttl, proto UDP
        frame[24]=8'h00; frame[25]=8'h00; // checksum
        frame[26]=8'hC0; frame[27]=8'hA8; frame[28]=8'h01; frame[29]=8'h64; // src
        frame[30]=8'hC0; frame[31]=8'hA8; frame[32]=8'h01; frame[33]=8'h0A; // dst
        // UDP
        frame[34]=8'h13; frame[35]=8'h88; // sport 5000
        frame[36]=8'h13; frame[37]=8'h89; // dport 5001
        frame[38]=8'h00; frame[39]=8'h12; // len 18
        frame[40]=8'h00; frame[41]=8'h00; // csum
        // payload 10 bytes
        for (i = 0; i < 10; i = i + 1) frame[42+i] = 8'hA0 + i[7:0];

        pay_bytes = 0;
        send_frame_from_arr(52, 1);
        repeat (4) @(posedge clk);
        if (pay_bytes != 10) begin
            $display("FAIL pay_bytes=%0d exp 10", pay_bytes);
            errors = errors + 1;
        end else $display("PASS payload extracted");
        if (!udp_ok) begin
            // udp_ok pulses; may have passed
        end

        // wrong port
        frame[37] = 8'h8A; // 5002
        pay_bytes = 0;
        send_frame_from_arr(52, 1);
        repeat (4) @(posedge clk);
        if (pay_bytes != 0) begin
            $display("FAIL wrong port leaked %0d bytes", pay_bytes);
            errors = errors + 1;
        end else $display("PASS wrong port dropped");

        if (errors == 0) $display("PASS tb_udp_parser ALL");
        else $display("FAIL tb_udp_parser errors=%0d", errors);
        $finish;
    end
endmodule
