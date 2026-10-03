`timescale 1ns/1ps
// tb_v113_key_powup —— "没人碰键，屏上那一格就必须是 0 度"：按板上的真接线跑，整支**不碰 rst_n**。
//
// 立案背景（ISSUES #256，根因终于量出来了）：
//   `src/rtl/top/system_top.v:250` 把 u_pl 的 `sys_rst_n` 恒接 `1'b1`
//     ⇒ `key_debounce` 里 `if (!rst_n) key_stable <= 1'b1;` 是**死支**。
//   综合实测（`build/evidence/r113_ff_init.txt`，两份 dcp 各量一遍、每遍 COMPARED=96）：
//     `u_pl/u_k1/key_stable_reg` = FDRE、**INIT=1'b0**（想要的是 1=松着）；
//     `u_pl/u_ang/angle_reg[*]` = FDRE、INIT=1'b0（这个与想要的一致）。
//   ⇒ 上电"线上松着（4.7 k 上拉）、寄存器说按着"，去抖窗走完那一沿在下游 `key_long` 里就是
//     一次"松手" ⇒ 白补一枚短按 ⇒ `ROT:` 就是 1 度；而 `angle_reg` 的 INIT=0 解释了
//     **为什么每次配置都正好是 1**（不是 2、3）：重配一次就"清零 + 白送一度"。
//   修法 = 把上电语义写进声明（`key_stable = 1'b1` 等）。带着"复位恒 1"再综合一次，仍量到
//     FDRE INIT=1'b1 ⇒ 位流真的带上了（`build/evidence/r113_init_tied_rst.txt`）。
//   改前三腿对照的凭据：`build/evidence/r113_powup_verdict.txt` + `build/evidence/pu113/`
//     （r110 红：inc=1 angle=1；r112 带武装门**同样红** ⇒ 武装门没打中这个因；fix 绿）。
//
// 为什么这支不能拿 tb_v111 代替：那一支是先拉复位再放开，恰好把这个坑盖住（复位一放寄存器就是 1）。
// 标签一律 ASCII（记忆里那条老规矩：CJK 进 $display 在 xsim 日志里是坏字节，而且
//   `[8*N:1]` 会从**左**截掉长名 ⇒ 判据 id 一旦被截，车道那句 grep 就看不见红了）。
module tb_v113_key_powup;
    localparam integer DBN  = 1000;    // 去抖窗（缩放；板上是 1_000_000 = 20 ms @50 MHz）
    localparam integer HOLD = 30000;   // 长按阈值
    localparam integer ARM  = 10000;   // LED 旗标阈值
    localparam integer RUN  = 3 * DBN + 500;

    reg clk = 1'b0;
    reg key_n_r = 1'b1;                // 板上 4.7 k 上拉 ⇒ 不碰键时恒"松着"
    always #10 clk = ~clk;

    wire p1, k1_up, ltog, short_pulse, holding;
    wire [8:0] angle;
    wire       rotate_active;

    key_debounce #(.CNT_MAX(DBN)) u_k1 (
        .clk(clk), .rst_n(1'b1), .key_n(key_n_r),   // 复位恒 1 = system_top.v:250 的真接线
        .pulse(p1), .key_stable(k1_up));
    key_long #(.HOLD_CYC(HOLD), .ARM_CYC(ARM)) u_k1l (
        .clk(clk), .rst_n(1'b1), .pressed(~k1_up), .tog(ltog),
        .short_pulse(short_pulse), .holding(holding));
    angle_ctrl u_ang (
        .clk(clk), .rst_n(1'b1), .key_inc(short_pulse), .key_dec(1'b0),
        .frame_tgl(1'b0), .auto_en(1'b0), .speed(3'd0),
        .angle(angle), .rotate_active(rotate_active));

    integer inc = 0, ev_t = -1;
    always @(posedge clk) if (short_pulse === 1'b1) begin
        inc = inc + 1;
        if (ev_t < 0) ev_t = $time;
    end

    // 硬件里 FDRE 上电是 0（网实测到的），xsim 里没复位的变量默认是 X。不注入就是在比 X。
    // ⚠ 这里**故意不碰** key_stable / key_sync0 / key_sync1 / key_prev：它们该由 RTL 的声明初值
    //   自己立起来，那正是 P0/P0b 要判的东西（删掉 `= 1'b1` 就会露成 X ⇒ 立刻红）。
    initial begin
        u_k1.cnt          = 21'd0;
        u_k1.acnt         = 21'd0;
        u_k1.armed        = 1'b0;
        u_k1l.cnt         = 28'd0;
        u_k1l.fired       = 1'b0;
        u_k1l.tog         = 1'b0;
        u_k1l.short_pulse = 1'b0;
        u_k1l.holding     = 1'b0;
        u_ang.angle       = 9'd0;
        u_ang.fs_s        = 3'd0;
    end

    integer errors = 0, judged = 0;
    task chk(input [8*90:1] name, input cond);
        begin
            judged = judged + 1;
            if (cond) $display("PASS %0s", name);
            else begin $display("FAIL %0s", name); errors = errors + 1; end
        end
    endtask

    initial begin
        #1;
        $display("INFO PWRUP key_stable=%b sync0=%b sync1=%b angle=%0d",
                 u_k1.key_stable, u_k1.key_sync0, u_k1.key_sync1, angle);
        chk("P0 key_stable must come up 1'b1 (released), not X/0", u_k1.key_stable === 1'b1);
        chk("P0b both synchroniser stages come up 1'b1",
            u_k1.key_sync0 === 1'b1 && u_k1.key_sync1 === 1'b1);

        repeat (RUN) @(posedge clk);
        $display("INFO after %0d cycles inc=%0d angle=%0d event_time=%0d", RUN, inc, angle, ev_t);
        chk("A1 no key touched => zero short-press events", inc == 0);
        chk("A2 angle stays 0 (OSD ROT cell must read 0, not 1)", angle == 9'd0);
        chk("A3 long-press toggle not given away either", ltog == 1'b0);
        chk("A4 rotate_active stays 0 (picture does not rotate)", rotate_active == 1'b0);

        // 反面对照：真按一次必须恰好走一度 —— 没有这一条，A1 的绿可能只是链子根本不工作。
        @(posedge clk);
        key_n_r = 1'b0;                    // 真按住
        repeat (DBN + 20) @(posedge clk);  // 过去抖窗、不到长按阈值
        key_n_r = 1'b1;                    // 松手
        repeat (DBN + 40) @(posedge clk);
        $display("INFO control (one real press) inc=%0d angle=%0d", inc, angle);
        chk("B1 one real press => exactly one event", inc == 1);
        chk("B2 => angle +1 (proves A1 is not a dead-green)", angle == 9'd1);

        if (judged < 8) begin
            $display("FAIL FLOOR only %0d criteria judged (ruler idled)", judged);
            errors = errors + 1;
        end
        if (errors == 0) $display("RESULT tb_v113_key_powup PASS checks=%0d", judged);
        else             $display("RESULT tb_v113_key_powup FAIL errors=%0d judged=%0d", errors, judged);
        $finish;
    end
endmodule
