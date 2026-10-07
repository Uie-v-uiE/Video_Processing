`timescale 1ns/1ps
// 功能：被测模块 `src_arb`（例化 `dut`，.T_OFF_CYC(20)，顶层用 2_000_000=20 ms，这里缩短只为
// 少等滞回计数）；覆盖点：#174 —— why_ps 必须是"换手判决那一拍的输入快照"，互锁冻住主人
// 期间不许被最新输入刷新，而真换手时必须重新取一次快照。
// 激励与检查：#5 翻转时钟（10 ns，与顶层 axi_clk 同周期），激励一律在 negedge 写；rst_n
// 上电为 0，头 6 个 negedge 期间读复位形状，随后放成 1 再等 3 拍；eth_live 先置 1 等 ETH
// 抢走总线、再置 0 等静默让位（wait_owner 最多 400 个 negedge，覆盖 TQ=20 的滞回）；
// 然后 fill_busy=1 冻住主人、空 4 拍后把 eth_live 翻成 1 再等 6 拍；fill_busy=0 让 ETH 回抢；
// 最后 sel=2'd2（强制 PS）等一次真换手。
// 判定条件（写各条实际比较的表达式）：W1a owner_eth===1'b0 && why_ps===3'b011；
// W1b owner_eth===1'b0 && why_ps===3'b010；W2 owner_eth===1'b1；W3 owner_eth===1'b0 且
// W3b why_ps===3'b010；W4 互锁中 owner_eth===1'b0；W5（正文，改前必须红）why_ps===3'b010，
// 旧写法在这里被最新输入刷成 3'b000；W6 owner_eth===1'b1；W7 why_ps===3'b100 &&
// owner_eth===1'b0（判决沿看到 force_ps=1、eth_live=1、eth_tb_ok=1）。
// 预期结果：通过时每条打 `  PASS <标签> | <说明> | <读数>`，随后打 `checks=%0d errors=0`
// 与 `TB RESULT PASS`；失败时该条打 `  FAIL <标签> | <说明> | <读数>`（W5 红就是 #174
// 本体，W7 拦住"why_ps 再也不更新"的反配对），收尾打 `checks=%0d errors=%0d` 与
// `TB RESULT FAIL`；400 us 看门狗到点打 `  FAIL Z_timeout | never finished checks=%0d
// fails=%0d` + `TB RESULT FAIL timeout`。
// tb_src_arb_why.v —— ISSUES #174 的尺子（模块级，秒级跑完）。
//
// 症状：`src_arb.v:62` 的 `why_ps <= {force_ps, ~eth_live, ~eth_tb_ok};` 挂在**无条件**那一支，
// 每拍跟着输入刷新；而 `owner_eth` 只在 `both_idle`（`:69`）才换主人。于是 PS 正在搬一帧
// （`fill_busy=1` ⇒ 换手被互锁拦住）的时候把 `eth_live` 翻一下，屏上/上位机读到的"为什么 PS 拿着"
// 就变了，可主人一次都没换 —— `:32-38` 的注释承诺的是"三个输入在**判决同一个时钟沿**上的快照"，
// 代码给的是"最新一拍的输入"。#55 定过同一族口径（两个地方各说一套），那次修的是标签反了。
//
// 这台架的分工：
//   W1a、W1b、W2~W4、W6~W7 是地板（现行真行为，改前改后都必须绿）；W5 是这一刀的正文，**改前必须红**。
//   W7 是 W5 的反配对：若有人把修法写成"why_ps 从此不再更新"，W5 会变绿而 W7 替我拦住它 ——
//   快照的含义是"换手那一拍的输入"，不是"永远钉死"。
// ⚠ 判据名一律 ASCII：定宽字段被多字节中文从左边截掉，`grep <标签>` 就找不到那一条（r94 撞过两次）。
// ⚠ `T_OFF_CYC` 这里传 20（顶层用 2_000_000=20 ms）：滞回计数是**唯一**需要等的东西，缩短参数
//   不改变任何一条判据的语义，只把台架从"要等 40 ms×N"变成毫秒级。
module tb_src_arb_why;
    localparam integer TQ = 20;

    reg clk = 0, rst_n = 0;
    reg eth_live = 0, eth_tb_ok = 1;
    reg [1:0] sel = 2'd0;
    reg row_busy = 0, fill_busy = 0;
    wire owner_eth;
    wire [2:0] why_ps;

    always #5 clk = ~clk;                 // 100 MHz，与顶层 axi_clk 同周期

    src_arb #(.T_OFF_CYC(TQ)) dut (
        .clk(clk), .rst_n(rst_n),
        .eth_live(eth_live), .eth_tb_ok(eth_tb_ok), .sel(sel),
        .row_busy(row_busy), .fill_busy(fill_busy),
        .owner_eth(owner_eth), .why_ps(why_ps));

    integer fails = 0, checks = 0;
    task chk;
        input [8*40-1:0] name;
        input            ok;
        input [8*64-1:0] note;
        input integer    v1;
        begin
            checks = checks + 1;
            if (ok) $display("  PASS %0s | %0s | %0d", name, note, v1);
            else    begin fails = fails + 1; $display("  FAIL %0s | %0s | %0d", name, note, v1); end
        end
    endtask

    // 等到主人变成期望的那一个（最多 400 拍 ⇒ 覆盖 TQ 的滞回）。
    // 结果放 wc_ok，不用参数回传：调用方拿同一个整数既当本轮结果又当累计器会互相盖掉。
    reg wc_ok;
    task wait_owner;
        input want;
        integer k;
        begin
            wc_ok = 0;
            for (k = 0; k < 400 && !wc_ok; k = k + 1) begin
                @(negedge clk);
                if (owner_eth === want) wc_ok = 1;
            end
        end
    endtask

    integer i;
    initial begin
        repeat (6) @(negedge clk);
        // ---- W1a 复位**期间**的形状：先给 PS，且原因不能谎报"一切正常" ----
        // 3'b011 只活在 rst_n=0 的时候：`:62` 是无条件每拍刷新，复位一放开第一个沿就把它盖掉。
        // 第一版把这条写在放开复位之后，读出 010 ⇒ 红的不是 DUT，是我的台架（锚定规矩那条老账）。
        chk("W1a_reset_shape", owner_eth === 1'b0 && why_ps === 3'b011,
            "in reset: owner=0, why_ps=011 (unproven timebase)", why_ps);
        rst_n = 1;
        repeat (3) @(negedge clk);
        // ---- W1b 放开复位后第一拍的快照（010 = 没流 + 时基已被台架钉成可信） ----
        chk("W1b_first_edge_after_reset", owner_eth === 1'b0 && why_ps === 3'b010,
            "first snapshot sees no stream, timebase ok", why_ps);

        // ---- W2 链路活 ⇒ ETH 抢走总线（地板） ----
        eth_live = 1;                      // eth_tb_ok 一直是 1
        wait_owner(1'b1);
        chk("W2_eth_grabs_when_live", owner_eth === 1'b1, "eth_wanted=1 and idle => owner=ETH", owner_eth);

        // ---- W3 断流 ⇒ 静默 TQ 拍后交还 PS；换手那一拍的快照 ----
        eth_live = 0;
        wait_owner(1'b0);
        chk("W3_owner_hands_off_to_ps", owner_eth === 1'b0, "quiet hysteresis hands the bus back", owner_eth);
        chk("W3b_reason_at_handover", why_ps === 3'b010, "deciding edge: no stream, timebase ok", why_ps);

        // ---- W4/W5 正文：PS 正在搬一帧 ⇒ 互锁冻住主人，此时翻 eth_live ----
        fill_busy = 1;                     // both_idle=0 ⇒ 结构上不可能换手
        repeat (4) @(negedge clk);
        eth_live = 1;                      // "流回来了" —— 但主人被冻住，一次都没换
        repeat (6) @(negedge clk);
        chk("W4_interlock_holds_mid_copy", owner_eth === 1'b0,
            "mid-copy interlock refuses to flip the owner", owner_eth);
        // 改前必须红：旧写法这里刷成 000（"有流、时基正常"），可 PS 仍是主人、主人一次都没换。
        chk("W5_why_ps_is_a_decision_snapshot", why_ps === 3'b010,
            "#174 must freeze with the owner (010)", why_ps);

        // ---- W6 搬完 ⇒ ETH 立刻回抢（地板：滞回只服务让位方向） ----
        fill_busy = 0;
        wait_owner(1'b1);
        chk("W6_eth_retakes_after_copy", owner_eth === 1'b1,
            "ETH retakes the bus once both engines idle", owner_eth);

        // ---- W7 W5 的反配对：真换手时必须换成判决那一拍的输入 ----
        // 钉成"强制看 fb"⇒ eth_wanted=0，静默 TQ 拍后 PS 拿回屏幕；判决沿看到的是
        // force_ps=1、eth_live=1、eth_tb_ok=1 ⇒ 必须是 100（被人钉住，不是故障）。
        // 若把 #174 修成"why_ps 再也不更新"，这里会停在 W6 之后那次判决的值 ⇒ 这条替我拦住它。
        sel = 2'd2;
        wait_owner(1'b0);
        chk("W7_reason_moves_at_next_handover", why_ps === 3'b100 && owner_eth === 1'b0,
            "a real handover re-snapshots: 100 = pinned", why_ps);

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
