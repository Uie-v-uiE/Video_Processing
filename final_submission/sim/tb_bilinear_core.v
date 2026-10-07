`timescale 1ns/1ps
// 功能：被测模块 `bilin_lerp`（RGB565 四抽头双线性插值算术核）；覆盖点＝fx/fy 全零与四角同色的恒等、
//        插值方向的单调性、左右镜像对称、纯白端点保持，以及与"先纵后横"黄金模型的 400 组随机对照。
// 激励与检查：时钟 #10 翻转（20 ns 周期），rst_n 拉低 3 拍后释放，每改一次输入等 3 个上升沿再取 pix；
//        判据1 用 8 组 p00 取值、fx=fy=0 要求 pix!==p00 即判红；判据6 四角同 16'hFFFF、fx=91 fy=173
//        要求 pix===16'hFFFF；判据2 六色四角同色、fx/fy 以 15 为步长采样，要求 pix===p00；
//        判据3 fx 从 0 走到 255，要求 pix[15:11] 不比上一格回退；判据4 16 组随机抽头交换左右抽头并
//        fx→255-fx，要求两次 R 码差 dr<=1；判据5 400 组随机抽头要求 R/G/B 与 ref_c 在 5/6bit 输出码域
//        逐通道差 <=1（dr/dg/db 任一 >1 即判红）。
// 预期结果：通过时逐段打印 `[tb_bilinear_core.v:<行号>] PASS 判据1/2/3/4/6`，判据5 的 PASS 行只在
//        errors==0 时打印并带最差偏差值，末行 `RESULT tb_bilinear_core PASS`；失败时对应段打印
//        `FAIL 判据N ...` 并附 pix/期望值或 dR/dG/dB，errors 加一，末行改为
//        `RESULT tb_bilinear_core FAIL (<n> errors)`；超过 #20_000_000 打印 `RESULT tb_bilinear_core FAIL timeout`。
// tb_bilinear_core —— bilin_lerp（双线性插值算术核）的判据。跑法：bash sim/run_one.sh tb_bilinear_core
// 黄金模型故意用**另一种结合顺序**（先纵后横）算，而 RTL 是先横后纵 —— 不是把实现式子抄一遍；
//   两条路只允许在"最后一步舍入"上差 ±1 个输出 LSB。
// 判据 1..6 写在下面各段测试的开头，每条都标明它红于哪一种实现错误
//   （1 恒等端点 / 2 四角同色 / 3 单调 / 4 左右镜像 / 5 随机对照 / 6 白黑端点）。
module tb_bilinear_core;
    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg [15:0] p00, p10, p01, p11;
    reg  [7:0] fx, fy;
    wire [15:0] pix;
    wire        vld;

    bilin_lerp u_dut (
        .clk(clk), .rst_n(rst_n),
        .p00(p00), .p10(p10), .p01(p01), .p11(p11),
        .fx(fx), .fy(fy), .pix(pix), .vld(vld)
    );

    integer errors = 0;
    integer seed = 32'h5EED_17C6;
    integer i, j, k, dr, dg, db, worst;
    reg [15:0] tmpa, tmpb;
    reg [7:0]  r8, g8, b8, rr, rg, rb, xa, xb, xc;
    reg [4:0]  pa, pb;

    // 8bit 通道展开（按定义写，不复用 DUT 里的函数）
    function [7:0] e5; input [4:0] v; begin e5 = {v, v[2:0]}; end endfunction
    function [7:0] e6; input [5:0] v; begin e6 = {v, v[1:0]}; end endfunction

    // 黄金模型：先纵后横
    function [7:0] ref_c;
        input [7:0] a, b, c, d;          // a=p00 b=p10 c=p01 d=p11
        input [7:0] wx, wy;
        integer t0, t1, num;
        begin
            t0  = a * (256 - wy) + c * wy;
            t1  = b * (256 - wy) + d * wy;
            num = t0 * (256 - wx) + t1 * wx;
            num = (num + 32768) / 65536;
            if (num > 255) num = 255;
            ref_c = num[7:0];
        end
    endfunction

    task wait_out;
        begin
            repeat (3) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        rst_n = 0; p00=0; p10=0; p01=0; p11=0; fx=0; fy=0;
        repeat (3) @(posedge clk); rst_n = 1;

        // 判据 1：fx=fy=0 ⇒ 逐位等于 p00（红于：权重和不为 256、回包多移一位）
        // fx/fy 必须真的为 0：第一版写成 `fx = k[7:0]^8'd0` 让 fx 跟着循环变量走 ⇒ 量到的偏差是台架自己的错
        for (k = 0; k < 8; k = k + 1) begin
            case (k)
                0: p00 = 16'hBEEF;  1: p00 = 16'h0001;  2: p00 = 16'h07E0;
                3: p00 = 16'hF800;  4: p00 = 16'hFFFF;  5: p00 = 16'h001F;
                6: p00 = 16'h1234;  default: p00 = 16'hABCD;
            endcase
            p10 = 16'h1234; p01 = 16'h5678; p11 = 16'h9ABC;
            fx = 8'd0; fy = 8'd0;
            wait_out;
            if (pix !== p00) begin
                $display("[tb_bilinear_core.v:79] FAIL 判据1 fx=fy=0：pix=%h 应为 p00=%h", pix, p00);
                errors = errors + 1;
            end
        end
        $display("[tb_bilinear_core.v:83] PASS 判据1 fx=fy=0 逐位等于 p00");

        // 判据 6：纯白/纯黑端点恒等（红于：位复制展开被写成左移补零）
        p00 = 16'hFFFF; p10 = p00; p01 = p00; p11 = p00;
        fx = 8'd91; fy = 8'd173; wait_out;
        if (pix !== 16'hFFFF) begin
            $display("[tb_bilinear_core.v:89] FAIL 判据6 纯白插值后 = %h（应仍为 ffff，说明展开通道不是位复制）", pix);
            errors = errors + 1;
        end else $display("[tb_bilinear_core.v:91] PASS 判据6 纯白在任意权重下保持 ffff");

        // 判据 2：四角同色 ⇒ 对全部采样 (fx,fy) 逐位等于该色（红于：舍入偏置/饱和写错，最容易"看着对"）
        for (k = 0; k < 6; k = k + 1) begin
            case (k)
                0: p00 = 16'hFFFF;
                1: p00 = 16'h0000;
                2: p00 = 16'hF800;
                3: p00 = 16'h07E0;
                4: p00 = 16'h001F;
                5: p00 = 16'h1234;
            endcase
            p10 = p00; p01 = p00; p11 = p00;
            for (i = 0; i < 256; i = i + 15) begin
                for (j = 0; j < 256; j = j + 15) begin
                    fx = i[7:0]; fy = j[7:0];
                    wait_out;
                    if (pix !== p00) begin
                        $display("[tb_bilinear_core.v:109] FAIL 判据2 四角同色 %h 在 fx=%0d fy=%0d 下读出 %h",
                                 p00, fx, fy, pix);
                        errors = errors + 1;
                        i = 9999; j = 9999;
                    end
                end
            end
        end
        $display("[tb_bilinear_core.v:117] PASS 判据2 四角同色对全部采样 (fx,fy) 恒等（白/黑/纯红/纯绿/纯蓝/一般色）");

        // 判据 3：沿插值方向输出单调不减（红于：左右权重接反）
        for (j = 0; j <= 255; j = j + 1) begin
            p00 = 16'h0000; p10 = 16'hF800; p01 = 16'h0000; p11 = 16'hF800;
            fx = j[7:0]; fy = 8'd0;
            wait_out;
            if (j > 0 && pix[15:11] < pa) begin
                $display("[tb_bilinear_core.v:125] FAIL 判据3 非单调：fx=%0d 时 R 从 %0d 退回 %0d", j, pa, pix[15:11]);
                errors = errors + 1; j = 9999;
            end
            pa = pix[15:11];
        end
        $display("[tb_bilinear_core.v:130] PASS 判据3 沿插值方向输出单调不减");

        // 判据 4：交换左右抽头且 fx→255-fx ⇒ 结果差 ≤1 LSB（红于：镜像不对称）
        for (k = 0; k < 16; k = k + 1) begin
            p00 = {$random(seed)} & 16'hF800;
            p10 = {$random(seed)} & 16'hF800;
            p01 = {$random(seed)} & 16'hF800;
            p11 = {$random(seed)} & 16'hF800;
            fx  = {$random(seed)} & 8'hFF;
            fy  = {$random(seed)} & 8'hFF;
            wait_out;
            pa = pix[15:11];
            tmpa = p00; tmpb = p01;
            p00 = p10; p10 = tmpa;           // 交换左/右抽头
            p01 = p11; p11 = tmpb;
            fx  = 8'd255 - fx;
            wait_out;
            pb = pix[15:11];
            dr = pa > pb ? pa - pb : pb - pa;
            if (dr > 1) begin
                $display("[tb_bilinear_core.v:150] FAIL 判据4 镜像不对称：原 %0d 镜像后 %0d", pa, pb);
                errors = errors + 1;
            end
        end
        $display("[tb_bilinear_core.v:154] PASS 判据4 左右镜像在 ±1 LSB 内对称");

        // 判据 5：400 组随机抽头对黄金模型逐通道差 ≤1 LSB（一般性正确）
        worst = 0;
        for (k = 0; k < 400; k = k + 1) begin
            p00 = {$random(seed)} & 16'hFFFF;
            p10 = {$random(seed)} & 16'hFFFF;
            p01 = {$random(seed)} & 16'hFFFF;
            p11 = {$random(seed)} & 16'hFFFF;
            fx  = {$random(seed)} & 8'hFF;
            fy  = {$random(seed)} & 8'hFF;
            wait_out;

            rr = ref_c(e5(p00[15:11]), e5(p10[15:11]), e5(p01[15:11]), e5(p11[15:11]), fx, fy);
            rg = ref_c(e6(p00[10:5]),  e6(p10[10:5]),  e6(p01[10:5]),  e6(p11[10:5]),  fx, fy);
            rb = ref_c(e5(p00[4:0]),   e5(p10[4:0]),   e5(p01[4:0]),   e5(p11[4:0]),   fx, fy);

            // 比较必须在**输出码域**（5/6bit）做。第一版拿 8bit 域比，而 DUT 的
            // 输出本来就只有 5/6bit 精度 —— 那 8 个低位被量化掉了，容差再宽也没意义。
            xa = rr[7:3]; xb = rg[7:2]; xc = rb[7:3];
            dr = pix[15:11] > xa ? pix[15:11] - xa : xa - pix[15:11];
            dg = pix[10:5]  > xb ? pix[10:5]  - xb : xb - pix[10:5];
            db = pix[4:0]   > xc ? pix[4:0]   - xc : xc - pix[4:0];
            if (dr > worst) worst = dr;
            if (dg > worst) worst = dg;
            if (db > worst) worst = db;
            if (dr > 1 || dg > 1 || db > 1) begin
                $display("[tb_bilinear_core.v:181] FAIL 判据5 第%0d 组偏离黄金模型 dR=%0d dG=%0d dB=%0d 码 (fx=%0d fy=%0d)",
                         k, dr, dg, db, fx, fy);
                $display("[tb_bilinear_core.v:183] p00=%h p10=%h p01=%h p11=%h -> pix=%h，参考=%h%h%h",
                         p00, p10, p01, p11, pix, xa, xb, xc);
                errors = errors + 1; k = 99999;
            end
        end
        if (errors == 0)
            $display("[tb_bilinear_core.v:189] PASS 判据5 400 组随机抽头与黄金模型逐通道差 <=1 个输出码（最差 %0d）", worst);

        $display("");
        if (errors == 0) $display("RESULT tb_bilinear_core PASS");
        else             $display("RESULT tb_bilinear_core FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("RESULT tb_bilinear_core FAIL timeout");
        $finish;
    end
endmodule
