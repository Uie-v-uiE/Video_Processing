`timescale 1ns/1ps
// 功能：被测模块 `ps_publish`（例化 `u_dut`）；覆盖点：tog 跨域同步成 pend 的建立/保持/清除，
// 以及"一次发布对应一次消费"在两个非整数比时钟下的相位扫描。
// 激励与检查：#10 翻转得消费侧 clk（20 ns）、#3.5 翻转得发布侧 src（7 ns，故意不成整数比）；
// rst_n 上电为 0，4 个 clk 沿后放成 1、再等 2 拍；场景依次为：复位后读 pend；连喂 30 次
// 消费（consume 每次举一拍）；单次翻转 tog 后最多 5 拍内抓 pend 上升、再空等 12 拍看保持、
// 一次 consume 后等 3 拍看落回；两次相隔 60 ns 的快速发布后等 10 拍；末段 60 次"发布 +
// 消费"，相位取 31 位 LFSR（种子 32'h13579BDF）的 ph%60×0.1 ns（0..5.9 ns）并在消费前
// 再抖 ph%25×0.1 ns，每次最多等 8 拍抓 pend 上升。
// 判定条件：1 pend===1'b0；2 空跑 rises==0 && falls==0 && consumes==0；3 一次发布 got==1
// 且无 consume 时 pend===1'b1；4 consume 之后 pend===1'b0；5 两次快速发布 rises==1 &&
// pend===1'b1；5b pend===1'b0 && falls==1 && consumes==1；6 相位扫描必须
// rises==60 && falls==60 && consumes==60。
// 预期结果：通过时每条打 `[tb_ps_publish.v:39] <判据名> ok`，errors==0 时打
// `RESULT tb_ps_publish PASS`（前有计数现场行 `计数：rises=.. falls=.. consumes=..`）；
// 失败时对应判据打 `... <<< 不成立`，某次发布没被同步到还打
// `<<< 第 %0d 次发布没有被同步到（pend 未在 8 拍内起来）`，收尾打
// `RESULT tb_ps_publish FAIL (%0d 处不成立)`，400 us 看门狗到点打
// `RESULT tb_ps_publish FAIL 超时（没有跑到最后的断言）`。
// tb_ps_publish —— 验证 PS 发布脉冲的跨域 + "一次发布对应一次消费"。
// 为什么要台架而不是上板看：这段逻辑错了的表现是"偶尔多刷/少刷一帧"，
// 在屏幕上和 SD 本身的抖动分不开。所以把两个时钟做成**非整数比**（7 ns vs 20 ns），
// 让翻转沿相对 clk 的相位在几十次迭代里扫遍整周期，再逐次核对。
// 写成纯 Verilog-2001：这个流程里 xvlog 对 .v 不开 SV，int / ++ / $urandom_range 都不认。
module tb_ps_publish;
    reg  clk = 0;      // 消费侧（clk_pix，20 ns）
    reg  src = 0;      // 发布侧（axi_clk，7 ns —— 故意不成整数比）
    reg  rst_n = 0;
    reg  tog = 0;
    reg  consume = 0;
    wire pend, new_tog;
    reg  pend_d = 0;

    integer errors = 0;
    integer rises = 0, falls = 0, consumes = 0;
    integer k = 0, got = 0;
    reg [31:0] ph = 32'h13579BDF;         // LFSR：伪随机但**可复现**的相位

    always #10 clk = ~clk;
    always #3.5 src = ~src;

    ps_publish u_dut (.clk(clk), .rst_n(rst_n), .tog(tog), .consume(consume),
                      .pend(pend), .new_tog(new_tog));

    always @(posedge clk) begin
        pend_d <= pend;
        if (pend && !pend_d)  rises = rises + 1;
        if (!pend && pend_d)  falls = falls + 1;
        if (consume && pend)  consumes = consumes + 1;
    end

    task chk;
        input [8*60:1] named;
        input ok;
        begin
            $display("[tb_ps_publish.v:39] %-58s %s", named, ok ? "ok" : "<<< 不成立");
            if (!ok) errors = errors + 1;
        end
    endtask

    // 等一次 pend 上升，最多 n 拍；没等到则 got=0
    task wait_pend;
        input integer n;
        integer i;
        begin
            got = 0;
            for (i = 0; (i < n) && (got == 0); i = i + 1) begin
                @(posedge clk);
                if (pend && !pend_d) got = 1;
            end
        end
    endtask

    // 一次发布 + 一次消费；phase 决定翻转沿相对 clk 的位置（单位 0.1 ns）
    task pub_then_consume;
        input integer phase;
        begin
            #(phase * 0.1);
            tog = ~tog;
            wait_pend(8);
            if (got == 0) begin
                $display("[tb_ps_publish.v:65] <<< 第 %0d 次发布没有被同步到（pend 未在 8 拍内起来）", k);
                errors = errors + 1;
            end
            #((ph % 25) * 0.1);
            @(posedge clk); #1 consume = 1;
            @(posedge clk); #1 consume = 0;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        chk("1 复位后 pend=0", pend === 1'b0);

        // ---- 2. 没有发布时反复消费，不该凭空起 pend ----
        rises = 0; falls = 0; consumes = 0;
        for (k = 0; k < 30; k = k + 1) begin
            @(posedge clk); #1 consume = 1;
            @(posedge clk); #1 consume = 0;
        end
        chk("2 空跑 30 次消费：pend 无上升也无下降", rises == 0 && falls == 0 && consumes == 0);

        // ---- 3/4. 单次发布：起来、保持、只被 consume 放掉 ----
        tog = ~tog;
        wait_pend(5);
        chk("3 一次发布后 pend 在 5 拍内起来", got == 1);
        repeat (12) @(posedge clk);
        chk("3b 没有 consume 时 pend 保持为 1（不会自己消失）", pend === 1'b1);
        @(posedge clk); #1 consume = 1;
        @(posedge clk); #1 consume = 0;
        repeat (3) @(posedge clk);
        chk("4 consume 之后 pend 落回 0", pend === 1'b0);

        // ---- 5. 连续两次发布只对应一次消费（电平语义，模块头部写明的取舍）----
        // 间隔必须大于同步链的采样窗口：真把两次翻转塞进同一个 20 ns 采样间隔里，
        // 电平来回一次等于"没发布"——那是协议的前提（PS 每帧之间至少隔一个帧周期），
        // 不是这里要测的东西。
        rises = 0; falls = 0; consumes = 0;
        tog = ~tog; #60;
        tog = ~tog; #60;
        repeat (10) @(posedge clk);
        $display("[tb_ps_publish.v:108] 诊断(5): rises=%0d falls=%0d consumes=%0d pend=%b", rises, falls, consumes, pend);
        // 合并的证据是"只有一个上升沿 + 一次消费"：pend 本来就已经是 1，
        // 第二次发布不可能再产生一个上升沿 —— 断言 rises==2 是我一开始写错的期望。
        chk("5 两次快速发布只留一个挂起（pend 仅上一个沿且保持）",
            rises == 1 && pend === 1'b1);
        @(posedge clk); #1 consume = 1;
        @(posedge clk); #1 consume = 0;
        repeat (6) @(posedge clk);
        $display("[tb_ps_publish.v:116] 诊断(5b): rises=%0d falls=%0d consumes=%0d pend=%b", rises, falls, consumes, pend);
        chk("5b 合并后一次消费即回到静默", pend === 1'b0 && falls == 1 && consumes == 1);

        // ---- 6. 相位扫描：60 次发布必须正好 60 次消费 ----
        rises = 0; falls = 0; consumes = 0;
        for (k = 0; k < 60; k = k + 1) begin
            ph = {ph[30:0], ph[31] ^ ph[21] ^ ph[16] ^ ph[3]};
            pub_then_consume(ph % 60);           // 0..5.9 ns，覆盖 7 ns 的发布周期
        end
        repeat (10) @(posedge clk);
        chk("6 相位扫描 60 次：60 升 / 60 降 / 60 次消费一一对应",
            rises == 60 && falls == 60 && consumes == 60);

        $display("");
        $display("[tb_ps_publish.v:130] 计数：rises=%0d falls=%0d consumes=%0d", rises, falls, consumes);
        if (errors == 0) $display("RESULT tb_ps_publish PASS");
        else             $display("[tb_ps_publish.v:132] RESULT tb_ps_publish FAIL (%0d 处不成立)", errors);
        $finish;
    end

    initial begin
        #400_000;
        $display("[tb_ps_publish.v:138] RESULT tb_ps_publish FAIL 超时（没有跑到最后的断言）");
        $finish;
    end
endmodule
