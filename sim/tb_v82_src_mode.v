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

    localparam [1:0] M_AUTO = 2'd0, M_ETH = 2'd1, M_PS = 2'd3, M_CARD = 2'd2;

    reg clk = 0, rst_n = 0;
    reg  ltog = 0;
    wire [1:0] mode;
    reg  [1:0] mode_old = M_AUTO;      // 旧写法（复位灌 1）的对照
    (* ASYNC_REG = "TRUE" *) reg [2:0] lsync_old = 3'b111;

    src_mode u_dut (.clk(clk), .rst_n(rst_n), .ltog(ltog), .mode(mode));

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
            if (!cond) begin errors = errors + 1; $display("FAIL %0s (t=%0t)", name, $time); end
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
        $display("INFO 复位后 mode=%0d AUTO=%0d ETH=%0d PS=%0d CARD=%0d / 旧写法=%0d",
                 mode, M_AUTO, M_ETH, M_PS, M_CARD, mode_old);

        // ---- T2 一次长按 = 恰好一步 ----
        one_press;  repeat (6) @(posedge clk);
        expect("T2 一次长按只前进一格 AUTO→锁ETH", mode === M_ETH);
        one_press;  repeat (6) @(posedge clk);
        expect("T2b 再一次 → 锁PS", mode === M_PS);
        one_press;  repeat (6) @(posedge clk);
        expect("T2c 再一次 → 锁图卡", mode === M_CARD);
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
            expect("T6 连续三次长按 = 前进三格（到锁图卡）", mode === M_CARD);
            $display("INFO T6 结束位置 mode=%0d（期望 %0d=锁图卡）", mode, M_CARD);
        end

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
