`timescale 1ns/1ps
// tb_commit_strobe.v —— ISSUES #171 的尺子（模块级，秒级就跑完）。
//
// 症状链：`pl_video_top.v` 里那段
//     else if (frame_ready && eth_link_pix) eth_has_frame <= 1'b1;
//     else if (copy_abort_pix)              eth_has_frame <= 1'b0;   // ← 永远轮不到
// 之所以轮不到：`frame_commit_lock` 的 `frame_ready_pix` **只置 1、只有像素域异步复位才清零**
// （`:133-136`）⇒ 链路活着的时候第一个条件天天为真，第二个分支不可达 ⇒ abort 之后那张撕裂帧
// 照样显示、`status` 里的 `eth_ready` 照样读 1（上位机以为换帧成功了）。
//
// 所以这条尺子量的是**脉冲宽度**，不是"有没有置起来"：
//   B1 一次提交之后 `frame_ready_pix` 必须**只亮一个像素拍**（是 strobe 不是 level）；
//   B2 第二次提交必须**再**出现一个上升沿（level 语义下第二次提交毫无变化 ⇒ 同根因的第二条）。
//   A 组是地板：现行真行为（窗口重开才起拍、abort 真发生、copy_active 真被清、翻转 CDC 契约还在）
//   必须先绿，否则 B 组的红说明不了任何事（本项目规矩：基线条目不绿，任何"红"都不算数）。
//
// 看门狗是**真触发**的：模块带 `WD_CYC` 参数（顶层用默认 200 万 ⇒ 板上 20 ms），这里传 40，
// 让 `copy_active` 悬着不 done 就必然溢出 —— 走真实路径，不需要层次 force。
// ⚠ 两次提交之间必须**重开消隐窗口**（`allow_rise`/`vsync_req` 才是起拍条件；窗口一直开着就
//   不会有第二个沿）—— 第一版不知道这件事，A3/A4/A6 全红，红的却是我的台架。
// ⚠ 名字与说明都写 ASCII：定宽字段被多字节中文从左边截掉，`grep` 就找不到那条（r94 撞过两次）。
module tb_commit_strobe;
    localparam integer WD = 40;

    reg axi_clk = 0, pix_clk = 0, axi_rst_n = 0, pix_rst_n = 0;
    always #5  axi_clk = ~axi_clk;         // 100 MHz
    always #10 pix_clk = ~pix_clk;         // 50 MHz，与 axi 同相（上升沿每 20 ns 重合一次 ——
                                           // 这正是 v7.9 注释里说的撞车几何，不要有意避开它）

    reg commit_req = 0, de = 0, vsync = 0, blank_safe = 0, copy_busy = 0, copy_done = 0;
    reg [31:0] commit_base = 32'h1000_0000;
    wire start_copy, allow_copy_axi, copy_abort, abort_tgl;
    wire [31:0] copy_base;
    wire frame_ready_pix;

    frame_commit_lock #(.IMG_H(300), .DISP_H(600), .WD_CYC(WD)) u (
        .axi_clk(axi_clk), .axi_rst_n(axi_rst_n),
        .commit_req(commit_req), .commit_base(commit_base),
        .pix_clk(pix_clk), .pix_rst_n(pix_rst_n),
        .de(de), .vsync(vsync), .blank_safe(blank_safe),
        .copy_busy(copy_busy), .copy_done(copy_done),
        .start_copy(start_copy), .copy_base(copy_base),
        .frame_ready_pix(frame_ready_pix), .allow_copy_axi(allow_copy_axi),
        .copy_abort(copy_abort), .abort_tgl(abort_tgl));

    integer fails = 0, checks = 0;
    task chk;
        input [8*34-1:0] name;
        input            ok;
        input [8*64-1:0] note;
        input integer    v1;
        begin
            checks = checks + 1;
            if (ok) $display("  PASS %0s | %0s | %0d", name, note, v1);
            else    begin fails = fails + 1; $display("  FAIL %0s | %0s | %0d", name, note, v1); end
        end
    endtask

    // 观察量
    integer n_start = 0, n_abort = 0, n_tgl = 0, n_ready_hi = 0, n_ready_rise = 0;
    integer run_hi = 0, max_hi = 0;
    reg ready_prev = 0, tgl_prev = 0;
    always @(posedge pix_clk) begin
        if (frame_ready_pix && !ready_prev) n_ready_rise = n_ready_rise + 1;
        if (frame_ready_pix) begin n_ready_hi = n_ready_hi + 1; run_hi = run_hi + 1;
                                  if (run_hi > max_hi) max_hi = run_hi; end
        else                  run_hi = 0;
        ready_prev = frame_ready_pix;
    end
    always @(posedge axi_clk) begin
        if (start_copy) n_start = n_start + 1;
        if (copy_abort) n_abort = n_abort + 1;
        // 每次 copy_abort 必须让 abort_tgl **恰好翻一次**（v7.9 翻转式脉冲同步器的契约，
        // 也是顶层 `copy_abort_pix = ab1 ^ ab2` 收得到一拍的依据）—— A7 钉它。
        if (abort_tgl !== tgl_prev) begin n_tgl = n_tgl + 1; tgl_prev = abort_tgl; end
    end

    task pulse_commit;
        begin
            @(posedge axi_clk); commit_req <= 1;
            @(posedge axi_clk); commit_req <= 0;
        end
    endtask
    task pulse_done;
        begin
            @(posedge axi_clk); copy_done <= 1;
            @(posedge axi_clk); copy_done <= 0;
        end
    endtask
    // 重开消隐窗口：`start_copy` 只在 allow 的**上升沿**（或 vsync 沿）起拍 ——
    // 第一版把 commit 放在已经开着的窗口里，于是 A1 报 0 而 A3 报 1：那是我不懂这台机器的
    // 起拍条件，不是缺陷。⇒ 每次提交的正确顺序是"先挂 pending，再重开窗口"。
    task reopen_window;
        begin
            blank_safe = 0; repeat (8) @(posedge axi_clk);
            blank_safe = 1; repeat (8) @(posedge axi_clk);
        end
    endtask
    task do_commit;                 // 挂上 commit_req，然后重开窗口去触发那个上升沿
        begin
            pulse_commit;
            reopen_window;
        end
    endtask

    integer i, n_start_before, n_rise_before, n_rise_at;
    initial begin
        repeat (6) @(posedge axi_clk);
        axi_rst_n = 1; pix_rst_n = 1;
        repeat (6) @(posedge axi_clk);

        // ================= 第一次提交：地板 + 脉冲宽度 =================
        // ⚠ 采样窗口必须**贴着 copy_done 之后**开：第一版在 12 个像素拍之后才去读电平，
        //   于是"修成脉冲"之后 A2 反倒红了 —— 修好了却被判成坏，这是最糟的一种假红（尺子的错）。
        blank_safe = 1; repeat (8) @(posedge axi_clk);
        do_commit;
        for (i = 0; i < 16 && n_start < 1; i = i + 1) @(posedge axi_clk);
        chk("A1_start_copy_issued", n_start >= 1, "start_copy pulses at the window rising edge", n_start);
        repeat (4) @(posedge axi_clk);
        n_rise_before = n_ready_rise; max_hi = 0; run_hi = 0;
        pulse_done;
        repeat (30) @(posedge pix_clk);
        chk("A2_commit_raises_ready", n_ready_rise > n_rise_before,
            "a commit must still raise frame_ready_pix (floor for B1)", n_ready_rise - n_rise_before);
        chk("B1_ready_is_one_pix_wide", (max_hi >= 1) && (max_hi <= 1),
            "longest frame_ready_pix run after a commit; >1 = level = #171", max_hi);

        // ================= 第二次提交（正常完成）：必须再有一个沿 =================
        n_start_before = n_start; n_rise_before = n_ready_rise; max_hi = 0; run_hi = 0;
        do_commit;
        for (i = 0; i < 24 && n_start == n_start_before; i = i + 1) @(posedge axi_clk);
        repeat (2) @(posedge axi_clk);
        pulse_done;
        repeat (30) @(posedge pix_clk);
        chk("B2_second_commit_re_rises", n_ready_rise > n_rise_before,
            "rising edges after the 2nd commit; level semantics show none", n_ready_rise - n_rise_before);
        chk("B3_second_commit_also_strobe", (max_hi >= 1) && (max_hi <= 1),
            "2nd commit pulse width in pix cycles", max_hi);

        // ================= 看门狗：起拍后不给 done ⇒ 恰好一次 abort =================
        n_start_before = n_start;
        do_commit;
        for (i = 0; i < 24 && n_start == n_start_before; i = i + 1) @(posedge axi_clk);
        chk("A3_third_copy_started", n_start >= n_start_before + 1,
            "third start_copy before the watchdog runs out", n_start);
        n_rise_at = n_ready_rise;
        for (i = 0; i < WD + 20; i = i + 1) @(posedge axi_clk);
        chk("A4_abort_fired_once", n_abort == 1, "copy_abort pulses exactly once per watchdog", n_abort);
        chk("A6_abort_clears_active", u.copy_active === 1'b0, "u.copy_active must be 0 after abort", u.copy_active);
        chk("A5_toggle_matches_abort", (n_tgl == n_abort) && (n_abort == 1),
            "abort_tgl toggles once per copy_abort (v7.9 contract)", n_tgl);
        // 这一路上没有 copy_done ⇒ 不该出现任何"提交沿"（防把 abort 当成换帧成功）
        chk("A7_no_spurious_commit_edge", n_ready_rise == n_rise_at,
            "commit edges caused by the watchdog alone (must be 0)", n_ready_rise - n_rise_at);

        // ================= abort 之后还能恢复，而且仍是脉冲 =================
        n_start_before = n_start; n_rise_before = n_ready_rise; max_hi = 0; run_hi = 0;
        do_commit;
        for (i = 0; i < 24 && n_start == n_start_before; i = i + 1) @(posedge axi_clk);
        pulse_done;
        repeat (30) @(posedge pix_clk);
        chk("A8_recovers_after_abort", (n_start >= n_start_before + 1) && (n_ready_rise > n_rise_before),
            "after an abort the next commit still starts and pulses ready", n_start);
        chk("B4_still_one_pix_wide_after_abort", (max_hi >= 1) && (max_hi <= 1),
            "post-abort commit pulse width", max_hi);

        $display("checks=%0d errors=%0d", checks, fails);
        if (fails == 0) $display("TB RESULT PASS");
        else            $display("TB RESULT FAIL");
        $finish;
    end

    initial begin
        #400_000;
        $display("  FAIL Z_timeout | never finished checks=%0d fails=%0d", checks, fails);
        $display("TB RESULT FAIL timeout");
        $finish;
    end
endmodule
