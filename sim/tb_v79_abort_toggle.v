`timescale 1ns/1ps
// v7.9 台架：`copy_abort`（axi 域 1 拍 = 10 ns 脉冲）到 50 MHz 像素域的三种接法，
// 用**相位扫描**把它们量开：0 = 两路时钟同相（这正是板上 MMCM 50/100 MHz 的真实情况），
// 1..9 ns = 人为加的偏移，代表硅片上的时钟不确定度（skew/JI）。
//   RAW   ：像素域直接 `if (copy_abort)` —— 改之前的写法
//   LVL3  ：电平型 3 级同步 —— "看起来最正规"的那版，为什么在这里反而更糟
//   TOG   ：翻转式脉冲同步器（frame_commit_lock.abort_tgl + 3FF + 异拍）—— 本版
// 判据：
//   A1 每个相位下 TOG 看到的次数 == 真发生的 abort 次数（一次不多、一次不少）
//   A2 至少有一个相位 RAW 漏看（证明这不是理论洁癖）
//   A3 LVL3 与 RAW 在**每一个**相位上数目都一样 ⇒ "换电平同步"根本不是修法（实测，不是推论）
module tb_v79_abort_toggle;
    localparam integer IMG_H = 300;
    localparam integer WD    = 32'd30;      // 看门狗 30 个 axi 拍 = 300 ns，短到能量相位

    // ---- 时钟：axi 固定 5 ns 半周期；pix 半周期默认 10 ns，可临时改成 11 ns 做一次性移相 ----
    reg axi_clk = 0, pix_clk = 0, rst_n = 0;
    integer PZ = 10;
    always #(PZ) pix_clk = ~pix_clk;
    always #5 axi_clk = ~axi_clk;

    reg commit_req = 0, blank_safe = 0, vsync = 0, de = 0, copy_busy = 0, copy_done = 0;
    wire start_copy, allow, copy_abort, copy_abort_tgl, frame_ready;
    wire [31:0] copy_base;

    frame_commit_lock #(.IMG_H(IMG_H), .DISP_H(600), .WD_CYC(WD)) u_cm (
        .axi_clk(axi_clk), .axi_rst_n(rst_n),
        .commit_req(commit_req), .commit_base(32'h1000_0000),
        .pix_clk(pix_clk), .pix_rst_n(rst_n),
        .de(de), .vsync(vsync), .blank_safe(blank_safe),
        .copy_busy(copy_busy), .copy_done(copy_done),
        .start_copy(start_copy), .copy_base(copy_base),
        .frame_ready_pix(frame_ready), .allow_copy_axi(allow),
        .copy_abort(copy_abort), .abort_tgl(copy_abort_tgl)
    );

    // ---- 真值：axi 域里 abort 发生了多少次 ----
    integer n_abort = 0;
    always @(posedge axi_clk) if (copy_abort) n_abort = n_abort + 1;

    // ---- 接法 1：裸采（改之前的样子）----
    reg raw_q = 0, raw_qd = 0;
    integer n_raw = 0;
    always @(posedge pix_clk) begin
        raw_q <= copy_abort;
        raw_qd <= raw_q;
    end
    always @(posedge pix_clk) if (raw_q && !raw_qd) n_raw = n_raw + 1;

    // ---- 接法 2：电平型 3 级同步 ----
    (* ASYNC_REG = "TRUE" *) reg l0 = 0, l1 = 0, l2 = 0, l2d = 0;
    integer n_lvl = 0;
    always @(posedge pix_clk) begin
        {l2, l1, l0} <= {l1, l0, copy_abort};
        l2d <= l2;
    end
    always @(posedge pix_clk) if (l2 && !l2d) n_lvl = n_lvl + 1;

    // ---- 接法 3：翻转 + 3 级 + 异拍（本版的顶层写法）----
    (* ASYNC_REG = "TRUE" *) reg a0 = 0, a1 = 0, a2 = 0;
    wire tog_pix = a1 ^ a2;
    integer n_tog = 0;
    always @(posedge pix_clk) begin
        {a2, a1, a0} <= {a1, a0, copy_abort_tgl};
        if (tog_pix) n_tog = n_tog + 1;
    end

    task shift_phase;                  // 把像素域整体推后 1 ns（一次性，不改频率）
        begin
            PZ = 11;
            @(posedge pix_clk);
            PZ = 10;
        end
    endtask

    // 跑一轮：一个 commit → 一次 abort
    task one_abort;
        integer k;
        begin
            @(posedge axi_clk);
            commit_req <= 1'b1;
            @(posedge axi_clk);
            commit_req <= 1'b0;
            for (k = 0; k < 400; k = k + 1) @(posedge axi_clk);   // 等 start + 看门狗到期
        end
    endtask

    integer errors = 0;
    integer tot_abort = 0, tot_raw = 0, tot_lvl = 0, tot_tog = 0;
    integer p, a0c, r0c, l0c, t0c;
    integer phases_missed_raw = 0, phases_lvl_differs = 0, phases_tog_bad = 0;

    initial forever #400 vsync = ~vsync;   // 800 ns 一次的 vsync，喂 allow_rise/vsync_req 两条路

    initial begin : trial
        de = 1; blank_safe = 1;             // 常开的消隐窗口
        rst_n = 0;
        repeat (8) @(posedge axi_clk);
        rst_n = 1;
        repeat (20) @(posedge axi_clk);

        for (p = 0; p < 10; p = p + 1) begin
            a0c = n_abort; r0c = n_raw; l0c = n_lvl; t0c = n_tog;
            one_abort();
            one_abort();
            one_abort();
            $display("phase=%0dns  aborts=%0d  raw=%0d  lvl3=%0d  toggle=%0d",
                     p, n_abort-a0c, n_raw-r0c, n_lvl-l0c, n_tog-t0c);
            if (n_tog - t0c != n_abort - a0c) begin
                errors = errors + 1; phases_tog_bad = phases_tog_bad + 1;
            end
            if (n_raw - r0c < n_abort - a0c) phases_missed_raw = phases_missed_raw + 1;
            if (n_lvl - l0c != n_raw - r0c)  phases_lvl_differs = phases_lvl_differs + 1;
            shift_phase();
        end
        tot_abort = n_abort; tot_raw = n_raw; tot_lvl = n_lvl; tot_tog = n_tog;

        // A1：翻转同步器在每一个相位都必须不多不少
        if (phases_tog_bad != 0)
            $display("FAIL A1 toggle 在 %0d 个相位上数目不对", phases_tog_bad);
        // A2 / A3：负向对照必须抓到东西，否则说明这条问题记错了
        if (phases_missed_raw == 0)
            $display("FAIL A2 没有任何相位让裸采漏看 —— ISSUES #27 的现象描述要重写");
        if (phases_lvl_differs != 0)
            $display("FAIL A3 电平 3 级与裸采出现了不一致（%0d 个相位）—— 这条结论要重测",
                     phases_lvl_differs);

        $display("TOTAL aborts=%0d raw=%0d lvl3=%0d toggle=%0d  (raw-miss-phases=%0d, lvl-diff-phases=%0d)",
                 tot_abort, tot_raw, tot_lvl, tot_tog, phases_missed_raw, phases_lvl_differs);
        if (errors == 0 && phases_tog_bad == 0 && phases_missed_raw > 0 && phases_lvl_differs == 0)
            $display("PASS tb_v79_abort_toggle");
        else $display("FAIL tb_v79_abort_toggle errors=%0d", errors);
        $finish;
    end
endmodule
