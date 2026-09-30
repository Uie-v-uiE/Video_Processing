`timescale 1ns/1ps
// tb_icmp_ping0 —— #188 的尺子：`ping -l 0` 让 `icmp_tx` 的载荷计数减一回绕，回复变成一个畸形巨帧。
//
// 机理（`src/rtl/eth/icmp_tx.v:325-329`，逐行读过）：`st_tx_data` 里
//   `if (data_cnt < tx_data_num - 16'd1) data_cnt <= data_cnt + 1;`
//   `else if (data_cnt == tx_data_num - 16'd1) …补位…`
// 当 `tx_byte_num = 0`（`ping -l 0` 的回复就是这个）时 `tx_data_num - 1` 在 16 位里回绕成 65535 ⇒
// 第一个条件对 `data_cnt = 0..65534` 恒真，机器一路发 **65536** 个数据字节，
// 而 `total_num`（`:112`）写的是 `0 + 28` ⇒ 发出去的帧自己声明"数据段 65536 字节、IP 头 28"。
//
// 期望值不抄 RTL，由定义算：以太网上一个 ICMP 回复的**数据段**长度取
// `max(请求的载荷字节数, MIN_DATA_NUM=18)`（文件头 `:53-55` 自己写的：46 = 20 IP + 8 ICMP + 18 数据）。
// 三条场景各自钉一件事：
//   T1 载荷 0 字节 ⇒ 必须发 18 个数据字节（**改前必红**：今天发 65536）。
//   T2 载荷 8 字节 ⇒ 仍发 18（补位这条路今天就是对的，改不许把它弄坏）。
//   T3 载荷 56 字节 ⇒ 恰好 56（不补位；把边界收得太紧会在这里少发）。
//   T4 反空转：每场都必须真的进过 `st_tx_data` 并且发出 `tx_done`（"0 次"不是通过）。
module tb_icmp_ping0;

    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk;                       // 125 MHz GMII 域

    reg  [15:0] tx_byte_num = 0;
    reg  [7:0]  tx_data = 0;
    reg         tx_start_en = 0;
    reg  [31:0] reply_checksum = 32'h0;
    reg  [15:0] icmp_id = 16'h1234, icmp_seq = 16'h0001;
    reg  [47:0] des_mac = 48'h0123456789AB;
    reg  [31:0] des_ip = 32'h0A000001;
    reg  [31:0] crc_data = 32'hDEADBEEF;
    reg  [7:0]  crc_next = 8'h5A;

    wire tx_done, tx_req, gmii_tx_en, crc_en, crc_clr;
    wire [7:0] gmii_txd;

    integer errors = 0;
    integer cyc_data = 0, cyc_txen = 0, dones = 0;
    integer scene = 0, want = 0;
    reg [7:0] last_data_byte = 8'h0;      // 最后一个"真载荷"字节（补位应当重复它）
    reg [7:0] pad_first = 8'h0;           // 补位段第一个字节
    integer pad_seen = 0;                 // 补位段长度

    icmp_tx dut (
        .clk(clk), .rst_n(rst_n),
        .reply_checksum(reply_checksum), .icmp_id(icmp_id), .icmp_seq(icmp_seq),
        .tx_start_en(tx_start_en), .tx_data(tx_data), .tx_byte_num(tx_byte_num),
        .des_mac(des_mac), .des_ip(des_ip), .crc_data(crc_data), .crc_next(crc_next),
        .tx_done(tx_done), .tx_req(tx_req), .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd),
        .crc_en(crc_en), .crc_clr(crc_clr));

    // 观测：数据态的拍数（= 实际发出的数据字节数）与整帧的 tx_en 拍数
    always @(posedge clk) if (rst_n) begin
        if (dut.cur_state == dut.st_tx_data) begin
            if (cyc_data >= tx_byte_num) begin
                if (pad_seen == 0) pad_first <= gmii_txd;   // 第一段补位（cyc_data == tx_byte_num 那一拍）
                pad_seen = pad_seen + 1;
            end
            last_data_byte <= gmii_txd;
            cyc_data = cyc_data + 1;
        end
        if (gmii_tx_en)                      cyc_txen = cyc_txen + 1;
        if (tx_done)                         dones    = dones + 1;
    end

    task chk(input [8*140:1] named, input ok);
        begin
            if (ok) $display("PASS %0s", named);
            else  begin $display("FAIL %0s", named); errors = errors + 1; end
        end
    endtask

    // 跑一场：复位后给一个 tx_byte_num，拉起 tx_start_en 一拍，等 tx_done（最多 cap 拍）
    task run_scene(input integer n_bytes, input integer cap);
        integer k;
        begin
            @(negedge clk); rst_n = 0;
            repeat (4) @(negedge clk);
            cyc_data = 0; cyc_txen = 0; dones = 0;
            last_data_byte = 0; pad_first = 0; pad_seen = 0;
            tx_byte_num = n_bytes[15:0];
            @(negedge clk); rst_n = 1;
            repeat (3) @(negedge clk);
            @(negedge clk); tx_data = 8'hA5 + n_bytes[7:0]; tx_start_en = 1;
            @(negedge clk); tx_start_en = 0;
            k = 0;
            while (dones == 0 && k < cap) begin @(negedge clk); k = k + 1; end
        end
    endtask

    initial begin
        // ---- T1：`ping -l 0` 的回复 ----
        scene = 1; want = 18;
        run_scene(0, 200_000);
        $display("INFO T1 tx_byte_num=0 → 数据态拍数=%0d（期望 %0d）整帧 tx_en 拍数=%0d tx_done=%0d",
                 cyc_data, want, cyc_txen, dones);
        chk("T1 zero-byte ping reply must emit exactly MIN_DATA_NUM (18) data bytes, not 65536",
            cyc_data == want);
        chk("T4a T1 really ran: entered the data state and completed the frame once",
            cyc_data > 0 && dones == 1);

        // ---- T2：8 字节载荷（合法的短 ping），补位这条路必须照旧 ----
        scene = 2; want = 18;
        run_scene(8, 200_000);
        $display("INFO T2 tx_byte_num=8 → 数据态拍数=%0d（期望 %0d）tx_done=%0d", cyc_data, want, dones);
        chk("T2 8-byte payload still pads to 18 data bytes", cyc_data == want && dones == 1);

        // ---- T5：短 ping 的补位内容（必须紧跟 T2 判——`run_scene` 每次都会清零观测变量，
        //      放到 T3 之后读到的是 56 字节那一场的"没有补位"，那就是我自己写的又一条假话）----
        //      定义上这段不被 IP 长度字段覆盖，但今天的行为是"重复最后一个有效字节"；
        //      若某个只改长度的修法把它变成"读口的下一个字节"，这条会红 ⇒ 得连读请求一起门住。
        $display("INFO T5 tx_byte_num=8 补位段长度=%0d 第一个补位字节=%h 最后一个载荷字节=%h",
                 pad_seen, pad_first, last_data_byte);
        chk("T5 padding repeats the last payload byte (a length-only fix must not change content)",
            pad_seen == 10 && pad_first == last_data_byte);

        // ---- T3：56 字节载荷，不补位；边界收得太紧会在这里少发 ----
        scene = 3; want = 56;
        run_scene(56, 200_000);
        $display("INFO T3 tx_byte_num=56 → 数据态拍数=%0d（期望 %0d）tx_done=%0d", cyc_data, want, dones);
        chk("T3 56-byte payload emits exactly 56 data bytes (no padding, none lost)",
            cyc_data == want && dones == 1);

        $display("");
        if (errors == 0) $display("RESULT tb_icmp_ping0 PASS");
        else             $display("RESULT tb_icmp_ping0 FAIL nfail=%0d", errors);
        $finish;
    end

    initial begin
        #30_000_000;
        $display("FAIL tb_icmp_ping0 timeout");
        $display("RESULT tb_icmp_ping0 FAIL nfail=timeout");
        $finish;
    end

endmodule
