`timescale 1ns/1ps
// OSD only:
//   L0 FPS=xx      (decimal 2)
//   L1 ANG=xxx     (decimal 3)
//   L2 EN=xxxxx    (binary 5)
//   L3 DROP=xxxxx  (hex 5) —— CDC 写口被挡住而永久消失的 16bit 字数。
//      故意用十六进制：32bit 的十进制除法在 50 MHz 像素域会拉出 45 级组合链
//      （V7.6 首次 L3：WNS −6.765）。饱和在 FFFFF，**不回卷**。
//   L4 STALL=xxxx  (decimal 4, 饱和在 9999) —— 距上一个完整帧过了多少 ms；9999 = 早就断了
// 3x rose. Space = blank glyph (NOT digit 0).
module osd_overlay #(
    parameter X0 = 16,
    parameter Y0 = 12,
    parameter SCALE = 3,
    parameter CHAR_W = 18,          // 5*3 + 3 gap
    parameter CHAR_H = 21,          // 7*3
    parameter LINE_GAP = 10,
    parameter MAX_CHARS = 10,
    parameter N_LINES = 6
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        de,
    input  wire [8:0]  angle,
    input  wire [4:0]  effect_en,
    input  wire [7:0]  fps,
    // src_sel / eth_link 这两个输入**从来没有被用过**（2026-09-24 查 ISSUES #55 时才发现：
    // 文档与我自己都以为屏上有“SRC:0/1”那一行，其实 OSD 五条线里没有片源）。
    // 所以片源/模式这件事第一次真正上屏 = 下面新增的 L5，输入口留着是给以后的行用。
    input  wire        src_sel,
    input  wire        eth_link,
    // 屏幕上**真正在显示的那一路**，由顶层的片源 mux 给（不是模式环）：
    //   {fb_vis, owner_eth} ⇒ 0x=CARD（图卡）/ 10=PS（DDR 里 PS 那一帧）/ 11=ETH（网络帧）
    // 为什么不用 mode：mode 是"要哪一路"的意愿，实际给不给还要看 `have_src` 与仲裁。
    // 用户 2026-09-24 报的"CARD 和 PS 写反了、显示 ETH 时写着 AUTO"就是这个差别：
    // 照着意愿画标签，屏幕与标签会在"意愿没生效"的那些状态下对不上。
    input  wire [1:0]  src_eff,
    // 模式环仍然要看得见（长按有没有生效的唯一屏上凭据，ISSUES #55），但只以一个 `*` 表示
    // "此刻是手动锁住的"，不再占一整格标签。
    input  wire [1:0]  mode,        // 00 自动 01 锁ETH 11 锁PS 10 锁图卡（与 src_mode 同序）
    input  wire [15:0] net_pkts,
    input  wire [15:0] net_bad,
    input  wire [31:0] net_drop,
    input  wire [15:0] net_stall,
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
    // 行号必须能表示 N_LINES-1：原来写死 [1:0]，加到 5 行后第 3/4 行永远取不到。
    wire [2:0]  line = (ly / LINE_H);
    wire [7:0]  pix_y = ly - line * LINE_H;
    wire [4:0]  cidx = lx / CHAR_W;
    wire [7:0]  pix_x = lx % CHAR_W;
    wire        in_char = in_box && (pix_y < CHAR_H);

    function [7:0] dig;
        input [3:0] v;
        begin
            if (v <= 4'd9) dig = 8'h30 + v;  // '0'..'9'
            else           dig = 8'h20;      // blank
        end
    endfunction

    // DROP 用十六进制：字模表里 A-F 本来就有（10..15），glyph_idx 也已经认它们
    function [7:0] hexdig;
        input [3:0] v;
        begin
            if (v <= 4'd9) hexdig = 8'h30 + v;   // '0'..'9'
            else           hexdig = 8'h37 + v;   // 'A'(=65) .. 'F'
        end
    endfunction

    wire [7:0]  fps_v = (fps > 8'd99) ? 8'd99 : fps;
    wire [7:0]  fps_t = (fps_v / 8'd10) % 8'd10;
    wire [7:0]  fps_o = fps_v % 8'd10;

    wire [8:0]  ang_v = angle;                 // 0..359
    wire [15:0] ang16 = {7'd0, ang_v};
    wire [3:0]  ang_h = (ang16 / 16'd100) % 16'd10;
    wire [3:0]  ang_t = (ang16 / 16'd10)  % 16'd10;
    wire [3:0]  ang_o = ang16 % 16'd10;

    // DROP=xxxxx：显示成**十六进制**，不是懒得做除法，而是 32bit 的 /10000、/1000、
    // /100、/10 四个常系数除法在像素时钟（50 MHz）下合成了一条 45 级、26.6 ns 的
    // 组合链（V7.6 第一次 L3 就死在这里：WNS −6.765，19 个违例端点）。
    // 取 nibble 只要一层 16:1 mux。"00000 = 一个字都没丢"在任何进制下同样成立，
    // 而溢出侧仍然要**饱和**：回卷到 0 会被读成"没问题"，那是这块屏最不该撒的谎。
    wire [19:0] dr_v  = (net_drop > 32'h000F_FFFF) ? 20'hFFFFF : net_drop[19:0];
    // STALL=xxxx：十进制，先把操作数压到 14 bit（9999 以内），再**分两拍算**。
    // 一次算完四个十进制位在 50 MHz 像素域是 28 级 / 16.9 ns 的组合链
    // （V7.6 第一次 L3 的 −6.765 就是这么来的），拆成「/1000 与其余三位」两拍后
    // 每段都只剩十来级。数字每帧才变一次，晚两拍到人眼没有任何影响。
    wire [13:0] st_v  = (net_stall > 16'd9999) ? 14'd9999 : net_stall[13:0];
    reg  [3:0]  st_k;                              // 千位
    reg  [9:0]  st_rem;                            // 去掉千位后的余数 0..999
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin st_k <= 0; st_rem <= 0; end
        else begin
            st_k   <= st_v / 14'd1000;
            st_rem <= st_v % 14'd1000;
        end
    end
    wire [9:0]  s9 = st_rem;
    wire [3:0]  st_d3 = st_k;
    wire [3:0]  st_d2 = (s9 / 10'd100) % 10'd10;
    wire [3:0]  st_d1 = (s9 / 10'd10)  % 10'd10;
    wire [3:0]  st_d0 =  s9            % 10'd10;

    // Fixed strings — no trailing junk
    reg [7:0] chars [0:N_LINES*MAX_CHARS-1];
    integer i;
    always @(*) begin
        for (i = 0; i < N_LINES*MAX_CHARS; i = i + 1)
            chars[i] = 8'h20;

        // L0: FPS=xx
        chars[0] = "F";
        chars[1] = "P";
        chars[2] = "S";
        chars[3] = "=";
        chars[4] = dig(fps_t[3:0]);
        chars[5] = dig(fps_o[3:0]);

        // L1: ANG=xxx
        chars[1*MAX_CHARS+0] = "A";
        chars[1*MAX_CHARS+1] = "N";
        chars[1*MAX_CHARS+2] = "G";
        chars[1*MAX_CHARS+3] = "=";
        chars[1*MAX_CHARS+4] = dig(ang_h);
        chars[1*MAX_CHARS+5] = dig(ang_t);
        chars[1*MAX_CHARS+6] = dig(ang_o);

        // L2: EN=xxxxx
        chars[2*MAX_CHARS+0] = "E";
        chars[2*MAX_CHARS+1] = "N";
        chars[2*MAX_CHARS+2] = "=";
        chars[2*MAX_CHARS+3] = effect_en[0] ? "1" : "0";
        chars[2*MAX_CHARS+4] = effect_en[1] ? "1" : "0";
        chars[2*MAX_CHARS+5] = effect_en[2] ? "1" : "0";
        chars[2*MAX_CHARS+6] = effect_en[3] ? "1" : "0";
        chars[2*MAX_CHARS+7] = effect_en[4] ? "1" : "0";

        // L3: DROP=xxxxx  （CDC 写口被挡住而永久消失的字数）
        chars[3*MAX_CHARS+0] = "D";
        chars[3*MAX_CHARS+1] = "R";
        chars[3*MAX_CHARS+2] = "O";
        chars[3*MAX_CHARS+3] = "P";
        chars[3*MAX_CHARS+4] = "=";
        chars[3*MAX_CHARS+5] = hexdig(dr_v[19:16]);
        chars[3*MAX_CHARS+6] = hexdig(dr_v[15:12]);
        chars[3*MAX_CHARS+7] = hexdig(dr_v[11:8]);
        chars[3*MAX_CHARS+8] = hexdig(dr_v[7:4]);
        chars[3*MAX_CHARS+9] = hexdig(dr_v[3:0]);

        // L4: STALL=xxxx  （距上一个完整帧过了多少 ms）
        chars[4*MAX_CHARS+0] = "S";
        chars[4*MAX_CHARS+1] = "T";
        chars[4*MAX_CHARS+2] = "A";
        chars[4*MAX_CHARS+3] = "L";
        chars[4*MAX_CHARS+4] = "L";
        chars[4*MAX_CHARS+5] = "=";
        chars[4*MAX_CHARS+6] = dig(st_d3[3:0]);
        chars[4*MAX_CHARS+7] = dig(st_d2[3:0]);
        chars[4*MAX_CHARS+8] = dig(st_d1[3:0]);
        chars[4*MAX_CHARS+9] = dig(st_d0[3:0]);

        // L5: 片源模式。这一行存在的唯一理由是“长按有没有生效”以前只能靠猜（ISSUES #55）。
        // 整个块用 N_LINES 门控：老台架仍按 5 行例化，写第 6 行就是数组越界（综合器不报错、仿真只给个 warning）。
        if (N_LINES > 5) begin

        chars[5*MAX_CHARS+0] = "S";
        chars[5*MAX_CHARS+1] = "R";
        chars[5*MAX_CHARS+2] = "C";
        chars[5*MAX_CHARS+3] = "=";
        // 标签画的是**屏幕上真的在显示的那一路**（src_eff），不是模式环（见端口注释：
        // 用户报的"CARD/PS 反了、显示 ETH 时写 AUTO"就是拿意愿当事实画的后果）。
        // 第 8 格放一个 `*` 表示"此刻是手动锁住的"——长按有没有生效仍然看得见（ISSUES #55），
        // 但不再靠一整格标签。
        case (src_eff)
            2'b11:   begin chars[5*MAX_CHARS+4] = "E"; chars[5*MAX_CHARS+5] = "T";
                          chars[5*MAX_CHARS+6] = "H"; chars[5*MAX_CHARS+7] = " "; end
            2'b10:   begin chars[5*MAX_CHARS+4] = "P"; chars[5*MAX_CHARS+5] = "S";
                          chars[5*MAX_CHARS+6] = " "; chars[5*MAX_CHARS+7] = " "; end
            default: begin chars[5*MAX_CHARS+4] = "C"; chars[5*MAX_CHARS+5] = "A";
                          chars[5*MAX_CHARS+6] = "R"; chars[5*MAX_CHARS+7] = "D"; end   // CARD
        endcase
        chars[5*MAX_CHARS+8] = (mode == 2'b00) ? " " : "*";
        end
    end

    // 5x7 font. Index 31 = blank (spaces).
    reg [4:0] font [0:31][0:6];
    integer fi, fj;
    initial begin
        for (fi = 0; fi < 32; fi = fi + 1)
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
        // G=16 N=20 P=22 S=24 = = 27
        font[16][0]=5'b01110; font[16][1]=5'b10001; font[16][2]=5'b10000;
        font[16][3]=5'b10111; font[16][4]=5'b10001; font[16][5]=5'b10001; font[16][6]=5'b01110;
        // v7.6 新增：R=17 O=18 T=19 L=21（给 DROP / STALL 两行用）
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
        // 31 stays blank
    end

    // 字码 → 字形号。**故意写成 case 而不是 if/else 区间比较**（V7.9.4 / 时序深度优化）：
    // 原来那串 `c >= 0x30 && c <= 0x39` 之类是**串行优先级链**，每个区间比较还要一次减法，
    // 它们和同一拍里的 `line*MAX_CHARS+cidx`、`font[gi][fy]` 串成一条 27 级、CARRY4=10 的链，
    // 就是 L3 报告里 `x_d_reg[11]→b_reg` 这条全设计最差路径的主体。
    // case 的 256 个码点是**并行**译码（真值表与原来逐项一致，`sim/tb_v794_osd_glyph.v` 做差分验证），
    // 表里没有的码点仍然落到 31=空格 —— 语义一字未改，只是不再串行。
    function [4:0] glyph_idx;
        input [7:0] c;
        begin
            case (c)
                8'h30: glyph_idx = 5'd0;   8'h31: glyph_idx = 5'd1;
                8'h32: glyph_idx = 5'd2;   8'h33: glyph_idx = 5'd3;
                8'h34: glyph_idx = 5'd4;   8'h35: glyph_idx = 5'd5;
                8'h36: glyph_idx = 5'd6;   8'h37: glyph_idx = 5'd7;
                8'h38: glyph_idx = 5'd8;   8'h39: glyph_idx = 5'd9;
                8'h41: glyph_idx = 5'd10;  8'h42: glyph_idx = 5'd11;
                8'h43: glyph_idx = 5'd12;  8'h44: glyph_idx = 5'd13;
                8'h45: glyph_idx = 5'd14;  8'h46: glyph_idx = 5'd15;
                8'h47: glyph_idx = 5'd16;  // G
                8'h4C: glyph_idx = 5'd21;  // L
                8'h4E: glyph_idx = 5'd20;  // N
                8'h4F: glyph_idx = 5'd18;  // O
                8'h50: glyph_idx = 5'd22;  // P
                8'h52: glyph_idx = 5'd17;  // R
                8'h53: glyph_idx = 5'd24;  // S
                8'h54: glyph_idx = 5'd19;  // T
                8'h55: glyph_idx = 5'd23;  // U（AUTO 要用；以前字库里没有 U）
                8'h48: glyph_idx = 5'd25;  // H（ETH 要用；以前字库里也没有）
                8'h2A: glyph_idx = 5'd26;  // *（手动锁片源的标记）
                8'h3D: glyph_idx = 5'd27;  // =
                default: glyph_idx = 5'd31; // BLANK（空格以及一切不在表里的码点）
            endcase
        end
    endfunction

    wire [7:0] ch = chars[line*MAX_CHARS + cidx];
    wire [4:0] gi = glyph_idx(ch);
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
