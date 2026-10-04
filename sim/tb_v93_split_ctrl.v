`timescale 1ns/1ps
// 功能：被测模块 `split_ctrl`（两台：dut 取 .TICK_BITS(6)，dut16 用默认档，均 DISP_W=1024、SRC_W=512）；
//        覆盖点＝手工位置透传与越界夹紧、swap 只换内容不换缝位、shown_pct 与整数除法逐点对账、源域跟随
//        的折算、自动扫描的端点与步长、节拍按有效像素计（连续栅格与带消隐栅格各量一遍）、speed=0 钉住、
//        手工转自动不跳位、range 写反折成 [min,max]、默认档一步的像素数。
// 激励与检查：时钟 #10 翻转（20 ns 周期），rst_n 以初值 0 走 4 拍后置 1 再等 2 拍；pixels(n) 喂 n 个有效
//        像素（每像素 de=1/de=0 各一拍）；watch(total,gap) 扫 total 个有效像素、每满 64 个插 gap 拍消隐，
//        用量依次为 220000/12000/700/700(gap=320)/400/200/45000，T12 对 eff16 走 3*65536+8 个像素；
//        手工位置取 512、777、1024、2000、1000、256、128、300，speed 取 1/7/0/3，lo16/hi16 取 0/16、
//        4/12、12/4（写反）。判定：T0 eff===eff 且 pct===pct；T1a eff===512、T1b ===777、T1c/T1d ===1024；
//        T2a swap 后 eff 与 pct 同值、T2b rol===0、T2c rol===1 且 eff 不动；T3 16 个位置
//        pct===(pos_px*100)/DW、T3b eff=1024 ⇒ pct===100、T3c 512 ⇒ ===50；T4a follow 下 1000 夹到
//        eff===512、T4b 256/512 ⇒ pct===((256*100)/SW)===50、T4c 128 ⇒ 25、T4d 退回显示域 128 ⇒ 12；
//        T5a/T5b touched_lo、touched_hi 均 >0、T5c minv===0 且 maxv===DW、T5d nchg>100 且 bad_step==0；
//        T6a speed=7 下 bad_step==0 且 nchg>10、T6b minv===256 且 maxv===768 且两端都采到、T6c pct===25；
//        T7/T8a nchg>4 且 vp_min_gap==64 且 vp_max_gap==64；T8b minv>=lo_exp 且 maxv<=hi_exp；
//        T9 nchg==0 且 eff===v===300；T10 v===300 且 nchg>0 且 first_delta==1 且 300<eff<400；
//        T11 minv>=256、maxv<=768、两端采到、bad_step==0、nchg>100；T12 nch>=3 且 gmin==gmax==65536；
//        T13 nvalid>350000（陪跑，防上面全成空判据）。
// 预期结果：通过时每条 chk 打一行 "  PASS <判据名>"、末行 PASS tb_v93_split_ctrl，watch 的 DBG 行里
//        bad_step=0、touched_lo/touched_hi 非 0、gap=[64,64]；失败时对应判据前打 "  FAIL <判据名>"
//        （watch 的 DBG 行先给出 min/max/touched/bad_step 的实际数字），末行变
//        FAIL tb_v93_split_ctrl errors=<n>；本文件没有看门狗 initial，跑飞靠 sim/run_one.sh 的超时。
// 台架：src/rtl/video/split_ctrl.v（V8-4 分割线发生器）。跑：bash sim/run_one.sh tb_v93_split_ctrl
// 判据一律写成可反例的形式：端点判"真的取到 lo/hi"（T5/T6b/T11），不是"落在 [lo,hi] 内"；
// 步长判"每步恰好 = speed 或落在端点上的收尾那一步"（T6a）；夹紧的"判据有牙"由 T1b（777 原样透传）陪证；
// 节拍按**有效像素数**计，在连续栅格与"1024 有效 + 320 消隐"上各量一遍（T7/T8）：按拍计会让两次
//   像素数差 31 %（= 消隐占比）而拍数不变 —— #54/#56 就栽在这区别上；
// 百分比不抄 RTL 乘子、用整数除法 (eff*100)/W 独立算（T3/T4）；swap 只换内容不换缝位（T2）；统计类配"真的驱动了 N 个像素"陪跑（T13，#60）。
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

    // 扫 total 个有效像素，途中每 64 个插 gap 拍消隐；记录变化次数 / 相邻变化的有效像素间隔
    // （**跳过第一次**，tcnt 相位任意）/ min/max / 两端点各被采到几次 / 步长不合规次数
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
            // 每段观测都打自己的账：红了要能一眼分清"被测者没做到"还是"观测窗口不够/初值不在区间里"
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
                $display("[tb_v93_split_ctrl.v:162] T3 eff=%0d 百分比=%0d 期望 %0d", pos_px, pct, lo_exp);
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
        // 顺序要紧：只有手工模式才把扫描值灌成 pos_px，打开 auto 之后再改 pos_px 是不灌的
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
        // 窗口要盖得住"从 300 起、上 468 + 下 512 + 上 512 ≈ 1492 像素 @ 每步 3 像素 × 每步 64 个
        // 有效像素" ≈ 3.2 万像素；观测窗口不够 ≠ 被测者错（同一教训见 tb_v89 直方图 NG 7→11）。
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
