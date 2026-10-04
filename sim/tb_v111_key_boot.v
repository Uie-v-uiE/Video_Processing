`timescale 1ns/1ps
// 功能：被测模块 `key_debounce` + `key_long` + `angle_ctrl`（u_k1/u_k1l/u_ang 串成真链，
//        u_k1.key_stable 取反喂 u_k1l.pressed，u_k1l.short_pulse 喂 u_ang.key_inc，key_dec 恒 0）；
//        覆盖点：复位释放后线松着时的上电角度、去抖窗内外的按下、武装门开后的真人短按、跨过长按阈值。
// 激励与检查：时钟 #10 翻转（20 ns 周期，50 MHz）；每腿先 rst_n 拉低 8 拍再放开；参数按真值缩 1000 倍
//        （DBN=1_000、HOLD=30_000、ARM=10_000，FRAME=835 拍算一显示帧，frame_tgl 每 FRAME 拍翻一次）；
//        key_n 拉低时长取 0.5×DBN / 1.5×DBN / HOLD+DBN+500 拍三档，松手后再跑 2×DBN 或 4×FRAME 拍，
//        另有线恒高跑 3×DBN 与先等门开跑 DBN+50 两腿；
//        判定条件：R 放开当拍 angle==0 且 rotate_active==0、ltog==0 且 k1_up==1；
//        B 与 D 都要 inc_cnt==0 且 angle==0；A 按住期间 k1_up==1，松手后 inc_cnt==0、angle==0、ltog==0；
//        A6 真人一按要 angle==9'd1 且 inc_cnt==1 且 ltog==0；
//        C 要 ltog==1 且 inc_cnt==0 且松手后 angle==0。
// 预期结果：通过时末行打印 `PASS tb_v111_key_boot` 且 errors==0，各腿 INFO 行的
//        angle/rotate_active/ltog/k1_up/short_pulse 累计与上述取值一致（A、B、D 三腿 angle 恒 0）；
//        失败时该条判据打印一行 `  FAIL <判据名>`、errors 加一，末行变 `FAIL tb_v111_key_boot errors=<n>`；
//        跑到 #20_000_000 未收尾打印 `FAIL tb_v111_key_boot timeout`。
// 台架：上电那一度 —— 用户 2026-10-03 问「为啥现在上电之后就是 1 度旋转而不是 0」。
// 跑法：bash sim/run_one.sh tb_v111_key_boot
//
// 链是**真三份**：key_debounce → key_long → angle_ctrl，接法照抄 pl_video_top.v:136-150/183-188
// （u_k1 的 key_stable 取反喂 key_long.pressed；短按 k1_short 喂 angle_ctrl.key_inc；
//   KEY2 的按下沿脉冲 p2 喂 key_dec —— 这里 KEY2 恒不按下，因为屏上是 +1°而不是 359°）。
//
// 参数按 tb_v87_key_long 的老规矩同比例缩 1000 倍（真实值 CNT_MAX=1_000_000=20 ms、
// HOLD_CYC=30_000_000=0.6 s、ARM_CYC=10_000_000=0.2 s）。判据靠的是**比例**：
//   按下时长落在 (去抖窗, 长按阈值) 之间 ⇒ 出一枚 short_pulse；跨过长按阈值 ⇒ 只翻 tog。
//   缩比例是为了让这支留在快车道（几万拍），不是为了改语义。
//
// 判据形状 = 夹逼 + 对照，三条各钉一件事：
//   A 浮空读低 1.5×去抖窗后回高 ⇒ 角度恰好 +1、模式位不动 —— 与用户看到的"只有 1°、没换模式"一字不差
//   D 浮空读低 0.5×去抖窗后回高 ⇒ 角度必须还是 0（低于去抖窗的毛刺不背这个锅，A 不是"随便给个 0 就能过"）
//   B 这根线全程为高（= XDC 里给 key1_n 加 PULLUP 之后电气上保证的状态）⇒ 角度 0
//   C 按下时长跨过长按阈值 ⇒ 翻 tog 且**不许**动角度（若是这根线一直趴着，症状会长按那个方向变，不是 1°）
//   R 复位释放那一拍角度必须为 0（⇒ 那一度不是复位值给的，是复位之后进来的事件）
module tb_v111_key_boot;

    localparam integer DBN   = 1_000;      // 真实 1_000_000（20 ms）
    localparam integer HOLD  = 30_000;     // 真实 30_000_000（0.6 s）
    localparam integer ARM   = 10_000;     // 真实 10_000_000（0.2 s）
    localparam integer FRAME = 835;        // 16.7 ms ÷ 1000 @ 50 MHz ⇒ 一个"显示帧"的拍数

    reg clk = 0, rst_n = 0, key_n = 1'b1, fs_tgl = 0;
    reg auto_en = 0;
    wire p1, k1_up, k1_short, k1_hold, ltog;
    wire [8:0] angle;
    wire rotate_active;

    key_debounce #(.CNT_MAX(DBN)) u_k1 (
        .clk(clk), .rst_n(rst_n), .key_n(key_n), .pulse(p1), .key_stable(k1_up));

    key_long #(.HOLD_CYC(HOLD), .ARM_CYC(ARM)) u_k1l (
        .clk(clk), .rst_n(rst_n), .pressed(~k1_up),
        .tog(ltog), .short_pulse(k1_short), .holding(k1_hold));

    angle_ctrl u_ang (
        .clk(clk), .rst_n(rst_n),
        .key_inc(k1_short), .key_dec(1'b0),          // KEY2 恒不按下：症状是 +1 不是 359
        .frame_tgl(fs_tgl), .auto_en(auto_en), .speed(3'd1),
        .angle(angle), .rotate_active(rotate_active));

    always #10 clk = ~clk;                            // 50 MHz sys_clk

    integer errors = 0, inc_cnt, i;

    task expect;
        input [120*8:1] name;
        input cond;
        begin
            if (cond !== 1'b1) begin errors = errors + 1; $display("  FAIL %0s", name); end
        end
    endtask

    // 跑 n 拍：统计 key_inc 事件枚数，并按真帧率翻 frame_tgl（auto_en 由调用者钉）
    task run_n;
        input integer n;
        input [120*8:1] tag;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk);
                #1;                                   // 取样点放在 NBA 之后（读旧值那条老坑）
                if (k1_short) inc_cnt = inc_cnt + 1;
                if ((i % FRAME) == (FRAME - 1)) fs_tgl = ~fs_tgl;
            end
            $display("[tb_v111_key_boot.v:69] INFO %0s：angle=%0d rotate_active=%0b ltog=%0b k1_up=%0b short_pulse 累计=%0d",
                     tag, angle, rotate_active, ltog, k1_up, inc_cnt);
        end
    endtask

    // 一次"上电"：复位按住几拍再放开，链的复位值就是上电值
    task fresh_boot;
        begin
            rst_n = 0; key_n = 1'b1; auto_en = 0; fs_tgl = 0; inc_cnt = 0;
            repeat (8) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        // ---- R：上电复位值 ----
        fresh_boot();
        rst_n = 1; #1;
        expect("R 复位释放这一拍 angle=0（那一度不是复位值给的）", angle == 9'd0 && rotate_active == 1'b0);
        expect("R2 同一拍 ltog=0、k1_up=1（按键链认「松着」）", ltog == 1'b0 && k1_up == 1'b1);

        // ---- B：全程为高（PULLUP 之后电气上必然的状态）----
        key_n = 1'b1;
        run_n(3 * DBN, "B 线全程高");
        expect("B 全程高 ⇒ 一枚短按都不许发、angle 保持 0", inc_cnt == 0 && angle == 9'd0);

        // ---- D：低于去抖窗的毛刺（0.5×DBN）⇒ 不算按下 ----
        fresh_boot(); rst_n = 1; #1;
        key_n = 1'b0; run_n(DBN / 2, "D 按 0.5×去抖窗");
        key_n = 1'b1; run_n(2 * DBN, "D 松手之后再等 2×去抖窗");
        expect("D 毛刺短于去抖窗 ⇒ 不发短按、angle 保持 0（A 不是「给个低电平就红」）",
               inc_cnt == 0 && angle == 9'd0);

        // ---- A：上电那次低电平（1.5×去抖窗）随后回高 ----
        // ⚠ 这四条按**应该怎样**判（不是描述现状）：r112 的武装门要求"复位释放后那次低电平
        //    既不被确认成按下、也不发事件"。改前的红就是凭据 `build/evidence/r112_key_boot_before.txt`
        //    （那份件里 A 腿的 INFO 实测 `k1_up=0`、`angle=1`、`short_pulse 累计=1` ⇒ A1/A2/A3/A5 四条同时红，
        //    件里数到的 FAIL 是 3 条，因为当时 A1 还写成"描述现状"；A1 的改前读数直接从它自己那行 INFO 读）。
        fresh_boot(); rst_n = 1; #1;
        key_n = 1'b0; run_n((DBN * 3) / 2, "A 浮空读低 1.5×去抖窗");
        expect("A1 上电那次低电平**不许**被确认成按下：k1_up 必须保持 1", k1_up == 1'b1);
        key_n = 1'b1; run_n(2 * DBN, "A 线回高（松手）");
        expect("A2 上电那次低电平**不许**发短按（修前红，r112 武装门之后必须绿）", inc_cnt == 0);
        expect("A3 ⇒ angle 必须保持 0（用户报的'上电就是 1 度'就是这里红掉的）", angle == 9'd0 && rotate_active == 1'b0);
        expect("A4 模式位没动（用户只看到角度变了 ⇒ 长按阈值没被跨过）", ltog == 1'b0);
        run_n(4 * FRAME, "A 再等 4 帧（auto_en 仍为 0）");
        expect("A5 帧沿 + auto_en=0 ⇒ 角度不涨，且全程没多出事件（修前红）", angle == 9'd0 && inc_cnt == 0);

        // ---- A6 反空对照：门开过之后，**真人**短按必须照常生效 ----
        // 少了这一条，"把上电那次吞掉"与"把按键整个弄哑"在判据里长得一模一样。
        key_n = 1'b0; run_n((DBN * 3) / 2, "A6 真人按住 1.5×去抖窗");
        key_n = 1'b1; run_n(2 * DBN, "A6 真人松手");
        expect("A6 门开后的真短按必须恰好加 1 度（angle 0→1、全程只一枚事件、模式位不动）",
               angle == 9'd1 && inc_cnt == 1 && ltog == 1'b0);

        // ---- C：跨过长按阈值（这里真参数是 0.6 s）⇒ 翻模式位、不动角度 ----
        // ⚠ 按住时长要从**去抖确认之后**起算：key_long 吃的 pressed 是 `~k1_up`，而 k1_up 要过 DBN 拍才落 0。
        //   第一跑我按 HOLD+500 拍算，实测差 1000 拍没到阈值（C1 红）—— 那是我的期望错，不是 DUT 错。
        // r112 加了武装门之后，这一腿**先等门开**再按：这里要测的是"合法长按只切模式"；
        //   "上电就趴着不动"那一类归 A 腿管（门不开 ⇒ 既不转角度也不切模式，是有意的）。
        fresh_boot(); rst_n = 1; #1;
        run_n(DBN + 50, "C 先让门开（线松着满一个窗口）");
        expect("C0 门开之前不许确认按下：k1_up 仍为 1", k1_up == 1'b1);
        key_n = 1'b0; run_n(HOLD + DBN + 500, "C 按住跨过长按阈值（含去抖那 1×DBN）");
        expect("C1 长按 ⇒ tog 翻一次", ltog == 1'b1);
        expect("C2 长按期间不许发短按（ISSUES #55 那一条在这支链上也得成立）", inc_cnt == 0);
        key_n = 1'b1; run_n(2 * DBN, "C 松手");
        expect("C3 松手也不补发 ⇒ angle 保持 0", angle == 9'd0 && inc_cnt == 0);

        if (errors == 0) $display("PASS tb_v111_key_boot");
        else             $display("FAIL tb_v111_key_boot errors=%0d", errors);
        $finish;
    end

    initial begin
        #20_000_000;   // 20 ms 仿真时间上限：真实跑量约 (3+3+5+6+35)×1e3 拍 ≈ 2.6 ms
        $display("FAIL tb_v111_key_boot timeout");
        $finish;
    end
endmodule
