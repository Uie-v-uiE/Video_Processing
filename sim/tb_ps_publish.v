`timescale 1ns/1ps
// tb_ps_publish —— 验证 PS 发布脉冲的跨域 + "一次发布对应一次消费"。
//
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
            $display("%-58s %s", named, ok ? "ok" : "<<< 不成立");
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
                $display("<<< 第 %0d 次发布没有被同步到（pend 未在 8 拍内起来）", k);
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
        $display("  诊断(5): rises=%0d falls=%0d consumes=%0d pend=%b", rises, falls, consumes, pend);
        // 合并的证据是"只有一个上升沿 + 一次消费"：pend 本来就已经是 1，
        // 第二次发布不可能再产生一个上升沿 —— 断言 rises==2 是我一开始写错的期望。
        chk("5 两次快速发布只留一个挂起（pend 仅上一个沿且保持）",
            rises == 1 && pend === 1'b1);
        @(posedge clk); #1 consume = 1;
        @(posedge clk); #1 consume = 0;
        repeat (6) @(posedge clk);
        $display("  诊断(5b): rises=%0d falls=%0d consumes=%0d pend=%b", rises, falls, consumes, pend);
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
        $display("计数：rises=%0d falls=%0d consumes=%0d", rises, falls, consumes);
        if (errors == 0) $display("RESULT tb_ps_publish PASS");
        else             $display("RESULT tb_ps_publish FAIL (%0d 处不成立)", errors);
        $finish;
    end

    initial begin
        #400_000;
        $display("RESULT tb_ps_publish FAIL 超时（没有跑到最后的断言）");
        $finish;
    end
endmodule
