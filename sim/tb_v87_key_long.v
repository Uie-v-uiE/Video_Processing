`timescale 1ns/1ps
// 台架：src/rtl/util/key_long.v（一个按键的两种语义）
//
// 用户 2026-09-24 报的两条都归这里：
//   · "长按的话总会先触发一次短按" ⇒ 短按以前由 key_debounce 在**按下沿**发；
//   · "有时候直接长按没反应，先点按一下再长按一般就可以切" ⇒ 1.2 s 阈值 + 全程没有反馈。
// 所以这个台架钉四件事：
//   T1 短按（按 0.3 s 松手）：只发 short_pulse，**不许**动 tog
//   T2 长按（按到阈值）：tog 恰好翻一次，且**在按住期间就翻**（不等到松手）
//   T3 长按后继续按住不放：不许再翻第二次（fired 门）
//   T4 长按后松手：不许补发 short_pulse（否则"长按顺带转 1°"这条就还在）
//   T5 松手之后重新武装：再按一次还能长按生效
//   T6 holding：过 ARM（0.2 s）就亮、到阈值就灭 —— LED 的反馈来自它
//   T7 反例（判据自己的判据）：如果 short_pulse 是"按下沿"发的，T2 期间它必然为 1；
//      这里显式检查"按住期间 short_pulse 一直是 0"，写法退回旧版就会红。
//
// 时钟按 sys_clk = 50 MHz（20 ns）；阈值通过参数缩到毫秒级，仿真才跑得完，
// **逻辑与真阈值完全一致**（HOLD/ARM 都是参数）。
module tb_v87_key_long;

    // 真硬件用 30_000_000 / 10_000_000（0.6 s / 0.2 s）；这里同比例缩 1000 倍，
    // 保持 ARM:HOLD = 1:3 的相对关系 —— 判据里凡是用到"之间"的地方都依赖这个比例。
    localparam integer HOLD = 30_000;
    localparam integer ARM   = 10_000;

    reg clk = 0, rst_n = 0, pressed = 0;
    wire tog, short_pulse, holding;

    key_long #(.HOLD_CYC(HOLD), .ARM_CYC(ARM)) u_dut (
        .clk(clk), .rst_n(rst_n), .pressed(pressed),
        .tog(tog), .short_pulse(short_pulse), .holding(holding)
    );

    always #10 clk = ~clk;             // 50 MHz

    integer errors = 0, sp_cnt, i;

    task expect;
        input [100*8:1] name;
        input cond;
        begin
            if (!cond) begin errors = errors + 1; $display("  FAIL %0s", name); end
        end
    endtask

    // 按住 n 拍，期间统计 short_pulse 出现次数（应当恒 0）与 holding 的形态
    task hold_n;
        input integer n;
        input [100*8:1] tag;
        begin
            sp_cnt = 0;
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk);
                #1;                     // 取样点放在 NBA 之后，避免读到旧值
                sp_cnt = sp_cnt + (short_pulse ? 1 : 0);
            end
            $display("INFO %0s：按住期间 short_pulse 次数=%0d holding=%0b tog=%0b",
                     tag, sp_cnt, holding, tog);
        end
    endtask

    initial begin
        rst_n = 0; pressed = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        #1;
        expect("T0 复位后 tog=0、holding=0", tog === 1'b0 && holding === 1'b0);

        // ---- T1 短按：0.5×HOLD 之后松手 ⇒ 只发一次 short_pulse，不动 tog ----
        pressed = 1;
        hold_n(ARM + 200, "T1 短按按住");          // 过 ARM、远不到 HOLD
        expect("T1a 按住期间（未到阈值）绝不发短按脉冲 —— 旧写法在这里必红", sp_cnt == 0);
        expect("T1b 过 ARM 之后 holding=1（LED 反馈的来源）", holding === 1'b1);
        pressed = 0;
        @(posedge clk); #1;              // 模块要下一个时钟沿才看见松手
        expect("T1c 松手的那一拍发 short_pulse", short_pulse === 1'b1);
        @(posedge clk); #1;
        expect("T1d 只发一拍（再下一拍就撤）", short_pulse === 1'b0);
        expect("T1e 短按不动 tog", tog === 1'b0);
        expect("T1f 松手后 holding 清零", holding === 1'b0);

        // ---- T2/T3/T4 长按：到阈值当拍翻 tog，继续按住不重复，松手不补发短按 ----
        pressed = 1;
        hold_n(ARM - 100, "T2a 阈值前");
        expect("T2b 没到阈值时 holding 还没亮（ARM 之前）", holding === 1'b0);
        hold_n(ARM + 100, "T2c 过 ARM 未到阈值");
        expect("T2d 这一段 holding 应该已经亮了", holding === 1'b1);
        hold_n(HOLD - (ARM + 200), "T2e 逼近阈值");
        #1;
        expect("T2f 松手前 tog 已经翻过一次", tog === 1'b1);
        expect("T2g 长按期间同样不许发 short_pulse（= 用户报的'总先触发一次短按'）", sp_cnt == 0);
        hold_n(5 * ARM, "T3 到阈值后继续按住");
        expect("T3b 继续按住不再翻第二次", tog === 1'b1);
        expect("T3c 到阈值后 holding 撤掉（LED 表示'已生效'而不是'还在计'）", holding === 1'b0);
        pressed = 0;
        @(posedge clk); #1;
        expect("T4 长按松手不补发短按", short_pulse === 1'b0);

        // ---- T5 重新武装：再按一次还能生效 ----
        pressed = 1;
        hold_n(HOLD + 50, "T5a 第二次长按");
        pressed = 0; @(posedge clk); #1;
        expect("T5b 第二次长按 ⇒ tog 翻回 0（一次按下恰好一次事件）", tog === 1'b0);
        expect("T5c 全程没有短按混进来", sp_cnt == 0);

        // ---- T6 抖动：按下不足 ARM 就松手，仍然算一次短按（去抖在 key_debounce 里做，不在这里）----
        pressed = 1; hold_n(50, "T6a 极短按住"); pressed = 0; @(posedge clk); #1;
        expect("T6b 极短按下松手也发短按（去抖是 key_debounce 的职责，本模块不许吞事件）",
               short_pulse === 1'b1);

        $display("");
        if (errors == 0) $display("PASS tb_v87_key_long");
        else             $display("FAIL tb_v87_key_long errors=%0d", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL tb_v87_key_long timeout");
        $finish;
    end
endmodule
