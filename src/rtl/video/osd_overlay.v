`timescale 1ns/1ps
// OSD 五行（格式的底子是用户 2026-09-24 亲给的四行原话，屏上现在长这样）：
//
//   1024X600  FPS:30  SRC:ETH
//   PIPE:11000 TH:80 GAMMA:1.8
//   ROT:45°  ZOOM:0.75X(AUTO)
//   SPLIT:50%(AUTO)  LATENCY:16MS
//   TEMP:47C  ETH IS NO SIGNAL
//
// 对用户原话的偏差一共五处，全部有理由、全部由 `tb_osd_lines` 钉住：字段、顺序、值域一个没动，
// 前四处只动空格的个数（第二行压线是为了不越过分割线），第五处是 #67：
// **屏上一律大写**（17 个小写字模在这个字号下画不出可认的字形，用户 2026-09-26 原话
// "特别是字母 p 弄得很丑 ⇒ 全部改成大写"），以及尺寸那一格从"片源 512×300"改成"面板 1024×600"
// 并挪到行首（详见下面 L0 那段）。大小写折算在 `put` 里做，不在 `glyph_idx` 那条链上加逻辑。
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
    // V9-4：第 5 行只有一件事 —— 没有 ETH 信号时印 "ETH is no signal"（用户 2026-09-25 指定的
    // 那半句话），其余时间整行是空格、屏幕上看不见多出来的一行。为什么开第 5 行而不是塞进
    // 前四行：那四行的格式是用户亲给的，字段、顺序、空格都动不得；而这一句必须完整可读，
    // 塞进 L0 尾巴会在 "Src:ETH 512x300" 之后贴边（32 格早就用满）。
    // 高度账：5×(21+10) = 155 px < 600 ✓，字格尺寸一个都没动。
    parameter N_LINES = 5,
    // #67：第一行那一格画的是**面板**尺寸，不再画片源的 512×300。
    // 为什么改：r59b 之后左右两半已经合成一整屏，屏上看到的就是一整幅 1024×600；
    // 而旧写法紧跟在 `Src:` 后面，读起来像"片源是 512×300 而画面只占半屏"——两个都不是真的。
    // ⚠ 顶层递进来的是**面板**那一份（`2*IMG_W` / `2*IMG_H` —— 与本文件里 `proc_pipeline.H_ACTIVE`、
    //   `raw_line_delay.W` 用的是同一个 ×2 关系），不是片源尺寸：屏上画的数与真实扫描的列/行数同源。
    parameter OUT_W = 1024,
    parameter OUT_H = 600
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        de,
    // ---- 四行的数据来源。规矩：**每一个都必须在 PLAN §7d 的表里**，不在表里的不许上屏 ----
    input  wire [8:0]  angle,        // 度（0..359：angle_ctrl 里就是十进制度数，不用换算）
    input  wire [7:0]  fps,          // fps_q
    input  wire [8:0]  stage_sel,    // 五级链实际生效的九位（effect_ctrl 同步到本域的那一个口）
    input  wire [7:0]  threshold,    // 二值化阈值
    input  wire [5:0]  gamma_disp,   // gamma×10，PS 写 LUT 时同一个字顺路带过来，只用于显示
    input  wire [2:0]  zoom_code,    // zoom_ctrl 的"最近一档"号（八档表在它那边）
    input  wire        zoom_auto,    // 1 = 呼吸缩放正在跑 ⇒ Zoom 后面加 (Auto)
    input  wire        zoom_fit,     // V9-2：1 = 倍率由角度定 ⇒ 加 (Fit)，并且不再叠 (Auto)
    input  wire [7:0]  split_pct,    // 见文件头：现在来自几何参数
    input  wire        split_auto,   // 1 = 缝在自动扫描 ⇒ (Auto)
    input  wire [15:0] lat_ms,       // 链路内时延（ms），axi 域除完再过 snap_cross
    input  wire        lat_ok,       // 0 ⇒ 没有可信测量，画 `--`
    input  wire [1:0]  src_eff,      // {fb_vis, owner_eth}：屏幕上真的这一路
    input  wire [1:0]  mode,         // 00 自动 01 ETH 11 SD 10 TEST（与 src_mode 同序；`*` 由它派生）
    // V9-4：ETH 那一路"该有画面却没有"——顶层判的是"屏上挂的是 ETH 帧、但 200 ms 没等到新帧"。
    // 用户的原话：「现在没有 ETH 的时候，如果接到 ETH 信号，它仍然是锁住上一帧的画面」⇒
    // 不许只是悄悄冻着，要在屏上说清楚（他选的方案就是"打印一条 ETH is no signal"）。
    input  wire        no_sig,
    // V9-6：片上温度（PS 侧 XADC）。两位**十进制 BCD**（[7:4]=十位、[3:0]=个位），
    //   任何一个半字节 >9 就是"还没有可信读数"⇒ 画 `--`（与 `lat_ok=0` 同一规矩）。
    //   为什么 PS 就把十进制算好了再传：这个 always 块是**一整块组合逻辑**，而
    //   `u_pipe/xd_reg[7][4] → u_osd/g_reg[6]/D`（27 级）正是 clkout0_1 那一组的 WNS 路径
    //   （r63b/r63c/r64b 三份 timing_summary 都指着它）⇒ 这里再加一次 /100+/10 是往
    //   全设计最差的链上加深度。先例：Latency 那一格从 #59 起就是"换算在 axi 域做完再跨"。
    //   量程与诚实：这一格只画 0..99 °C；越界与读不到都画 `--`，完整读数在串口 `temp`。
    input  wire [7:0]  temp_disp,
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

    // ====== #96 时序专项：把"字格几何"这一级算完就**寄存一拍** ======
    // r74 的 `build/timing_summary.rpt` 里全设计最差那条是
    // `u_pl/x_d_reg[20][4] → u_pl/u_osd/b_reg[4]/D`，**29 级、9 个 CARRY4**、slack 只剩 0.549 ns。
    // 那 9 个 CARRY4 不是字形译码（R25 那次已经把它并行化了），而是这里的**格子换算**：
    // `ly / 31`、`lx / 18`、`lx % 18` 三个除/模（LINE_H 与 CHAR_W 都不是 2 的幂）——
    // 它们原本和"取字符 → 查字形 → 选位图行 → 上色"串在同一拍里，一条链上既有减法又有查表。
    // 拆法只有一处聪明可言：**把减法那一半挪到前一拍**（输入是 `x_d/y_d` 的寄存器，本来就是给这一拍用的），
    // 背景像素 `r_in/g_in/b_in` 与 `de/hs/vs` 跟着**同样晚一拍** ⇒ 内容与坐标仍然同一拍，
    // 整个模块的输出延迟从 1 拍变 2 拍，而这一拍对面板不可见（所有下游都吃这一份输出）。
    // 为什么不该改成"提前算好整行"：那要把 32 格一次算出来，硬件从 1 个乘法器变成一整排，
    // 而本项目最差的一条链缺的是**深度**不是吞吐（同一件事的先例见 Latency 那一格：换算挪地方，不挪数据量）。
    reg [2:0] s_line;
    reg [7:0] s_pix_y;
    reg [4:0] s_cidx;
    reg [7:0] s_pix_x;
    reg       s_in_char;
    reg [7:0] s_r, s_g, s_b;
    reg       s_de, s_hs, s_vs;

    wire        in_box = de && (x >= X0) && (x < X0 + BOX_W) &&
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

    always @(posedge clk) begin
        s_line    <= line;
        s_pix_y   <= pix_y;
        s_cidx    <= cidx;
        s_pix_x   <= pix_x;
        s_in_char <= in_char;
        s_r <= r_in;  s_g <= g_in;  s_b <= b_in;
        s_de <= de;   s_hs <= hs_in; s_vs <= vs_in;
    end

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

    // 尺寸那一格没有单独的换算线：`putnum4(OUT_W)` / `putnum4(OUT_H)` 的参数是 elaboration
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
    // ⚠ **屏上没有小写**（#67）：字库里那 17 个小写字模全部退役，`glyph_idx` 也不再认 0x61~0x7A。
    //   折大小写这件事放在**写这一侧**而不是读那一侧，是因为读侧那条 `ch→gi→font→b_reg`
    //   正是全设计最差路径的主体（本文件下面那段 27 级的注释）；在这里折一次是一句比较 + 一次减法，
    //   而它换来的是译码表少 17 个分支。写了小写字面量也不会漏出洞：折完再进格子里。
    task put; input [7:0] c;
        reg [7:0] u;
        begin
            u = c;
            if (u >= 8'h61 && u <= 8'h7A) u = u - 8'h20;
            if (col < N_LINES*MAX_CHARS) chars[col] = u;
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
    // 四位数：只给**面板宽高**用（`OUT_W/OUT_H` 是 elaboration 常数 ⇒ /1000 折成接线）。
    // ⚠ 不许拿它打运行时数值：16 位除以 1000 就是二十几级链，而 OSD 的读侧正是全设计最差那条路径；
    //   要显示新的运行时数值请照 `lat_v` 那一招分拍算（上面 Latency 的注释）。
    // 千位打出来之后三位**不省前导零**（`1024` 打成 1,0,2,4；`putd3` 那种省略只适用于最低那一位）。
    task putnum4; input [15:0] v;
        reg [3:0] th;
        reg [9:0] rem;
        begin
            th  = v / 16'd1000;
            rem = v % 16'd1000;
            if (th == 4'd0) putnum(rem);
            else begin
                put(dig(th));
                put(dig(rem / 10'd100));
                put(dig((rem / 10'd10) % 10'd10));
                put(dig(rem % 10'd10));
            end
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

        // ---------- L0: 1024X600  FPS:30  SRC:ETH ----------
        // #67 的两处改动都在这五行里：
        //   ① 画**面板**尺寸（旧版画片源的 512×300，而且紧跟 `Src:` 后面，读起来像"片源只有半屏"）；
        //   ② 尺寸放在**行首**：这样它不再被读成 `SRC:` 的定语，最宽一格（TEST*）27 字符
        //      ⇒ 右沿 16+27*18 = 502 ≤ 511，仍然整行落在分割线左边（判据 tb_osd_lines T13a）。
        //   ③ 全大写：`x` 这个分隔符因此换成了大写 X（新字模 56）—— 小写字模这一族整个退役。
        at(0);
        putnum4(OUT_W);
        put("X");
        putnum4(OUT_H);
        puts("  FPS:", 6);
        putnum(fps_v);
        puts("  SRC:", 6);
        put_src(src_eff, mode);

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
        // (Fit) 与 (Auto) 互斥：同时开两个后缀那一格就 32 格溢到下一行去了（`put` 会
        // 直接写进 L3 的格子里），而且"呼吸"与"按角度定"本来就不可能同时成立。
        if (zoom_fit)       puts("(Fit)", 5);
        else if (zoom_auto) puts("(Auto)", 6);

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

        // ---------- L4：V9-4 开这一行，现在它常驻"片上温度"，ETH 那一句跟在后面 ----------
        // 为什么温度落在这一行而不是 L1（gamma 旁边）：上面四行的字段、顺序、空格是用户
        //   2026-09-24 亲给的，V8-5 的偏差清单只允许改空格数；而这一行本来就是"要告诉用户的话"
        //   开的。最宽激励 `Temp:47C  ETH is no signal` = 26 格 ⇒ 右沿 16+26*18 = 484 < 511，
        //   温度与异常句并存也不压到分割线（判据 tb_osd_lines T13e）。
        // `no_sig` 的判据不变（顶层从 eth_live 推）：这一句仍然只在"屏上挂着 ETH 帧但没信号"时出现。
        // 为什么当初值得单独开这一行、今天为什么还留着：这条判据是**给用户看的**（拔了线/停了推流
        //   时画面会冻在最后一帧，没有这一句就会被当成"板子卡死"）。它的凭据不是眼睛：`eth_live`
        //   每一位都有台架（tb_link_monitor）与机器读回（lane0/lane2）。
        at(4);
        puts("Temp:", 5);
        // 两个半字节都是十进制数字才画数，否则画 `--` —— 与 `lat_ok=0` 同一规矩：
        //   不许把不成立的数画到屏上。上电时 effect_ctrl 那条链的复位值就是"非数字"，
        //   所以 PS app 起来之前这一格是 `Temp:--`，不是 `Temp:00C`（那是一条没人测过的数）。
        if ((temp_disp[7:4] <= 4'd9) && (temp_disp[3:0] <= 4'd9)) begin
            put(dig(temp_disp[7:4]));          // 十位
            put(dig(temp_disp[3:0]));          // 个位
            put("C");
        end else begin
            puts("--", 2);
        end
        if (no_sig) begin
            puts("  ETH is no ", 12);
            puts("signal", 6);
        end
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
        // ============ V8-5 新增的 5 个符号 + 大写 Z + 短线（小写那一族已在 #67 退役）============
        // 位图与 `build/glyphs_draft.txt` 那份草稿逐项一致；台架 tb_osd_lines 里
        // **另抄一遍**同一批位图当反例源（谁改了另一处就红，同 GL_U/GL_H 的老做法）。
        // 28~43 这一批原来是小写 a c e i l m n o p r s t u x y —— 用户 2026-09-26 的原话是
        // "小写字母搞出来有点奇怪，特别是 p 弄得很丑 ⇒ 全部改成大写"。字模只有 5×7，
        // 做不出真正的降部（p/q/y 那三个尤其明显：要么糊成一团、要么与基线不齐），
        // 所以这一族不是"画得不好"而是**这个字号画不出**⇒ 连同 `glyph_idx` 里那 17 个码点一起删掉，
        // 屏上从此只有大写。空洞留在表里不动号：`tb_v794` 的金表钉的是 0..27 那段历史号。
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
        font[52][0]=5'b00000; font[52][1]=5'b00000; font[52][2]=5'b00000;
        font[52][3]=5'b11111; font[52][4]=5'b00000; font[52][5]=5'b00000; font[52][6]=5'b00000; // -
        // ============ #67 新增的四个大写 ============
        // 为什么以前没有：那四个字母只以小写出现过（pipe/zoom/split/latency、以及尺寸里的 x），
        // 屏上从没有过它们的大写 ⇒ 字库里就真的没画（不是简写掉了，与上面 U/H 那两条同一种"真没画"）。
        // 号接在 53 之后照旧"只往后加、不回头改已用的号"（`tb_v794_osd_glyph` 钉的是 0..27 那段）。
        font[54][0]=5'b11111; font[54][1]=5'b00100; font[54][2]=5'b00100;
        font[54][3]=5'b00100; font[54][4]=5'b00100; font[54][5]=5'b00100; font[54][6]=5'b11111; // I
        font[55][0]=5'b10001; font[55][1]=5'b11011; font[55][2]=5'b10101;
        font[55][3]=5'b10101; font[55][4]=5'b10001; font[55][5]=5'b10001; font[55][6]=5'b10001; // M
        font[56][0]=5'b10001; font[56][1]=5'b10001; font[56][2]=5'b01010;
        font[56][3]=5'b00100; font[56][4]=5'b01010; font[56][5]=5'b10001; font[56][6]=5'b10001; // X
        font[57][0]=5'b10001; font[57][1]=5'b10001; font[57][2]=5'b01010;
        font[57][3]=5'b00100; font[57][4]=5'b00100; font[57][5]=5'b00100; font[57][6]=5'b00100; // Y
        // 63 = 空格（全 0，由开头的循环清好）
    end

    // 字码 → 字形号。**故意写成 case 而不是 if/else 区间比较**（V7.9.4 / 时序深度优化）：
    // 原来那串 `c >= 0x30 && c <= 0x39` 之类是**串行优先级链**，每个区间比较还要一次减法，
    // 它们和同一拍里的 `line*MAX_CHARS+cidx`、`font[gi][fy]` 串成一条 27 级、CARRY4=10 的链，
    // ⚠ #96 又把这条链**从中间切了一拍**（格子换算 `ly/31`、`lx/18`、`lx%18` 挪到前一拍寄存，
    //   背景像素与 de/hs/vs 跟着晚一拍）⇒ 读这一侧现在只剩"取字符 + 并行译码 + 选位图行"。
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
                // ============ #67：屏上不再有小写 ============
                // 原来这里挂着 17 个小写码点（0x61~0x7A），全部删掉 —— 小写字母进了 `put`
                // 就被折成大写，本域永远看不见它们。**这条链是全设计最差路径的主体**
                //（`ch→gi→font→b_reg`），少 17 个分支就是少那一侧的深度。
                8'h49: glyph_idx = 6'd54;  // I（PIPE / SPLIT / SIGNAL 都要，老字库里没有）
                8'h4D: glyph_idx = 6'd55;  // M（ZOOM）
                8'h58: glyph_idx = 6'd56;  // X（尺寸那一格的分隔符，原来是小写 x）
                8'h59: glyph_idx = 6'd57;  // Y（LATENCY）
                default: glyph_idx = 6'd63; // BLANK（空格以及一切不在表里的码点）
            endcase
        end
    endfunction

    // 读这一侧全部吃**上一拍算好的格子**（`s_*`）：`chars` 的索引是 移位+或（MAX_CHARS=32），
    // 字形译码是并行 case（R25），`/SCALE` 只有 5 个值 —— 这一侧原本就不深，深的是前一拍的除/模。
    wire [7:0] ch = chars[s_line * MAX_CHARS + s_cidx];
    wire [5:0] gi = glyph_idx(ch);
    wire [2:0] fx = s_pix_x / SCALE;
    wire [2:0] fy = (s_pix_y < 7*SCALE) ? (s_pix_y / SCALE) : 3'd6;
    wire [4:0] font_row = font[gi][fy];
    wire pixel_on = s_in_char && (fx < 5) && (font_row[4-fx] == 1'b1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r <= 0; g <= 0; b <= 0;
            de_out <= 0; hs_out <= 0; vs_out <= 0;
        end else begin
            de_out <= s_de;          // #96：格子与背景像素一起晚了一拍 ⇒ 这里跟着晚一拍
            hs_out <= s_hs;
            vs_out <= s_vs;
            if (pixel_on) begin
                r <= 8'hFF; g <= 8'h00; b <= 8'h90; // rose
            end else begin
                r <= s_r; g <= s_g; b <= s_b;
            end
        end
    end
endmodule
