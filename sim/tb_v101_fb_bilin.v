`timescale 1ns/1ps
// tb_v101_fb_bilin —— 双线性读口 `fb_bilin` 的判据（#52 / ISSUES #76 段二的单元凭据）。跑法：bash sim/run_one.sh tb_v101_fb_bilin
// L3 延迟不靠声明、靠量：把 (行滞后, 列平移) 当两个未知数搜索，要求**只有唯一一组成立**，实测 (2 个显示行, 2 拍)。
//   行方向晚一整对（一对结果要等这对的第二行才算得出来并写下）⇒ 顶层补偿 +2 个显示行且必须是**偶数**：奇数行
//   会打破 `row0 = ~y[0]` 的成对奇偶，一对的两行就分属两个源行。列方向 2 拍与 `rd_addr_q`+BRAM 同深 ⇒ `MIX_D` 的账不改。
// L4 逐位严格（不设 ±1 LSB）：黄金写"先纵后横"、RTL 是"先横后纵"，中间量都不截断 ⇒ 同一个整数；抽头接错会差几十 LSB。
module tb_v101_fb_bilin;
    localparam IMG_W = 512, IMG_H = 300;
    localparam H_TOT = 1344, H_FP = 160, H_ACT = 1024;   // 一行：前肩 160 + 有效 1024 + 后肩 160
    localparam NROW  = 24;                                // 四段 × 6 行：段边界 0/6/12/18 **必须偶数**（行号由 row>>1 推 sy，
                                                          // 边界落在奇数行 ⇒ 一对显示行的 A/B 分属两段 = 台架自找的错位）
    localparam NCYC  = NROW * H_TOT + 8;
    localparam LAG   = 2*H_TOT + 2;    // 量出来的错位：晚 1 对显示行（2 行）+ 2 拍（L3 钉住它，不抄字面量）

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;                    // 50 MHz，与顶层 clk_pix 同频

    reg         wr_en = 0;
    reg  [18:0] wr_addr = 0;
    reg  [63:0] wr_data = 0;
    reg  [11:0] sx = 0, sy = 0;
    reg  [8:0]  jd = 0;              // 显示列对号（顶层 = x[9:1]）：暂存/结果缓冲用它索引
    reg  [7:0]  fx = 0, fy = 0;
    reg         bilin_en = 1, col0 = 1, row0 = 1, pair_odd = 0, req_vld = 0, oob_in = 0;
    wire [15:0] pix;
    wire        oob_out;

    fb_bilin #(.IMG_W(IMG_W), .IMG_H(IMG_H)) dut (
        .clk(clk), .rst_n(rst_n),
        .wr_clk(clk), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .sx(sx), .sy(sy), .jd(jd), .fx(fx), .fy(fy), .bilin_en(bilin_en),
        .col0(col0), .row0(row0), .pair_odd(pair_odd), .req_vld(req_vld), .oob_in(oob_in),
        .pix(pix), .oob_out(oob_out)
    );

    // ---- L9/L10：`ISSUES #127` 第 3 条 CANDIDATE 的"机会计数"探针 ----
    // 末行那次 `w_b = w_a + ROW_WORDS` 会越过 `frame_buffer_w64` 的真实数据（WORDS=38400 个字，实际写到 38400
    // 但 bank 深 8192 的填充区从没写过）⇒ xsim 读出 X、板上读出 BRAM 上电的 0。RTL 靠 `ky_use`/`kx_use` 把
    // 越界方向的抽头**折回图内**（`fb_bilin.v:161-162`），所以"屏上没现象"与"真的被折回门住了"两种说法
    // 今天无法区分 —— 除非数出一个非零的**机会**。
    // 吃 DUT 自己的 `addr_nxt` 那根线，不在台架里重算地址：T18 那一轮实测过"重算式判据看不见 RTL 地址算术被换"
    // （`sim/mut_control.sh` 的 `osd_addr` 分支）。对齐：addr_nxt(T) ⇒ 数据在 T+2 回来，`ky_d2` 也是 T 的两拍后。
    localparam WRD = (IMG_W * IMG_H + 3) / 4;
    reg  [1:0] vld_h = 2'b00;
    // 槽位身份决定"该看哪一道折回"：`(row0=0,col0=1)` 发的就是 `w_b`（末行越界），由 **ky** 折回；
    // `(row0=1,col0=0)` 发的是 `w_a+1`（只有最后一个像素越界），由 **kx** 折回。
    // 第一版把两者混成一个计数、只查 ky_d2 ⇒ 末列那一读被算成"没折回"，L10 假红（度量错，不是 DUT 错）。
    reg  [1:0] oobB_h = 2'b00, oobA_h = 2'b00;
    reg [11:0] sy_h1 = 0, sy_h2 = 0;     // 归因用：越界那一拍的 sy 要**两级**历史（一拍历史量到的是下一拍的坐标）
    integer bil_oob_opp = 0, bil_oob_harm = 0, bil_oobB = 0, bil_oobA = 0;
    integer harm_now = 0;
    integer harm_sy = -1, harm_ky = 0, harm_be = 0;
    real    harm_t = 0;
    always @(posedge clk) begin
        oobB_h <= {oobB_h[0], (dut.addr_nxt >= WRD && !dut.row0 && dut.col0)};
        oobA_h <= {oobA_h[0], (dut.addr_nxt >= WRD &&  dut.row0 && !dut.col0)};
        vld_h  <= {vld_h[0], req_vld};
        sy_h1  <= sy;
        sy_h2  <= sy_h1;
        if (dut.addr_nxt >= WRD) begin
            bil_oob_opp = bil_oob_opp + 1;
            // 身份要**当场**判（同一拍的 addr 与同一拍的 row0/col0 才配得上）：上一版拿晚一拍的历史位去 AND
            // 当拍的槽位身份，量的是两件不同的事，所以 B/A 都报了 0 —— 那不是"没有 B 越界"，是度量写错了。
            if (!dut.row0 && dut.col0)    bil_oobB = bil_oobB + 1;
            else if (dut.row0 && !dut.col0) bil_oobA = bil_oobA + 1;
        end
        if (vld_h[1]) begin
            // 第三道门：图外那一格由 `oob` 链回黑（`fb_bilin.v:47` 那句"越界由顶层的 oob 回黑：同一个像素、同一拍"），
            // 所以只有"这一格本来要画、且两道折回都没生效"才算伤害。第一版漏了它 ⇒ 3 拍假红（度量错，不是 DUT 错）。
            harm_now = ((oobB_h[1] && !dut.ky_d2) || (oobA_h[1] && !dut.kx_d2)) && !dut.oob_d2;
            if (harm_now) begin
                // 先钉现场再累加：上一版把捕获写在 `bil_oob_harm == 0` 上，而累加是同块里的阻塞赋值 ⇒
                // 第一次红的那一拍读到的已经是 1，现场永远没记下来（打出来 t=0 / sy=-1 就是这个空值）。
                if (harm_sy < 0) begin
                    harm_t  = $time;
                    harm_sy = sy_h2;                   // 越界那一拍（T）的 sy：299=末行（折回本该是 1）
                    harm_ky = dut.ky_d2;
                    harm_be = oobB_h[1];               // 1=纵向 B 抽头，0=横向 +1 抽头
                end
                bil_oob_harm = bil_oob_harm + 1;
            end
        end
    end

    // ---- 黄金内存（与写口同一份数据，逐字写进 DUT）----
    reg [15:0] mem [0:IMG_W*IMG_H-1];
    reg [15:0] w0, w1, w2, w3;
    integer    c, i, errors;

    // 图样：R 随列异或行、G 随列、B 混两者 ⇒ 每个源像素的值几乎唯一，抽头接错必然留下痕迹
    function [15:0] pxy;
        input [11:0] a, b;
        begin
            pxy = { a[4:0] ^ b[4:0], a[5:0], b[4:0] ^ a[3:0] };
        end
    endfunction

    // 通道展开按定义写（位复制），故意不复用 DUT 里的函数
    function integer e5; input [4:0] v; begin e5 = {24'd0, v, v[2:0]}; end endfunction
    function integer e6; input [5:0] v; begin e6 = {22'd0, v, v[1:0]}; end endfunction

    function [15:0] mpx;                      // 图外回 0：只可能出现在"权重已被钉 0"的抽头上
        input integer a, b;
        begin
            if (a < 0 || a >= IMG_W || b < 0 || b >= IMG_H) mpx = 16'd0;
            else mpx = mem[b*IMG_W + a];
        end
    endfunction

    // ---- 当拍请求的黄金值（只用请求属性 + 黄金内存，与 DUT 的内部延迟无关）----
    integer ref_fx, ref_fy, tr0, tr1, tg0, tg1, tb0, tb1, nr, ng, nb, guard_bad;
    reg [15:0] ref_pix, r0t, r1t, r2t, r3t;
    task ref_step;
        integer ax, ay;
        begin
            guard_bad = guard_bad;
            ref_fx = (!bilin_en || sx >= IMG_W-1) ? 0 : fx;
            ref_fy = (!bilin_en || sy >= IMG_H-1) ? 0 : fy;
            ax = sx; ay = sy;
            r0t = mpx(ax,      ay);
            r1t = mpx(ax + 1,  ay);
            r2t = mpx(ax,      ay + 1);
            r3t = mpx(ax + 1,  ay + 1);
            if (req_vld && (ax >= IMG_W || ay >= IMG_H)) guard_bad = guard_bad + 1;  // 有效槽位不该图外
            tr0 = e5(r0t[15:11])*(256-ref_fy) + e5(r2t[15:11])*ref_fy;
            tr1 = e5(r1t[15:11])*(256-ref_fy) + e5(r3t[15:11])*ref_fy;
            nr  = (tr0*(256-ref_fx) + tr1*ref_fx + 32768) / 65536;
            tg0 = e6(r0t[10:5])*(256-ref_fy) + e6(r2t[10:5])*ref_fy;
            tg1 = e6(r1t[10:5])*(256-ref_fy) + e6(r3t[10:5])*ref_fy;
            ng  = (tg0*(256-ref_fx) + tg1*ref_fx + 32768) / 65536;
            tb0 = e5(r0t[4:0])*(256-ref_fy) + e5(r2t[4:0])*ref_fy;
            tb1 = e5(r1t[4:0])*(256-ref_fy) + e5(r3t[4:0])*ref_fy;
            nb  = (tb0*(256-ref_fx) + tb1*ref_fx + 32768) / 65536;
            ref_pix = { nr[7:3], ng[7:2], nb[7:3] };
        end
    endtask

    // ---- 采样数组（每拍一条）----
    reg [15:0] pq     [0:NCYC-1];
    reg        oq     [0:NCYC-1];
    reg [15:0] gq     [0:NCYC-1];
    reg [15:0] gnn    [0:NCYC-1];
    reg        obo    [0:NCYC-1];
    reg        gvalid [0:NCYC-1];
    reg        isnn   [0:NCYC-1];
    reg [11:0] sxa    [0:NCYC-1];
    reg [11:0] sya    [0:NCYC-1];
    integer    rown [0:NROW-1], rowbd [0:NROW-1], dshow;

    task line;                                 // 判据标签/说明一律 ASCII（xsim 会截 CJK 的 bit7）
        input [8*44-1:0] tag;
        input integer ok;
        input [8*72-1:0] note;
        begin
            if (ok) $display("[tb_v101.v] PASS %0s | %0s", tag, note);
            else    begin $display("[tb_v101.v] FAIL %0s | %0s", tag, note); errors = errors + 1; end
        end
    endtask

    integer rl, cl, nm, nbest, best_rl, best_cl, nchk, nchk_best;
    integer idx, nnbad, slotbad, nslot, nx, nckA, nckB, nckC, nckD, pixbad, labbad, firstbad, warm;
    reg [15:0] a1, a2, a3, a4;

    // ===================================================================== 主流程
    initial begin
        errors = 0; guard_bad = 0; nbest = 0;
        for (i = 0; i < IMG_W*IMG_H; i = i + 1) mem[i] = 16'd0;
        // 硬件上电 BRAM = 0；xsim 是 X。不抹平这个差别，"越界抽头 × 权重 0" 就不可能在仿真里成立。
        // 三块的名字/深度跟着 `frame_buffer_w64` 的拆分走（32768 + 4096 + 2048）；
        // 这里只是把阵列抹平，判据本身与拆法无关，所以拆法再变也只动这三行。
        for (i = 0; i < 32768; i = i + 1) dut.u_fb.a0[i] = 64'd0;
        for (i = 0; i < 4096;  i = i + 1) dut.u_fb.a1[i] = 64'd0;
        for (i = 0; i < 2048;  i = i + 1) dut.u_fb.a2[i] = 64'd0;

        for (i = 0; i < IMG_W*IMG_H; i = i + 4) begin
            w0 = pxy(i % IMG_W,     i / IMG_W);
            w1 = pxy((i+1) % IMG_W, i / IMG_W);
            w2 = pxy((i+2) % IMG_W, i / IMG_W);
            w3 = pxy((i+3) % IMG_W, i / IMG_W);
            mem[i+0] = w0; mem[i+1] = w1; mem[i+2] = w2; mem[i+3] = w3;
            wr_data = {w3, w2, w1, w0};
            wr_addr = i / 4;
            wr_en   = 1'b1;
            @(posedge clk); #1;
        end
        wr_en = 1'b0;
        rst_n = 1'b1;
        repeat (6) @(posedge clk); #1;

        for (c = 0; c < NROW*H_TOT; c = c + 1) begin
            drive(c / H_TOT, c % H_TOT);
            pq[c]  = pix;      oq[c]  = oob_out;
            ref_step;
            gq[c]  = ref_pix;  obo[c] = oob_in;
            gvalid[c] = req_vld;
            isnn[c]   = !bilin_en;
            sxa[c]    = sx;  sya[c] = sy;
            gnn[c]    = mpx(sx, sy);
            @(posedge clk); #1;
        end
        check;
        $finish;
    end

    // 四段：A 常规双线性（sy 10..12）、B 末行夹取 + 人造标签（sy 297..299，验"标签跟着内容走"）、C bilin_en=0 最近邻、
    // D **旋转样子的映射**：源行随"列"走、源列每 4 个显示列对才 +1 ⇒ 同一源列在一行里被反复用到却属于不同源行
    //   —— 正是"暂存按源列 sx 索引"会撞车的形状（用户报的"一开始旋转就满屏噪点"，#68 同族的空集判据由 L8 拦）。
    task drive;
        input integer row, xx;
        integer pair_in_blk;
        begin
            col0     = ~xx[0];
            row0     = ~row[0];
            pair_odd =  row[1];
            req_vld  = (xx >= H_FP) && (xx < H_FP + H_ACT);
            jd       = (xx - H_FP) >> 1;                  // 显示列对号：一对显示列内恒定
            sx       = (row >= 18) ? (100 + (jd >> 2)) : jd;   // 段 D：源列**倒退着重复**（旋转）
            bilin_en = (row < 12) || (row >= 18);
            pair_in_blk = (row - (row/6)*6) >> 1;         // 段内第几对显示行
            sy       = (row < 6)  ? (10 + pair_in_blk)
                     : (row < 12) ? (297 + pair_in_blk)
                     : (row < 18) ? (20 + pair_in_blk)
                                  : ((200 + jd) % 290);   // 段 D：源行沿着一行走 = 旋转的一条线
            fx       = ((sx * 7) + 13) & 8'hFF;       // 只依赖源列 ⇒ 一对显示列内恒定
            fy       = ((sy * 11) + 5) & 8'hFF;       // 只依赖源行 ⇒ 一对显示行内恒定
            oob_in   = (sx >= IMG_W) || (sy >= IMG_H) ||
                       ((row >= 6 && row < 12) && (sx >= 256)) ||
                       ((row >= 12 && row < 18) && ((sx >> 6) & 1));   // 后两项是**人造**标签，只验"标签跟着内容走"
        end
    endtask

    // ===================================================================== 判定
    task check;
        begin
            line("L1 preload", (mem[0] == pxy(11'd0,11'd0)) &&
                 (mem[IMG_W*IMG_H-1] == pxy(IMG_W-1, IMG_H-1)),
                 "golden mem filled through the same words the DUT saw");

            // ---- L3 唯一 (行滞后, 列平移) ----
            // 区分度来自"平移一列必然跨到另一个源列（sx 变 1）"⇒ 错位候选组留下大量不符（实测 (1,2) 那组 44% = "每个偶数行对只对一半"）。
            // 抄字面量把判据调到绿 = 判据作废（#54/#68）。
            for (rl = 0; rl <= 3; rl = rl + 1) begin
                for (cl = -2; cl <= 2; cl = cl + 1) begin
                    nm = 0; nchk = 0;
                    for (c = 0; c < NROW*H_TOT; c = c + 1) begin
                        idx = c - rl*H_TOT - cl;
                        if (idx >= 0 && idx < NROW*H_TOT && gvalid[c] && gvalid[idx]) begin
                            nchk = nchk + 1;
                            if (pq[c] !== gq[idx]) nm = nm + 1;
                        end
                    end
                    if (rl == 2 && cl == 2) begin
                        nchk_best = nchk;
                        $display("[tb_v101.v] NOTE (2 row, 2 cyc): mismatch=%0d of %0d samples", nm, nchk);
                    end
                    if (nchk > 8000 && nm == 0) begin
                        nbest = nbest + 1; best_rl = rl; best_cl = cl;
                    end
                end
            end
            $display("[tb_v101.v]      唯一性：命中的候选组数 nbest=%0d winner=(%0d,%0d)",
                     nbest, best_rl, best_cl);
            line("L3 unique shift", nbest == 1 && best_rl == 2 && best_cl == 2,
                 "the only match must be (2 display rows, 2 cycles) - see header");

            // ---- L4 严格流比对（钉在 (2,0)）+ L5 最近邻 + L7 无 X ----
            pixbad = 0; labbad = 0; nnbad = 0; nx = 0; warm = 0;
            nckA = 0; nckB = 0; nckC = 0; nckD = 0; firstbad = -1;
            for (c = LAG; c < NROW*H_TOT; c = c + 1) begin
                idx = c - LAG;
                if (!gvalid[c] || !gvalid[idx]) begin
                    if ((pix ^ pix) !== 0) warm = warm + 1;
                end else begin
                    if (((pq[c] ^ pq[c]) !== 0) || ((oq[c] ^ oq[c]) !== 0)) nx = nx + 1;
                    if (isnn[idx]) begin
                        nckC = nckC + 1;
                        if (pq[c] !== gnn[idx]) begin
                            nnbad = nnbad + 1;  if (firstbad < 0) firstbad = c;
                        end
                    end else begin
                        if      (idx / H_TOT < 6)  nckA = nckA + 1;
                        else if (idx / H_TOT < 12) nckB = nckB + 1;
                        else                       nckD = nckD + 1;   // 段 D：旋转样子的映射
                        if (pq[c] !== gq[idx]) begin
                            pixbad = pixbad + 1; if (firstbad < 0) firstbad = c;
                        end
                        if (oq[c] !== obo[idx]) labbad = labbad + 1;
                    end
                end
            end
            // ---- DIAG：逐行不符数 + 头几条不符样本现场（红的时候靠它定位，不靠猜）----
            for (rl = 0; rl < NROW; rl = rl + 1) begin rown[rl] = 0; rowbd[rl] = 0; end
            dshow = 0;
            for (c = LAG; c < NROW*H_TOT; c = c + 1) begin
                idx = c - LAG;
                if (gvalid[c] && gvalid[idx] && !isnn[idx]) begin
                    rl = c / H_TOT;
                    rown[rl] = rown[rl] + 1;
                    if (pq[c] !== gq[idx]) begin
                        rowbd[rl] = rowbd[rl] + 1;
                        if (dshow < 6) begin
                            dshow = dshow + 1;
                            $display("[tb_v101.v] DIAG c=%0d row=%0d xx=%0d sxgot=%0d | got=%h exp=%h expNN=%h | idx=%0d sxq=%0d syq=%0d",
                                     c, c/H_TOT, c%H_TOT, sxa[c], pq[c], gq[idx], gnn[idx], idx, sxa[idx], sya[idx]);
                        end
                    end
                end
            end
            for (rl = 0; rl < NROW; rl = rl + 1)
                $display("[tb_v101.v] DIAG row=%0d n=%0d bad=%0d", rl, rown[rl], rowbd[rl]);

            // L4b 标签与内容同级：oob 与像素写进**同一个字、同一拍**读出（段 B/C 的"半幅打标签"图样就为证这个）
            // L5 bilin_en=0 必须**逐位**等于最近邻（不是 ±1 LSB）—— "板上 on/off 来回切不用重新构建"的凭据
            line("L4 exact bilinear stream", pixbad == 0,
                 "bit-exact vs the vertical-first golden, no tolerance");
            line("L4b label follows content", labbad == 0,
                 "oob_out must be the label carried in the SAME written word as the pixel");
            line("L5 nn identity bilin_en=0", nnbad == 0,
                 "nearest neighbour bit-exact (board on/off toggle needs no rebuild)");
            line("L7 no X on checked slots", nx == 0, "X would make every count above a false green");
            $display("[tb_v101.v]      bad pix=%0d label=%0d nn=%0d X=%0d firstbad_cyc=%0d 跳过=%0d",
                     pixbad, labbad, nnbad, nx, firstbad, warm);
            $display("[tb_v101.v]      样本：段A=%0d 段B=%0d 段D(旋转映射)=%0d 最近邻=%0d 黄金越界请求=%0d",
                     nckA, nckB, nckD, nckC, guard_bad);

            // ---- L6 一个 2x2 显示块四槽同值（乒乓极性/撕裂的直接证据，无模型只比 DUT 自己；"来自上一对显示行"由 L3 唯一性钉住）----
            slotbad = 0; nslot = 0;
            for (c = LAG; c + H_TOT + 1 < NROW*H_TOT; c = c + 1) begin
                if (gvalid[c] && gvalid[c+1] && gvalid[c+H_TOT] && gvalid[c+H_TOT+1]
                    && ((c % H_TOT) >= H_FP) && ((c % H_TOT) % 2 == 0)
                    && ((c / H_TOT) % 2 == 0)) begin   // 纵向两拍必须落在**同一对**显示行里
                    a1 = pq[c]; a2 = pq[c+1]; a3 = pq[c+H_TOT]; a4 = pq[c+H_TOT+1];
                    nslot = nslot + 1;
                    if (a1 !== a2 || a1 !== a3 || a1 !== a4) slotbad = slotbad + 1;
                end
            end
            line("L6 four slots same value", slotbad == 0,
                 "one source pixel shows the same value in 2 cols x 2 rows");
            $display("[tb_v101.v]      L6 检查 %0d 个显示块，不符 %0d", nslot, slotbad);

            // ---- L8 覆盖：判据不许在空集上过（#68 同族）----
            // 段 D 也必须真的被量过：把旋转映射从 drive() 里删掉的话，L4 只会"少比对一段"而照样绿 —— 这条就是拦它。
            line("L8 coverage", (nckA > 4000 && nckB > 4000 && nckC > 4000 && nckD > 4000
                                 && nslot > 3000 && guard_bad == 0),
                 "each segment must actually have been measured");

            // ---- L9/L10：#127 第 3 条的成对判据（先让"机会"非零，再说"门住了"）----
            $display("[tb_v101.v]      L9/L10 counts: oob_word_reads=%0d oob_used_unfolded=%0d words=%0d (B=%0d A=%0d)",
                     bil_oob_opp, bil_oob_harm, WRD, bil_oobB, bil_oobA);
            // 没有 offender 时**整行不打**：留一行 t=0 / sy=-1 的初值会让人以为"抓到过-but-没内容"
            if (harm_sy >= 0)
                $display("[tb_v101.v]      L10 first offender: t=%0t tap=%0s sy_then=%0d ky_d2=%0d",
                         harm_t, (harm_be ? "vertical-B" : "horizontal+1"), harm_sy, harm_ky);
            line("L9 bilin padding read happened", (bil_oob_opp > 0),
                 "if 0 the last row was never reached: L10 proves nothing");
            line("L10 padding word never used", (bil_oob_harm == 0),
                 "oob beat folded into the picture with ky_d2=0");

            if (errors == 0) $display("[tb_v101.v] RESULT tb_v101_fb_bilin PASS errors=0");
            else             $display("[tb_v101.v] RESULT tb_v101_fb_bilin FAIL errors=%0d", errors);
        end
    endtask
endmodule
