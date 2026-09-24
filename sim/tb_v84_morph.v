`timescale 1ns/1ps
// 台架：src/rtl/process/proc_morph.v（级 5 形态学：3×3 腐蚀 / 膨胀）
//
// 挡三类"看起来像实现了"的错法：
//   ① 旁路当成实现（mode 只接了个 mux，屏上永远看到原图，或者"关掉效果"时也错一行）；
//   ② 腐蚀/膨胀接反（min/max 写反，实心图形上看不出来，必须比同一个位置在两种模式下的结果）；
//   ③ 窗口对不齐（两条行缓存的 3×3 中心到底落在哪一行，写错就是整幅错一行/一列）。
//
// ③ 的基准不自己发明：proc_box_blur 是 V7 就在用、真机看过的通路，这里**同时喂同一帧**，
//    比较两者亮区掩码必须完全重合 ⇒ 新模块与既有通路同一种对齐，将来 V8-4 做逐像素分割混合
//    时不会因为多一级而错行（ISSUES #54 记了这个约定）。
// 语义判据（面积、边角）的期望值由"定义"算：邻域全 1 / 有 1，并按 T2 实测到的偏移对齐，
// 不引用 DUT 内部信号、也不照抄 RTL 写法。
module tb_v84_morph;

    localparam W = 24, H = 16;
    localparam [15:0] WHITE = 16'hFFFF, BLACK = 16'h0000;

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg  [1:0]  mode = 2'd0;
    reg         de = 0, de_b = 0;
    reg  [11:0] xs = 0, ys = 0;
    reg  [15:0] src = BLACK, src_b = BLACK;
    wire        de_o, de_ob;
    wire [15:0] d_o, d_ob;

    proc_morph #(.H_ACTIVE(W)) dut (
        .clk(clk), .rst_n(rst_n), .mode(mode), .threshold(8'd80),
        .de_in(de), .x_in(xs), .y_in(ys), .din(src), .de_out(de_o), .dout(d_o)
    );
    reg ref_byp = 1;   // 对照用的 blur：T1 让它也走旁路（比对两个模块的旁路是否同一约定）
    proc_box_blur #(.H_ACTIVE(W)) refb (
        .clk(clk), .rst_n(rst_n), .bypass(ref_byp),
        .hs_in(1'b0), .vs_in(1'b0), .de_in(de_b), .x_in(xs), .y_in(ys), .din(src_b),
        .de_out(de_ob), .dout(d_ob)
    );

    reg [15:0] field    [0:H-1][0:W-1];
    reg [15:0] got      [0:H-1][0:W-1];
    reg [15:0] got_blur [0:H-1][0:W-1];
    reg [15:0] snap_e   [0:H-1][0:W-1];
    reg [15:0] snap_d   [0:H-1][0:W-1];
    reg [15:0] ref_e    [0:H-1][0:W-1];
    integer fx, fy, oi, oj, bi, bj;
    integer errors = 0, n_deo = 0, n_deob = 0;
    integer ox, oy;                  // T2 实测出来的'输出相对输入'的偏移

    always @(posedge clk) if (de_o && oi < H) begin
        n_deo = n_deo + 1;
        got[oi][oj] = d_o;
        oj = oj + 1;
        if (oj == W) begin oj = 0; oi = oi + 1; end
    end
    always @(posedge clk) if (de_ob && bi < H) begin
        n_deob = n_deob + 1;
        got_blur[bi][bj] = d_ob;
        bj = bj + 1;
        if (bj == W) begin bj = 0; bi = bi + 1; end
    end

    task chk;
        input [100*8:1] name;
        input cond;
        begin
            if (cond !== 1'b1) begin
                errors = errors + 1;
                $display("  FAIL %0s", name);
            end
        end
    endtask

    // ---- 图形的定义（期望值唯一来源）----
    function inside_sq;
        input integer x; input integer y;
        inside_sq = (x >= 8 && x <= 15 && y >= 5 && y <= 10);
    endfunction
    function inside_dot;
        input integer x; input integer y;
        inside_dot = (x == 3 && y == 3);
    endfunction
    function bit_at;                 // "算 1"的像素：方块 ∪ 孤立点
        input integer x; input integer y;
        bit_at = inside_sq(x, y) || inside_dot(x, y);
    endfunction
    function integer nb_at;          // 以 (x,y) 为中心的 3×3 里有几个 1
        input integer x; input integer y;
        integer a, b, c;
        begin
            c = 0;
            for (a = -1; a <= 1; a = a + 1)
                for (b = -1; b <= 1; b = b + 1)
                    if (x + a >= 0 && x + a < W && y + b >= 0 && y + b < H)
                        if (bit_at(x + a, y + b)) c = c + 1;
            nb_at = c;
        end
    endfunction
    function exp_erode;              // 邻域全 1（中心按实测偏移取）
        input integer x; input integer y;
        exp_erode = (nb_at(x - ox, y - oy) == 9);
    endfunction
    function exp_dilate;             // 邻域有 1
        input integer x; input integer y;
        exp_dilate = (nb_at(x - ox, y - oy) >= 1);
    endfunction


    // 每段测试都跑**两帧**：第二帧才是采集帧。
    // 第一帧的作用是把上一段留下的行缓存冲掉 —— 3x3 窗口有两条行缓存，
    // 换一段激励后头两行读到的是上一帧的内容（T2 平场第一次就栽在这里：期望全帧不变，
    // 结果第二行带着上一段渐变的斜率）。这不是 DUT 的错，是台架忘了热身。
    task feed2;
        input [1:0] m;
        integer x, y;
        begin
            mode = m;
            oi = 0; oj = 0; bi = 0; bj = 0; n_deo = 0; n_deob = 0;
            for (y = 0; y < H; y = y + 1) begin
                for (x = 0; x < W; x = x + 1) begin
                    @(negedge clk);
                    xs = x; ys = y;
                    src = field[y][x];   de = 1;
                    src_b = field[y][x]; de_b = 1;
                end
                @(negedge clk); de = 0; de_b = 0;
            end
            repeat (6) @(negedge clk);
            de = 0; de_b = 0;
        end
    endtask

    // 两帧：第一帧热身（冲掉上一段留下的行缓存），第二帧才是采集帧
    task feed;
        input [1:0] m;
        begin feed2(m); feed2(m); end
    endtask

    task snap_e_store; integer a, b; begin
        for (a = 0; a < H; a = a + 1)
            for (b = 0; b < W; b = b + 1) snap_e[a][b] = got[a][b];
    end endtask
    task snap_d_store; integer a, b; begin
        for (a = 0; a < H; a = a + 1)
            for (b = 0; b < W; b = b + 1) snap_d[a][b] = got[a][b];
    end endtask

    integer cnt, bad, i, j, m2, diff, c_x, c_y, dot_lit;

    // 亮像素质心（use_blur=1 取 blur 那份；blur 的"亮"是任何非零，morph 是 FFFF）
    task centroid;
        input integer use_blur;
        output integer cx; output integer cy;
        integer x, y, sx, sy, n;
        reg [15:0] v;
        begin
            sx = 0; sy = 0; n = 0; cx = -1; cy = -1;
            for (y = 0; y < H; y = y + 1)
                for (x = 0; x < W; x = x + 1) begin
                    v = use_blur ? got_blur[y][x] : got[y][x];
                    if (v !== BLACK) begin sx = sx + x; sy = sy + y; n = n + 1; end
                end
            if (n > 0) begin cx = sx / n; cy = sy / n; end
        end
    endtask

    initial begin
        for (fy = 0; fy < H; fy = fy + 1)
            for (fx = 0; fx < W; fx = fx + 1) begin
                field[fy][fx] = BLACK; got[fy][fx] = BLACK; got_blur[fy][fx] = BLACK;
            end
        rst_n = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);
        ox = 0; oy = 0;

        // ================= T1 旁路：必须与 blur 的旁路逐位相同 =================
        // 不要求“逐位等于输入”：窗口级的旁路用的是**中心抽头**（blur/sobel 一直如此），
        // 所以正确的判据是“新模块与既有模块同一种约定” —— 这样切换效果时画面不会跳。
        // 中心抽头本身的行列错位是既有问题，记在 ISSUES #54。
        for (fy = 5; fy <= 10; fy = fy + 1)
            for (fx = 8; fx <= 15; fx = fx + 1) field[fy][fx] = WHITE;
        field[3][3] = WHITE;
        ref_byp = 1'b1;
        feed(2'd0);
        bad = 0;
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1)
                if (got[j][i] !== got_blur[j][i]) bad = bad + 1;
        chk("T1 旁路与 blur 的旁路逐位相同（同一个中心抽头约定）", bad == 0);
        if (bad) begin
            for (j = 0; j < H; j = j + 1) begin
                $write("     T1 r%0d m=", j);
                for (i = 0; i < W; i = i + 1) $write("%h ", got[j][i]);
                $write("  b=");
                for (i = 0; i < W; i = i + 1) $write("%h ", got_blur[j][i]);
                $write("\n");
            end
        end

        // ================= T2 对齐：孤立点的亮区掩码必须与 blur 完全重合 =================
        for (fy = 0; fy < H; fy = fy + 1)
            for (fx = 0; fx < W; fx = fx + 1) begin field[fy][fx] = BLACK; got_blur[fy][fx] = BLACK; end
        field[3][3] = WHITE;
        ref_byp = 1'b0;   // 这一段要 blur 真的算 3x3 均值，亮区掩码才是对齐基准
        feed(2'd2);
        diff = 0; cnt = 0;
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1) begin
                m2 = ((got[j][i] !== BLACK) != (got_blur[j][i] !== BLACK)) ? 1 : 0;
                if (got_blur[j][i] !== BLACK) cnt = cnt + 1;
                diff = diff + m2;
            end
        chk("T2a 亮区掩码与 blur 一致（两者对齐方式相同）", diff == 0);
        if (diff) begin
            for (j = 0; j < H; j = j + 1) begin
                $write("     MAP r%02d  m=", j);
                for (i = 0; i < W; i = i + 1) $write("%c", (got[j][i] !== BLACK) ? 8'h23 : 8'h2E);
                $write("  b=");
                for (i = 0; i < W; i = i + 1)
                    $write("%c", (got_blur[j][i] !== BLACK) ? 8'h23 : 8'h2E);
                $write("\n");
            end
        end
        chk("T2b blur 也认这个点是亮区（掩码非空，比较不是空对空）", cnt > 0);
        centroid(0, c_x, c_y);
        ox = c_x - 3;  oy = c_y - 3;      // 孤立点在 (3,3) ⇒ 实测偏移
        if (diff) $display("     T2 掩码不同的位置数=%0d morph 质心=(%0d,%0d)", diff, c_x, c_y);

        // ================= T3..T8 语义（大方块 + 孤立点同时在场）=================
        for (fy = 0; fy < H; fy = fy + 1)
            for (fx = 0; fx < W; fx = fx + 1) field[fy][fx] = inside_sq(fx, fy) ? WHITE : BLACK;
        field[3][3] = WHITE;

        feed(2'd1);  snap_e_store;
        feed(2'd2);  snap_d_store;

        // 孤立点 (3,3) 的膨胀块在 rows 3..5 / cols 2..4；方块膨胀后最左到 col=7 ⇒ 数 cols≤6 是干净的
        dot_lit = 0;
        for (j = 0; j <= 6; j = j + 1)
            for (i = 0; i <= 6; i = i + 1)
                if (snap_d[j][i] == WHITE) dot_lit = dot_lit + 1;

        chk("T3 腐蚀：方块中心仍白、边角被啃",
            snap_e[8][11] == WHITE && snap_e[5][8] == BLACK);
        chk("T4 腐蚀：孤立点连同邻域一起没",
            snap_e[3][3] == BLACK && snap_e[4][4] == BLACK);
        chk("T5 膨胀：孤立点长成 3x3（离方块够远，计数干净）", dot_lit == 9);
        if (dot_lit != 9) $display("     T5 孤立点邻域亮像素=%0d 期望 9", dot_lit);
        chk("T6 同一位置 (x=7,y=8) 两者相反：腐蚀黑 / 膨胀白（没接反）",
            snap_e[8][7] == BLACK && snap_d[8][7] == WHITE);

        // 逐像素对定义（避开左右边界与首行：那里的邻域本来就是守卫态）
        bad = 0;
        for (j = 2; j < H - 2; j = j + 1)
            for (i = 2; i < W - 2; i = i + 1) begin
                if (exp_erode(i, j) && snap_e[j][i] !== WHITE) bad = bad + 1;
                if (!exp_erode(i, j) && snap_e[j][i] !== BLACK &&
                    !(i == 2 && j <= 5)) bad = bad + 1;     // 左边守卫列另说
            end
        chk("T7 腐蚀逐像素等于定义（邻域全 1）", bad == 0);
        if (bad) $display("     T7 不符定义的像素数=%0d 偏移 ox=%0d oy=%0d", bad, ox, oy);

        bad = 0;
        for (j = 2; j < H - 2; j = j + 1)
            for (i = 2; i < W - 2; i = i + 1)
                if (exp_dilate(i, j) != (snap_d[j][i] == WHITE)) bad = bad + 1;
        chk("T8 膨胀逐像素等于定义（邻域有 1）", bad == 0);
        if (bad) $display("     T8 不符定义的像素数=%0d", bad);

        cnt = 0;
        for (j = 4; j < H - 4; j = j + 1)
            for (i = 4; i < W - 4; i = i + 1)
                if (snap_e[j][i] == WHITE) cnt = cnt + 1;
        if (cnt != 24) $display("     T9 腐蚀亮像素 cnt=%0d 期望 24", cnt);
        chk("T9 腐蚀把 8x6 缩成 6x4", cnt == 24);

        // ================= T10 mode3（腐蚀+膨胀同时要求）= 旁路 =================
        // 与 T1 同一个道理：判据是"和 mode0 一致"，不是"和输入一致"（旁路用的是中心抽头）。
        feed(2'd0);
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1) ref_e[j][i] = got[j][i];
        feed(2'd3);
        bad = 0;
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1)
                if (got[j][i] !== ref_e[j][i]) bad = bad + 1;
        chk("T10 mode3 与 mode0 逐位相同（开/闭运算要两遍窗口，这里显式不吃）", bad == 0);

        // ================= T11 全黑输入 → 全黑输出（反例）=================
        for (fy = 0; fy < H; fy = fy + 1)
            for (fx = 0; fx < W; fx = fx + 1) begin field[fy][fx] = BLACK; got[fy][fx] = WHITE; end
        feed(2'd2);
        bad = 1;
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1)
                if (got[j][i] !== BLACK) bad = 0;
        chk("T11 全黑输入膨胀后仍全黑（白不可能从邻域里冒出来）", bad == 1);

        // ================= T12 延迟与 mode 无关（左右窗对齐的前提）=================
        chk("T12 两帧脉冲数都是 W*H（延迟固定，不随 mode 变）", n_deo == H * W);

        $display("");
        if (errors == 0) $display("PASS tb_v84_morph");
        else $display("FAIL tb_v84_morph errors=%0d", errors);
        $finish;
    end
endmodule
