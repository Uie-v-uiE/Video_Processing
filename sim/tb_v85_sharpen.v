`timescale 1ns/1ps
// 台架：src/rtl/process/proc_sharpen.v（级 2 的第二个算法：3×3 锐化 [0,-1,0;-1,5,-1;0,-1,0]）
//
// 为什么判据全用**竖直条纹**：两条行缓存的 3×3 窗口中心落在哪一行，与 proc_box_blur 是同一个
// 约定（tb_v84 已经用差分钉过：亮区掩码必须与 blur 完全重合）。竖直条纹在 y 方向是平移不变的，
// 于是"列"上的期望值与行对齐无关 ⇒ 判据既精确又不会被那个 ±1 行的约定牵住。
// 水平方向的偏移不是假设：T2 的平场判据要求逐位等于输入，任何列向错位都会立刻红。
//
// 四类必测：
//   ① 平场不动（5c − 4c = c，且没有溢出）—— 挡"锐化把整幅提亮/压暗"这种系数写错；
//   ② 边缘过冲（亮侧邻一个暗列 ⇒ 翻倍）；
//   ③ 上下钳位：R/B 钳到 31、**G 必须钳到 63**（G 是 6 bit，钳位写成 31 是最容易犯的截断错）；
//   ④ 旁路逐位等于输入 + 脉冲数等于像素数（延迟固定，与 bypass 无关）。
module tb_v85_sharpen;

    localparam W = 16, H = 8;

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg         bypass = 1;
    reg         de = 0;
    reg  [11:0] xs = 0, ys = 0;
    reg  [15:0] src = 0;
    wire        de_o;
    wire [15:0] d_o;

    proc_sharpen #(.H_ACTIVE(W)) dut (
        .clk(clk), .rst_n(rst_n), .bypass(bypass),
        .de_in(de), .x_in(xs), .y_in(ys), .din(src), .de_out(de_o), .dout(d_o)
    );
    // 对齐基准：与 proc_box_blur 的旁路逐位比（两个窗口级的旁路必须是同一种抽头约定，
    // 否则切换效果时画面会跳；约定本身的错位见 ISSUES #54）
    wire        de_ob;
    wire [15:0] d_ob;
    proc_box_blur #(.H_ACTIVE(W)) refb (
        .clk(clk), .rst_n(rst_n), .bypass(1'b1),
        .hs_in(1'b0), .vs_in(1'b0), .de_in(de), .x_in(xs), .y_in(ys), .din(src),
        .de_out(de_ob), .dout(d_ob)
    );
    reg [15:0] gotb [0:H-1][0:W-1];
    integer ki = 0, kj = 0;
    always @(posedge clk) if (de_ob && ki < H) begin
        gotb[ki][kj] = d_ob;
        kj = kj + 1;
        if (kj == W) begin kj = 0; ki = ki + 1; end
    end

    reg [15:0] field [0:H-1][0:W-1];
    reg [15:0] got   [0:H-1][0:W-1];
    integer fx, fy, oi, oj, errors = 0, n_p = 0, bad, i, j, v;

    always @(posedge clk) if (de_o && oi < H) begin
        n_p = n_p + 1;
        got[oi][oj] = d_o;
        oj = oj + 1;
        if (oj == W) begin oj = 0; oi = oi + 1; end
    end

    task chk;
        input [100*8:1] name;
        input cond;
        begin
            if (!cond) begin errors = errors + 1; $display("  FAIL %0s", name); end
        end
    endtask

    // 每段测试都跑**两帧**：第二帧才是采集帧。
    // 第一帧的作用是把上一段留下的行缓存冲掉 —— 3x3 窗口有两条行缓存，
    // 换一段激励后头两行读到的是上一帧的内容（T2 平场第一次就栽在这里：期望全帧不变，
    // 结果第二行带着上一段渐变的斜率）。这不是 DUT 的错，是台架忘了热身。
    task feed2;
        input bt;
        integer x, y;
        begin
            bypass = bt; oi = 0; oj = 0; ki = 0; kj = 0; n_p = 0;
            for (y = 0; y < H; y = y + 1) begin
                for (x = 0; x < W; x = x + 1) begin
                    @(negedge clk); xs = x; ys = y; src = field[y][x]; de = 1;
                end
                @(negedge clk); de = 0;
            end
            repeat (6) @(negedge clk);
            de = 0;
        end
    endtask

    task feed;
        input [1:0] m2;
        begin feed2(m2); feed2(m2); end
    endtask

    // 通道拆装（期望值由"图案的定义"算，不照抄 RTL 的先减后夹写法）
    function [15:0] px; input integer r; input integer g; input integer b;
        px = {r[4:0], g[5:0], b[4:0]};
    endfunction

    integer step_lit;                     // 台阶：x >= 8 为亮

    initial begin
        for (fy = 0; fy < H; fy = fy + 1)
            for (fx = 0; fx < W; fx = fx + 1) begin field[fy][fx] = 0; got[fy][fx] = 0; end
        rst_n = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        // ---------- T1 旁路必须与 blur 的旁路逐位相同（同一个中心抽头约定）----------
        for (fy = 0; fy < H; fy = fy + 1)
            for (fx = 0; fx < W; fx = fx + 1) field[fy][fx] = px(fx * 2, fx * 3, fx);
        feed(1'b1);
        bad = 0;
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1)
                if (got[j][i] !== gotb[j][i]) bad = bad + 1;
        chk("T1 旁路与 blur 的旁路逐位相同", bad == 0);
        if (bad) $display("     T1 不同的像素=%0d", bad);

        // ---------- T2 平场不动 ----------
        for (fy = 0; fy < H; fy = fy + 1)
            for (fx = 0; fx < W; fx = fx + 1) field[fy][fx] = px(6, 12, 6);
        feed(1'b0);
        bad = 0;
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1)
                if (got[j][i] !== px(6, 12, 6)) bad = bad + 1;
        chk("T2 平场锐化后逐位不变（5c-4c=c，且没有溢出）", bad == 0);
        if (bad) begin
            for (j = 0; j < H; j = j + 1) begin
                $write("     T2 r%0d ", j);
                for (i = 0; i < W; i = i + 1) $write("%h ", got[j][i]);
                $write("\n");
            end
        end

        // ---------- T3 竖直台阶：亮侧边缘过冲、暗侧被压到 0 ----------
        for (fy = 0; fy < H; fy = fy + 1)
            for (fx = 0; fx < W; fx = fx + 1)
                field[fy][fx] = (fx >= 8) ? px(6, 12, 6) : 16'h0000;
        feed(1'b0);
        // x=8 是第一列亮：四邻里左邻是暗，其余同列 ⇒ 5*6 − (6+6+6+0) = 12（正好翻倍）
        // 手算：R 5*6−(6+6+6+0)=12，G 5*12−(12*3)=24，B 同 R ⇒ px(12,24,12)
        chk("T3a 亮侧边缘列 x=8 过冲成 2 倍", got[4][8] === px(12, 24, 12));
        chk("T3b 亮侧内部 x=10 回到原值", got[4][10] === px(6, 12, 6));
        chk("T3c 暗侧贴边 x=7 被压到 0（不减成负数回绕）", got[4][7] === 16'h0000);
        // 整列扫一遍：亮侧不许出现比原值暗的、暗侧不许出现亮的
        bad = 0;
        for (j = 2; j < H - 1; j = j + 1)
            for (i = 10; i < W - 1; i = i + 1)
                if (got[j][i] !== px(6, 12, 6)) bad = bad + 1;
        chk("T3d 远离台阶的亮侧内部全部等于原值", bad == 0);

        // ---------- T4/T5 钳位：R/B 到 31、G 必须到 63 ----------
        for (fy = 0; fy < H; fy = fy + 1)
            for (fx = 0; fx < W; fx = fx + 1) field[fy][fx] = px(20, 40, 20);
        for (fy = 0; fy < H; fy = fy + 1)
            for (fx = 0; fx < 2; fx = fx + 1) field[fy][fx] = 16'h0000;   // 左两列暗，造大过冲
        feed(1'b0);
        // x=2 是第一列亮，左右邻：左暗右亮 → 5*20-(20+20+20+0)=40 > 31 ⇒ 钳到 31
        // G: 5*40-(40+40+40+0)=80 > 63 ⇒ 必须钳到 63（写成 31 就是 6 bit 当 5 bit 用的老错）
        v = got[4][2];
        chk("T4 R/B 过冲钳到满量程 31", v[15:11] === 5'd31 && v[4:0] === 5'd31);
        chk("T5 G 过冲钳到 6 bit 的满量程 63（不是 31）", v[10:5] === 6'd63);
        if (v[10:5] !== 6'd63) $display("     T5 实际 G=%0d 期望 63（整像素 %h）", v[10:5], v);

        // ---------- T6 锐化真的改了画面（反例：通路被旁路掉也会全绿）----------
        bad = 0;
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1)
                if (got[j][i] !== field[j][i]) bad = bad + 1;
        chk("T6 与输入不同的像素存在（挡「看着锐化了其实没接」）", bad > 0);

        // ---------- T7 延迟固定：脉冲数 = 像素数 ----------
        chk("T7 de_out 脉冲数等于像素数（延迟与 bypass 无关）", n_p == H * W);

        $display("");
        if (errors == 0) $display("PASS tb_v85_sharpen");
        else $display("FAIL tb_v85_sharpen errors=%0d", errors);
        $finish;
    end
endmodule
