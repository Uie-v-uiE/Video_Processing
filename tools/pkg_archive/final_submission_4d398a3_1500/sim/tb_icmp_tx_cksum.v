`timescale 1ns/1ps
// 功能：被测模块 `icmp_tx`（`src/rtl/eth/icmp_tx.v`，ICMP 回显应答的 GMII 发送器）；覆盖点＝**发出去的
//        那一帧里的校验和字段与整帧字节流**，在"把单拍多操作数求和拆成逐拍累加"这类改法前后必须逐字节相同。
//        立这条台架的动机：全设计 setup 最差的一族（`eth_rxc` 域 WNS 0.739 ns）两端都在本模块的校验和
//        累加里（`ip_head_reg[*]/C → check_buffer_reg[*]/D`，11 级逻辑含 6 个 CARRY4、route 58 %），
//        而 `icmp_tx.v:278-282` 是"一拍里加 5~6 项"的加法树 ⇒ 结构上可以改成一拍一项，
//        但必须先有一条把整帧钉死的尺子。
// 激励与检查：时钟 #4 翻转（8 ns，GMII 125 MHz 域）。每个场景重新复位：negedge 拉低 rst_n 4 拍，置
//        `tx_byte_num`/`icmp_id`/`icmp_seq`/`des_ip`/`reply_checksum` 后释放，再等 3 拍打一拍
//        `tx_start_en`；`tx_req` 为高的那一拍按 `pay[]` 给下一个字节（顶层 `eth_ctrl.v:57` 也是
//        "请求后给数"这一形），`crc_data`/`crc_next` 恒 0（FCS 由外部 `crc32_d8` 算，本台架不判它）。
//        采集＝`gmii_tx_en` 为高的每个时钟沿把 `gmii_txd` 存进 `bytes[]`，直到 `tx_done` 或 400_000 拍。
//        判定按**定义**算，不抄 RTL：
//          A1 IP 首部校验和自洽：把发出的 20 字节 IP 首部里校验和那两字节当作 0，按 16 位大端拼字做
//             反码求和（进位回卷），取反必须等于帧里那两字节。这条与"首部各字段是什么"独立对应。
//          A2 反空转：每场都必须真的采到 ≥40 字节并走到 `tx_done`（采到 0 字节不是"通过"）。
//          A3 能红的对照：两场只差 `reply_checksum` 的最低一位 ⇒ 帧里的 ICMP 校验和字段必须**不同**
//             （若相同说明判据根本没看见校验和）。
//          A4 整帧留档：每场把字节流按 16 字节一行打出（`BYTES <场> <n> <hex…>`）并附一枚 32 位滚动
//             摘要 `SUM32`。摘要与 BYTES 行是"改动前后逐字节相同"的比对面；摘要只作旁证不参与判定。
//        ICMP 校验和的**期望值不在这里重算**：它的输入 `reply_checksum` 本身就是接收侧算好的数据段和
//        （文件头 `:5-6` 的口径），且 RTL 把它作为一个 32 位量加进 32 位累加器后再折叠两次——
//        在台架里另写一套折叠只能证明"我抄得像"，所以这一格交给 A4 的字节流相等来钉，A3 负责它没瞎。
// 预期结果：通过时逐条打 `PASS A1 ip checksum self-consistent | …`、`PASS A2 captured …`、
//        `PASS A3 perturbation | cksum … -> …`，并打 `BYTES …` 留档行，末行
//        `RESULT tb_icmp_tx_cksum PASS nfail=0`；失败时对应条目改打 `FAIL <条目名> | <读数>` 且 nfail
//        加一，末行 `RESULT tb_icmp_tx_cksum FAIL nfail=<n>`；6 ms 看门狗到点打
//        `RESULT tb_icmp_tx_cksum FAIL timeout`。
module tb_icmp_tx_cksum;

    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk;                       // 125 MHz GMII 域

    reg  [31:0] reply_checksum = 0;
    reg  [15:0] icmp_id  = 16'h1234;
    reg  [15:0] icmp_seq = 16'h0001;
    reg         tx_start_en = 0;
    reg  [ 7:0] tx_data = 0;
    reg  [15:0] tx_byte_num = 8;
    reg  [47:0] des_mac = 48'h0123456789AB;
    reg  [31:0] des_ip = 32'h0A000001;
    reg  [31:0] crc_data = 32'h0;
    reg  [ 7:0] crc_next = 8'h0;

    wire        tx_done, tx_req, gmii_tx_en, crc_en, crc_clr;
    wire [ 7:0] gmii_txd;

    icmp_tx u_icmp(.clk(clk), .rst_n(rst_n), .reply_checksum(reply_checksum),
        .icmp_id(icmp_id), .icmp_seq(icmp_seq), .tx_start_en(tx_start_en),
        .tx_data(tx_data), .tx_byte_num(tx_byte_num), .des_mac(des_mac),
        .des_ip(des_ip), .crc_data(crc_data), .crc_next(crc_next),
        .tx_done(tx_done), .tx_req(tx_req), .gmii_tx_en(gmii_tx_en),
        .gmii_txd(gmii_txd), .crc_en(crc_en), .crc_clr(crc_clr));

    integer bytes[0:1023];                      // 显式清零：`integer` 数组默认是 X
    integer pay[0:63];
    integer nbytes, pidx, k, nfail, scen, kpair, acc, carry, ip_ofs, icmp_ofs;
    integer exp_ip, got_ip, prev_ic, cur_ic, calc_ones_out;
    reg [31:0] sum32;

    task reset_all;                             // 每场都重新复位，不留上一场的寄存器残值
        begin
            @(negedge clk); rst_n = 0;
            repeat (4) @(negedge clk);
            nbytes = 0; pidx = 0; tx_start_en = 0;
            rst_n = 1;
            repeat (3) @(negedge clk);
        end
    endtask

    task run_scen(input [31:0] rsum, input [15:0] nbyte);
        integer t;
        begin
            reply_checksum = rsum; tx_byte_num = nbyte;
            @(negedge clk); tx_start_en = 1;
            @(negedge clk); tx_start_en = 0;
            for (t = 0; t < 400_000; t = t + 1) begin
                @(posedge clk);
                if (tx_req) begin
                    tx_data <= pay[pidx % 64];
                    pidx = pidx + 1;
                end
                if (gmii_tx_en && nbytes < 1024) begin
                    bytes[nbytes] = gmii_txd; nbytes = nbytes + 1;
                end
                if (tx_done) t = 400_000;
            end
        end
    endtask

    // 反码求和（定义法，16 位大端拼字；skip_ofs 那一格的两字节当 0 处理＝不参与累加）
    task calc_ones(input integer from, input integer len, input integer skip_ofs);
        integer q;
        begin
            acc = 0;
            q = 0;
            while (q + 1 < len) begin
                if (q == skip_ofs) begin
                    // 校验和字段本身当 0，跳这一对
                end else begin
                    acc = acc + (((bytes[from + q]) & 16'hFF) << 8) + ((bytes[from + q + 1]) & 16'hFF);
                end
                q = q + 2;
            end
            carry = (acc >> 16) & 32'hFFFF;
            acc = (acc & 32'hFFFF) + carry;
            carry = (acc >> 16) & 32'hFFFF;
            acc = acc + carry;
            calc_ones_out = acc & 32'hFFFF;
        end
    endtask

    task dump(input [15:0] tag);
        integer c;
        begin
            sum32 = 32'h0;
            for (c = 0; c < nbytes; c = c + 1)
                sum32 = (sum32 + bytes[c] + 32'h9E3779B1) ^ (sum32 << 5);
            $display("BYTES %0d %0d SUM32=%h", tag, nbytes, sum32);
            for (c = 0; c < nbytes; c = c + 16) begin
                $write("  %04x ", c);
                for (kpair = 0; kpair < 16 && c + kpair < nbytes; kpair = kpair + 1)
                    $write("%02x ", bytes[c + kpair] & 8'hFF);
                $display("");
            end
        end
    endtask

    initial begin
        for (k = 0; k < 64; k = k + 1)   pay[k] = 8'hA0 + k;
        for (k = 0; k < 1024; k = k + 1) bytes[k] = 0;
        nfail = 0; scen = 0; prev_ic = -1;
        ip_ofs = 22;                          // 前导 8 + 以太头 14
        icmp_ofs = 22 + 20;

        // ---- 场 1：8 字节载荷、reply_checksum=0、des_ip 给定 ----
        reset_all; run_scen(32'h00000000, 16'd8);  scen = scen + 1;
        if (nbytes < 40) begin
            $display("FAIL A2 captured | scen %0d only %0d bytes", scen, nbytes); nfail = nfail + 1;
        end else begin
            $display("PASS A2 captured | scen %0d bytes=%0d", scen, nbytes);
            calc_ones(ip_ofs, 20, 10);
            exp_ip = (~calc_ones_out) & 16'hFFFF;
            got_ip = ((bytes[ip_ofs + 10] & 8'hFF) << 8) + (bytes[ip_ofs + 11] & 8'hFF);
            if (exp_ip === got_ip) $display("PASS A1 ip checksum self-consistent | got=%h exp=%h", got_ip, exp_ip);
            else begin $display("FAIL A1 ip checksum | got=%h exp=%h", got_ip, exp_ip); nfail = nfail + 1; end
            dump(1);
        end
        cur_ic = ((bytes[icmp_ofs + 2] & 8'hFF) << 8) + (bytes[icmp_ofs + 3] & 8'hFF);
        prev_ic = cur_ic;

        // ---- 场 2：56 字节载荷（不补位那一支）、reply_checksum=0x11223344 ----
        reset_all; run_scen(32'h11223344, 16'd56); scen = scen + 1;
        if (nbytes < 40) begin
            $display("FAIL A2 captured | scen %0d only %0d bytes", scen, nbytes); nfail = nfail + 1;
        end else begin
            $display("PASS A2 captured | scen %0d bytes=%0d", scen, nbytes);
            calc_ones(ip_ofs, 20, 10);
            exp_ip = (~calc_ones_out) & 16'hFFFF;
            got_ip = ((bytes[ip_ofs + 10] & 8'hFF) << 8) + (bytes[ip_ofs + 11] & 8'hFF);
            if (exp_ip === got_ip) $display("PASS A1 ip checksum self-consistent | got=%h exp=%h", got_ip, exp_ip);
            else begin $display("FAIL A1 ip checksum | got=%h exp=%h", got_ip, exp_ip); nfail = nfail + 1; end
            dump(2);
        end

        // ---- 场 3：与场 1 只差 reply_checksum 的最低一位 ⇒ ICMP 校验和必须变 ----
        reset_all; run_scen(32'h00000001, 16'd8); scen = scen + 1;
        cur_ic = ((bytes[icmp_ofs + 2] & 8'hFF) << 8) + (bytes[icmp_ofs + 3] & 8'hFF);
        if (nbytes >= 40 && cur_ic !== prev_ic)
            $display("PASS A3 perturbation | cksum %h -> %h", prev_ic, cur_ic);
        else begin
            $display("FAIL A3 perturbation | both/either bad: %h -> %h bytes=%0d", prev_ic, cur_ic, nbytes);
            nfail = nfail + 1;
        end
        dump(3);

        // ---- 场 4：des_ip=0 ⇒ 走参数 DES_IP 那一支（把首部字段的来源也钉住） ----
        des_ip = 32'h0;
        reset_all; run_scen(32'h00000000, 16'd8); scen = scen + 1;
        if (nbytes < 40) begin
            $display("FAIL A2 captured | scen %0d only %0d bytes", scen, nbytes); nfail = nfail + 1;
        end else begin
            $display("PASS A2 captured | scen %0d bytes=%0d", scen, nbytes);
            calc_ones(ip_ofs, 20, 10);
            exp_ip = (~calc_ones_out) & 16'hFFFF;
            got_ip = ((bytes[ip_ofs + 10] & 8'hFF) << 8) + (bytes[ip_ofs + 11] & 8'hFF);
            if (exp_ip === got_ip) $display("PASS A1 ip checksum self-consistent | got=%h exp=%h", got_ip, exp_ip);
            else begin $display("FAIL A1 ip checksum | got=%h exp=%h", got_ip, exp_ip); nfail = nfail + 1; end
            dump(4);
        end

        if (nfail == 0) $display("RESULT tb_icmp_tx_cksum PASS nfail=0");
        else            $display("RESULT tb_icmp_tx_cksum FAIL nfail=%0d", nfail);
        $finish;
    end

    initial begin
        #6_000_000;
        $display("RESULT tb_icmp_tx_cksum FAIL timeout");
        $finish;
    end
endmodule
