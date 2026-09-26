`timescale 1ns/1ps
// tb_osd_lines —— V8-5 四行 OSD 的整串判据（格式是用户 2026-09-24 亲给的，原话照抄）
//
// 为什么这一版把"逐格点对"换成"整串比对"：
//   新的排版按**实际位数**打数字（Th:80 而不是 Th:080），所以"某一格在第几列"不再是常数。
//   整串比对反而更狠：字段整体挪一格、少打一位、后缀没跟上，全都会红。
// 五类必判：
//   1) 四行内容逐字符等于用户给的那四行（T1）；
//   2) 每个可动态变的字段都在**边界值**上对一遍（fps 9/99/200、angle 5/45/359、
//      threshold 9/80/255、pct 7/50/100、ms 0/5/16/125/999/饱和、gamma 0..30）；
//   3) 屏上不许有"看不见的字母"：凡是画出来的格，字码必须能在字模表里找到号（T9），
//      这条专门挡"忘了画某个小写、屏上静默少一笔"（V7.6 的 R/O/T/L 就是这么抓出来的）；
//   4) 分辨率那一格必须来自**参数**而不是写死的字符串（T8 用第二份不同参数的例化对账）；
//   5) 判据自身要有牙（T11）：故意拿错的期望去比，必须逐格报红，否则 T1 那 4×32 次比对
//      就是恒真式（#60 那一课：绿得不明不白比不绿更危险）。
// ⚠ 期望串里的度数符号是用 {"Rot:45", 8'hDF, "..."} **拼**出来的，不是直接打那个字符：
//   Verilog 字符串按字节塞，直接写会进去两个 UTF-8 字节（C2 B0），整行错位。
module tb_osd_lines;
    localparam integer X0 = 16, Y0 = 12, SC = 3, CW = 18, CH = 21, LG = 10;
    // NL 跟 RTL 的默认值 N_LINES=5。**这里曾经写死 4**：`put` 有 `col < N_LINES*MAX_CHARS` 的
    // 边界保护 ⇒ 传进 4 会把 V9-4 那一行**整行丢掉**，于是"ETH is no signal"与后来加的
    // 温度格从头到尾没有金表（两份 RTL 都编得过、台架全绿，因为被测的那一份根本没有第五行）。
    // 这是一类坑的第三次出现（#60/#88：判据在空集上过），修法也一样：让例化跟默认参数一致，
    // 再让 T1e/T13e/T15 真的去比那一行。
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
    reg        tde = 0;
    wire [7:0] ro, go, bo;
    wire de_o, hs_o, vs_o;

    osd_overlay #(.X0(X0), .Y0(Y0), .SCALE(SC), .CHAR_W(CW), .CHAR_H(CH),
                  .LINE_GAP(LG), .MAX_CHARS(MC), .N_LINES(NL),
                  .IMG_W(512), .IMG_H(300)) u_osd (
        .clk(clk), .rst_n(rst_n), .x(tx), .y(ty), .de(tde),
        .angle(i_angle), .fps(i_fps), .stage_sel(i_sel), .threshold(i_th),
        .gamma_disp(i_gd), .zoom_code(i_zc), .zoom_auto(i_za), .zoom_fit(1'b0),
        .split_pct(i_sp), .split_auto(i_sa), .lat_ms(i_ms), .lat_ok(i_ok),
        .src_eff(i_src), .mode(i_mode), .bg_pix(16'h0), .no_sig(i_ns), .temp_disp(i_tmp),
        .r_in(8'd0), .g_in(8'd0), .b_in(8'd0), .hs_in(1'b0), .vs_in(1'b0),
        .r(ro), .g(go), .b(bo), .de_out(de_o), .hs_out(hs_o), .vs_out(vs_o)
    );

    // 第二份：只换片源参数。它存在的唯一理由是把"分辨率那一格是实参"钉住
    //（第一份无论怎么改激励都回答不了"512x300 是不是写死的"）。
    wire [7:0] r2, g2, b2;
    osd_overlay #(.X0(X0), .Y0(Y0), .SCALE(SC), .CHAR_W(CW), .CHAR_H(CH),
                  .LINE_GAP(LG), .MAX_CHARS(MC), .N_LINES(NL),
                  .IMG_W(640), .IMG_H(480)) u_osd2 (
        .clk(clk), .rst_n(rst_n), .x(tx), .y(ty), .de(tde),
        .angle(i_angle), .fps(i_fps), .stage_sel(i_sel), .threshold(i_th),
        .gamma_disp(i_gd), .zoom_code(i_zc), .zoom_auto(i_za), .zoom_fit(1'b0),
        .split_pct(i_sp), .split_auto(i_sa), .lat_ms(i_ms), .lat_ok(i_ok),
        .src_eff(i_src), .mode(i_mode), .bg_pix(16'h0), .no_sig(1'b0), .temp_disp(i_tmp),
        .r_in(8'd0), .g_in(8'd0), .b_in(8'd0), .hs_in(1'b0), .vs_in(1'b0),
        .r(r2), .g(g2), .b(b2), .de_out(), .hs_out(), .vs_out()
    );

    integer errors = 0, ncell = 0, nvis = 0, nscan = 0;
    reg   verbose = 1;   // T11 那条自检要故意比错，安静下来才不污染 PASS/FAIL 行

    // Latency 的十进制是**寄存过一拍**的（osd_overlay 里那一级拆分），改完激励要等几拍
    task settle;
        begin
            repeat (4) @(posedge clk);
            #1;
        end
    endtask

    // 整串比对：**长度由 want 自己数出来**（Verilog 把短串左补 0 塞进宽端口 ⇒ 最高那个
    // 非 0 字节的位置就是实际长度），手数格子一定数错（第一版就错了三处）。
    // 前 n 格等于 want，其余格必须是空格 —— "尾巴上不许有垃圾"这一条也一起判掉。
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

    // 一行占多少格、右沿到不到分割线。几何：X0=16 起点、CW=18 一格 ⇒ 第 k 格（1 基）右沿 = X0+k*CW。
    // 分割线在 x=511/512（split_display 的 PANE_W-1/PANE_W 两列标记）⇒ 判据 X0+k*CW <= 511。
    // 这条是 2026-09-25 用户报"gamma 那一行跑到分界线那边去了"之后加的：
    // 改之前第二行是 28 格 ⇒ 16+28*18 = 520 > 511 ⇒ 当时就会红；收窄之后 26 格 = 484。
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
                $display("[tb_osd_lines.v:122] FAIL %0s L%0d 占了 %0d 格 ⇒ 右沿 x=%0d 越过分割线 511", tag, ln, k, right);
            end else begin
                $display("[tb_osd_lines.v:124] ok   %0s L%0d 占 %0d 格，右沿 x=%0d <= 511", tag, ln, k, right);
            end
        end
    endtask

    // 逐像素扫一个字符格：亮的像素数必须和 TB 独立写的那份点阵一致
    task scan_glyph;
        input integer ln;
        input integer cidx;
        input [5*7-1:0] want;
        input [4*8-1:0] tag;
        integer r, c, oncnt, wantcnt;
        reg got;
        begin
            oncnt = 0; wantcnt = 0;
            for (r = 0; r < 7; r = r + 1) begin
                for (c = 0; c < 5; c = c + 1) begin
                    tx = X0 + cidx*CW + c*SC + SC/2;
                    ty = Y0 + ln*LH + r*SC + SC/2;
                    tde = 1'b1;
                    #1;
                    got = u_osd.pixel_on;
                    if (got) oncnt = oncnt + 1;
                    if (want[(6-r)*5 +: 5] & (5'b10000 >> c)) wantcnt = wantcnt + 1;
                end
            end
            tde = 1'b0;
            if (oncnt != wantcnt) begin
                errors = errors + 1;
                $display("[tb_osd_lines.v:153] FAIL %0s 格(%0d,%0d) 亮 %0d 像素，点阵说 %0d", tag, ln, cidx, oncnt, wantcnt);
            end
        end
    endtask

    // T9 的引擎：把某一行的每一格塞进 glyph_idx，**非空格的格不许落到 63**
    //（落到 63 = 这个码点没画字模，屏上静默少一笔；V7.6 靠这条抓出过 R/O/T/L 四个字）
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
                        $display("[tb_osd_lines.v:174] FAIL %0s 第 %0d 格码点 %h 没有字模（屏上看不见这一笔）", tag, c, code);
                    end
                end else if (u_osd.gi !== 6'd63) begin
                    errors = errors + 1;
                    $display("[tb_osd_lines.v:178] FAIL %0s 空格格位 %0d 竟然译出了字模号 %0d", tag, c, u_osd.gi);
                end
                release u_osd.ch;
            end
        end
    endtask

    // TB 独立抄一遍的新字模（与 RTL 那份互为反例源：谁改了另一处就红）
    localparam [5*7-1:0] G_A    = {5'b00000,5'b00000,5'b01110,5'b00001,5'b01111,5'b10001,5'b01111};
    localparam [5*7-1:0] G_M    = {5'b00000,5'b00000,5'b11110,5'b10101,5'b10101,5'b10101,5'b10101};
    localparam [5*7-1:0] G_O    = {5'b00000,5'b00000,5'b01110,5'b10001,5'b10001,5'b10001,5'b01110};
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
                $display("[tb_osd_lines.v:215] FAIL %0s L%0d 里找不到码点 %h（这一格没画出来）", tag, ln, code);
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

        // ================= T1 用户给的那四行，逐字符 =================
        defaults(); settle;
        expect_line(0, "FPS:30  Src:ETH  512x300", "T1a");
        expect_line(1, "Pipe:11000 Th:80 Gamma:1.8", "T1b");
        expect_line(2, {"Rot:45", 8'hDF, "  Zoom:0.75x(Auto)"}, "T1c");
        expect_line(3, "Split:50%  Latency:16ms", "T1d");
        // L4（V9-4 开、V9-6 起常驻温度）：这一格第一次有金表 —— 以前 NL 写死 4，
        // RTL 里那一行整个没被例化出来，所以"绿"是空集上的绿（见文件头那条 ⚠）。
        expect_line(4, "Temp:47C", "T1e");
        if (errors == 0) $display("[tb_osd_lines.v:239] PASS T1 四行逐字符等于用户原话（分辨率按真实几何 512x300 画），第 5 行是常驻的温度格");

        // ================= T2 数字宽度：不打前导零；越界一律饱和不回卷 =================
        i_fps = 8'd9;   i_angle = 9'd5; i_th = 8'd9; i_sp = 8'd7; i_ms = 16'd5; settle;
        expect_line(0, "FPS:9  Src:ETH  512x300", "T2a");
        expect_line(1, "Pipe:11000 Th:9 Gamma:1.8", "T2b");
        expect_line(2, {"Rot:5", 8'hDF, "  Zoom:0.75x(Auto)"}, "T2c");
        expect_line(3, "Split:7%  Latency:5ms", "T2d");
        i_fps = 8'd200; i_angle = 9'd359; i_th = 8'd255; i_sp = 8'd100; i_ms = 16'd5000; settle;
        expect_line(0, "FPS:99  Src:ETH  512x300", "T2e");
        expect_line(1, "Pipe:11000 Th:255 Gamma:1.8", "T2f");
        expect_line(2, {"Rot:359", 8'hDF, "  Zoom:0.75x(Auto)"}, "T2g");
        expect_line(3, "Split:100%  Latency:999ms", "T2h");
        if (errors == 0) $display("[tb_osd_lines.v:252] PASS T2 一位数不占两格、fps/ms 越界饱和（99 / 999）而不是回卷成小数");

        // ================= T3 片源那一格：标签跟着屏幕走，不跟意愿走 =================
        // ⚠ 用词是**用户的决定**，一天里改了两次：先是他的读法 `CARD`=SD 回放 / `PS`=片内图卡，
        //   随后他直接定了三个词 **`ETH` / `SD` / `TEST`**（"就叫 ETH SD TEST"）。
        //   本台架换的只是"这一状态印哪个词"：`i_src` 的位序 `{fb_vis, owner_eth}` 一个都没动。
        //   判据的**不变部分**才是重点：三态各自印什么词可以谈，但"标签必须跟着屏幕走、
        //   锁住才有 `*`、`*` 紧跟名字"这三条不许动（ISSUES #55/#66 讲的是这个，不是用词）。
        i_fps = 8'd30; i_src = 2'b10; i_mode = 2'b11; settle;
        expect_line(0, "FPS:30  Src:SD*  512x300", "T3a");
        i_src = 2'b00; i_mode = 2'b10; settle;
        expect_line(0, "FPS:30  Src:TEST*  512x300", "T3b");
        i_src = 2'b01; i_mode = 2'b01; settle;
        expect_line(0, "FPS:30  Src:TEST*  512x300", "T3c");
        i_src = 2'b11; i_mode = 2'b00; settle;
        expect_line(0, "FPS:30  Src:ETH  512x300", "T3d");
        if (errors == 0) $display("[tb_osd_lines.v:268] PASS T3 锁住才有 *、* 紧跟名字；仲裁与 mux 不一致时画 mux 那一路（#55）");

        // ================= T4 五位 Pipe 码 =================
        defaults(); settle;             // 每段自己把激励摆回基线：T2 留下的 Th=255 会把期望串顶歪
        i_sel = 9'd0;   settle; expect_line(1, "Pipe:00000 Th:80 Gamma:1.8", "T4a");
        i_sel = 9'h003; settle; expect_line(1, "Pipe:30000 Th:80 Gamma:1.8", "T4b");
        i_sel = 9'h008; settle; expect_line(1, "Pipe:02000 Th:80 Gamma:1.8", "T4c");
        i_sel = 9'h010; settle; expect_line(1, "Pipe:00100 Th:80 Gamma:1.8", "T4d");
        i_sel = 9'h060; settle; expect_line(1, "Pipe:00020 Th:80 Gamma:1.8", "T4e");
        i_sel = 9'h080; settle; expect_line(1, "Pipe:00001 Th:80 Gamma:1.8", "T4f");
        // 腐蚀+膨胀同时置 1 = proc_pipeline 里写死的"两个都不做"⇒ 第五格必须是 0，
        // 写 3 就是"屏上说两个都开、画面上什么都没发生"（tb_v86 T14 那条语义的屏上版）
        i_sel = 9'h180; settle; expect_line(1, "Pipe:00000 Th:80 Gamma:1.8", "T4g");
        i_sel = 9'h1FF; settle; expect_line(1, "Pipe:33120 Th:80 Gamma:1.8", "T4h");
        defaults(); settle;
        if (errors == 0) $display("[tb_osd_lines.v:283] PASS T4 八种控制字逐位对（全 1 那组：前两级 3、Sobel 1、阈值旁路 0）");

        // ================= T5 Zoom 八档 + (Auto) 后缀 =================
        begin : blk5
            integer q;
            for (q = 0; q <= 7; q = q + 1) begin
                i_zc = q[2:0]; settle;
                case (q)
                    0:    expect_line(2, {"Rot:45", 8'hDF, "  Zoom:0.25x(Auto)"}, "T50");
                    1:    expect_line(2, {"Rot:45", 8'hDF, "  Zoom:0.33x(Auto)"}, "T51");
                    2:    expect_line(2, {"Rot:45", 8'hDF, "  Zoom:0.50x(Auto)"}, "T52");
                    3:    expect_line(2, {"Rot:45", 8'hDF, "  Zoom:0.75x(Auto)"}, "T53");
                    4:    expect_line(2, {"Rot:45", 8'hDF, "  Zoom:1.00x(Auto)"}, "T54");
                    5:    expect_line(2, {"Rot:45", 8'hDF, "  Zoom:1.33x(Auto)"}, "T55");
                    6:    expect_line(2, {"Rot:45", 8'hDF, "  Zoom:1.50x(Auto)"}, "T56");
                    default: expect_line(2, {"Rot:45", 8'hDF, "  Zoom:2.00x(Auto)"}, "T57");
                endcase
            end
        end
        i_zc = 3'd3; i_za = 1'b0; settle;
        expect_line(2, {"Rot:45", 8'hDF, "  Zoom:0.75x"}, "T5z");
        i_za = 1'b1; settle;
        if (errors == 0) $display("[tb_osd_lines.v:305] PASS T5 八档各自精确；zoom_auto 关掉就不许再有 (Auto)");

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
                expect_line(1, {"Pipe:11000 Th:80 Gamma:", g_hi, 8'h2E, g_lo}, "T6");
            end
        end
        i_gd = 6'd0; settle;
        expect_line(1, "Pipe:11000 Th:80 Gamma:0.0", "T6z");
        i_gd = 6'd18; settle;
        if (errors == 0) $display("[tb_osd_lines.v:324] PASS T6 gamma×10 二十一台逐档对；0.0 = 表关着（PL 逐位旁路）");

        // ================= T7 Latency：没测量就必须画 -- =================
        i_ms = 16'd0; settle;
        expect_line(3, "Split:50%  Latency:0ms", "T7a");
        i_ms = 16'd16; settle;
        expect_line(3, "Split:50%  Latency:16ms", "T7b");
        i_ms = 16'd125; settle;
        expect_line(3, "Split:50%  Latency:125ms", "T7c");
        i_ok = 1'b0; i_ms = 16'd77; settle;
        expect_line(3, "Split:50%  Latency:--ms", "T7d");
        i_ok = 1'b1; i_sa = 1'b1; i_ms = 16'd33; settle;
        expect_line(3, "Split:50%(Auto)  Latency:33ms", "T7e");
        i_sa = 1'b0; i_ms = 16'd16; settle;
        if (errors == 0) $display("[tb_osd_lines.v:338] PASS T7 lat_ok=0 屏上是 --，过期/没算完的数不许冒充测量值");

        // ================= T8 分辨率那一格来自参数，不是写死的串 =================
        begin : blk8
            integer c8;
            reg [7:0] exp8;
            for (c8 = 0; c8 < 7; c8 = c8 + 1) begin
                exp8 = "0" + (c8 == 0 ? 8'd6  : (c8 == 1 ? 8'd4  :
                        (c8 == 2 ? 8'd0  : (c8 == 3 ? 8'd24 :
                        (c8 == 4 ? 8'd4  : (c8 == 5 ? 8'd8  : 8'd0))))));
                // 640x480：'6' '4' '0' 'x'(0x78) '4' '8' '0'
                if (c8 == 3) exp8 = 8'h78;
                if (u_osd2.chars[0*MC + 17 + c8] !== exp8) begin
                    errors = errors + 1;
                    $display("[tb_osd_lines.v:352] FAIL T8 第二份(640x480) 第 %0d 格 = %h 期望 %h", c8,
                             u_osd2.chars[0*MC + 17 + c8], exp8);
                end
                ncell = ncell + 1;
            end
            if (errors == 0) $display("[tb_osd_lines.v:357] PASS T8 换一组 IMG_* 参数那一格就跟着变 ⇒ 画的是实参");
            // 第一份仍是 512x300（与第二份并存 ⇒ 排除"两份共用同一个常数"的假绿）
            expect_line(0, "FPS:30  Src:ETH  512x300", "T8b");
            if (u_osd.chars[0*MC+17] === u_osd2.chars[0*MC+17]) begin
                errors = errors + 1;
                $display("[tb_osd_lines.v:362] FAIL T8c 两份画了同一个数字 ⇒ 分辨率那一格没吃到参数");
            end
        end

        // ================= T9 屏上不许有"看不见的字母" =================
        // V9-6 起第五行也要查：那一行有 `Temp:`（大写 T + 三个小写 + 冒号）、数字、`C`，
        // 以及 `ETH is no signal`（那句里的小写 g 是 V9-4 新画的）—— 少一个字模就是屏上静默少一笔。
        defaults(); settle;
        no_invisible(0, "T9a"); no_invisible(1, "T9b");
        no_invisible(2, "T9c"); no_invisible(3, "T9d"); no_invisible(4, "T9i");
        i_src = 2'b00; i_mode = 2'b11; i_sa = 1'b1; i_zc = 3'd7;
        i_th = 8'd255; i_ok = 1'b0; i_gd = 6'd30;
        i_ns = 1'b1;   i_tmp = 8'hFF;   settle;   // 温度读不到 + ETH 那一句亮着：这一行的另一半状态
        no_invisible(0, "T9e"); no_invisible(1, "T9f");
        no_invisible(2, "T9g"); no_invisible(3, "T9h"); no_invisible(4, "T9j");
        defaults(); settle;
        if (errors == 0) $display("[tb_osd_lines.v:375] PASS T9 两种状态 × 五行：每个非空格都译得出字模号，空格必须译成 63");

        // ================= T10 新字模逐像素扫（按码点找格子，不手写第几格） =================
        // 位图是 TB 自己抄的（`build/glyphs_draft.txt` 那份），与 RTL 互为反例源：
        // 谁改了 RTL 的一行位图而没改这里，亮像素数就对不上。
        defaults(); settle;
        scan_code(1, 8'h61, G_A,    "T10a");    // Gamma 的两个 a
        scan_code(1, 8'h6D, G_M,    "T10b");    // Gamma 的两个 m
        scan_code(2, 8'h6F, G_O,    "T10c");    // Rot/Zoom/(Auto) 里的 o
        scan_code(2, 8'hDF, G_DEG,  "T10d");    // 度数符号
        scan_code(2, 8'h5A, G_Z,    "T10e");    // Zoom 的 Z（V8-5 新画的大写）
        scan_code(2, 8'h28, G_LPAR, "T10f");    // (Auto) 的左括号
        scan_code(3, 8'h25, G_PCT,  "T10g");    // 百分号
        scan_code(3, 8'h3A, G_COL,  "T10h");    // 冒号（Split:/Latency: 两处，都要有笔画）
        scan_code(1, 8'h2E, G_DOT,  "T10i");    // 1.8 的小数点
        i_ok = 1'b0; settle;
        scan_code(3, 8'h2D, G_DASH, "T10j");    // Latency 没有可信测量时的两根短线
        i_ok = 1'b1; settle;
        if (errors == 0) $display("[tb_osd_lines.v:393] PASS T10 新字模逐个扫过（a m o Z ° ( %% : . -），少一笔就少一截亮像素");

        // ================= T11 判据自己有牙吗：拿错的期望比，必须逐格红 =================
        save_e = errors; verbose = 0;
        expect_line(0, "FPS:31  Src:ETH  512x300", "T11");
        if (errors == save_e + 1) begin
            $display("[tb_osd_lines.v:399] PASS T11 错期望被抓到（那一格确实逐格在比，不是恒真式）");
            errors = save_e; verbose = 1;          // 自检的"红"是预期，撤销计数并恢复打印
        end else begin
            verbose = 1;
            errors = errors + 1;
            $display("[tb_osd_lines.v:404] FAIL T11 判据没牙：错期望报了 %0d 处（应为 1）", errors - save_e);
        end

        // ================= T13 行宽：任何一行都不许越过左半窗的分割线 =================
        // 拿"今天可达的最宽一组激励"来量：FPS 三位、Src 带 * 且是**最长的那个词**、阈值三位、
        // 效果字四位全非零、γ 一位小数、时延三位。这时任何一行都不许出界。
        // ⚠ "最长"这一条**跟着用词走**：用词从 CARD 换成 TEST/SD 之后，`2'b10` 那一态只剩两个字母
        //   （"SD"），拿它当"最宽激励"会悄悄把这一行缩短 3 格 ⇒ 判据就没牙了。所以这里取
        //   `i_src = 2'b00` → `TEST*`（5 格，与当初的 `CARD*` 同宽）。以后再加词，先回来看这一行。
        // ⚠ `i_sa`（Split 的 (Auto) 旗标）**必须留 0** —— 顶层现在把它绑成常量 0（缝还没有执行者，
        //   ISSUES #62）。第一次跑这条判据时我用 i_sa=1 量出 **L3 = 31 格 = 574 px > 511**，
        //   也就是说：**V8-4b 一旦让 (Auto) 真的亮起来，第四行就会压到分割线上**，
        //   届时要先把 L3 的双空格收掉（或那一格不再画 (Auto)）。这条约束记在这里，别让它丢。
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
        if (errors == 0) $display("[tb_osd_lines.v:423] PASS T13 最宽可达激励下五行都留在分割线这边（X0+k*CW <= 511）");

        // ================= T14 两个"看着像别的字母"的字模（用户报 Src→Sro / Split→Solit）====
        // 点阵是**按字母形状手抄**的，不从 osd_overlay.v 复制（那正是当初让它活下来的原因：
        // 金表与实现同源 ⇒ 抄错也一起错）。'c' 的右列一整列必须空，'p' 的左列必须贯通到降部。
        // 位置：L0 "FPS:99  Src:TEST*…" 的 'c' 在第 10 格；L1 "Pipe:…" 的小写 'p' 在第 2 格。
        scan_glyph(0, 10, 35'b00000_00000_01110_10000_10000_10000_01111, "T14a"); // c
        scan_glyph(1,  2, 35'b00000_00000_10110_10001_10001_10110_10000, "T14b"); // p
        if (errors == 0) $display("[tb_osd_lines.v:431] PASS T14 c/p 两个字模逐像素对上（c 右列全空、p 左列贯通）");

        // ================= T15 温度那一格：256 个编码全扫（V9-6） =================
        // 为什么是"全扫 256"而不是挑几个：这一格的规则是一句位判断
        //   （`temp_disp[7:4] <= 9 && temp_disp[3:0] <= 9` ⇒ 画 BCD，否则画 `--`），
        //   挑样最容易漏掉的就是"边界那 1"：把 `<= 9` 写成 `< 9`，只有含数字 9 的那些编码会红
        //   （0x09、0x19、…、0x90、0x99 —— 而 47 °C 这种室温激励一个都不会红）。
        // TB 侧的期望是**自己算的**（十位/个位各自转 ASCII），不是抄 RTL 的字符串：
        //   抄来的期望与实现同源 ⇒ 抄错也一起错（T14 那条注释讲的是同一件事）。
        // 顺带钉住"两位固定宽度"：100 个编码里 0..9 °C 画的是 `Temp:07C` 而不是 `Temp:7C` ——
        //   这与 L1/L3 的"不打前导零"**相反**，是有意的：这一格后面跟着 ETH 那句异常文字，
        //   数字宽度一跳整句就会左右抖。理由写在 osd_overlay.v 的 L4 那段。
        begin : blk15
            integer q15, ndig15, ndash15, hit15;
            reg [7:0] c15;                      // ⚠ 扫描变量必须是 reg 不是 integer：**integer 不许
                                                //   做部分选择**（Verilog-2001），而这里要拆两个半字节
            reg [3:0] d15, o15;
            reg [8*32-1:0] w15;
            ndig15 = 0; ndash15 = 0;
            defaults(); settle;      // ⚠ 必须先把 i_ns 收回 0：T13 的最宽激励把 ETH 那一句点亮了，
                                     //   而 expect_line 是**整行 32 格**都比（尾巴多一句就是几十个 FAIL）
            for (q15 = 0; q15 < 256; q15 = q15 + 1) begin
                c15  = q15;        // 靠赋值截到低 8 位（integer 不能做部分选择，写 q15[7:0] 是非法的）
                d15  = c15[7:4];
                o15  = c15[3:0];
                i_tmp = c15;
                if (d15 <= 4'd9 && o15 <= 4'd9) begin
                    w15 = {"Temp:", 8'h30 + d15, 8'h30 + o15, 8'h43};   // 'C'
                    ndig15 = ndig15 + 1;
                end else begin
                    w15 = "Temp:--";
                    ndash15 = ndash15 + 1;
                end
                settle;
                expect_line(4, w15, "T15");
            end
            // 陪跑数：100 个能画、156 个画 `--`。少了这一条，"扫了 256 次"本身也可能是错觉
            //（比如循环变量接错，256 次都是同一个编码 ⇒ 全都"过"）。
            if (ndig15 != 100 || ndash15 != 156) begin
                errors = errors + 1;
                $display("[tb_osd_lines.v:452] FAIL T15 分类数不对：能画 %0d（应 100）、-- %0d（应 156）",
                         ndig15, ndash15);
            end
            // 复位值那一格：effect_ctrl 的 gm_sync 低字节复位成 0xFF ⇒ 屏上必须是 `--`，
            // 不能是 `Temp:00C`（那是一条谁都没测过的数）。扫面里已经含 0xFF，这一条是把它点名。
            i_tmp = 8'hFF; settle;
            expect_line(4, "Temp:--", "T15z");
            // 这条判据自己有没有牙：拿错的期望比一次 L4（T11 的同一手法，针对新加的这一行）
            save_e = errors; verbose = 0;
            i_tmp = 8'h47; settle;
            hit15 = errors;
            expect_line(4, "Temp:48C", "T15t");          // 故意比错：个位差 1
            if (errors == hit15 + 1) errors = hit15;      // 预期的红，撤销
            else begin
                verbose = 1;
                errors = errors + 1;
                $display("[tb_osd_lines.v:462] FAIL T15t 第五行的比对没牙：错期望报了 %0d 处（应为 1）",
                         errors - hit15);
            end
            verbose = 1;
            defaults(); settle;
            if (errors == save_e)
                $display("[tb_osd_lines.v:466] PASS T15 温度那一格 256 个编码全扫过，且错期望会被抓到");
        end

        // ================= T12 陪跑：样本数必须 > 0（#60 那一课） =================
        if (errors == 0) $display("[tb_osd_lines.v:434] PASS T12 本台架比对了 %0d 格、查了 %0d 个非空格、扫了 %0d 个字形",
                                  ncell, nvis, nscan);
        if (ncell < 1500 || nvis < 150 || nscan < 12) begin
            errors = errors + 1;
            $display("[tb_osd_lines.v:438] FAIL T12 样本太少（ncell=%0d nvis=%0d）⇒ 上面有些判据是空的", ncell, nvis);
        end

        $display("");
        if (errors == 0) $display("RESULT tb_osd_lines PASS");
        else             $display("RESULT tb_osd_lines FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("RESULT tb_osd_lines FAIL timeout");
        $finish;
    end
endmodule
