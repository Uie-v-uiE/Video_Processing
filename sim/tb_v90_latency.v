`timescale 1ns/1ps
// 台架：src/rtl/video/frame_latency.v（V8-6 链路内时延打点）
//
// 这个模块产出的数字**会上文档、会被念给评委听**，所以判据的重点不是"有没有数"，而是
// "数会不会骗人"。四件事必须钉住：
//   ① 单位是**拍数**，PL 里不做除法 —— r49 就是因为在这里除了一个 100（不是 2 的幂）
//      而架出组合除法器，WNS −5.014（门禁拦下，ISSUES #58）。所以读数必须精确等于
//      台架自己数出来的拍差，一个 tick 都不能差。
//   ② 配对：commit→start→done→显示帧起始 走齐了才许出一次读数；顺序错、缺步、
//      上一轮的晚到事件，统统不许凑成一次"看起来合理"的测量（宁可 n_meas 不动）。
//   ③ 不回绕：差值为负/绕了半圈时报 32'hFFFF_FFFF 并置 clamped（钳位），
//      绝不报成一个很小的时延。
//   ④ max 只增不减，n_meas 如实数轮次。
//
// 台架自己也红过两次才修对，原因都写在下面 ev()/ev_sof() 旁边：
// `task ev; input which;` 默认**只有 1 bit** ⇒ ev(2) 被截成 0，copy_done 永不发生、所有读数停在 0；
// 加了 3 级同步之后收尾晚几拍，不等这几拍就会把"其实量到了"读成 0。**量具错了会把发现报成故障。**
module tb_v90_latency;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;                 // 100 MHz：一拍 10 ns，与 fclk0 同口径

    reg commit = 0, copy_start = 0, copy_done = 0;
    reg sof_tgl = 0;                       // 显示帧起始的**翻转位**（像素域转过来的样子）

    wire [31:0] c1, c2, tot, mx;
    wire [15:0] ncyc;
    wire        clamp;

    frame_latency dut (
        .axi_clk(clk), .axi_rst_n(rst_n),
        .commit(commit), .copy_start(copy_start), .copy_done(copy_done),
        .disp_sof_tgl(sof_tgl),
        .c1_cyc(c1), .c2_cyc(c2), .tot_cyc(tot), .max_cyc(mx),
        .n_meas(ncyc), .clamped(clamp)
    );

    integer errors = 0, t1, t2, t3, i, j, mx_keep;

    task chk;
        input [100*8:1] name;
        input cond;
        begin
            if (!cond) begin errors = errors + 1; $display("  FAIL %0s", name); end
        end
    endtask

    // 单拍脉冲事件。⚠ `which` 必须显式给位宽：task 的 input 默认 1 bit，
    // 写 `input which` 时 ev(2) 会被截成 0 ⇒ copy_done 永远不发（本文件 2026-09-24 就是这么全红过）。
    task ev;
        input [1:0] which;                 // 0 commit / 1 start / 2 done
        begin
            @(negedge clk);
            case (which) 0: commit = 1; 1: copy_start = 1; default: copy_done = 1; endcase
            @(negedge clk);
            commit = 0; copy_start = 0; copy_done = 0;
        end
    endtask

    // 翻转一次"显示帧起始"，然后等同步链灌满（3 级 + 收尾判定 ⇒ 数拍）再看读数
    task ev_sof;
        begin
            @(negedge clk); sof_tgl = ~sof_tgl;
            repeat (8) @(negedge clk);
        end
    endtask

    task wait_cyc;
        input integer n;
        begin repeat (n) @(negedge clk); end
    endtask

    initial begin
        rst_n = 0; commit = 0; copy_start = 0; copy_done = 0; sof_tgl = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        // ---- T1 复位后没有读数、没有假的最大值 ----
        chk("T1 复位：三段/总和/max/n_meas 全 0，clamped=0",
            c1 === 0 && c2 === 0 && tot === 0 && mx === 0 && ncyc === 0 && clamp === 0);

        // ---- T2 一轮干净的时序：读数必须**恰好等于拍差**（单位=拍，不做除法）----
        @(negedge clk); t1 = dut.cyc;  ev(0);
        wait_cyc(500);
        @(negedge clk); t2 = dut.cyc;  ev(1);
        wait_cyc(1500);
        @(negedge clk); t3 = dut.cyc;  ev(2);
        wait_cyc(8000);
        ev_sof();
        chk("T2 c1 恰好等于 commit→start 的拍差（±事件脉冲自身的 1 拍）",
            (c1 >= t2 - t1 - 1) && (c1 <= t2 - t1 + 1));
        chk("T2b c2 恰好等于 start→done 的拍差",
            (c2 >= t3 - t2 - 1) && (c2 <= t3 - t2 + 1));
        chk("T2c tot 覆盖整段（≥ c1+c2+8000 且 < c1+c2+8200：同步链那几拍算在内）",
            tot >= c1 + c2 + 8000 && tot <= c1 + c2 + 8200);
        chk("T2d 第一轮 max == tot，n_meas == 1，没钳位",
            mx == tot && ncyc == 1 && clamp == 0);

        // ---- T3 时序乱了序：先 start / 先 done 都不许出数 ----
        ev(1); wait_cyc(100);              // 没有 commit 配对的 start
        ev(2); wait_cyc(100);              // 没有起点的 done
        ev_sof();
        chk("T3 缺 commit 的一串事件不产生读数（n_meas 仍是 1）", ncyc == 1);

        // ---- T4 第二轮更小：tot 跟着变小，但 max 保留历史最大 ----
        @(negedge clk); t1 = dut.cyc; ev(0);
        wait_cyc(100);  ev(1);
        wait_cyc(100);  ev(2);
        wait_cyc(200);  ev_sof();
        chk("T4 第二轮读数被记下（n_meas=2）且 tot 明显小于第一轮",
            ncyc == 2 && tot < 4000 && tot > 300);
        chk("T4b max 不被小值覆盖（演示时要念的就是这个数）", mx == (tot < mx ? mx : tot) && mx >= 4000);

        // ---- T5 commit 一刷新就清配对标记：旧轮晚到的 done 不许凑数 ----
        ev(0); wait_cyc(100);
        ev(1); wait_cyc(50);               // 这一轮走到 start
        ev(0); wait_cyc(50);               // 新 commit 来了 ⇒ 上一轮作废
        ev(2); wait_cyc(50);               // 这个 done 属于被作废的那一轮
        ev_sof();
        chk("T5 作废轮次不会被晚到的 done 凑成一次读数（n_meas 仍是 2）", ncyc == 2);

        // ---- T6 没搬完的一帧不出读数 ----
        ev(0); wait_cyc(100);
        ev(1); wait_cyc(100);
        ev_sof();
        chk("T6 缺 copy_done 的一帧不产生读数（n_meas 仍是 2）", ncyc == 2);

        // ---- T7 钳位：把 t_commit 强行设到"未来"，让差值变负 ⇒ 必须报 0xFFFFFFFF 且置标志 ----
        @(negedge clk);
        mx_keep = mx;
        dut.t_commit = dut.cyc + 32'd100_000;     // 人为制造一次倒挂（时序异常/绕圈的等价形状）
        dut.have_commit = 1'b1; dut.have_start = 1'b1; dut.have_done = 1'b1;
        dut.t_start  = dut.cyc;
        dut.t_done   = dut.cyc;
        ev_sof();
        chk("T7 差值为负 ⇒ 三项报 32'hFFFF_FFFF 并置 clamped（**绝不回绕成小数**）",
            clamp == 1 && (c1 === 32'hFFFF_FFFF || c2 === 32'hFFFF_FFFF || tot === 32'hFFFF_FFFF));
        chk("T7b 钳位轮次仍如实计数（读数是否可用由 clamped 说，不由 n_meas 说）", ncyc == 3);
        // 这一条是台架逼出来的设计缺陷：钳位值 0xFFFFFFFF 一旦进过 max，
        // "最大时延"就永远读不出真数了 ⇒ RTL 里 max 只认真读数。
        chk("T7c 钳位的那一轮不污染 max（一次倒挂不许把最大时延永远钉在 0xFFFFFFFF）",
            mx === mx_keep);

        $display("");
        $display("口径提醒：本模块量的是 PL 内部（commit 之后到该帧开始扫描），单位是 axi 拍数；");
        $display("   上位机编码与网线传输不在内 ⇒ 对外只能说「链路内时延（PL 侧）」，");
        $display("   且第三段（等扫描）的分辨率是一个显示帧 ⇒ 报数必须带 ±1 帧。");
        $display("   换算成时间戳在 src/host/health_read.mjs 里做（1 拍 = 10 ns，一个常量）。");
        $display("");
        if (errors == 0) $display("PASS tb_v90_latency");
        else             $display("FAIL tb_v90_latency errors=%0d", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL tb_v90_latency timeout");
        $finish;
    end
endmodule
