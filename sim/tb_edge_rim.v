`timescale 1ns/1ps
// tb_edge_rim —— 用户 2026-09-27 报的"左侧与上方边缘的像素条带仍然存在"：先量，再修。
//
// 为什么现有三把尺子看不见它：`tb_v98` 的 C2/C3/C4 判的是**位置**与**非黑**。rim 不是位置错、
// 也不是黑不黑，它是**值**的断层：`proc_box_blur.v` 的 border 旗标在最外圈**直接旁路滤波**
// （`dout <= p11`，原图直出），往里一格却是 3×3 平均 ⇒ 有纹理的画面上是一条轮廓线；
// 位置全对，所以那三把尺子全绿。
//
// 期望值按**定义**算（9 抽头平均；竖条纹时每个不同列正好重复 3 次 ⇒ 三列平均），
// 不抄 RTL 的 `*57>>9` 常数；容差 ±1（RTL 用 57/512 近似 1/9，是有意为之，见同文件 77 行）。
//
// ⚠ 对位不能靠标签：先**从数据里量出列滞后 `sh`**（在 0..5 里找让内部格最吻合定义的那个平移），
//   再用它评判边缘。为什么这样才算数：`#92 v2` 那一版判据在模块级绿、顶层红，就是因为对位
//   靠的是"标签到第几列"。这里允许平移由**被测对象自己**给出，而 R1 仍然可红（平移越界、
//   或没有任何平移能吻合定义 ⇒ 滤波根本没按定义做）。
// 判据：R0 采集完整性 / R1 内部 == 定义 / R2 第 0 列 == clamp-to-edge / R3 第 0 行 == clamp-to-edge。
// 今天 R2/R3 该红 —— 红才把"条带"钉成一个数；修完转绿才算修好。
`default_nettype none
module tb_edge_rim;
    localparam integer W = 64, H = 64;
    localparam [15:0] WHT = 16'hFFFF, BLK = 16'h0000;

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg         de;
    reg  [11:0] xs, ys;
    reg  [15:0] din;
    wire        de_o;
    wire [15:0] dout;

    integer mode;                               // 0 = 竖条纹（值随列变），1 = 横条纹（值随行变）

    proc_box_blur #(.H_ACTIVE(W)) u_dut (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0),
        .hs_in(1'b0), .vs_in(1'b0), .de_in(de), .x_in(xs), .y_in(ys), .din(din),
        .de_out(de_o), .dout(dout) );

    reg [15:0] out [0:H*W-1];
    integer ncap = 0, ndeo = 0;
    always @(posedge clk) if (de_o) begin
        if (ncap < H*W) begin out[ncap] = dout; ncap = ncap + 1; end
        ndeo = ndeo + 1;
    end

    function [15:0] pat; input integer x, y;
        begin pat = ((((mode == 0) ? x : y) & 1) ? BLK : WHT); end
    endfunction

    function [15:0] mean3; input [15:0] a, b, c;
        integer r, g, bl;
        begin
            r  = ({11'd0, a[15:11]} + {11'd0, b[15:11]} + {11'd0, c[15:11]} + 2) / 3;
            g  = ({10'd0, a[10:5]}  + {10'd0, b[10:5]}  + {10'd0, c[10:5]}  + 2) / 3;
            bl = ({11'd0, a[4:0]}   + {11'd0, b[4:0]}   + {11'd0, c[4:0]}   + 2) / 3;
            mean3 = {r[4:0], g[5:0], bl[4:0]};
        end
    endfunction

    function integer dev; input [15:0] got, expv;
        integer d, t;
        begin
            d = got[15:11] - expv[15:11]; if (d < 0) d = -d;
            t = got[10:5]  - expv[10:5];  if (t < 0) t = -t; if (t > d) d = t;
            t = got[4:0]   - expv[4:0];   if (t < 0) t = -t; if (t > d) d = t;
            dev = d;
        end
    endfunction

    task send_frame;
        integer x, y;
        begin
            for (y = 0; y < H; y = y + 1) begin
                for (x = 0; x < W; x = x + 1) begin
                    @(posedge clk); #1;
                    de = 1'b1; xs = x[11:0]; ys = y[11:0]; din = pat(x, y);
                end
                @(posedge clk); #1;
                de = 1'b0; din = 16'd0;                       // 行间隙：链子在这里补跳末列那一拍
                @(posedge clk); #1;
            end
            @(posedge clk); #1; de = 1'b0;
            repeat (30) @(posedge clk);                       // 排空
        end
    endtask

    // 内部格在**列平移 `s` 与行平移 `ro`** 下不吻合定义的格数。
    // 为什么要扫两个方向：3×3 的行窗口里"中心行"天然落后于当拍送进来的行（p0/p1 来自行缓存），
    // 而它的量我不能假定 —— 只能由被测对象自己给出（#92 v2 那一课：假定对位 = 造一把只能绿的尺子）。
    function integer interior_bad; input integer s, ro;
        integer j, i, k, b, c0, c1, c2;
        begin
            b = 0;
            for (j = 6; j < H; j = j + 1)
                for (i = 6; i < W-6; i = i + 1) begin
                    k = (j + ro)*W + (i + s);
                    if (k >= H*W) k = H*W - 1;
                    if (mode == 0) begin
                        c0 = i-1; c1 = i; c2 = i+1;
                        if (dev(out[k], mean3(pat(c0,j), pat(c1,j), pat(c2,j))) > 1) b = b + 1;
                    end else begin
                        if (dev(out[k], mean3(pat(i,j-1), pat(i,j), pat(i,j+1))) > 1) b = b + 1;
                    end
                end
            interior_bad = b;
        end
    endfunction

    integer i, j, k, s, ro, sh, rsh, bad0, bad1, bad2, bad3, n2, n3, d, bs, bsb;
    reg [15:0] e;

    initial begin
        de = 1'b0; xs = 0; ys = 0; din = 0; mode = 0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        bad0 = 0; bad1 = 0; bad2 = 0; bad3 = 0; n2 = 0; n3 = 0;

        for (mode = 0; mode < 2; mode = mode + 1) begin
            ncap = 0; ndeo = 0;
            send_frame(); send_frame(); send_frame();        // 第 2、3 帧才是稳态
            if (ncap < H*W || ndeo != 3*H*W) begin
                bad0 = 1;
                $display("R0 collect broken mode=%0d: capped=%0d de_out=%0d want 3x%0d", mode, ncap, ndeo, H*W);
            end
            sh = 0; rsh = 0; bsb = 1<<30;
            for (ro = 0; ro <= 3; ro = ro + 1)
                for (s = 0; s <= 5; s = s + 1) begin
                    bs = interior_bad(s, ro);
                    if (bs < bsb) begin sh = s; rsh = ro; bsb = bs; end
                end
            $display("MODE %0d: measured latency = (%0d columns, %0d rows); interior mismatch %0d of %0d there",
                     mode, sh, rsh, bsb, (H-6)*(W-12));
            if (bsb != 0) begin
                bad1 = 1;
                $display("FAIL R1 NO alignment in 0..5 x 0..3 makes the interior match the definition (bad=%0d)", bsb);
            end else $display("PASS R1 calibration trusted: interior == definition at (%0d,%0d)", sh, rsh);
            for (j = 6; j < H; j = j + 1) begin
                k = (j + rsh)*W + sh;                          // 中心 = 输入 (0,j) 的那一格
                if (mode == 0) begin
                    e = mean3(pat(0,j), pat(0,j), pat(1,j)); // 缺的左邻复制成第 0 列
                    d = dev(out[k], e); n2 = n2 + 1;
                    if (d > 1) begin
                        bad2 = bad2 + 1;
                        if (bad2 <= 3) $display("R2 rim (0,%0d): got=%h clamp-to-edge=%h raw-bypass=%h dev=%0d",
                                                j, out[k], e, pat(0,j), d);
                    end
                end
            end
            for (i = 6; i < W-6; i = i + 1) begin
                k = rsh*W + i + sh;                            // 中心 = 输入 (i,0) 的那一格
                if (mode == 1) begin
                    e = mean3(pat(i,0), pat(i,0), pat(i,1)); // 缺的上邻复制成第 0 行
                    d = dev(out[k], e); n3 = n3 + 1;
                    if (d > 1) begin
                        bad3 = bad3 + 1;
                        if (bad3 <= 3) $display("R3 rim (%0d,0): got=%h clamp-to-edge=%h raw-bypass=%h dev=%0d",
                                                i, out[k], e, pat(i,0), d);
                    end
                end
            end
        end

        if (bad0 == 0) $display("PASS R0 ruler integrity: 3 frames x %0d captured by de_out order", H*W);
        if (bad1 == 0) $display("PASS R1 interior == the definition at the measured column latency");
        if (bad2 == 0) $display("PASS R2 left column == clamp-to-edge (%0d rows)", n2);
        else           $display("FAIL R2 left column is NOT clamp-to-edge in %0d/%0d rows: it emits the raw bypassed pixel", bad2, n2);
        if (bad3 == 0) $display("PASS R3 top row == clamp-to-edge (%0d columns)", n3);
        else           $display("FAIL R3 top row is NOT clamp-to-edge in %0d/%0d columns: it emits the raw bypassed pixel", bad3, n3);

        if (bad0 == 0 && bad1 == 0 && bad2 == 0 && bad3 == 0) $display("RESULT tb_edge_rim PASS");
        else $display("RESULT tb_edge_rim FAIL bad0=%0d bad1=%0d bad2=%0d bad3=%0d", bad0, bad1, bad2, bad3);
        $finish;
    end
endmodule
`default_nettype wire
