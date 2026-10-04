`timescale 1ns/1ps
// 功能：被测模块 `dc_fifo`（参数 DATA_W=36、ADDR_W=13，深度 DEPTH=8192）；覆盖点＝跨域 FIFO 的"满"边界
//        落在第几格、报满后是否还收字、排空字数与写入序号顺序、两轮指针回绕。
// 激励与检查：写域 #4 翻转（8 ns）、读域 #20 翻转（40 ns），复位释放前空跑 4 个写沿、释放后再走 3 拍；
//        阶段 A 读侧不动、写侧连灌 DEPTH+400 个字（wr_data 取写入计数）；判据 C1 要求首次报满前的收下
//        字数 full_at 必须等于 DEPTH；C2 要求报满之后的迟收字数 late_accept==0；阶段 B 逐字读到 received==accepted
//        （上限 DEPTH+2000 次读），C3 要求 received==DEPTH、C4 要求 rd_data 逐字等于 expect_idx 计数
//        （mismatch==0）；阶段 C 再做 3 轮"灌 DEPTH+300 后排空"，C5 要求 received==accepted 且 mismatch==0。
// 预期结果：通过时打印 `PASS C1 boundary: all 8192 slots accepted`、`PASS C2 blocked once full`、
//        `PASS C3 drained 8192 words`、`PASS C4 every word came back in write order`、
//        `PASS C5 pointer wrap covered (<accepted> words through the 8192 boundary)`，另有
//        `[tb_cdc_capacity:PROBE] first_full_after_accepts=/drained=/peak_occ=` 三条量值行，末两行
//        `PASS tb_cdc_capacity ALL` 与 `RESULT tb_cdc_capacity PASS`；失败时对应判据打印
//        `FAIL C1 wr_full fires one slot early: accepted <n> of 8192`、`FAIL C2 <n> words accepted AFTER
//        wr_full`、`FAIL C3 drain count <n> != depth 8192`、`FAIL C4 payload order broken: <n> mismatched
//        words`（附最多 3 条 `FAIL data[<n>]=<got> exp <want>`）或 `FAIL C5 wrap bursts lost words /
//        out of order`，末两行改为 `FAIL tb_cdc_capacity errors=<n>` 与 `RESULT tb_cdc_capacity FAIL errors=<n>`。
// dc_fifo 的"满"边界台架：只测一只 FIFO，不接任何链路。
// 输入：写域 8 ns（= 板上 eth_rxc）、读域 40 ns；写侧一路灌，读侧按阶段停/放。
// 输出：五条判据 C1..C5 + 两条 PROBE（首次报满发生在收下第几个字之后、峰值占用）。
//   C1 满发生在**收下第 DEPTH 个字之后**（不是 DEPTH−1）；C2 报满之后一个都不再收；
//   C3/C4 排空后字数等于深度、且逐字对得上写入序号；C5 三轮灌满-排空跨过指针回绕点。
// 为什么需要这支：`wr_full` 原来用**下一个**写指针（wbin+1 的格雷码）去比，"满"因此提前一格落地
// —— 第 8192 个字被当作溢出丢掉，而那条"加法 + 二进制转格雷 + 比较"的锥体正是全设计最差 setup
// 路径的起点（ISSUES #105/#121）。C1 就是这件事的尺子：改前红（8191）、改后绿（8192），
// 对照跑法 `sim/mut_control.sh tb_cdc_capacity C1 cdc_full_next`。
module tb_cdc_capacity;
    localparam DATA_W = 36;
    localparam ADDR_W = 13;
    localparam DEPTH  = (1 << ADDR_W);

    reg               wr_clk = 0, rd_clk = 0, wr_rst_n = 0, rd_rst_n = 0;
    reg               wr_en = 0, rd_en = 0;
    reg  [DATA_W-1:0] wr_data = 0;
    wire              wr_full, rd_empty;
    wire [DATA_W-1:0] rd_data;

    always #4 wr_clk = ~wr_clk;    // 125 MHz：写域就是 eth_rxc 的周期
    always #20 rd_clk = ~rd_clk;   // 25 MHz：读域故意慢，好把 FIFO 灌满

    dc_fifo #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) dut (
        .wr_clk(wr_clk), .wr_rst_n(wr_rst_n), .wr_en(wr_en), .wr_data(wr_data), .wr_full(wr_full),
        .rd_clk(rd_clk), .rd_rst_n(rd_rst_n), .rd_en(rd_en), .rd_data(rd_data), .rd_empty(rd_empty));

    integer errors = 0;
    integer i, k, burst;
    integer accepted = 0, late_accept = 0, full_at = -1;
    integer received = 0, mismatch = 0, expect_idx = 0, peak_occ = 0;
    reg issued;

    always @(posedge wr_clk) if (wr_rst_n && wr_en) begin
        if (wr_full) begin
            if (full_at < 0) full_at = accepted;   // 报满之前一共收下了几个字
        end else begin
            accepted = accepted + 1;
            if (full_at >= 0) late_accept = late_accept + 1;  // 已报满还收字 = 覆盖未读数据
        end
    end

    // 一次一读：发读 → 空一拍 → 收 rd_data。BRAM 读有一拍延迟，这样对齐不用推流水线。
    task do_read;
        begin
            @(negedge rd_clk); rd_en = 1;
            @(posedge rd_clk); issued = !rd_empty;   // 这一拍真的把 rbin 推进了吗
            @(negedge rd_clk); rd_en = 0;
            @(posedge rd_clk);                       // rd_data 现在是那一拍取出的字
            if (issued) begin
                received = received + 1;
                if (rd_data !== expect_idx[DATA_W-1:0]) begin
                    mismatch = mismatch + 1;
                    if (mismatch <= 3)
                        $display("FAIL data[%0d]=%h exp %h", received, rd_data, expect_idx);
                end
                expect_idx = expect_idx + 1;
                if (accepted - received > peak_occ) peak_occ = accepted - received;
            end
        end
    endtask

    initial begin
        $display("[tb_cdc_capacity:INFO] depth=%0d data_w=%0d", DEPTH, DATA_W);
        repeat (4) @(posedge wr_clk);
        wr_rst_n = 1; rd_rst_n = 1;
        repeat (3) @(posedge wr_clk);

        // 阶段 A：读侧不动，写侧连灌 —— 量"满"落在哪一格
        for (i = 0; i < DEPTH + 400; i = i + 1) begin
            @(negedge wr_clk); wr_data = accepted[DATA_W-1:0]; wr_en = 1;
        end
        @(negedge wr_clk); wr_en = 0;

        $display("[tb_cdc_capacity:PROBE] first_full_after_accepts=%0d of depth=%0d", full_at, DEPTH);
        if (full_at != DEPTH) begin
            $display("FAIL C1 wr_full fires one slot early: accepted %0d of %0d", full_at, DEPTH);
            errors = errors + 1;
        end else $display("PASS C1 boundary: all %0d slots accepted", DEPTH);

        if (late_accept != 0) begin
            $display("FAIL C2 %0d words accepted AFTER wr_full -- unread data overwritten", late_accept);
            errors = errors + 1;
        end else $display("PASS C2 blocked once full");

        // 阶段 B：放读排空，逐字对序号
        i = 0;
        while (received < accepted && i < DEPTH + 2000) begin do_read; i = i + 1; end
        $display("[tb_cdc_capacity:PROBE] drained=%0d mismatch=%0d peak_occ=%0d", received, mismatch, peak_occ);
        if (received != DEPTH) begin
            $display("FAIL C3 drain count %0d != depth %0d", received, DEPTH);
            errors = errors + 1;
        end else $display("PASS C3 drained %0d words", DEPTH);
        if (mismatch != 0) begin
            $display("FAIL C4 payload order broken: %0d mismatched words", mismatch);
            errors = errors + 1;
        end else $display("PASS C4 every word came back in write order");

        // 阶段 C：三轮"灌满-排空"，让两个指针都跨过 8192 的回绕点
        for (burst = 0; burst < 3; burst = burst + 1) begin
            for (k = 0; k < DEPTH + 300; k = k + 1) begin
                @(negedge wr_clk); wr_data = accepted[DATA_W-1:0]; wr_en = 1;
            end
            @(negedge wr_clk); wr_en = 0;
            i = 0;
            while (received < accepted && i < DEPTH + 3000) begin do_read; i = i + 1; end
        end
        if (received != accepted) begin
            $display("FAIL C5 wrap bursts lost words: accepted %0d drained %0d", accepted, received);
            errors = errors + 1;
        end else if (mismatch != 0) begin
            $display("FAIL C5 wrap bursts out of order: %0d mismatched", mismatch);
            errors = errors + 1;
        end else $display("PASS C5 pointer wrap covered (%0d words through the 8192 boundary)", accepted);

        if (errors == 0) begin
            $display("PASS tb_cdc_capacity ALL");
            $display("RESULT tb_cdc_capacity PASS");
        end else begin
            $display("FAIL tb_cdc_capacity errors=%0d", errors);
            $display("RESULT tb_cdc_capacity FAIL errors=%0d", errors);
        end
        $finish;
    end
endmodule
