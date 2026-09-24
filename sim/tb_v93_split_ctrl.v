`timescale 1ns/1ps
// 台架：src/rtl/video/split_ctrl.v（V8-4 分割线发生器）
//
// 这个模块里"看着对"和"判得住"差别最大的是扫描，所以判据都写成**可反例**的形式：
//   * 端点判"必须真的取到 lo 与 hi"（T5/T6/T11），不是"落在 [lo,hi] 内" ——
//     后者在三角波卡死在中点时照样绿；
//   * 步长判"每一次变化恰好等于 speed，或者是落在端点上的那一步"（T6a）——
//     只判"最终到了端点"挡不住"一拍跳 16 像素"；
//   * 节拍判**有效像素数**而不是周期数，并且同一件事在"连续栅格"和"1024 有效 + 320 消隐"
//     两种栅格上各量一遍（T7 与 T8）：如果实现用的是"第几拍"，这两次的像素数会差 31 %
//     （= 消隐占比）而拍数不变 ⇒ 这一对判据能区分"按像素计"与"按拍计"。#54/#56 就栽在
//     这种区别上（tb_rotate_window 的 SLOT_LAG 假红、"分割线旁边的颜色条"）；
//   * 百分比不抄 RTL 的乘子，用整数除法 (eff*100)/W 独立算一遍（T3/T4 各若干个点）；
//   * swap 判"缝位与百分比一个像素都不动"（T2）——spec 要的是只换内容不换线位；
//   * 夹紧的"判据自身是活的"由 T1b 陪证：同一个模块里 777 必须原样透传，
//     所以 T1c/T1d 的"输出等于 1024"不可能是"输出恒为 1024"蒙对的。
//   * 统计类判据全部配一条"真的驱动了 N 个像素"的陪跑（T13）——#60 那一课。
module tb_v93_split_ctrl;

    localparam DW = 1024, SW = 512;
    localparam TB_Q = 6;                       // 快档：64 个有效像素走一步

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg         de = 0;
    reg  [11:0] pos_px = 0;
    reg         auto_en = 0;
    reg         follow = 0;
    reg  [3:0]  speed = 1;
    reg  [4:0]  lo16 = 0, hi16 = 16;
    reg         swap = 0;
    wire [11:0] eff;
    wire        rol;
    wire [11:0] pct;

    split_ctrl #(.DISP_W(DW), .SRC_W(SW), .TICK_BITS(TB_Q)) dut (
        .clk(clk), .rst_n(rst_n), .de(de), .pos_px(pos_px), .auto_en(auto_en),
        .follow(follow), .speed(speed), .lo16(lo16), .hi16(hi16), .swap(swap),
        .split_eff(eff), .raw_on_left(rol), .shown_pct(pct)
    );

    // 顶层用的那一档：只拿它量"一步 = 2^16 个有效像素"
    wire [11:0] eff16;
    split_ctrl #(.DISP_W(DW), .SRC_W(SW)) dut16 (
        .clk(clk), .rst_n(rst_n), .de(de), .pos_px(pos_px), .auto_en(auto_en),
        .follow(follow), .speed(speed), .lo16(lo16), .hi16(hi16), .swap(swap),
        .split_eff(eff16), .raw_on_left(), .shown_pct()
    );

    integer errors = 0, nvalid = 0, i, bad3, v, k;
    integer lo_exp, hi_exp;                    // watch 的期望端点（每次 watch 前先设好）
    // watch 的统计量
    integer minv, maxv, nchg, touched_lo, touched_hi, bad_step, first_delta;
    integer vp_min_gap, vp_max_gap;

    task chk;
        input [100*8:1] name;
        input cond;
        begin
            if (cond !== 1'b1) begin errors = errors + 1; $display("  FAIL %0s", name); end
            else $display("  PASS %0s", name);
        end
    endtask

    // 走 n 个**有效**像素（de 只在这些拍为 1）；不统计消隐
    task pixels;
        input integer n;
        integer a;
        begin
            for (a = 0; a < n; a = a + 1) begin
                @(negedge clk); de = 1;
                @(negedge clk); de = 0;
                nvalid = nvalid + 1;
            end
        end
    endtask

    // 扫 total 个有效像素，途中插 gap 个消隐拍（每 64 个有效像素一次），记录：
    //   变化次数 / 相邻变化的有效像素间隔（**跳过第一次**，因为 tcnt 的相位是任意的）/
    //   min/max / 两个端点各被采到几次 / 步长不合规的次数
    task watch;
        input integer total;
        input integer gap;
        integer c, d, p, since, first;
        begin
            p = eff; nchg = 0; first = 1;
            minv = eff; maxv = eff; touched_lo = 0; touched_hi = 0;
            bad_step = 0; first_delta = 0;
            vp_min_gap = 1 << 28; vp_max_gap = 0; since = 0;
            for (c = 0; c < total; c = c + 1) begin
                @(negedge clk); de = 1;
                @(negedge clk); de = 0;
                nvalid = nvalid + 1;
                since = since + 1;
                if (gap != 0 && ((c % 64) == 63))
                    for (d = 0; d < gap; d = d + 1) begin
                        @(negedge clk); de = 0;
                        @(negedge clk);
                    end
                if (eff !== p) begin
                    nchg = nchg + 1;
                    if (first) begin
                        first_delta = (eff > p) ? (eff - p) : (p - eff);
                        first = 0;
                    end else begin
                        if (since < vp_min_gap) vp_min_gap = since;
                        if (since > vp_max_gap) vp_max_gap = since;
                    end
                    since = 0;
                    if (((eff > p) ? (eff - p) : (p - eff)) != speed &&
                        eff !== lo_exp[11:0] && eff !== hi_exp[11:0])
                        bad_step = bad_step + 1;
                    p = eff;
                end
                if (eff < minv) minv = eff;
                if (eff > maxv) maxv = eff;
                if (eff === lo_exp[11:0]) touched_lo = touched_lo + 1;
                if (eff === hi_exp[11:0]) touched_hi = touched_hi + 1;
            end
            // 每段观测都把自己的账打出来：红了之后要能一眼看出是"被测者没做到"还是
            // "观测窗口不够 / 初值不在区间里"（skill/failing_read_prints_geometry）。
            $display("     DBG watch total=%0d nchg=%0d min=%0d max=%0d touched_lo=%0d touched_hi=%0d bad_step=%0d first_delta=%0d gap=[%0d,%0d]",
                     total, nchg, minv, maxv, touched_lo, touched_hi, bad_step,
                     first_delta, vp_min_gap, vp_max_gap);
        end
    endtask

    initial begin
        // ---------- T0 反 X：复位后输出必须是确定的数 ----------
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);
        chk("T0  复位后 split_eff / shown_pct 既不是 X 也不是 Z",
            eff === eff && pct === pct);

        // ---------- T1 手工位置：透传 + 越界夹紧 ----------
        auto_en = 0; pos_px = 512; pixels(4);
        chk("T1a 手工位置 512 原样透传", eff === 512);
        pos_px = 777; pixels(4);
        chk("T1b 手工位置 777 原样透传（没有被量化到 1/16 的格子上）", eff === 777);
        pos_px = 1024; pixels(4);
        chk("T1c 手工位置 = 屏宽是合法值（缝推到最右），原样到 1024", eff === 1024);
        pos_px = 2000; pixels(4);
        chk("T1d 越界位置被夹回屏宽（T1b 已证明它不是恒等于 1024）", eff === 1024);

        // ---------- T2 swap 只换内容，不换缝位 ----------
        v = eff; k = pct; swap = 1; pixels(4);
        chk("T2a swap=1 时 split_eff / shown_pct 一个像素都不动",
            eff === v && pct === k);
        chk("T2b swap=1 ⇒ raw_on_left=0", rol === 1'b0);
        swap = 0; pixels(4);
        chk("T2c swap 回 0 ⇒ raw_on_left=1 且缝位仍在原处", rol === 1'b1 && eff === v);

        // ---------- T3 百分比：与整数除法独立对账（显示域） ----------
        bad3 = 0;
        for (i = 0; i < 16; i = i + 1) begin
            pos_px = i * 64; pixels(2);
            lo_exp = (pos_px * 100) / DW;
            if (pct !== lo_exp) begin
                bad3 = bad3 + 1;
                $display("     T3 eff=%0d 百分比=%0d 期望 %0d", pos_px, pct, lo_exp);
            end
        end
        chk("T3  显示域 16 个位置的百分比与整数除法逐点一致", bad3 == 0);
        pos_px = 1024; pixels(2);
        chk("T3b eff = 屏宽 ⇒ 100 %", pct === 100);
        pos_px = 512; pixels(2);
        chk("T3c eff = 半屏 ⇒ 50 %", pct === 50);

        // ---------- T4 源域（split_follow）：宽度换成 512 ----------
        follow = 1; pos_px = 1000; pixels(2);
        chk("T4a 跟随模式下 1000 被夹到源宽 512", eff === 512);
        pos_px = 256; pixels(2);
        chk("T4b 跟随模式百分比按**源宽**折算（256/512 = 50 %）",
            pct === ((256 * 100) / SW) && pct === 50);
        pos_px = 128; pixels(2);
        chk("T4c 跟随模式 128/512 的百分比 = 25", pct === ((128 * 100) / SW) && pct === 25);
        follow = 0; pos_px = 128; pixels(2);
        chk("T4d 退回显示域：同一个 128 现在是 12 %（两档乘子不共用）",
            pct === ((128 * 100) / DW) && pct === 12);

        // ---------- T5 自动扫描全行程：两个端点必须真的取到 ----------
        auto_en = 1; speed = 1; lo16 = 0; hi16 = 16; lo_exp = 0; hi_exp = DW;
        pos_px = 0; pixels(2);
        watch(220000, 0);                       // 0→1024→0 需要 2048 步 × 64 像素
        chk("T5a 全行程扫描采到了下端点 0", touched_lo > 0);
        chk("T5b 全行程扫描采到了上端点 1024", touched_hi > 0);
        chk("T5c 全程不越界（min = 0 且 max = 1024）", minv === 0 && maxv === DW);
        chk("T5d 既有上升也有下降 ⇒ 是三角波，不是锯齿撞墙就停",
            nchg > 100 && bad_step == 0);

        // ---------- T6 range 夹紧到 1/4..3/4，且步长恰好 = speed ----------
        speed = 7; lo16 = 4; hi16 = 12; lo_exp = 256; hi_exp = 768;
        auto_en = 1; pos_px = 256; pixels(2);
        watch(12000, 0);                        // (768-256)/7 = 74 步/半程 × 64 ≈ 4.7 k
        chk("T6a 每一次变化要么是 7 个像素，要么是落在端点上的最后一步（bad_step=0）",
            bad_step == 0 && nchg > 10);
        chk("T6b range 4..12 的下端点确实是 256、上端点确实是 768",
            touched_lo > 0 && touched_hi > 0 && minv === lo_exp && maxv === hi_exp);
        auto_en = 0; pos_px = 256; pixels(2);
        chk("T6c 下端点 256 的百分比 = 25（跟随关闭）", pct === 25);

        // ---------- T7 节拍：一步 = 64 个有效像素（快档 TICK_BITS=6） ----------
        auto_en = 1; speed = 1; lo16 = 0; hi16 = 16; lo_exp = 0; hi_exp = DW;
        pos_px = 0; pixels(2);
        watch(700, 0);
        chk("T7  连续两次变化之间恰好 64 个有效像素",
            nchg > 4 && vp_min_gap == 64 && vp_max_gap == 64);

        // ---------- T8 同一件事在"1024 有效 + 320 消隐"的栅格上仍然成立 ----------
        watch(700, 320);
        chk("T8a 插了 31 % 消隐之后，一步仍是 64 个**有效像素**（不按拍计）",
            nchg > 4 && vp_min_gap == 64 && vp_max_gap == 64);
        chk("T8b 消隐期间输出不越界（min/max 仍落在 range 内）",
            minv >= lo_exp && maxv <= hi_exp);

        // ---------- T9 speed=0 = 钉住 ----------
        // 先把 swp 灌成 300（只有手工模式会让扫描值跟住 pos_px），再打开 auto + speed=0：
        // 期望"钉在 300 这一拍上"。第一次这里判失败是因为顺序写反了 —— 打开 auto 之后再改
        // pos_px 是不灌的（那样"手工位置"与"扫描值"就成了两条互不相干的数，判据会假绿）。
        speed = 0; lo16 = 0; hi16 = 16; lo_exp = 0; hi_exp = DW;
        auto_en = 0; pos_px = 300; pixels(4);
        v = eff;
        auto_en = 1; watch(400, 0);
        chk("T9  speed=0 ⇒ 扫描值钉住不动（且钉的正是手工位置那一点）",
            nchg == 0 && eff === v && v === 300);

        // ---------- T10 手工 → 自动不跳位 ----------
        auto_en = 0; speed = 1; pos_px = 300; pixels(4);
        v = eff;
        auto_en = 1; watch(200, 0);
        chk("T10 打开 auto 的第一次变化是 +1（从手工位置 300 续扫，不回 0）",
            v === 300 && nchg > 0 && first_delta == 1 && eff > 300 && eff < 400);

        // ---------- T11 range 写反（lo>hi）必须折成 [min,max] ----------
        // 窗口要盖得住"从 300 起、上行 468 + 下行 512 + 上行 512 = 1492 像素 @ 每步 3 像素
        // × 每步 64 个有效像素"≈ 3.2 万像素。第一次这里判红是因为只给了 2 万像素 ——
        // 那是**观测窗口不够**，不是被测者错（同一个教训见 tb_v89 把直方图 NG 从 7 加到 11）。
        auto_en = 0; speed = 3; lo16 = 12; hi16 = 4; lo_exp = 256; hi_exp = 768;
        pos_px = 300; pixels(4);
        auto_en = 1; watch(45000, 0);
        chk("T11 range 写成 80 20 时：仍夹在 [256,768]，两端都取到，步长合规",
            minv >= lo_exp && maxv <= hi_exp && touched_lo > 0 && touched_hi > 0
            && bad_step == 0 && nchg > 100);

        // ---------- T12 顶层那一档参数：一步 = 65536 个有效像素 ----------
        auto_en = 1; speed = 1; lo16 = 0; hi16 = 16; pos_px = 0; pixels(4);
        begin : blk12
            integer c2, p2, since2, gmin, gmax, nch;
            p2 = eff16; since2 = 0; gmin = 1 << 28; gmax = 0; nch = 0;
            for (c2 = 0; c2 < 3 * 65536 + 8; c2 = c2 + 1) begin
                @(negedge clk); de = 1;
                @(negedge clk); de = 0;
                nvalid = nvalid + 1;
                since2 = since2 + 1;
                if (eff16 !== p2) begin
                    if (nch > 0) begin
                        if (since2 < gmin) gmin = since2;
                        if (since2 > gmax) gmax = since2;
                    end
                    nch = nch + 1; since2 = 0; p2 = eff16;
                end
            end
            chk("T12 默认档（TICK_BITS=16）一步恰好 65536 个有效像素 = 64 行",
                nch >= 3 && gmin == 65536 && gmax == 65536);
        end

        // ---------- T13 陪跑：这一轮真的驱动了足够多的像素 ----------
        chk("T13 样本数 > 0（这里要求 35 万个有效像素，否则上面全是空判据）",
            nvalid > 350000);

        $display("");
        if (errors == 0) $display("PASS tb_v93_split_ctrl");
        else $display("FAIL tb_v93_split_ctrl errors=%0d", errors);
        $finish;
    end
endmodule
