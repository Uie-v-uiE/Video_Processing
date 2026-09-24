`timescale 1ns/1ps
// tb_v794_osd_glyph —— V7.9.4 那次"把 glyph_idx 从串行区间比较改成并行 case"的差分判据。
//
// 要防的事：译码改动**只可能**改到"某个 ASCII 落到哪个字形号"，而字形号错了在屏幕上的表现是
// 换一个字母（S 变 5、P 变 D 之类），肉眼在 1024×600 的小字上很难立刻发现。所以这里不抽样、
// 不靠渲染，而是把**全部 256 个码点**逐个塞进被改的那一级（`force` RTL 里的 `ch` 这根线），
// 读 RTL 自己算出来的 `gi`，和 TB 里**按改前语义独立重写**的黄金函数逐项比。
// 黄金函数就是 V7.9.3 那串 if/else 的形状（含减法），不是我重新理解的"应该是什么"——
// 这样"改前后等价"这件事是被测出来的，不是我声称的。
module tb_v794_osd_glyph;
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
        .zoom_code(3'd4), .zoom_auto(1'b0),
        .split_pct(8'd50), .split_auto(1'b0),
        .lat_ms(16'd0), .lat_ok(1'b0),
        .src_eff(2'b11), .mode(2'b00), .bg_pix(16'h0),
        .r_in(8'd0), .g_in(8'd0), .b_in(8'd0), .hs_in(1'b0), .vs_in(1'b0),
        .r(ro), .g(go), .b(bo), .de_out(de_o), .hs_out(hs_o), .vs_out(vs_o)
    );

    // 黄金表：**按 §7d / glyphs_draft 那张号表独立抄一遍**（不是从 RTL 里 copy 出来的），
    // 谁改了 RTL 的 case 而没改这张表，这里就红。
    // V7.9.3 的"改前语义"仍然成立（0x30..0x39、0x41..0x46、大写若干、* 与 =），
    // V8-5 只是往表里**加**码点：小写 16 个、: . % ( ) ° -、大写 Z。空格的号从 31 挪到 63。
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
            else if (c == 8'h2A) gold_glyph = 6'd26;   // *
            else if (c == 8'h3D) gold_glyph = 6'd27;   // =
            else if (c == 8'h3A) gold_glyph = 6'd44;   // :
            else if (c == 8'h2E) gold_glyph = 6'd45;   // .
            else if (c == 8'h25) gold_glyph = 6'd46;   // %
            else if (c == 8'h28) gold_glyph = 6'd47;   // (
            else if (c == 8'h29) gold_glyph = 6'd48;   // )
            else if (c == 8'hDF) gold_glyph = 6'd49;   // °（Latin-1）
            else if (c == 8'h2D) gold_glyph = 6'd52;   // -（Latency 的 `--`）
            // V8-5 的十六个小写：号按草稿走（28..43 里挑出来的那 15 个 + h 接在 51）
            else if (c == 8'h61) gold_glyph = 6'd28;   // a
            else if (c == 8'h63) gold_glyph = 6'd29;   // c
            else if (c == 8'h65) gold_glyph = 6'd30;   // e
            else if (c == 8'h68) gold_glyph = 6'd51;   // h
            else if (c == 8'h69) gold_glyph = 6'd32;   // i
            else if (c == 8'h6C) gold_glyph = 6'd33;   // l
            else if (c == 8'h6D) gold_glyph = 6'd34;   // m
            else if (c == 8'h6E) gold_glyph = 6'd35;   // n
            else if (c == 8'h6F) gold_glyph = 6'd36;   // o
            else if (c == 8'h70) gold_glyph = 6'd37;   // p
            else if (c == 8'h72) gold_glyph = 6'd38;   // r
            else if (c == 8'h73) gold_glyph = 6'd39;   // s
            else if (c == 8'h74) gold_glyph = 6'd40;   // t
            else if (c == 8'h75) gold_glyph = 6'd41;   // u
            else if (c == 8'h78) gold_glyph = 6'd42;   // x
            else if (c == 8'h79) gold_glyph = 6'd43;   // y
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
            $display("FAIL 只比对了 %0d/256 个码点", n_hit);
            errors = errors + 1;
        end

        // 2) 判据本身要有牙：拿一个**故意写错**的期望值去比 RTL，必须判为"不等"。
        //    （如果连错的期望值都能比"过"，说明 1) 那 256 次比对是恒真式、等于没测）
        force u_osd.ch = 8'h53;                  // 'S'，真值应是 24
        #1;
        if (u_osd.gi === 6'd25) begin
            $display("FAIL 反向断言失效：'S' 竟然等于故意写错的 25");
            errors = errors + 1;
        end
        if (u_osd.gi !== 6'd24) begin
            $display("FAIL 'S' 既不等于 24 也不该等于别的：实得 %0d", u_osd.gi);
            errors = errors + 1;
        end
        release u_osd.ch;

        // 3) **不在表里的码点**必须落到 63=空格（老规矩，号从 31 挪到 63）。
        //    这里挑 'b'：四行 OSD 里没有这个字母，所以它没画字模 —— 若哪天格式里冒出 'b'，
        //    它会静默变空格（屏上少一笔），届时这条判据仍然是绿的，抓它的是
        //    tb_osd_lines 的"整屏不许有看不见的字母"那条。
        force u_osd.ch = 8'h62;                  // 'b'
        #1;
        if (u_osd.gi !== 6'd63) begin
            $display("FAIL 未画的 b 应该落到空格 63，实得 gi=%0d", u_osd.gi);
            errors = errors + 1;
        end
        release u_osd.ch;

        // 3b) 号挪过位置的那些码点，逐个钉一次（空格从 31→63 最容易改漏：
        //     改了的 RTL、没改的默认分支 = 全屏幕是 0）
        force u_osd.ch = 8'h20;                  // 空格本身
        #1;
        if (u_osd.gi !== 6'd63) begin
            $display("FAIL 空格 20 应落到 63，实得 %0d", u_osd.gi);
            errors = errors + 1;
        end
        release u_osd.ch;
        force u_osd.ch = 8'h30;                  // '0' 与"空格 31"这对老号不能再混
        #1;
        if (u_osd.gi !== 6'd0) begin
            $display("FAIL '0' 应落到 0，实得 %0d", u_osd.gi);
            errors = errors + 1;
        end
        release u_osd.ch;

        if (errors == 0) $display("PASS tb_v794_osd_glyph");
        else             $display("FAIL tb_v794_osd_glyph errors=%0d", errors);
        $finish;
    end

    initial begin
        #200_000;                                  // 60 µs 量级就够（没有长流水线）
        $display("FAIL watchdog：台架没跑完就超时");
        $finish;
    end
endmodule
