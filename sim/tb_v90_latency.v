`timescale 1ns/1ps
// 台架：src/rtl/video/frame_latency.v（V8-6 链路内时延打点）
//
// 这个模块产出的数字**会上文档、会被念给评委听**，所以判据的重点不是"有没有数"，而是
// "数会不会骗人"。三件事必须钉住：
//   ① 配对：只有 commit→start→done→显示帧起始 这条链走齐了才许出一次读数；
//      任何一步缺了或乱了序，宁可**不出数**（n_meas 不动），也不许报一个看起来合理的数。
//   ② 单位：µs 换算的除数只有一个来源（AXI_CYC_PER_US）⇒ 同一段激励喂两台不同参数的 DUT，
//      读数必须差恰好 10 倍（这一条是"改了 fclk 只改一处"那句注释的凭据）。
//   ③ 溢出：到顶必须钳位并置 saturated，**不许回绕** —— 回绕会把一次很大的等待报成很小的时延。
//
// 两台 DUT：
//   u_norm : AXI_CYC_PER_US=100（fclk0=100 MHz 的真实口径）、SAT_US=65535
//   u_small: AXI_CYC_PER_US=10、SAT_US=200（让"溢出"这一件事在几微秒的仿真里就能造出来）
module tb_v90_latency;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;                 // 100 MHz：一拍 10 ns，与 fclk0 同口径

    reg commit = 0, copy_start = 0, copy_done = 0;
    reg sof_tgl = 0;                       // 显示帧起始的**翻转位**（像素域转过来的样子）

    wire [15:0] n_l1, n_l2, n_l3, n_tot, n_max, n_cnt;
    wire        n_sat;
    wire [15:0] s_l1, s_l2, s_l3, s_tot, s_max, s_cnt;
    wire        s_sat;

    frame_latency #(.AXI_CYC_PER_US(100), .SAT_US(16'hFFFF)) u_norm (
        .axi_clk(clk), .axi_rst_n(rst_n),
        .commit(commit), .copy_start(copy_start), .copy_done(copy_done),
        .disp_sof_tgl(sof_tgl),
        .l1_us(n_l1), .l2_us(n_l2), .l3_us(n_l3), .tot_us(n_tot),
        .max_us(n_max), .n_meas(n_cnt), .saturated(n_sat)
    );
    // u_small 的口径故意只把"除数"改成 10（不是同时把上限缩小）：
    // 这样 T2b 的"读数恰好 10 倍"才是在测除数本身，而不是撞在钳位上；
    // 钳位由 T5 用一段 5000 µs 的间隔单独造出来。
    frame_latency #(.AXI_CYC_PER_US(10), .SAT_US(16'd4000)) u_small (
        .axi_clk(clk), .axi_rst_n(rst_n),
        .commit(commit), .copy_start(copy_start), .copy_done(copy_done),
        .disp_sof_tgl(sof_tgl),
        .l1_us(s_l1), .l2_us(s_l2), .l3_us(s_l3), .tot_us(s_tot),
        .max_us(s_max), .n_meas(s_cnt), .saturated(s_sat)
    );

    integer errors = 0, i;
    task chk;
        input [100*8:1] name;
        input cond;
        begin
            if (!cond) begin errors = errors + 1; $display("  FAIL %0s", name); end
        end
    endtask

    // 单拍脉冲事件（下一拍自动撤掉，免得两个事件粘在同一拍）
    // ⚠ `which` 必须显式给位宽：task 的 input 默认**只有 1 bit**，
    //   写成 `input which` 时 ev(2) 会被截成 0 ⇒ copy_done 永远不发，
    //   整个模块一次数都收不齐、所有读数停在 0 —— 台架自己坏得毫不起眼（2026-09-24 撞到）。
    task ev;
        input [1:0] which;                 // 0 commit / 1 start / 2 done
        begin
            @(negedge clk);
            case (which) 0: commit = 1; 1: copy_start = 1; default: copy_done = 1; endcase
            @(negedge clk);
            commit = 0; copy_start = 0; copy_done = 0;
        end
    endtask

    task ev_sof;
        begin
            @(negedge clk); sof_tgl = ~sof_tgl;
            // 收尾要等同步链灌满：DUT 里 `disp_sof_tgl` 先过 3 级（ASYNC_REG 链）再做边沿检测，
            // 所以翻转之后要 4~5 拍才看得到读数。以前只有一级 prev，第 2 拍就有结果 ——
            // 台架若不等这几拍，会把"其实量到了"读成 0（本文件 2026-09-24 就是这么红过一次）。
            repeat (6) @(negedge clk);
        end
    endtask

    task wait_cyc;
        input integer n;
        begin
            repeat (n) @(negedge clk);
        end
    endtask

    initial begin
        rst_n = 0; commit = 0; copy_start = 0; copy_done = 0; sof_tgl = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        // ---- T1 复位后没有读数、也没有假的最大值 ----
        chk("T1 复位：三段与总和为 0，n_meas=0，saturated=0",
            n_l1 === 0 && n_l2 === 0 && n_l3 === 0 && n_tot === 0 &&
            n_max === 0 && n_cnt === 0 && n_sat === 0);

        // ---- T2 一轮干净的时序：500 / 1500 / 8000 拍 ----
        // 100 MHz ⇒ 500 拍 = 5 µs；1500 拍 = 15 µs；8000 拍 = 80 µs；总 10000 拍 = 100 µs
        ev(0); wait_cyc(500);
        ev(1); wait_cyc(1500);
        ev(2); wait_cyc(8000);
        ev_sof();
        $display("DBG norm  l1=%0d l2=%0d l3=%0d tot=%0d max=%0d cnt=%0d sat=%0b",
                 n_l1, n_l2, n_l3, n_tot, n_max, n_cnt, n_sat);
        $display("DBG small l1=%0d l2=%0d l3=%0d tot=%0d max=%0d cnt=%0d sat=%0b",
                 s_l1, s_l2, s_l3, s_tot, s_max, s_cnt, s_sat);
        chk("T2 一轮量完：l1=5 l2=15 l3=80 tot=100 µs（u_norm，100 拍/µs）",
            n_l1 == 5 && n_l2 == 15 && n_l3 == 80 && n_tot == 100 && n_cnt == 1);
        // ②单位：同一串激励在 10 拍/µs 的那台上必须大 10 倍，允许 ±1 µs 的**舍入口径差**：
        //   总和是"先加拍数、一次舍入"，三段是"各自舍入" ⇒ parts 相加可能与 tot 差 1 µs。
        //   这是刻意的（模块头部写了），别改成"逐段相加得总数"——那样一次钳位就会把总和撑成假数。
        chk("T2b 单位来自参数：u_small（10 拍/µs）读数是 u_norm 的 10 倍（±10 µs）",
            s_l1 == n_l1*10 && s_l2 == n_l2*10 &&
            s_tot >= n_tot*10 - 10 && s_tot <= n_tot*10 + 10);
        chk("T2c 除数不同不会改变 n_meas（两台各量一轮）", n_cnt == 1 && s_cnt == 1);

        // ---- T3 时序乱了序：先 start 后 commit ⇒ 不许出数 ----
        ev(1); wait_cyc(100);              // copy_start，但没有配对的 commit
        ev(2); wait_cyc(100);              // copy_done，同样没有起点
        ev_sof();
        chk("T3 缺 commit 的一串事件不产生读数（n_meas 仍是 1）",
            n_cnt == 1 && s_cnt == 1);

        // ---- T4 第二轮更小：max 不许被小值覆盖，n_meas 递增 ----
        ev(0); wait_cyc(100);              // 1 µs
        ev(1); wait_cyc(100);              // 1 µs
        ev(2); wait_cyc(200);              // 2 µs
        ev_sof();
        chk("T4 第二轮 tot=4 µs 被记下，但 max 仍是第一轮的 100 µs",
            n_tot == 4 && n_max == 100 && n_cnt == 2);
        chk("T4b u_small 同样是 10 倍口径，且小值不会覆盖 max",
            s_tot >= n_tot*10 - 10 && s_tot <= n_tot*10 + 10 &&
            s_max >= 1000 && s_cnt == 2);

        // ---- T5 溢出：u_small 口径 10 拍/µs、SAT=4000 µs ⇒ 造一轮 5000 µs 必须钳位 ----
        ev(0); wait_cyc(20000);            // 2000 µs（u_norm 口径 200 µs）
        ev(1); wait_cyc(10000);            // 1000 µs
        ev(2); wait_cyc(20000);            // 2000 µs ⇒ 总 5000 µs > 4000
        ev_sof();
        chk("T5 超上限：u_small 的总和钳在 4000 且 saturated=1（不许回绕成小数）",
            s_tot == 4000 && s_sat == 1 && s_cnt == 3);
        chk("T5b 同一串事件在正常参数那台上是 500 µs 且不饱和（钳位只跟口径有关）",
            n_tot == 500 && n_sat == 0 && n_cnt == 3);
        chk("T5c 钳位后各段读数都不许大于总和（否则三段无法解释总数）",
            s_l1 <= s_tot && s_l2 <= s_tot && s_l3 <= s_tot);

        // ---- T6 一轮没走完就来新 commit：旧轮的晚到事件不许凑成一轮 ----
        ev(0); wait_cyc(100);              // 新轮开始
        ev(1); wait_cyc(100);              // 走完 start
        ev(0); wait_cyc(50);               // 又来个 commit（上一轮作废）
        ev(2); wait_cyc(50);               // 这个 done 属于被作废的那轮
        ev_sof();
        chk("T6 commit 一刷新就清配对标记 ⇒ 晚到的 done 凑不出数（n_meas 仍是 3）",
            n_cnt == 3);                   // 已完成的是 T2 / T4 / T5 三轮

        // ---- T7 没有 done 就没有收尾：只 commit+start+sof 不出数 ----
        ev(0); wait_cyc(100);
        ev(1); wait_cyc(100);
        ev_sof();
        chk("T7 没搬完的一帧不出读数（n_meas 仍是 3）", n_cnt == 3);

        $display("");
        $display("口径提醒：本模块量的是 PL 内部（commit 之后到该帧开始扫描），");
        $display("           上位机编码与网线传输不在内 ⇒ 对外只能说「链路内时延（PL 侧）」，");
        $display("           并且 L3 的分辨率是一个显示帧 ⇒ 报数带 ±1 帧。");
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
