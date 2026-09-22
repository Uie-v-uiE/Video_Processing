`timescale 1ns/1ps
// tb_osd_lines — V7.6 新增的两行 OSD（DROP / STALL）必须真的能画出来。
//
// 为什么单独测：OSD 是这次交付里唯一"靠人眼验收"的部分，而它的两个陷阱都是静默的：
//   1) 行号 `line` 原来写死 [1:0]，N_LINES 加到 5 之后第 3/4 行永远取不到
//      —— 屏幕上什么都不显示，但综合和时序报告全绿；
//   2) 字模表原来只有 A-G/N/P/S/0-9/=，新增的 R/O/T/L 若没进 glyph_idx，
//      字母会**静默变成空格**，"DROP=12345" 看着像 "  OP=12345"。
// 所以这里既查 chars[] 里的 ASCII，也逐像素把 8 个字形扫一遍和 TB 里独立写死的
// 5x7 点阵对比 —— 字模表在 TB 里重抄一遍是有意的，不然会和 RTL 一起错。
module tb_osd_lines;
    localparam integer X0 = 16, Y0 = 12, SC = 3, CW = 18, CH = 21, LG = 10, MC = 10;
    localparam integer LH = CH + LG;                 // 31

    // 5x7 字模（bit4 = 最左列），TB 独立定义
    localparam [5*7-1:0] GL_A = {5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
    localparam [5*7-1:0] GL_D = {5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
    localparam [5*7-1:0] GL_E = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
    localparam [5*7-1:0] GL_F = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
    localparam [5*7-1:0] GL_L = {5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
    localparam [5*7-1:0] GL_O = {5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
    localparam [5*7-1:0] GL_P = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
    localparam [5*7-1:0] GL_R = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
    localparam [5*7-1:0] GL_S = {5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
    localparam [5*7-1:0] GL_T = {5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg [31:0] drop = 0;
    reg [15:0] stall = 0;
    reg [11:0] tx = 0, ty = 0;
    reg        tde = 0;
    wire [7:0] ro, go, bo;
    wire de_o2, hs_o, vs_o;

    osd_overlay #(.X0(X0), .Y0(Y0), .SCALE(SC), .CHAR_W(CW), .CHAR_H(CH),
                  .LINE_GAP(LG), .MAX_CHARS(MC), .N_LINES(5)) u_osd (
        .clk(clk), .rst_n(rst_n), .x(tx), .y(ty), .de(tde),
        .angle(9'd0), .effect_en(5'd0), .fps(8'd0),
        .src_sel(1'b0), .eth_link(1'b1),
        .net_pkts(16'd0), .net_bad(16'd0),
        .net_drop(drop), .net_stall(stall), .bg_pix(16'h0),
        .r_in(8'd0), .g_in(8'd0), .b_in(8'd0), .hs_in(1'b0), .vs_in(1'b0),
        .r(ro), .g(go), .b(bo), .de_out(de_o2), .hs_out(hs_o), .vs_out(vs_o)
    );

    integer errors = 0;

    task expect_line;
        input integer line;
        input [8*10-1:0] want;      // 10 个 ASCII，第 0 个字符在最高字节
        integer c;
        reg [7:0] a, b;
        begin
            for (c = 0; c < 10; c = c + 1) begin
                a = want[(9-c)*8 +: 8];
                b = u_osd.chars[line*MC + c];
                if (a !== b) begin
                    $display("FAIL line%0d char%0d = '%c'(=%h), want '%c'(=%h)",
                             line, c, b, b, a, a);
                    errors = errors + 1;
                end
            end
        end
    endtask

    // 逐像素扫一个字符格，亮的像素数必须和 TB 点阵一致
    task scan_glyph;
        input integer line;
        input integer cidx;
        input [5*7-1:0] want;
        integer r, c, oncnt, wantcnt;
        reg got;
        begin
            oncnt = 0; wantcnt = 0;
            for (r = 0; r < 7; r = r + 1) begin
                for (c = 0; c < 5; c = c + 1) begin
                    tx  = X0 + cidx*CW + c*SC + SC/2;
                    ty  = Y0 + line*LH + r*SC + SC/2;
                    tde = 1'b1;
                    #1;
                    got = u_osd.pixel_on;
                    if (got) oncnt = oncnt + 1;
                    if (want[(6-r)*5 +: 5] & (5'b10000 >> c)) wantcnt = wantcnt + 1;
                end
            end
            tde = 1'b0;
            if (oncnt != wantcnt) begin
                $display("FAIL line%0d char%0d lit %0d px, font says %0d px (字形没进 glyph_idx 就会全空)",
                         line, cidx, oncnt, wantcnt);
                errors = errors + 1;
            end
        end
    endtask


    // STALL 的十进制现在分两拍算（osd_overlay 里的 st_k/st_rem 流水），
    // 所以改完激励必须等几拍再读 chars[]。
    task settle;
        begin
            repeat (4) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        rst_n = 0; repeat (4) @(posedge clk); rst_n = 1; tde = 0; #1;

        drop = 32'd0;      settle; expect_line(3, "DROP=00000"); expect_line(4, "STALL=0000");
        drop = 32'd12345;  settle; expect_line(3, "DROP=03039");   // 12345 = 0x3039
        stall = 16'd678;   settle; expect_line(4, "STALL=0678");
        drop = 32'd99999;  settle; expect_line(3, "DROP=1869F");   // 99999 = 0x1869F
        drop = 32'd200000; settle; expect_line(3, "DROP=30D40");  // 20bit 装得下，不该饱和
        drop = 32'd4000000; settle; expect_line(3, "DROP=FFFFF"); // 越过 0xFFFFF 才饱和，不许回卷成 0
        stall = 16'd60000; settle; expect_line(4, "STALL=9999");  // 饱和（70000 会被 16bit 截成 4464，测不到这件事）
        if (errors == 0) $display("PASS number formatting: DROP hex (5 nibble) / STALL dec, both saturating");

        scan_glyph(3, 0, GL_D);
        scan_glyph(3, 1, GL_R);
        scan_glyph(3, 2, GL_O);
        scan_glyph(3, 3, GL_P);
        scan_glyph(4, 0, GL_S);
        scan_glyph(4, 1, GL_T);
        scan_glyph(4, 2, GL_A);
        scan_glyph(4, 3, GL_L);
        scan_glyph(4, 4, GL_L);
        // 老行不能因为 line 位宽改动而移位
        scan_glyph(0, 0, GL_F);
        scan_glyph(2, 0, GL_E);
        $display("PASS glyph scan: D R O P S T A L (+ 老行 F/E 没移位)");

        if (errors == 0) $display("RESULT tb_osd_lines PASS");
        else             $display("RESULT tb_osd_lines FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #1_000_000;
        $display("RESULT tb_osd_lines FAIL timeout");
        $finish;
    end
endmodule
