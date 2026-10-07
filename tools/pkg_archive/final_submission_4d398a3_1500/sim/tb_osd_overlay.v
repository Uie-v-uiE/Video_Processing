`timescale 1ns/1ps
// 功能：被测模块 `osd_overlay`（两份例化：`u_osd` 参数 X0=16/Y0=12/SCALE=3/CHAR_W=18/
// CHAR_H=21/LINE_GAP=10/MAX_CHARS=32/N_LINES=5/OUT_W=1024/OUT_H=600；`u_osd2` 只换
// OUT_W=1280/OUT_H=960）；覆盖点：T1..T18 的五行整串逐字符等于期望、边界位宽与饱和、片源
// 标签与星号、PIPE 五位码与缩放八档与 gamma、字模逐像素形状、行宽不越分割线、温度 256
// 编码全扫、osd_en 总开关正反成对、越界索引的机会计数。
// 激励与检查：#10 翻转时钟（周期 20 ns）；rst_n 复位 4 拍后放开、tde 平时为 0，改完激励
// settle 等 4 拍再比（latency 那一格的十进制寄存过一拍）；defaults() 给一组金样（fps=30、
// angle=45、i_sel=9'h005、th=80、gd=18、zc=3、za=1、sp=50、ms=16、ok=1、src=2'b11、
// temp=8'h47）；T2 先喂一位数（fps=9、th=9、angle=5、sp=7、ms=5）再喂越界（fps=200 期望画
// 99、th=255、angle=359、sp=100、ms=5000 期望画 999）、T4 八组控制字
// （9'h000/003/008/010/060/080/180/1FF）、T5 八档 zoom_code 加 zoom_auto=0、T6 gamma 二十
// 一档逐档、T8 读第二份的前 8 格、T9 force u_osd.ch 逐格喂码点、T10 按码点逐像素扫
// 5×7=35 个点、T13/T14 取最宽激励量行宽与残留小写、T15 把 256 个温度编码全扫（期望串
// 由 TB 自己算）、T16 背景取 {8'h12,8'h34,8'h56} 扫整片格子（步长 2）、T17 走完整个
// 1024×600 有效区。
// 判定条件：expect_line 要求前 n 格等于期望串、其余格 ==8'h20（如 L0==
// "1024X600  FPS:30  SRC:ETH"、L2=={"ROT:45",8'hDF,"  ZOOM:0.75X(AUTO)"}、L4==
// "SPLIT:50%  LATENCY:16MS"、L5=="TEMP:47C"）；T8 第二份第 0..7 格依次
// '1''2''8''0''X''9''6''0' 且两份第 1 格必须不相等；T9 非空格 u_osd.gi !==6'd63、空格
// gi ===6'd63；T10 逐像素 nbad==0 且 npx==35 且 oncnt==wantcnt；T13 每行右沿
// X0+k*CW<=511；T14 非空格不得落在小写码点且非空格计数不为 0；T15 分类数必须
// ndig==100 && ndash==156 且 8'hFF 画 "TEMP:--"；T16 要求 t13_off==0 && t13_on>0 &&
// t13_seen>5000；T17 oob_opp>0、T18 oob_harm==0；T11/T15t 各拿一条错期望比一次，errors
// 必须恰好 +1（判据有牙自检，红的撤销计数）；T12 样本地板 ncell>=1500、nvis>=150、
// nscan>=12。
// 预期结果：通过时每段各打一条 `[tb_osd_overlay.v:...] PASS T1..T18`（T12 那条附
// "比对了 %0d 格、查了 %0d 个非空格、扫了 %0d 个字形"，T16 的现场行前缀写作 `T13 scan`），
// errors==0 收尾打 `RESULT tb_osd_overlay PASS`；失败时打
// `FAIL <标签> L<行> cell<列> got %h want %h` 或对应段的 `FAIL T13 ... 右沿 x=%0d 越过分割线
// 511` / `FAIL T14 屏上有 %0d 格是小写码点` / `FAIL T15 分类数不对` /
// `FAIL T16 en=1 差异格=%0d（要 >0）` / `FAIL T17 全程 0 次越界索引` /
// `FAIL T18 有 %0d 拍在**画像素**时索引越界`，收尾打 `RESULT tb_osd_overlay FAIL
// (%0d errors)`，80 ms 看门狗到点打 `RESULT tb_osd_overlay FAIL timeout`。
// tb_osd_overlay —— 例化 osd_overlay 两份（第二份只换 OUT_W/OUT_H，用来钉"尺寸那一格来自参数"），验五行 OSD 的整串逐字符等于给定期望：新排版按实际位数打数字（Th:80 不是 Th:080）⇒ "某一格在第几列"不再是常数，整串比对反而更狠——字段整体挪一格、少打一位、后缀没跟上，全都会红。
// 判据索引 T1..T16：五行内容 · 边界值位宽与饱和 · 片源字段标签与星号 · PIPE 五位码 · 缩放八档与 (AUTO) · gamma
//   … · T13 最宽激励下五行留在分割线内 · **T16 `osd_en=0` 逐位等于背景（叠层总开关，正/反成对）**
//   （2026-09-29：这一条原本也叫 T13，与"行宽"那条撞了标签 ⇒ 日志里看 T13 不知道在看哪一条；换号并补进索引）×10 · 没测量画 -- · 尺寸来自参数 · 格字码必须能在字模表找到号 · 字模逐像素扫 · 判据有牙（错期望必须逐格红）· 陪跑样本地板 · 行宽 X0+k*CW<=511 不越分割线 · 屏上不许残留小写 · 温度半字节 256 编码全扫；每条的期望串写在自己那段的 expect_line 上。
// 跑法：bash sim/run_one.sh tb_osd_overlay
module tb_osd_overlay;
    localparam integer X0 = 16, Y0 = 12, SC = 3, CW = 18, CH = 21, LG = 10;
    // NL 必须跟 RTL 的默认值 N_LINES=5：`put` 有 `col < N_LINES*MAX_CHARS` 的边界保护 ⇒ 写死 4 会把 V9-4 那一行
    // **整行丢出台架**（两份 RTL 都编得过、台架全绿）= #60/#88 的"判据在空集上过"。修法：例化跟默认参数一致，再让 T1e/T13e/T15 真去比那一行。
    localparam integer MC = 32, NL = 5, LH = CH + LG;

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg [8:0]  i_angle = 0;
    reg [7:0]  i_fps   = 0;
    reg [8:0]  i_sel   = 0;
    reg [7:0]  i_th    = 80;
    reg [5:0]  i_gd    = 0;
    reg [7:0]  i_tmp   = 8'hFF;   // V9-6：屏上温度那一格（BCD，半字节 >9 = 没有可信读数）
    reg        i_ns    = 0;       // V9-4：ETH is no signal 的开关
    reg [2:0]  i_zc    = 4;
    reg        i_za    = 0;
    reg [7:0]  i_sp    = 50;
    reg        i_sa    = 0;
    reg [15:0] i_ms    = 0;
    reg        i_ok    = 0;
    reg [1:0]  i_src   = 2'b11;
    reg [1:0]  i_mode  = 2'b00;
    reg [11:0] tx = 0, ty = 0;
    // T16 用：背景像素与叠层总开关。背景**故意不给全黑** —— 全黑时"输出等于背景"和
    // "输出被清成 0"是同一个数，判据就没有牙（#78 那一族：零要能区分"对"与"没测"）。
    reg [7:0] i_r = 8'h12, i_g = 8'h34, i_b = 8'h56;
    reg       i_en = 1'b1;
    reg        tde = 0;
    wire [7:0] ro, go, bo;
    wire de_o, hs_o, vs_o;

    osd_overlay #(.X0(X0), .Y0(Y0), .SCALE(SC), .CHAR_W(CW), .CHAR_H(CH),
                  .LINE_GAP(LG), .MAX_CHARS(MC), .N_LINES(NL),
                  .OUT_W(1024), .OUT_H(600)) u_osd (
        .clk(clk), .rst_n(rst_n), .x(tx), .y(ty), .de(tde),
        .angle(i_angle), .fps(i_fps), .stage_sel(i_sel), .threshold(i_th),
        .gamma_disp(i_gd), .zoom_code(i_zc), .zoom_auto(i_za), .zoom_fit(1'b0),
        .split_pct(i_sp), .split_auto(i_sa), .lat_ms(i_ms), .lat_ok(i_ok),
        .src_eff(i_src), .mode(i_mode), .bg_pix(16'h0), .osd_en(i_en), .no_sig(i_ns), .temp_disp(i_tmp),
        .r_in(i_r), .g_in(i_g), .b_in(i_b), .hs_in(1'b0), .vs_in(1'b0),
        .r(ro), .g(go), .b(bo), .de_out(de_o), .hs_out(hs_o), .vs_out(vs_o)
    );

    // 第二份：只换面板参数（把"尺寸那一格是实参"钉住 —— 第一份无论怎么改激励都回答不了"1024X600 是不是写死的"）。
    wire [7:0] r2, g2, b2;
    osd_overlay #(.X0(X0), .Y0(Y0), .SCALE(SC), .CHAR_W(CW), .CHAR_H(CH),
                  .LINE_GAP(LG), .MAX_CHARS(MC), .N_LINES(NL),
                  .OUT_W(1280), .OUT_H(960)) u_osd2 (
        .clk(clk), .rst_n(rst_n), .x(tx), .y(ty), .de(tde),
        .angle(i_angle), .fps(i_fps), .stage_sel(i_sel), .threshold(i_th),
        .gamma_disp(i_gd), .zoom_code(i_zc), .zoom_auto(i_za), .zoom_fit(1'b0),
        .split_pct(i_sp), .split_auto(i_sa), .lat_ms(i_ms), .lat_ok(i_ok),
        .src_eff(i_src), .mode(i_mode), .bg_pix(16'h0), .osd_en(1'b1), .no_sig(1'b0), .temp_disp(i_tmp),
        .r_in(8'd0), .g_in(8'd0), .b_in(8'd0), .hs_in(1'b0), .vs_in(1'b0),
        .r(r2), .g(g2), .b(b2), .de_out(), .hs_out(), .vs_out()
    );

    integer errors = 0, ncell = 0, nvis = 0, nscan = 0;

    // ---- #127 第 2 条 CANDIDATE 的探针（`osd_overlay.v:487` 的 `chars` 越界读）----
    // 声明是 `[0:N_LINES*MAX_CHARS-1]`，而索引 `s_line*MAX_CHARS + s_cidx` 的位宽允许到
    // `7*MC + (MC-1)` ⇒ 地址能越过数组上界。RTL 靠 `pixel_on = s_in_char && …` 把非字形区间的像素整段丢掉
    // （`osd_overlay.v:492`），所以"真的被门住了"与"激励从没走到过越界地址"在屏上**一模一样**。
    // 只有数出一个非零的**机会**计数，才有资格说前者（`技能包旧条目 criterion_blind_spot.md（重建前的名字，未随本包；现有条目索引见 skills/README.md）`）。
    // 成对写：T17 = 机会地板（必须 > 0，否则 T18 的 0 是空的）；T18 = 伤害计数（画像素那一拍用了越界索引 ⇒ 必须 0）。
    integer oob_opp = 0, oob_harm = 0, oob_max = 0, oob_idx = 0;
    always @(posedge clk) if (rst_n) begin
        oob_idx = u_osd.ch_addr;      // 吃 DUT 那根真地址线（`osd_overlay.v` 的 `ch_addr`）：不再重算
        // 最大值要**每拍**都跟：只在越界分支里更新的话，"最大到过 0"就分不清"索引从没超过 0"与
        // "越界从没发生所以这个累加器一直是初值"（写第一版就踩到了，下面的 FAIL 文案因此是错的）。
        if (oob_idx > oob_max) oob_max = oob_idx;
        if (oob_idx >= NL * MC) begin
            oob_opp = oob_opp + 1;
            if (u_osd.s_in_char) oob_harm = oob_harm + 1;
        end
    end
    reg   verbose = 1;   // T11 那条自检要故意比错，安静下来才不污染 PASS/FAIL 行

    // Latency 的十进制是**寄存过一拍**的（osd_overlay 里那一级拆分），改完激励要等几拍
    task settle;
        begin
            repeat (4) @(posedge clk);
            #1;
        end
    endtask

    // 扫过 OSD 那块矩形（步长 2：字模的一个像素是 SCALE=3 宽，2 的步长不会整块漏掉笔画），
    // 数"输出 != 背景"的格子。latency 是 2 拍 ⇒ 每格等 3 拍再采。
    integer ndiff = 0, nseen = 0;
    task scan_bg;
        input [8*16-1:0] nm;
        integer sx, sy;
        begin
            ndiff = 0; nseen = 0;
            for (sy = 0; sy < NL*(CH+LG); sy = sy + 2) begin
                for (sx = 0; sx < MC*CW; sx = sx + 2) begin
                    tx = (X0 + sx); ty = (Y0 + sy); tde = 1'b1;
                    @(posedge clk); @(posedge clk); @(posedge clk); #1;
                    nseen = nseen + 1;
                    if ({ro, go, bo} !== {i_r, i_g, i_b}) ndiff = ndiff + 1;
                end
            end
            tde = 1'b0;
            $display("T13 scan %0s: 扫过 %0d 格、与背景不同 %0d 格", nm, nseen, ndiff);
        end
    endtask
    integer t13_on = 0, t13_off = 0, t13_seen = 0;

    // 整串比对：**长度由 want 自己数出来**（Verilog 把短串左补 0 塞进宽端口 ⇒ 最高那个非 0 字节的位置就是实际长度），手数格子一定数错。
    // 前 n 格等于 want，其余格必须是空格 —— "尾巴上不许有垃圾"这一条也一起判掉。
    // ⚠ 期望串里的度数符号是用 {"Rot:45", 8'hDF, "..."} **拼**出来的，不是直接打那个字符：字符串按字节塞，
    //   直接写会进去两个 UTF-8 字节（C2 B0），整行错位。
    task expect_line;
        input integer ln;
        input [8*32-1:0] want;
        input [4*8-1:0] tag;
        integer c, n, top;
        reg [7:0] a, b;
        begin
            n = 0;
            for (top = 0; top < 32; top = top + 1)
                if (want[top*8 +: 8] !== 8'h00) n = top + 1;
            for (c = 0; c < MC; c = c + 1) begin
                a = (c < n) ? want[(n-1-c)*8 +: 8] : 8'h20;
                b = u_osd.chars[ln*MC + c];
                if (a !== b) begin
                    errors = errors + 1;
                    if (verbose) $display("  FAIL %0s L%0d cell%0d got %h want %h", tag, ln, c, b, a);
                end
                ncell = ncell + 1;
            end
        end
    endtask

    // 一行占多少格、右沿到不到分割线。几何：X0=16 起点、CW=18 一格 ⇒ 第 k 格（1 基）右沿 = X0+k*CW；
    // 分割线在 x=511/512（split_display 的 PANE_W-1/PANE_W 两列标记）⇒ 判据 X0+k*CW <= 511。
    //（用户报"gamma 那一行跑到分界线那边去"之后加的：当时第二行 28 格 ⇒ 16+28*18 = 520 > 511 就红；收窄后 26 格 = 484。）
    task line_within_pane;
        input integer ln;
        input [4*8-1:0] tag;
        integer c, k, right;
        begin
            k = 0;
            for (c = 0; c < MC; c = c + 1)
                if (u_osd.chars[ln*MC + c] !== 8'h20) k = c + 1;
            right = X0 + k * CW;
            ncell = ncell + k;
            if (right > 511) begin
                errors = errors + 1;
                $display("[tb_osd_overlay.v:122] FAIL %0s L%0d 占了 %0d 格 ⇒ 右沿 x=%0d 越过分割线 511", tag, ln, k, right);
            end else begin
                $display("[tb_osd_overlay.v:124] ok   %0s L%0d 占 %0d 格，右沿 x=%0d <= 511", tag, ln, k, right);
            end
        end
    endtask

    // 逐像素扫一个字符格：亮的像素数必须和 TB 独立写的那份点阵一致
    task scan_glyph;
        input integer ln;
        input integer cidx;
        input [5*7-1:0] want;
        input [4*8-1:0] tag;
        reg wexp;
        integer r, c, oncnt, wantcnt, npx, nbad;
        reg got;
        begin
            oncnt = 0; wantcnt = 0; npx = 0; nbad = 0;
            for (r = 0; r < 7; r = r + 1) begin
                for (c = 0; c < 5; c = c + 1) begin
                    tx = X0 + cidx*CW + c*SC + SC/2;
                    ty = Y0 + ln*LH + r*SC + SC/2;
                    tde = 1'b1;
                    // #96：字格几何现在是**前一拍寄存**的（`s_line/s_cidx/s_pix_x/s_pix_y`）⇒ 先放一个时钟沿让那一拍成立，再在这一拍读 `pixel_on`。
                    // 少这一拍不会变红，而是整幅形状平移一格后继续"对上"（亮像素总数不变 ⇒ 计数式判据看不见平移），
                    // 所以这里不只加沿，末尾 T12 还要求扫描次数 nscan 不为零（形状判据要有样本）。
                    @(posedge clk);
                    #1;
                    got = u_osd.pixel_on;
                    wexp = want[(6-r)*5 + (4-c)];      // 逐像素：第 r 行、第 c 列（位序与 want 的拼法一致）
                    npx = npx + 1;
                    if (got !== wexp) nbad = nbad + 1;
                    if (got) oncnt = oncnt + 1;
                    if (wexp) wantcnt = wantcnt + 1;
                end
            end
            tde = 1'b0;
            // 两条判据，**逐像素那条才是主判**：只数亮像素总数的话"整幅形状平移一格"看不见红（总数一个都不变）—— #96 把字格几何挪到前一拍寄存，最容易出的正是这一类平移。
            if (nbad != 0) begin
                errors = errors + 1;
                $display("[tb_osd_overlay.v:153] FAIL %0s 格(%0d,%0d) 逐像素 %0d/%0d 不对（形状平移/错行）", tag, ln, cidx, nbad, npx);
            end
            if (npx != 35) begin
                errors = errors + 1;
                $display("[tb_osd_overlay.v:156] FAIL %0s 格(%0d,%0d) 只扫了 %0d 个像素（应为 35）⇒ 这一条是空集上的绿", tag, ln, cidx, npx);
            end
            if (oncnt != wantcnt) begin
                errors = errors + 1;
                $display("[tb_osd_overlay.v:161] FAIL %0s 格(%0d,%0d) 亮 %0d 像素，点阵说 %0d", tag, ln, cidx, oncnt, wantcnt);
            end
        end
    endtask

    // T9 的引擎：把某一行的每一格塞进 glyph_idx，**非空格的格不许落到 63**（63 = 这个码点没画字模 ⇒ 屏上静默少一笔；V7.6 靠这条抓出过 R/O/T/L 四个字）
    task no_invisible;
        input integer ln;
        input [4*8-1:0] tag;
        integer c;
        reg [7:0] code;
        begin
            for (c = 0; c < MC; c = c + 1) begin
                code = u_osd.chars[ln*MC + c];
                force u_osd.ch = code;
                #1;
                if (code !== 8'h20) begin
                    nvis = nvis + 1;
                    if (u_osd.gi === 6'd63) begin
                        errors = errors + 1;
                        $display("[tb_osd_overlay.v:174] FAIL %0s 第 %0d 格码点 %h 没有字模（屏上看不见这一笔）", tag, c, code);
                    end
                end else if (u_osd.gi !== 6'd63) begin
                    errors = errors + 1;
                    $display("[tb_osd_overlay.v:178] FAIL %0s 空格格位 %0d 竟然译出了字模号 %0d", tag, c, u_osd.gi);
                end
                release u_osd.ch;
            end
        end
    endtask

    // TB 独立抄一遍的新字模（与 RTL 那份互为反例源：谁改了另一处就红）。#67：a/m/o 原来抄的是**小写**点阵，屏上只有大写之后换成大写那一份；I/X/Y 是那一轮新画的（M 早已有号 34，但那是小写的号）。
    localparam [5*7-1:0] G_A    = {5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
    localparam [5*7-1:0] G_I    = {5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b11111};
    localparam [5*7-1:0] G_M    = {5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
    localparam [5*7-1:0] G_O    = {5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
    localparam [5*7-1:0] G_X    = {5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
    localparam [5*7-1:0] G_Y    = {5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
    localparam [5*7-1:0] G_Z    = {5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b11111};
    localparam [5*7-1:0] G_PCT  = {5'b11000,5'b11001,5'b00010,5'b00100,5'b01000,5'b10011,5'b00011};
    localparam [5*7-1:0] G_COL  = {5'b00000,5'b00110,5'b00110,5'b00000,5'b00110,5'b00110,5'b00000};
    localparam [5*7-1:0] G_DEG  = {5'b01100,5'b10010,5'b10010,5'b01100,5'b00000,5'b00000,5'b00000};
    localparam [5*7-1:0] G_DOT  = {5'b00000,5'b00000,5'b00000,5'b00000,5'b00000,5'b00110,5'b00110};
    localparam [5*7-1:0] G_LPAR = {5'b00010,5'b00100,5'b01000,5'b01000,5'b01000,5'b00100,5'b00010};
    localparam [5*7-1:0] G_DASH = {5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};


    // 按码点在某一行里找那一格，再逐像素扫（找到几处扫几处，找不到就判红）
    task scan_code;
        input integer ln;
        input [7:0] code;
        input [5*7-1:0] want;
        input [4*8-1:0] tag;
        integer c, hit;
        begin
            hit = 0;
            for (c = 0; c < MC; c = c + 1)
                if (u_osd.chars[ln*MC + c] === code) begin
                    hit = hit + 1;
                    scan_glyph(ln, c, want, tag);
                    nscan = nscan + 1;
                end
            if (hit == 0) begin
                errors = errors + 1;
                $display("[tb_osd_overlay.v:215] FAIL %0s L%0d 里找不到码点 %h（这一格没画出来）", tag, ln, code);
            end
        end
    endtask

    task defaults;
        begin
            i_fps = 8'd30; i_angle = 9'd45; i_sel = 9'h005; i_th = 8'd80;
            i_gd = 6'd18;  i_zc = 3'd3;     i_za = 1'b1;
            i_sp = 8'd50;  i_sa = 1'b0;     i_ms = 16'd16;  i_ok = 1'b1;
            i_src = 2'b11; i_mode = 2'b00;
            i_tmp = 8'h47; i_ns = 1'b0;     // 屏上温度那一格：BCD 47 ⇒ `Temp:47C`
        end
    endtask

    integer save_e;
    initial begin
        rst_n = 0; repeat (4) @(posedge clk); rst_n = 1; tde = 0; #1;

        // ================= T1 用户给的那四行，逐字符（#67 之后屏上一律大写、尺寸换成面板）=========
        defaults(); settle;
        expect_line(0, "1024X600  FPS:30  SRC:ETH", "T1a");
        expect_line(1, "PIPE:11000 TH:80 GAMMA:1.8", "T1b");
        expect_line(2, {"ROT:45", 8'hDF, "  ZOOM:0.75X(AUTO)"}, "T1c");
        expect_line(3, "SPLIT:50%  LATENCY:16MS", "T1d");
        // L4（V9-4 开、V9-6 起常驻温度）：这一格第一次有金表 —— 以前 NL 写死 4，那一行整个没被例化出来，"绿"是空集上的绿。
        expect_line(4, "TEMP:47C", "T1e");
        if (errors == 0) $display("[tb_osd_overlay.v:239] PASS T1 四行逐字符等于用户原话（尺寸那一格画面板 1024X600），第 5 行是常驻的温度格");

        // ================= T2 数字宽度：不打前导零；越界一律饱和不回卷 =================
        i_fps = 8'd9;   i_angle = 9'd5; i_th = 8'd9; i_sp = 8'd7; i_ms = 16'd5; settle;
        expect_line(0, "1024X600  FPS:9  SRC:ETH", "T2a");
        expect_line(1, "PIPE:11000 TH:9 GAMMA:1.8", "T2b");
        expect_line(2, {"ROT:5", 8'hDF, "  ZOOM:0.75X(AUTO)"}, "T2c");
        expect_line(3, "SPLIT:7%  LATENCY:5MS", "T2d");
        i_fps = 8'd200; i_angle = 9'd359; i_th = 8'd255; i_sp = 8'd100; i_ms = 16'd5000; settle;
        expect_line(0, "1024X600  FPS:99  SRC:ETH", "T2e");
        expect_line(1, "PIPE:11000 TH:255 GAMMA:1.8", "T2f");
        expect_line(2, {"ROT:359", 8'hDF, "  ZOOM:0.75X(AUTO)"}, "T2g");
        expect_line(3, "SPLIT:100%  LATENCY:999MS", "T2h");
        if (errors == 0) $display("[tb_osd_overlay.v:252] PASS T2 一位数不占两格、fps/ms 越界饱和（99 / 999）而不是回卷成小数");

        // ================= T3 片源那一格：标签跟着屏幕走，不跟意愿走 =================
        // 用词是**用户的决定**（最终定为 `ETH` / `SD` / `TEST`，见 ISSUES #55/#66）：换的只是"这一状态印哪个词"，
        //   `i_src` 的位序 `{fb_vis, owner_eth}` 一个都没动。**不许动的不变部分**：标签跟着屏幕走、锁住才有 `*`、`*` 紧跟名字。
        i_fps = 8'd30; i_src = 2'b10; i_mode = 2'b11; settle;
        expect_line(0, "1024X600  FPS:30  SRC:SD*", "T3a");
        i_src = 2'b00; i_mode = 2'b10; settle;
        expect_line(0, "1024X600  FPS:30  SRC:TEST*", "T3b");
        i_src = 2'b01; i_mode = 2'b01; settle;
        expect_line(0, "1024X600  FPS:30  SRC:TEST*", "T3c");
        i_src = 2'b11; i_mode = 2'b00; settle;
        expect_line(0, "1024X600  FPS:30  SRC:ETH", "T3d");
        if (errors == 0) $display("[tb_osd_overlay.v:268] PASS T3 锁住才有 *、* 紧跟名字；仲裁与 mux 不一致时画 mux 那一路（#55）");

        // ================= T4 五位 Pipe 码 =================
        defaults(); settle;             // 每段自己把激励摆回基线：T2 留下的 Th=255 会把期望串顶歪
        i_sel = 9'd0;   settle; expect_line(1, "PIPE:00000 TH:80 GAMMA:1.8", "T4a");
        i_sel = 9'h003; settle; expect_line(1, "PIPE:30000 TH:80 GAMMA:1.8", "T4b");
        i_sel = 9'h008; settle; expect_line(1, "PIPE:02000 TH:80 GAMMA:1.8", "T4c");
        i_sel = 9'h010; settle; expect_line(1, "PIPE:00100 TH:80 GAMMA:1.8", "T4d");
        i_sel = 9'h060; settle; expect_line(1, "PIPE:00020 TH:80 GAMMA:1.8", "T4e");
        i_sel = 9'h080; settle; expect_line(1, "PIPE:00001 TH:80 GAMMA:1.8", "T4f");
        // 腐蚀+膨胀同时置 1 = proc_pipeline 里写死的"两个都不做"⇒ 第五格必须是 0；写 3 就是"屏上说两个都开、画面上什么都没发生"（tb_v86 T14 的屏上版）
        i_sel = 9'h180; settle; expect_line(1, "PIPE:00000 TH:80 GAMMA:1.8", "T4g");
        i_sel = 9'h1FF; settle; expect_line(1, "PIPE:33120 TH:80 GAMMA:1.8", "T4h");
        defaults(); settle;
        if (errors == 0) $display("[tb_osd_overlay.v:283] PASS T4 八种控制字逐位对（全 1 那组：前两级 3、Sobel 1、阈值旁路 0）");

        // ================= T5 Zoom 八档 + (Auto) 后缀 =================
        begin : blk5
            integer q;
            for (q = 0; q <= 7; q = q + 1) begin
                i_zc = q[2:0]; settle;
                case (q)
                    0:    expect_line(2, {"ROT:45", 8'hDF, "  ZOOM:0.25X(AUTO)"}, "T50");
                    1:    expect_line(2, {"ROT:45", 8'hDF, "  ZOOM:0.33X(AUTO)"}, "T51");
                    2:    expect_line(2, {"ROT:45", 8'hDF, "  ZOOM:0.50X(AUTO)"}, "T52");
                    3:    expect_line(2, {"ROT:45", 8'hDF, "  ZOOM:0.75X(AUTO)"}, "T53");
                    4:    expect_line(2, {"ROT:45", 8'hDF, "  ZOOM:1.00X(AUTO)"}, "T54");
                    5:    expect_line(2, {"ROT:45", 8'hDF, "  ZOOM:1.33X(AUTO)"}, "T55");
                    6:    expect_line(2, {"ROT:45", 8'hDF, "  ZOOM:1.50X(AUTO)"}, "T56");
                    default: expect_line(2, {"ROT:45", 8'hDF, "  ZOOM:2.00X(AUTO)"}, "T57");
                endcase
            end
        end
        i_zc = 3'd3; i_za = 1'b0; settle;
        expect_line(2, {"ROT:45", 8'hDF, "  ZOOM:0.75X"}, "T5z");
        i_za = 1'b1; settle;
        if (errors == 0) $display("[tb_osd_overlay.v:305] PASS T5 八档各自精确；zoom_auto 关掉就不许再有 (AUTO)");

        // ================= T6 Gamma 那一格（γ×10 逐档） =================
        begin : blk6
            integer q;
            reg [7:0] g_hi, g_lo;      // 必须先用 8 bit 的容器接住：拼接里 `8'h30 + q` 的自定
                                        // 宽度是 32 bit ⇒ 期望串会多出三个非零字节，
                                        // expect_line 数出来的长度就错了（第一版栽在这里）
            for (q = 10; q <= 30; q = q + 1) begin
                i_gd = q[5:0];
                g_hi = 8'h30 + (q / 10);
                g_lo = 8'h30 + (q % 10);
                settle;
                expect_line(1, {"PIPE:11000 TH:80 GAMMA:", g_hi, 8'h2E, g_lo}, "T6");
            end
        end
        i_gd = 6'd0; settle;
        expect_line(1, "PIPE:11000 TH:80 GAMMA:0.0", "T6z");
        i_gd = 6'd18; settle;
        if (errors == 0) $display("[tb_osd_overlay.v:324] PASS T6 gamma×10 二十一台逐档对；0.0 = 表关着（PL 逐位旁路）");

        // ================= T7 Latency：没测量就必须画 -- =================
        i_ms = 16'd0; settle;
        expect_line(3, "SPLIT:50%  LATENCY:0MS", "T7a");
        i_ms = 16'd16; settle;
        expect_line(3, "SPLIT:50%  LATENCY:16MS", "T7b");
        i_ms = 16'd125; settle;
        expect_line(3, "SPLIT:50%  LATENCY:125MS", "T7c");
        i_ok = 1'b0; i_ms = 16'd77; settle;
        expect_line(3, "SPLIT:50%  LATENCY:--MS", "T7d");
        i_ok = 1'b1; i_sa = 1'b1; i_ms = 16'd33; settle;
        expect_line(3, "SPLIT:50%(AUTO)  LATENCY:33MS", "T7e");
        i_sa = 1'b0; i_ms = 16'd16; settle;
        if (errors == 0) $display("[tb_osd_overlay.v:338] PASS T7 lat_ok=0 屏上是 --，过期/没算完的数不许冒充测量值");

        // ================= T8 尺寸那一格来自参数，不是写死的串 =================
        // 第二份例化 .OUT_W(1280) .OUT_H(960) ⇒ 第一格起应该是 "1280X960" 八个字符，逐格比、一位都不能错。
        // 走的是 `putnum4` 的**四位**分支（打千位之后三位不省前导零）：换成 800/600 就一辈子测不到那一支。
        begin : blk8
            integer c8;
            reg [7:0] exp8;
            for (c8 = 0; c8 < 8; c8 = c8 + 1) begin
                // '1' '2' '8' '0' 'X' '9' '6' '0'
                exp8 = (c8 == 0) ? 8'h31 : (c8 == 1) ? 8'h32 :
                       (c8 == 2) ? 8'h38 : (c8 == 3) ? 8'h30 :
                       (c8 == 4) ? 8'h58 : (c8 == 5) ? 8'h39 :
                       (c8 == 6) ? 8'h36 : 8'h30;
                if (u_osd2.chars[0*MC + c8] !== exp8) begin
                    errors = errors + 1;
                    $display("[tb_osd_overlay.v:352] FAIL T8 第二份(1280x960) 第 %0d 格 = %h 期望 %h", c8,
                             u_osd2.chars[0*MC + c8], exp8);
                end
                ncell = ncell + 1;
            end
            if (errors == 0) $display("[tb_osd_overlay.v:357] PASS T8 换一组 OUT_* 参数那一格就跟着变 ⇒ 画的是实参");
            // 第一份仍是 1024X600（与第二份并存 ⇒ 排除"两份共用同一个常数"的假绿）。
            // ⚠ 比的是**第 2 格**：两份的千位都是 '1'，拿第 0/1 格比会一起绿（1024 与 1280 的
            //   区别在第 2 格上：'0' 对 '2'）。
            expect_line(0, "1024X600  FPS:30  SRC:ETH", "T8b");
            if (u_osd.chars[0*MC+1] === u_osd2.chars[0*MC+1]) begin
                errors = errors + 1;
                $display("[tb_osd_overlay.v:362] FAIL T8c 两份画了同一个数字 ⇒ 尺寸那一格没吃到参数");
            end
        end

        // ================= T9 屏上不许有"看不见的字母" =================
        // V9-6 起第五行也要查：`TEMP:`、两位温度、`C`，以及 `ETH IS NO SIGNAL`（#67 后全是大写，S/I/G/N/A/L 八个字母一个都不能少字模）—— 少一个就是屏上静默少一笔。
        defaults(); settle;
        no_invisible(0, "T9a"); no_invisible(1, "T9b");
        no_invisible(2, "T9c"); no_invisible(3, "T9d"); no_invisible(4, "T9i");
        i_src = 2'b00; i_mode = 2'b11; i_sa = 1'b1; i_zc = 3'd7;
        i_th = 8'd255; i_ok = 1'b0; i_gd = 6'd30;
        i_ns = 1'b1;   i_tmp = 8'hFF;   settle;   // 温度读不到 + ETH 那一句亮着：这一行的另一半状态
        no_invisible(0, "T9e"); no_invisible(1, "T9f");
        no_invisible(2, "T9g"); no_invisible(3, "T9h"); no_invisible(4, "T9j");
        defaults(); settle;
        if (errors == 0) $display("[tb_osd_overlay.v:375] PASS T9 两种状态 × 五行：每个非空格都译得出字模号，空格必须译成 63");

        // ================= T10 新字模逐像素扫（按码点找格子，不手写第几格） =================
        // 位图是 TB 自己抄的（`build/glyphs_draft.txt` 那份），与 RTL 互为反例源：谁改了 RTL 的一行位图没改这里，亮像素数就对不上。
        defaults(); settle;
        scan_code(1, 8'h49, G_I,    "T10a");    // PIPE 的 I（#67 新画，号 54）
        scan_code(1, 8'h4D, G_M,    "T10b");    // GAMMA 的两个 M（#67 新画，号 55）
        scan_code(1, 8'h41, G_A,    "T10m");    // GAMMA 的两个 A（老号 10，形状与小写 a 不同）
        scan_code(2, 8'h4F, G_O,    "T10c");    // ROT / ZOOM / (AUTO) 里的 O（老号 18）
        scan_code(2, 8'hDF, G_DEG,  "T10d");    // 度数符号
        scan_code(2, 8'h5A, G_Z,    "T10e");    // ZOOM 的 Z（V8-5 新画的大写）
        scan_code(2, 8'h28, G_LPAR, "T10f");    // (AUTO) 的左括号
        scan_code(3, 8'h25, G_PCT,  "T10g");    // 百分号
        scan_code(3, 8'h3A, G_COL,  "T10h");    // 冒号（SPLIT:/LATENCY: 两处，都要有笔画）
        scan_code(1, 8'h2E, G_DOT,  "T10i");    // 1.8 的小数点
        scan_code(0, 8'h58, G_X,    "T10n");    // 尺寸那一格的分隔符 X（#67 新画，号 56）
        scan_code(3, 8'h59, G_Y,    "T10o");    // LATENCY 的 Y（#67 新画，号 57）
        i_ok = 1'b0; settle;
        scan_code(3, 8'h2D, G_DASH, "T10j");    // Latency 没有可信测量时的两根短线
        i_ok = 1'b1; settle;
        if (errors == 0) $display("[tb_osd_overlay.v:393] PASS T10 字模逐个扫过（I M A O Z ( %% : . X Y -），少一笔就少一截亮像素");

        // ================= T11 判据自己有牙吗：拿错的期望比，必须逐格红 =================
        save_e = errors; verbose = 0;
        expect_line(0, "1024X600  FPS:31  SRC:ETH", "T11");
        if (errors == save_e + 1) begin
            $display("[tb_osd_overlay.v:399] PASS T11 错期望被抓到（那一格确实逐格在比，不是恒真式）");
            errors = save_e; verbose = 1;          // 自检的"红"是预期，撤销计数并恢复打印
        end else begin
            verbose = 1;
            errors = errors + 1;
            $display("[tb_osd_overlay.v:404] FAIL T11 判据没牙：错期望报了 %0d 处（应为 1）", errors - save_e);
        end

        // ================= T13 行宽：任何一行都不许越过左半窗的分割线 =================
        // 拿"今天可达的最宽一组激励"来量：FPS 三位、Src 带 * 且是**最长的那个词**、阈值三位、效果字四位全非零、γ 一位小数、时延三位 ⇒ 任何一行都不许出界。
        // ⚠ "最长"这一条**跟着用词走**：用词从 CARD 换成 TEST/SD 之后 `2'b10` 那一态只剩两个字母（"SD"），拿它当最宽激励会悄悄把这一行
        //   缩短 3 格 ⇒ 判据就没牙了。所以这里取 `i_src = 2'b00` → `TEST*`（5 格，与当初的 `CARD*` 同宽）；以后再加词先回来看这一行。
        // ⚠ `i_sa`（Split 的 (Auto) 旗标）**必须留 0** —— 顶层现在把它绑成常量 0（缝还没有执行者，ISSUES #62）。
        //   i_sa=1 量出过 **L3 = 31 格 = 574 px > 511** ⇒ V8-4b 一旦让 (Auto) 真的亮起来，第四行就会压到分割线上，届时要先把 L3 的双空格收掉（或那一格不再画 (Auto)）。
        i_fps = 8'd99; i_src = 2'b00; i_mode = 2'b11;
        i_sel = 9'h1FF; i_th = 8'd255; i_gd = 6'd18;
        i_angle = 9'd359; i_zc = 4; i_za = 1; i_sp = 8'd100; i_sa = 0; i_ms = 16'd999; i_ok = 1;
        // 第五行的最宽激励：温度两位数 + ETH 那一句**同时**在（两者会拼在同一行，
        // 任缺其一都会把这一行的宽度少算 16 格 ⇒ 出界就看不见了）。
        i_tmp = 8'h99; i_ns = 1'b1;
        settle;
        line_within_pane(0, "T13a"); line_within_pane(1, "T13b");
        line_within_pane(2, "T13c"); line_within_pane(3, "T13d");
        line_within_pane(4, "T13e");
        if (errors == 0) $display("[tb_osd_overlay.v:423] PASS T13 最宽可达激励下五行都留在分割线这边（X0+k*CW <= 511）");

        // ================= T14 屏上不许残留小写（#67：字库里已经没有小写）=================
        // 为什么必须单独有：折算在 `put`（写格子那一侧）做，`glyph_idx` 已经不认 0x61~0x7A ⇒ **漏折的那一格不报错，只画成空格**，
        //   所以它不会让任何一次"码点→号"的比对变红 —— 正是 T9 那一族里最隐蔽的一种。
        // 这里直接扫 5×32 个格子：非空格落在小写区间就判红，并**要求非空格足够多**（空集不许过 —— #60）。沿用 T13 的最宽激励：
        //   五行都填满、且 `ETH IS NO SIGNAL` 亮着（这一句是原来小写最密集的地方，最有资格抓漏折）。
        begin : blk14
            integer c14, l14, nchk14, nlow14;
            reg [7:0] b14;
            nchk14 = 0; nlow14 = 0;
            for (l14 = 0; l14 < NL; l14 = l14 + 1)
                for (c14 = 0; c14 < MC; c14 = c14 + 1) begin
                    b14 = u_osd.chars[l14*MC + c14];
                    if (b14 !== 8'h20) begin
                        nchk14 = nchk14 + 1;
                        if (b14 >= 8'h61 && b14 <= 8'h7A) nlow14 = nlow14 + 1;
                    end
                    ncell = ncell + 1;
                end
            if (nlow14 != 0) begin
                errors = errors + 1;
                $display("[tb_osd_overlay.v:443] FAIL T14 屏上有 %0d 格是小写码点 ⇒ put 的折算漏了，它们画不出笔画", nlow14);
            end
            if (nchk14 < 90) begin
                errors = errors + 1;
                $display("[tb_osd_overlay.v:448] FAIL T14 只扫到 %0d 个非空格 ⇒ 这一条是空集上的绿", nchk14);
            end
            if (errors == 0) $display("[tb_osd_overlay.v:452] PASS T14 %0d 个非空格没有一个小写码点", nchk14);
        end

        // ================= T15 温度那一格：256 个编码全扫（V9-6） =================
        // 为什么"全扫 256"而不是挑几个：这一格的规则是一句位判断 `temp_disp[7:4] <= 9 && temp_disp[3:0] <= 9` ⇒ 画 BCD，否则画 `--`；
        //   挑样最容易漏的就是"边界那 1"：把 `<= 9` 写成 `< 9` 只有含数字 9 的编码会红（0x09、0x19、…、0x99 —— 47 °C 这种室温激励一个都不红）。
        // TB 侧期望是**自己算的**（十位/个位各自转 ASCII），不抄 RTL 的字符串：抄来的期望与实现同源 ⇒ 抄错也一起错（T14 讲的是同一件事）。
        // 顺带钉住"两位固定宽度"：0..9 °C 画的是 `Temp:07C` 而不是 `Temp:7C` —— 与 L1/L3 的"不打前导零"**相反**且有意：
        //   这一格后面跟着 ETH 那句异常文字，数字宽度一跳整句就左右抖（理由在 osd_overlay.v 的 L4 那段）。
        begin : blk15
            integer q15, ndig15, ndash15, hit15;
            reg [7:0] c15;                      // ⚠ 扫描变量必须是 reg 不是 integer：**integer 不许
                                                //   做部分选择**（Verilog-2001），而这里要拆两个半字节
            reg [3:0] d15, o15;
            reg [8*32-1:0] w15;
            ndig15 = 0; ndash15 = 0;
            defaults(); settle;      // ⚠ 必须先把 i_ns 收回 0：T13 的最宽激励把 ETH 那一句点亮了，
                                     //   而 expect_line 是**整行 32 格**都比（尾巴多一句就是几十个 FAIL）
            // 起点取在扫描**之前**：原先 `save_e` 是扫完 256 次、分类数也判过之后才取的，
            // 于是"扫描全红"之后 errors 不再增长，末尾那句 `errors == save_e` 照样印
            // "PASS T15 256 个编码全扫过"（2026-09-29 只读评审报的无牙判据，#128）。
            save_e = errors;
            for (q15 = 0; q15 < 256; q15 = q15 + 1) begin
                c15  = q15;        // 靠赋值截到低 8 位（integer 不能做部分选择，写 q15[7:0] 是非法的）
                d15  = c15[7:4];
                o15  = c15[3:0];
                i_tmp = c15;
                if (d15 <= 4'd9 && o15 <= 4'd9) begin
                    w15 = {"TEMP:", 8'h30 + d15, 8'h30 + o15, 8'h43};   // 'C'
                    ndig15 = ndig15 + 1;
                end else begin
                    w15 = "TEMP:--";
                    ndash15 = ndash15 + 1;
                end
                settle;
                expect_line(4, w15, "T15");
            end
            // 陪跑数：100 个能画、156 个画 `--`。少了这一条，"扫了 256 次"本身也可能是错觉
            //（比如循环变量接错，256 次都是同一个编码 ⇒ 全都"过"）。
            if (ndig15 != 100 || ndash15 != 156) begin
                errors = errors + 1;
                $display("[tb_osd_overlay.v:452] FAIL T15 分类数不对：能画 %0d（应 100）、-- %0d（应 156）",
                         ndig15, ndash15);
            end
            // 复位值那一格：effect_ctrl 的 gm_sync 低字节复位成 0xFF ⇒ 屏上必须是 `--`，
            // 不能是 `Temp:00C`（那是一条谁都没测过的数）。扫面里已经含 0xFF，这一条是把它点名。
            i_tmp = 8'hFF; settle;
            expect_line(4, "TEMP:--", "T15z");
            // 这条判据自己有没有牙：拿错的期望比一次 L4（T11 的同一手法，针对新加的这一行）
            verbose = 0;                             // save_e 已提到扫描之前（#128），这里只静音那条故意比错的控制
            i_tmp = 8'h47; settle;
            hit15 = errors;
            expect_line(4, "TEMP:48C", "T15t");          // 故意比错：个位差 1
            if (errors == hit15 + 1) errors = hit15;      // 预期的红，撤销
            else begin
                verbose = 1;
                errors = errors + 1;
                $display("[tb_osd_overlay.v:462] FAIL T15t 第五行的比对没牙：错期望报了 %0d 处（应为 1）",
                         errors - hit15);
            end
            verbose = 1;
            defaults(); settle;
            if (errors == save_e)
                $display("[tb_osd_overlay.v:466] PASS T15 温度那一格 256 个编码全扫过，且错期望会被抓到");
            else begin
                errors = errors + 1;
                $display("[tb_osd_overlay.v:466] FAIL T15 汇总：扫描之前 %0d 个错，现在是 %0d 个 ⇒ 那一格至少有一个编码不对（不是扫描没跑）",
                         save_e, errors - 1);
            end
        end

        // ================= T12 陪跑：样本数必须 > 0（#60 那一课） =================
        if (errors == 0) $display("[tb_osd_overlay.v:434] PASS T12 本台架比对了 %0d 格、查了 %0d 个非空格、扫了 %0d 个字形",
                                  ncell, nvis, nscan);
        if (ncell < 1500 || nvis < 150 || nscan < 12) begin
            errors = errors + 1;
            $display("[tb_osd_overlay.v:438] FAIL T12 样本太少（ncell=%0d nvis=%0d）⇒ 上面有些判据是空的", ncell, nvis);
        end

        // ---- T16：`osd_en=0` 必须让输出**逐位等于背景**（= 这一层不存在），开着才画得出字 ----
        // 为什么成对：只判"关掉以后没有字"是不够的 —— 那可能只是这一层本来就没在画。
        // 所以先量"开着时与背景不同的格子数 > 0"（正对照，证明这块矩形里真的画了东西），
        // 再要求"关掉时那一数 = 0"。两件事同一次扫描里量，格子集合完全相同。
        i_r = 8'h12; i_g = 8'h34; i_b = 8'h56;
        i_en = 1'b1;
        repeat (4) @(posedge clk); #1;
        scan_bg("en=1");  t13_on = ndiff;  t13_seen = nseen;
        i_en = 1'b0;
        repeat (4) @(posedge clk); #1;
        scan_bg("en=0");  t13_off = ndiff;
        if (t13_off == 0 && t13_on > 0 && t13_seen > 5000)
            $display("PASS T16 osd_en=0 => 输出逐位等于背景（关掉=这层不存在），开着在同一片格子里画出了字（对照）");
        else begin
            $display("FAIL T16 en=1 差异格=%0d（要 >0）  en=0 差异格=%0d（要 =0）  扫过格=%0d（要 >5000）",
                     t13_on, t13_off, t13_seen);
            errors = errors + 1;
        end
        i_en = 1'b1;

        // ---- T17 的激励：把整个有效区走一遍（1024×600，`de=1`，硬件每帧就是这么给的）----
        // 上面那些判据只把 `tx/ty` 停在**格子里**的比对点上 ⇒ 索引从没越过数组上界（第一次跑就红在 T17，
        // 而且红得对：机会计数=0 时 T18 的 0 什么都证明不了）。这一趟不做像素比对，只让探针有资格说话。
        begin : walk17
            integer wx, wy;
            verbose = 0;
            for (wy = 0; wy < 600; wy = wy + 1) begin
                ty = wy[11:0];
                for (wx = 0; wx < 1024; wx = wx + 1) begin
                    tx = wx[11:0]; tde = 1'b1;
                    @(posedge clk);
                end
            end
            tde = 1'b0; #1;
            verbose = 1;
        end

        // ---- T17/T18：#127 第 2 条的"机会计数"探针（越界索引真的发生过吗 / 有没有影响到画出来的像素）----
        if (oob_opp == 0) begin
            $display("FAIL T17 全程 0 次越界索引（数组上界 %0d，最大到过 %0d）⇒ T18 的 0 什么都没证明，#127 第 2 条仍未被测过",
                     NL*MC - 1, oob_max);
            errors = errors + 1;
        end else
            $display("PASS T17 激励把索引推到越界 %0d 拍（最大索引 %0d > 数组上界 %0d）⇒ 机会确实出现过",
                     oob_opp, oob_max, NL*MC - 1);
        if (oob_harm != 0) begin
            $display("FAIL T18 有 %0d 拍在**画像素**（s_in_char=1）时索引越界 ⇒ in_char 那道门失效，屏上会取到别一行的字模",
                     oob_harm);
            errors = errors + 1;
        end else
            $display("PASS T18 越界的那 %0d 拍里没有一次 s_in_char=1 ⇒ 读到什么都不画，#127 第 2 条是'被门住的越界读'而不是屏上缺陷",
                     oob_opp);

        $display("");
        if (errors == 0) $display("RESULT tb_osd_overlay PASS");
        else             $display("RESULT tb_osd_overlay FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        // 看门狗只防"挂死"，不是判据。T17 那一趟全有效区扫描要 614400 拍 × 40 ns ≈ 24.6 ms，
        // 原来这 20 ms 会被自己的激励走完 ⇒ 抬到 80 ms（要防的是"一拍都不动"，不是"跑得久"）。
        #80_000_000;
        $display("RESULT tb_osd_overlay FAIL timeout");
        $finish;
    end
endmodule
