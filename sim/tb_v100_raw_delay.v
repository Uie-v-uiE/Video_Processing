`timescale 1ns/1ps
// tb_v100_raw_delay —— V8-4b 那块"原图抽头延后 OFF_LINES 行"的行环形缓存自己的判据
//
// 为什么单独给它一台架（ISSUES #62 第 3 步 / #68）：
//   4b 的整个卖点是"一条读流、缝只是逐像素选链子前 / 链子后两个抽头"。
//   两个抽头要能选，必须**站在同一格内容上**。第一版 `raw_line_delay` 是把 4 个 `line_cache` 串起来，
//   本台架当场量出它的传递函数是 (行 −4, 列 −4)：串级每一级都多花一拍 ⇒ 列方向累计偏 N 格。
//   这种错在模块级滤波台架里永远不会响（每台架只喂自己那一级），到 4b 就是一条 4 像素宽的竖带。
//   ⇒ 改成一块 1W1R 的行环形 RAM（写槽 = y 低位、读槽 = (y−LINES) 同一几位）之后，
//     "对不对"的判据就是下面这几条，期望值全部**独立算**，不从被测代码反推。
//
// 判据：
//   T1 稳态逐格：输出第 (row,k) 格必须恰好是**第 row−LINES 行的同一列 k**（列一格都不许偏）
//   T2 头 LINES 行不判定：那时环形 RAM 里还没有"上一行"（屏上落在帧首那几条线，与 #54 同一族）
//   T3 de 链与数据链等长：de 只在一部分列上打 ⇒ 凡有输出的那格，值必须仍是那一列
//   T4 LINES=0 必须是组合直通（链子哪天不滞后，顶层不必删例化，也不推 RAM）
//   T5 跨过槽位回绕（LINES=4 ⇒ 环 8 行，本台架喂到 13 行）之后仍要对齐
//   T6 覆盖面：逐格判据的样本数必须够大，否则"空窗假绿"（本项目清过好几次的那类）
//
// ⚠ 相位：输入在 negedge 驱动、DUT 在下一个 posedge 吃，所以每个样本的检查放在
//   **再下一个 negedge**。第一版就是在这一点上把"我自己的相位差一格"读成"硬件差一格"
//   （`skill/bench_self_inflicted_reds.md` 签名二：采样相位与被测节拍混叠）。
module tb_v100_raw_delay;
    localparam integer W     = 64;        // 一行 64 列（小、跑得快；真实顶层是 512）
    localparam integer LINES = 4;
    localparam integer ROWS  = 13;        // 特意跨过 2^RLOG = 8 的槽位回绕（T5）

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg         de = 0;
    reg  [11:0] x = 0, y = 0;
    reg  [15:0] d = 0;
    wire [15:0] q, q0;
    wire        qd, qd0;

    raw_line_delay #(.LINES(LINES), .W(W)) dut1 (
        .clk(clk), .rst_n(rst_n), .de(de), .x(x), .y(y), .d_in(d), .d_out(q), .de_out(qd)
    );
    raw_line_delay #(.LINES(0), .W(W)) dut0 (
        .clk(clk), .rst_n(rst_n), .de(de), .x(x), .y(y), .d_in(d), .d_out(q0), .de_out(qd0)
    );

    integer nfail = 0;
    integer t1_cnt = 0, t1_bad = 0, t3_cnt = 0, t3_bad = 0;
    integer pcnt = 0, pbad = 0;
    integer rr, kk, chk_from;
    // 上一拍喂进去的那一格（在下一个 negedge 检查它）
    integer p_row;
    reg [7:0] p_col;
    reg       p_valid;
    reg       partial;     // 本趟是否只在部分列上打 de，决定值能不能判
    reg       p_de_prev;   // 上一拍喂进去的 de（= 本拍应该看到的 de_out）
    reg [15:0] expq;

    task line(input [8*44-1:0] tag, input ok, input [8*150-1:0] txt);
        begin
            if (!ok) nfail = nfail + 1;
            $display("%s %0s | %0s", ok ? "PASS" : "FAIL", tag, txt);
        end
    endtask

    // 喂 [from,to) 行；do_check=1 ⇒ 从第 max(from,LINES) 行起逐格检查
    // ⚠ 每个参数都要各自写 `input integer`：只给第一个写类型，后面三个会按 Verilog 的默认取 **1 bit**，
    //   于是 `to=13` 传进来变成 1 ⇒ 行循环一次都不跑 ⇒ 样本数 0 ⇒ 判据"看起来全过"其实是空跑。
    //   （这正是 `skill/bench_self_inflicted_reds.md` / 记忆里那条"task 参数默认 1 bit"的前科，
    //    2026-09-25 我又犯了一次，靠 T6"覆盖面"这条才当场暴露。）
    task feed(input integer from, input integer to, input integer use_partial, input integer do_check);
        begin
            pbad = 0; pcnt = 0;
            partial = use_partial;
            for (rr = from; rr < to; rr = rr + 1) begin
                for (kk = 0; kk < W + 2; kk = kk + 1) begin
                    @(negedge clk);
                    // ---------- 1) 检查上一拍喂进去的那一格（此刻 posedge 已经把结果打进 q）----------
                    if (do_check == 1 && p_valid == 1 && rr >= from + 1) begin
                        pcnt = pcnt + 1;
                        expq = {((p_row - LINES) % 256), p_col};
                        // 值只在"参考行里那一列真的被写过"时才对得上：de 图样是 k%3==0（各行相同），
                        // 所以参考行里没打 de 的那些列留着更早的内容 ⇒ 那些列只判 de，不判值。
                        if ((p_col % 3 != 0) && (partial == 1)) begin
                            if (qd !== p_de_prev) begin
                                pbad = pbad + 1;
                                if (pbad <= 3) $display("     de 不符：喂入(row=%0d,col=%0d) de_out=%0b 应为 %0b",
                                                        p_row, p_col, qd, p_de_prev);
                            end
                        end else if (q !== expq || qd !== p_de_prev) begin   // de_out 必须就是上一拍的 de
                            pbad = pbad + 1;
                            if (pbad <= 3)
                                $display("     不符：喂入(row=%0d,col=%0d) 输出=%04x 期望=%04x de_out=%0b",
                                         p_row, p_col, q, expq, qd);
                        end
                    end
                    // ---------- 2) 喂这一格 ----------
                    if (kk < W) begin
                        x <= kk[11:0];
                        y <= rr[11:0];
                        d <= {rr[7:0], kk[7:0]};              // 值 = {行号, 列号}
                        de <= (use_partial == 0) || ((kk % 3) == 0);
                        p_row   = rr;
                        p_col   = kk[7:0];
                        p_de_prev = (use_partial == 0) ? 1'b1 : (((kk % 3) == 0) ? 1'b1 : 1'b0);
                        p_valid = (rr >= from + 1);            // 第一行的样本要到下一行才检查
                    end else begin
                        de <= 1'b0;
                        p_de_prev = 1'b0;
                        p_valid = 1'b0;                        // 行间的空隙不检查
                    end
                end
            end
        end
    endtask

    integer f1_cnt, f1_bad;
    initial begin
        de = 0; x = 0; y = 0; d = 0; p_row = -1; p_col = 8'hFF; p_valid = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);

        // ---- T2：头 LINES 行只预热 ----
        feed(0, LINES, 0, 0);
        $display("INFO T2 前 %0d 行只预热不判定（RAM 里还没有上一行；屏上落在帧首，与 #54 同一族）", LINES);

        // ---- T1 + T5：稳态逐格（喂到 13 行，跨过 8 行的槽位回绕）----
        feed(LINES, ROWS, 0, 1);
        f1_cnt = pcnt; f1_bad = pbad;
        t1_cnt = f1_cnt; t1_bad = f1_bad;
        line("T1 稳态逐格对齐（列一格不偏）", t1_cnt > 300 && t1_bad == 0,
             "输出第 (row,k) 格必须是第 row-LINES 行的同一列 k");
        line("T5 跨过槽位回绕仍对齐", t1_bad == 0,
             "喂到 13 行 > 2^RLOG=8 ⇒ 环回绕之后判据仍然成立");
        $display("INFO T1 样本 %0d 格、错 %0d 格（W=%0d × 行 %0d..%0d）", t1_cnt, t1_bad, W, LINES, ROWS-1);

        // ---- T3：de 只打在 k%3==0 的列上 ----
        feed(ROWS, ROWS + 4, 1, 1);
        t3_cnt = pcnt; t3_bad = pbad;
        // T3 判的是模块**真正承诺**的那件事：`de_out` 与 `d_out` 都只延后一拍（同一块 RAM 的读出），
        //   不存在"标签比内容新/旧一拍"。
        //   ⚠ 前提也要说明：本模块**不**给 de 做 LINES 行的行延迟 ⇒ 调用方必须保证
        //     "每一行的 de 图样相同"（顶层就是如此：偶数列打 de，天天一样）。
        //     第一版我拿"只在一部分列上打 de"去判"输出 de 必须与输入 de 同一列"，那是我给模块
        //     加了一条它没承诺、也用不上的语义 ⇒ 红在台架自己。改成判"de_out == 上一拍的 de"。
        line("T3 de 与数据同为一拍延迟", t3_cnt > 60 && t3_bad == 0,
             "d_out 与 de_out 都只延后一拍 ⇒ 不允许出现“数据到了、de 还没到”（#54 那一族的另一种）");
        $display("INFO T3 样本 %0d 格、错 %0d 格", t3_cnt, t3_bad);

        // ---- T4：LINES=0 是组合直通 ----
        @(negedge clk);
        x <= 12'd9; y <= 12'd3; d <= 16'h0309; de <= 1'b1;
        #1;                                   // 组合直通不必等时钟沿
        line("T4 LINES=0 是组合直通", (q0 === 16'h0309),
             "深度 0 ⇒ 直通且不推 RAM");
        @(negedge clk); de <= 1'b0;

        // ---- T6：覆盖面 ----
        line("T6 覆盖面不是空跑", (t1_cnt + t3_cnt) > 500,
             "两条逐格判据加起来要有几百格的覆盖面，否则差一格也可能被空窗混过去");

        if (nfail == 0) $display("RESULT tb_v100_raw_delay PASS");
        else            $display("RESULT tb_v100_raw_delay FAIL nfail=%0d", nfail);
        $finish;
    end
endmodule
