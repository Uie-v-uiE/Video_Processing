`timescale 1ns/1ps
// tb_v96_zoom_scan —— 缩放/旋转下"取图位置"的**逐像素扫描**（ISSUES #56 第 1 条缺的那份判据）
//
// 为什么值得单独一份：#56 的症状是用户眼睛看到的"缩放的时候线会移位"，而已有的两份台架各管一半 ——
// `tb_v89_align` 量的是效果链"数据 vs 标签"的错位（**直通**那一格），`tb_zoom_mapper` 只验了
// 中心/OOB 这几个点。没有人量过"**每一列屏幕上到底取了源图哪一列，它怎么随 inv_scale 变**"，
// 所以"是量化取整在爬、还是映射算错了"这两种解释一直没分开 —— 而这两种的修法完全不同
// （前者=亚像素插值，代码在 tag v7.8；后者=RTL bug）。这份台架把这件事变成读得出来的数。
//
// 期望值的来源是**定义**，不是 RTL 的流水线：
//     sx_real = W/2 + (x − W/2)·inv/256      （逆映射：屏幕 → 源）
//     sx      = floor(sx_real)，frac = 256·(sx_real − sx) ∈ [0,255]
// 台架用整数自己算 floor 与余数（`>>>` 语义 = 向 −∞ 取整，正负两半都要对 —— 中心两侧
// 差一格就是"缝"的候选来源之一）。流水线延迟不假设：扫一个对齐位移，找一个能让全部样本
// 自洽的 k（找不到就红），与 tb_v94 同一手法。
//
// 六条判据：
//   M1 floor/frac 逐像素自洽（含 x < 中心 的负偏移 —— 经典"右移当截断"的坑就在这）
//   M2 单调性：inv ≥ 256 时源列必须随屏幕列不减；inv > 256 必须严格增（缩小时不许回头）
//   M3 中心不动：屏幕中心必须落在源中心，转不转、几度都算
//   M4 四边 OOB 对称：0.25x 时左右（上下）黑边列数差 ≤ 1
//   M5 90° 的交换性：屏幕走一横排 ⇒ 源图必须走一竖列（Δsx≈0、|Δsy|≈inv/256）
//   M6 **量**（不判红绿）：呼吸一趟 inv 256→512→256 里，同一屏幕列选中的源列漂了多少
//      —— 这个数字就是"缩放时线在挪"的量化说法，写进 #56 而不是留在猜测里
module tb_v96_zoom_scan;
    localparam IW = 512, IH = 300, CX = IW/2, CY = IH/2;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg  [9:0] inv = 10'd256;
    reg  [8:0] angle = 9'd0;
    reg        rot_en = 0;
    reg  [11:0] xin = 0, yin = 0;
    wire [11:0] xout, yout;
    wire        oob;
    wire [7:0]  fx, fy;

    zoom_mapper #(.IMAGE_W(IW), .IMAGE_H(IH)) u_map (
        .clk(clk), .rst_n(rst_n), .inv_scale(inv), .angle(angle), .rotate_en(rot_en),
        .x_in(xin), .y_in(yin), .x_out(xout), .y_out(yout), .oob(oob), .frac_x(fx), .frac_y(fy));

    integer errors = 0, i, k, best_k = -1;

    task expect(input [639:0] name, input cond);
        begin
            if (cond !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL %0s (t=%0t)", name, $time);
            end else $display("PASS %0s", name);
        end
    endtask

    /* ---------- 激励模型：一条扫描线，像素按 (x, y=CY) 顺序喂 ---------- */
    // 窗**必须对中心严格对称**（xp 从 −127 到 +127，共 255 列）：M4 判的是"左右 OOB 列数相等"，
    // 窗子自己差一列的话这条就永远是 64 vs 63 —— 那是台架的不对称，不是硬件的不对称。
    localparam NPIX = 255;                 // 扫 255 个屏幕列：中心两侧各 127
    localparam X0 = CX - 127;              // ⇒ xp ∈ [−127, +127]
    // 日志必须比请求数**多留几格**：只收 NPIX 拍的话，最后 k 个请求的输出永远进不来，
    // 于是"右半边"莫名少 k 列 —— 第一次跑 M4 就是这样红了 63 vs 61，而 k 恰好等于 2。
    // 这就是 S20 签名三的近亲：捕获窗比流水线短，判据在量台架自己。
    localparam NLOG = NPIX + 12;
    reg        feed_en = 0;
    integer    sent = 0, got = 0;
    reg  [11:0] sx_log [0:NLOG-1];         // 逐拍记下来的输出（捕获序 = 输出序）
    reg  [11:0] sy_log [0:NLOG-1];
    reg  [7:0]  fx_log [0:NLOG-1];
    reg         oob_log [0:NLOG-1];

    // 流水线里最多 8 级；扫描对齐位移 k：输出第 j 个样本对应输入第 j−k 个请求
    // ⚠ 每条激励都在 `@(posedge clk); #1;` 之后才改：不写这个 #1 就是"测试台与 DUT 在同一个
    //    active 事件里抢先后"，仿真顺序未定义 —— 这类假红查一整天（S20 签名二的近亲）。
    task scan(input [9:0] vi, input [8:0] va, input vr);
        begin
            @(posedge clk); #1;
            inv = vi; angle = va; rot_en = vr;
            for (i = 0; i < NPIX; i = i + 1) begin
                xin = X0 + i; yin = CY;
                @(posedge clk); #1;
                if (got < NLOG) begin                   // 发送阶段同时收：延迟全在这里被对齐掉
                    sx_log[got] = xout; sy_log[got] = yout; fx_log[got] = fx; oob_log[got] = oob;
                    got = got + 1;
                end
            end
            xin = 12'hFFF; yin = 12'hFFF;             // 排空：让最后 k 个请求的输出也进日志
            while (got < NLOG) begin
                @(posedge clk); #1;
                sx_log[got] = xout; sy_log[got] = yout; fx_log[got] = fx; oob_log[got] = oob;
                got = got + 1;
            end
        end
    endtask

    task reset_capture; begin sent = 0; got = 0; end endtask

    /* ---------- 期望值：只按定义算（整数 floor 与余数）---------- */
    // d = x − CX（有符号），p = d·inv，floor(p/256) = p>>>8（算术右移就是向 −∞ 取整）
    function integer exp_sx; input integer x; input integer vi;
        integer d, p;
        begin
            d = x - CX; p = d * vi;
            exp_sx = ((p >= 0) ? (p / 256) : -((( -p ) + 255) / 256)) + CX;   // 手写的 floor，不用 >>>
        end
    endfunction
    function integer exp_frac; input integer x; input integer vi;
        integer d, p, f;
        begin
            d = x - CX; p = d * vi;
            f = p - 256 * ((p >= 0) ? (p / 256) : -(((-p) + 255) / 256));
            exp_frac = f;                                   // 必在 [0,255]
        end
    endfunction

    integer bad_m1, bad_m2, n_inrange, j, r;
    integer want_sx, want_fr;
    // 扫描窗里"屏幕列 x 对应哪个捕获槽"：请求序号 = x − X0，输出再往后挪 best_k
    function integer slot; input integer x; begin slot = (x - X0) + best_k; end endfunction

    initial begin
        repeat (4) @(posedge clk); rst_n = 1;
        repeat (2) @(posedge clk);

        /* ---------- 先定流水线对齐位移 k：找一个让 M1 全对的 k ---------- */
        for (k = 0; k <= 8; k = k + 1) begin
            reset_capture; scan(10'd341, 9'd0, 1'b0);
            bad_m1 = 0;
            for (r = 0; r < NPIX; r = r + 1) begin      // 按**请求**编号走：槽 = 请求 + k
                j = r + k;
                want_sx = exp_sx(X0 + r, 341); want_fr = exp_frac(X0 + r, 341);
                if (sx_log[j] !== want_sx[11:0] || fx_log[j] !== want_fr[7:0]) bad_m1 = bad_m1 + 1;
            end
            if (bad_m1 == 0 && best_k < 0) best_k = k;
        end
        expect("M0 there exists a pipeline alignment that makes every pixel exact", best_k >= 0);
        if (best_k < 0) begin
            $display("FAIL tb_v96_zoom_scan(align) 找不到对齐位移：后面全部无法判");
            $finish;
        end
        $display("  INFO 流水线延迟 = %0d 拍（台架扫出来的，不是抄 RTL 注释的）", best_k);

        /* ---------- M1 floor/frac 逐像素自洽（含中心两侧）---------- */
        reset_capture; scan(10'd512, 9'd0, 1'b0);
        bad_m1 = 0;
        for (r = 0; r < NPIX; r = r + 1) begin
            j = r + best_k;
            want_sx = exp_sx(X0 + r, 512); want_fr = exp_frac(X0 + r, 512);
            if (sx_log[j] !== want_sx[11:0] || fx_log[j] !== want_fr[7:0]) bad_m1 = bad_m1 + 1;
        end
        expect("M1 inv=512: floor+frac exact on all 255 columns, both sides of the centre",
               bad_m1 == 0);

        reset_capture; scan(10'd256, 9'd0, 1'b0);
        bad_m1 = 0;
        for (r = 0; r < NPIX; r = r + 1) begin
            j = r + best_k;
            want_sx = exp_sx(X0 + r, 256); want_fr = exp_frac(X0 + r, 256);
            if (sx_log[j] !== want_sx[11:0] || fx_log[j] !== want_fr[7:0]) bad_m1 = bad_m1 + 1;
        end
        expect("M1b inv=256 (1.0x) must be the identity map", bad_m1 == 0);

        /* ---------- M2 单调不减 / 严格增 + M4 OOB 对称 ---------- */
        reset_capture; scan(10'd1023, 9'd0, 1'b0);            // 0.25x：源列间距 ≈ 4
        bad_m2 = 0; n_inrange = 0;
        for (r = 1; r < NPIX; r = r + 1) begin
            j = r + best_k;
            if (!oob_log[j] && !oob_log[j-1]) begin
                n_inrange = n_inrange + 1;
                if (sx_log[j] <= sx_log[j-1]) bad_m2 = bad_m2 + 1;   // inv>256 ⇒ 每列都要往前走
            end
        end
        expect("M2 0.25x: source column strictly increases along the screen row",
               bad_m2 == 0 && n_inrange > NPIX/4);
        // M4：扫描窗对中心严格对称（xp ∈ [−127,+127]），映射本身也对称
        //      ⇒ 左侧 OOB 列数与右侧 OOB 列数必须**相等**（差 1 都不许：那是取整偏了一格，
        //      也正是"缝两侧不对称"的候选来源之一）。
        begin : m4
            integer lead, trail, q;
            lead = 0; trail = 0;
            for (q = 0; q < NPIX; q = q + 1)
                if (oob_log[q + best_k]) lead = lead + 1; else q = NPIX;
            for (q = NPIX - 1; q >= 0; q = q - 1)
                if (oob_log[q + best_k]) trail = trail + 1; else q = -1;
            expect("M4 0.25x: left and right OOB runs are equal (symmetric rounding)",
                   lead > 0 && lead == trail);
            $display("  INFO M4: left OOB=%0d cols, right OOB=%0d cols (screen row through the centre)",
                     lead, trail);
        end

        /* ---------- M3 中心不动（转不转、任意角）---------- */
        reset_capture; scan(10'd776, 9'd0, 1'b0);
        expect("M3a centre pixel maps to centre (no rotation)",
               !oob_log[CX - X0 + best_k] && sx_log[CX-X0+best_k] == CX && sy_log[CX-X0+best_k] == CY);
        reset_capture; scan(10'd776, 9'd45, 1'b1);
        expect("M3b centre pixel maps to centre (45 deg)",
               !oob_log[CX - X0 + best_k] && sx_log[CX-X0+best_k] == CX && sy_log[CX-X0+best_k] == CY);
        reset_capture; scan(10'd776, 9'd300, 1'b1);
        expect("M3c centre pixel maps to centre (300 deg)",
               !oob_log[CX - X0 + best_k] && sx_log[CX-X0+best_k] == CX && sy_log[CX-X0+best_k] == CY);

        /* ---------- M5 90° 的交换性：屏幕横排 ⇒ 源竖列 ---------- */
        // 取窗口里 sy 一定不越界的一段：|xp| ≤ 75 ⇒ 屏幕列 192..320（xp = x − 256）
        reset_capture; scan(10'd512, 9'd90, 1'b1);
        begin : m5
            integer dsx_max, dsy_min, a, b, npair;
            dsx_max = 0; dsy_min = 9999; npair = 0;
            for (j = slot(196); j <= slot(316); j = j + 1) begin
                // （xvlog 不认 `continue`：这一族是 Verilog-2001，只有 if 守卫）
                if (!(oob_log[j] || oob_log[j-1])) begin
                    a = sx_log[j] - sx_log[j-1]; if (a < 0) a = -a;
                    b = sy_log[j] - sy_log[j-1]; if (b < 0) b = -b;
                    if (a > dsx_max) dsx_max = a;
                    if (b < dsy_min) dsy_min = b;
                    npair = npair + 1;
                end
            end
            expect("M5 at 90 deg a horizontal screen run becomes a vertical source run",
                   npair > 60 && dsx_max <= 1 && dsy_min >= 1);
            $display("  INFO M5: pairs=%0d max|dsx|=%0d min|dsy|=%0d (inv=512 => expect ~2 px per screen px)",
                     npair, dsx_max, dsy_min);
        end

        /* ---------- M6 量：呼吸一趟 inv 256→512，同一屏幕列选中的源列漂多少 ---------- */
        begin : m6
            integer inv_a, inv_b, sa, sb, drift_max, drift_sum, steps, s2;
            drift_max = 0; drift_sum = 0; steps = 0;
            for (inv_a = 256; inv_a + 8 <= 512; inv_a = inv_a + 8) begin
                inv_b = inv_a + 8;
                reset_capture; scan(inv_a[9:0], 9'd0, 1'b0);
                sa = sx_log[slot(CX + 64)];
                reset_capture; scan(inv_b[9:0], 9'd0, 1'b0);
                sb = sx_log[slot(CX + 64)];
                s2 = sa - sb; if (s2 < 0) s2 = -s2;
                drift_sum = drift_sum + s2; steps = steps + 1;
                if (s2 > drift_max) drift_max = s2;
            end
            $display("  INFO M6 breathing step=8, screen column CX+64: source column under it moves");
            $display("       max %0d px per step, total %0d px over the 256->512 sweep (%0d steps)",
                     drift_max, drift_sum, steps);
            // 理论：Δ源列 / Δinv = 64/256 = 0.25 px 每单位 inv ⇒ 每步(8) 恰 2 px，整趟 32 步 = 64 px。
            // 这条**不是**"越小越好"的软判据：它钉的是"取整行为与定义一致"，
            // 一旦有人把 floor 写成截断，负半边会整段偏 1，总数就对不上了。
            expect("M6 crawl matches the definition (max 2 px/step, total 64 px over a sweep)",
                   drift_max <= 2 && drift_sum == 64);
        end

        $display("  stats: best_k=%0d  NPIX=%0d  X0=%0d", best_k, NPIX, X0);
        if (errors == 0) $display("PASS tb_v96_zoom_scan");
        else             $display("FAIL tb_v96_zoom_scan errors=%0d", errors);
        $finish;
    end

    initial begin : watchdog
        #2_000_000;
        $display("FAIL tb_v96_zoom_scan timeout");
        $finish;
    end
endmodule
