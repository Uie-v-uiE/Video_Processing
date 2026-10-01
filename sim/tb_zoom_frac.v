`timescale 1ns/1ps
// tb_zoom_frac.v —— #104 的尺子：旋转支的小数位到底有没有交给双线性单元。
//
// 为什么要单独一把快尺子：#104 的病在 `zoom_mapper` 的组合/流水算术里（旋转支把 `>>> 16` 之后的
// 16 位小数**丢掉**、`frac_x/frac_y` 钉成 0），而顶层台架 tb_v98 一跑 75 分钟以上，拿它当这把小刀的
// 反馈环等于每次改一个位宽就等一小时。这里直接例化被测模块，几秒出结果。
//
// 期望值是**照着 zoom_mapper 现在的算术**一条条推出来的，不是"我以为应该等于"：
//   s0  xp = x − W/2、yp_math = H/2 − y          （旋转支用数学坐标，y 向上）
//   s1  xr_m = xp·C + yp·S、yr_m = −xp·S + yp·C   （C/S 是 Q8 的 cos/sin）
//   s2  rot_xs = xr_m·inv（Q16）⇒ 源 x = xr_pix + W/2、源 y = H/2 − yr_pix
//   输出必须是"**同一格**的 floor 与 frac"：x_out = floor(X)，frac_x = (X − floor(X))·256，y 同理。
//   纵向多一次"翻回来"，所以 y 的 floor 不是 H/2 − floor(Y_math)，而是它再减一格（当小数≠0 时）——
//   这一条正是最容易写错的地方，所以它单独成为一条判据（H4）。
//
// 判据形状：H1/H2 = 缩放支不许被改动带坏（负对照）；H3/H4 = 旋转支 floor 与 frac 自洽；
// H5 = 旋转态必须真的有小数（否则 `bilin on` 是空头支票）。改之前 H3/H4/H5 必须红、H1/H2 必须绿。
module tb_zoom_frac;

    localparam integer IW = 512, IH = 300;

    reg clk = 1'b0, rst_n = 1'b0;
    reg [9:0]  inv_scale = 10'd256;
    reg [8:0]  angle     = 9'd0;
    reg        rotate_en = 1'b0;
    reg [11:0] x_in = 12'd0, y_in = 12'd0;
    wire [11:0] x_out, y_out;
    wire        oob;
    wire [7:0]  frac_x, frac_y;

    zoom_mapper #(.IMAGE_W(IW), .IMAGE_H(IH)) dut (
        .clk(clk), .rst_n(rst_n), .inv_scale(inv_scale), .angle(angle),
        .rotate_en(rotate_en), .x_in(x_in), .y_in(y_in),
        .x_out(x_out), .y_out(y_out), .oob(oob), .frac_x(frac_x), .frac_y(frac_y)
    );

    always #10 clk = ~clk;                 // 50 MHz 像素钟

    integer errors = 0;
    integer dcheck = 0;   // D 这一族跑了多少次比较（汇总行要用，声明必须在 check_px 之前）
    // Q8 三角表：从 DUT 的 cos_rom/sin_rom 里取**同一张表**的值，参考就不引入第二次三角近似
    reg signed [15:0] Cv, Sv;
    real Ct, St;

    task step;                             // 一拍
        begin @(posedge clk); #1; end
    endtask

    // 参考值（实数，只在台架里用）：返回 1 = 该像素在窗内
    real Xr, Yr;
    function integer expect_at(input [11:0] x, input [11:0] y, input rot, input [9:0] inv);
        real xp, yp, c, s;
        begin
            // ⚠ 全部走实数域：`x - (IW/2)` 在这里是**无符号** 12 位减法（x 是无符号端口、
            //   IW/2 是整数字面量 ⇒ 结果是 32 位无符号，250−256 回绕成 4.29e9），
            //   第一版就是栽在这上面：参考把每个像素都算成"窗外"。乘 1.0 就是把两边都拉进 real。
            xp = x * 1.0 - (IW / 2) * 1.0;
            if (rot) begin
                yp = (IH / 2) * 1.0 - y * 1.0;           // 数学坐标，y 向上
                c  = Ct; s = St;
                Xr = (xp * c + yp * s) * inv / 65536.0 + (IW / 2);
                Yr = (IH / 2) - ((-xp * s + yp * c) * inv / 65536.0);
            end else begin
                yp = y * 1.0 - (IH / 2) * 1.0;             // 显示坐标，y 向下
                c  = 256.0; s = 0.0;
                Xr = xp * inv / 256.0 + (IW / 2);
                Yr = yp * inv / 256.0 + (IH / 2);
            end
            expect_at = (Xr >= 0.0 && Xr < IW && Yr >= 0.0 && Yr < IH);
        end
    endfunction

    // xsim 没有 `$round`，`$floor` 也不敢指望（都是 SystemVerilog 的）⇒ 自己写两个：
    //   $rtoi 是**朝 0 截断**，所以朝 −∞ 取整要自己补一格；舍入同理。
    function integer floor_i(input real v); integer t;
        begin t = $rtoi(v); floor_i = (v < 0.0 && t != v) ? (t - 1) : t; end
    endfunction
    function integer round_i(input real v);
        begin round_i = $rtoi(v + (v >= 0.0 ? 0.5 : -0.5)); end
    endfunction

    task check_px(input integer tag, input [11:0] x, input [11:0] y, input rot);
        integer fxs, fys; real ex, ey;
        begin
            dcheck = dcheck + 1;              // #162：D 这一族是"逐像素对实数参考"，一次比较记一次
            x_in = x; y_in = y;
            step; step; step;                            // 三级流水
            if (!expect_at(x, y, rot, inv_scale)) begin
                if (!oob) begin
                    $display("FAIL D%d oob_must_be_1 | x=%0d y=%0d outside but DUT did not flag oob", tag, x, y);
                    errors = errors + 1;
                end
            end else begin
                if (oob) begin
                    $display("FAIL D%d inside_but_oob | x=%0d y=%0d", tag, x, y);
                    errors = errors + 1;
                end
                fxs = floor_i(Xr); fys = floor_i(Yr);
                ex  = Xr - fxs; ey = Yr - fys;
                if (x_out !== fxs[11:0]) begin
                    $display("FAIL D%d floor_x | expect %0d got %0d (x=%0d y=%0d)", tag, fxs, x_out, x, y);
                    errors = errors + 1;
                end
                if (y_out !== fys[11:0]) begin
                    $display("FAIL D%d floor_y | expect %0d got %0d (x=%0d y=%0d)", tag, fys, y_out, x, y);
                    errors = errors + 1;
                end
                if ((round_i(ex * 256.0) - frac_x) > 1 || (frac_x - round_i(ex * 256.0)) > 1) begin
                    $display("FAIL D%d frac_x | exact=%0.4f -> %0d/256 got %0d (x=%0d y=%0d)", tag, ex, round_i(ex*256.0), frac_x, x, y);
                    errors = errors + 1;
                end
                if ((round_i(ey * 256.0) - frac_y) > 1 || (frac_y - round_i(ey * 256.0)) > 1) begin
                    $display("FAIL D%d frac_y | exact=%0.4f -> %0d/256 got %0d (x=%0d y=%0d)", tag, ey, round_i(ey*256.0), frac_y, x, y);
                    errors = errors + 1;
                end
            end
        end
    endtask

    integer nfrac, ntot, px, py;
    initial begin
        // 1) 缩放支（rotate_en=0）：负对照，今天就必须全绿
        inv_scale = 10'd299;                             // ≈0.86x：一定会有非零小数
        dcheck = 0;
        repeat (4) step; rst_n = 1'b1; repeat (2) step;
        for (py = 100; py < 120; py = py + 3)
            for (px = 250; px < 270; px = px + 5)
                check_px(1, px[11:0], py[11:0], 1'b0);
        $display("H1 zoom_branch_floor_frac | rotate_en=0, inv=299: floor+frac must describe the same cell (this is the negative control: it is green today and must stay green)");
        check_px(2, 12'd400, 12'd40, 1'b0);
        $display("H2 zoom_branch_inside | one more zoom-only pixel inside the window");

        // 2) 旋转支：30°、1.00x。今天 frac 被钉成 0 ⇒ H3/H4/H5 必须红
        rotate_en = 1'b1; angle = 9'd30; inv_scale = 10'd256;
        // ⚠ `cos_rom`/`sin_rom` 是**同步**读出的：换 angle 之后立刻取值，取到的是上一个角度的表项。
        //   第一版就栽在这里 —— 参考拿到 C=256/S=0，等于"我没旋转"，于是 60 个像素全报 floor_y 错，
        //   症状看起来完全像"DUT 旋转算错了"。所以这里先等 10 拍再取表，并且**自检取到的确实是新角度**。
        repeat (10) step;
        Cv = dut.u_cos.value; Sv = dut.u_sin.value;      // 与 DUT 同一张表
        Ct = Cv; St = Sv;
        if (Ct == 256.0 && St == 0.0) begin
            $display("FAIL H0 reference_table_stale | angle=30 却取到 C=256/S=0（表还没换过来）⇒ 参考自己不可信，本轮结果作废");
            errors = errors + 1;
        end else begin
            $display("PASS H0 reference_table_fresh | angle=30 取到 C=%0d S=%0d（Q8，与 DUT 同一张表）", $rtoi(Ct), $rtoi(St));
        end
        repeat (3) step;
        nfrac = 0; ntot = 0;
        for (py = 120; py < 180; py = py + 7) begin
            for (px = 200; px < 320; px = px + 11) begin
                check_px(3, px[11:0], py[11:0], 1'b1);
                ntot = ntot + 1;
                if (frac_x !== 8'd0 || frac_y !== 8'd0) nfrac = nfrac + 1;
            end
        end
        $display("H3 rot_floor_frac | 30 deg inv=256: %0d pixels, every one must carry its own fraction (DUT gave nonzero in %0d of them)", ntot, nfrac);
        $display("D%0d rot_and_zoom_pixel_compare | %0d independent floor/frac comparisons ran with %0d mismatch (this is the strong ruler: it printed only FAILs before #162)", dcheck, dcheck, errors);
        $display("H4 rot_floor_frac | the y axis is flipped back (H/2 - y): floor/frac must still describe the SAME cell - off-by-one here shows up as a 1-row shear while rotating");
        if (nfrac == 0) begin
            $display("FAIL H5 rot_has_fraction | every rotation pixel came out with frac_x=frac_y=0 => `bilin on` is a promise the rotation branch does not keep (#104)");
            errors = errors + 1;
        end else
            $display("PASS H5 rot_has_fraction | %0d of %0d rotation pixels carry a non-zero fraction", nfrac, ntot);

        // ————— #189：不是猜"这种像素存在不存在"，是扫出来并数清楚 —————
        // 病灶：`zoom_mapper.v:75-79` 判"有没有小数"只看 `rot_ys[15:8]`，而真实小数是 `rot_ys[15:0]/65536`。
        // 当小数落在 `(0, 1/256)` 时它读成"没有小数"⇒ 该减的那一格没减 ⇒ `y_out` 整行取错。
        // 三条判据各管一件事，缺一条就会变成"看着红但其实什么都没测"：
        //   S2 扫描**必须真的遇到**足够多这种像素（正对照能动能成立的前提；遇不到就当场判红，不许空过）
        //   S1 把看到的数量与第一个反例**报出来**（每次跑都打一行，不靠人翻日志）
        //   S3 这些像素的 `floor_y` 必须等于实数参考（修前必须红，修后必须绿）
        begin : scan189
            integer ai, si, ax, ay, tot, nlow, nbad, fb_x, fb_y, fb_ang, fb_inv, fys2, an;
            real    fr;
            tot = 0; nlow = 0; nbad = 0; fb_x = -1; fb_y = -1; fb_ang = -1; fb_inv = -1;
            for (ai = 0; ai < 12; ai = ai + 1) begin
                an = 9'd20 + ai * 19;                    // 覆盖 20°..248°（表是 Q8，一格≈1.4°）
                for (si = 0; si < 2; si = si + 1) begin
                    inv_scale = (si == 0) ? 10'd256 : 10'd299;
                    rotate_en = 1'b1; angle = an[8:0];
                    repeat (10) step;                     // 同步表：换角度后要等它换过来
                    Cv = dut.u_cos.value; Sv = dut.u_sin.value; Ct = Cv; St = Sv;
                    if (Ct == 256.0 && St == 0.0) begin
                        $display("FAIL S0 scan189_table_stale | angle=%0d 却取到 C=256/S=0 ⇒ 参考不可信，本轮作废", an);
                        errors = errors + 1;
                    end
                    for (ay = 90; ay < 270; ay = ay + 15) begin
                        for (ax = 150; ax < 370; ax = ax + 17) begin
                            if (expect_at(ax[11:0], ay[11:0], 1'b1, inv_scale)) begin
                                x_in = ax[11:0]; y_in = ay[11:0];
                                step; step; step;
                                tot = tot + 1;
                                fr  = Yr - floor_i(Yr);                 // 显示空间的小数（0 ≤ fr < 1）
                                // ⚠ 选错端就等于没测：RTL 判的是**数学空间**的小数 f，而这里 Yr 已经翻过号
                                //   （Y_disp = H/2 − Y_math），所以 f∈(0,1/256) ⇔ fr = 1−f ∈ (255/256, 1)。
                                //   第一版按 fr < 1/256 筛，扫到 8 个像素、0 个错——那是**筛到了另一头**，
                                //   不能当成"#189 不存在"的证据（2026-10-01 自己抓到的一次"尺子维度错"）。
                                if (fr > (255.0 / 256.0) && fr < 1.0) begin
                                    nlow = nlow + 1;
                                    fys2 = floor_i(Yr);
                                    if (y_out !== fys2[11:0]) begin
                                        nbad = nbad + 1;
                                        if (fb_x < 0) begin
                                            fb_x = ax; fb_y = ay; fb_ang = an; fb_inv = inv_scale;
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            $display("S1 scan189 | 扫了 %0d 个旋转态像素，其中数学空间小数落在 (0,1/256)（显示侧 fr>255/256）的 %0d 个，#189 让它们取错行的 %0d 个；首个反例 x=%0d y=%0d angle=%0d inv=%0d",
                     tot, nlow, nbad, fb_x, fb_y, fb_ang, fb_inv);
            if (nlow < 5) begin
                $display("FAIL S2 scan189_saw_the_case | 只遇到 %0d 个这种像素（<5）⇒ 这条扫描等于没测，不许当通过", nlow);
                errors = errors + 1;
            end
            if (nbad != 0) begin
                $display("FAIL S3 rot_frac_lowbyte | %0d/%0d 个像素的 floor_y 与实数参考差一格 ⇒ #189 是活缺陷（判小数存在与否必须用 16 位，不是高字节）", nbad, nlow);
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("[tb_zoom_frac] RESULT tb_zoom_frac PASS errors=0");
        else             $display("[tb_zoom_frac] RESULT tb_zoom_frac FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #400000;
        $display("[tb_zoom_frac] RESULT tb_zoom_frac FAIL timeout");
        $finish;
    end
endmodule
