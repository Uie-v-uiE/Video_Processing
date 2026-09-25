`timescale 1ns/1ps
// tb_v100_fit_rot —— V9 新算术的两台台架：
//   T1/T2  zoom_fit：360 个角度逐个验"装得下"与"不白缩"
//   T2b    0° 必须回到 1.0x 附近（拟合不该在没转的时候留一个明显的缩水）
//   T3     angle_ctrl 的自动旋转：只在帧沿走、speed=0 钉住、过 360 取模不丢度、按键仍然有效
//   T5     zoom_ctrl 的第三种来源：inv_used / zoom_code 是不是同一个数
//
// ⚠ 判据与 DUT **不共用同一条算式**（这是仓库里"尺子先错"那一族教训的正面做法，#68）：
//   zoom_fit 里面用"乘倒数常数 + 移位"避开运行时除法（#58），这里就用**交叉相乘**的整数比较
//   判同一件事 —— 台架里一次除法都不做，也不抄那个常数。
// ⚠ 消息全部 ASCII：xsim 在中文 Windows 控制台下打 CJK 会落成乱码（任务 #55 记的就是这件事，
//   而红了读不出数字 = 白跑一轮）。中文只出现在注释里，那里不进日志。
//
// 怎么跑（快照名要可辨认，理由见 ISSUES #75 的"读到过别人的 PASS"那段）：
//   cmd //c "D:\Software\Vivado\2025.2.1\Vivado\bin\xvlog.bat" <本文件 + 下面四个 RTL>
//   cmd //c "D:\Software\Vivado\2025.2.1\Vivado\bin\xelab.bat" tb_v100_fit_rot -s v100fr
//   cmd //c "D:\Software\Vivado\2025.2.1\Vivado\bin\xsim.bat"  -runall v100fr
module tb_v100_fit_rot;
    localparam integer IW = 512, IH = 300;

    reg clk = 0, rst_n;
    always #10 clk = ~clk;                 // 50 MHz，与 clk_pix 同一档

    // ---------------- DUT 1：zoom_fit ----------------
    reg  [8:0] a1;
    wire [9:0] inv_fit;
    zoom_fit #(.IMAGE_W(IW), .IMAGE_H(IH)) u_fit (
        .clk(clk), .rst_n(rst_n), .angle(a1), .inv_fit(inv_fit)
    );
    // 台架自己读同一张三角表（Q8，256=1.0）—— 这是"被验对象的事实"，不是它的算式
    wire signed [9:0] sb, cb;
    sin_rom tb_sin (.angle(a1), .value(sb));
    cos_rom tb_cos (.angle(a1), .value(cb));
    wire [9:0] bC = cb[9] ? (~cb + 10'd1) : cb;
    wire [9:0] bS = sb[9] ? (~sb + 10'd1) : sb;
    // 装得下的充要条件（交叉相乘，无除法）：inv/W >= (W*C + H*S)/W  <=>  inv*W >= W*C + H*S
    wire [31:0] need_x = IW * bC + IH * bS;           // <= (512+300)*256 = 207872
    wire [31:0] need_y = IW * bS + IH * bC;
    wire [31:0] hav    = {22'd0, inv_fit};

    // ---------------- DUT 2：angle_ctrl ----------------
    reg  k_inc = 0, k_dec = 0, auto_en = 0, ftgl = 0;
    reg  [2:0] spd = 0;
    wire [8:0] ang;
    wire       rot_act;
    angle_ctrl u_ang (
        .clk(clk), .rst_n(rst_n), .key_inc(k_inc), .key_dec(k_dec),
        .frame_tgl(ftgl), .auto_en(auto_en), .speed(spd),
        .angle(ang), .rotate_active(rot_act)
    );

    // ---------------- DUT 3：zoom_ctrl（第三种来源）----------------
    reg  frame_start = 0, en = 1, manual = 0, fit_en = 0;
    reg  [2:0] zsel = 0;
    wire [9:0] inv_scale, inv_used;
    wire       zact, zdir;
    wire [2:0] zcode;
    zoom_ctrl #(.INV_LO(10'd256), .INV_HI(10'd512), .STEP(10'd2)) u_zc (
        .clk(clk), .rst_n(rst_n), .enable(en), .frame_start(frame_start),
        .zsel(zsel), .manual(manual), .fit_en(fit_en), .inv_fit(inv_fit),
        .inv_scale(inv_scale), .inv_used(inv_used),
        .zoom_active(zact), .zoom_code(zcode), .dir(zdir)
    );

    // 帧沿要过 3 级同步 + 异或才成为 angle_ctrl 里的那一次推进 ⇒ **检查之前必须等几步**。
    // 不等的话最后一次翻转的沿还没落地，读到的角度少一步 —— 第一版的 T3f 就是这样把
    // 正确的硬件读成"取模丢了 7°"的（尺子先错，#68 那一族的第三次）。
    task settle;
        begin repeat (6) @(posedge clk); end
    endtask

    integer errors = 0, checks = 0;
    integer a;

    task fail; input [255:0] m;
        begin errors = errors + 1; $display("FAIL %0s", m); end
    endtask
    task ok;   input [255:0] m;
        begin checks = checks + 1; $display("ok   %0s", m); end
    endtask

    initial begin
        rst_n = 0; a1 = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        #1;

        // ---- T1 + T2 + T2b：360 个角度，每个验"横/纵都装得下"、不小于 1.0x、且不白缩 3 % 以上 ----
        for (a = 0; a < 360; a = a + 1) begin
            a1 = a[8:0];
            repeat (4) @(posedge clk);         // zoom_fit 现在是两级（分子一级、乘常数+取大一级）
            checks = checks + 1;
            if (hav * IW < need_x) begin
                errors = errors + 1;
                $display("FAIL T1 a=%0d fits-X NO: inv=%0d need>%0d/%0d (C=%0d S=%0d)",
                         a, inv_fit, need_x, IW, bC, bS);
            end
            if (hav * IH < need_y) begin
                errors = errors + 1;
                $display("FAIL T1 a=%0d fits-Y NO: inv=%0d need>%0d/%0d (C=%0d S=%0d)",
                         a, inv_fit, need_y, IH, bC, bS);
            end
            if (inv_fit < 10'd256) begin
                errors = errors + 1;
                $display("FAIL T1 a=%0d inv=%0d < 256: fit must never enlarge", a, inv_fit);
            end
            // "刚好"是两个方向的较大者 => 两个方向都超 3 % 才算缩过头。
            // 只比一个方向就是本台架第一版那次假红（#68 同一课，写在 ISSUES #75）。
            if ((hav * IW > (need_x + (need_x >> 5))) &&
                (hav * IH > (need_y + (need_y >> 5)))) begin
                errors = errors + 1;
                $display("FAIL T2 a=%0d over-shrunk: inv=%0d (both axes > 3%% tolerance)", a, inv_fit);
            end
            if (a == 0) begin
                if (inv_fit > 10'd259) begin
                    errors = errors + 1;
                    $display("FAIL T2b a=0 inv_fit=%0d (expect 256..259) chain: C=%0d S=%0d nx=%0d ny=%0d ix=%0d iy=%0d imax=%0d",
                             inv_fit, u_fit.C, u_fit.S, u_fit.nx, u_fit.ny, u_fit.ix, u_fit.iy, u_fit.imax);
                end else begin
                    checks = checks + 1;
                    $display("ok   T2b a=0 inv_fit=%0d ~= 1.0x", inv_fit);
                end
            end
        end
        $display("T1/T2 done: 360 angles, each vs two independent 'fits' inequalities");

        // ---- T3 自动旋转的节拍 ----
        auto_en = 0; spd = 3; ftgl = 0;
        repeat (2) @(posedge clk);
        if (ang !== 9'd0) begin
            $display("FAIL T3a ang moved before any edge: ang=%0d", ang); errors = errors + 1;
        end
        repeat (10) begin @(posedge clk) ftgl = ~ftgl; @(posedge clk); end
        settle;
        // 一帧 = 翻转位翻**一次**（angle_ctrl 里 fs_s[1]^fs_s[2]，不分升降沿）。
        // 但 auto_en=0 时**一帧沿都不许推进**，所以这里的期望值就是 0；推进的那条判据在下面 T3c。
        if (ang !== 9'd0) begin
            $display("FAIL T3b auto=0 must freeze: after 10 edges ang=%0d (expect 0); ftgl=%b fs_s=%b k_inc=%b k_dec=%b",
                     ang, ftgl, u_ang.fs_s, k_inc, k_dec);
            errors = errors + 1;
        end else ok("T3b auto_en=0: frame edges do not advance angle");
        checks = checks + 1;
        auto_en = 1;
        repeat (10) begin @(posedge clk) ftgl = ~ftgl; @(posedge clk); end
        settle;
        if (ang !== 9'd30) begin
            $display("FAIL T3c speed=3, 10 edges => 30 deg, got %0d (edge lost or double-counted)", ang);
            errors = errors + 1;
        end else $display("ok   T3c 10 frame edges x 3 deg => %0d", ang);
        checks = checks + 1;

        // ---- T3e 先回零，再用按键推到 355（±1° 必须一直有效：那是用户唯一的手动入口）----
        spd = 7; auto_en = 0;
        repeat (ang) begin @(posedge clk) k_dec = 1; @(posedge clk) k_dec = 0; end
        if (ang !== 9'd0) begin
            $display("FAIL T3e cannot get back to 0 by key_dec: ang=%0d", ang); errors = errors + 1;
        end
        repeat (355) begin @(posedge clk) k_inc = 1; @(posedge clk) k_inc = 0; end
        if (ang !== 9'd355) begin
            $display("FAIL T3e key_inc to 355 got %0d -- T3f below is then meaningless", ang);
            errors = errors + 1;
        end else $display("ok   T3e key ±1 deg still reaches any angle (355)");
        checks = checks + 1;
        auto_en = 1;
        repeat (2) begin @(posedge clk) ftgl = ~ftgl; @(posedge clk); end   // 2 帧 x 7 = +14 => 369 => 9
        settle;
        $display("OBS T3f after 2 edges at speed=7 from 355: ang=%0d (expect 9)", ang);
        if (ang !== 9'd9) begin
            $display("FAIL T3f mod-360 wrap wrong: ang=%0d", ang); errors = errors + 1;
        end else ok("T3f wraps 360 without losing degrees");
        checks = checks + 1;
        auto_en = 0;

        // ---- T5 zoom_ctrl：fit_en=1 => inv_used 就是 inv_fit，且 zoom_code 分区跟同一个数 ----
        fit_en = 1; a1 = 45; repeat (5) @(posedge clk);
        $display("OBS T5 a=45: inv_used=%0d zcode=%0d zact=%b inv_scale(regular path)=%0d",
                 inv_used, zcode, zact, inv_scale);
        if (inv_used !== inv_fit) fail("T5a fit_en=1 but inv_used != inv_fit");
        else ok("T5a fit_en=1 => the mapper gets the fitted value");
        checks = checks + 1;
        if (inv_used >= 10'd427 && inv_used < 10'd644) begin
            if (zcode !== 3'd2) fail("T5b OSD bucket != the bucket of the value in use");
            else ok("T5b 45 deg (inv about 490) shows 0.50x: bucket follows inv_used");
        end else $display("SKIP T5b inv_used=%0d outside the 0.50x bucket", inv_used);
        checks = checks + 1;
        fit_en = 0; repeat (3) @(posedge clk);
        if (inv_used !== inv_scale) fail("T5c fit_en=0 did not fall back to inv_scale");
        else ok("T5c turning fit off returns to the previous source (no jump)");
        checks = checks + 1;

        $display("== tb_v100_fit_rot: checks=%0d errors=%0d ==", checks, errors);
        if (errors == 0) $display("V100 PASS");
        else             $display("V100 FAIL");
        $finish;
    end
endmodule
