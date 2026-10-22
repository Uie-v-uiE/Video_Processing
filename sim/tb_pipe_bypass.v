`timescale 1ns/1ps
// 功能：被测模块 `proc_pipeline` #(.H_ACTIVE(1024))（u_pipe，stage_sel=9'd0 即九级全旁路）；
//        覆盖点：全旁路链不凭空造出黑格或 X 格、每个输入列在输出 burst 里恰好出现一次、四个
//        窗口级九条行缓存数组的槽位都被写过、行尾不越界写自己的行缓存，以及"把一列钉黑"的
//        正对照证明探测器不是空转；窗口 C（#129）再覆盖**帧边界**：内容行号进 tag、两臂只差
//        `y_in` 的口径，判"全旁路必须是晚 L 个显示行的直通线"（L 由拟合给，并与 OFF_LINES 对账）。
// 激励与检查：时钟 always #10 clk=~clk（20 ns = 50 MHz，与 clk_pix 同档），负沿置 rst_n=1 后
//        等 4 个上升沿；每行喂 HA=1024 个有效拍（de=1、xc=col、din=patn(col)）再 LINE−HA=320
//        个消隐拍（de=0、xc=1024..1343、din=16'h0000），yc 在整行喂完后才取 row+1，共 ROWS=12
//        行、从第 SETTLE=6 行起判（留过 4 行窗口偏移）；列号从像素里解出（decx 是 patn 的逆），
//        不按"第几个脉冲"计。判据：C0r ruler_bad==0（1024 列都满足 decx(patn(x))==x 且无一
//        落入 v_black 定义）；C10dpre 喂任何像素前 unwr 与 blur lb0/lb1、sharp lb0/lb1、
//        sobel lb0/lb1/mc1、morph mc1/mb1 九个计数逐条 ==1024；C10pre seen_a>=1024 &&
//        blen_j==1024；C10a interior_black==0 && badrow_a==0 && xwin_a==0；C10c holes==0 &&
//        invented==0（每列出现次数 pres[k]==ROWS−SETTLE==6，输出格数恰为 1024×6）；C10d
//        unwr==0；C10fs near_edge>0；C10f oor_blur==0 && oor_sharp==0 && oor_sobel==0 &&
//        oor_morph==0；C10b 在窗口 B（输入第 HOLE=300 列钉成 16'h0000）要求
//        badrow_b>=6 && worst>=6。
// 预期结果：通过时逐条打印 PASS <ASCII 判据名> | <说明>（C0r ruler pattern is invertible and
//        holds no black、C10dpre the cache probe sees every array、C10pre window A judged a
//        whole output burst、C10a bypassed chain invents no black or X cell、C10c every input
//        column is emitted exactly once per row、C10d every line-cache slot was written at
//        least once、C10fs the stimulus really pushed the coordinate to the line end、C10f no
//        window stage writes outside its own line cache、C10b the same detector does see a
//        black column fed in），并带 A row6… / A rows_judged=6 / C10c columns emitted… /
//        C10f out-of-range cache writes… / CACHE at reset、after A: total=… / B row6… /
//        B rows_with_black=… 读数行，末行 RESULT tb_pipe_bypass PASS nfail=0；失败时
//        对应条打印 FAIL <判据名> | <说明> 并 nfail+1，末行 RESULT tb_pipe_bypass
//        FAIL nfail=<n>。C10c 红指向 #111（链子数据比自身 de_out 晚一拍：行首插 0x0000、末列
//        发不出去），定位看 OBS #111 head/tail 行的 val@pos0 与 dec@pos0/1/2/1023；C10f 红
//        指向 #103 的越界写机理，读数在 C10f 行的 first offender x_in / HW slot / din；
//        C10dpre 或 C10fs 红说明层级名指向空或激励没走到行尾，此时其余零读数不作数。
// tb_pipe_bypass —— 只测效果链：全旁路时链子不许凭空造出黑列，也不许把列搞错（ISSUES #103）。
// 板上四条同时成立的事实（2026-09-28 用户眼睛 + 串口逐条量的）：
//   ① `split 100`（整屏换成原图抽头）线就消失 ⇒ 在链子里，不在共用读口；
//   ② 换 zoom 线不动 ⇒ 按**显示列**索引，不是源坐标；
//   ③ 九级全关也还在 ⇒ 不是某一级的算法，是"旁路"这条路本身（`proc_box_blur.v` 末段
//      `dout <= bypass ? center : avg`：旁路给的是行缓存里的窗口中心抽头，不是 `din`）；
//   ④ 只开模糊也不摊成三列 ⇒ 黑不是模糊的输入带进来的。
// 四条合起来只剩一种解释：**某个窗口级的行缓存里那一格从来没被写成内容**。
// 为什么单元台架能看见而顶层台架看不见：xsim 里没写过的数组槽读出来是 X，而硬件里（综合日志：
// blur/sharp/sobel 的 `lb1` 被 `Synth 8-6849` 判 `ram_style="block"` 不可行 ⇒ LUTRAM；
// `proc_morph` 的 `mb0/mb1` 被 `Synth 8-7186` 判根本没推断成 RAM）上电是 0 = 黑。
// ⇒ **同一格的两个名字**：仿真记 X、板子记黑。所以这里的判据把 X 和黑一起数，槽位完整性单独判。
// ⚠ 三个坑（前两个是这份文件自己的历史）：
//   1) `y_in` 必须逐行递增。钉成 0 会让每一拍都满足 `stale_row` ⇒ 旁路走"当前行那一路"，
//      行缓存**根本不参与** ⇒ 判据就在一条没被测的代码上发绿。
//   2) 图案只随列变、不随行变：旁路输出取中心抽头，天然带 −1 行/级（整链 −4 行），
//      随行变就会红在"行偏移"这个正当理由上（#54 那一族的反面教材）。
//   3) 列号不许只由"我数第几个 de_out"说了算。第一版就是这么做的，量到 `col_mismatch=1024`
//      —— 整行都不符，而那是**尺子的错**（一个恒定偏移就够让整行红，于是这条判据永远没有牙）。
//      现在列号从像素里**解出来**（图案可逆），数出来的位置只用来对账，并把 burst 长度与
//      第 0/1/2/1023 格的解值一起打印出来 ⇒ 真有偏移时读数能说是几列。
// 判据（成对写，没有对照的零可能只是探测器瞎）：
//   C0r     尺子自检：图案可逆，且 1024 列里没有一列落进"黑"的定义
//   C10dpre 复位后一个像素都没喂时，这块探针必须**逐条数组**数到 1024 个 X 槽
//   C10pre  被判的那一行几乎覆盖整行，且输出 burst 正好 H_ACTIVE 长
//   C10a    全旁路 + 输入无黑 ⇒ 输出不许有"黑或 X"的格子
//   C10c    全旁路 ⇒ 每一格解出来的列号必须等于它在输出行里的位置
//   C10d    四个窗口级的每一条行缓存：每个槽位都被写过（读回不许带 X）
//   C10b    正对照：把输入的某一列钉黑 ⇒ C10a 那个计数器与那个直方图必须数到东西
module tb_pipe_bypass;

    localparam integer HA     = 1024;         // 与顶层一致：一行 1024 个有效拍（显示列）
    localparam integer LINE   = 1344;         // 一行总拍数（含消隐），与真实时序一致（H_TOTAL=1024+44+88+188）
    localparam integer ROWS   = 12;           // 跑 12 行：前几行是四级行缓存的填充期
    localparam integer SETTLE = 6;            // 从第 6 行开始判（> 4 行偏移 + 余量）
    localparam integer HOLE   = 300;          // 正对照里被钉黑的那一列
    // ⚠ 消隐期**必须让 x 继续数到 1343**、`din` 给 0（= 顶层消隐期 `pix_raw` 的真值，oob 把它钉成 0）。
    //   第一版这里消隐期喂 x=0，于是"行首那一拍的写地址越界"根本没发生 ⇒ C10f 是个不会红的空判据。
    //   一行的次序也与顶层一致：先 1024 个有效拍，再 320 个消隐拍（下一行的行首紧跟着）。

    integer k, row, col, st, seen_a_total = 0;
    integer nfail = 0;
    integer black_a = 0, mism_a = 0, seen_a = 0, badrow_a = 0, xwin_a = 0, unparsable = 0;
    integer black_b = 0, badrow_b = 0;
    integer interior_black = 0, holes = 0, hole_first = -1, invented = 0;
    integer pres[0:HA-1];                    // 每个被判行里，某一源列被发出的次数
    integer hist[0:HA-1];                     // 黑或 X 的格子数（按输出位置）
    integer mh[0:HA-1];                       // 解出的列号 ≠ 输出位置 的格子数
    integer worst = 0, wcol = -1, best = 999999, bcol = 1;
    integer mworst = 0, mwcol = -1;
    integer unwr = 0, unw_first = -1, unw_last = -1;
    integer n_bl0 = 0, n_bl1 = 0, n_sl0 = 0, n_sl1 = 0, n_ob0 = 0, n_ob1 = 0;
    integer n_omc = 0, n_mbit = 0, n_mc1 = 0;
    integer black_col = -1, ruler_bad = 0, blen = 0, blen_j = 0;
    integer dc_c0 = -1, dc_c1 = -1, dc_c2 = -1, dc_tail = -1;
    reg [15:0] v_c0 = 16'h0;
    reg        x_c0 = 1'b0;
    reg        pd_b = 0, pd_s = 0, pd_o = 0, pd_m = 0;
    integer    hd_b = -9, hd_s = -9, hd_o = -9, hd_m = -9;

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;                    // 50 MHz = clk_pix

    reg         de = 0;
    reg  [11:0] xc = 0, yc = 0;
    reg  [15:0] din = 16'h0000;
    reg  [8:0]  sel = 9'd0;
    wire        de_out;
    wire [15:0] dout;

    proc_pipeline #(.H_ACTIVE(HA)) u_pipe (
        .clk(clk), .rst_n(rst_n),
        .stage_sel(sel), .threshold(8'd128),
        .gamma_en(1'b0), .gamma_wr(1'b0), .gamma_idx(8'd0), .gamma_data(8'd0),
        .rotate_active(1'b0),
        .hs_in(1'b0), .vs_in(1'b0),
        .de_in(de), .x_in(xc), .y_in(yc), .din(din),
        .off_rows(), .de_out(de_out), .dout(dout)
    );

    // 每列一个**互不相同**的值（10 个列位全带上：r=x[3:0]、g=x[8:4]、b 带 x[9]），
    // 且三个通道都 ≥16 ⇒ 图案自己永不被判成黑，同时任何一路丢内容都会露出来。
    function [15:0] patn;
        input [11:0] x;
        begin
            patn = {1'b1, x[3:0], 1'b1, x[8:4], 1'b1, x[9], 3'b101};
        end
    endfunction

    // 图案可逆 ⇒ 列号从像素里读，不从"第几个脉冲"里猜。不是本图案的值就报 -1（内容被改过）。
    function integer decx;
        input [15:0] p;
        begin
            if (^p === 1'bx)                              decx = -1;
            else if (p[15] !== 1'b1 || p[10] !== 1'b1 ||
                     p[4]  !== 1'b1 || p[2:0] !== 3'b101) decx = -1;
            else                                          decx = p[3]*512 + p[9:5]*16 + p[14:11];
        end
    endfunction

    function v_black;
        input [15:0] p;
        begin
            v_black = (^p !== 1'bx) && (p[15:11] < 5'd4) && (p[10:5] < 6'd4) && (p[4:0] < 5'd4);
        end
    endfunction

    reg check_on = 0;
    reg [11:0] xo = 0;        // 输出 burst 内数出来的位置（burst 起点重新归 0，只用来与解出的列号对账）
    reg        do_d = 0;

    task line;
        input [8*200-1:0] nm;
        input             ok;
        input [8*300-1:0] why;
        begin
            if (!ok) nfail = nfail + 1;
            $display("%s %0s | %0s", ok ? "PASS" : "FAIL", nm, why);
        end
    endtask

    // 一拍：喂一个像素，同拍收一侧输出（链子有延迟，喂与收并行）
    task step;
        input        vld;
        input [11:0] x;
        input [15:0] d;
        integer dc;
        begin
            @(posedge clk);
            de = vld; xc = x; din = d;
            #1;
            if (de_out && !do_d) begin xo = 12'd0; blen = 0; end   // burst 起点对齐
            if (de_out) begin
                blen = blen + 1;
                dc = decx(dout);
                if (check_on) begin
                    if (xo == 0) begin
                        dc_c0 = dc;
                        v_c0  = dout;
                        x_c0  = (^dout === 1'bx);
                    end
                    // 逐级定位：每一级自己的 burst 头一拍解出的是第几列。
                    // 哪一级先给出 -1 / 与下一级不同，多插的那一格就是它造的。
                    if (u_pipe.u_blur.de_out  && !pd_b) hd_b = decx(u_pipe.u_blur.dout);
                    if (u_pipe.u_sharp.de_out && !pd_s) hd_s = decx(u_pipe.u_sharp.dout);
                    if (u_pipe.u_sobel.de_out && !pd_o) hd_o = decx(u_pipe.u_sobel.dout);
                    if (u_pipe.u_morph.de_out && !pd_m) hd_m = decx(u_pipe.u_morph.dout);
                    pd_b = u_pipe.u_blur.de_out;  pd_s = u_pipe.u_sharp.de_out;
                    pd_o = u_pipe.u_sobel.de_out; pd_m = u_pipe.u_morph.de_out;
                    if (xo == 1)  dc_c1 = dc;
                    if (xo == 2)  dc_c2 = dc;
                    if (xo == HA-1) dc_tail = dc;
                    if (dc < 0) begin
                        unparsable = unparsable + 1;
                        if (xo < HA) mh[xo] = mh[xo] + 1;
                    end else begin
                        if (dc >= 0 && dc < HA) pres[dc] = pres[dc] + 1;
                        if (dc != xo) mism_a = mism_a + 1;
                        if (xo < HA) mh[xo] = mh[xo] + 1;
                    end
                    if (dout === 16'hxxxx || (^dout === 1'bx)) begin
                        xwin_a = xwin_a + 1;
                        black_a = black_a + 1;
                        if (xo > 0 && xo < HA-1) interior_black = interior_black + 1;
                        if (xo < HA) hist[xo] = hist[xo] + 1;
                        black_col = xo;
                    end else if (v_black(dout)) begin
                        black_a = black_a + 1;
                        if (xo > 0 && xo < HA-1) interior_black = interior_black + 1;
                        if (xo < HA) hist[xo] = hist[xo] + 1;
                        black_col = xo;
                    end
                    seen_a = seen_a + 1; seen_a_total = seen_a_total + 1;
                end
                xo = xo + 12'd1;
                if (xo == HA[11:0]) xo = 12'd0;
            end
            if (!de_out && do_d) blen_j = blen;    // 刚结束的那一行输出 burst 有多长
            do_d = de_out;
        end
    endtask

    // ================= C10f：写地址越界（这一条就是 #103 的机理，仿真与硬件在这里分家）=================
    // `proc_pipeline.v:79` 写的是 `xd[0] <= x_in` ⇒ 抽头 `xd[k]` 实际是 **k+1 拍**，而抽头号按的是
    // "该级 de_in 之前累积的拍数"（2/5/8/12）⇒ 四个窗口级的列标签比它自己的 `de` **晚一整拍**：
    //   · 行内最后一个有效拍上 `x_in` 只到 H_ACTIVE-2 ⇒ **H_ACTIVE-1 那个槽位永远没人写**（C10d 量到的就是它）；
    //   · 每行**第一个**有效拍上 `x_in` 还停在消隐期（顶层一屏数到 1343）⇒ 写地址越界。
    // 越界这一笔在 xsim 里是"丢掉"（数组越界的写什么都不做），在硬件里地址按位截断 ⇒
    // **每行往同一个槽位写进一个消隐期的值**（消隐期的 `din` 是 0）⇒ 屏上就是一根钉在固定列的黑线。
    // ⇒ 这条判据是"根因"，C10d/C10a 是它的两个可见后果；三者必须一起从红变绿。
    integer oor_blur = 0, oor_sharp = 0, oor_sobel = 0, oor_morph = 0;
    integer oor_x = -1, oor_slot = -1, oor_din = 0;
    // 取样地板（2026-09-29 只读评审报的一类空判据）：C10f 原来只数"坏条件出现几次"，
    // 于是 `oor_* == 0` 有两种解释——修好了，或者激励根本没把坐标推到行尾（激励一改就白过）。
    // near_edge 数的是"机会"：`de_in` 为高且坐标已经走到最后一列或更靠外。它为 0 时 C10f 不许算数。
    integer near_edge = 0;
    always @(posedge clk) if (rst_n) begin
        if (u_pipe.u_blur.de_in && u_pipe.u_blur.x_in >= HA - 1) near_edge = near_edge + 1;
        if (u_pipe.u_blur.de_in && u_pipe.u_blur.x_in >= HA) begin
            oor_blur = oor_blur + 1;
            if (oor_x < 0) begin
                oor_x    = u_pipe.u_blur.x_in;
                oor_slot = u_pipe.u_blur.x_in % HA;      // 硬件按地址位截断 ⇒ 落到这一格
                oor_din  = u_pipe.u_blur.din;
            end
        end
        if (u_pipe.u_sharp.de_in && u_pipe.u_sharp.x_in >= HA) oor_sharp = oor_sharp + 1;
        if (u_pipe.u_sobel.de_in && u_pipe.u_sobel.x_in >= HA) oor_sobel = oor_sobel + 1;
        if (u_pipe.u_morph.de_in && u_pipe.u_morph.x_in >= HA) oor_morph = oor_morph + 1;
    end

    // 行缓存槽位完整性：分层引用四个窗口级的九条数组，逐条数"读回带 X"的槽位。
    // 这些数组没有复位（带异步复位的 RAM 口综合不出 BRAM），所以只能靠"写过"来干净。
    task scan_cache;
        input [8*24-1:0] nm;
        begin
            n_bl0 = 0; n_bl1 = 0; n_sl0 = 0; n_sl1 = 0; n_ob0 = 0; n_ob1 = 0;
            n_omc = 0; n_mbit = 0; n_mc1 = 0;
            unwr = 0; unw_first = -1; unw_last = -1;
            for (st = 0; st < HA; st = st + 1) begin
                if (^u_pipe.u_blur.lb0[st]  === 1'bx) n_bl0 = n_bl0 + 1;
                if (^u_pipe.u_blur.lb1[st]  === 1'bx) n_bl1 = n_bl1 + 1;
                if (^u_pipe.u_sharp.lb0[st] === 1'bx) n_sl0 = n_sl0 + 1;
                if (^u_pipe.u_sharp.lb1[st] === 1'bx) n_sl1 = n_sl1 + 1;
                if (^u_pipe.u_sobel.lb0[st] === 1'bx) n_ob0 = n_ob0 + 1;
                if (^u_pipe.u_sobel.lb1[st] === 1'bx) n_ob1 = n_ob1 + 1;
                if (^u_pipe.u_sobel.mc1[st] === 1'bx) n_omc = n_omc + 1;
                if (^u_pipe.u_morph.mc1[st] === 1'bx) n_mc1 = n_mc1 + 1;
                if (u_pipe.u_morph.mb1[st]  === 1'bx) n_mbit = n_mbit + 1;
                if (^u_pipe.u_blur.lb0[st] === 1'bx || ^u_pipe.u_blur.lb1[st] === 1'bx ||
                    ^u_pipe.u_sharp.lb0[st] === 1'bx || ^u_pipe.u_sharp.lb1[st] === 1'bx ||
                    ^u_pipe.u_sobel.lb0[st] === 1'bx || ^u_pipe.u_sobel.lb1[st] === 1'bx ||
                    ^u_pipe.u_sobel.mc1[st] === 1'bx ||
                    u_pipe.u_morph.mb1[st] === 1'bx  || ^u_pipe.u_morph.mc1[st] === 1'bx) begin
                    unwr = unwr + 1;
                    if (unw_first < 0) unw_first = st;
                    unw_last = st;
                end
            end
            $display("CACHE %0s: total=%0d first=%0d last=%0d | blur lb0/lb1=%0d/%0d sharp lb0/lb1=%0d/%0d sobel lb0/lb1=%0d/%0d sobel mc1=%0d morph mb1/mc1=%0d/%0d",
                     nm, unwr, unw_first, unw_last, n_bl0, n_bl1, n_sl0, n_sl1, n_ob0, n_ob1, n_omc, n_mbit, n_mc1);
        end
    endtask

    // ================= 窗口 C（#129：C5c 的机理）：绕回连续流里链子必须是"晚 L 行的直通线" =================
    // 顶层往链子里塞的是两本账：`din(pix_raw)` 带的是**请求行**（#54 (B) 的提前量 + #97/#98 的绕回 ⇒ 显示行 d
    // 的 pix_raw 是源行 wrap((d+4)>>1)，见 `pl_video_top.v:276`），而旧写法的 `y_in(cy_d[3])` 是**显示行**
    //（`cy = min(d>>1, IMG_H-1)`，`pl_video_top.v:243`：每帧从 0 重开、只钳不绕）。本体里两者只差一个常数，
    // 帧边界那几行差的不是常数：绕回把源行 0,0,1,1 放进帧头 0..3 行的内容里，标签此时也叫 0,0,1,1，于是四个
    // 窗口级的 `stale_row`（`y_in==0`）在帧头武装，而它的补法是发**当前那一拍**的原色（`proc_sobel.v:150` 的
    // `d21`、`proc_box_blur.v` 的 `h2x`）—— 当前那一拍的内容已经是源行 2 ⇒ 帧头四行发的是前瞻一行的格子
    //（顶层同一件事 = tb_video_pipeline_top 的 C5c：屏上 0..3 行给源行 2，原图抽头同一拍给 0,0,1,1）。
    // 这里并行例化两条链，激励一字不差，只差 `STREAM_WRAP`：
    //   u_pipe（默认 0 = 帧锚定，四把 rim 尺子判的那一版）  → cout0
    //   u_wrap（1 = 绕回连续流，顶层现在用这一版）           → cout1
    // 再叠一个标签口径的变量（两臂只差 `y_in` 怎么算），于是四格读数各说一件事：
    //   锚定实例两臂都必须**坏**（否则 C11c 的零没有对照），绕回实例两臂都必须**不坏**。
    // 判据把"晚几行"交给拟合（不把 OFF_LINES 抄进尺子，链子哪天改深度这把尺子不许先错 —— #54 那一族）。
    localparam integer C_SRC  = 8;              // 一"帧"几个源行（链子只认 y_in 的数值，不认 IMG_H）
    localparam integer C_ACT  = 2*C_SRC;        // 每帧有效显示行 = 源行 x2（与顶层 2:1 同形）
    localparam integer C_BLK  = 4;              // 帧尾消隐行（真实是 25 行；机理只要求"de=0 的行存在过"）
    localparam integer C_FR   = 6;              // 每臂跑 6 帧
    localparam integer C_ADV  = 4;              // 内容相对显示行的提前量 = OFF_LINES + BILIN_ROWS - 2（pix_raw 的账）
    localparam integer C_SAMP = 512;            // 在输出 burst 的第 512 格取样（避开 #111 的行首/行尾那一格）
    localparam integer C_MAXR = 192;            // 行号数组上界（6 帧 x (16+4) = 120，留余量）

    integer cin  [0:C_MAXR-1];                  // 第 i 个**喂入行**喂进去的内容源行号
    integer cout0[0:C_MAXR-1];                  // 锚定实例（u_pipe）第 j 个输出 burst 解出的行号
    integer cout1[0:C_MAXR-1];                  // 绕回实例（u_wrap）同一格
    integer nin_rows = 0, nout0 = 0, nout1 = 0;
    integer a0_bad = -1, a0_L = -1, a1_bad = -1, a1_L = -1, a_n = 0;
    integer armA0_bad = -1, armA1_bad = -1, armA0_L = -1, armA1_L = -1, armA_n = 0;
    integer armB0_bad = -1, armB1_bad = -1, armB0_L = -1, armB1_L = -1, armB_n = 0;
    integer cs_pos0 = 0, cs_pos1 = 0, c11_wraps = 0, c11_ruler_bad = 0;
    integer first0 = -1, first1 = -1;
    reg     co_prev0 = 1'b0, co_prev1 = 1'b0;
    wire        de_out_w;
    wire [15:0] dout_w;

    proc_pipeline #(.H_ACTIVE(HA), .STREAM_WRAP(1)) u_wrap (
        .clk(clk), .rst_n(rst_n),
        .stage_sel(sel), .threshold(8'd128),
        .gamma_en(1'b0), .gamma_wr(1'b0), .gamma_idx(8'd0), .gamma_data(8'd0),
        .rotate_active(1'b0),
        .hs_in(1'b0), .vs_in(1'b0),
        .de_in(de), .x_in(xc), .y_in(yc), .din(din),
        .off_rows(), .de_out(de_out_w), .dout(dout_w)
    );

    function [15:0] patc;                       // 行号进 tag、列取低 7 位：一个像素自己说"我是哪一行"
        input [7:0] r;
        input [11:0] c;
        begin patc = {1'b1, r, c[6:0]}; end
    endfunction

    function integer decr;                      // patc 的逆（只解行；带 X 给 -1）
        input [15:0] p;
        begin decr = (^p === 1'bx) ? -1 : p[14:7]; end
    endfunction

    function integer wrap_row;                  // 与顶层 cy_r 同一条"减一次就够"（#58：不留运行时取模）
        input integer v;
        begin wrap_row = (v >= C_SRC) ? (v - C_SRC) : v; end
    endfunction

    always @(posedge clk) begin                 // 两条链同一拍各数各的 burst
        if (rst_n) begin
            if (de_out  && !co_prev0) cs_pos0 = 0;
            if (de_out  && cs_pos0 == C_SAMP  && nout0 < C_MAXR) begin
                cout0[nout0] = decr(dout);   nout0 = nout0 + 1;
            end
            if (de_out)  cs_pos0 = cs_pos0 + 1;
            if (de_out_w && !co_prev1) cs_pos1 = 0;
            if (de_out_w && cs_pos1 == C_SAMP && nout1 < C_MAXR) begin
                cout1[nout1] = decr(dout_w); nout1 = nout1 + 1;
            end
            if (de_out_w) cs_pos1 = cs_pos1 + 1;
        end
        co_prev0 = de_out;
        co_prev1 = de_out_w;
    end

    task feed_c;                                // 一帧：C_ACT 个有效行（每行都带真实行消隐）+ C_BLK 行全消隐
        input integer labmode;                  // 0 = 臂 A（显示行>>1，顶层 #129 之前的口径）；1 = 臂 B（内容自己的行号）
        integer d, x, tmr, tml;
        reg [7:0] cr, lr;
        begin
            for (d = 0; d < C_ACT + C_BLK; d = d + 1) begin
                tmr = wrap_row((d + C_ADV) >> 1);
                cr  = tmr[7:0];                             // 本行喂进链子的**内容**行号
                tml = d >> 1;
                lr  = (labmode == 0) ? tml[7:0] : cr;       // 喂给 `y_in` 的行标签（两臂唯一的差别）
                if (d < C_ACT) begin
                    if (nin_rows < C_MAXR) begin
                        cin[nin_rows] = tmr;
                        nin_rows = nin_rows + 1;
                    end
                    for (x = 0; x < HA; x = x + 1) begin
                        @(posedge clk);
                        de = 1'b1; xc = x[11:0]; yc = {4'b0, lr}; din = patc(cr, x[11:0]);
                        #1;
                    end
                end else begin
                    for (x = 0; x < HA; x = x + 1) begin
                        @(posedge clk);
                        de = 1'b0; xc = x[11:0]; yc = {4'b0, lr}; din = 16'h0000;
                        #1;
                    end
                end
                // 每一行后面都跟真实的行消隐（`LINE-HA` 拍）：链子的"行尾补跳"、`no_left_r[0] <= ~de_in`
                // 与 `line_end` 全挂在这一段上。第一版只在帧尾留消隐，16 个有效行连成一串 ⇒ `de_out` 16 行
                // 不落地 ⇒ 采样器每帧只数到 1 个 burst（out=6 / fed=96，覆盖地板当场红）。
                for (x = 0; x < LINE - HA; x = x + 1) begin
                    @(posedge clk);
                    de = 1'b0; xc = HA + x; yc = {4'b0, lr}; din = 16'h0000;
                    #1;
                end
            end
        end
    endtask

    task fit_one;                               // 对一条序列找一个常数行延迟 L；只报数，不判定
        input integer arr;                      // 0 = 锚定实例，1 = 绕回实例
        integer L, j, bad, first, n, no, inL;
        begin
            no = (arr == 0) ? nout0 : nout1;
            bad = 0; first = -1; n = 0;
            for (L = 0; L <= 12; L = L + 1) begin
                bad = 0; first = -1; n = 0;
                for (j = 0; j < no; j = j + 1) begin
                    inL = (j >= C_ACT) && ((j - L) >= 0) && ((j - L) < nin_rows);
                    if (inL) begin
                        n = n + 1;
                        if (((arr == 0) ? cout0[j] : cout1[j]) != cin[j-L]) begin
                            bad = bad + 1;
                            if (first < 0) first = j;
                        end
                    end
                end
                if (bad < (arr == 0 ? a0_bad : a1_bad)) begin
                    if (arr == 0) begin a0_bad = bad; a0_L = L; first0 = first; end
                    else            begin a1_bad = bad; a1_L = L; first1 = first; end
                    a_n = n;
                end
            end
        end
    endtask

    task run_arm;                               // 清账 → 喂 6 帧 → 两条链各自拟合
        input integer labmode;
        input [8*56-1:0] nm;
        integer f, ar, j;
        begin
            for (ar = 0; ar < C_MAXR; ar = ar + 1) begin
                cin[ar] = -9; cout0[ar] = -9; cout1[ar] = -9;
            end
            nin_rows = 0; nout0 = 0; nout1 = 0; cs_pos0 = 0; cs_pos1 = 0;
            co_prev0 = 1'b0; co_prev1 = 1'b0;
            a0_bad = 9999; a0_L = -1; a1_bad = 9999; a1_L = -1; a_n = 0; first0 = -1; first1 = -1;
            // 链子是 de 门控的：臂与臂之间不排空也不会串数据（没喂的拍不前进）；
            // 上一臂留在行缓存里的尾巴算进本臂的热身（拟合跳过前 C_ACT 行）。
            for (f = 0; f < C_FR; f = f + 1) feed_c(labmode);
            for (ar = 1; ar < nin_rows; ar = ar + 1)          // 内容序列里真的"绕回"过几次（7 -> 0）
                if (cin[ar] < cin[ar-1]) c11_wraps = c11_wraps + 1;
            fit_one(0);
            fit_one(1);
            $display("C11 %0s: anchored bad=%0d L=%0d first_bad=%0d || wrapped bad=%0d L=%0d first_bad=%0d || judged=%0d fed=%0d out=%0d/%0d rows_per_frame=%0d",
                     nm, a0_bad, a0_L, first0, a1_bad, a1_L, first1, a_n, nin_rows, nout0, nout1, C_ACT);
            for (j = C_ACT; j < nout1; j = j + 1)
                if (((j % C_ACT) < 6) && a1_L >= 0 && (j - a1_L) < nin_rows)
                    $display("  C11 %0s out#%0d frameline=%0d wrapped=%0d anchored=%0d exp=%0d",
                             nm, j, j % C_ACT, cout1[j], cout0[j], cin[j-a1_L]);
        end
    endtask

    initial begin
        for (k = 0; k < HA; k = k + 1) begin hist[k] = 0; mh[k] = 0; pres[k] = 0; end
        @(negedge clk); rst_n = 1;
        repeat (4) @(posedge clk);

        // 尺子自检：图案必须可逆（否则"列对齐"是在我自己编的列号上判的），
        // 且 1024 列里一列都不许落进"黑"的定义（否则 C10a 的黑是我自己带进去的）。
        ruler_bad = 0;
        for (k = 0; k < HA; k = k + 1) begin
            if (decx(patn(k[11:0])) != k) ruler_bad = ruler_bad + 1;
            if (v_black(patn(k[11:0])))   ruler_bad = ruler_bad + 1;
        end
        line("C0r ruler pattern is invertible and holds no black", ruler_bad == 0,
             "every judged column below is read out of the pixel, so the encoding must round-trip and must not contain the thing we count");

        // C10d 的配对：一个像素都没喂时，九条数组的 1024 个槽位**逐条**都必须是 X。
        scan_cache("at reset");
        line("C10dpre the cache probe sees every array",
             unwr == HA && n_bl0 == HA && n_bl1 == HA && n_sl0 == HA && n_sl1 == HA &&
             n_ob0 == HA && n_ob1 == HA && n_omc == HA && n_mc1 == HA && n_mbit == HA,
             "before any pixel is fed each of the nine arrays must read all X, so C10d's zero cannot come from a hierarchical name that points at nothing");

        // ================= 窗口 A：输入无黑、九级全旁路 =================
        sel = 9'd0;
        for (row = 0; row < ROWS; row = row + 1) begin
            check_on = (row >= SETTLE);
            if (check_on) begin black_a = 0; mism_a = 0; seen_a = 0; unparsable = 0;
                interior_black = 0; end
            for (col = 0; col < HA; col = col + 1)        step(1'b1, col[11:0], patn(col[11:0]));
            for (k = 0; k < LINE - HA; k = k + 1)         step(1'b0, HA+k, 16'h0000);
            yc = row[11:0] + 12'd1;             // 行号在整行喂完之后才推进（第一行才是 y=0）
            if (check_on) begin
                badrow_a = badrow_a + ((interior_black > 0) ? 1 : 0);
                if (row == SETTLE)
                    $display("A row%0d: burst=%0d out_px=%0d black_or_X=%0d col_off=%0d unparsable=%0d || dec@pos0/1/2/1023=%0d/%0d/%0d/%0d val@pos0=%h isX=%b || head-decode blur/sharp/sobel/morph=%0d/%0d/%0d/%0d",
                             row, blen_j, seen_a, black_a, mism_a, unparsable,
                             dc_c0, dc_c1, dc_c2, dc_tail, v_c0, x_c0, hd_b, hd_s, hd_o, hd_m);
            end
        end
        check_on = 0;
        scan_cache("after A");
        worst = 0; wcol = -1; best = 999999; bcol = 1; mworst = 0; mwcol = -1;
        for (k = 1; k < HA-1; k = k + 1) begin
            if (hist[k] > worst) begin worst = hist[k];  wcol = k; end
            if (hist[k] < best)  begin best  = hist[k];  bcol = k; end
            if (mh[k] > mworst)  begin mworst = mh[k];   mwcol = k; end
        end
        $display("A rows_judged=%0d black_or_X_cells=%0d col_mismatch=%0d unparsable=%0d bad_rows=%0d || black worst col%0d=%0d best col%0d=%0d || mismatch worst col%0d=%0d",
                 ROWS-SETTLE, black_a, mism_a, unparsable, badrow_a, wcol, worst, bcol, best, mwcol, mworst);
        // 行首那一格与末列那一格是**另一条**病灶（#111，改前改后都在）：burst 内容是
        // `[0x0000, col0, col1, ..., col1022]` —— 首格凭空黑、末列样本发不出去。
        // 它落在屏幕最左那一列（#102 那一族），与 #103 那根钉在显示列 320 的线不是同一件事：
        // #103 的机理是"越界写被硬件截断成第 319 槽"，已由 C10d/C10f 判住。这里把它单独打出来，
        // 不混进下面的判据（混进去 = 这条台架永远红着，谁都不会去看读数）。
        $display("OBS #111 head/tail: val@pos0=%h isX=%b dec@pos0/1/2=%0d/%0d/%0d dec@pos%0d=%0d (head black + last column never emitted)",
                 v_c0, x_c0, dc_c0, dc_c1, dc_c2, HA-1, dc_tail);
        line("C10pre window A judged a whole output burst",
             seen_a >= HA && blen_j == HA,
             "the judged row must be a full H_ACTIVE-long output burst, else the zeros below come from an empty set");
        line("C10a bypassed chain invents no black or X cell",
             interior_black == 0 && badrow_a == 0 && xwin_a == 0,
             "input has no black and all nine stages are bypassed => any black/X out inside the line is made by the chain (#103)");
        // C10c 判的是**契约本身**：旁路的链子是一根直通线，输入的每一列必须在输出 burst 里
        // 出现**恰好一次**（不多、不少、不凭空插一格）。这比"位置 p 必须等于列 p"更硬，
        // 因为它不依赖"哪一拍算 burst 头"这种约定 —— 顶层用 `pipe_dout_q` 把整条链再打一拍，
        // burst 头与内容的对应关系由顶层决定，单元级无权替它定。
        holes = 0; hole_first = -1; invented = 0;
        for (k = 0; k < HA; k = k + 1) begin
            if (pres[k] != ROWS-SETTLE) begin
                holes = holes + 1;
                if (hole_first < 0) hole_first = k;
            end
        end
        invented = seen_a_total - HA*(ROWS-SETTLE);
        $display("C10c columns emitted exactly once per judged row: off-count=%0d first=%0d || cells out=%0d expected=%0d invented=%0d",
                 holes, hole_first, seen_a_total, HA*(ROWS-SETTLE), invented);
        line("C10c every input column is emitted exactly once per row", holes == 0 && invented == 0,
             "ISSUES #111, NOT #103: the chain's data is one beat behind its own de_out, so the last column of every line falls off the end and a 0x0000 cell is inserted at the head (top hides it with pipe_dout_q; #102's left-edge line is the same defect)");
        line("C10d every line-cache slot was written at least once", unwr == 0,
             "an unwritten slot reads X in xsim and 0 on the board: that is one black column per name");
        $display("C10f out-of-range cache writes (de high && x_in >= H_ACTIVE): blur=%0d sharp=%0d sobel=%0d morph=%0d || first offender x_in=%0d -> HW slot %0d with din=%h || opportunity beats (de && x_in >= H_ACTIVE-1)=%0d",
                 oor_blur, oor_sharp, oor_sobel, oor_morph, oor_x, oor_slot, oor_din, near_edge);
        line("C10fs the stimulus really pushed the coordinate to the line end (C10f's sample floor)",
             near_edge > 0,
             "if this is 0, C10f's zeros prove nothing: the stimulus never reached the beat that can overflow the write address. Pair with sim/mut_control.sh: the pre-fix RTL must redden C10f under this same stimulus.");
        line("C10f no window stage writes outside its own line cache",
             oor_blur == 0 && oor_sharp == 0 && oor_sobel == 0 && oor_morph == 0,
             "the coordinate taps sit one beat behind the de chain, so each line head writes x_in=1343: xsim drops that write, the board truncates it to slot 319 and stores the blanking value 0 => one black column at display column 320 (#103)");

        // ================= 窗口 B：正对照，把输入第 HOLE 列钉黑 =================
        for (k = 0; k < HA; k = k + 1) hist[k] = 0;
        for (row = 0; row < ROWS; row = row + 1) begin
            check_on = (row >= SETTLE);
            if (check_on) black_a = 0;
            for (col = 0; col < HA; col = col + 1)
                step(1'b1, col[11:0], (col == HOLE) ? 16'h0000 : patn(col[11:0]));
            for (k = 0; k < LINE - HA; k = k + 1)         step(1'b0, HA+k, 16'h0000);
            yc = row[11:0] + 12'd1;
            if (check_on) begin
                black_b = black_a;              // step 累加的就是 C10a 那一个计数器
                badrow_b = badrow_b + ((black_b > 0) ? 1 : 0);
                if (row == SETTLE)
                    $display("B row%0d: black=%0d (input column %0d was forced black)", row, black_b, HOLE);
            end
        end
        check_on = 0;
        wcol = -1; worst = 0;
        for (k = 0; k < HA; k = k + 1) if (hist[k] > worst) begin worst = hist[k]; wcol = k; end
        $display("B rows_with_black=%0d worst pos%0d = %0d cells", badrow_b, wcol, worst);
        line("C10b the same detector does see a black column fed in",
             badrow_b >= ROWS-SETTLE && worst >= ROWS-SETTLE,
             "pair for C10a: forcing one input column black must light that very counter and that very histogram bin");

        // ================= 窗口 C（#129 / C5c 的机理）：绕回实例必须是纯延迟线 =================
        c11_ruler_bad = 0;
        for (k = 0; k < C_SRC; k = k + 1)
            if (decr(patc(k[7:0], 12'd512)) != k) c11_ruler_bad = c11_ruler_bad + 1;
        line("C11r0 row ruler round-trips and holds no black", c11_ruler_bad == 0,
             "every row number below is read out of the pixel, so the encoding must round-trip for all C_SRC rows");

        run_arm(0, "armA(label=display row>>1, pre-#129 top)");
        armA0_bad = a0_bad; armA1_bad = a1_bad; armA0_L = a0_L; armA1_L = a1_L; armA_n = a_n;
        run_arm(1, "armB(label=content row, shipped top)");
        armB0_bad = a0_bad; armB1_bad = a1_bad; armB0_L = a0_L; armB1_L = a1_L; armB_n = a_n;

        line("C11pre1 each arm judged at least two whole frames", armA_n >= 2*C_ACT && armB_n >= 2*C_ACT,
             "the fit compares an empty set otherwise; one output burst per fed row for 6 frames is the floor");
        line("C11pre2 both chains emitted one burst per fed row", nout0 == nout1 && nout0 >= 2*C_ACT,
             "the two instances share the burst index; if one of them ever dropped or invented a row the four readings below are not comparable");
        line("C11pre3 the stimulus really wrapped (content row decreased)", c11_wraps > 0,
             "the frame-boundary band this window is about must be reached at least once, else every zero below is an empty set");
        line("C11c wrapped chain is a pure delay line, under both label conventions",
             armA1_bad == 0 && armB1_bad == 0,
             "STREAM_WRAP=1 (what the top feeds now) must emit exactly the input row L display rows late: the frame head's center already IS the row it should show, so the forward tap must not fire. Pre-fix reading with the same stimulus: anchored bad=20/80 judged at out#16..19 got=2 exp=0,0,1,1 (arm A) and bad=20 at out#28..31 (arm B) - that is tb_video_pipeline_top C5c's 24 bad head cells");
        line("C11d anchored chain is NOT a pure delay line (the control that makes C11c's zero mean something)",
             armA0_bad != 0 && armB0_bad != 0,
             "same stimulus, same ruler, only STREAM_WRAP differs: if the default (frame-anchored) instance also came out clean, C11c would be decoration and the four rim benches' contract would be untested here");
        line("C11e one constant lag, equal to the chain's own OFF_LINES, in all four readings",
             armA0_L == u_pipe.OFF_LINES && armB0_L == u_pipe.OFF_LINES &&
             armA1_L == u_pipe.OFF_LINES && armB1_L == u_pipe.OFF_LINES,
             "I1: the row offset has exactly one source (u_pipe.OFF_LINES); the fit is not allowed to paper over the boundary by choosing a different L per arm or per instance");

        $display("RESULT tb_pipe_bypass %s nfail=%0d", (nfail == 0) ? "PASS" : "FAIL", nfail);
        $finish;
    end

endmodule
