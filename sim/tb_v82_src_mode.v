`timescale 1ns/1ps
// 台架：src/rtl/util/src_mode.v（长按翻转位 → 片源模式格雷码）
//
// 核心判据只有一条：**一次都没按，模式不许动**。
// 这条以前在 pl_video_top 里，没有任何台架碰得到它，于是"lsync 复位成 3'b111"这个写法
// 上了板：源头 tog 复位是 0，移位进来的第一个 0 会让 lsync[1]^lsync[2] 连续两拍为真
// ⇒ 上电自己走两步 AUTO→锁ETH→锁PS ⇒ 仲裁看到的 sel 永远不是 AUTO，"停流交回"永不发生。
// 症状与 #24 那次板级红**长得一模一样**（owner 位不动），但根因不同 —— 所以判据不能只报"红"，
// 必须能指出是谁占着（lane30 现在把 mode 与两个 busy 一起读回来了）。
//
// 检查器自己也要有反面对照（本仓库一贯做法，见 skill/artifact_freeze_and_freshness.md）：
// 这里同时例化一份**旧写法**的复制（复位 3'b111），断言它确实会多发边沿。
// 没有这条对照，"T1 通过"可能只是因为我的激励根本没能推进移位链。
//
// 期望常数（四个模式的格雷码）在这里重抄一遍，不从 RTL 引用。
module tb_v82_src_mode;

    localparam [1:0] M_AUTO = 2'd0, M_ETH = 2'd1, M_SD = 2'd3, M_TEST = 2'd2;

    reg clk = 0, rst_n = 0;
    reg  ltog = 0;
    reg  eth_now = 0;   // 此刻屏上是不是 ETH：AUTO 那一格按它挑目标（ISSUES #55）
    reg  [1:0] prev_m;  // T7 比较相邻两格用
    wire [1:0] mode;
    // V8-2 补的"串口命令钉模式"：码 + 翻转位（都是 axi 域准静态，这里按同一形状喂）
    reg  [1:0] ov_code = M_AUTO;
    reg        ov_tog  = 1'b0;
    reg  [1:0] mode_before_ov;
    reg  [1:0] mode_old = M_AUTO;      // 旧写法（复位灌 1）的对照
    (* ASYNC_REG = "TRUE" *) reg [2:0] lsync_old = 3'b111;

    src_mode u_dut (.clk(clk), .rst_n(rst_n), .ltog(ltog), .eth_now(eth_now),
                    .ov_code(ov_code), .ov_tog(ov_tog), .mode(mode));

    always #10 clk = ~clk;             // 50 ns = 20 MHz，像素钟的量级够用

    // 旧写法逐字照搬：链复位 111 + 同样的边沿检测
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin lsync_old <= 3'b111; mode_old <= M_AUTO; end
        else begin
            lsync_old <= {lsync_old[1:0], ltog};
            if (lsync_old[1] ^ lsync_old[2]) mode_old <= {mode_old[0], ~mode_old[1]};
        end
    end

    integer errors = 0;
    task expect; input [100*8:1] name; input cond;
        begin
            if (cond !== 1'b1) begin errors = errors + 1; $display("FAIL %0s (t=%0t)", name, $time); end
            else $display("PASS %0s", name);
        end
    endtask

    // 一次真实长按：把 tog 翻一次并**保持**至少 8 拍（远超 3 级同步链）
    task one_press;
        begin
            ltog = ~ltog;
            repeat (8) @(posedge clk);
        end
    endtask

    // 一次真实的"命令钉模式"：先让码稳定 8 拍，再翻位（main.c 的 ctrl_publish_mode 就是这两笔）。
    // 顺序反过来写就会红 —— 那正是这条改动唯一的风险点，所以它自己必须是一条判据。
    task publish_mode;
        input [1:0] code;
        begin
            ov_code = code;
            repeat (8) @(posedge clk);
            ov_tog  = ~ov_tog;
            repeat (8) @(posedge clk);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);

        // ---- T1 上电不许多动：一次没按，DUT 必须还停在 AUTO ----
        expect("T1 复位后什么都不按，模式仍为 AUTO", mode === M_AUTO);
        // ---- T1b 反面对照：旧写法必须**真的**会自己动，否则 T1 是空跑 ----
        // 数一下旧写法的移位链：111 →(灌 0)110 → 100 → 000，`[1]^[2]` 只在 100 那一拍为真
        // ⇒ **上电白送一次长按**，模式 AUTO→锁ETH。而 `sel=锁ETH` 在 src_arb 里是
        // `force_eth=1` ⇒ owner_eth 永远为 1、"停流交回"永不发生 —— 与板级实测一字不差。
        expect("T1b 反面对照：旧写法(链复位=1)上电自己一步到锁ETH", mode_old === M_ETH);
        $display("INFO 复位后 mode=%0d AUTO=%0d ETH=%0d SD=%0d TEST=%0d / 旧写法=%0d",
                 mode, M_AUTO, M_ETH, M_SD, M_TEST, mode_old);

        // ---- T2 一次长按 = 恰好一步 ----
        one_press;  repeat (6) @(posedge clk);
        expect("T2 一次长按只前进一格 AUTO→锁ETH", mode === M_ETH);
        one_press;  repeat (6) @(posedge clk);
        expect("T2b 再一次 → 锁PS", mode === M_SD);
        one_press;  repeat (6) @(posedge clk);
        expect("T2c 再一次 → TEST 档", mode === M_TEST);
        one_press;  repeat (6) @(posedge clk);
        expect("T2d 再一次 → 回 AUTO（四态环闭合）", mode === M_AUTO);

        // ---- T3 每一步只动一位（格雷码：这是 ms0 那对同步器安全的前提）----
        begin : gray
            integer k, bad;
            reg [1:0] before;
            bad = 0;
            for (k = 0; k < 4; k = k + 1) begin
                before = mode;
                one_press;  repeat (6) @(posedge clk);
                if ((mode ^ before) === 2'd0 || (mode ^ before) === 2'd3) bad = bad + 1;
            end
            expect("T3 四次切换每步都只有一位变化", bad == 0);
            $display("INFO T3 两位同时变化的步数 = %0d（必须为 0）", bad);
        end

        // ---- T4 一次翻转只算一次事件：等满 24 拍也不许多走 ----
        // 顺带一条**负知识**（写在这里省得下一个人来查）：翻转位方案**没有**毛刺滤波能力 ——
        // 单拍的 `ltog` 跳变同样会被数成一次事件，这是设计定义而不是缺陷；能过滤的是脉冲跨域，
        // 而那正是我们不敢用脉冲的原因（ISSUES #36）。所以这里断言"一次翻转=恰好一格"，
        // 不去断言"毛刺不算"。
        expect("T4 起点确实回到 AUTO（否则下面的期望是空的）", mode === M_AUTO);
        ltog = ~ltog;
        repeat (24) @(posedge clk);
        expect("T4 一次翻转 = 恰好一格 AUTO→锁ETH，多等 20 拍也不许再动", mode === M_ETH);

        // ---- T5 半路复位：链与模式必须一起回到"不动"的起点，且之后不再白送事件 ----
        expect("T5 复位前已经是锁ETH（T4 的结果，否则 T5b 没有对照意义）", mode === M_ETH);
        @(negedge clk); rst_n = 0;
        repeat (3) @(negedge clk);
        @(negedge clk); rst_n = 1;
        repeat (12) @(posedge clk);
        expect("T5b 复位把模式清回 AUTO，且再来一次上电边沿（没有第二次白送）", mode === M_AUTO);

        // ---- T6 长按事件与 tog 一对一：连按 3 次 = 3 步，不漏不重 ----
        begin : three
            integer k;
            for (k = 0; k < 3; k = k + 1) one_press;
            repeat (8) @(posedge clk);
            expect("T6 连续三次长按 = 前进三格（到 TEST 档）", mode === M_TEST);
            $display("INFO T6 结束位置 mode=%0d（期望 %0d=TEST 档）", mode, M_TEST);
        end

        // ---- T7 AUTO 那一格不许是空动作（用户实测：ETH 画面下第一次长按百分百没反应）----
        // 上一条测试结束时 mode 在锁图卡；复位回 AUTO，再把 eth_now 置 1 模拟“屏上就是 ETH”。
        @(negedge clk); rst_n = 0; repeat (3) @(negedge clk); @(negedge clk); rst_n = 1;
        eth_now = 1'b1;
        repeat (12) @(posedge clk);
        expect("T7a 起点是 AUTO 且 eth_now=1", mode === M_AUTO);
        one_press;
        expect("T7b 正在显示 ETH ⇒ 一次长按直接到锁PS（不许走成看不出变化的锁ETH）", mode === M_SD);
        begin : gray2
            integer k2, bad2, same;
            bad2 = 0; same = 0;
            for (k2 = 0; k2 < 2; k2 = k2 + 1) begin
                prev_m = mode;
                one_press;
                if ((prev_m ^ mode) === 2'b11) bad2 = bad2 + 1;   // 两位同时翻 = 格雷码被破坏
                if (prev_m === mode)           same = same + 1;   // 原地不动 = 空动作（就是用户报的那条）
                $display("INFO T7c 一步 %0d -> %0d（翻转位 %02b）", prev_m, mode, prev_m ^ mode);
            end
            expect("T7c 之后两格仍每格只翻 1 位（格雷码没破）", bad2 == 0);
            expect("T7d 每一格都必须真的换态（不许有空动作）", same == 0);
        end
        eth_now = 1'b0;
        // ---- T8~T12：V8-2 补的"串口命令钉模式"（2026-09-25 用户报"锁住之后只能长按三次才出来"）----
        publish_mode(M_AUTO);
        expect("T8a 起点：命令 AUTO 之后模式是 AUTO", mode === M_AUTO);
        one_press;
        expect("T8b 环也从 AUTO 起步（AUTO 覆盖会把环一起清，否则交还出一个旧锁）", mode === M_ETH);
        publish_mode(M_AUTO);                          // 回到已知起点
        publish_mode(M_TEST);
        expect("T9a 命令钉 TEST ⇒ 模式立刻是 TEST 档", mode === M_TEST);
        one_press;
        expect("T9b 覆盖期间长按只做一件事 = 交还（交还后环还在 AUTO，所以看到 AUTO）",
               mode === M_AUTO);
        publish_mode(M_SD);
        expect("T10a 命令钉 SD（码=11）", mode === M_SD);
        eth_now = 1'b1;
        publish_mode(M_ETH);
        expect("T10b 覆盖可以被下一条命令立刻换掉（钉 ETH），与 eth_now 无关", mode === M_ETH);
        eth_now = 1'b0;
        publish_mode(M_AUTO);
        // T11：延迟线判据 —— 沿**之后**才改的码不算数（这是 ctrl_publish_mode 两笔写的依据）
        publish_mode(M_SD);
        mode_before_ov = mode;
        ov_tog = ~ov_tog;                              // 先翻沿
        @(posedge clk);
        ov_code = M_TEST;                              // 沿之后才改码（故意写错顺序）
        repeat (8) @(posedge clk);
        expect("T11 沿之后才改的码不算数（采的是沿出发那一刻的码）", mode === mode_before_ov);
        publish_mode(M_AUTO);
        expect("T12 收尾回到 AUTO，后面若再加判据起点是干净的", mode === M_AUTO);
        eth_now = 1'b0;
        if (errors == 0) $display("PASS tb_v82_src_mode");
        else             $display("FAIL tb_v82_src_mode errors=%0d", errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL tb_v82_src_mode timeout");
        $finish;
    end
endmodule
