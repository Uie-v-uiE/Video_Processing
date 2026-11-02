`timescale 1ns/1ps
// 一次性实验（拷贝树 /tmp/kx/pu113/，不入库）——问的是板上真值，不是"我以为的真值"：
//   `src/rtl/top/system_top.v:250` 把 `sys_rst_n` 恒接 **1'b1** ⇒ `key_debounce` 里
//   `if (!rst_n) key_stable <= 1'b1;` 是**死支**；综合实测（`build/evidence/r113_ff_init.txt`，
//   两份 dcp 各量一次、COMPARED=96）：`u_pl/u_k1/key_stable_reg`、`key_sync0_reg`、`key_sync1_reg`
//   全是 **FDRE、INIT=1'b0**（复位引脚根本没接）。⇒ 上电那 20 ms 里线上是"松着"（4.7 kΩ 上拉），
//   寄存器却说"按着"，确认沿就是"松手"⇒ key_long 补发一枚 short_pulse ⇒ angle 白涨 1°。
//   同一次量到 `u_pl/u_ang/angle_reg[*]` 也是 FDRE INIT=0 ⇒ **每配置一次 PL 就正好回到 1**，
//   与"刷完 elf 屏上就是 1 而不是 0、且不是 2/3"对上（elf 重载不复位这一域，所以它是配置时留下的）。
//
// 仿真必须建模位流的 INIT：xsim 里没复位的 reg 是 **X**，硬件里是 **0**（量出来的），
// 拿 X 当上电会让判据整个失真（第一版就是这么被自己的地板抓到：angle 读 X 判不了）。
// ⇒ A 腿在 #0 显式 deposit 上面量到的那一组 INIT；B 腿走一次真复位当对照（唯一差别 = 有没有复位过）。
`define PWRUP_INIT(inst_kl, inst_ang) \
    inst_kl.cnt = 28'd0; inst_kl.fired = 1'b0; inst_kl.tog = 1'b0; \
    inst_kl.short_pulse = 1'b0; inst_kl.holding = 1'b0; \
    inst_ang.angle = 9'd0; inst_ang.fs_s = 3'd0;

module tb_powup;
    localparam integer DBN   = 1000;    // 去抖窗（缩放值）
    localparam integer HOLD  = 30000;   // 长按阈值
    localparam integer ARM   = 10000;   // LED 计时旗标
    localparam integer RUN   = 2600;    // 2.6×去抖窗：够确认一次，不够到长按阈值

    reg clk = 1'b0;
    always #10 clk = ~clk;

    // ---- A 腿：rst_n 恒 1，与 system_top.v 给 u_pl 的实参一模一样 ----
    wire p1a, k1_up_a, ltog_a, short_a, holding_a;
    wire [8:0] angle_a; wire active_a;
    key_debounce #(.CNT_MAX(DBN)) k1 (.clk(clk), .rst_n(1'b1), .key_n(1'b1),
                                      .pulse(p1a), .key_stable(k1_up_a));
    key_long #(.HOLD_CYC(HOLD), .ARM_CYC(ARM)) kl1 (.clk(clk), .rst_n(1'b1),
                              .pressed(~k1_up_a), .tog(ltog_a),
                              .short_pulse(short_a), .holding(holding_a));
    angle_ctrl ang1 (.clk(clk), .rst_n(1'b1), .key_inc(short_a), .key_dec(1'b0),
                     .frame_tgl(1'b0), .auto_en(1'b0), .speed(3'd0),
                     .angle(angle_a), .rotate_active(active_a));

    // ---- B 腿：同一套模块，唯一区别 = 复位真的走过一次 ----
    reg rstn_b = 1'b0;
    wire p1b, k1_up_b, ltog_b, short_b, holding_b;
    wire [8:0] angle_b; wire active_b;
    key_debounce #(.CNT_MAX(DBN)) k2 (.clk(clk), .rst_n(rstn_b), .key_n(1'b1),
                                      .pulse(p1b), .key_stable(k1_up_b));
    key_long #(.HOLD_CYC(HOLD), .ARM_CYC(ARM)) kl2 (.clk(clk), .rst_n(rstn_b),
                              .pressed(~k1_up_b), .tog(ltog_b),
                              .short_pulse(short_b), .holding(holding_b));
    angle_ctrl ang2 (.clk(clk), .rst_n(rstn_b), .key_inc(short_b), .key_dec(1'b0),
                     .frame_tgl(1'b0), .auto_en(1'b0), .speed(3'd0),
                     .angle(angle_b), .rotate_active(active_b));

    integer inc_a = 0, inc_b = 0;
    always @(posedge clk) begin
        if (short_a === 1'b1) inc_a = inc_a + 1;
        if (short_b === 1'b1) inc_b = inc_b + 1;
    end
    // 事件时刻也记下来：判"白送一次"要看是不是只有那一枚，不是看总数顺眼
    integer ev_a_t = -1;
    always @(posedge clk) if (short_a === 1'b1 && ev_a_t < 0) ev_a_t = $time;

    initial begin
        // key_long / angle_ctrl 这些寄存器在**三种版本里都是 INIT=0**（量到的），
        // 仿真默认是 X ⇒ 不分腿都要注入，否则判据是在比 X。
        `PWRUP_INIT(kl1, ang1)
`ifdef HARNESS_INIT0
        // 未修的那两版：key_debounce 的"松着=1"从没进位流（复位支是死支）⇒ 硬件上电是 0
        k1.key_stable = 1'b0; k1.key_sync0 = 1'b0; k1.key_sync1 = 1'b0; k1.key_prev = 1'b0;
` ifndef NO_ARMED
        k1.armed      = 1'b0; k1.acnt = 21'd0; k1.cnt = 21'd0;
` endif
`endif
    end

    integer errors = 0;
    task chk(input [8*40:1] tag, input cond);
        begin
            if (cond) $display("PASS %0s", tag);
            else begin $display("FAIL  %0s", tag); errors = errors + 1; end
        end
    endtask

    initial begin
        #1;
        $display("INFO INIT A腿 key_stable=%b sync1=%b angle=%0d（X 就说明注入没生效，别看结论）",
                 k1.key_stable, k1.key_sync1, angle_a);
        if (k1.key_stable === 1'bx) begin
            $display("RESULT tb_powup BLOCKED 上电值取不到（层次名错？实验不算数）");
            $finish;
        end
        repeat (RUN) @(posedge clk);
        rstn_b = 1'b1;                       // B 腿此刻才释放复位
        repeat (RUN) @(posedge clk);
        $display("INFO A(=板上接线，无复位) inc=%0d angle=%0d 事件时刻=%0d key_stable 现在=%b",
                 inc_a, angle_a, ev_a_t, k1.key_stable);
        $display("INFO B(走过一次复位)   inc=%0d angle=%0d", inc_b, angle_b);

        // 期望按**定义**写：没人碰键，屏上那一格就该是 0°。
        chk("A1 不碰键不许自发短按", inc_a == 0);
        chk("A2 角度必须是 0",      angle_a == 9'd0);
        chk("B1 对照：复过一次位同样不许自发事件", inc_b == 0);
        chk("B2 对照：角度 0",      angle_b == 9'd0);
        repeat (RUN) @(posedge clk);
        chk("A3 即使红，也只白送一枚（停在 1 不是持续增长）", angle_a <= 9'd1);
        chk("A4 两腿唯一差别是复位：B 腿必须一直干净（否则红不能归因到复位缺失）", angle_b == 9'd0);

        if (errors == 0) $display("RESULT tb_powup PASS");
        else             $display("RESULT tb_powup FAIL errors=%0d", errors);
        $finish;
    end
endmodule
