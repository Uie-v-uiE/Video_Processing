`timescale 1ns/1ps
// 功能：被测模块 `osd_overlay`；覆盖点＝glyph 并行 case 译码与 V7.9.3 串行区间比较的等价性，即
//        0..255 全部码点各自落到哪个字形号：0x30..0x39 连号、0x41..0x46 连号、H L N O P R S T U Z
//        I M X Y 单点、* = : . % ( ) ° - 七个符号，以及未列码点与空格统一落 63、'0' 落 0。
// 激励与检查：clk 半周期 #10，rst_n 拉低 3 拍后释放；逐码点 `force u_osd.ch = c`（c = 0..255）、
//        `#1` 等组合稳定、读 RTL 自算的 `u_osd.gi` 与 TB 内独立重写的黄金函数比、再 `release`，共 256 次。
//        判定 1 `u_osd.gi !== gold_glyph(c)` 即错；判定 2 计数地板 `n_hit !== 256` 即错；
//        判定 3（反向断言）force 8'h53 时 `gi === 6'd25` 必须为假、`gi !== 6'd24` 也必须为假；
//        判定 4 force 8'h62 与 8'h20 时 `gi` 必须等于 6'd63；判定 5 force 8'h30 时必须等于 6'd0。
// 预期结果：通过时全程不出 FAIL 行、只打末行 `PASS tb_osd_glyph_rom`（errors==0）；失败时打
//        `FAIL code=<码点> rtl_gi=<n> gold=<m>`、`FAIL 只比对了 <n>/256 个码点`、
//        `FAIL 反向断言失效：'S' 竟然等于故意写错的 25`、`FAIL 'S' 既不等于 24 也不该等于别的`、
//        `FAIL 未画的 b 应该落到空格 63`、`FAIL 空格 20 应落到 63`、`FAIL '0' 应落到 0` 之一，
//        errors 加一并把末行改判 `FAIL tb_osd_glyph_rom errors=<n>`；#200_000 处未 finish 时打
//        `FAIL watchdog：台架没跑完就超时`。
// tb_osd_glyph_rom —— V7.9.4 把 glyph_idx 从"串行区间比较"改成"并行 case"的**差分判据**。跑：bash sim/run_one.sh tb_osd_glyph_rom
// 要防的事：译码改动**只可能**改到"某个 ASCII 落到哪个字形号"，而字形号错了在屏幕上的表现是换一个字母（S 变 5、P 变 D 之类），
//   肉眼在 1024×600 的小字上很难立刻发现。
// 所以这里不抽样、不靠渲染：把**全部 256 个码点**逐个塞进被改的那一级（`force` RTL 里的 `ch` 这根线），读 RTL 自己算出来的 `gi`，
// 和 TB 里**按改前语义独立重写**的黄金函数逐项比 —— 黄金函数就是 V7.9.3 那串 if/else 的形状（含减法），不是重新理解的"应该是什么"，
// 这样"改前后等价"这件事是被测出来的，不是我声称的。
module tb_osd_glyph_rom;
    localparam integer X0 = 16, Y0 = 12, SC = 3, CW = 18, CH = 21, LG = 10, MC = 32;

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg [11:0] tx = 0, ty = 0;
    reg        tde = 0;
    wire [7:0] ro, go, bo;
    wire de_o, hs_o, vs_o;

    osd_overlay #(.X0(X0), .Y0(Y0), .SCALE(SC), .CHAR_W(CW), .CHAR_H(CH),
                  .LINE_GAP(LG), .MAX_CHARS(MC), .N_LINES(4)) u_osd (
        .clk(clk), .rst_n(rst_n), .x(tx), .y(ty), .de(tde),
        .angle(9'd0), .fps(8'd0),
        .stage_sel(9'd0), .threshold(8'd80), .gamma_disp(6'd18),
        .zoom_code(3'd4), .zoom_auto(1'b0), .zoom_fit(1'b0),
        .split_pct(8'd50), .split_auto(1'b0),
        .lat_ms(16'd0), .lat_ok(1'b0),
        .src_eff(2'b11), .mode(2'b00), .bg_pix(16'h0), .osd_en(1'b1), .no_sig(1'b0),
        // ⚠ V9-6 新加的 `temp_disp` 必须**显式接一个值**，不许悬空：悬空 = X，会顺着 `if ((temp_disp[7:4] <= 4'd9) ...)`
        //   把整行字符变成 X（#88 的根因就是顶层台架一个悬空输入红了四判据好几天）。这里给"没有可信读数"那个编码即可；
        //   `N_LINES(4)` 也是有意的：这里不比行内容，行数是几都与"码点→字形号"无关。
        .temp_disp(8'hFF),
        .r_in(8'd0), .g_in(8'd0), .b_in(8'd0), .hs_in(1'b0), .vs_in(1'b0),
        .r(ro), .g(go), .b(bo), .de_out(de_o), .hs_out(hs_o), .vs_out(vs_o)
    );

    // 黄金表：**按 §7d / glyphs_draft 那张号表独立抄一遍**（不是从 RTL 里 copy 出来的），谁改了 RTL 的 case 没改这张表就红。
    // V7.9.3 的"改前语义"仍然成立（0x30..0x39、0x41..0x46、大写若干、* 与 =）；V8-5 只是往表里**加**码点：
    //   : . % ( ) ° -、大写 Z，空格的号从 31 挪到 63。
    // #67：**屏上不再有小写** —— 0x61~0x7A 这一族从 RTL 的 case 里删掉了、本表也一起删 ⇒ 它们落到最后的 63=空格。
    //   大小写折算发生在 `put`（写格子那一侧）、不在这一条并行链上，所以 `glyph_idx` 收到小写码点本身就是错（折算漏了），下面 256 次全码点扫描仍盯着这件事；
    //   同时新增四个大写 I=54 M=55 X=56 Y=57（PIPE / GAMMA / 尺寸分隔符 / LATENCY 要用）。
    function [5:0] gold_glyph;
        input [7:0] c;
        begin
            if (c >= 8'h30 && c <= 8'h39)       gold_glyph = c - 8'h30;
            else if (c >= 8'h41 && c <= 8'h46)  gold_glyph = 6'd10 + (c - 8'h41);
            else if (c == 8'h47) gold_glyph = 6'd16;
            else if (c == 8'h48) gold_glyph = 6'd25;   // H
            else if (c == 8'h4C) gold_glyph = 6'd21;   // L
            else if (c == 8'h4E) gold_glyph = 6'd20;   // N
            else if (c == 8'h4F) gold_glyph = 6'd18;   // O
            else if (c == 8'h50) gold_glyph = 6'd22;   // P
            else if (c == 8'h52) gold_glyph = 6'd17;   // R
            else if (c == 8'h53) gold_glyph = 6'd24;   // S
            else if (c == 8'h54) gold_glyph = 6'd19;   // T
            else if (c == 8'h55) gold_glyph = 6'd23;   // U
            else if (c == 8'h5A) gold_glyph = 6'd50;   // Z（Zoom）
            else if (c == 8'h49) gold_glyph = 6'd54;   // I（#67：PIPE / SPLIT）
            else if (c == 8'h4D) gold_glyph = 6'd55;   // M（#67：GAMMA / ZOOM）
            else if (c == 8'h58) gold_glyph = 6'd56;   // X（#67：尺寸那一格的分隔符）
            else if (c == 8'h59) gold_glyph = 6'd57;   // Y（#67：LATENCY）
            else if (c == 8'h2A) gold_glyph = 6'd26;   // *
            else if (c == 8'h3D) gold_glyph = 6'd27;   // =
            else if (c == 8'h3A) gold_glyph = 6'd44;   // :
            else if (c == 8'h2E) gold_glyph = 6'd45;   // .
            else if (c == 8'h25) gold_glyph = 6'd46;   // %
            else if (c == 8'h28) gold_glyph = 6'd47;   // (
            else if (c == 8'h29) gold_glyph = 6'd48;   // )
            else if (c == 8'hDF) gold_glyph = 6'd49;   // °（Latin-1）
            else if (c == 8'h2D) gold_glyph = 6'd52;   // -（Latency 的 `--`）
            // 小写 a c e g h i l m n o p r s t u x y 那 17 条**从这里删掉了**（#67）。
            // ⚠ 下面那句 `n_hit !== 256` 的覆盖地板，才是把"金表漏一格"（r69 全量回归才发现漏了 0x67）从静默变成红的东西
            //   ⇒ 谁以后加字模，先改这张表再改 RTL，而且必须跑**全量**（门禁不跑台架 = #88 那一族）。
            else                 gold_glyph = 6'd63;   // 空格
        end
    endfunction

    integer errors = 0, k, n_hit;
    reg [7:0] c;
    initial begin
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;

        // 1) 全 256 码点：RTL 的 gi 必须与黄金函数逐项相同
        n_hit = 0;
        for (k = 0; k < 256; k = k + 1) begin
            c = k[7:0];
            force u_osd.ch = c;
            #1;                                   // 让组合逻辑稳定
            if (u_osd.gi !== gold_glyph(c)) begin
                $display("FAIL code=%h rtl_gi=%0d gold=%0d", c, u_osd.gi, gold_glyph(c));
                errors = errors + 1;
            end
            if (u_osd.gi === gold_glyph(c)) n_hit = n_hit + 1;
            release u_osd.ch;
        end
        if (n_hit !== 256) begin
            $display("[tb_osd_glyph_rom.v:103] FAIL 只比对了 %0d/256 个码点", n_hit);
            errors = errors + 1;
        end

        // 2) 判据本身要有牙：拿一个**故意写错**的期望值去比 RTL，必须判为"不等"。
        //    （如果连错的期望值都能比"过"，说明 1) 那 256 次比对是恒真式、等于没测）
        force u_osd.ch = 8'h53;                  // 'S'，真值应是 24
        #1;
        if (u_osd.gi === 6'd25) begin
            $display("[tb_osd_glyph_rom.v:112] FAIL 反向断言失效：'S' 竟然等于故意写错的 25");
            errors = errors + 1;
        end
        if (u_osd.gi !== 6'd24) begin
            $display("[tb_osd_glyph_rom.v:116] FAIL 'S' 既不等于 24 也不该等于别的：实得 %0d", u_osd.gi);
            errors = errors + 1;
        end
        release u_osd.ch;

        // 3) **不在表里的码点**必须落到 63=空格（老规矩，号从 31 挪到 63）。这里挑 'b'：四行 OSD 里没有这个字母、没画字模；
        //    若哪天格式里冒出 'b'，它会静默变空格（屏上少一笔）、届时这条判据仍然绿，抓它的是 tb_osd_overlay 的"整屏不许有看不见的字母"那条。
        force u_osd.ch = 8'h62;                  // 'b'
        #1;
        if (u_osd.gi !== 6'd63) begin
            $display("[tb_osd_glyph_rom.v:128] FAIL 未画的 b 应该落到空格 63，实得 gi=%0d", u_osd.gi);
            errors = errors + 1;
        end
        release u_osd.ch;

        // 3b) 号挪过位置的那些码点，逐个钉一次（空格从 31→63 最容易改漏：
        //     改了的 RTL、没改的默认分支 = 全屏幕是 0）
        force u_osd.ch = 8'h20;                  // 空格本身
        #1;
        if (u_osd.gi !== 6'd63) begin
            $display("[tb_osd_glyph_rom.v:138] FAIL 空格 20 应落到 63，实得 %0d", u_osd.gi);
            errors = errors + 1;
        end
        release u_osd.ch;
        force u_osd.ch = 8'h30;                  // '0' 与"空格 31"这对老号不能再混
        #1;
        if (u_osd.gi !== 6'd0) begin
            $display("[tb_osd_glyph_rom.v:145] FAIL '0' 应落到 0，实得 %0d", u_osd.gi);
            errors = errors + 1;
        end
        release u_osd.ch;

        if (errors == 0) $display("PASS tb_osd_glyph_rom");
        else             $display("FAIL tb_osd_glyph_rom errors=%0d", errors);
        $finish;
    end

    initial begin
        #200_000;                                  // 60 µs 量级就够（没有长流水线）
        $display("[tb_osd_glyph_rom.v:157] FAIL watchdog：台架没跑完就超时");
        $finish;
    end
endmodule
