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
    localparam integer X0 = 16, Y0 = 12, SC = 3, CW = 18, CH = 21, LG = 10, MC = 10;

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg [11:0] tx = 0, ty = 0;
    reg        tde = 0;
    wire [7:0] ro, go, bo;
    wire de_o, hs_o, vs_o;

    osd_overlay #(.X0(X0), .Y0(Y0), .SCALE(SC), .CHAR_W(CW), .CHAR_H(CH),
                  .LINE_GAP(LG), .MAX_CHARS(MC), .N_LINES(5)) u_osd (
        .clk(clk), .rst_n(rst_n), .x(tx), .y(ty), .de(tde),
        .angle(9'd0), .effect_en(5'd0), .fps(8'd0),
        .src_sel(1'b0), .eth_link(1'b1),
        .net_pkts(16'd0), .net_bad(16'd0),
        .net_drop(20'd0), .net_stall(16'd0), .bg_pix(16'h0),
        .r_in(8'd0), .g_in(8'd0), .b_in(8'd0), .hs_in(1'b0), .vs_in(1'b0),
        .r(ro), .g(go), .b(bo), .de_out(de_o), .hs_out(hs_o), .vs_out(vs_o)
    );

    // 改前语义（V7.9.3）：串行区间比较 + 减法。逐条照抄，不做"等价化简"。
    function [4:0] gold_glyph;
        input [7:0] c;
        begin
            if (c >= 8'h30 && c <= 8'h39)       gold_glyph = c - 8'h30;
            else if (c >= 8'h41 && c <= 8'h46)  gold_glyph = 5'd10 + (c - 8'h41);
            else if (c == 8'h47) gold_glyph = 5'd16;
            else if (c == 8'h4C) gold_glyph = 5'd21;
            else if (c == 8'h4E) gold_glyph = 5'd20;
            else if (c == 8'h4F) gold_glyph = 5'd18;
            else if (c == 8'h50) gold_glyph = 5'd22;
            else if (c == 8'h52) gold_glyph = 5'd17;
            else if (c == 8'h53) gold_glyph = 5'd24;
            else if (c == 8'h54) gold_glyph = 5'd19;
            else if (c == 8'h3D) gold_glyph = 5'd27;
            else                 gold_glyph = 5'd31;
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
        if (u_osd.gi === 5'd25) begin
            $display("FAIL 反向断言失效：'S' 竟然等于故意写错的 25");
            errors = errors + 1;
        end
        if (u_osd.gi !== 5'd24) begin
            $display("FAIL 'S' 既不等于 24 也不该等于别的：实得 %0d", u_osd.gi);
            errors = errors + 1;
        end
        release u_osd.ch;

        // 3) 非 ASCII 码点必须落到 31=空格（这是"字模表里没有的字母静默变空格"的老坑，
        //    改前改后都该成立；小写 a-z 不在表里）
        force u_osd.ch = 8'h73;                  // 's'（小写）
        #1;
        if (u_osd.gi !== 5'd31) begin
            $display("FAIL 小写 s 应该落到空格，实得 gi=%0d", u_osd.gi);
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
