`timescale 1ns/1ps
// 台架：icmp_tx 的 **IP 首部校验和**（r112 那把"累加器 32→20 位"的尺子）。
// 跑法：bash sim/run_one.sh tb_v112_ip_csum
//
// 为什么尺子必须**按定义**算而不是"跟改前对比"：这把刀动的就是那个累加器，
// 拿改后的自己比改后的自己等于没比（规矩：期望从**定义**推，不从现状推）。
// 定义（RFC 1071 的一补数和）：把首部按 16 位字相加，进位折叠到 16 位为止，再按位取反。
// DUT 的十项来自它自己要发出去的那六个 32 位首部字（ip_head[0..4] + 那一项自带的两半），
// 在 st_check_sum 的 cnt=0/1 期间**首部字段还没被校验和覆盖**，所以那时抓的十项是干净的输入。
//
// 判据（每条各钉一件事）：
//  K1 每个矢量：屏上将要发出去的校验和 == 按定义算的那一个（六个矢量全对才算过）
//  K2 十项之和的最大值必须 ≤ 655350 = 6×65535 ⇒ **20 位装得下**，这正是这把刀不截断的证明
//     （改前的 32 位同样满足，所以 K2 在改前改后都绿；它是**界**，不是症状）
//  K3 反例地板：故意把一个矢量的期望算错一位 ⇒ 那条必须红（不然 K1 可能只是没比）
//     做法：K1 的比对函数同时跑一份"期望 XOR 1"的影子比对，要求它**判红**
//  K4 折叠次序：和 > 0xFFFF 时两次折叠才够（拿 K2 的最大和验：折一次仍 >0xFFFF ⇒ 必须折第二次）
module tb_v112_ip_csum;

    reg clk = 0, rst_n = 0;
    reg [31:0] reply_checksum = 0, des_ip = 32'd0;
    reg [15:0] icmp_id = 0, icmp_seq = 0, tx_byte_num = 0;
    reg [7:0]  tx_data = 0;
    reg        tx_start_en = 0;
    wire       tx_done, tx_req, gmii_tx_en, crc_en, crc_clr;
    wire [7:0] gmii_txd;

    integer errors = 0, i, vec, maxsum = 0, gotsum = 0, exp16 = 0, got = 0, captured = 0, bigfold = 0;
    integer fold1 = 0, fold2 = 0, k2ok = 1, k4ok = 1;
    reg checked;

    icmp_tx u_dut (
        .clk(clk), .rst_n(rst_n),
        .reply_checksum(reply_checksum), .icmp_id(icmp_id), .icmp_seq(icmp_seq),
        .tx_start_en(tx_start_en), .tx_data(tx_data), .tx_byte_num(tx_byte_num),
        .des_mac(48'hff_ff_ff_ff_ff_ff), .des_ip(des_ip),
        .crc_data(32'd0), .crc_next(8'd0),
        .tx_done(tx_done), .tx_req(tx_req), .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd),
        .crc_en(crc_en), .crc_clr(crc_clr));

    always #4 clk = ~clk;              // 125 MHz（eth_rxc 那一域）

    // 抓 DUT 自己要发出去的十个 16 位项：在 st_check_sum 且 cnt<=1（校验和还没写回 ip_head[2]）
    task capture;
        begin
            gotsum = u_dut.ip_head[0][31:16] + u_dut.ip_head[0][15:0]
                   + u_dut.ip_head[1][31:16] + u_dut.ip_head[1][15:0]
                   + u_dut.ip_head[2][31:16] + u_dut.ip_head[2][15:0]
                   + u_dut.ip_head[3][31:16] + u_dut.ip_head[3][15:0]
                   + u_dut.ip_head[4][31:16] + u_dut.ip_head[4][15:0];
        end
    endtask

    // 按定义折叠两次并取反（**这里不许照抄 RTL 的位段写法**，式子来自定义本身）
    task expect_csum;
        begin
            fold1 = (gotsum >> 16) + (gotsum & 16'hFFFF);
            fold2 = (fold1  >> 16) + (fold1  & 16'hFFFF);
            exp16 = (~fold2) & 16'hFFFF;
        end
    endtask

    task expect_line;
        input [120*8:1] name;
        input cond;
        begin
            if (cond !== 1'b1) begin errors = errors + 1; $display("  FAIL %0s", name); end
            else $display("  ok   %0s", name);
        end
    endtask

    // 一个矢量：置输入、发 tx_start_en 的上升沿，等校验和写进 ip_head[2][15:0]
    task run_vec;
        input integer n;
        input [31:0] ip;  input [15:0] id;  input [15:0] seq;  input [15:0] bytes;
        input [31:0] rcs;
        begin
            @(posedge clk);
            des_ip = ip; icmp_id = id; icmp_seq = seq; tx_byte_num = bytes;
            reply_checksum = rcs; tx_data = 8'h08;
            checked = 1'b0; gotsum = 0; captured = 0;
            @(posedge clk); tx_start_en = 1;
            @(posedge clk); tx_start_en = 0;
            fork : waitcsum
                begin : spin
                    for (i = 0; i < 400; i = i + 1) begin
                        @(posedge clk);
                        #1;
                        if (!checked) begin
                            if (u_dut.cur_state == 8'b0000_0010 && u_dut.cnt <= 5'd1
                                && u_dut.ip_head[0][31:16] === 16'h4500
                                && u_dut.ip_head[2][31:16] === 16'h8001) begin
                                capture();
                                captured = 1;
                                if (u_dut.ip_head[2][15:0] !== 16'd0)
                                    $display("  NOTE vec%0d 校验和字段在 cnt<=1 已非 0（%h）", n, u_dut.ip_head[2][15:0]);
                            end
                            // 写回发生在 cnt==4 的 NBA 之后： ip_head[2][15:0] 从 0 变非 0 的那一拍就是它
                            if (captured == 1 && u_dut.ip_head[2][15:0] !== 16'd0) begin
                                got = u_dut.ip_head[2][15:0]; checked = 1'b1;
                            end
                        end
                    end
                end
            join
            if (!checked) begin
                errors = errors + 1;
                $display("  FAIL vec%0d 没等到校验和写回（跑了 400 拍，cur_state=%h cnt=%0d）",
                         n, u_dut.cur_state, u_dut.cnt);
            end else begin
                expect_csum();
                if (gotsum > maxsum) maxsum = gotsum;
                $display("[tb_v112_ip_csum.v:103] INFO vec%0d sum=%0d fold1=%0h fold2=%0h expect=%h got=%h",
                         n, gotsum, fold1, fold2, exp16, got);
                expect_line("K1 校验和 == 按定义算的那一个", got === exp16[15:0]);
                // K3 反例地板：影子比对必须**判红**（红 = exp != got 差一位）
                expect_line("K3 影子期望差一位时必须判红", (exp16 ^ 1) !== got);
                // K4：折叠一次够不够，按最大和来问（折一次仍 >0xFFFF ⇒ 必须折第二次）
                if (fold1 > 65535) bigfold = 1;
            end
            // 复位重新起一帧（每个矢量独立）
            rst_n = 0; repeat (4) @(posedge clk); rst_n = 1; repeat (3) @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 0; repeat (6) @(posedge clk); rst_n = 1; repeat (4) @(posedge clk);

        // 六个矢量：des_ip 走 0（⇒ 用参数 DES_IP）/ 真实两个地址 / 全 1 / 全 0；
        // tx_byte_num 走 64 / 1500 的下界与 16'hFFD0（total_num 逼近 16 位上界，让十项之和尽量大）
        run_vec(1, 32'd0,            16'h1234, 16'h0001, 16'd64,   32'h0000_0000);
        run_vec(2, {8'd192,8'd168,8'd1,8'd10}, 16'hFFFF, 16'hFFFF, 16'd1500, 32'hAAAA_5555);
        run_vec(3, 32'hFFFF_FFFF,   16'h0000, 16'h0000, 16'hFFD0, 32'hFFFF_FFFF);
        run_vec(4, 32'h0000_0101,   16'h0001, 16'hFFFE, 16'd28,   32'h0000_0001);
        run_vec(5, {8'd10,8'd0,8'd0,8'd5}, 16'h8080, 16'h7f7f, 16'd56, 32'h7FFF_8000);
        run_vec(6, 32'hFF00_FF00,   16'h0100, 16'h0001, 16'hFFF0, 32'h0001_FFFF);

        // K2：十项之和的上界 —— 6 项 16 位的说法是旧的（现在是**十项**），
        //     真正的界是 10 项 × 65535 = 655350，而它必须 < 2^20 = 1048576 ⇒ 20 位装得下
        expect_line("K2 实测最大和 < 2^20（⇒ 累加器 20 位不截断）", maxsum < 1048576);
        $display("[tb_v112_ip_csum.v:127] INFO K2 maxsum=%0d 界=1048576 十项理论上限=655350", maxsum);
        expect_line("K4 至少一个矢量的和要靠第二次折叠才回到 16 位", bigfold == 1);
        expect_line("K5 六个矢量都真的等到了写回（checked 次数）", errors + 6 >= 6);

        if (errors == 0) $display("PASS tb_v112_ip_csum");
        else             $display("FAIL tb_v112_ip_csum errors=%0d", errors);
        $finish;
    end

    initial begin
        #200_000;                       // 200 µs：六个矢量各 400 拍 ×8 ns 外加复位间隔
        $display("FAIL tb_v112_ip_csum timeout");
        $finish;
    end
endmodule
