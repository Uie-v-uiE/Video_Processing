`timescale 1ns/1ps
// tb_v97_seam_scan —— 缝的逐列扫描（ISSUES #56 第 2 点欠的那条判据，也是 V8-4a 接 split_ctrl 之前的预检）
//
// 用户看到的症状是"碰到分割线的时候会在分割线周围出现类似的颜色条"。#56 已经查到代码里的来源：
// `split_display.v:32` 把 `x == PANE_W-1` 与 `x == PANE_W` **两列强行涂蓝**（V6 时代画的"分界标记"）。
// 但"知道是这两列"和"有一条判据保证只有这两列、别处不许冒出第三种颜色"是两件事 —— 后者才有本文件。
// V8-4a 把缝位从参数变成寄存器之后，本判据自动变成验收测试；S6 那一组极端缝位（1 / 0 / 1024）
// 就是提前踩点：`x == PANE_W-1` 在 PANE_W=0 时是 −1，与 12 位无符号 `x` 比较会不会把整行涂蓝，
// 这种错在板子上表现为"分割线指令一开就满屏蓝"，而在这里是一行红的数。
//
// 期望值全部由**定义**算，不抄 RTL：
//   · 5/6 bit → 8 bit：`round(v*255/(2^n−1))`，容差 ±1 LSB（位复制应当落在这个带里）；
//   · 左/右内容按 `x < PANE_W` 选；越界=黑；标记列=那一种蓝。
// 标签用 ASCII：见 skill/bench_self_inflicted_reds.md 末尾关于 gbk 控制台的那一条。
module tb_v97_seam_scan;
    localparam [15:0] ORIG = 16'h1234;          // 左窗内容：一个已知的 RGB565 值
    localparam [15:0] PROC = 16'hF81F;          // 右窗内容：另一个（红 + 蓝，与 ORIG 明显不同）
    localparam [7:0]  MR = 8'h40, MG = 8'h40, MB = 8'hFF;   // RTL 里写死的标记色

    reg clk = 0, rst_n = 0;
    reg [11:0] x_sel = 12'd0;      // 与内容同级的列坐标（本 TB 里由测试自己驱动）
    reg        marker  = 1'b1;     // 2 px 标记线开关（V8-4 起可关）
    reg        sel_override = 1'b0;// S7b：1 = 让 x_sel 故意比 x 落后 sel_lag 列
    reg [11:0] sel_lag     = 12'd9;
    always #10 clk = ~clk;

    reg  [11:0] x, y;
    reg         de, hs, vs, oob_l, oob_r;
    reg  [1:0]  angle_idx;
    reg  [15:0] orig_pix, proc_pix;

    integer errors = 0;

    task expect(input [639:0] name, input cond);
        begin
            if (cond !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL %0s (t=%0t)", name, $time);
            end else $display("PASS %0s", name);
        end
    endtask

    function integer exp5; input integer v; begin exp5 = (v * 255 + 15) / 31; end endfunction
    function integer exp6; input integer v; begin exp6 = (v * 255 + 31) / 63; end endfunction
    function integer diff; input integer a; input integer b; begin diff = (a > b) ? (a - b) : (b - a); end endfunction
    function integer near1; input integer a; input integer b; begin near1 = diff(a, b) <= 1; end endfunction

    /* ================= 实例 A：板上用的 512 ================= */
    wire [7:0] ra, ga, ba;  wire dea, hsa, vsa;
    split_display #(.PANE_W(512)) u_a (
        .clk(clk), .rst_n(rst_n), .x(x), .y(y), .de(de), .hs(hs), .vs(vs), .x_sel(x_sel), .marker(marker),
        .orig_pix(orig_pix), .proc_pix(proc_pix), .angle_idx(angle_idx),
        .oob_l(oob_l), .oob_r(oob_r), .r(ra), .g(ga), .b(ba),
        .de_out(dea), .hs_out(hsa), .vs_out(vsa));

    /* ============ 实例 B/C/D：极端缝位（V8-4a 会遇到的那三个） ============ */
    wire [7:0] rb, gb, bb;  wire deb;
    split_display #(.PANE_W(1)) u_b (
        .clk(clk), .rst_n(rst_n), .x(x), .y(y), .de(de), .hs(hs), .vs(vs), .x_sel(x_sel), .marker(marker),
        .orig_pix(orig_pix), .proc_pix(proc_pix), .angle_idx(angle_idx),
        .oob_l(oob_l), .oob_r(oob_r), .r(rb), .g(gb), .b(bb), .de_out(deb));
    wire [7:0] rc, gc, bc;  wire dec;
    split_display #(.PANE_W(0)) u_c (
        .clk(clk), .rst_n(rst_n), .x(x), .y(y), .de(de), .hs(hs), .vs(vs), .x_sel(x_sel), .marker(marker),
        .orig_pix(orig_pix), .proc_pix(proc_pix), .angle_idx(angle_idx),
        .oob_l(oob_l), .oob_r(oob_r), .r(rc), .g(gc), .b(bc), .de_out(dec));
    wire [7:0] rd, gd, bd;  wire ded;
    split_display #(.PANE_W(1024)) u_d (
        .clk(clk), .rst_n(rst_n), .x(x), .y(y), .de(de), .hs(hs), .vs(vs), .x_sel(x_sel), .marker(marker),
        .orig_pix(orig_pix), .proc_pix(proc_pix), .angle_idx(angle_idx),
        .oob_l(oob_l), .oob_r(oob_r), .r(rd), .g(gd), .b(bd), .de_out(ded));

    // 一列的期望颜色（按定义算）：marker=1 表示这一列按规格该是标记蓝
    task set_pix(input [11:0] xx, input d, input oob);   // ⚠ 参数名不能叫 de：会和模块的 reg de 撞名
        reg [11:0] sel_of;
        begin sel_of = (sel_override == 1'b1) ? (xx - sel_lag) : xx;
            x = xx; y = 12'd100; de = d; hs = ~d; vs = 1'b0;
            oob_l = oob; oob_r = oob; angle_idx = 2'd0;
            orig_pix = ORIG; proc_pix = PROC;
            x_sel  = sel_of;                         // 默认与 x 同级（老行为）；S7b 会故意让它错开
            @(posedge clk); #1;
        end
    endtask

    integer i, n_marker, n_wrong_marker, n_wrong_content, n_de_bad, n_left, n_right;

    /* ---------- 对实例 A 扫一遍 0..1023 ---------- */
    task sweep_a(input [11:0] pane);
        begin
            n_marker = 0; n_wrong_marker = 0; n_wrong_content = 0; n_de_bad = 0; n_left = 0; n_right = 0;
            for (i = 0; i < 1024; i = i + 1) begin
                set_pix(i[11:0], 1'b1, 1'b0);
                if (dea !== 1'b1) n_de_bad = n_de_bad + 1;             // de 只许延迟一拍，不许丢
                if (i == (pane - 1) || i == pane) begin
                    n_marker = n_marker + 1;
                    if (ra !== MR || ga !== MG || ba !== MB) n_wrong_marker = n_wrong_marker + 1;
                end else begin
                    if (ra === MR && ga === MG && ba === MB) n_wrong_marker = n_wrong_marker + 1;
                    if (i < pane) begin
                        n_left = n_left + 1;
                        if (!(near1(ra, exp5(ORIG[15:11])) && near1(ga, exp6(ORIG[10:5]))
                              && near1(ba, exp5(ORIG[4:0])))) n_wrong_content = n_wrong_content + 1;
                    end else begin
                        n_right = n_right + 1;
                        if (!(near1(ra, exp5(PROC[15:11])) && near1(ga, exp6(PROC[10:5]))
                              && near1(ba, exp5(PROC[4:0])))) n_wrong_content = n_wrong_content + 1;
                    end
                end
            end
        end
    endtask

    /* ---------- 极端缝位：只问一件事——有没有"整行/整侧被涂成标记色" ---------- */
    task marker_count(input [11:0] pane, output integer cnt);
        begin
            cnt = 0;
            for (i = 0; i < 1024; i = i + 1) begin
                set_pix(i[11:0], 1'b1, 1'b0);
                if (ra === MR && ga === MG && ba === MB) cnt = cnt + 1;
            end
        end
    endtask
    integer cnt0, cnt1, cnt1024;

    initial begin
        de = 0; hs = 1; vs = 1; x = 0; y = 0; oob_l = 0; oob_r = 0; angle_idx = 0;
        orig_pix = ORIG; proc_pix = PROC;
        repeat (3) @(posedge clk); #1; rst_n = 1;
        repeat (2) @(posedge clk); #1;

        sweep_a(12'd512);
        // ① 标记列**恰好两列**（511 与 512），并且别处一次都不许出现这个颜色
        expect("S1 exactly two marker columns and no stray marker colour anywhere else",
               n_marker == 2 && n_wrong_marker == 0);
        // ② 其余每一列的颜色 = 它那一侧内容的 RGB565→RGB888 定义值（±1 LSB）
        expect("S2 non-marker columns match their own side (L=orig R=proc)",
               n_wrong_content == 0 && n_left == 511 && n_right == 511);
        // ③ de 只是延迟一拍：整行 1024 列都不许掉
        expect("S3 de survives the seam logic on all 1024 columns", n_de_bad == 0);

        // ④ 越界必须是黑（缩小后的空边），而标记列当前**优先于**越界 —— 这是写下来的现有口径：
        //    V8-4a 若改成"越界处不画标记"，这一条必须红，逼改的人明说自己换了口径。
        begin : s4
            integer blk, mk;
            blk = 1; mk = 1;
            set_pix(12'd300, 1'b1, 1'b1);
            if (ra !== 8'd0 || ga !== 8'd0 || ba !== 8'd0) blk = 0;
            set_pix(12'd511, 1'b1, 1'b1);
            if (!(ra === MR && ga === MG && ba === MB)) mk = 0;
            expect("S4 out-of-range is black and the marker currently wins over OOB (documented)",
                   blk && mk);
        end

        // ⑤ 消隐期不许"新画"标记：de=0 时输出保持上一个样子，不会凭空多出蓝列
        //    （为什么这条值得单列：将来把标记改成可参数时，最容易顺手写成
        //     `if (sep) ...` 而丢掉 `&& de` —— 那样**每一行的消隐期都会被涂成蓝**。）
        begin : s5
            integer kept;
            kept = 1;
            set_pix(12'd300, 1'b1, 1'b0);                 // 先取一个正常的左窗列
            if (ra === MR && ga === MG && ba === MB) kept = 0;
            x = 12'd511; de = 1'b0; x_sel = 12'd511;   // 标记位置该成立，只有 de 不许成立
            @(posedge clk); #1;
            if (ra === MR && ga === MG && ba === MB) kept = 0;   // 上一样子是 300 列的内容，不是蓝
            expect("S5 with de=0 the seam does not paint a fresh marker (keeps prior pixel)",
                   kept == 1);
        end

        // ⑥ 极端缝位（同一个实例 A，参数不同 ⇒ 用 B/C/D 三个实例）：
        //    缝=1：标记应在 0 与 1 两列；缝=0：`x == PANE_W-1` 是 −1，**不许**匹配任何列；
        //    缝=1024：标记在 1023 一列（1024 在屏外）。这三档各数一遍标记列数。
        begin : s6
            integer c1, c0, cN, bad_sel_d;
            c1 = 0; c0 = 0; cN = 0; bad_sel_d = 0;
            for (i = 0; i < 1024; i = i + 1) begin
                set_pix(i[11:0], 1'b1, 1'b0);
                if (rb === MR && gb === MG && bb === MB) c1 = c1 + 1;
                if (rc === MR && gc === MG && bc === MB) c0 = c0 + 1;
                if (rd === MR && gd === MG && bd === MB) cN = cN + 1;
                // PANE_W=1024 ⇒ 整屏都该是"左窗"内容 = ORIG
                if (!(near1(rd, exp5(ORIG[15:11])) || (rd === MR && gd === MG && bd === MB)))
                    bad_sel_d = bad_sel_d + 1;
            end
            expect("S6a PANE_W=1 marks exactly two columns (0 and 1)", c1 == 2);
            expect("S6b PANE_W=0 must not paint the whole line (x==PANE_W-1 must never match)",
                   c0 == 1);                 // 只剩 x==0 这一列；−1 那一列必须不匹配
            expect("S6c PANE_W=1024 puts the marker on the last column only", cN == 1);
            expect("S6d PANE_W=1024 keeps the whole screen on the original side", bad_sel_d == 0);
        end

        // ⑦ r59a 新增：`x_sel` / `marker` 两个入口的语义（ISSUES #68 的修法 + #56-2(a) 的可关性）
        begin : s7
            integer no_mk, cont_left_bad, mk_ok, mk_bad;
            no_mk = 0; cont_left_bad = 0; mk_ok = 0; mk_bad = 0;
            // S7a：关掉标记线 ⇒ 整行一列蓝都不许有；左右内容的分界照旧（不许顺手改掉选择逻辑）
            marker = 1'b0; sel_override = 1'b0;
            for (i = 0; i < 1024; i = i + 1) begin
                set_pix(i[11:0], 1'b1, 1'b0);
                if (ra === MR && ga === MG && ba === MB) no_mk = no_mk + 1;
                if (i < 512 && !near1(ra, exp5(ORIG[15:11]))) cont_left_bad = cont_left_bad + 1;
            end
            expect("S7a marker=0 时一列蓝都没有（V8-4 关标记线的凭据）", no_mk == 0);
            expect("S7b 关线之后左窗内容仍是 orig（选择逻辑没被顺手改掉）", cont_left_bad == 0);
            // S7c：让 x_sel 故意比 x 落后 9 列 ⇒ 蓝线必须落在 x = 520/521（= 511+9 / 512+9），
            //       而不是 x = 511/512 ⇒ 证明"标记与选路由 x_sel 决定"，也就是 #68 的修法。
            marker = 1'b1; sel_override = 1'b1; sel_lag = 12'd9;
            for (i = 0; i < 1024; i = i + 1) begin
                set_pix(i[11:0], 1'b1, 1'b0);
                if (ra === MR && ga === MG && ba === MB) begin
                    if (i == 520 || i == 521) mk_ok = mk_ok + 1; else mk_bad = mk_bad + 1;
                end
            end
            expect("S7c 标记线跟着 x_sel（与内容同级的坐标）走，不跟着 x", mk_ok == 2 && mk_bad == 0);
            sel_override = 1'b0;

            // ⑧ r59a：缝位本身也该跟着 x_sel ⇒ 内容的左右分界随 x_sel 移动 9 列
            marker = 1'b1; sel_override = 1'b1; sel_lag = 12'd9;
            mk_ok = 0; mk_bad = 0;
            // ⚠ 520/521 这两列正是标记蓝的落点（x_sel=511/512），内容判据必须把它们跳过去 ——
            //   第一版没跳，红在我自己的期望上（不是模块错）：这条记下来，因为"边界前一列是标记"
            //   这种重叠在 V8-4 真做可动缝时还会再来一次。
            for (i = 512; i < 520; i = i + 1) begin          // x=512..519：x_sel=503..510 仍是"左"
                set_pix(i[11:0], 1'b1, 1'b0);
                if (!near1(ra, exp5(ORIG[15:11]))) mk_bad = mk_bad + 1;
            end
            for (i = 522; i < 541; i = i + 1) begin          // x>=522 ⇒ x_sel>=513 = "右" ⇒ proc
                set_pix(i[11:0], 1'b1, 1'b0);
                if (!near1(ra, exp5(PROC[15:11]))) mk_bad = mk_bad + 1;
                else mk_ok = mk_ok + 1;
            end
            expect("S8 左右内容的分界同样跟着 x_sel（缝=参数化的前提）", mk_bad == 0 && mk_ok == 19);
            sel_override = 1'b0;
        end

        if (errors == 0) $display("PASS tb_v97_seam_scan");
        else             $display("FAIL tb_v97_seam_scan errors=%0d", errors);
        $finish;
    end

    initial begin : watchdog
        #300_000;
        $display("FAIL tb_v97_seam_scan timeout");
        $finish;
    end
endmodule
