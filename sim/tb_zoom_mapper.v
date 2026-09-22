`timescale 1ns/1ps
// zoom_mapper + zoom_ctrl：原本=最大，向缩小循环
module tb_zoom_mapper;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg        enable = 1;
    reg        frame_start = 0;
    wire [9:0] inv_scale;
    wire       zoom_active, dir;

    zoom_ctrl #(.INV_LO(10'd256), .INV_HI(10'd512), .STEP(10'd8)) u_ctrl (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .frame_start(frame_start),
        .inv_scale(inv_scale), .zoom_active(zoom_active), .dir(dir)
    );

    reg  [11:0] x_in = 0, y_in = 0;
    reg  [9:0]  inv_force = 10'd256;
    reg         rot_en = 1'b0;
    reg  [8:0]  angle = 9'd0;
    wire [11:0] xo, yo;
    wire        oobo;
    wire [7:0]  fx, fy;

    zoom_mapper #(.IMAGE_W(512), .IMAGE_H(300)) u_map (
        .clk(clk), .rst_n(rst_n),
        .inv_scale(inv_force), .angle(angle), .rotate_en(rot_en),
        .x_in(x_in), .y_in(y_in),
        .x_out(xo), .y_out(yo), .oob(oobo),
        .frac_x(fx), .frac_y(fy)
    );

    integer errors = 0;
    integer i;

    // 判据自己的 ROM 读数（只借"表里的常数"，不借被测的算术通路）
    wire signed [9:0] tb_sin, tb_cos;
    sin_rom u_tb_sin (.angle(angle), .value(tb_sin));
    cos_rom u_tb_cos (.angle(angle), .value(tb_cos));

    integer n_frac_nz = 0;     // 出现过小数非零的样本数（不然 y 取补那条分支根本没被走到）
    integer n_wrong_caught = 0; // 「不修正的旧写法」会被本判据抓住的样本数（反向对照）

    real sxr, syr, ex1, ey1, yr_true, yrm;
    integer fl;

    task expect_frac;
        input        rot;
        input [9:0]  inv;
        input [255:0] tag;
        real xp, ypd, ypm, u, c, sn;
        begin
            u   = inv / 256.0;
            c   = tb_cos / 256.0;
            sn  = tb_sin / 256.0;
            // 先搬进 real 再做减法：`x_in - 256` 在整数域里是**无符号**运算，
            // 会得到 2^32-56 这种数（现象：判据里 true 比 recon 正好大 2^32 的整数倍，
            // 小数位却完全吻合 ⇒ 一看就知道是 TB 自己的位宽/符号错，不是 RTL 错）。
            xp  = x_in;   ypd = y_in;
            xp  = xp - 256.0;
            ypd = ypd - 150.0;
            ypm = -ypd;
            if (rot) begin
                sxr = (xp*c + ypm*sn)*u + 256.0;
                yr_true = (-xp*sn + ypm*c)*u;
                syr = 150.0 - yr_true;
            end else begin
                sxr = xp*u + 256.0;
                syr = ypd*u + 150.0;
            end
            if (oobo) begin
                // 越界样本被填黑，小数没有意义：跳过，但整数还原本身仍要自洽
                ex1 = 0.0; ey1 = 0.0;
            end else begin
                ex1 = (xo + fx/256.0) - sxr;
                ey1 = (yo + fy/256.0) - syr;
                if (ex1 < 0) ex1 = -ex1;
                if (ey1 < 0) ey1 = -ey1;
                if (ex1 > 0.004 || ey1 > 0.004) begin
                    $display("FAIL frac %0s recon=(%f,%f) true=(%f,%f) got xy=(%0d,%0d) f=(%0d,%0d)",
                             tag, xo + fx/256.0, yo + fy/256.0, sxr, syr, xo, yo, fx, fy);
                    errors = errors + 1;
                end
                if (fx != 0 || fy != 0) n_frac_nz = n_frac_nz + 1;
                if (rot) begin
                    // 旧写法（y 不修正）会把整数停在 floor(150-yr) 的另一种取法上：
                    // 150 - floor(yr) 与真正的 floor(150 - yr) 在小数非零时差 1 整像素。
                    fl = yr_true;                       // 向零截断
                    if (yr_true < 0 && fl != yr_true) fl = fl - 1;   // 变成向下取整
                    yrm = 150.0 - fl;
                    if ((yrm - syr) > 0.2 || (syr - yrm) > 0.2) n_wrong_caught = n_wrong_caught + 1;
                end
            end
        end
    endtask

    task stepN;
        input integer n;
        integer j;
        begin
            for (j = 0; j < n; j = j + 1) @(posedge clk);
        end
    endtask

    task expect_xy;
        input [11:0] ex, ey;
        input        exp_oob;
        input [255:0] tag;
        begin
            if (oobo !== exp_oob || (!exp_oob && (xo !== ex || yo !== ey))) begin
                $display("FAIL %0s got (%0d,%0d) oob=%b expect (%0d,%0d) oob=%b",
                         tag, xo, yo, oobo, ex, ey, exp_oob);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // inv=256 identity (original size)
        inv_force = 10'd256; rot_en = 0; angle = 0;
        x_in = 0; y_in = 0; stepN(4); expect_xy(12'd0, 12'd0, 1'b0, "id(0,0)");
        x_in = 100; y_in = 50; stepN(4); expect_xy(12'd100, 12'd50, 1'b0, "id(100,50)");

        // inv=512 → 0.5x zoom-out
        // sx = 256 + (x-256)*512/256 = 256 + (x-256)*2
        // center stays; edges OOB
        inv_force = 10'd512;
        x_in = 256; y_in = 150; stepN(4); expect_xy(12'd256, 12'd150, 1'b0, "0.5x center");
        x_in = 0; y_in = 0; stepN(4); expect_xy(12'd0, 12'd0, 1'b1, "0.5x(0,0) OOB");
        // sx=256+(128-256)*2=0 → in range; sy=150+(75-150)*2=0
        x_in = 128; y_in = 75; stepN(4); expect_xy(12'd0, 12'd0, 1'b0, "0.5x(128,75)");
        // sx=256+(384-256)*2=512 → OOB (>=512)
        x_in = 384; y_in = 225; stepN(4); expect_xy(12'd0, 12'd0, 1'b1, "0.5x(384,225) OOB");

        // rotate 0 + inv 256 identity
        inv_force = 10'd256; rot_en = 1; angle = 0;
        x_in = 200; y_in = 100; stepN(4); expect_xy(12'd200, 12'd100, 1'b0, "rot0 id");
        expect_frac(1'b1, 10'd256, "rot0 (200,100)");

        // ---- 小数位还原判据（V7.8 双线性）----
        // 非 2 的幂的 inv ⇒ 小数必然非零；把 (x_out + frac/256) 拼回来和实数模型比。
        inv_force = 10'd300; rot_en = 0;
        x_in = 100; y_in = 60;  stepN(4); expect_frac(1'b0, 10'd300, "inv300 (100,60)");
        x_in = 300; y_in = 210; stepN(4); expect_frac(1'b0, 10'd300, "inv300 (300,210)");
        x_in = 71;  y_in = 233; stepN(4); expect_frac(1'b0, 10'd300, "inv300 (71,233)");
        inv_force = 10'd411;
        x_in = 200; y_in = 140; stepN(4); expect_frac(1'b0, 10'd411, "inv411 (200,140)");
        x_in = 405; y_in = 190; stepN(4); expect_frac(1'b0, 10'd411, "inv411 (405,190)");

        // 旋转分支：45°/30°/60° 的小数。y 方向是减法，「整数退一格 + 小数取补」没做对的话
        // 这里差的是一整像素（>>0.004），不是差一点。
        // 取点都离中心近，避免整张图旋转后被 OOB 判据跳过（那就变成"没判"的假绿）。
        rot_en = 1; inv_force = 10'd256; angle = 45;
        x_in = 300; y_in = 210; stepN(4); expect_frac(1'b1, 10'd256, "rot45 (300,210)");
        x_in = 200; y_in = 140; stepN(4); expect_frac(1'b1, 10'd256, "rot45 (200,140)");
        x_in = 280; y_in = 120; stepN(4); expect_frac(1'b1, 10'd256, "rot45 (280,120)");
        inv_force = 10'd300; angle = 30;
        x_in = 200; y_in = 140; stepN(4); expect_frac(1'b1, 10'd300, "rot30 inv300 (200,140)");
        x_in = 290; y_in = 190; stepN(4); expect_frac(1'b1, 10'd300, "rot30 inv300 (290,190)");
        inv_force = 10'd411; angle = 60;
        x_in = 300; y_in = 180; stepN(4); expect_frac(1'b1, 10'd411, "rot60 inv411 (300,180)");
        x_in = 330; y_in = 90;  stepN(4); expect_frac(1'b1, 10'd411, "rot60 inv411 (330,90)");

        // zoom_ctrl: start 256, STEP=8 toward 512
        if (inv_scale !== 10'd256) begin
            $display("FAIL ctrl reset inv=%0d", inv_scale);
            errors = errors + 1;
        end
        // (512-256)/8=32 frames to hit INV_HI
        for (i = 0; i < 20; i = i + 1) begin
            frame_start = 1; @(posedge clk); frame_start = 0; @(posedge clk);
        end
        // 256+20*8=416
        if (inv_scale !== 10'd416) begin
            $display("FAIL ctrl after 20 frames inv=%0d expect 416", inv_scale);
            errors = errors + 1;
        end
        for (i = 0; i < 40; i = i + 1) begin
            frame_start = 1; @(posedge clk); frame_start = 0; @(posedge clk);
        end
        // hit 512 then bounce down; expect still in [256,512]
        if (inv_scale < 10'd256 || inv_scale > 10'd512) begin
            $display("FAIL ctrl range inv=%0d", inv_scale);
            errors = errors + 1;
        end
        enable = 0;
        frame_start = 1; @(posedge clk); frame_start = 0; @(posedge clk);
        if (inv_scale !== 10'd256 || zoom_active !== 1'b0) begin
            $display("FAIL ctrl disable inv=%0d act=%b", inv_scale, zoom_active);
            errors = errors + 1;
        end

        // 判据自己也要有牙：小数字段必须真的被走到；并且「不做 y 修正」的旧写法
        // 会被本判据抓到（否则这条判据只是在重复一遍恒等式）。
        $display("INFO frac coverage: nonzero_frac=%0d wrong_y_convention_would_be_caught=%0d",
                 n_frac_nz, n_wrong_caught);
        if (n_frac_nz < 8) begin
            $display("FAIL frac never exercised (nz=%0d) — 判据空转", n_frac_nz);
            errors = errors + 1;
        end
        if (n_wrong_caught < 3) begin
            $display("FAIL teeth: un-fixed y convention slips through (caught=%0d)", n_wrong_caught);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS tb_zoom_mapper");
        else             $display("FAIL tb_zoom_mapper errors=%0d", errors);
        $finish;
    end
endmodule
