`timescale 1ns/1ps
// tb_writer_abort.v —— ISSUES #170 的尺子：abort 之后**在途的读拍**会串进下一帧。
//
// 被测的是 `src/rtl/axi/axi_frame_writer_gated.v`（顶层里那个 u_row）：它把 DDR 里刚提交的一帧逐行
// 拉回显示缓存。`abort`（上一帧撕了、这一帧不要了）那一拍把 `active` 清 0，而
// `m_axi_rready = active && !sk_full` ⇒ 从下一拍起**不再接收任何 R 拍**。
// 按 AXI 的规矩，master 必须把 `rvalid` 举到 `rvalid && rready` 为止 ⇒ 已经在途的拍不会消失，
// 它们会等在新帧门口：下一帧 `start` 之后第一批被接收的拍其实属于上一帧，而写地址是按"本帧第几个字"
// 推进的 ⇒ 症状就是"整帧平移 + 顶部花"；`outstanding` 在 abort 时被清 0、随后又按这些**旧拍的 rlast**
// 递减 ⇒ 计数从此与真相不符（#170 记的第二半）。
//
// ⚠ 这支台架的全部意义在响应器**照协议办事**：`rvalid` 一旦举起来就 held 住，被接收才推进。
//   如果这里写成"rready=0 就把那拍丢掉"，症状根本不会出现 ⇒ 尺子在被测物上做假绿。
//   B1/B2 两条就是响应器自己的对照：abort 的时机必须真的有在途、而且那一拍确实还举着没人收。
module tb_writer_abort;
    // 小画幅：64×16 = 1024 像素 = 256 个 64bit 字 = 16 个 16 拍 burst（够跑出 MAX_OUT=4 个在途 burst）。
    localparam integer IW = 64, IH = 16, BEATS = 16;
    localparam integer TOTAL_WORDS = (IW*IH)/4;
    localparam [31:0] BASE_A = 32'h1000_0000, BASE_B = 32'h2000_0000;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg         enable = 1, start = 0, abort = 0, allow_wr = 1;
    reg  [31:0] base_addr = BASE_A;
    wire        busy, done, fb_wr_en, rready, arvalid;
    wire [18:0] fb_wr_addr;
    wire [63:0] fb_wr_data;
    wire [31:0] araddr, copy_cycles;
    wire [7:0]  arlen;
    wire [2:0]  arsize;
    wire [1:0]  arburst;
    reg  [63:0] rdata_r = 0;
    reg         rlast_r = 0, rvalid_r = 0;

    axi_frame_writer_gated #(.IMG_W(IW), .IMG_H(IH), .BASE_ADDR(BASE_A)) dut (
        .clk(clk), .rst_n(rst_n), .enable(enable), .start(start), .base_addr(base_addr),
        .allow_wr(allow_wr), .abort(abort), .busy(busy), .done(done),
        .fb_wr_en(fb_wr_en), .fb_wr_addr(fb_wr_addr), .fb_wr_data(fb_wr_data),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize), .m_axi_arburst(arburst),
        .m_axi_arvalid(arvalid), .m_axi_arready(1'b1),
        .m_axi_rdata(rdata_r), .m_axi_rlast(rlast_r), .m_axi_rvalid(rvalid_r), .m_axi_rready(rready),
        .copy_cycles(copy_cycles));

    // ---- R 响应器：已接受的 AR 排队，每串 16 拍；数据低 16 位编进"这一拍是本帧第几个字" ----
    // 两个 base 的 [15:0] 都是 0 ⇒ 写进缓存的数据低 16 位就是帧内字序号，能直接看出串帧没有。
    reg  [31:0] q_addr [0:63];
    integer     q_w = 0, q_r = 0, beat = 0;
    wire        inflight = (q_r != q_w) || rvalid_r;          // 还有没响应完的 burst，或正举着 rvalid
    wire [31:0] head     = q_addr[q_r % 64];

    // AR 捕获与队列推进在**同一个 always** 里：两个块各管半个指针会引入调度竞态
    // （一个阻塞递增、另一个读同一个整数 ⇒ 谁先跑由仿真器决定，这是"台架自己不稳"的形状）。
    always @(posedge clk) begin
        if (!rst_n) begin beat <= 0; q_r <= 0; q_w = 0; end
        else begin
            if (arvalid) begin q_addr[q_w % 64] = araddr; q_w = q_w + 1; end   // arready 恒 1
            if (rvalid_r && rready) begin                                     // **被接收才推进**，否则 held
                if (beat == BEATS-1) begin beat <= 0; q_r <= q_r + 1; end
                else beat <= beat + 1;
            end
        end
    end

    // R 通道三个信号是**队列状态的组合函数**：这样"同一拍被呈现两次"这种事在结构上不可能发生。
    // （第一版把它们也寄存了，于是 rlast 那一拍在 burst 边界被重复呈现一次 ——
    //   症状是 A4/B6 报 17 次"乱序"（= 16 个 burst 边界 + 1）而 A2 的字数照样对得上：
    //   那是**我的响应器**在骗人，不是 DUT 的问题。台架先自证清白，才有资格说别人。）
    always @(*) begin
        rvalid_r = (q_r != q_w);
        rlast_r  = (beat == BEATS-1);
        rdata_r  = {32'hA5A5_0000, 16'd0, head[15:0] + beat[15:0]};
    end

    // ---- 判据 ----
    // 声明风格照 `tb_v94_zoom_sel` 的 `chk`（**非 ANSI**）：ANSI 端口写法与 `sformatf` 都不是
    // Verilog-2001（今天两版都栽在这儿）。⇒ 说明文字走字面量，数字单独走 `v1`。
    // 判据名一律 ASCII：日志名带中文时 100 字节字段会从左边被截掉，`grep <标签>` 就找不到那一条（r94 撞过）。
    integer fails = 0, checks = 0;
    task chk;
        input [8*44-1:0] name;
        input            ok;
        input [8*78-1:0] note;
        input integer    v1;
        begin
            checks = checks + 1;
            if (ok) $display("  PASS %0s | %0s | %0d", name, note, v1);
            else    begin fails = fails + 1; $display("  FAIL %0s | %0s | %0d", name, note, v1); end
        end
    endtask

    integer wr_seen = 0, order_bad = 0;
    reg [63:0] first_data = 0;
    reg        first_seen = 0;
    // ⚠ 期望值这次是**逐行从编码算出来的**，不是凭直觉写 `prev+1`：
    //   数据低 16 位 = `araddr[15:0] + beat`，而 `araddr = base + burst_idx*(BEATS*8)` ⇒
    //   第 w 个字（本帧内 0 起）落在 burst k=w/16、拍 b=w%16，其编码值 = k*128 + b。
    //   第一版按 `prev+1` 判 ⇒ **干净跑**也被报出 15 次"乱序"（= 16 个 burst 边界少一个），
    //   那是尺子自己错（A4 这类基线条目在树上就该绿），不是 DUT 的问题。
    integer   widx;
    reg [15:0] exp_off;
    always @(posedge clk) if (fb_wr_en) begin
        wr_seen = wr_seen + 1;
        if (!first_seen) begin first_data = fb_wr_data; first_seen = 1; end
        widx    = wr_seen - 1;
        exp_off = (widx/BEATS)*128 + (widx%BEATS);
        if (fb_wr_data[15:0] !== exp_off) begin
            order_bad = order_bad + 1;
            // PROBE（不是判据，只帮我看清是哪一类边界）：前 6 次失序把上下文打出来
            if (order_bad <= 6)
                $display("    PROBE order break at write %0d: got 0x%h expected 0x%h (beat=%0d)",
                         wr_seen, fb_wr_data[15:0], exp_off, beat);
        end
    end
    task reset_obs; begin wr_seen = 0; first_seen = 0; order_bad = 0; end endtask
    // `rvalid_r/rlast_r/rdata_r` 现在是**组合输出**（由队列状态算出来），任务里只能动队列，
    // 不能去赋值那三个 —— 多驱动会让台架自己变成不可信的那一方。
    task clear_queue; begin q_r = q_w; beat = 0; end endtask

    integer t = 0;
    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // ===== A：无 abort 的一跑。对照 —— 必须在**当前树上也是绿的**（证明台架本身没意见）=====
        base_addr = BASE_A; abort = 0; reset_obs; clear_queue;
        @(posedge clk); start = 1; @(posedge clk); start = 0;
        t = 0;
        while (!done && t < 6000) begin @(posedge clk); t = t + 1; end
        chk("A1_baseline_done", done === 1'b1, "cycles from start to done (must be finite)", t);
        chk("A2_baseline_word_count", wr_seen == TOTAL_WORDS, "words written; expected TOTAL_WORDS", wr_seen);
        chk("A3_baseline_first_is_head", first_data[15:0] == 16'd0, "frame offset carried by the very first write", first_data[15:0]);
        chk("A4_baseline_in_order", order_bad == 0, "out-of-order writes in a clean run", order_bad);

        // ===== B：在途时 abort，然后重启下一帧（#170 的形状）=====
        base_addr = BASE_A; reset_obs; clear_queue;
        @(posedge clk); start = 1; @(posedge clk); start = 0;
        t = 0;
        while (wr_seen < 3 && t < 600) begin @(posedge clk); t = t + 1; end
        chk("B1_precondition_inflight", inflight === 1'b1, "bursts still unanswered at the abort moment (must be > 0)", q_w - q_r);
        abort = 1; @(posedge clk); abort = 0; @(posedge clk);
        chk("B2_master_holds_the_beat", (rvalid_r === 1'b1) && (rready === 1'b0),
            "after abort rvalid must still be asserted while rready is 0 (AXI: the master may not drop it)", q_w - q_r);

        base_addr = BASE_B; reset_obs;
        @(posedge clk); start = 1; @(posedge clk); start = 0;
        t = 0;
        while (!first_seen && t < 3000) begin @(posedge clk); t = t + 1; end
        chk("B3_new_frame_starts_at_own_head", first_data[15:0] == 16'd0,
            "non-zero = the aborted frame's in-flight beat was written first, so the whole frame is shifted", first_data[15:0]);
        t = 0;
        while (!done && t < 8000) begin @(posedge clk); t = t + 1; end
        chk("B4_new_frame_completes", done === 1'b1, "cycles until the new frame reports done", t);
        chk("B5_new_frame_word_count", wr_seen == TOTAL_WORDS, "words written for the new frame", wr_seen);
        chk("B6_new_frame_in_order", order_bad == 0,
            "out-of-order writes = outstanding desync (old rlast decrements another burst)", order_bad);

        // ===== C：消隐期与 abort 期都不许写（现在就该绿；留着防"修的时候顺手改了 allow 的语义"）=====
        base_addr = BASE_A; reset_obs; clear_queue;
        @(posedge clk); allow_wr = 0; start = 1; @(posedge clk); start = 0;
        repeat (80) @(posedge clk);
        chk("C1_blank_window_no_write", wr_seen == 0, "writes while allow_wr=0", wr_seen);
        allow_wr = 1;
        repeat (300) @(posedge clk);
        abort = 1; @(posedge clk); abort = 0;
        reset_obs;
        repeat (60) @(posedge clk);
        chk("C2_no_write_after_abort", wr_seen == 0, "writes in the 60 cycles right after abort", wr_seen);

        $display("checks=%0d errors=%0d", checks, fails);
        if (fails == 0) $display("TB RESULT PASS");
        else            $display("TB RESULT FAIL");
        $finish;
    end

    initial begin
        #8_000_000;
        $display("  FAIL Z_timeout | the run never finished (checks=%0d fails=%0d)", checks, fails);
        $display("TB RESULT FAIL timeout");
        $finish;
    end
endmodule
