`timescale 1ns/1ps
// tb_head_rot_displace —— #167 里**映射这一半**的那把尺子：旋转态下"上一帧的角度"与"这一帧的角度"
// 会把画面挪开多少源像素。它**不判**"帧头到底吃了哪一帧"（那是顶层台架 `C5c` 判的，凭据
// build/tb_v98_report.txt 与 build/evidence/r104_c5head_band.txt），它量的是**后果的大小**——
// 正是 2026-10-02 早上眼睛答不出来的那一档（"1 档与 7 档看不出差"），因为那一档眼睛饱和在可见阈之上。
//
// 与 #162 同一套规矩：**只用 DUT 自己的输出**（`zoom_mapper` 的 `x_out/y_out/oob` 与 `zoom_fit` 的
// `inv_fit`），不在外面重算正/逆映射、不重抄那张 Q8 三角表 ⇒ 位移这个数是 RTL 的算术给的，不是我算的。
// （2026-10-01 23:15 我在 RTL 外面建模判"角点出屏"报了假阳性，错在格心/格角约定与 RTL 不一致。）
//
// 判据三条（差分对 + 地板）：
//   D1 **k=0 对照**：同一个角度扫两遍，帧顶带内每一格的 `xo/yo/oob` 必须逐位相同（位移 0、越界位不变）。
//      这条说明"差出来的东西是角度步造成的"，不是台架自己在漂；它与 D2 共用同一批数据，
//      所以 D2 若在 k=1 也报"0 格移动"，就是尺子坏了（那条按红计）。
//   D2 **k>=1 有位移**：第二遍用"上一帧角度" θ-k（`inv_fit` 也跟着换成 θ-k 那一档，与顶层一致：
//      inv 是角度算出来的），带内 `oob=0` 的格必须至少有一格移动 >= 1 个源像素，并把
//      k -> 最大/最小/平均位移与"越界位翻转的格数"印出来（这张表取代那句"看不出差"）。
//   D3 **地板 + 不许空判**：每档两遍扫到的格数必须等于带内格数 x 2，且带内至少有一格有效；
//      一个有效格都没有时按红计并明说"无可判"（"空判据恒绿"那一族）。
//
// 带为什么取视口行 0..3：顶层那 6 个**显示**行的帧头窗（`OFF_LINES` 4 + `BILIN_ROWS` 2）在 mapper 这边
// 每两个显示行对一个视口行（屏 1024 列 = 2 x 512），0..3 这 4 个视口行盖住 0..7 共 8 个显示行，
// 把 6 行窗口整个包进去还多留 2 行余量。**这句是口径声明，不是判据**——"到底哪几行吃了上一帧"由 C5c 判。
module tb_head_rot_displace;
    localparam integer W = 512, H = 300;
    localparam integer BAND = 4;                 // 视口行 0..BAND-1（盖住屏顶 8 个显示行）
    localparam integer NK  = 4;                  // k = 0/1/2/7 度每帧
    localparam integer NA  = 3;                  // 基准角三档：45 / 60 / 168

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg  [8:0] angle = 9'd0;
    wire [9:0] inv_fit;
    zoom_fit #(.IMAGE_W(W), .IMAGE_H(H)) u_fit (
        .clk(clk), .rst_n(rst_n), .angle(angle), .inv_fit(inv_fit)
    );

    reg        rot_en = 1'b1;
    reg [9:0]  inv_force = 10'd256;
    reg [11:0] x_in = 0, y_in = 0;
    wire [11:0] xo, yo;
    wire        oobo;
    wire [7:0]  fx, fy;
    zoom_mapper #(.IMAGE_W(W), .IMAGE_H(H)) u_map (
        .clk(clk), .rst_n(rst_n),
        .inv_scale(inv_force), .angle(angle), .rotate_en(rot_en),
        .x_in(x_in), .y_in(y_in),
        .x_out(xo), .y_out(yo), .oob(oobo), .frac_x(fx), .frac_y(fy)
    );

    integer errors = 0, nD1_red = 0, nD2_red = 0, nD3_red = 0;
    integer k_list [0:NK-1];
    integer a_list [0:NA-1];
    // ⚠ 计数器一律由**调用方**清零：在 task 里清零会把第一遍攒下的 swept/live1 抹掉，
    //   于是 D3 那条地板变成"永远不等"（第一版就是这么写的，抄回来时读才发现）。
    integer px [0:W*BAND-1], py [0:W*BAND-1], poob [0:W*BAND-1];
    integer ki, ai, i, j, idx, ncell;
    integer swept, live1, live2, diffcell, oobchg, maxd, sumd, mind;
    integer sx, sy, dx, dy, d, inv_now, inv_prev;

    task sweep_band;                 // want_store=1 记进数组；=0 与数组逐格比
        input integer want_store;
        integer ii, jj;
        begin
            for (ii = 0; ii < BAND; ii = ii + 1) begin
                for (jj = 0; jj < W; jj = jj + 1) begin
                    x_in = jj[11:0]; y_in = ii[11:0];
                    @(posedge clk); @(posedge clk); @(posedge clk);   // mapper 深度留 3 拍余量（同 #162）
                    idx = ii * W + jj;
                    swept = swept + 1;
                    if (want_store) begin
                        px[idx] = xo; py[idx] = yo; poob[idx] = oobo;
                        if (!oobo) live1 = live1 + 1;
                    end else begin
                        if (!oobo) live2 = live2 + 1;
                        if (oobo !== poob[idx]) begin
                            oobchg = oobchg + 1;
                        end else if (!oobo && !poob[idx]) begin
                            sx = xo; sy = yo;
                            dx = sx - px[idx]; if (dx < 0) dx = -dx;
                            dy = sy - py[idx]; if (dy < 0) dy = -dy;
                            d = dx; if (dy > d) d = dy;
                            if (d > 0) begin
                                diffcell = diffcell + 1;
                                sumd = sumd + d;
                                if (d < mind) mind = d;
                            end
                            if (d > maxd) maxd = d;
                        end
                    end
                end
            end
        end
    endtask

    initial begin
        k_list[0] = 0; k_list[1] = 1; k_list[2] = 2; k_list[3] = 7;
        a_list[0] = 45; a_list[1] = 60; a_list[2] = 168;

        rst_n = 0; repeat (6) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);
        ncell = W * BAND;

        for (ai = 0; ai < NA; ai = ai + 1) begin
            for (ki = 0; ki < NK; ki = ki + 1) begin
                swept = 0; live1 = 0; live2 = 0; diffcell = 0; oobchg = 0;
                maxd = 0; sumd = 0; mind = 4096;

                // 第一遍：当帧角度 θ 与它自己那档 inv_fit
                angle = a_list[ai][8:0];
                repeat (6) @(posedge clk);
                inv_now = inv_fit;
                sweep_band(1);
                // 第二遍：上一帧角度 θ-k 与它自己那档 inv_fit
                angle = ((a_list[ai] - k_list[ki]) + 360) % 360;
                repeat (6) @(posedge clk);
                inv_prev = inv_fit;
                sweep_band(0);

                if (swept != ncell * 2 || (live1 == 0 && live2 == 0)) begin
                    $display("FAIL D3 floor ang=%0d k=%0d swept=%0d expect=%0d live1=%0d live2=%0d（带内无可判的格）",
                             a_list[ai], k_list[ki], swept, ncell * 2, live1, live2);
                    errors = errors + 1; nD3_red = nD3_red + 1;
                end

                if (k_list[ki] == 0) begin
                    if (diffcell != 0 || oobchg != 0) begin
                        $display("FAIL D1 same-angle sweeps differ ang=%0d diff=%0d oobchg=%0d expect=0/0",
                                 a_list[ai], diffcell, oobchg);
                        errors = errors + 1; nD1_red = nD1_red + 1;
                    end else begin
                        $display("PASS D1 k=0 对照 ang=%0d inv=%0d 带内有效格=%0d 两遍逐位相同（台架自己不漂）",
                                 a_list[ai], inv_now, live1);
                    end
                end else begin
                    if (diffcell == 0 || maxd < 1) begin
                        $display("FAIL D2 no displacement ang=%0d k=%0d diff=%0d maxd=%0d expect>=1 格且>=1px",
                                 a_list[ai], k_list[ki], diffcell, maxd);
                        errors = errors + 1; nD2_red = nD2_red + 1;
                    end else begin
                        $display("PASS D2 ang=%0d k=%0d inv %0d->%0d 有效格=%0d 移动格=%0d 最大位移=%0d 最小=%0d 平均=%0d.%0d 越界位翻转=%0d",
                                 a_list[ai], k_list[ki], inv_now, inv_prev, live2, diffcell, maxd, mind,
                                 sumd / diffcell, (sumd % diffcell) * 10 / diffcell, oobchg);
                    end
                end
            end
        end

        if (nD1_red == 0 && nD2_red == 0 && nD3_red == 0 && errors == 0) begin
            $display("RESULT tb_head_rot_displace PASS cells=%0d pairs=%0d k=%0d..%0d",
                     ncell * 2 * NA * NK, NA * NK, k_list[1], k_list[NK-1]);
        end else begin
            $display("RESULT tb_head_rot_displace FAIL errors=%0d D1=%0d D2=%0d D3=%0d",
                     errors, nD1_red, nD2_red, nD3_red);
        end
        $finish;
    end
endmodule
