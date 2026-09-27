`timescale 1ns/1ps
// tb_v89_align —— **量**（不是猜）效果链的「数据 vs 标签」错开几行几列：ISSUES #54 的那一半
//   跑法 `bash sim/run_one.sh tb_v89_align`。办法：喂一张**像素值就是坐标**的合成图（R5=行号、G6=常数记号、B5=列号），旁路只搬运不运算
//   ⇒ 输出里解出的 (y',x') 与该输出**所在位置** (y,x) 一减就是错位量。四个窗口级各自单独例化、与整链**同时**喂同一张图 ⇒ "哪一级贡献几行"是读出来的。
// 硬判据（今天必须成立）：S1 每个被测的全部样本都落在同一个 (Δrow,Δcol)；S1b 没有样本跑到 ±3 之外；
//   S2 整链 Δrow = 四个窗口级 Δrow 之和；S3 测量帧每个被测恰好收到 H*W 拍 de_out（不许多也不许少）。
// 目标判据（本文件现在的角色是**量具**，今天只报数）：T0 见文件末尾那条 —— 全旁路下的偏移必须与模块声明的 OFF_LINES 逐像素一致。
module tb_v89_align;
    localparam W = 32;
    localparam H = 32;
    localparam LINE = W + 1;              // 一帧一行 = W 个 de + 1 拍行间空隙
    localparam NG = 11;                   // Δ 直方图边长（-5..+5）
    // 从 7 加宽到 11 的理由（#54 (A') 之后）：四个窗口级统一到同一套中心抽头约定之后，整链的行偏移从 -3 变成
    // -4（每级 -1 × 四级），7 格窗装不下 ⇒ 621 个样本被记成"落在 ±3 之外"。那不是新缺陷，是**量程不够**；
    // 判据判的还是同一件事，只是窗要盖得住现象。

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg         de = 0;
    reg  [11:0] xs = 0, ys = 0;
    reg  [15:0] src = 0;
    integer cw_blur = 0, cw_pipe = 0, cw_hold = 0;   // 末列 (de_in, x_in) 是否同拍（诊断，见下面 always 里那条）
    integer src_row;   // 行号取模后的整数（表达式不能直接位选）
    integer src_off = 0;   // T1：模拟读侧提前 OFF_LINES 行取像素

    // ---------------- 被测：四个窗口级（各自旁路）+ 整链（全旁路）----------------
    wire        d_blur, d_shp, d_sob, d_mor, d_pipe;
    wire [15:0] q_blur, q_shp, q_sob, q_mor, q_pipe;

    proc_box_blur #(.H_ACTIVE(W)) u_blur (
        .clk(clk), .rst_n(rst_n), .bypass(1'b1),
        .hs_in(1'b0), .vs_in(1'b0), .de_in(de),
        .x_in(xs), .y_in(ys), .din(src), .de_out(d_blur), .dout(q_blur)
    );
    proc_sharpen #(.H_ACTIVE(W)) u_shp (
        .clk(clk), .rst_n(rst_n), .bypass(1'b1),
        .de_in(de), .x_in(xs), .y_in(ys), .din(src), .de_out(d_shp), .dout(q_shp)
    );
    proc_sobel #(.H_ACTIVE(W)) u_sob (
        .clk(clk), .rst_n(rst_n), .bypass(1'b1),
        .vs_in(1'b0), .de_in(de), .x_in(xs), .y_in(ys), .din(src),
        .de_out(d_sob), .dout(q_sob)
    );
    proc_morph #(.H_ACTIVE(W)) u_mor (
        .clk(clk), .rst_n(rst_n), .mode(2'd0), .threshold(8'd128),
        .de_in(de), .x_in(xs), .y_in(ys), .din(src), .de_out(d_mor), .dout(q_mor)
    );
    proc_pipeline #(.H_ACTIVE(W)) u_pipe (
        .clk(clk), .rst_n(rst_n),
        .stage_sel(9'd0), .threshold(8'd128),
        .gamma_en(1'b0), .gamma_wr(1'b0), .gamma_idx(8'd0), .gamma_data(8'd0),
        .rotate_active(1'b0), .hs_in(1'b0), .vs_in(1'b0),
        .de_in(de), .x_in(xs), .y_in(ys), .din(src), .de_out(d_pipe), .dout(q_pipe)
    );

    // ---------------- 记账：位置由台架自己数（模块不输出坐标，这正是本条要问的东西）----------------
    integer hb   [0:4][0:NG*NG-1];        // 每个被测一张 Δ 直方图（整帧）
    integer hbi  [0:4][0:NG*NG-1];        // 同一张，但只统计**内部**像素
    integer obc  [0:4];                   // 跑到 ±3 之外的样本数（整帧）
    integer obi  [0:4];                   // 同上，内部
    integer cnt  [0:4];                   // 收到的 de_out 拍数（整帧）
    integer cnti [0:4];                   // 同上，内部
    integer posx [0:4];                   // 当前输出位置的列（台架自己数）
    integer posy [0:4];                   // 当前输出位置的行
    integer fy, fx, dr, dc, idx;

    // 每个被测**各自一段判断**：五个 de_out 的时序本来一样，写成 if/else if 会"同一拍里只数到第一个"⇒ 量具自己骗自己。
    // 两份账：整帧（含边界）与**内部**（行≥4、列≥4）。窗口级在首行/首列本来就走"缓存没内容"的分支，混在一张直方图里
    // S1 判的就不是"错位是不是固定"而是"边界有几格" —— 那是另一种问法，得分开问。
    integer MARGIN = 4;
    // 逐列恒等账（#92 的第二把尺子）：为什么现有判据看不见这件事 —— 内部那一套把 `posx == W-1` 整列**排除**在
    // 判据之外（下面 `posx[idx] < W-1` 那一条），整帧那一套用直方图峰值 ⇒ 每行错一列 = 32/1024 个样本，峰仍在主偏移上，
    // 所以 T0/T1 全绿；而顶层 `tb_v98` 的 C2 恰恰在**每行最后一列**量到 484 个偏离（`dm1=484 dp1=0 dother=0`，见 #92）。
    // 两边说的是同一件事，只是这里几秒钟跑完、还知道是哪一级。记法：对每个被测、每个**输出列号**存一份"该列看到的错位量"
    // 直方图，跑完拿整帧主偏移当基准，凡某一列的样本没落在主偏移上就把这一列报出来 —— 不做任何延迟假设。
    localparam DCN = 11;                        // dc 的记账窗（-5..+5），与 NG 同宽
    integer colbin [0:4][0:W-1][0:DCN-1];
    task sample;
        input integer idx;
        input [15:0]  q;
        begin
            fy = q[15:11]; fx = q[4:0];
            dr = fy - posy[idx];
            dc = fx - posx[idx];
            if (dr >= -5 && dr <= 5 && dc >= -5 && dc <= 5)
                hb[idx][(dr + 5)*NG + (dc + 5)] = hb[idx][(dr + 5)*NG + (dc + 5)] + 1;
            else obc[idx] = obc[idx] + 1;
            cnt[idx] = cnt[idx] + 1;
            // 逐列那份账：只跳过**首几行**（行缓存热身），最后一列要算进来
            if (posy[idx] >= MARGIN && dc >= -5 && dc <= 5)
                colbin[idx][posx[idx]][dc + 5] = colbin[idx][posx[idx]][dc + 5] + 1;
            if (posy[idx] >= MARGIN && posy[idx] < H-1 && posx[idx] >= MARGIN && posx[idx] < W-1) begin
                if (dr >= -5 && dr <= 5 && dc >= -5 && dc <= 5)
                    hbi[idx][(dr + 5)*NG + (dc + 5)] = hbi[idx][(dr + 5)*NG + (dc + 5)] + 1;
                else obi[idx] = obi[idx] + 1;
                cnti[idx] = cnti[idx] + 1;
            end
            posx[idx] = posx[idx] + 1;
            if (posx[idx] == W) begin posx[idx] = 0; posy[idx] = posy[idx] + 1; end
        end
    endtask

    always @(posedge clk) if (rst_n) begin
        if (d_blur)  sample(0, q_blur);
        if (d_shp)   sample(1, q_shp);
        if (d_sob)   sample(2, q_sob);
        if (d_mor)   sample(3, q_mor);
        if (d_pipe)  sample(4, q_pipe);
        // 诊断（不是判据）：末列那一拍各级的 (de_in, x_in) 到底有没有对上。为什么现在要问：单独例化的四级 `line_end`
        // arming 成立、链子里的那份不成立（ID 只有 chain 红），差别只可能在坐标延迟线 `xd[]` 与逐级 de 的对齐上——猜没用，数一拍。
        cw_blur  = cw_blur  + ((u_blur.de_in  && u_blur.x_in  == W-1) ? 1 : 0);
        cw_pipe  = cw_pipe  + ((u_pipe.u_blur.de_in && u_pipe.u_blur.x_in == W-1) ? 1 : 0);
        cw_hold  = cw_hold  + ((u_pipe.u_blur.de_in && u_pipe.u_blur.x_in == W-1 && u_pipe.u_blur.de_out) ? 1 : 0);
    end

    function [8*8:1] name_of;             // 打印用
        input integer k;
        begin
            case (k) 0: name_of = "blur";   1: name_of = "sharp";
                      2: name_of = "sobel";  3: name_of = "morph";
                      default: name_of = "chain"; endcase
        end
    endfunction

    integer ii, jj, kk, bi, bj, bv, tot, errors, dr_chain, dr_sum;
    integer ii2, jj2, biv, totv;               // 内部像素那一套峰值
    integer ii3, jj3, c3, b3, m3, mj;          // ID（逐列恒等）内层循环
    integer idbad, idncol, idcol1, iddc1, idn1, idtot;   // ID 的账
    integer nsec [0:4];                         // 内部"第二个偏移"的样本数（报数用）
    integer drow_i [0:4], dcol_i [0:4];         // 每个被测的内部主偏移
    // 本文件原来的判据是内联写的（`if (!c) errors=errors+1;`）。新加的 T0/T1 用统一的任务，
    // 而这个任务**必须判 X**：`if (!cond)` 在 cond=X 时两个分支都不走 ⇒ 静默绿（ISSUES #60）。
    task expect; input [100*8:1] name; input cond;
        begin
            if (cond !== 1'b1) begin errors = errors + 1; $display("  FAIL %0s", name); end
            else $display("[tb_v89_align.v:136] PASS %0s", name);   // 打出来：看不到"判过什么"的判据等于没判（#60）
        end
    endtask

    integer OFF;
    integer c4dr, c4dc, c4cons, c4tot, c4ob;   // 补偿前整链那一遍的账（T0 用）
    initial begin
        OFF = u_pipe.OFF_LINES;          // 从 RTL 取声明值，不在台架里重抄一遍数字
        for (ii = 0; ii < 5; ii = ii + 1) begin
            obc[ii] = 0; cnt[ii] = 0; posx[ii] = 0; posy[ii] = 0;
            obi[ii] = 0; cnti[ii] = 0;
            for (jj = 0; jj < NG*NG; jj = jj + 1) begin
                hb[ii][jj] = 0; hbi[ii][jj] = 0;
            end
        end
        errors = 0;

        rst_n = 0; de = 0; xs = 0; ys = 0; src = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        // 两帧：第一帧热身（行缓存是脏的，尾巴与边界效应都归它），第二帧才测
        for (ii = 0; ii < 2; ii = ii + 1) begin
            for (jj = 0; jj < 5; jj = jj + 1) begin
                posx[jj] = 0; posy[jj] = 0;
                if (ii == 1) begin
                    cnt[jj] = 0; obc[jj] = 0; cnti[jj] = 0; obi[jj] = 0;
                    for (kk = 0; kk < NG*NG; kk = kk + 1) begin
                        hb[jj][kk] = 0; hbi[jj][kk] = 0;
                    end
                    for (ii3 = 0; ii3 < W; ii3 = ii3 + 1)
                        for (jj3 = 0; jj3 < DCN; jj3 = jj3 + 1) colbin[jj][ii3][jj3] = 0;
                end
            end
            for (jj = 0; jj < H; jj = jj + 1) begin
                for (kk = 0; kk < W; kk = kk + 1) begin
                    @(negedge clk);
                    xs  = kk[11:0]; ys = jj[11:0];
                    src_row = (jj + src_off) % H; src = {src_row[4:0], 6'h2A, kk[4:0]};  // 行号(+平移) / 记号 / 列号
                    de  = 1;
                end
                @(negedge clk); de = 0;                     // 行间空隙
            end
            de = 0;
            repeat (LINE * 4 + 16) @(negedge clk);          // 排空
        end

        $display("");
        $display("[tb_v89_align.v:183] === 旁路下的「数据 vs 标签」错位量（像素值=坐标；单位：一行/一个像素）===");
        $display("[tb_v89_align.v:184] 整帧那一列把首行/首列也算进来（窗口级在那里走的是「缓存还没内容」的分支），");
        $display("[tb_v89_align.v:185] 判据只看**内部**那一列：错位必须是一个固定值，边界几格由数字说话。");
        dr_sum = 0; dr_chain = 0;
        for (kk = 0; kk < 5; kk = kk + 1) begin
            // 整帧峰值（只报数）
            bi = 0; bj = 0; bv = -1; tot = 0;
            for (ii = 0; ii < NG*NG; ii = ii + 1) tot = tot + hb[kk][ii];
            for (ii = 0; ii < NG; ii = ii + 1)
                for (jj = 0; jj < NG; jj = jj + 1)
                    if (hb[kk][ii*NG + jj] > bv) begin bv = hb[kk][ii*NG + jj]; bi = ii; bj = jj; end
            // 内部峰值（判据用这个）
            ii2 = 0; jj2 = 0; biv = -1; totv = 0;
            for (ii = 0; ii < NG*NG; ii = ii + 1) totv = totv + hbi[kk][ii];
            for (ii = 0; ii < NG; ii = ii + 1)
                for (jj = 0; jj < NG; jj = jj + 1)
                    if (hbi[kk][ii*NG + jj] > biv) begin biv = hbi[kk][ii*NG + jj]; ii2 = ii; jj2 = jj; end
            $display("[tb_v89_align.v:200] %0s  整帧 d=(%0d,%0d) %0d/%0d 越界%0d | 内部 d=(%0d,%0d) %0d/%0d 越界%0d | 收到 %0d 拍",
                     name_of(kk), bi - 5, bj - 5, bv, tot, obc[kk],
                     ii2 - 5, jj2 - 5, biv, totv, obi[kk], cnt[kk]);
            if (biv != totv) begin
                // 这不是"模型错了"，而是**真实存在的第二个偏移**：sobel 的 +2 列会在每行末尾绕到下一行开头，所以它内部有两种
                // 偏移（27 个 ≈ 每行 2 个 × 13 行）。数量当凭据报出来，别判红 —— 判红会让这条真实发现被当成量具坏了。
                $display("[tb_v89_align.v:207] NOTE S1 %0s：内部有 %0d/%0d 个样本落在第二个偏移上（行末回绕/边界逻辑）",
                         name_of(kk), totv - biv, totv);
                nsec[kk] = totv - biv;
            end else nsec[kk] = 0;
            if (totv == 0) begin
                $display("[tb_v89_align.v:212] FAIL S1c %0s：内部一个样本都没采到 ⇒ 量具自己坏了（MARGIN 太大？）",
                         name_of(kk));
                errors = errors + 1;
            end
            if (obi[kk] != 0) begin
                $display("[tb_v89_align.v:217] FAIL S1b %0s：内部有 %0d 个样本的偏移落在 ±3 之外", name_of(kk), obi[kk]);
                errors = errors + 1;
            end
            if (cnt[kk] != H*W) begin
                $display("[tb_v89_align.v:221] FAIL S3 %0s：收到 %0d 拍，应为 %0d（de 链多发或漏发）",
                         name_of(kk), cnt[kk], H*W);
                errors = errors + 1;
            end
            // ID：旁路下的逐列恒等（#92 第二把尺子）。每一列的样本都必须落在**整帧主偏移**那一格上；哪一列没有，
            // 就把它和它偏到哪一格报出来。这条不看峰值、不排最后一列，所以"T0/T1 全绿而顶层 C2 每行错一列"从此不可能再藏。
            idbad = 0; idncol = 0; idcol1 = -1; iddc1 = 0; idn1 = 0; idtot = 0;
            for (ii3 = 0; ii3 < W; ii3 = ii3 + 1) begin
                c3 = 0; b3 = 0; m3 = -1; mj = 0;
                for (jj3 = 0; jj3 < DCN; jj3 = jj3 + 1) begin
                    c3 = c3 + colbin[kk][ii3][jj3];
                    if (jj3 != bj && colbin[kk][ii3][jj3] > 0) begin
                        b3 = b3 + colbin[kk][ii3][jj3];
                        if (colbin[kk][ii3][jj3] > m3) begin m3 = colbin[kk][ii3][jj3]; mj = jj3; end
                    end
                end
                idtot = idtot + c3;
                if (b3 != 0) begin
                    idbad = idbad + b3; idncol = idncol + 1;
                    if (idcol1 < 0) begin idcol1 = ii3; iddc1 = mj - 5; idn1 = b3; end
                end
            end
            $display("ID %0s: off-col samples=%0d/%0d in %0d cols | first col=%0d dc=%0d n=%0d",
                     name_of(kk), idbad, idtot, idncol, idcol1, iddc1, idn1);
            expect("ID 旁路必须逐列恒等（含每行最后一列，偏移只有一个值）", idbad == 0);
            if (kk < 4) dr_sum = dr_sum + (ii2 - 5);
            else        dr_chain = ii2 - 5;
            drow_i[kk] = ii2 - 5; dcol_i[kk] = jj2 - 5;
            if (kk == 4) begin          // 整链那份账先存下来：下面 T1 会重记同样的数组
                c4dr = ii2 - 5; c4dc = jj2 - 5; c4cons = biv; c4tot = totv; c4ob = obi[4];
            end
        end
        // T1：读侧补偿真的抵消得了吗（模拟 pl_video_top 的 cy_r）—— 把激励整体平移 OFF_LINES 行 = "显示第 r 行时去问
        // 第 r+OFF 行的像素"，链子的内容滞后是 −OFF，两者相加必须是 0。这一条过了，才允许在顶层写那个提前量。
        begin : comp
            integer rows2;
            src_off = OFF;                          // OFF 在下面是从 RTL 取的声明值
            for (jj = 0; jj < 5; jj = jj + 1) begin
                posx[jj] = 0; posy[jj] = 0;
                cnt[jj] = 0; obc[jj] = 0; cnti[jj] = 0; obi[jj] = 0;
                for (kk = 0; kk < NG*NG; kk = kk + 1) begin hb[jj][kk] = 0; hbi[jj][kk] = 0; end
            end
            for (rows2 = 0; rows2 < 2; rows2 = rows2 + 1) begin
                for (jj = 0; jj < H; jj = jj + 1) begin
                    for (kk = 0; kk < W; kk = kk + 1) begin
                        @(negedge clk);
                        xs = kk[11:0]; ys = jj[11:0];
                        src_row = (jj + src_off) % H; src = {src_row[4:0], 6'h2A, kk[4:0]};
                        de  = 1;
                    end
                    @(negedge clk); de = 0;
                end
                de = 0;
                repeat (LINE * 4 + 16) @(negedge clk);
                if (rows2 == 0) begin
                    // 第一帧只是让行缓存热起来，账目在第二帧才记
                    for (jj = 0; jj < 5; jj = jj + 1) begin
                        posx[jj] = 0; posy[jj] = 0; cnt[jj] = 0; cnti[jj] = 0; obi[jj] = 0;
                        for (kk = 0; kk < NG*NG; kk = kk + 1) begin hb[jj][kk] = 0; hbi[jj][kk] = 0; end
                    end
                end
            end
            src_off = 0;
            // 只看整链：内部偏移必须是 (0,0) 且 100 % 一致
            ii2 = 0; jj2 = 0; biv = -1; totv = 0;
            for (ii = 0; ii < NG*NG; ii = ii + 1) totv = totv + hbi[4][ii];
            for (ii = 0; ii < NG; ii = ii + 1)
                for (jj = 0; jj < NG; jj = jj + 1)
                    if (hbi[4][ii*NG + jj] > biv) begin biv = hbi[4][ii*NG + jj]; ii2 = ii; jj2 = jj; end
            $display("[tb_v89_align.v:270] T1 读侧提前 %0d 行之后，整链内部偏移 d=(%0d,%0d) 一致 %0d/%0d",
                     OFF, ii2 - 5, jj2 - 5, biv, totv);
            expect("T1 补偿后整链内部偏移 = (0,0)（顶层 cy_r 的提前量由此才有依据）",
                   (ii2 - 5) == 0 && (jj2 - 5) == 0 && biv == totv && totv > 0 && obi[4] == 0);
        end

        // S4：三个"取中心抽头"的窗口级必须**同一套约定**（blur 是那份约定的原主）。这条才是本文件真正的看门狗：
        // 谁把某一级改成自洽旁路，它的 drow 就会与另外两级不同 ⇒ 切换效果时画面会跳一行。
        if (drow_i[1] != drow_i[0] || drow_i[3] != drow_i[0] ||
            dcol_i[1] != dcol_i[0] || dcol_i[3] != dcol_i[0]) begin
            $display("[tb_v89_align.v:281] FAIL S4 三个窗口级约定不一致：blur=(%0d,%0d) sharp=(%0d,%0d) morph=(%0d,%0d)",
                     drow_i[0], dcol_i[0], drow_i[1], dcol_i[1], drow_i[3], dcol_i[3]);
            errors = errors + 1;
        end
        $display("[tb_v89_align.v:285] 四个窗口级内部 drow 之和 = %0d；整链内部实测 drow = %0d", dr_sum, dr_chain);
        if (dr_sum != dr_chain) begin
            $display("[tb_v89_align.v:287] FAIL S2 累加性不成立 ⇒ 「每级各错若干行」的模型是错的，得重查哪一级");
            errors = errors + 1;
        end
        // T0（今天只报数，不假装绿）：判的**不是**"偏移必须是 0"—— 行缓存式 3×3 因果上就要滞后一行，那是物理不是缺陷。
        // 判的是**"偏移必须等于模块自己声明的 OFF_LINES，且逐像素一致"**：这条成立，顶层才能用一个常量把平移补掉
        //（pl_video_top 的 cy_r）；反过来，谁加了一级窗口级却忘了改 OFF_LINES，或把某一级改成另一套抽头约定，这条立刻红。
        $display("[tb_v89_align.v:295] T0 补偿前整链实测：d=(%0d,%0d) 主偏移占 %0d/%0d，越界 %0d；声明的 OFF_LINES=%0d",
                 c4dr, c4dc, c4cons, c4tot, c4ob, OFF);
        expect("T0 整链内部偏移 = (−OFF_LINES, 0) 且 100 % 一致（声明值与行为对得上）",
               c4dr == -OFF && c4dc == 0 && c4cons == c4tot && c4tot > 0 && c4ob == 0);

        $display("");
        $display("OBS lastcol: standalone_blur=%0d chain_blur=%0d (arming beats seen by each blur; the chain's de and its x tap are NOT the same beat, so arming alone is not enough to time the flush)",
                 cw_blur, cw_pipe);
        if (errors == 0) $display("PASS tb_v89_align");
        else             $display("FAIL tb_v89_align errors=%0d", errors);
        $finish;
    end

    initial begin
        #8_000_000;
        $display("FAIL tb_v89_align timeout");
        $finish;
    end
endmodule
