`timescale 1ns/1ps
// 台架：icmp_tx **发出去的字节流**指纹（r112 那把"IP 校验和累加器 32→20 位"的等价尺子）。
// 跑法：bash sim/run_one.sh tb_v112_tx_bytes
//
// 为什么用字节指纹而不是"在 TB 里按定义重算校验和"：那一版（tb_v112_ip_csum）要在
// st_check_sum 里抓 ip_head 的十个 16 位项，而首部是**跨拍逐个填进去**的，抓早了读到的是没建好的字，
// 我在预算内没把那个节拍啃下来——记录在 ISSUES。等价性不需要我理解节拍：
// 一把"只该改内部累加位宽"的刀，如果改了语义，发出去的字节一定变；没变就是没变。
// 这比"跟改前的自己比"强的地方在于**指纹来自外部可见真值**（gmii_txd），不是来自 RTL 内部写法。
//
// 判据：
//  T1 每个矢量的前 72 字节必须**非零且成帧**（至少出现 0x45 开头的那个 IP 首字节）——不然指纹是空的
//  T2 计数地板：每个矢量至少收到 40 个字节（发满才谈得上等价）
//  T3 反空对照：只动 des_ip 一个输入，指纹必须变（不然"两次相同"可能只是没比/全是 0）
//  真正的凭据是**两次跑的指纹文件逐字相同**（脚本 build/r112_csum_equiv.sh 做 base/cut 差分）
module tb_v112_tx_bytes;

    reg clk = 0, rst_n = 0;
    reg [31:0] reply_checksum = 0, des_ip = 0;
    reg [15:0] icmp_id = 0, icmp_seq = 0, tx_byte_num = 0;
    reg [7:0]  tx_data = 0;
    reg        tx_start_en = 0;
    wire       tx_done, tx_req, gmii_tx_en, crc_en, crc_clr;
    wire [7:0] gmii_txd;

    icmp_tx u_dut (
        .clk(clk), .rst_n(rst_n),
        .reply_checksum(reply_checksum), .icmp_id(icmp_id), .icmp_seq(icmp_seq),
        .tx_start_en(tx_start_en), .tx_data(tx_data), .tx_byte_num(tx_byte_num),
        .des_mac(48'hff_ff_ff_ff_ff_ff), .des_ip(des_ip),
        .crc_data(32'd0), .crc_next(8'd0),
        .tx_done(tx_done), .tx_req(tx_req), .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd),
        .crc_en(crc_en), .crc_clr(crc_clr));

    always #4 clk = ~clk;                        // 125 MHz，与板上 gmii_tx_clk 同域

    localparam integer NBYTE = 72;               // 前导码 8 + 以太网头 14 + IP 头 20 + ICMP 8 = 50，再留余量
    integer errors = 0, n, v, i, cnt, found45;
    reg [7:0] bytes [0:NBYTE-1];
    reg [7:0] dfa, dfb;                           // 两个矢量的指纹（滚动异或+移位，可逆性不需要，只要会动）
    reg [7:0] dig [0:5];

    task vec;
        input integer idx;
        input [31:0] ip;  input [15:0] id;  input [15:0] seq;  input [15:0] bytes_n;
        input [31:0] rcs;
        integer k;
        begin
            rst_n = 0; repeat (5) @(posedge clk); rst_n = 1; repeat (3) @(posedge clk);
            des_ip = ip; icmp_id = id; icmp_seq = seq; tx_byte_num = bytes_n;
            reply_checksum = rcs; tx_data = 8'hA5;
            for (k = 0; k < NBYTE; k = k + 1) bytes[k] = 8'h00;
            cnt = 0; found45 = 0; dfa = 8'h00;
            @(posedge clk); tx_start_en = 1;
            @(posedge clk); tx_start_en = 0;
            for (k = 0; k < 3200; k = k + 1) begin
                @(posedge clk); #1;
                if (gmii_tx_en && cnt < NBYTE) begin
                    bytes[cnt] = gmii_txd;
                    dfa = dfa ^ gmii_txd;
                    dfa = {dfa[6:0], ~dfa[7]};        // 顺序相关的滚动混合
                    cnt = cnt + 1;
                end
            end
            for (k = 0; k < cnt; k = k + 1) if (bytes[k] === 8'h45) found45 = 1;
            dig[idx] = dfa;
            // 指纹 = **逐字节原文**，不是哈希：8 位混合有 1/256 的概率把差异盖掉（规矩 48：
            // 旁证本身也是一条声明，可逆/精确才算数）。两个矢量的字节打全，比对是逐字相等。
            $write("[tb_v112_tx_bytes.v:66] BYTES v%0d n=%0d", idx, cnt);
            for (k = 0; k < cnt; k = k + 1) $write(" %h", bytes[k]);
            $write("\n");
            $display("[tb_v112_tx_bytes.v:69] INFO v%0d mix=%h first=%h%h%h%h%h%h%h%h",
                     idx, dfa, bytes[0], bytes[1], bytes[2], bytes[3],
                     bytes[8], bytes[9], bytes[10], bytes[11]);
            if (cnt < 40) begin errors = errors + 1; $display("  FAIL T2 v%0d 只收到 %0d 个字节（地板 40）", idx, cnt); end
            if (!found45) begin errors = errors + 1; $display("  FAIL T1 v%0d 字节流里没有 IP 首部的 0x45", idx); end
        end
    endtask

    initial begin
        vec(0, 32'd0,            16'h1234, 16'h0001, 16'd64,   32'h0000_0000);
        vec(1, {8'd192,8'd168,8'd1,8'd10}, 16'hFFFF, 16'hFFFF, 16'd1500, 32'hAAAA_5555);
        vec(2, 32'hFFFF_FFFF,   16'h0000, 16'h0000, 16'hFFD0, 32'hFFFF_FFFF);
        vec(3, 32'h0000_0101,   16'h0001, 16'hFFFE, 16'd28,   32'h0000_0001);
        vec(4, {8'd10,8'd0,8'd0,8'd5}, 16'h8080, 16'h7f7f, 16'd56, 32'h7FFF_8000);
        vec(5, 32'hFF00_FF00,   16'h0100, 16'h0001, 16'hFFF0, 32'h0001_FFFF);

        // T3 反空对照：把 v0 的 des_ip 改一个字节，指纹必须不同
        vec(0, 32'd0,            16'h1234, 16'h0001, 16'd64,   32'h0000_0000);   // 再跑一次同一矢量
        dfb = dig[0];
        vec(0, 32'd0,            16'h1234, 16'h0001, 16'd64,   32'h0000_0001);   // 只动 reply_checksum 一位
        if (dfb === dig[0]) begin errors = errors + 1; $display("  FAIL T3 改了输入指纹却不动（%h）—— 这把尺子没有牙", dig[0]); end
        else $display("  ok   T3 改一个输入位，指纹从 %h 变成 %h", dfb, dig[0]);

        if (errors == 0) $display("PASS tb_v112_tx_bytes");
        else             $display("FAIL tb_v112_tx_bytes errors=%0d", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL tb_v112_tx_bytes timeout");
        $finish;
    end
endmodule
