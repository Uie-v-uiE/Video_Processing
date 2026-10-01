`timescale 1ns/1ps
// tb_zoom_fit_corners —— #162（E4/#93 的机器替身）：旋转 + 拟合时**源图四角是不是真的还在屏上**。
//
// 为什么要在台架里判、而不是在外面算一遍：2026-10-01 23:15 那一节里我用 node 在 RTL 外面建模判"角点出屏"，
// 报了个假阳性——错在**我用的格心/格角约定与 RTL 不一致**（差半格到一格）。教训写死在这里：
// 这台架**只用 DUT 自己的输出**（`zoom_mapper` 的 `x_out/y_out/oob` 与 `zoom_fit` 的 `inv_fit`），
// 不在外面重算正/逆映射，也不抄那张 Q8 三角表之外的第二份真值。
//
// 判据两条（两端夹逼）：
//   A **装得下**：取 `zoom_fit` 给出的 `inv_fit`，把整个显示窗（512×300 个视口格）喂给 `zoom_mapper`，
//     那么源图的四个角 `(0,0) (W-1,0) (0,H-1) (W-1,H-1)` 每一个都必须被某个 `oob=0` 的显示格取到。
//     ⇒ 这就是"旋到哪个角度就缩到刚好整个画面还在屏里"的可执行版本：角点被裁掉就是没装下。
//   B **正对照**（这条判据必须能红）：把倍率故意放大一档（`inv = inv_fit - 1`，即比"刚好"更大一点），
//     旋转框就会溢出视口 ⇒ 至少有一个源角**不再**被任何 `oob=0` 的显示格取到。
//     B 不成立就说明 A 是恒真的摆设（"空判据恒绿"那一族）。
//
// 覆盖地板（两条都印）：扫到的格数、`oob=0` 的格数、A 每角命中几个角、B 每角掉了几个角——
// 少一个数量级就是尺子坏了，不是设计好了。
module tb_zoom_fit_corners;
    localparam integer W = 512, H = 300;
    localparam integer NANG = 6;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;                    // 100 MHz 像素域的节拍

    reg  [8:0]  angle = 9'd0;
    wire [9:0]  inv_fit;
    zoom_fit #(.IMAGE_W(W), .IMAGE_H(H)) u_fit (
        .clk(clk), .rst_n(rst_n), .angle(angle), .inv_fit(inv_fit)
    );

    reg         rot_en = 1'b1;
    reg  [9:0]  inv_force = 10'd256;
    reg  [11:0] x_in = 0, y_in = 0;
    wire [11:0] xo, yo;
    wire        oobo;
    wire [7:0]  fx, fy;

    zoom_mapper #(.IMAGE_W(W), .IMAGE_H(H)) u_map (
        .clk(clk), .rst_n(rst_n),
        .inv_scale(inv_force), .angle(angle), .rotate_en(rot_en),
        .x_in(x_in), .y_in(y_in),
        .x_out(xo), .y_out(yo), .oob(oobo), .frac_x(fx), .frac_y(fy)
    );

    integer ang_list [0:NANG-1];
    integer a, i, j, k;
    integer swept, live;                     // 覆盖地板
    integer strictA, strictB;
    integer exminx, exmaxx, exminy, exmaxy, ehit0, ehit1;
    integer bxminx, bxmaxx, bxminy, bxmaxy, bhit0, bhit1;
    integer seenA, seenB;                    // 本角度里 A / B 各命中几个源角
    integer errors = 0;
    integer sx, sy;                              // 比较一律走这条路：无符号位向量与 integer 混比会被转成无符号
    integer nA_red = 0, nB_red = 0;

    // 扫一遍整个显示窗，数出"四个源角各有没有被 oob=0 的格取到"
    task sweep;
        input [9:0] inv;
        output integer corners;
        output integer nswept;
        output integer nlive;
        output integer ominx, omaxx, ominy, omaxy, ohit0, ohitM;
        integer c0, c1, c2, c3;
        begin
            corners = 0; c0 = 0; c1 = 0; c2 = 0; c3 = 0; nswept = 0; nlive = 0;
            ominx = W; omaxx = 0; ominy = H; omaxy = 0; ohit0 = 0; ohitM = 0;
            inv_force = inv;                       // ← 少了这一行的话 A/B 两遍扫的是同一个倍率（第一版就犯了这个）
            @(posedge clk); @(posedge clk); @(posedge clk);
            for (i = 0; i < H; i = i + 1) begin
                for (j = 0; j < W; j = j + 1) begin
                    x_in = j[11:0]; y_in = i[11:0];
                    @(posedge clk); @(posedge clk); @(posedge clk);   // mapper 的深度留 3 拍余量
                    nswept = nswept + 1;
                    if (!oobo) begin
                        nlive = nlive + 1;
                        sx = xo; sy = yo;
                        if (omaxy == 0 && nlive == 1) begin omaxx = sx; omaxy = sy; end
                        if (sx < ominx) ominx = sx;
                        if (sx > omaxx) omaxx = sx;
                        if (sy < ominy) ominy = sy;
                        if (sy > omaxy) omaxy = sy;
                        if (xo == 0 || yo == 0) ohit0 = ohit0 + 1;
                        if (xo == W-1 || yo == H-1) ohitM = ohitM + 1;
                        // 角点原像一般不落在那个整数格上（显示格是整数、映射是定点）⇒ 判"离角点 ≤1 格"
                        if (xo <= 1  && yo <= 1)                      c0 = 1;
                        if (xo >= W-2 && yo <= 1)                     c1 = 1;
                        if (xo <= 1  && yo >= H-2)                    c2 = 1;
                        if (xo >= W-2 && yo >= H-2)                   c3 = 1;
                        strictA = strictA + ((xo == 0 && yo == 0) || (xo == W-1 && yo == 0)
                           || (xo == 0 && yo == H-1) || (xo == W-1 && yo == H-1));
                    end
                end
            end
            corners = c0 + c1 + c2 + c3;
        end
    endtask

    initial begin
        ang_list[0] = 0;  ang_list[1] = 30;  ang_list[2] = 45;
        ang_list[3] = 60; ang_list[4] = 90;  ang_list[5] = 270;

        rst_n = 0; repeat (6) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);

        for (a = 0; a < NANG; a = a + 1) begin
            angle = ang_list[a][8:0];
            repeat (6) @(posedge clk);                 // zoom_fit 是两拍流水线 + 余量
            if (inv_fit < 10'd256) begin
                $display("FAIL fit_below_identity angle=%0d inv_fit=%0d", angle, inv_fit);
                errors = errors + 1;
            end
            sweep(inv_fit,         seenA, swept, live, exminx, exmaxx, exminy, exmaxy, ehit0, ehit1);
            sweep(10'd256,         seenB, swept, live, bxminx, bxmaxx, bxminy, bxmaxy, bhit0, bhit1);
            // 地板：扫到的格数必须是 2 遍整窗（A 与 B 各一遍）
            if (swept != W * H) begin
                $display("FAIL floor_swept angle=%0d swept=%0d expect=%0d", angle, swept, W * H);
                errors = errors + 1;
            end else if (live <= 0) begin
                $display("FAIL floor_live_zero angle=%0d", angle);
                errors = errors + 1;
            end
            // A：四个源角都必须还在屏里
            if (seenA != 4) begin
                $display("FAIL A_clipped angle=%0d inv_fit=%0d corners_seen=%0d expect=4", angle, inv_fit, seenA);
                errors = errors + 1; nA_red = nA_red + 1;
            end
            // B：放大一档之后必须至少掉一个角，否则 A 是摆设
            if (angle != 0 && seenB >= 4) begin
                $display("FAIL B_no_teeth angle=%0d no-fit(1.00x) corners_seen=%0d expect<4", angle, seenB);
                errors = errors + 1; nB_red = nB_red + 1;
            end
            $display("PASS cov angle=%0d inv_fit=%0d swept=%0d A_corners=%0d B_corners=%0d A_srcx=%0d..%0d A_srcy=%0d..%0d",
                     angle, inv_fit, swept, seenA, seenB, exminx, exmaxx, exminy, exmaxy);
        end

        if (nA_red == 0 && nB_red == 0 && errors == 0) begin
            $display("RESULT tb_zoom_fit_corners PASS");
        end else begin
            $display("RESULT tb_zoom_fit_corners FAIL errors=%0d A_red=%0d B_red=%0d", errors, nA_red, nB_red);
        end
        $finish;
    end
endmodule
