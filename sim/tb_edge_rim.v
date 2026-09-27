`timescale 1ns/1ps
// tb_edge_rim —— "左侧与上方边缘的像素条带仍然存在"的专用尺子（#97 那一族）：先量，再修
//   跑法 `bash sim/run_one.sh tb_edge_rim`。为什么 `tb_v98` 的 C2/C3/C4 看不见它：那三把判的是**位置**与**非黑**，
//   而 rim 不是位置错、也不是黑不黑，它是**值的断层**与**内容的陈旧**：窗口级在边缘要么直接旁路发原图（一条比内部更锐的线），要么吃行缓存里上一帧的尾巴（一条与当前画面无关的带）⇒ 位置全对，三把尺子全绿。
// 两轮判据覆盖四个窗口级（blur/sharpen/sobel/morph）：第一轮 `R*` 与第二轮 `D*` 的清单分别写在各自那一段的开头。
// ⚠ 激励的**周期**是这把尺子的命门：隔列黑白（周期 2）下平移 2、4 列与不平移给出**同一串**期望值 ⇒ 搜索任选一个平移都算"内部全对"。现在用 `13x+7 mod 32`（`13*s mod 32` 对 s∈1..5 全不为 0）。
// ⚠ 采集必须是**稳态帧**（第一帧行缓存里全是上电前的格子）；⚠ 平移扫描**允许负值**且从 0 往外排（退化维落在 0，否则 rim 挑到帧边界那一行）；⚠ 覆盖地板：`judged` 少于地板就算红 —— "什么都没量"永远不等于"量了且对"。
`default_nettype none
module tb_edge_rim;
    localparam integer W = 64, H = 64, FW = H*W;

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg         de;
    reg  [11:0] xs, ys;
    reg  [15:0] din;

    wire        de_bu, de_sh, de_so, de_mo;
    wire [15:0] o_bu, o_sh, o_so, o_mo;
    reg  [1:0]  stage;                       // 0 blur  1 sharpen  2 sobel  3 morph

    proc_box_blur #(.H_ACTIVE(W)) u_bu (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0),
        .hs_in(1'b0), .vs_in(1'b0), .de_in(de), .x_in(xs), .y_in(ys), .din(din),
        .de_out(de_bu), .dout(o_bu) );
    proc_sharpen #(.H_ACTIVE(W)) u_sh (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din),
        .de_out(de_sh), .dout(o_sh) );
    proc_sobel #(.H_ACTIVE(W)) u_so (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0), .vs_in(1'b0),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din),
        .de_out(de_so), .dout(o_so) );
    proc_morph #(.H_ACTIVE(W)) u_mo (
        .clk(clk), .rst_n(rst_n), .mode(2'd1), .threshold(8'd128),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din),
        .de_out(de_mo), .dout(o_mo) );

    wire [15:0] dut = (stage == 2'd0) ? o_bu  : (stage == 2'd1) ? o_sh :
                      (stage == 2'd2) ? o_so  : o_mo;
    wire        ded = (stage == 2'd0) ? de_bu : (stage == 2'd1) ? de_sh :
                      (stage == 2'd2) ? de_so : de_mo;

    reg [15:0] cap [0:2*FW-1];               // **第三、第四帧**（不是头两帧！）
    reg [15:0] fA  [0:FW-1];                 // 差分对照用的两份"改邻居之前"
    reg [15:0] fB  [0:FW-1];
    integer ndeo = 0, derr = 0, cx = 0;
    always @(posedge clk) begin
        if (rst_n && (de_bu !== de_sh || de_bu !== de_so || de_bu !== de_mo)) derr = derr + 1;
        if (ded) begin
            // ⚠ 这条洞是**尺子自己的**：原来写 `if (ndeo < 2*FW) cap[ndeo] = dut;` —— 注释说"第三、四帧"，
            //   代码留的却是**头两帧**：复位后第一帧行缓存是 X/0，而 `dev(X, 期望)` 的比较**永远不算不符**
            //   （`X > 1` 为假）⇒ R1~R5 可以"绿在 X 上"。现在采第三、四帧，并另加 R8：被判格子有一位是 X 就直接红。
            if (ndeo >= 2*FW && ndeo < 4*FW) cap[ndeo - 2*FW] = dut;
            ndeo = ndeo + 1;
        end
    end

    // 激励
    integer pkind;          // 0 hash  1 第0列钉死  2 末列钉死  3 第0行钉死  4 末行逐帧交替
    integer gmode;          // pkind==0 时：0 随列变 1 随行变
    reg [4:0] p_lo, p_hi, p_probe;
    integer fnum;

    function [4:0] hash5; input integer p;
        begin hash5 = ((p * 13 + 7) % 32); end
    endfunction
    function [15:0] gray; input [4:0] v;
        begin gray = {v, {v, 1'b0}, v}; end
    endfunction
    function [15:0] pat; input integer x, y;
        reg [4:0] a;
        begin
            a = 5'd10;
            case (pkind)
                0:      a = (gmode == 0) ? hash5(x) : hash5(y);
                1:      a = (x == 0)     ? p_lo : p_hi;
                2:      a = (x == W-1)   ? p_lo : p_hi;
                3:      a = (y == 0)     ? p_lo : p_hi;
                // 4/5/6 是差分判据的真正形状："改哪一格"与"看哪一格"必须**隔着一圈** —— 让第 0 列的左邻回绕源
                //   (= 上一行的末列) 在两次跑之间变，看第 0 列动不动；对末列同理（回绕源 = 下一行的第 0 列）。
                //   为什么"钉住第 0 列、只改其余列"那一版对 morph 红不了：膨胀是 `any1`，回绕进来的那一格与中心列
                //   在同一图案里**同为暗** ⇒ 夹不夹都一样 ⇒ 判据结构上绿。
                4:      a = (y == H-1)   ? ((fnum & 1) ? 5'd30 : 5'd4) : p_hi;
                5:      a = (x == W-1)   ? p_probe : 5'd24;             // 只有末列在两跑之间变
                6:      a = (x == 0)     ? p_probe : 5'd24;             // 只有第 0 列在两跑之间变
                // 7 = **×2 行复制**的几何：顶层喂给链子的 `y_in` 是**源行**（`.y_in(cy_d[3])`），而显示栅格每两条行走一条源行
                //   ⇒ 窗口三行取自 {src(r−2), src(r−1), src(r)}：偶数显示行是 {k−1,k−1,k}、奇数行是 {k−1,k,k}，也就是
                //   "中心那一行"在成对的两行里**一次是 k−1、一次是 k**。这一维在 1× 栅格的激励里**说不出来**（前六条都是 1×），
                //   而旗标 `no_above = (y_in==1)` 在"每对的第二行"上会把一个**合法的**上一行夹掉 ⇒ R7 量它。
                7:      a = hash5((y >> 1) < (H >> 1) ? (y >> 1) : ((H >> 1) - 1));
                // 8 = **×2 列复制**（R7 的镜像）：顶层 `x_in` 是**显示列** 0..1023，相邻两拍是同一个源列 ⇒ 链子看到的"一行"
                //   是 `SS SS CC CC ...` 的形状。夹取旗标的武装列号是 `x_in == H_ACTIVE-2`，也就是"末对的**前**一拍"——
                //   这一条在 1× 栅格里与"末列"是同一格，在 2× 里差一对。图案沿行不变 ⇒ 纵向三抽头同值 ⇒ 3×3 平均退化成横向三格平均。
                8:      a = hash5((x >> 1) < (W >> 1) ? (x >> 1) : ((W >> 1) - 1));
            endcase
            pat = gray(a);
        end
    endfunction

    function [15:0] mean3; input [15:0] X, Y, Z;
        integer r, g2, bl;
        begin
            r  = ({11'd0, X[15:11]} + {11'd0, Y[15:11]} + {11'd0, Z[15:11]} + 2) / 3;
            g2 = ({10'd0, X[10:5]}  + {11'd0, Y[10:5]}  + {11'd0, Z[10:5]}  + 2) / 3;
            bl = ({11'd0, X[4:0]}   + {11'd0, Y[4:0]}   + {11'd0, Z[4:0]}   + 2) / 3;
            mean3 = {r[4:0], g2[5:0], bl[4:0]};
        end
    endfunction

    function integer dev; input [15:0] got, expv;
        integer d, t;
        begin
            d = got[15:11] - expv[15:11]; if (d < 0) d = -d;
            t = got[10:5]  - expv[10:5];  if (t < 0) t = -t; if (t > d) d = t;
            t = got[4:0]   - expv[4:0];   if (t < 0) t = -t; if (t > d) d = t;
            dev = d;
        end
    endfunction

    task send_frame;
        integer x, y;
        begin
            for (y = 0; y < H; y = y + 1) begin
                for (x = 0; x < W; x = x + 1) begin
                    @(posedge clk); #1;
                    de = 1'b1; xs = x[11:0];
                    ys = (pkind == 7) ? (y >> 1) : y[11:0];   // ×2 模式下 y_in 喂**源行**（与顶层一致）
                    din = pat(x, y);
                end
                @(posedge clk); #1;
                de = 1'b0; din = 16'd0;                       // 行间隙：链子在这里补跳末列那一拍
                @(posedge clk); #1;
            end
            @(posedge clk); #1; de = 1'b0;
            repeat (30) @(posedge clk);                       // 排空
            fnum = fnum + 1;
        end
    endtask

    // 跑四帧，只留第三、第四帧（第三帧 = 稳态参考帧；第四帧给 D3 当"下一帧的第一行"）
    task run4;
        begin
            ndeo = 0;
            send_frame(); send_frame(); send_frame(); send_frame();
        end
    endtask

    // 扫描顺序 = 从 0 往外 ⇒ 平局取最小平移（退化维必须落在 0，见文件头）
    integer ord_s [0:8], ord_r [0:6];

    // 内部格在平移 (s, ro) 下不吻合定义的格数
    function integer interior_bad; input integer s, ro;
        integer jj, ii, kk, b;
        begin
            b = 0;
            for (jj = 1; jj < H-1; jj = jj + 1)
                for (ii = 1; ii < W-1; ii = ii + 1) begin
                    kk = (jj + ro)*W + (ii + s);
                    if (kk < 0 || kk >= FW) begin
                    end else if (gmode == 0) begin
                        if (dev(cap[kk], mean3(pat(ii-1,jj), pat(ii,jj), pat(ii+1,jj))) > 1) b = b + 1;
                    end else begin
                        if (dev(cap[kk], mean3(pat(ii,jj-1), pat(ii,jj), pat(ii,jj+1))) > 1) b = b + 1;
                    end
                end
            interior_bad = b;
        end
    endfunction

    integer sh, rsh, s, ro, i, j, k, nj, bs, bsb, bb, bad, stg;
    integer r7bad, r7n, cxn;
    // R9 = R7 的**镜像**：×2 的是**列**而不是行（顶层 `x_in` 是显示列、相邻两拍同一个源列的复制）。
    integer r9bad, r9n, cxn2, sc_l, sc_r;

    // ×2 模式下"显示行 t 走的是哪一条源行"：帧头之前没有行 ⇒ 定义就按 clamp-to-edge 取第 0 行
    function integer ssrc; input integer t;
        begin if (t < 0) ssrc = 0; else ssrc = (t >> 1); end
    endfunction
    integer b0, b1g, b2, b3, b4, b5, n2, n3, n4, n5, d;
    reg [15:0] e;

    initial begin
        de = 1'b0; xs = 0; ys = 0; din = 0; stage = 0; pkind = 0; gmode = 0; fnum = 0;
        p_lo = 5'd6; p_hi = 5'd12;
        ord_s[0]=0; ord_s[1]=-1; ord_s[2]=1; ord_s[3]=-2; ord_s[4]=2;
        ord_s[5]=-3; ord_s[6]=3; ord_s[7]=4; ord_s[8]=5;
        ord_r[0]=0; ord_r[1]=-1; ord_r[2]=1; ord_r[3]=-2;
        ord_r[4]=2; ord_r[5]=-3; ord_r[6]=3;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        b0=0; b1g=0; b2=0; b3=0; b4=0; b5=0; n2=0; n3=0; n4=0; n5=0;

        // 第一轮：blur 的精确 golden（两种条纹各跑一次）—— 9 抽头平均按定义算，容差 ±1（RTL 用 57/512 近似 1/9）。
        //   R0 采集完整性 + 四级的 de 同根；R1 内部 == 定义，并把列、行平移**量**出来（不是假设出来的）；
        //   R2 左圈 / R3 上圈 / R4 右圈 / R5 屏上第一行（"中心行 = −1"那一格）。
        for (gmode = 0; gmode < 2; gmode = gmode + 1) begin
            stage = 2'd0; pkind = 0;
            run4();
            if (ndeo != 4*FW) begin
                b0 = 1;
                $display("R0 collect broken gmode=%0d: de_out=%0d want %0d", gmode, ndeo, 4*FW);
            end
            sh = 0; rsh = 0; bsb = 1<<30; nj = 0;
            for (ro = 0; ro < 7; ro = ro + 1)
                for (s = 0; s < 9; s = s + 1) begin
                    bs = interior_bad(ord_s[s], ord_r[ro]);
                    if (bs < bsb) begin sh = ord_s[s]; rsh = ord_r[ro]; bsb = bs; end
                end
            for (j = 1; j < H-1; j = j + 1)
                for (i = 1; i < W-1; i = i + 1)
                    if (((j+rsh)*W + (i+sh)) >= 0 && ((j+rsh)*W + (i+sh)) < FW) nj = nj + 1;
            $display("GOLDEN gmode=%0d: latency = (%0d columns, %0d rows); interior mismatch %0d of %0d",
                     gmode, sh, rsh, bsb, nj);
            if (nj < 3000 || bsb != 0) begin
                b1g = 1;
                $display("FAIL R1 NO alignment in -3..5 x -3..3 makes the interior match the definition (bad=%0d judged=%0d)", bsb, nj);
            end else $display("PASS R1 calibration trusted: interior == definition at (%0d,%0d) over %0d cells", sh, rsh, nj);

            if (gmode == 0) begin
                for (j = 6; j < H-6; j = j + 1) begin
                    k = (j + rsh)*W + sh;                            // 中心 = 输入 (0,j)
                    e = mean3(pat(0,j), pat(0,j), pat(1,j));         // 左邻缺 ⇒ 复制第 0 列
                    d = dev(cap[k], e); n2 = n2 + 1;
                    if (d > 1 && b2 < 3) $display("DIAG R2 (0,%0d): got=%h clamp=%h raw=%h dev=%0d", j, cap[k], e, pat(0,j), d);
                    if (d > 1) b2 = b2 + 1;
                    k = (j + rsh)*W + (W-1) + sh;                    // 中心 = 输入 (W-1,j)
                    e = mean3(pat(W-2,j), pat(W-1,j), pat(W-1,j));   // 右邻缺 ⇒ 复制末列
                    d = dev(cap[k], e); n4 = n4 + 1;
                    if (d > 1 && b4 < 3) $display("DIAG R4 (%0d,%0d): got=%h clamp=%h raw=%h dev=%0d", W-1, j, cap[k], e, pat(W-1,j), d);
                    if (d > 1) b4 = b4 + 1;
                end
            end else begin
                for (i = 6; i < W-6; i = i + 1) begin
                    k = (0 + rsh)*W + i + sh;                        // 中心 = 输入 (i,0)：缺上邻
                    e = mean3(pat(i,0), pat(i,0), pat(i,1));
                    d = dev(cap[k], e); n3 = n3 + 1;
                    if (d > 1 && b3 < 3) $display("DIAG R3 (%0d,0): got=%h clamp=%h raw=%h dev=%0d", i, cap[k], e, pat(i,0), d);
                    if (d > 1) b3 = b3 + 1;
                    k = i + sh;                                      // 屏上第一行（中心行 = −1）
                    if (k >= 0 && k < FW) begin
                        e = mean3(pat(i-1,0), pat(i,0), pat(i+1,0));
                        d = dev(cap[k], e); n5 = n5 + 1;
                        if (d > 1 && b5 < 3) $display("DIAG R5 row0 (%0d): got=%h frame0-window=%h stale-below=%h",
                                                      i, cap[k], e, mean3(pat(i,H-2),pat(i,H-1),pat(i,H-1)));
                        if (d > 1) b5 = b5 + 1;
                    end
                end
            end
        end

        // 第二轮：四个窗口级都跑的**差分**判据 —— 不给每个算法写 golden（四份 golden 会把这一轮拖成"给台架补算术"），
        // 而用户报的缺陷用"感不感得起邻居"就能判死。每个方向两把：一把查"旁路"（rim 必须随**圈内**的邻居变），
        // 一把查"回绕"（rim 必须**不**随圈外的回绕源变）。只有一把的话另一族的错会绿 —— 是用 morph 的反例
        //（关掉左夹 ⇒ 判据照样绿）才看见少了一把。每段都配**正对照**：激励没换/采集坏了时对照那一格也不动，就先红对照。
        // ⚠ 循环变量必须是 32 位 `integer`：写成 `for (stage = 0; stage < 2'd4; ...)` 时 `2'd4` 是**两位**字面量
        //   ⇒ 截断成 0 ⇒ 条件永远为假 ⇒ 整轮差分判据一次都没跑，而屏幕照样打满一屏 PASS。
        for (stg = 0; stg < 4; stg = stg + 1) begin
            stage = stg[1:0];
            // ---- D1 第 0 列必须随第 1 列变（旁路检测）----
            pkind = 1; p_lo = 5'd20; p_hi = 5'd12; run4();
            for (i = 0; i < FW; i = i + 1) fA[i] = cap[i];
            p_hi = 5'd22; run4();
            bad = 0; bb = 0;
            for (j = 6; j < H-6; j = j + 1) begin
                if (cap[j*W] == fA[j*W]) bad = bad + 1;              // rim 对邻居无感 ⇒ 发的是原图
                if (cap[j*W+1] != fA[j*W+1]) bb = bb + 1;          // 正对照
            end
            $display("D1 stage=%0d : left rim responds in %0d/%0d rows; interior control changed in %0d/%0d",
                     stage, (H-12)-bad, H-12, bb, H-12);
            if (bad != 0) begin
                b2 = b2 + 100;
                $display("FAIL D1 stage=%0d left column does NOT depend on column 1 in %0d rows (bypassed rim = 一条带)", stage, bad);
            end else if (bb < H-12) begin
                b2 = b2 + 100;
                $display("FAIL D1 stage=%0d POSITIVE CONTROL dead: interior cell did not change either (激励/采集坏了)", stage);
            end else $display("PASS D1 stage=%0d left column is processed, not passed through", stage);

            // ---- D1w 第 0 列必须**不**随末列变（回绕检测：第 0 列的左邻回绕源就是上一行的末列）----
            pkind = 5; p_probe = 5'd8; run4();
            for (i = 0; i < FW; i = i + 1) fA[i] = cap[i];
            p_probe = 5'd28; run4();
            bad = 0; bb = 0;
            for (j = 6; j < H-6; j = j + 1) begin
                if (cap[j*W] !== fA[j*W]) bad = bad + 1;             // 圈外的格子渗进来了
                if (cap[j*W + (W-2)] !== fA[j*W + (W-2)]) bb = bb + 1;  // 正对照：圈内那一格必须变
            end
            $display("D1w stage=%0d : left rim immune to the wrap source in %0d/%0d rows; control moved in %0d/%0d",
                     stage, (H-12)-bad, H-12, bb, H-12);
            if (bad != 0) begin
                b2 = b2 + 100;
                $display("FAIL D1w stage=%0d left column CHANGES when only the LAST column changes => 上一行末列绕进来了（%0d rows）", stage, bad);
            end else if (bb == 0) begin
                b2 = b2 + 100;
                $display("FAIL D1w stage=%0d POSITIVE CONTROL dead: column %0d did not move either", stage, W-2);
            end else $display("PASS D1w stage=%0d left column carries no wrapped-in neighbour", stage);

            // ---- D2 末列必须随倒数第二列变（旁路检测）----
            pkind = 2; p_lo = 5'd20; p_hi = 5'd12; run4();
            for (i = 0; i < FW; i = i + 1) fB[i] = cap[i];
            p_hi = 5'd22; run4();
            bad = 0; bb = 0;
            for (j = 6; j < H-6; j = j + 1) begin
                if (cap[j*W + (W-1)] == fB[j*W + (W-1)]) bad = bad + 1;
                if (cap[j*W + (W-2)] != fB[j*W + (W-2)]) bb = bb + 1;
            end
            $display("D2 stage=%0d : last rim responds in %0d/%0d rows; interior control changed in %0d/%0d",
                     stage, (H-12)-bad, H-12, bb, H-12);
            if (bad != 0) begin
                b4 = b4 + 100;
                $display("FAIL D2 stage=%0d last column does NOT depend on column %0d (bypassed / 未 clamp 的末列)", stage, W-2);
            end else if (bb < H-12) begin
                b4 = b4 + 100;
                $display("FAIL D2 stage=%0d POSITIVE CONTROL dead: interior cell did not change either", stage);
            end else $display("PASS D2 stage=%0d last column is processed, not passed through", stage);

            // ---- D2w 末列必须**不**随第 0 列变（回绕检测：末列的右邻回绕源就是下一行的第 0 列）----
            pkind = 6; p_probe = 5'd8; run4();
            for (i = 0; i < FW; i = i + 1) fB[i] = cap[i];
            p_probe = 5'd28; run4();
            bad = 0; bb = 0;
            for (j = 6; j < H-6; j = j + 1) begin
                if (cap[j*W + (W-1)] !== fB[j*W + (W-1)]) bad = bad + 1;
                if (cap[j*W + 1] !== fB[j*W + 1]) bb = bb + 1;       // 正对照：第 1 列的窗口含第 0 列
            end
            $display("D2w stage=%0d : last rim immune to the wrap source in %0d/%0d rows; control moved in %0d/%0d",
                     stage, (H-12)-bad, H-12, bb, H-12);
            if (bad != 0) begin
                b4 = b4 + 100;
                $display("FAIL D2w stage=%0d last column CHANGES when only column 0 changes => 下一行第 0 列绕进来了（%0d rows）", stage, bad);
            end else if (bb == 0) begin
                b4 = b4 + 100;
                $display("FAIL D2w stage=%0d POSITIVE CONTROL dead: column 1 did not move either", stage);
            end else $display("PASS D2w stage=%0d last column carries no wrapped-in neighbour", stage);

            // ---- D3 屏上第一行必须**不**随上一帧的末行变（陈旧检测）----
            pkind = 4; p_hi = 5'd24; run4();
            bad = 0; bb = 0;
            for (i = 2; i < W-2; i = i + 1) begin
                if (cap[FW + i] !== cap[i]) bad = bad + 1;           // 第四帧第一行 vs 第三帧
                if (cap[FW + (H-1)*W + i] !== cap[(H-1)*W + i]) bb = bb + 1;   // 末行必须交替
            end
            $display("D3 stage=%0d : screen row 0 stable in %0d/%0d cols; last-row control alternates in %0d/%0d",
                     stage, (W-4)-bad, W-4, bb, W-4);
            if (bad != 0) begin
                b5 = b5 + 100;
                $display("FAIL D3 stage=%0d screen row 0 CHANGES with the previous frame's last row => 吃的是上一帧的尾巴（上边缘那条带）", stage);
            end else if (bb == 0) begin
                b5 = b5 + 100;
                $display("FAIL D3 stage=%0d POSITIVE CONTROL dead: the alternating last row did not change either", stage);
            end else $display("PASS D3 stage=%0d screen row 0 carries no stale row", stage);
        end

        // ---- R7：×2 行复制几何下的上沿旗标（四家的母本 blur 先判；这是 1× 激励说不出的一维）----
        stage = 2'd0; pkind = 7; run4();
        r7bad = 0; r7n = 0; cxn = 0;
        for (i = 0; i < 2*FW; i = i + 1) if (^cap[i] === 1'bx) cxn = cxn + 1;
        for (i = 0; i < H; i = i + 1) begin
            k = i*W + 20;                                   // 图案沿列不变 ⇒ 取一列就够
            // 期望 = 该显示行三行源行的电平平均；电平是 `hash5(源行)`（与激励同一个映射），
            // 第一版这里写成 `gray(ssrc(..))` 把 hash 漏掉了 ⇒ "定义"算成了另一个东西，红得没有意义。
            e = mean3(gray(hash5(ssrc(i-2))), gray(hash5(ssrc(i-1))), gray(hash5(ssrc(i))));
            r7n = r7n + 1;
            if (dev(cap[k], e) > 1) begin
                r7bad = r7bad + 1;
                if (r7bad <= 6) $display("DIAG R7 disp row %0d (y_in=%0d): got=%h 定义=%h 该格的三行源行={%0d,%0d,%0d}",
                                         i, (i >> 1), cap[k], e, ssrc(i-2), ssrc(i-1), ssrc(i));
            end
        end
        // ---- R8：被判的格子里不许有 X（第一版就是"绿在 X 上"，见上面采集那段）----
        if (cxn != 0) begin
            b0 = 1;
            $display("FAIL R8 %0d captured cells contain X —— 比较式对 X 永远不算不符，绿是假的", cxn);
        end else $display("PASS R8 no X in the captured steady frames");
        if (r7n < 40) begin
            b1g = 1;
            $display("FAIL R7 judged only %0d display rows (floor 40)", r7n);
        end else if (r7bad != 0) begin
            b1g = 1;
            $display("FAIL R7 %0d/%0d display rows 不等于定义 ⇒ ×2 几何下上沿旗标夹掉了合法的上一行", r7bad, r7n);
        end else $display("PASS R7 x2-duplicated geometry: all %0d display rows == definition", r7n);

        // ---- R9：×2 **列**复制几何下的左/右沿夹取（R7 的镜像；四家里先判母本 blur）----
        //   期望 = 该显示列三列源列的电平平均，左右各按"夹到自身"处理；纵向三抽头同值 ⇒ 退化成一维。
        //   若右沿旗标在 2× 下差一对，红会精确落在**末对**（62/63）或它的左邻；若左沿差一对，落在 0/1。
        stage = 2'd0; pkind = 8; run4();
        r9bad = 0; r9n = 0; cxn2 = 0;
        for (i = 0; i < 2*FW; i = i + 1) if (^cap[i] === 1'bx) cxn2 = cxn2 + 1;
        k = 20*W;                                              // 图案沿行不变 ⇒ 取一条内部行就够
        for (i = 0; i < W; i = i + 1) begin
            sc_l = (i == 0)    ? i     : (i - 1);              // 第 0 列的左邻 = 自身
            sc_r = (i == W-1)  ? i     : (i + 1);              // 末列的右邻   = 自身
            e = mean3(gray(hash5(ssrc(sc_l))), gray(hash5(ssrc(i))), gray(hash5(ssrc(sc_r))));
            r9n = r9n + 1;
            if (dev(cap[k + i], e) > 1) begin
                r9bad = r9bad + 1;
                if (r9bad <= 6) $display("DIAG R9 disp col %0d (x_in>>1=%0d): got=%h 定义=%h 三列源列={%0d,%0d,%0d}",
                                         i, (i >> 1), cap[k + i], e, ssrc(sc_l), ssrc(i), ssrc(sc_r));
            end
        end
        if (cxn2 != 0) begin
            b1g = 1;
            $display("FAIL R9x %0d R9 cells contain X —— 比较式对 X 永远不算不符，绿是假的", cxn2);
        end
        if (r9n < 40) begin
            b1g = 1;
            $display("FAIL R9 judged only %0d display columns (floor 40)", r9n);
        end else if (r9bad != 0) begin
            b1g = 1;
            $display("FAIL R9 %0d/%0d display columns 不等于定义 ⇒ ×2 列几何下沿旗标夹错了（看 DIAG 落在哪一对）", r9bad, r9n);
        end else $display("PASS R9 x2-duplicated columns: all %0d display cols == definition", r9n);

        if (derr != 0) begin
            b0 = 1;
            $display("FAIL R0b four stages' de_out disagree in %0d beats (de 约定脱钩)", derr);
        end else if (b0 == 0) $display("PASS R0 ruler integrity: 4 frames per run, all four stages share one de");
        if (b1g == 0) $display("PASS R1 interior == the definition at the measured latency");
        if (b2 == 0)  $display("PASS R2/D1 left column == clamp-to-edge and responds to its neighbour (golden judged %0d)", n2);
        else          $display("FAIL R2/D1 left column NOT clamp-to-edge / not neighbour-sensitive (bad=%0d n2=%0d)", b2, n2);
        if (b3 == 0)  $display("PASS R3 top row == clamp-to-edge (judged %0d)", n3);
        else          $display("FAIL R3 top row NOT clamp-to-edge (bad=%0d n3=%0d)", b3, n3);
        if (b4 == 0)  $display("PASS R4/D2 last column == clamp-to-edge and responds (golden judged %0d)", n4);
        else          $display("FAIL R4/D2 last column NOT clamp-to-edge / not neighbour-sensitive (bad=%0d n4=%0d)", b4, n4);
        if (b5 == 0)  $display("PASS R5/D3 screen row 0 == its own window, no stale row (golden judged %0d)", n5);
        else          $display("FAIL R5/D3 screen row 0 wrong or stale (bad=%0d n5=%0d)", b5, n5);
        if (n2 < 20 || n3 < 20 || n4 < 20 || n5 < 20) begin
            $display("FAIL coverage floor: n2=%0d n3=%0d n4=%0d n5=%0d (each floor 20)", n2, n3, n4, n5);
            b0 = 1;
        end

        if (b0==0 && b1g==0 && b2==0 && b3==0 && b4==0 && b5==0 &&
            n2>=20 && n3>=20 && n4>=20 && n5>=20)
            $display("RESULT tb_edge_rim PASS");
        else $display("RESULT tb_edge_rim FAIL b0=%0d b1=%0d b2=%0d b3=%0d b4=%0d b5=%0d n2=%0d n3=%0d n4=%0d n5=%0d",
                      b0, b1g, b2, b3, b4, b5, n2, n3, n4, n5);
        $finish;
    end
endmodule
`default_nettype wire
