`timescale 1ns/1ps
// 功能：被测模块 `raw_line_delay`，两份例化 dut1 #(.LINES(4), .W(64)) 与 dut0
//        #(.LINES(0), .W(64))（直通对照）；覆盖点：行环形缓存的逐格语义——输出第 (row,k) 格
//        等于第 row−LINES 行的同一列 k、de 链与数据链等长、跨过 2^RLOG=8 的槽位回绕、
//        LINES=0 时组合直通、真实光栅（x 走到 HT−1、含竖消隐）下行首与行内各列。
// 激励与检查：时钟 always #5 clk=~clk（10 ns）；初值 de/x/y/d 清零，repeat(4) @(negedge clk)
//        后置 rst_n=1 再等 3 个负沿；输入全在 negedge 驱动、值取 d={行号,列号}，检查放在样本
//        之后第二个 negedge（dut1 在下一个 posedge 才吃）。T2：feed(0,4,0,0) 只预热不判；
//        T1/T5：feed(4,13,0,1) 每行喂 W+2=66 拍（末 2 拍 de=0），逐格判 q=={(p_row−4)%256,
//        p_col} 且 qd==p_de_prev，收尾 t1_cnt>300 && t1_bad==0（T5 复用同一计数，行 4..12
//        跨过环深 8）；T3：feed(13,17,1,1)，de 只打在 k%3==0 的列上，非 3 倍列只判 de，
//        收尾 t3_cnt>60 && t3_bad==0；T4：单拍驱动 x=12'd9、y=12'd3、d=16'h0309、de=1，#1 后
//        判 dut0 的 q0===16'h0309；T7/T7k：raster 按 HT=80（64 有效+16 空拍）、VT=16（0..7
//        有效）的真光栅，先 raster(1,0) 预热再 raster(2,1) 判定，驱动后 #2 处取 q，第 0 列判
//        q==={ref_row(rrow),8'd0}、第 1..W−1 列判 q==={ref_row(rrow),rcol−1}，环深
//        SLOTS=2^clog2(LINES+1) 由 LINES 现推；收尾 t7_cnt>12 && t7_bad==0、
//        t7k_cnt>600 && t7k_bad==0；T6 覆盖面地板 (t1_cnt+t3_cnt+t7_cnt+t7k_cnt)>1500。
// 预期结果：通过时七条判据各打印 PASS <标签> | <说明>（T1 稳态逐格对齐、T5 跨过槽位回绕仍
//        对齐、T3 de 与数据同为一拍延迟、T4 LINES=0 是组合直通、T7 行首第一格、T7k 行内其余
//        列、T6 覆盖面不是空跑），另有 INFO T2/T1/T3/T7 的样本计数行与最多 14 条
//        PROBE PHASE 相位读数，末行 RESULT tb_v100_raw_delay PASS；失败时对应条打印
//        FAIL <标签> | <说明> 并 nfail+1，同时先打明细：不符：喂入(row=…,col=…) 输出=%04x
//        期望=%04x de_out=%0b（最多 3 条）、de 不符…（最多 3 条）、T7 行首不符（最多 6 条）、
//        T7k 行内不符（最多 3 条），末行改打 RESULT tb_v100_raw_delay FAIL nfail=<n>。
// tb_v100_raw_delay —— V8-4b"原图抽头延后 OFF_LINES 行"的行环形缓存自己的判据；钉 #68/#102
//   跑法 `bash sim/run_one.sh tb_v100_raw_delay`。旧写法串 4 个 `line_cache` ⇒ 传递函数 (行 −4, 列 −4)：每级多花一拍
//   ⇒ 列向累计偏 N 格，模块级滤波台架永不响；现在是 1W1R 行环 RAM（写槽 = y 低位、读槽 = (y−LINES) 同一几位），期望值全部**独立算**。
// 判据：T1 输出 (row,k) 恰是第 row−LINES 行的**同一列 k**（列一格不许偏）；T2 头 LINES 行不判定（环里没有"上一行"，落帧首，#54 同族）；
//   T3 de 链与数据链等长（有输出的那格值必须仍是那一列）；T4 LINES=0 必须组合直通（不删例化、也不推 RAM）；
//   T5 跨过 2^RLOG=8 的槽位回绕（环 8 行，本台架喂到 13 行）后仍对齐；T6 逐格样本数必须够大，否则"空窗假绿"。
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
    // ⚠ 相位：输入在 negedge 驱动、DUT 在**下一个 posedge** 吃 ⇒ 每个样本的检查放在再下一个 negedge。
    //   第一版就是在这一点上把自己的相位差一格读成"硬件差一格"（`skills/bench_self_inflicted_reds.md` 签名二）。
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
    // ⚠ 每个参数都要各自写 `input integer`：只给第一个写类型，后面三个按 Verilog 默认取 **1 bit** ⇒
    //   `to=13` 变成 1 ⇒ 行循环一次不跑 ⇒ 样本数 0、判据"看起来全过"其实是空跑（靠 T6 才当场暴露）。
    task feed(input integer from, input integer to, input integer use_partial, input integer do_check);
        begin
            pbad = 0; pcnt = 0;
            partial = use_partial;
            for (rr = from; rr < to; rr = rr + 1) begin
                for (kk = 0; kk < W + 2; kk = kk + 1) begin
                    @(negedge clk);
                    // 1) 检查上一拍喂进去的那一格（此刻 posedge 已经把结果打进 q）
                    if (do_check == 1 && p_valid == 1 && rr >= from + 1) begin
                        pcnt = pcnt + 1;
                        expq = {((p_row - LINES) % 256), p_col};
                        // 值只在"参考行里那一列真的被写过"时才对得上：de 图样是 k%3==0（各行相同），
                        // 所以参考行里没打 de 的那些列留着更早的内容 ⇒ 那些列只判 de，不判值。
                        if ((p_col % 3 != 0) && (partial == 1)) begin
                            if (qd !== p_de_prev) begin
                                pbad = pbad + 1;
                                if (pbad <= 3) $display("[tb_v100_raw_delay.v:84] de 不符：喂入(row=%0d,col=%0d) de_out=%0b 应为 %0b",
                                                        p_row, p_col, qd, p_de_prev);
                            end
                        end else if (q !== expq || qd !== p_de_prev) begin   // de_out 必须就是上一拍的 de
                            pbad = pbad + 1;
                            if (pbad <= 3)
                                $display("[tb_v100_raw_delay.v:90] 不符：喂入(row=%0d,col=%0d) 输出=%04x 期望=%04x de_out=%0b",
                                         p_row, p_col, q, expq, qd);
                        end
                    end
                    // 2) 喂这一格
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
    // T7 / T7k：真实光栅（x 跑过消隐 + 竖消隐回帧头）。原来三条抓不到 #102：`feed()` 的"消隐"只有 2 拍、那两拍里
    //   **x 停在 W−1**（顶层 `video_timing` 数到 H_TOTAL−1=1343），而 RAM 读出晚一拍 + 消隐期拿 `x` 低几位当列地址 ⇒ 行首读到
    //   "消隐最后那个地址"的格子，这个洞在本台架里不存在。这里按真光栅驱动：HT=80（64 有效 + 16 空拍）、VT=16（0..7 有效、8..15 竖消隐）。
    //   有效行数 8 = 环深的整数倍（顶层 2·IMG_H=600 mod 8=0 同一条件）。两条各数各的样本：T7 第 0 列 = 绝对期望 `{参考行,0}`（#102 病灶）；
    //   T7k 第 1..W−1 列判 `{参考行,k}`，期望是 **k 不是 k−1**（晚的是拍不是列）：预读只许占"de 刚掉下去"那一拍，中间任一列被挪动
    //   = #92 第一笔那族整列错位 ⇒ 当场红。绕回与"第 0 列/第 1 列同源"是顶层性质（#98、tb_v98 的 P100/C6），本模块不判。
    localparam integer HT = 80, VT = 16, VACT = 8;
    integer t7_cnt = 0, t7_bad = 0, t7k_cnt = 0, t7k_bad = 0;
    integer rrow, rcol, exp_k;
    integer SLOTS;                         // 环深：由 LINES 现推（与被测模块 `clog2(LINES+1)` 同一条式子），不抄 8
    // 参考行 = (rw - LINES) mod 环深。写成 mod 而不是直接减：帧头那几行读的槽里装的是
    //   上一帧尾巴（行 4..7）的内容，"减出负数"在这里不是错误、就是这个语义。
    function [7:0] ref_row; input integer rw;
        // 赋给 [7:0] 的函数返回值本身就是截断，不写 SystemVerilog 的尺寸强转（这份台架按 Verilog 编）
        begin ref_row = (((rw - LINES) % SLOTS) + SLOTS) % SLOTS; end
    endfunction
    // 相位先量清楚再定期望：`feed()` 的"喂完之后第二拍才检查"与顶层 P100 的"标签与本拍内容同拍"不是一回事，
    //   直接用哪一条去判行首都可能是空判；PHASE 探针取"驱动之后、下一个 posedge 之前"那一拍（配对就发生在那半拍）。
    integer ph_cnt = 0;
    task raster(input integer n_frames, input integer check);
        begin
            for (rr = 0; rr < n_frames; rr = rr + 1) begin
                for (rrow = 0; rrow < VT; rrow = rrow + 1) begin
                    for (rcol = 0; rcol < HT; rcol = rcol + 1) begin
                        @(negedge clk);
                        // 2) 先喂这一拍：x 自由跑到 HT-1，de 只盖住有效列
                        x <= rcol[11:0];
                        y <= rrow[11:0];
                        de <= ((rrow < VACT) && (rcol < W)) ? 1'b1 : 1'b0;
                        d  <= {rrow[7:0], rcol[7:0]};
                        #2;   // 半个周期之后、下一个 posedge 之前：此刻标签就是本拍驱动的值
                        // 1) 判"本拍标签"配对的那一格
                        if (check == 1 && rrow < VACT && rcol < W) begin
                            exp_k = (rcol == 0) ? 0 : (rcol - 1);
                            if (rcol == 0) begin
                                t7_cnt = t7_cnt + 1;
                                if (q !== {ref_row(rrow), 8'd0}) begin
                                    t7_bad = t7_bad + 1;
                                    if (t7_bad <= 6)
                                        $display("T7 行首不符：标签(row=%0d,col=0) 输出=%04x 期望=%04x",
                                                 rrow, q, {ref_row(rrow), 8'd0});
                                end
                            end else begin
                                t7k_cnt = t7k_cnt + 1;
                                if (q !== {ref_row(rrow), exp_k[7:0]}) begin
                                    t7k_bad = t7k_bad + 1;
                                    if (t7k_bad <= 3)
                                        $display("T7k 行内不符：标签(row=%0d,col=%0d) 输出=%04x 期望=%04x",
                                                 rrow, rcol, q, {ref_row(rrow), exp_k[7:0]});
                                end
                            end
                        end
                        if (ph_cnt < 14 && check == 1 && rrow == 5 && rcol < 4) begin
                            ph_cnt = ph_cnt + 1;
                            $display("PROBE PHASE row=%0d col=%0d d_out=%04x (cell k-1 应=%04x, cell k 应=%04x)",
                                     rrow, rcol, q, {ref_row(rrow), (rcol-1)}, {ref_row(rrow), rcol[7:0]});
                        end
                    end
                end
            end
        end
    endtask

    initial begin
        de = 0; x = 0; y = 0; d = 0; p_row = -1; p_col = 8'hFF; p_valid = 0;
        SLOTS = 1; while (SLOTS < LINES + 1) SLOTS = SLOTS * 2;   // 与被测模块同一把式子（2^clog2(LINES+1)）
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

        // ---- T7 / T8：真实光栅（x 自由跑到 H_TOTAL-1、并且走满一个竖消隐）----
        //   第一趟（rr==0）只预热：环里还是上面几个任务留下的内容，行首的绝对期望当然对不上；
        //   第二趟起才判，且此时每一行的第 0 列都已经被上一帧的同一槽写过 ⇒ 期望成立。
        raster(1, 0);
        raster(2, 1);
        line("T7 行首第一格 = 本行第一列（不是消隐期地址的格子）",
             t7_cnt > 12 && t7_bad == 0,
             "#102：消隐期 x 还在数 ⇒ 旧写法让行首读到 `x[H_TOTAL-1]` 低位那一格；行首要等于自己那一列");
        line("T7k 行内其余列一格都不许动（预读只许占用消隐那一拍）",
             t7k_cnt > 600 && t7k_bad == 0,
             "把中间任何一列挪动就是 #92 第一笔那族整列错位；这一条就是那一族的护栏");
        $display("INFO T7 行首样本 %0d 格、错 %0d 格 || 行内样本 %0d 格、错 %0d 格",
                 t7_cnt, t7_bad, t7k_cnt, t7k_bad);

        // ---- T6：覆盖面 ----
        line("T6 覆盖面不是空跑", (t1_cnt + t3_cnt + t7_cnt + t7k_cnt) > 1500,
             "逐格判据加起来要有几百格的覆盖面，否则差一格也可能被空窗混过去");

        if (nfail == 0) $display("RESULT tb_v100_raw_delay PASS");
        else            $display("RESULT tb_v100_raw_delay FAIL nfail=%0d", nfail);
        $finish;
    end
endmodule
