`timescale 1ns/1ps
// OSD 四行（V8-5；格式是用户 2026-09-24 亲给的，原话照抄）：
//
//   FPS:30  Src:ETH  512x300
//   Pipe:11000  Th:80  Gamma:1.8
//   Rot:45°  Zoom:0.75x(Auto)
//   Split:50%  Latency:16ms
//
// 与 V7 那六行的差别（谁拿旧截图来对，先看这段）：
//   * 行容量 MAX_CHARS 10→32、行数 6→4。SCALE=3 时 32 格 = 576 像素 < 1024 ✓，
//     四行高 4×(21+10) = 124 < 600 ✓ ⇒ 字格尺寸一个都没动，动的只有字数与字模。
//   * 老六行里的 DROP / STALL **从屏上撤了**，不是功能删了：这两个数在
//     `src/host/health_read.mjs` 的 lane0~lane9 里本来就是机器可读的，而屏上这几格
//     要让给 spec 要求的四个字段。撤掉的两行仍各自有台架凭据（`tb_link_monitor` 等）。
//   * `Pipe:` 一格换口径：五位、每位 0..3，每位是"这一级开了哪个算法"
//     （1=第一个、2=第二个、3=两个都开、0=这一级旁路）。这**不是** V7 那个五位使能
//     （`en[4:0]`），拿旧截图对不上是有意的，见 PLAN_V8_SPEC.md §7d 那张表。
//   * `Src:` 画的仍然是"屏幕上真的这一路"（`src_eff`），意愿只用末尾一个 `*` 表示。
//     这条是 r48 的教训（ISSUES #55）：照着"想要哪一路"画标签，屏幕与标签就会在
//     "意愿没生效"的那些状态下对不上 —— 用户报的"CARD/PS 反了、显示 ETH 时写 AUTO"就是这个。
//     ⇒ 台架 tb_osd_lines 里那条"仲裁以为占着屏但 mux 选的是图卡"的反例必须一直留着。
//   * `Latency:` 这一格现在合法：#59 的快照口在 r51 板级 8/8 自洽
//     （`build/lat_snapshot_r51.txt`），换算在 axi 域用**逐次除法**做完再按翻转位跨域
//     （#58/#36/#52 三条规矩一起用）。没有可信测量时画 `--`：不许把不成立的数画到屏上。
//   * `Split:` 现在画的是**几何参数决定的那一格**（左窗宽 / 屏宽 = 50 %），因为可动缝
//     还没有执行者（`split_ctrl` 已单独验完、尚未接线，见 ISSUES #62）。V8-4b 把几何统一好
//     之后这一格改成读 `split_ctrl.shown_pct` —— 端口位宽已经留够，不用再改一次接口。
// 字模：5x7，SCALE=3。空格是索引 63（V8-5 之前是 31），**表里没有的码点一律落空格**，
//       绝不落到 0 —— 把未知字符画成数字 0 是这类表最难看出来的一种错。
module osd_overlay #(
    parameter X0 = 16,
    parameter Y0 = 12,
    parameter SCALE = 3,
    parameter CHAR_W = 18,          // 5*3 + 3 gap
    parameter CHAR_H = 21,          // 7*3
    parameter LINE_GAP = 10,
    parameter MAX_CHARS = 32,
    parameter N_LINES = 4,
    parameter IMG_W = 512,          // 片源几何：第一行末尾那一格报的就是它（实参，不是示意值）
    parameter IMG_H = 300
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        de,
    // ---- 四行的数据来源。规矩：**每一个都必须在 PLAN §7d 的表里**，不在表里的不许上屏 ----
    input  wire [8:0]  angle,        // 度（0..359：angle_ctrl 里就是十进制度数，不用换算）
    input  wire [7:0]  fps,          // fps_q
    input  wire [8:0]  stage_sel,    // 五级链实际生效的九位（effect_ctrl 合流之后的那一个口）
    input  wire [7:0]  threshold,    // 二值化阈值
    input  wire [5:0]  gamma_disp,   // gamma×10，PS 写 LUT 时同一个字顺路带过来，只用于显示
    input  wire [2:0]  zoom_code,    // zoom_ctrl 的"最近一档"号（八档表在它那边）
    input  wire        zoom_auto,    // 1 = 呼吸缩放正在跑 ⇒ Zoom 后面加 (Auto)
    input  wire [7:0]  split_pct,    // 见文件头：现在来自几何参数
    input  wire        split_auto,   // 1 = 缝在自动扫描 ⇒ (Auto)
    input  wire [15:0] lat_ms,       // 链路内时延（ms），axi 域除完再过 snap_cross
    input  wire        lat_ok,       // 0 ⇒ 没有可信测量，画 `--`
    input  wire [1:0]  src_eff,      // {fb_vis, owner_eth}：屏幕上真的这一路
    input  wire [1:0]  mode,         // 00 自动 01 ETH 11 SD 10 TEST（与 src_mode 同序；`*` 由它派生）
    input  wire [15:0] bg_pix,
    output reg  [7:0]  r,
    output reg  [7:0]  g,
    output reg  [7:0]  b,
    output reg         de_out,
    input  wire        hs_in,
    input  wire        vs_in,
    output reg         hs_out,
    output reg         vs_out,
    input  wire [7:0]  r_in,
    input  wire [7:0]  g_in,
    input  wire [7:0]  b_in
);
    localparam LINE_H = CHAR_H + LINE_GAP;
    localparam BOX_W  = MAX_CHARS * CHAR_W;
    localparam BOX_H  = N_LINES * LINE_H;

    wire in_box = de && (x >= X0) && (x < X0 + BOX_W) &&
                  (y >= Y0) && (y < Y0 + BOX_H);
    wire [11:0] lx = x - X0;
    wire [11:0] ly = y - Y0;
    // 行号位宽跟着 N_LINES 走：V7.6 那次写死 [1:0]，加到第 5/6 行时屏幕上永远取不到，
    // 而综合与时序报告全绿 —— 那是本文件第二次"绿着没显示"。
    wire [2:0]  line  = (ly / LINE_H);
    wire [7:0]  pix_y = ly - line * LINE_H;
    wire [4:0]  cidx  = lx / CHAR_W;
    wire [7:0]  pix_x = lx % CHAR_W;
    wire        in_char = in_box && (pix_y < CHAR_H) && (line < N_LINES);

    function [7:0] dig;
        input [3:0] v;
        begin
            if (v <= 4'd9) dig = 8'h30 + v;  // '0'..'9'
            else           dig = 8'h20;      // blank
        end
    endfunction

    // "这一级开了哪个算法"：0=都不开 1=第一个 2=第二个 3=两个都开
    function [7:0] lvl;
        input a, b;
        begin
            if (a && b)  lvl = "3";
            else if (b)  lvl = "2";
            else if (a)  lvl = "1";
            else         lvl = "0";
        end
    endfunction

    // （十进制的排版在下面的"打字符"任务里：putd3 按**实际位数**打，不打前导零 ⇒
    //   用户写的是 `Th:80` / `Split:50%`，屏上就不会变成 `Th:080` / `Split: 50%`。）

    wire [7:0] fps_v = (fps > 8'd99) ? 8'd99 : fps;

    // ---- 五位的 Pipe 码（PLAN §7d 的表；从**实际生效**的九位组合，不留第二条链）----
    wire [7:0] pc1 = lvl(stage_sel[0], stage_sel[1]);                    // 颜色：灰度 / 反色
    wire [7:0] pc2 = lvl(stage_sel[2], stage_sel[3]);                    // 滤波：模糊 / 锐化
    wire [7:0] pc3 = lvl(stage_sel[4], 1'b0);                            // 边缘：只有 Sobel
    // 阈值那一格只有"两种"，没有"同时开两种"：[6] 是 [5] 的**判决反相位**（只在 [5]=1 时有意义），
    // 所以它是"第二个算法"而不是"叠加"——lvl([5], [5]&[6]) 会把"两位都设了"画成 3，
    // 而屏上此刻显示的仍然是**一张**二值图。台架 T4e 钉住这件事（期望 2 而不是 3）。
    wire [7:0] pc4 = !stage_sel[5] ? "0" : (stage_sel[6] ? "2" : "1");
    // 形态学：腐蚀 / 膨胀。两位同时为 1 在 proc_pipeline 里是**明确的旁路**（开闭运算要两遍
    // 3×3 窗口，那里只有一遍；见其注释与 tb_v86 的 T14），所以这一格必须给 0 ——
    // 给 3 就是"屏上写着两个都开、画面上什么都没发生"，那正是本项目最不该犯的那类错。
    wire [7:0] pc5 = lvl(stage_sel[7] & ~stage_sel[8], stage_sel[8] & ~stage_sel[7]);

    // ---- Zoom 八档：号在 zoom_ctrl 里选（那里查表，不除），这里只把号翻成 5 个字符 ----
    reg [7:0] zc0, zc1, zc2, zc3, zc4;
    always @(*) begin
        case (zoom_code)
            3'd0:    begin {zc0,zc1,zc2,zc3,zc4} = "0.25x"; end
            3'd1:    begin {zc0,zc1,zc2,zc3,zc4} = "0.33x"; end
            3'd2:    begin {zc0,zc1,zc2,zc3,zc4} = "0.50x"; end
            3'd3:    begin {zc0,zc1,zc2,zc3,zc4} = "0.75x"; end
            3'd5:    begin {zc0,zc1,zc2,zc3,zc4} = "1.33x"; end
            3'd6:    begin {zc0,zc1,zc2,zc3,zc4} = "1.50x"; end
            3'd7:    begin {zc0,zc1,zc2,zc3,zc4} = "2.00x"; end
            // 4 = 1.00x。default 也走它而不是空白：号只有三 bit，
            // 没点出来的那一支就是 4，省一格 case 深度。
            default: begin {zc0,zc1,zc2,zc3,zc4} = "1.00x"; end
        endcase
    end

    // 分辨率那一格没有单独的换算线：`putnum(IMG_W)` / `putnum(IMG_H)` 的参数是 elaboration
    // 常数，综合直接把十进制位折成接线（台架 T11 换一个参数例化第二份，验证它画的是实参）。

    // ---- Latency 的百位/余数分一拍算，十位个位从余数里取（同 V7.6 的 STALL 那一招）----
    // 一次算三位在 50 MHz 像素域是二十几级组合链，V7.6 第一次上这条链时 WNS 是 −6.765；
    // 拆成"百位/余数"一拍、"十位/个位"再一拍，每段都只剩十来级。
    // 这个数一帧才变一次（甚至几帧一次），晚一拍对人眼没有任何影响，而 OSD 一像素都不该抖。
    wire [15:0] lat_v = (!lat_ok) ? 16'd0 : ((lat_ms > 16'd999) ? 16'd999 : lat_ms);
    reg  [3:0]  lt_h;
    reg  [7:0]  lt_rem;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin lt_h <= 4'd0; lt_rem <= 8'd0; end
        else begin
            lt_h   <= lat_v / 16'd100;         // 0..9（lat_v 已夹在 999 以内）
            lt_rem <= lat_v % 16'd100;         // 0..99
        end
    end

    // Fixed strings — no trailing junk
    reg [7:0] chars [0:N_LINES*MAX_CHARS-1];
    integer i, col, ti;

    // ---- 排版：一行一行"打字符"，数字按实际位数打 ----
    // 为什么不按固定格：用户的四行写的是 `Th:80`、`Split:50%`、`Rot:45°`，
    // 固定三位右对齐就会打出 `Th:080` / `Split: 50%`（多出来的空格在屏上是实打实的空位）。
    // 代价是"某一格在第几列"不再是常数 ⇒ 判据（tb_osd_lines）也按**整串比对**来写，
    // 反而比原来逐格点对更不容易被"整体挪一格"糊过去。
    task at;  input integer ln;  begin col = ln * MAX_CHARS; end endtask
    task put; input [7:0] c;
        begin
            if (col < N_LINES*MAX_CHARS) chars[col] = c;
            col = col + 1;
        end
    endtask
    task puts; input [8*12-1:0] s; input integer n;
        begin
            for (ti = 0; ti < n; ti = ti + 1)
                put(s[(n-1-ti)*8 +: 8]);
        end
    endtask
    // 百十个三个数字，**前导零不打**；三位都是 0 时打一个 "0"（0 也是一个要看的数）。
    task putd3; input [3:0] h, t, o;
        begin
            if (h != 4'd0) put(dig(h));
            if (h != 4'd0 || t != 4'd0) put(dig(t));
            put(dig(o));
        end
    endtask
    task putnum; input [9:0] v;
        begin
            putd3(v / 10'd100, (v / 10'd10) % 10'd10, v % 10'd10);
        end
    endtask

    // ---- 片源那一格：名字**按实际长度**打，锁住的 `*` 紧跟其后（不锁就不占格）----
    // 画的是屏幕上真的这一路（src_eff），不是模式环：这是 r48 的教训（ISSUES #55）。
    // 定宽字段会让 "ETH" 后面空两格、"CARD" 后面空零格，屏上的间隔看着一跳一跳。
    // ⚠ **为什么这两个信号是任务入参而不是任务里直接读**：Verilog-2001 的 `always @(*)`
    //   只把"这个块自己读到的信号"放进敏感表，**任务体内读的信号不算** ⇒ 直接读的话
    //   切片源时这个块根本不会被叫醒，屏上会永远留着上一次的名字。
    //   （台架 T3 第一次跑就抓到：src_eff 已经变成 CARD，chars 里还写着 PS。）
    // `Src:` 画的仍然是"屏幕上真的这一路"（`src_eff`），意愿只用末尾一个 `*` 表示。
    // 这条是 r48 的教训（ISSUES #55）：照着"想要哪一路"画标签，屏幕与标签就会在
    // "意愿没生效"的那些状态下对不上 —— 用户报的"显示 ETH 时写 AUTO"就是这个。
    //
    // ⚠ 用词经过两轮：2026-09-25 上午用户先说"card 对应的是图卡、eth 对应的是 sd 卡"（那时屏上是
    //   CARD=图卡 / PS=SD），我按他的读法换成 CARD=SD 回放 / PS=片内图卡；同一轮他坐在屏幕前
    //   又看了三遍，最后一句话定稿：**`ETH` / `SD` / `TEST`**（2026-09-25 上午 r58 内）。
    //   这三个词不再有任何一侧的歧义 —— CARD 这个词在板子上同时被念作"SD 卡"和"测试图卡"，
    //   而 PS 既指处理器也指"片内自绘"，所以两个都退出屏上文案。
    //   ⇒ 谁以后翻 ISSUES #55/#66 看到"CARD/PS 反了"那几句，别照旧文案改回去：
    //     那两条讲的是**标签必须跟着屏幕走**（这一条永远有效），用哪三个词是用户的决定。
    //   位序 `{fb_vis, owner_eth}` 与所有状态一个没动，改的只有"这一状态印哪个词"。
    //   字模不需要新增：S / D / T / E 早就在 ROM 里（"FPS"、"CARD"、"ETH" 用过）。
    task put_src;
        input [1:0] se;
        input [1:0] md;
        begin
            case (se)
                2'b11:   puts("ETH",  3);
                2'b10:   puts("SD",   2);
                default: puts("TEST", 4);
            endcase
            if (md != 2'b00) put("*");
        end
    endtask

    always @(*) begin
        for (i = 0; i < N_LINES*MAX_CHARS; i = i + 1)
            chars[i] = 8'h20;

        // ---------- L0: FPS:30  Src:ETH  512x300 ----------
        at(0);
        puts("FPS:", 4);
        putnum(fps_v);
        puts("  Src:", 6);
        put_src(src_eff, mode);
        puts("  ", 2);
        putnum(IMG_W);                 // 参数是 elaboration 常数 ⇒ 综合折成接线
        put("x");
        putnum(IMG_H);

        // ---------- L1: Pipe:11000 Th:80 Gamma:1.8 ----------
        // 2026-09-25 用户报"这一行跑到分界线那边去了"：字格宽 5 px × SCALE 3 = 15 px、格距 18 px，
        // 而左半窗只有 512 px ⇒ 一行最多 28 格就贴到线（`Pipe:11000  Th:80  Gamma:1.8` 恰好 28 格）。
        // 所以这一行的两个分隔从双空格收成单空格（28→26 格 ≈ 468 px，留出 44 px 余量）。
        // 这是**对用户原话格式的第四处有意偏差**（前三处见 CONTEST_CHECKLIST 的偏差清单）：
        // 字段、顺序、值一个没动，只动空格的个数。判据在 tb_osd_lines：
        // 它既比整串，也比"每行最右一个非空格的 x 必须 < PANE_W"。
        at(1);
        puts("Pipe:", 5);
        put(pc1); put(pc2); put(pc3); put(pc4); put(pc5);
        puts(" Th:", 4);
        putnum(threshold);
        puts(" Gamma:", 7);
        putnum(gamma_disp / 6'd10);
        put(".");
        put(dig(gamma_disp % 6'd10));

        // ---------- L2: Rot:45°  Zoom:0.75x(Auto) ----------
        at(2);
        puts("Rot:", 4);
        putnum(angle);                 // angle_ctrl 里就是十进制度数 0..359，不用换算
        put(8'hDF);                    // '°'（Latin-1 的度数符号）
        puts("  Zoom:", 7);
        put(zc0); put(zc1); put(zc2); put(zc3); put(zc4);
        if (zoom_auto) puts("(Auto)", 6);

        // ---------- L3: Split:50%(Auto)  Latency:16ms ----------
        at(3);
        puts("Split:", 6);
        putnum(split_pct);
        put("%");
        if (split_auto) puts("(Auto)", 6);
        puts("  Latency:", 10);
        if (!lat_ok) puts("--", 2);              // 没有可信测量 ⇒ 两条短线，不画数
        else putd3(lt_h, (lt_rem / 8'd10), (lt_rem % 8'd10));
        puts("ms", 2);
    end

    // 5x7 font。索引 0..27 是 V7 / V8 前三步用过的号（**历史插入序，不是字母序**），
    // `tb_v794_osd_glyph` 的金表钉的就是那一段 ⇒ V8-5 的新字一律接在 28 之后，不回头改已用的。
    // 31 原来是空格，现在空格在 63（31 不再被任何码点使用，位图留全 0）。
    reg [4:0] font [0:63][0:6];
    integer fi, fj;
    initial begin
        for (fi = 0; fi < 64; fi = fi + 1)
            for (fj = 0; fj < 7; fj = fj + 1)
                font[fi][fj] = 5'b00000;

        // 0-9
        // U / H：ISSUES #55 那行新 OSD 文字要用的两个字，老字库里没有（不是简写掉了，是真的没画）
        font[23][0]=5'b10001; font[23][1]=5'b10001; font[23][2]=5'b10001;
        font[23][3]=5'b10001; font[23][4]=5'b10001; font[23][5]=5'b10011; font[23][6]=5'b01110;  // U
        font[25][0]=5'b10001; font[25][1]=5'b10001; font[25][2]=5'b10001;
        font[25][3]=5'b11111; font[25][4]=5'b10001; font[25][5]=5'b10001; font[25][6]=5'b10001;  // H

        font[0][0]=5'b01110; font[0][1]=5'b10001; font[0][2]=5'b10011;
        font[0][3]=5'b10101; font[0][4]=5'b11001; font[0][5]=5'b10001; font[0][6]=5'b01110;
        font[1][0]=5'b00100; font[1][1]=5'b01100; font[1][2]=5'b00100;
        font[1][3]=5'b00100; font[1][4]=5'b00100; font[1][5]=5'b00100; font[1][6]=5'b01110;
        font[2][0]=5'b01110; font[2][1]=5'b10001; font[2][2]=5'b00001;
        font[2][3]=5'b00110; font[2][4]=5'b01000; font[2][5]=5'b10000; font[2][6]=5'b11111;
        font[3][0]=5'b11111; font[3][1]=5'b00010; font[3][2]=5'b01000;
        font[3][3]=5'b00001; font[3][4]=5'b00001; font[3][5]=5'b10001; font[3][6]=5'b01110;
        font[4][0]=5'b00010; font[4][1]=5'b00110; font[4][2]=5'b01010;
        font[4][3]=5'b10010; font[4][4]=5'b11111; font[4][5]=5'b00010; font[4][6]=5'b00010;
        font[5][0]=5'b11111; font[5][1]=5'b10000; font[5][2]=5'b11110;
        font[5][3]=5'b00001; font[5][4]=5'b00001; font[5][5]=5'b10001; font[5][6]=5'b01110;
        font[6][0]=5'b00110; font[6][1]=5'b01000; font[6][2]=5'b10000;
        font[6][3]=5'b11110; font[6][4]=5'b10001; font[6][5]=5'b10001; font[6][6]=5'b01110;
        font[7][0]=5'b11111; font[7][1]=5'b00001; font[7][2]=5'b00010;
        font[7][3]=5'b01000; font[7][4]=5'b01000; font[7][5]=5'b01000; font[7][6]=5'b01000;
        font[8][0]=5'b01110; font[8][1]=5'b10001; font[8][2]=5'b10001;
        font[8][3]=5'b01110; font[8][4]=5'b10001; font[8][5]=5'b10001; font[8][6]=5'b01110;
        font[9][0]=5'b01110; font[9][1]=5'b10001; font[9][2]=5'b10001;
        font[9][3]=5'b01111; font[9][4]=5'b00001; font[9][5]=5'b00010; font[9][6]=5'b01100;
        // A=10 B=11 C=12 D=13 E=14 F=15
        font[10][0]=5'b01110; font[10][1]=5'b10001; font[10][2]=5'b10001;
        font[10][3]=5'b11111; font[10][4]=5'b10001; font[10][5]=5'b10001; font[10][6]=5'b10001;
        font[11][0]=5'b11110; font[11][1]=5'b10001; font[11][2]=5'b10001;
        font[11][3]=5'b11110; font[11][4]=5'b10001; font[11][5]=5'b10001; font[11][6]=5'b11110;
        font[12][0]=5'b01110; font[12][1]=5'b10001; font[12][2]=5'b10000;
        font[12][3]=5'b10000; font[12][4]=5'b10000; font[12][5]=5'b10001; font[12][6]=5'b01110;
        font[13][0]=5'b11110; font[13][1]=5'b10001; font[13][2]=5'b10001;
        font[13][3]=5'b10001; font[13][4]=5'b10001; font[13][5]=5'b10001; font[13][6]=5'b11110;
        font[14][0]=5'b11111; font[14][1]=5'b10000; font[14][2]=5'b10000;
        font[14][3]=5'b11110; font[14][4]=5'b10000; font[14][5]=5'b10000; font[14][6]=5'b11111;
        font[15][0]=5'b11111; font[15][1]=5'b10000; font[15][2]=5'b10000;
        font[15][3]=5'b11110; font[15][4]=5'b10000; font[15][5]=5'b10000; font[15][6]=5'b10000;
        // G=16 N=20 P=22 S=24 = 27
        font[16][0]=5'b01110; font[16][1]=5'b10001; font[16][2]=5'b10000;
        font[16][3]=5'b10111; font[16][4]=5'b10001; font[16][5]=5'b10001; font[16][6]=5'b01110;
        // v7.6 新增：R=17 O=18 T=19 L=21（老 DROP / STALL 两行用的号，留着不动）
        font[17][0]=5'b11110; font[17][1]=5'b10001; font[17][2]=5'b10001;
        font[17][3]=5'b11110; font[17][4]=5'b10100; font[17][5]=5'b10010; font[17][6]=5'b10001;
        font[18][0]=5'b01110; font[18][1]=5'b10001; font[18][2]=5'b10001;
        font[18][3]=5'b10001; font[18][4]=5'b10001; font[18][5]=5'b10001; font[18][6]=5'b01110;
        font[19][0]=5'b11111; font[19][1]=5'b00100; font[19][2]=5'b00100;
        font[19][3]=5'b00100; font[19][4]=5'b00100; font[19][5]=5'b00100; font[19][6]=5'b00100;
        font[21][0]=5'b10000; font[21][1]=5'b10000; font[21][2]=5'b10000;
        font[21][3]=5'b10000; font[21][4]=5'b10000; font[21][5]=5'b10000; font[21][6]=5'b11111;
        font[20][0]=5'b10001; font[20][1]=5'b11001; font[20][2]=5'b10101;
        font[20][3]=5'b10101; font[20][4]=5'b10011; font[20][5]=5'b10001; font[20][6]=5'b10001;
        font[22][0]=5'b11110; font[22][1]=5'b10001; font[22][2]=5'b10001;
        font[22][3]=5'b11110; font[22][4]=5'b10000; font[22][5]=5'b10000; font[22][6]=5'b10000;
        font[24][0]=5'b01111; font[24][1]=5'b10000; font[24][2]=5'b10000;
        font[24][3]=5'b01110; font[24][4]=5'b00001; font[24][5]=5'b00001; font[24][6]=5'b11110;
        font[27][0]=5'b00000; font[27][1]=5'b00000; font[27][2]=5'b11111;
        font[27][3]=5'b00000; font[27][4]=5'b11111; font[27][5]=5'b00000; font[27][6]=5'b00000;
        // 26 = '*'：片源行用它标"这是手动锁住的"（模式≠自动）
        font[26][0]=5'b00000; font[26][1]=5'b00100; font[26][2]=5'b10101;
        font[26][3]=5'b01110; font[26][4]=5'b10101; font[26][5]=5'b00100; font[26][6]=5'b00000;
        // ============ V8-5 新增：15 个小写 + 5 个符号 + 大写 Z + 小写 h + 短线 ============
        // 位图与 `build/glyphs_draft.txt` 那份草稿逐项一致；台架 tb_osd_lines 里
        // **另抄一遍**同一批位图当反例源（谁改了另一处就红，同 GL_U/GL_H 的老做法）。
        font[28][0]=5'b00000; font[28][1]=5'b00000; font[28][2]=5'b01110;
        font[28][3]=5'b00001; font[28][4]=5'b01111; font[28][5]=5'b10001; font[28][6]=5'b01111; // a
        font[29][0]=5'b00000; font[29][1]=5'b00000; font[29][2]=5'b01110;
        // c：右边**整列不能出现**（原来 row3 与 row5 都画了右列 ⇒ 看着就是 o，用户报的
        //     "Src 像 Sro" 就是这个字；2026-09-25 重画，金表在 tb_v794 按字母定义独立给）
        font[29][3]=5'b10000; font[29][4]=5'b10000; font[29][5]=5'b10000; font[29][6]=5'b01111; // c
        font[30][0]=5'b00000; font[30][1]=5'b00000; font[30][2]=5'b01110;
        font[30][3]=5'b10001; font[30][4]=5'b11111; font[30][5]=5'b10000; font[30][6]=5'b01110; // e
        font[32][0]=5'b01100; font[32][1]=5'b00000; font[32][2]=5'b01100;
        font[32][3]=5'b00100; font[32][4]=5'b00100; font[32][5]=5'b00100; font[32][6]=5'b01110; // i
        font[33][0]=5'b01100; font[33][1]=5'b01000; font[33][2]=5'b01000;
        font[33][3]=5'b01000; font[33][4]=5'b01000; font[33][5]=5'b01000; font[33][6]=5'b01110; // l
        font[34][0]=5'b00000; font[34][1]=5'b00000; font[34][2]=5'b11110;
        font[34][3]=5'b10101; font[34][4]=5'b10101; font[34][5]=5'b10101; font[34][6]=5'b10101; // m
        font[35][0]=5'b00000; font[35][1]=5'b00000; font[35][2]=5'b11110;
        font[35][3]=5'b10001; font[35][4]=5'b10001; font[35][5]=5'b10001; font[35][6]=5'b10001; // n
        font[36][0]=5'b00000; font[36][1]=5'b00000; font[36][2]=5'b01110;
        font[36][3]=5'b10001; font[36][4]=5'b10001; font[36][5]=5'b10001; font[36][6]=5'b01110; // o
        // p：左列必须**从上到下贯通**（含基线下面那一行才是降部），碗只长在右边。
        //     原来 row2 是 01110（左列空）⇒ 整字看着像 o 加了个尾巴，用户报的"Split 像 Solit"。
        font[37][0]=5'b00000; font[37][1]=5'b00000; font[37][2]=5'b10110;
        font[37][3]=5'b10001; font[37][4]=5'b10001; font[37][5]=5'b10110; font[37][6]=5'b10000; // p
        font[38][0]=5'b00000; font[38][1]=5'b00000; font[38][2]=5'b10110;
        font[38][3]=5'b11001; font[38][4]=5'b10000; font[38][5]=5'b10000; font[38][6]=5'b10000; // r
        font[39][0]=5'b00000; font[39][1]=5'b00000; font[39][2]=5'b01111;
        font[39][3]=5'b10000; font[39][4]=5'b01110; font[39][5]=5'b00001; font[39][6]=5'b11110; // s
        font[40][0]=5'b01000; font[40][1]=5'b01000; font[40][2]=5'b11110;
        font[40][3]=5'b01000; font[40][4]=5'b01000; font[40][5]=5'b01001; font[40][6]=5'b00110; // t
        font[41][0]=5'b00000; font[41][1]=5'b00000; font[41][2]=5'b10001;
        font[41][3]=5'b10001; font[41][4]=5'b10001; font[41][5]=5'b10011; font[41][6]=5'b01101; // u
        font[42][0]=5'b00000; font[42][1]=5'b00000; font[42][2]=5'b10001;
        font[42][3]=5'b01010; font[42][4]=5'b00100; font[42][5]=5'b01010; font[42][6]=5'b10001; // x
        font[43][0]=5'b00000; font[43][1]=5'b00000; font[43][2]=5'b10001;
        font[43][3]=5'b10001; font[43][4]=5'b10011; font[43][5]=5'b01110; font[43][6]=5'b10000; // y
        font[44][0]=5'b00000; font[44][1]=5'b00110; font[44][2]=5'b00110;
        font[44][3]=5'b00000; font[44][4]=5'b00110; font[44][5]=5'b00110; font[44][6]=5'b00000; // :
        font[45][0]=5'b00000; font[45][1]=5'b00000; font[45][2]=5'b00000;
        font[45][3]=5'b00000; font[45][4]=5'b00000; font[45][5]=5'b00110; font[45][6]=5'b00110; // .
        font[46][0]=5'b11000; font[46][1]=5'b11001; font[46][2]=5'b00010;
        font[46][3]=5'b00100; font[46][4]=5'b01000; font[46][5]=5'b10011; font[46][6]=5'b00011; // %
        font[47][0]=5'b00010; font[47][1]=5'b00100; font[47][2]=5'b01000;
        font[47][3]=5'b01000; font[47][4]=5'b01000; font[47][5]=5'b00100; font[47][6]=5'b00010; // (
        font[48][0]=5'b01000; font[48][1]=5'b00100; font[48][2]=5'b00010;
        font[48][3]=5'b00010; font[48][4]=5'b00010; font[48][5]=5'b00100; font[48][6]=5'b01000; // )
        font[49][0]=5'b01100; font[49][1]=5'b10010; font[49][2]=5'b10010;
        font[49][3]=5'b01100; font[49][4]=5'b00000; font[49][5]=5'b00000; font[49][6]=5'b00000; // °
        font[50][0]=5'b11111; font[50][1]=5'b00001; font[50][2]=5'b00010;
        font[50][3]=5'b00100; font[50][4]=5'b01000; font[50][5]=5'b10000; font[50][6]=5'b11111; // Z
        font[51][0]=5'b10000; font[51][1]=5'b10000; font[51][2]=5'b10110;
        font[51][3]=5'b11001; font[51][4]=5'b10001; font[51][5]=5'b10001; font[51][6]=5'b10001; // h
        font[52][0]=5'b00000; font[52][1]=5'b00000; font[52][2]=5'b00000;
        font[52][3]=5'b11111; font[52][4]=5'b00000; font[52][5]=5'b00000; font[52][6]=5'b00000; // -
        // 63 = 空格（全 0，由开头的循环清好）
    end

    // 字码 → 字形号。**故意写成 case 而不是 if/else 区间比较**（V7.9.4 / 时序深度优化）：
    // 原来那串 `c >= 0x30 && c <= 0x39` 之类是**串行优先级链**，每个区间比较还要一次减法，
    // 它们和同一拍里的 `line*MAX_CHARS+cidx`、`font[gi][fy]` 串成一条 27 级、CARRY4=10 的链，
    // 就是 L3 报告里 `x_d_reg[11]→b_reg` 这条全设计最差路径的主体。
    // case 的码点是**并行**译码（真值表与逐项金表由 `tb_v794_osd_glyph` 差分钉住），
    // 表里没有的码点仍然落到 63=空格 —— 语义一字未改，只是不再串行。
    function [5:0] glyph_idx;
        input [7:0] c;
        begin
            case (c)
                8'h30: glyph_idx = 6'd0;   8'h31: glyph_idx = 6'd1;
                8'h32: glyph_idx = 6'd2;   8'h33: glyph_idx = 6'd3;
                8'h34: glyph_idx = 6'd4;   8'h35: glyph_idx = 6'd5;
                8'h36: glyph_idx = 6'd6;   8'h37: glyph_idx = 6'd7;
                8'h38: glyph_idx = 6'd8;   8'h39: glyph_idx = 6'd9;
                8'h41: glyph_idx = 6'd10;  8'h42: glyph_idx = 6'd11;
                8'h43: glyph_idx = 6'd12;  8'h44: glyph_idx = 6'd13;
                8'h45: glyph_idx = 6'd14;  8'h46: glyph_idx = 6'd15;
                8'h47: glyph_idx = 6'd16;  // G
                8'h4C: glyph_idx = 6'd21;  // L
                8'h4E: glyph_idx = 6'd20;  // N
                8'h4F: glyph_idx = 6'd18;  // O
                8'h50: glyph_idx = 6'd22;  // P
                8'h52: glyph_idx = 6'd17;  // R
                8'h53: glyph_idx = 6'd24;  // S
                8'h54: glyph_idx = 6'd19;  // T
                8'h55: glyph_idx = 6'd23;  // U（AUTO 要用；以前字库里没有 U）
                8'h48: glyph_idx = 6'd25;  // H（ETH 要用；以前字库里也没有）
                8'h5A: glyph_idx = 6'd50;  // Z（Zoom 要用，V8-5 新画）
                8'h2A: glyph_idx = 6'd26;  // *（手动锁片源的标记）
                8'h3D: glyph_idx = 6'd27;  // =
                8'h3A: glyph_idx = 6'd44;  // :（四行的分隔符；老 OSD 从头到尾没用过冒号）
                8'h2E: glyph_idx = 6'd45;  // .
                8'h25: glyph_idx = 6'd46;  // %
                8'h28: glyph_idx = 6'd47;  // (
                8'h29: glyph_idx = 6'd48;  // )
                8'hDF: glyph_idx = 6'd49;  // °（Latin-1 度数符号）
                8'h2D: glyph_idx = 6'd52;  // -（Latency 没有可信测量时画 `--`）
                8'h61: glyph_idx = 6'd28;  8'h63: glyph_idx = 6'd29;
                8'h65: glyph_idx = 6'd30;  8'h68: glyph_idx = 6'd51;
                8'h69: glyph_idx = 6'd32;  8'h6C: glyph_idx = 6'd33;
                8'h6D: glyph_idx = 6'd34;  8'h6E: glyph_idx = 6'd35;
                8'h6F: glyph_idx = 6'd36;  8'h70: glyph_idx = 6'd37;
                8'h72: glyph_idx = 6'd38;  8'h73: glyph_idx = 6'd39;
                8'h74: glyph_idx = 6'd40;  8'h75: glyph_idx = 6'd41;
                8'h78: glyph_idx = 6'd42;  8'h79: glyph_idx = 6'd43;
                default: glyph_idx = 6'd63; // BLANK（空格以及一切不在表里的码点）
            endcase
        end
    endfunction

    wire [7:0] ch = chars[line*MAX_CHARS + cidx];
    wire [5:0] gi = glyph_idx(ch);
    wire [2:0] fx = pix_x / SCALE;
    wire [2:0] fy = (pix_y < 7*SCALE) ? (pix_y / SCALE) : 3'd6;
    wire [4:0] font_row = font[gi][fy];
    wire pixel_on = in_char && (fx < 5) && (font_row[4-fx] == 1'b1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r <= 0; g <= 0; b <= 0;
            de_out <= 0; hs_out <= 0; vs_out <= 0;
        end else begin
            de_out <= de;
            hs_out <= hs_in;
            vs_out <= vs_in;
            if (pixel_on) begin
                r <= 8'hFF; g <= 8'h00; b <= 8'h90; // rose
            end else begin
                r <= r_in; g <= g_in; b <= b_in;
            end
        end
    end
endmodule
