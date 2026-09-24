`timescale 1ns/1ps
// 台架：右窗**贴着分割线的那一列**为什么会冒出"颜色条"（ISSUES #56 第 1 点的机器凭据）
//
// 用户 2026-09-24 报："右窗缩放的时候线会移位，并且碰到分割线的时候会在分割线周围出现类似的颜色条"。
// 读代码能看到三个**互相独立**的成因，本台架钉的是第 2、3 个：
//   (1) split_display 在 x==PANE_W-1/PANE_W 画了一根硬编码 2 像素蓝线（是特性，不是 bug；
//       参数化归 V8-4，本文件不管它）；
//   (2) **窗口级在最左列把"左邻"取成了上一行的最右列** —— 行缓存的 p 移位链跨过消隐不会复位，
//       于是上一行末尾的像素会漏进这一行的第 0/1/2 列；而右窗的第 0 列**正好就是分割线旁边**，
//       所以漏进来的东西画在缝边上 = 一条竖着的"颜色条"。
//   (3) 首行用的是**上一帧最后一行**的缓存（同一类问题的行版本）。
//
// 三个窗口级对 (2)(3) 的处理**本来就不一致**（2026-09-24 逐字读过）：
//   proc_box_blur.v:69   只挡 `y_d1==0`           ⇒ 最左列漏
//   proc_sharpen.v       挡 `x_d1==0 || y_d1==0`  ⇒ 两处都不漏
//   proc_morph.v:68      挡 `x_d1==0 || y_d1==0`  ⇒ 两处都不漏
//   proc_sobel.v         两个都不挡（`y_in` 甚至没被用过）⇒ 两处都漏
// 这正是"有时看得到有时看不到"的来源：开 Blur 只在缝边漏一列、开 Sobel 缝边和顶边都漏。
//
// 判据用**差分**写法，不猜任何一级的公式：同一份激励跑两遍，只把第 0 行末尾那几个像素
// 从 FLAT 改成 HOT；被测像素若与它们**无关**，两遍的输出必须逐位相同。
//   ⇒ 不依赖"正确答案应该是几"，所以谁都糊弄不了它；也天然自带反面对照（C1 在下面）。
// 另加一条**牙齿对照** C1：把 HOT 放到被测像素真正的左邻（内部列），差分必须**不为 0** ——
// 否则"两遍相同"可能只是因为我的激励根本没影响到输出（量具坏了，不是 DUT 干净）。
module tb_v92_seam_bleed;
    localparam W   = 512;          // 真实右窗宽度（IMG_W=512）
    localparam LN  = 4;            // 一"帧"四行：够让行缓存绕一圈，量到帧边界那一行的漏
    localparam GAP = 832;          // 真实消隐：H 总 1344 - 有效 512
    localparam [15:0] FLAT = 16'h2104;   // 一个**低但非零**的普通像素：低于 morph 的阈值 0x80，
                                      // 又不至于和"钳位取中心"的 0 混成一个值
    localparam [15:0] HOT  = 16'hFFFF;   // 拉满，保证与 FLAT 的差在任何窗口运算里都不为 0

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg         de = 0;
    reg  [11:0] xs = 0, ys = 0;
    reg  [15:0] src = 0;

    // ---------------- 四个被测（都例化成"只这一级"，与整链分开看）----------------
    wire        d_blu, d_shp, d_sob, d_mor;
    wire [15:0] q_blu, q_shp, q_sob, q_mor;

    proc_box_blur #(.H_ACTIVE(W)) u_blu (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0),
        .hs_in(1'b0), .vs_in(1'b0), .de_in(de), .x_in(xs), .y_in(ys), .din(src),
        .de_out(d_blu), .dout(q_blu)
    );
    proc_sharpen #(.H_ACTIVE(W)) u_shp (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0),
        .de_in(de), .x_in(xs), .y_in(ys), .din(src), .de_out(d_shp), .dout(q_shp)
    );
    proc_sobel #(.H_ACTIVE(W)) u_sob (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0),
        .vs_in(1'b0), .de_in(de), .x_in(xs), .y_in(ys), .din(src),
        .de_out(d_sob), .dout(q_sob)
    );
    // morph 吃的是"二值掩码"：mode=2 膨胀（任一邻为 1 即 1）对漏进来的邻最敏感
    proc_morph #(.H_ACTIVE(W)) u_mor (
        .clk(clk), .rst_n(rst_n), .mode(2'd2), .threshold(8'h80),
        .de_in(de), .x_in(xs), .y_in(ys), .din(src), .de_out(d_mor), .dout(q_mor)
    );

    // ---------------- 采样：位置 = 输出脉冲的连续计数（每 W 拍换一行）----------------
    // de_out 是 de_in 延三拍，**每一行的脉冲数仍然是 W**，所以连续数下去就能定出 (行,列)。
    // 只记 MEAS_ROW 那一行、COLS 里那几个列，别的丢掉。
    localparam MEAS_ROW = 2;                       // 帧内第三行：不是首行，绕开 (3) 的干扰
    integer cur_row = MEAS_ROW;                    // C3 要测第 0 行，所以采样行是可变的
    integer pc [0:3];                               // 每个被测一个脉冲计数
    integer got [0:3][0:15];                        // 抓到的值（列 0..2 + 对照区 SP0..SP0+6）
    reg     have [0:3][0:15];
    // 要抓的列：0/1/2 是"缝边漏区"；对照区抓**一段**（197..203）而不是一个点 ——
    // 因为"左邻影响哪一列输出"本身就是本条要问的事（第一版只抓 200，sharpen 报了红，
    // 但红的是"量具没抓到"还是"它的灵敏度串了列"分不清，所以改成整段抓 + 找差值落点）。
    localparam SP0 = 197, NSP = 7, TGT = 200;                  // 对照区：列 197..203
    localparam NC  = 3 + NSP;                       // 索引 0..2 = 漏区列，3.. = 对照区

    integer me, k, found;
    task sample; input integer idx; input [15:0] q;
        begin
            // 先判"这一拍是不是我要的位置"，再自增计数（顺序反了会整体错一格）
            if (pc[idx]/W == cur_row) begin
                if (pc[idx] % W <= 2) begin
                    got[idx][pc[idx] % W] = q; have[idx][pc[idx] % W] = 1;
                end else if (pc[idx] % W >= SP0 && pc[idx] % W < SP0 + NSP) begin
                    found = 3 + (pc[idx] % W - SP0);
                    got[idx][found] = q; have[idx][found] = 1;
                end
            end
            pc[idx] = pc[idx] + 1;
            if (pc[idx] == LN*W) pc[idx] = 0;       // 每"帧"对齐一次，免得漂移累积
        end
    endtask

    always @(posedge clk) if (rst_n) begin
        if (d_blu) sample(0, q_blu);
        if (d_shp) sample(1, q_shp);
        if (d_sob) sample(2, q_sob);
        if (d_mor) sample(3, q_mor);
    end

    // ---------------- 激励：整帧 FLAT，只有若干"扰动格"是 HOT ----------------
    // hot_col_base = -1 ⇒ 无扰动；= W-4 ⇒ 上一行末尾 4 格 HOT（(2) 的探针）；
    //                = 199 ⇒ 对照列的左邻 HOT（C1 的牙齿对照）；= 0 且行 = LN-1 ⇒ (3) 的探针。
    integer run, hot_row, hot_col, ln, cx2, r;
    task drive_frame; input integer hr; input integer hc; input integer nhot;
        begin
            for (ln = 0; ln < LN; ln = ln + 1) begin
                for (cx2 = 0; cx2 < W; cx2 = cx2 + 1) begin
                    @(negedge clk);
                    xs = cx2[11:0]; ys = ln[11:0];
                    src = (ln == hr && cx2 >= hc && cx2 < hc + nhot) ? HOT : FLAT;
                    de  = 1;
                end
                @(negedge clk); de = 0;
                repeat (GAP) @(negedge clk);         // 真实消隐宽度
            end
        end
    endtask

    // 跑一遍：先热身（帧缓存要绕一圈），再清零采样，然后测一帧
    task one_run; input integer hr; input integer hc; input integer nhot;
        begin
            drive_frame(hr, hc, nhot);
            for (me = 0; me < 4; me = me + 1) begin
                pc[me] = 0;
                for (k = 0; k < NC; k = k + 1) have[me][k] = 0;
            end
            drive_frame(hr, hc, nhot);
        end
    endtask

    // 两遍之差（逐位相同 ⇒ 0）
    function integer diff_bits; input [15:0] a, b; begin diff_bits = (a === b) ? 0 : 1; end endfunction

    integer errors = 0;
    reg [15:0] clean [0:3][0:15];
    reg [15:0] prov  [0:3][0:15];
    reg [15:0] ctrl  [0:3][0:15];
    // 本方言不是 SystemVerilog：没有 string / $sformatf（xvlog 直接报错），
    // 所以名字用"函数返回定长串 + 打印时并列"拼出来。
    function [8*8:1] name_of; input integer k;
        begin
            case (k) 0: name_of = "blur";    1: name_of = "sharpen";
                      2: name_of = "sobel";  3: name_of = "morph";
                      default: name_of = "?"; endcase
        end
    endfunction
    task chk; input [8*8:1] tag; input integer k; input cond; input [80*8:1] what;
        begin
            if (cond) $display("  PASS %0s %-8s %0s", tag, name_of(k), what);
            else begin errors = errors + 1; $display("  FAIL %0s %-8s %0s", tag, name_of(k), what); end
        end
    endtask
    task expect; input [120*8:1] name; input cond;
        begin
            if (!cond) begin errors = errors + 1; $display("  FAIL %0s", name); end
            else $display("  PASS %0s", name);
        end
    endtask

    integer col, wmove, wcnt;
    reg [8:0] mapbits [0:3];                   // 每级九个格子的影响位（按 dy,dx 顺序）
    integer mi;
    reg [200*8:1] line_buf, val_buf;
    reg [15:0] base_v [0:3];
    function map_full; input integer k;
        begin
            map_full = 1;
            for (mi = 0; mi < 9; mi = mi + 1) if (!mapbits[k][mi]) map_full = 0;
        end
    endfunction

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (4) @(negedge clk);

        // 第一遍：完全无扰动（上一行末尾也是 FLAT）
        one_run(-1, 0, 0);
        for (me = 0; me < 4; me = me + 1)
            for (k = 0; k < NC; k = k + 1) clean[me][k] = got[me][k];

        // 第二遍：把**上一行末尾** 4 格拉成 HOT —— 干净的设计里它碰不到第 0/1/2 列
        one_run(MEAS_ROW-1, W-4, 4);
        for (me = 0; me < 4; me = me + 1)
            for (k = 0; k < NC; k = k + 1) prov[me][k] = got[me][k];

        // 第三遍（牙齿对照）：HOT 放在对照列 200 的左邻 ⇒ 那一格的输出**必须**变
        one_run(MEAS_ROW, 199, 1);
        for (me = 0; me < 4; me = me + 1)
            for (k = 0; k < NC; k = k + 1) ctrl[me][k] = got[me][k];

        $display("");
        $display("=== 最左列的行末回绕（上一行末尾 4 格 HOT，看第 %0d 行的第 0/1/2 列动不动）===", MEAS_ROW);
        for (me = 0; me < 4; me = me + 1) begin
            $display("%0s  第0列 无扰动=%h 有扰动=%h | 对照区第200列 无扰动=%h 有扰动=%h",
                     name_of(me), clean[me][0], prov[me][0], clean[me][3+3], ctrl[me][3+3]);
        end
        // C0 量具自己先自证：十六个采样点必须**真的**抓到过（没抓到 = 采样位置算错，
        //     而"两遍相同"会在什么都没抓到的情况下假绿 —— 这是本仓一贯的"检查器也要有判据"）
        begin : c0
            integer miss;
            miss = 0;
            for (me = 0; me < 4; me = me + 1)
                for (k = 0; k < NC; k = k + 1) if (!have[me][k]) miss = miss + 1;
            // 注：have 的位宽按 0..2 + 对照区排布，NC 已经包含整段
            expect("C0 十六个采样点全部真的抓到（量具没空跑）", miss == 0);
            if (miss) $display("     缺采样 %0d 个", miss);
        end
        // C1 牙齿对照：每一级都必须**真的**被自己的左邻影响得到，否则下面的"没变"不算证据
        for (me = 0; me < 4; me = me + 1) begin
            wmove = -1; wcnt = 0;
            for (k = 0; k < NSP; k = k + 1)
                if (diff_bits(clean[me][3+k], ctrl[me][3+k]) == 1) begin
                    if (wmove < 0) wmove = SP0 + k;
                    wcnt = wcnt + 1;
                end
            $display("     %0s 对照区：扰动让 %0d 列的输出变了，最先变的是第 %0d 列（左邻在第 199 列）",
                     name_of(me), wcnt, wmove);
            chk("C1", me, wcnt >= 1, "左邻(199)变 HOT 时对照区必须有一列跟着变");
        end

        // C2 主判据：上一行末尾不该影响本行开头
        for (me = 0; me < 4; me = me + 1) begin
            chk("C2", me, diff_bits(clean[me][0], prov[me][0]) == 0,
                "第 0 列不受上一行末尾影响（缝边不冒条）");
            chk("C2", me, diff_bits(clean[me][1], prov[me][1]) == 0, "第 1 列同上");
            chk("C2", me, diff_bits(clean[me][2], prov[me][2]) == 0, "第 2 列同上");
        end

        // C3 帧边界（同一机制的行版本）：上一帧最后一行不该影响本帧第 0 行。
        //    四个被测一起测（计数器必须**一起**复位，单独复位一个会把别家的相位打乱）。
        cur_row = 0;                                // 采样点搬到首行
        for (me = 0; me < 4; me = me + 1) begin pc[me] = 0; for (k = 0; k < NC; k = k + 1) have[me][k] = 0; end
        drive_frame(LN-1, W-4, 4);                 // 让"最后一行末尾"带 HOT，留在缓存里
        for (me = 0; me < 4; me = me + 1) begin pc[me] = 0; for (k = 0; k < NC; k = k + 1) have[me][k] = 0; end
        drive_frame(LN-1, 0, 0);                   // 本帧干净，只有缓存是脏的
        for (me = 0; me < 4; me = me + 1) prov[me][2] = got[me][0];
        for (me = 0; me < 4; me = me + 1) begin pc[me] = 0; for (k = 0; k < NC; k = k + 1) have[me][k] = 0; end
        drive_frame(LN-1, 0, 0);                   // 再来一遍（缓存也干净了）
        for (me = 0; me < 4; me = me + 1) clean[me][2] = got[me][0];
        for (me = 0; me < 4; me = me + 1) begin
            $display("%0s  帧边界第 0 行：脏缓存=%h 干净=%h", name_of(me), prov[me][2], clean[me][2]);
            chk("C3", me, diff_bits(prov[me][2], clean[me][2]) == 0,
                "首行不受上一帧最后一行影响");
        end

        // ---- C4 九点抽头图：**这个窗口到底以哪个像素为中心**，用影响关系量出来 ----
        // 前面所有关于"错位几行几列"的争论都可以被这张图一次回答：
        // 把单个 HOT 放到被测点 (MEAS_ROW, TGT) 的 3×3 邻域里九个位置各跑一遍，
        // 看输出动没动。正确写法应该是九格全 '#'（真正的 3×3 窗口）。
        // 少一格 = 那一路抽头根本没接上；整图上下平移一格 = 窗口中心不在标签像素上。
        begin : tapmap
            integer dy, dx, mv;
            cur_row = MEAS_ROW;         // C3 把它搬到了第 0 行，这一段必须搬回来
            $display("");
            $display("=== 九点抽头图（. = 无影响，# = 有影响；中心 = 被测像素 (行%0d,列%0d)）===",
                     MEAS_ROW, TGT);
            one_run(-1, 0, 0);                          // 全 FLAT 基线
            for (me = 0; me < 4; me = me + 1) base_v[me] = got[me][3 + (TGT - SP0)];
            for (me = 0; me < 4; me = me + 1) begin
                for (dy = -1; dy <= 1; dy = dy + 1) begin
                    line_buf = "";
                    val_buf  = "";
                    for (dx = -1; dx <= 1; dx = dx + 1) begin
                        one_run(MEAS_ROW + dy, TGT + dx, 1);
                        mv = diff_bits(base_v[me], got[me][3 + (TGT - SP0)]);
                        mapbits[me][(1-dy)*3 + (dx+1)] = mv;
                        line_buf = {line_buf, mv ? "##" : ".."};
                        val_buf  = {val_buf, " ", $hexp(16, base_v[me]), "->",
                                    $hexp(16, got[me][3 + (TGT - SP0)])};
                    end
                    $display("%0s  源行偏移 d%0d ：%0s", name_of(me), dy, line_buf);
                    $display("            数值%0s", val_buf);
                end
            end
            // 判据：九格必须**全**亮（3×3 窗口的定义），且中心格也亮（旁路/工作都取中心抽头）
            for (me = 0; me < 4; me = me + 1)
                chk("C4", me, map_full(me) == 1, "九点抽头图九格全亮（3x3 窗口完整）");
        end

        $display("");
        $display("说明 C2/C3 现在的红是**登记在册的缺陷**（blur 只挡首行、sobel 两个都不挡），");
        $display("     修法是让三/四个窗口级共用同一套边界约定，见 ISSUES #54 (A') 与 #56。");
        $display("");
        if (errors == 0) $display("PASS tb_v92_seam_bleed");
        else             $display("FAIL tb_v92_seam_bleed errors=%0d", errors);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("FAIL tb_v92_seam_bleed timeout");
        $finish;
    end
endmodule
