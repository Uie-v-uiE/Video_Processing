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
    wire [31:0] qc1, qc2, qtot, qmax, qstat, qms;
    // V8-5：拍数→ms 的逐次除法那一组（OSD 的 Latency 一格就吃这四个口）
    wire [15:0] lms;
    wire        lvalid, lsticky, ltog;

    frame_latency dut (
        .axi_clk(clk), .axi_rst_n(rst_n),
        .commit(commit), .copy_start(copy_start), .copy_done(copy_done),
        .disp_sof_tgl(sof_tgl), .arm(arm),
        .c1_cyc(c1), .c2_cyc(c2), .tot_cyc(tot), .max_cyc(mx),
        .n_meas(ncyc), .clamped(clamp),
        .q_c1(qc1), .q_c2(qc2), .q_tot(qtot), .q_max(qmax), .q_stat(qstat),
        .q_ms(qms),                      // lane24：与 q_tot 同一轮的 ms（T16 判它）
        // V8-5：OSD 那一口的四个观测对象
        .lat_ms(lms), .lat_valid(lvalid), .lat_sticky(lsticky), .lat_tog(ltog)
    );

    // ---- ms 换算这一组的监视器（T12/T13 用）----
    reg  lt_prev = 0;                      // lat_tog 的上一次电平
    integer lt_edges = 0;                  // 翻转了几次 = 完成了几次换算
    reg     torn = 0;                      // 除法没跑完期间 lat_ms 被动过 ⇒ 半截数被写过
    reg  [15:0] lms_hold;
    always @(posedge clk) begin
        if (rst_n) begin
            if (ltog !== lt_prev) begin lt_edges = lt_edges + 1; lt_prev = ltog; end
            if (dut.drun && (lms !== lms_hold)) torn = 1;
        end
        lms_hold = lms;
    end

    integer errors = 0, t1, t2, t3, i, j, mx_keep;
    integer a1, a2, a3, bad, nchk;
    integer n_edge0, npair, nbadpair, nskip;                       // V8-5：T14 用的"翻转次数基线"
    reg [31:0] big;                        // V8-5：force 拍号时用的临时值

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

        // ================= V8-5：拍数→ms 的逐次除法（OSD 的 Latency 一格吃这四个口）=================
        // 判的到底是什么：
        //  T11 商必须**恰好**等于 tot/100000 —— 拿台架自己的整数除法独立算一遍，不抄 RTL 的余数；
        //      这条同时钉住"收尾那一位"（RTL 里 quo 是非阻塞的，最后一位在本拍还没进去，
        //      写错一个字符屏上就永远差 1 ms，而且差在"看起来对"的那一位上）。
        //  T12/T15 越界必须**饱和在 9999 ms**，不许回卷成小数（回卷 = 把"慢得离谱"报成
        //      "几乎没延迟"）；屏上只有三位，osd_overlay 自己再夹 999（那边有独立判据 T2h）。
        //  T13 除法跑一半时 lat_ms 不许动 ⇒ 跨域那一级拿到的永远是完整数（#59 同一类谎）。
        //  T14 一轮一次翻转：少翻 = OSD 停在旧值，多翻 = 撕开两组测量。
        //  T15 本轮配对被钳位 ⇒ lat_sticky=1（顶层再与一下，屏上画 `--`）；
        //      下一轮干净就必须回 0 —— 它**不是**会话粘滞位 `clamped`，两者故意不一样。
        // 相位扫描最后一轮的除法还没跑完 ⇒ 先等它翻完，再取基线
        //（第一版没等：基线少算一次 ⇒ T14 把"两轮翻两次"判成翻了三下，红的是台架不是 RTL）
        wait_cyc(50);
        n_edge0 = lt_edges;
        ev(0);
        wait_cyc(1000);   ev(1);
        wait_cyc(118000); ev(2);
        wait_cyc(200);    ev_sof();
        wait_cyc(60);                          // 除法 32 拍 + 收尾
        $display("DBG_T11 tot=%0d exp=%0d lms=%0d valid=%0d sticky=%0d edges=%0d",
                 tot, (tot / 100000), lms, lvalid, lsticky, lt_edges);
        chk("T11 商恰好等于 tot/100000（台架独立整数除法）", lms === (tot / 100000));
        chk("T11b 这一轮真的除出了非零毫秒（否则 T11 可能一直在比 0）", lms >= 1);
        chk("T11c 测量有效位亮、本轮没钳位", lvalid === 1'b1 && lsticky === 1'b0);

        // T12 造一个 2000 ms 的轮次：把拍号强行推到 2 亿拍之后再去打显示帧起始
        ev(0);
        wait_cyc(50);     ev(1);
        wait_cyc(50);     ev(2);
        big = dut.cyc + 32'd200_000_000;
        force dut.cyc = big;
        @(negedge clk); sof_tgl = ~sof_tgl;
        repeat (8) @(negedge clk);
        release dut.cyc;
        wait_cyc(60);
        $display("DBG_T12 tot=%0d lms=%0d sticky=%0d edges=%0d base=%0d", tot, lms, lsticky, lt_edges, n_edge0);
        // 本模块的饱和点是 **9999 ms**（四位数，读回口也用得上）；屏上那一格只有三位，
        // 由 osd_overlay 自己再夹到 999 —— 两件事各有判据：这里钉 9999，
        // tb_osd_lines 的 T2h 钉"5000 ms 上屏画 999"。
        chk("T12 两千毫秒的轮次原样报出（未越本模块的 9999 饱和点）",
            lms === 16'd2000 && lvalid === 1'b1);

        chk("T13 除法没跑完期间 lat_ms 从没被动过（跨域拿到的是完整数）", torn === 1'b0);
        chk("T14 两轮各翻一次：翻转次数 = 完成的换算次数", lt_edges === n_edge0 + 2);

        // T15 倒挂的一轮：拍号往回走 ⇒ diff 判为钳位 ⇒ 本轮不可信（sticky=1）
        ev(0);
        wait_cyc(50);     ev(1);
        wait_cyc(50);     ev(2);
        big = dut.cyc - 32'd1000;
        force dut.cyc = big;
        @(negedge clk); sof_tgl = ~sof_tgl;
        repeat (8) @(negedge clk);
        release dut.cyc;
        wait_cyc(60);
        $display("DBG_T15 tot=%0d lms=%0d valid=%0d sticky=%0d torn=%0d edges=%0d", tot, lms, lvalid, lsticky, torn, lt_edges);
        chk("T15 配对被钳位的那一轮：lat_sticky 亮（屏上那一格因此画 --）", lsticky === 1'b1);
        // tot 被钳成满量程 ⇒ 商是 4 万多的 ms ⇒ 必须停在 9999。这条是**真造出来的越界**，
        // 不是拿常数 1'b1 糊出来的空判据（#60 那一课：不许有条判据永远不会红）。
        chk("T15b 越界的一轮饱和在 9999，不回卷成小数", lms === 16'd9999);
        ev(0);
        wait_cyc(200);    ev(1);
        wait_cyc(200);    ev(2);
        wait_cyc(200);    ev_sof();
        wait_cyc(60);
        chk("T15c 下一轮干净就必须回 0（sticky 只是本轮的账，不是会话的账）",
            lsticky === 1'b0 && lvalid === 1'b1);
        chk("T15d 会话粘滞位仍然是 1（两件事故意分开，别让 OSD 拿它当筛子）", clamp === 1'b1);
        $display("T11_15 lms=%0d edges=%0d torn=%0d clamp=%0d", lms, lt_edges, torn, clamp);

        // ---- T16 lane24 那一口：与 q_tot **同一轮**的毫秒数必须等于整数除法 ----
        // 这一条是给板上的 OSD 用的：屏上 `Latency:` 画的 ms 与上位机 lane24 读的是同一个数，
        // 而 lane27 的 q_tot 是同一轮武装抄走的拍数 ⇒ 两者必须互相推得出来。
        // pair_ok（qms[17]）为 0 的那一次（正好撞进除法那 32 拍）不下结论，
        // 但必须**至少有一次**能下结论，否则这条判据就是空判据（#60 那一课）。
        @(negedge clk); arm = 1; @(negedge clk); arm = 0;
        npair = 0; nbadpair = 0; nskip = 0;
        for (i = 0; i < 40; i = i + 1) begin
            ev(0); ev(1); ev(2); ev_sof();
            // 除法要 32 拍 ⇒ 每 7 次里留一次**故意不等**（撞进除法窗口，pair_ok 必须给 0），
            // 其余等满 40 拍再武装（配对可用）。两种都要发生，否则"pair_ok 会保护"这句话
            // 本身就是一条从没走过分支的判据。
            if ((i % 7) != 3) wait_cyc(40);
            @(negedge clk); arm = 1; @(negedge clk); arm = 0;
            if (qtot !== 32'hFFFF_FFFF && qms[17]) begin
                npair = npair + 1;
                if (qms[15:0] !== (qtot / 32'd100000)) nbadpair = nbadpair + 1;
            end
            if (!qms[17]) nskip = nskip + 1;
            if (1'b0) begin
                $display("T16 pair qtot=%0d qms=%0d exp=%0d sticky=%0d",
                         qtot, qms[15:0], (qtot / 32'd100000), qms[16]);
            end
        end
        chk("T16 lane24 的 ms 与同一轮 q_tot 的整数除法一致（屏上那格的机器对照）",
            nbadpair == 0);
        chk("T16b 这条判据真的判到了配对（npair>0，否则是空判据）", npair > 0);
        chk("T16c 也真的撞到过除法窗口（nskip>0 ⇒ pair_ok 那一位不是装饰）", nskip > 0);
        $display("T16 npair=%0d nskip=%0d nbad=%0d", npair, nskip, nbadpair);

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
        #60_000_000;                         // V8-5 加了 12 万拍那一轮 ⇒ 看门狗跟着放宽
        $display("FAIL tb_v90_latency timeout");
        $finish;
    end
endmodule
