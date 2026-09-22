`timescale 1ns/1ps
// tb_fb_rd5x —— 判"这条 5 槽读口产出的像素，确实是对应那一拍请求的像素"。
//
// 这个台架要防的不是插值算错（那是 tb_bilin_lerp 的活），而是**配准**：
// 左窗 1 次读 + 右窗 4 次读 + 2 级插值 + 侧带移位链，任何一处少打一拍，板上的现象就是
// "画面错开一列 / 切窗口时跳一下"，而这种错**不会让任何模块报错**，也只会在明早的屏上露出来。
//
// 四条独立性设计：
//  1. 期望值用 TB 里的实数（real）双线性公式算，走与 DUT 完全不同的代码路径；
//     容差只给 ±1 个 5bit 通道 LSB —— 拿去吸收定点舍入，不吸收"取错像素"。
//  2. 延迟不是写死的：在 0..20 里搜唯一能全对的平移量，并且**断言唯一性**
//     （两个不同的平移量都能对上 = 判据没牙）。搜到的值再和钉住的常数比，
//     以后谁在通路里加/减一拍，这里直接红，而不是"画面悄悄挪一列"。
//  3. 反向对照（teeth）：同一批样本拿**最近邻**去比必须大面积不通过（>50%），
//     否则说明容差松到"插不插值都算对"。
//  4. 左窗那条腿必须**逐位精确**（它没有插值，任何误差都是错的）。
//
// 台架卫生：标签 ASCII；两个时钟同相（clk 的每个沿都落在 clk5 的沿上），与 MMCM 的真实关系一致。
module tb_fb_rd5x;
    localparam IW = 512;
    localparam IH = 300;
    localparam NREQ = 160;
    localparam LAT_PIN = 6;              // 第一次跑出来的值钉在这儿，之后任何漂移都算回归

    reg clk = 0, clk5 = 0, rst_n = 0;
    always #10 clk  = ~clk;              // 20 ns 像素周期
    always #2  clk5 = ~clk5;             // 4 ns 快槽；t=20,40,... 两钟同沿

    reg         wr_en = 0;
    reg  [18:0] wr_addr = 0;
    reg  [63:0] wr_data = 64'd0;
    reg  [11:0] sx_l = 0, sy_l = 0, sx_r = 0, sy_r = 0;
    reg  [7:0]  fx_r = 0, fy_r = 0;
    reg         sel_right = 0;
    reg         bilin_en = 1;
    reg         oob_l = 0, oob_r = 0;
    wire [15:0] pix;
    wire        oob_out, right_out;

    fb_rd5x #(.IMG_W(IW), .IMG_H(IH)) u_dut (
        .clk(clk), .clk5x(clk5), .rst_n(rst_n),
        .wr_clk(clk5), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .sx_l(sx_l), .sy_l(sy_l), .sx_r(sx_r), .sy_r(sy_r), .fx_r(fx_r), .fy_r(fy_r),
        .bilin_en(bilin_en),
        .sel_right(sel_right), .oob_l(oob_l), .oob_r(oob_r),
        .pix(pix), .oob_out(oob_out), .right_out(right_out)
    );

    // ---------------- 图像模型（高频图案：双线性与最近邻必须明显不同） ----------------
    function [15:0] img;
        input [11:0] x;
        input [11:0] y;
        begin
            img = {(((x*7)  + (y*3))  & 5'h1f),
                   (((x*3)  + (y*5))  & 6'h3f),
                   (((x*11) + (y*13)) & 5'h1f)};
        end
    endfunction

    function [15:0] img4;                 // 字第 lane 个像素
        input [18:0] word;
        input [1:0]  lane;
        reg [18:0] n;
        begin
            n = word*4 + lane;
            img4 = img(n % IW, n / IW);
        end
    endfunction

    function [7:0] rep5f; input [4:0] v; begin rep5f = {v, v[2:0]}; end endfunction
    function [7:0] rep6f; input [5:0] v; begin rep6f = {v, v[1:0]}; end endfunction

    // 实数双线性 → RGB565。与 DUT 的定点实现无关（判据 1）。
    function [15:0] bilin_exp;
        input [11:0] x;
        input [11:0] y;
        input [7:0]  a;
        input [7:0]  b;
        real rx, gx, bx, u, v;
        reg [15:0] p00, p10, p01, p11;
        integer ir, ig, ib;
        begin
            p00 = img(x, y);          p10 = img(x + 1'b1, y);
            p01 = img(x, y + 1'b1);   p11 = img(x + 1'b1, y + 1'b1);
            u = a / 256.0;  v = b / 256.0;
            rx = (1.0-u)*(1.0-v)*rep5f(p00[15:11]) + u*(1.0-v)*rep5f(p10[15:11])
               + (1.0-u)*v*rep5f(p01[15:11])       + u*v*rep5f(p11[15:11]);
            gx = (1.0-u)*(1.0-v)*rep6f(p00[10:5])  + u*(1.0-v)*rep6f(p10[10:5])
               + (1.0-u)*v*rep6f(p01[10:5])        + u*v*rep6f(p11[10:5]);
            bx = (1.0-u)*(1.0-v)*rep5f(p00[4:0])   + u*(1.0-v)*rep5f(p10[4:0])
               + (1.0-u)*v*rep5f(p01[4:0])         + u*v*rep5f(p11[4:0]);
            ir = rx / 8.0 + 0.5;   ig = gx / 8.0 + 0.5;   ib = bx / 8.0 + 0.5;
            bilin_exp = { ir[4:0], ig[5:0], ib[4:0] };
        end
    endfunction

    // 逐通道最大差（LSB 个数）
    function [15:0] chan_diff;
        input [15:0] a;
        input [15:0] b;
        integer d1, d2, d3, m;
        begin
            d1 = a[15:11] - b[15:11]; if (d1 < 0) d1 = -d1;
            d2 = a[10:5]  - b[10:5];  if (d2 < 0) d2 = -d2;
            d3 = a[4:0]   - b[4:0];   if (d3 < 0) d3 = -d3;
            m = d1; if (d2 > m) m = d2; if (d3 > m) m = d3;
            chan_diff = m[15:0];
        end
    endfunction

    // ---------------- 请求表 ----------------
    integer  q;
    reg [11:0] r_x [0:NREQ-1], r_y [0:NREQ-1], l_x [0:NREQ-1], l_y [0:NREQ-1];
    reg [7:0]  r_fx [0:NREQ-1], r_fy [0:NREQ-1];
    reg        r_sel [0:NREQ-1], r_oob [0:NREQ-1], r_oobL [0:NREQ-1];
    reg        r_bilin [0:NREQ-1];
    reg [15:0] e_bil [0:NREQ-1], e_nn [0:NREQ-1], e_left [0:NREQ-1];

    // ---------------- 观测表：每拍收一次输出（与请求同节拍计数） ----------------
    localparam NOBS = NREQ + 24;
    reg [15:0] o_pix [0:NOBS-1];
    reg        o_sel [0:NOBS-1], o_oob [0:NOBS-1];
    integer    nobs = 0;

    always @(posedge clk) begin
        if (rst_n) begin
            o_pix[nobs] = pix;                       //  blocking：取的是本沿之前的值
            o_sel[nobs] = right_out;
            o_oob[nobs] = oob_out;
            if (nobs < NOBS) nobs = nobs + 1;
        end
    end

    // 请求由时钟驱动的计数器送出：第 k 个请求在 nobs=k 那一拍之后出现
    integer rk = 0;
    always @(posedge clk) begin
        if (!rst_n) rk <= 0;
        else begin
            rk <= rk + 1;
            if (rk < NREQ) begin
                sx_l <= l_x[rk];  sy_l <= l_y[rk];
                sx_r <= r_x[rk];  sy_r <= r_y[rk];
                fx_r <= r_fx[rk]; fy_r <= r_fy[rk];
                sel_right <= r_sel[rk];
                bilin_en <= r_bilin[rk];
                oob_l  <= r_oobL[rk];
                oob_r  <= r_oob[rk];
            end
        end
    end

    integer errors = 0;
    task chk;
        input [8*46:1] named;
        input ok;
        begin
            $display("[CHK] %-46s : %s", named, ok ? "OK" : "BAD");
            if (!ok) errors = errors + 1;
        end
    endtask

    integer found, cand, nzero, i, j, nbad, nbil, nnear, nleft, nflag, ncmp, far, nnoff, noffbad;
    reg [15:0] got;

    initial begin
        for (q = 0; q < NREQ; q = q + 1) begin
            r_x[q]  = (q * 37) % (IW - 2);
            r_y[q]  = (q * 53) % (IH - 2);
            r_fx[q] = (q * 251 + 11) % 256;
            r_fy[q] = (q * 97  + 77) % 256;
            l_x[q]  = (q * 91) % IW;
            l_y[q]  = (q * 7)  % IH;
            r_sel[q] = (q % 4 != 0);                  // 3/4 右窗、1/4 左窗
            r_bilin[q] = (q % 5 != 4);                // 每 5 个请求关掉一次 ⇒ 同一条通路的退化档也被判
            r_oob[q] = (q % 17 == 0);
            r_oobL[q]= (q % 3 == 0);
            e_bil[q]  = bilin_exp(r_x[q], r_y[q], r_fx[q], r_fy[q]);
            e_nn[q]   = img(r_x[q], r_y[q]);
            e_left[q] = img(l_x[q], l_y[q]);
        end

        // ---- 走 DUT 自己的写口灌一张图（38400 个 64bit 字）----
        for (j = 0; j < (IW*IH)/4; j = j + 1) begin
            @(negedge clk5);
            wr_en = 1'b1;  wr_addr = j;
            wr_data = {img4(j,2'd3), img4(j,2'd2), img4(j,2'd1), img4(j,2'd0)};
        end
        @(negedge clk5); wr_en = 1'b0;

        @(negedge clk);  rst_n = 1;
        repeat (NREQ + 22) @(posedge clk);
        #1;

        // ---- 搜平移量 ----
        nzero = 0; found = -1;
        for (cand = 0; cand <= 20; cand = cand + 1) begin
            nbad = 0;
            for (i = 6; i < NREQ - 2; i = i + 1) begin
                if (i + cand >= nobs) nbad = nbad + 1;
                else if (o_sel[i+cand] !== r_sel[i] || o_oob[i+cand] !== (r_sel[i] ? r_oob[i] : r_oobL[i]))
                     nbad = nbad + 1;
            end
            if (nbad == 0) begin
                nzero = nzero + 1;
                if (found < 0) found = cand;
            end
        end
        $display("[INFO] alignment candidates found=%0d first=%0d", nzero, found);
        chk("shift is unique (two matches would mean no teeth)", nzero == 1);
        chk("measured LAT equals pinned value", found == LAT_PIN);

        // ---- 逐样本比对 ----
        nbil = 0; nnear = 0; nleft = 0; nflag = 0; ncmp = 0; far = 0; nnoff = 0; noffbad = 0;
        for (i = 6; i < NREQ - 2; i = i + 1) begin
            if (i + found >= nobs) begin nflag = nflag + 1; i = NREQ; end
            else begin
                ncmp = ncmp + 1;
                if (o_sel[i+found] !== r_sel[i]) nflag = nflag + 1;
                if (r_sel[i]) begin
                    got = o_pix[i+found];
                    if (r_bilin[i]) begin
                        if (chan_diff(got, e_bil[i]) > 16'd1) begin
                            if (nbil < 6)
                                $display("[DIAG] bil mismatch i=%0d got=%h exp=%h nn=%h",
                                         i, got, e_bil[i], e_nn[i]);
                            nbil = nbil + 1;
                        end
                        if (chan_diff(e_bil[i], e_nn[i]) > 16'd1) far = far + 1;
                        if (chan_diff(got, e_nn[i]) <= 16'd1) nnear = nnear + 1;
                    end else begin
                        // bilin_en=0：同一条通路必须**逐位**等于最近邻（fx=fy=0 时 lerp 恒等 p00）
                        nnoff = nnoff + 1;
                        if (got !== e_nn[i]) begin
                            if (noffbad < 6)
                                $display("[DIAG] bilin_off mismatch i=%0d got=%h exp(nn)=%h",
                                         i, got, e_nn[i]);
                            noffbad = noffbad + 1;
                        end
                    end
                end else if (o_pix[i+found] !== e_left[i]) begin
                    if (nleft < 6)
                        $display("[DIAG] left mismatch i=%0d got=%h exp=%h",
                                 i, o_pix[i+found], e_left[i]);
                    nleft = nleft + 1;
                end
            end
        end
        $display("[INFO] ncmp=%0d err_bil=%0d err_left=%0d err_flag=%0d near_miss=%0d far=%0d bilinoff=%0d err_off=%0d",
                 ncmp, nbil, nleft, nflag, nnear, far, nnoff, noffbad);
        chk("samples compared", ncmp > 100);
        chk("BILIN=0 degenerate path exercised", nnoff > 15);
        chk("BILIN=0 output is bit-exact nearest", noffbad == 0);
        chk("right pane == bilinear model (+/-1 LSB)", nbil == 0);
        chk("left pane  == nearest model (bit exact)", nleft == 0);
        chk("right_out/oob_out aligned with pix", nflag == 0);
        chk("teeth: bilinear != nearest on >50% samples", far * 2 > ncmp);
        chk("teeth: output is not the nearest pixel", nnear * 4 < far);

        if (errors == 0) $display("RESULT tb_fb_rd5x PASS");
        else             $display("RESULT tb_fb_rd5x FAIL (%0d bad)", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("RESULT tb_fb_rd5x FAIL timeout");
        $finish;
    end
endmodule
