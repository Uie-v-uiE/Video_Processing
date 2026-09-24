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
    // #59：读回口用的那一组快照
    reg         arm = 0;
    wire [31:0] qc1, qc2, qtot, qmax, qstat;

    frame_latency dut (
        .axi_clk(clk), .axi_rst_n(rst_n),
        .commit(commit), .copy_start(copy_start), .copy_done(copy_done),
        .disp_sof_tgl(sof_tgl), .arm(arm),
        .c1_cyc(c1), .c2_cyc(c2), .tot_cyc(tot), .max_cyc(mx),
        .n_meas(ncyc), .clamped(clamp),
        .q_c1(qc1), .q_c2(qc2), .q_tot(qtot), .q_max(qmax), .q_stat(qstat)
    );

    integer errors = 0, t1, t2, t3, i, j, mx_keep;
    integer a1, a2, a3, bad, nchk;

    // 0 = 这组含钳位值、判不了；1 = 可信且恒等式成立；2 = 可信但恒等式破了
    function [1:0] id_ok;
        input [31:0] x1, x2, xt;
        begin
            if (x1 === 32'hFFFF_FFFF || x2 === 32'hFFFF_FFFF || xt === 32'hFFFF_FFFF)
                id_ok = 2'd0;
            else id_ok = (xt >= x1 + x2) ? 2'd1 : 2'd2;
        end
    endfunction

    task chk;
        input [100*8:1] name;
        input cond;
        begin
            // `!== 1'b1` 而不是 `!cond`：cond 为 X 时 `if (!cond)` 两个分支都不走 ⇒
            // **判据会因为一个未初始化的计数器而静默变绿**（本文件 2026-09-24 就是这么绿了一次：
            // nchk 没清零 ⇒ X ⇒ T10b/T10c 一条都没判却报 PASS）。X 一律当红。
            if (cond !== 1'b1) begin errors = errors + 1; $display("  FAIL %0s", name); end
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

        // ---- T8/T8b/T8c/T9/T10：#59 的快照口 ----
        // 为什么要它：这五个字之间有恒等式 `tot ≥ c1 + c2`（c3 = 等扫描，非负），
        // 而 live 寄存器每轮都在换。上位机是**逐 lane 各读一次**（一次 mwr + 一次 mrd，
        // 五个 lane 要几毫秒），推流时每 ~16 ms 换一轮 ⇒ 读到的是不同轮的碎片。
        // r50 板级 11 组读数里 4 组破坏恒等式（`build/lat_tearing_r50.txt`），
        // 而 RTL 里这五个值是在**同一个 always 块、同一拍**写的 ⇒ 单次读一定自洽，
        // 所以错的是读法不是硬件 —— 这条判据就是钉住"读法"这一半。
        ev(0); wait_cyc(40); ev(1); wait_cyc(60); ev(2); ev_sof();     // 先跑一轮干净的
        chk("T8 起点：live 有可用读数且未钳位（否则下面的『不动』是空的）",
            tot != 0 && tot !== 32'hFFFF_FFFF);
        @(negedge clk); arm = 1; @(negedge clk); arm = 0;               // 一拍武装 = 同时抄五个
        a1 = qc1; a2 = qc2; a3 = qtot;
        chk("T8b 刚抄完：快照逐字等于当时的 live（五口同源）",
            qc1 === c1 && qc2 === c2 && qtot === tot && qmax === mx && qstat[31:16] === ncyc);
        ev(0); wait_cyc(90); ev(1); wait_cyc(40); ev(2); ev_sof();      // 再来一轮，live 必须换
        chk("T8c 又跑了一轮，live 确实更新了（否则『快照不动』没有对照意义）",
            tot !== a3);
        chk("T8d 没有再武装 ⇒ 快照一动不动（读回口拿到的是同一轮）",
            qc1 === a1 && qc2 === a2 && qtot === a3);
        @(negedge clk); arm = 1; @(negedge clk); arm = 0;
        chk("T9 再武装一次，快照跟到最新一轮",
            qc1 === c1 && qc2 === c2 && qtot === tot);
        // ⚠ 判"这一组可用"不能用 qstat[0]：`clamped` 是**整个会话的粘滞位**（T7 注过一次倒挂
        //    就永远是 1），拿它当"本轮无效"的筛子会让判据要么假红、要么**一条都没判就绿**
        //    （T10b 第一版就是这么假绿的）。本轮可不可信只看这一组自己有没有钳位值。
        chk("T10 快照这组满足恒等式 tot >= c1 + c2（板级破的就是它）",
            id_ok(qc1, qc2, qtot));
        // T10b **相位扫描**：轮次正在跑的时候，在任意一拍武装，抄到的一组都必须自洽。
        //      这条是判据里唯一会碰到"武装那一拍正好与写回同一拍"的相位，
        //      少了它，"快照"这个说法只在采样点错开时才成立 —— 那不够。
        bad = 0; nchk = 0;      // ⚠ Verilog 的 integer 默认是 X，不清零就是把判据交给 X
        for (i = 0; i < 600; i = i + 1) begin
            @(negedge clk); arm = 1; @(negedge clk); arm = 0;
            if (id_ok(qc1, qc2, qtot) == 2) bad = bad + 1;   // 2 = 这组可信但恒等式破了
            if (id_ok(qc1, qc2, qtot) != 0) nchk = nchk + 1;  // 真的判过几条（不许空跑）
            if (i % 60 == 59) begin ev(0); ev(1); ev(2); ev_sof(); end
        end
        chk("T10b 600 个相位各处武装，抄到的一组都不破坏恒等式", bad == 0);
        chk("T10c 相位扫描**真的判到了**可信组（否则 T10b 的绿是空的）", nchk > 50);
        // 计数打成 ASCII：判据的数字要能被 grep/脚本读走，不该压在中文里（本仓台架的规矩）
        $display("T10b phases=600 trusted=%0d violated=%0d snapshot_n=%0d",
                 nchk, bad, qstat[31:16]);

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
