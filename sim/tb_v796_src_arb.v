`timescale 1ns/1ps
// 台架：src/rtl/util/src_arb.v（片源仲裁）
//
// 要钉住的三件事，每条都配一个"反面对照"，否则测了等于没测：
//   A 只有两个引擎都空闲才换手         —— 对照：把 busy 拉起来，owner 必须**不动**
//   B 往 PS 让位要等一段静默（滞回）     —— 对照：T_OFF_CYC=0 的第二个实例必须**立刻**让位
//   C 帧间隔卡在阈值上不会来回抢总线     —— 对照：同一段抖动激励里统计翻转次数
// 另外 D 检查"硬件里真正用的那个常数"：用**默认参数**例化第三个实例，断言它在 100k 拍内
// 还没有让位（源码里写的是 2_000_000 拍 = AXI 100 MHz 下 20 ms）—— 这样"参数被谁改小了"
// 这种错会被这个台架抓到，而不是只在文档里被发现。
// E 是 2026-09-23 板级撞到的那一条：**eth_live 说"活着"但量它的时钟已经不准** ⇒ 必须让位。
//   现场是推流停下后画面钉在最后一帧、STALL=9999、SD 接不回来。根因不在 stall_ms 算错，
//   而在 RTL8211 断链时把 RXC 拉到 ~2.5 MHz（不停），于是 stall_ms 这个"ms"慢了约 48 倍，
//   那一位能连着十几秒一直为 1。当时把 `&& 时基健康` 写在 system_top 的裸与门里，
//   台架碰不到 ⇒ 判据等于没验；所以现在把这条限定搬进 src_arb，由 E 段钉住。
module tb_v796_src_arb;
    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;             // 10 ns ⇒ 100 MHz，与 AXI 域同名同频

    reg  eth_live = 1'b0;
    reg  tb_ok    = 1'b1;             // 量 eth_live 的那个源时基是否还准
    reg  [1:0] sel = 2'd0;            // 0=AUTO 1=强制 ETH 2=强制看 fb（=SD 回放；长按/命令切来的）
    reg  row_busy = 1'b0, fill_busy = 1'b0;
    wire owner_a, owner_b, owner_d;
    // V8-7：三个实例都接上 why_ps —— 不接就等于这条出口没人判（#55 那一类"设了没人看"）。
    wire [2:0] why_a, why_b, why_d;

    // 被测：机制用小常数，跑得快
    src_arb #(.T_OFF_CYC(200)) u_a (
        .clk(clk), .rst_n(rst_n), .eth_live(eth_live), .eth_tb_ok(tb_ok), .sel(sel),
        .row_busy(row_busy), .fill_busy(fill_busy), .owner_eth(owner_a),
        .why_ps(why_a));
    // 对照 1：滞回长度设成 0 ⇒ 除了 busy 互锁以外没有任何东西推迟让位
    src_arb #(.T_OFF_CYC(0)) u_b (
        .clk(clk), .rst_n(rst_n), .eth_live(eth_live), .eth_tb_ok(tb_ok), .sel(sel),
        .row_busy(row_busy), .fill_busy(fill_busy), .owner_eth(owner_b),
        .why_ps(why_b));
    // 对照 2：**默认参数**（硬件用的就是它）⇒ 用来证明 20 ms 这件事真的在 RTL 里
    src_arb u_d (
        .clk(clk), .rst_n(rst_n), .eth_live(eth_live), .eth_tb_ok(tb_ok), .sel(sel),
        .row_busy(row_busy), .fill_busy(fill_busy), .owner_eth(owner_d),
        .why_ps(why_d));

    integer errors = 0, flips = 0, i;
    reg prev_a, pb;
    // V8-7（G 段用）：期望值在**台架这边**按激励手算，声明放在模块级
    //（xvlog 不允许 initial 块里"先语句后声明"，这条踩过一次）
    reg  [2:0] exp_why;
    integer    gi, ngood, ndis;

    task expect(input [639:0] name, input cond);   // 90 个 ASCII 字符：32 位宽的 name 会把标签的头几个字节挤掉
        begin
            if (cond !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL %0s (t=%0t)", name, $time);
            end else $display("PASS %0s", name);
        end
    endtask

    initial begin
        $dumpfile("tb_v796_src_arb.vcd");
        // ---- 复位：两边都没东西 ⇒ 主人是 PS（owner_eth = 0）
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        expect("R0 reset: PS owns by default",        owner_a === 1'b0 && owner_b === 1'b0 && owner_d === 1'b0);

        // ---- A1 ETH 活起来 + 空闲 ⇒ 立刻接手
        eth_live = 1'b1;
        repeat (4) @(posedge clk);
        expect("A1 eth live + idle -> ETH owns",  owner_a === 1'b1);

        // ---- A2 想切回 PS，但 PS 引擎正在拷贝 ⇒ 不许动
        eth_live = 1'b0;
        fill_busy = 1'b1;
        repeat (600) @(posedge clk);          // 远超 T_OFF=200
        expect("A2 no handover while fill_busy",   owner_a === 1'b1);
        fill_busy = 1'b0;
        repeat (300) @(posedge clk);
        expect("A2b idle + quiet>T_OFF -> PS owns", owner_a === 1'b0);

        // ---- A3 反向：owner=ETH 时 ETH 引擎自己在忙，也不许被抢
        eth_live = 1'b1;
        repeat (4) @(posedge clk);
        expect("A3 re-take needs idle (first holds)",   owner_a === 1'b1);
        eth_live = 1'b0; row_busy = 1'b1;
        repeat (600) @(posedge clk);
        expect("A3b no handover while row_busy", owner_a === 1'b1);
        row_busy = 1'b0;
        repeat (300) @(posedge clk);
        expect("A3c hands over once busy released",            owner_a === 1'b0);

        // ---- B 滞回有牙：T_OFF=0 的对照实例必须**立刻**让位
        eth_live = 1'b1;
        repeat (4) @(posedge clk);
        eth_live = 1'b0;
        repeat (3) @(posedge clk);
        expect("B1 control (T_OFF=0) yields at once",     owner_b === 1'b0);
        expect("B2 DUT still waiting out the quiet window",       owner_a === 1'b1);
        // （owner_b 之后再也回不去，是因为 eth_live=1 时才抢回来；下面重新拉高再确认）
        eth_live = 1'b1;
        repeat (4) @(posedge clk);
        expect("B3 control can take it back too",       owner_b === 1'b1);

        // ---- C 抖动：以 100 拍为周期翻转 eth_live（< T_OFF=200），owner 不得来回翻
        eth_live = 1'b1;
        repeat (4) @(posedge clk);
        flips = 0; prev_a = owner_a;
        for (i = 0; i < 12; i = i + 1) begin
            repeat (100) @(posedge clk);
            eth_live = ~eth_live;
            #1;                              // 让 owner_a 稳定后再采样
            if (owner_a !== prev_a) begin flips = flips + 1; prev_a = owner_a; end
        end
        expect("C1 at most 1 flip under chatter",     flips <= 1);
        expect("C2 still ETH after chatter",           owner_a === 1'b1);
        // 反面对照：同样时长里，无滞回的实例翻转了很多次 ⇒ 说明 C1 不是"本来就翻不了"
        // （Verilog-2001：块内不能声明，所以 bf/pb 提到模块级）
        flips = 0;
        pb = owner_b;
        for (i = 0; i < 12; i = i + 1) begin
            repeat (100) @(posedge clk);
            eth_live = ~eth_live;
            #1;
            if (owner_b !== pb) begin flips = flips + 1; pb = owner_b; end
        end
        expect("C3 control does flip on the same stimulus", flips >= 3);

        // ---- D 默认参数（硬件用的 2_000_000）：静默 100k 拍之后仍不能往 PS 让位
        eth_live = 1'b1;
        repeat (6) @(posedge clk);
        expect("D0 default-param instance takes ETH",         owner_d === 1'b1);
        eth_live = 1'b0;
        repeat (100_000) @(posedge clk);
        expect("D1 default T_OFF > 100k cycles (20 ms)", owner_d === 1'b1);
        expect("D2 small-T_OFF DUT already yielded",    owner_a === 1'b0);

        // ---- E 时基不准 ⇒ "活着"那一位不许信（板级：推流停止后 SD 接不回画面）
        eth_live = 1'b1; tb_ok = 1'b1;              // 先让三路都归 ETH
        repeat (6) @(posedge clk);
        expect("E0 preflight: all three owned by ETH",
               owner_a === 1'b1 && owner_b === 1'b1 && owner_d === 1'b1);
        tb_ok = 1'b0;                               // 位仍是 1，只是量它的时钟被拉到 ~1/48
        repeat (3) @(posedge clk);
        expect("E1 control (T_OFF=0) yields on a bad timebase", owner_b === 1'b0);
        expect("E2 DUT is still inside its quiet window",       owner_a === 1'b1);
        repeat (600) @(posedge clk);
        expect("E3 bad timebase hands the screen back to PS",   owner_a === 1'b0);
        // 反面对照：同一段激励里小常数实例已经放手，默认参数实例还在等它的 20 ms
        expect("E4 default-param instance still holds at 606 cyc", owner_d === 1'b1);
        repeat (2_100_000) @(posedge clk);           // > T_OFF(2e6) ⇒ 硬件配置也必须放手
        expect("E5 default T_OFF: ETH releases after ~20 ms",     owner_d === 1'b0);
        tb_ok = 1'b1;                               // 时钟恢复（重新推流/链路回来）
        repeat (6) @(posedge clk);
        expect("E6 recovery: ETH takes the bus back at once",     owner_a === 1'b1);

        // ---- F 手动锁（长按按键切来的 sel）：只改"谁想要总线"，不改"什么时候能换手" ----
        eth_live = 1'b0; tb_ok = 1'b1; sel = 2'd0;
        repeat (600) @(posedge clk);
        expect("F0 AUTO with no stream: PS owns", owner_a === 1'b0);
        sel = 2'd1;                                // 锁 ETH —— 明知没有流，就是要占住总线
        repeat (6) @(posedge clk);
        expect("F1 force-ETH takes the bus although eth_live=0", owner_a === 1'b1);
        fill_busy = 1'b1;
        sel = 2'd2;                                // 当场改成"强制看 fb"：DDR 引擎正在拷贝，不许切
        repeat (600) @(posedge clk);
        expect("F2 force-PS still waits for fill_busy (互锁没被绕开)", owner_a === 1'b1);
        fill_busy = 1'b0;
        repeat (300) @(posedge clk);
        expect("F3 force-PS hands over once idle", owner_a === 1'b0);
        sel = 2'd0; eth_live = 1'b1;
        repeat (6) @(posedge clk);
        expect("F4 AUTO resumes following eth_live", owner_a === 1'b1);
        sel = 2'd3; eth_live = 1'b0;               // 11 是保留值：必须按 AUTO 处理，不能当"强制看 fb"
        repeat (600) @(posedge clk);
        expect("F5 sel=11 behaves as AUTO", owner_a === 1'b0);

        // ---- G（V8-7）why_ps：PS 拿着屏幕"是因为什么"拿着 ----
        // 期望值在这里**按激励手算**（{强制看 fb, 没流, 时基不可信}），不引用 RTL 里任何式子 ——
        // 抄过来就等于"用被测代码验被测代码"，改了 bug 一起改判据就永远绿。
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        expect("G0 复位值必须是 011（没有流 + 时基未验），不是 000（那等于宣称一切正常）",
               why_a === 3'b011 && why_b === 3'b011 && why_d === 3'b011 && owner_a === 1'b0);
        rst_n = 1'b1;
        // G1 十六种激励逐条对表（sel 的四种编码全走一遍）。两个 busy 拉高 ⇒ 只看"原因"，
        // 不会被换手时序混进来。
        // bit2 的解码表写死在这里（只有 2'b10 = 「强制看 fb（SD）」点亮），**不抄 RTL 的 (sel==2'd10)**：
        // 上一版把激励拼成 sel={1'b0,gi[2]} ⇒ 01 是「强制 ETH」而不是「强制看 fb」，红的是台架自己。
        row_busy = 1'b1; fill_busy = 1'b1; ngood = 0;
        for (gi = 0; gi < 16; gi = gi + 1) begin
            sel      = gi[3:2];                       // 00=AUTO 01=强制ETH 10=强制看fb(SD) 11=保留(按 AUTO)
            eth_live = gi[1];
            tb_ok    = gi[0];
            case (sel)
                2'd10:   exp_why = {1'b1, ~eth_live, ~tb_ok};
                default: exp_why = {1'b0, ~eth_live, ~tb_ok};
            endcase
            repeat (3) @(posedge clk);
            if (why_a === exp_why && why_d === exp_why && why_b === exp_why) ngood = ngood + 1;
            else $display("  DBG G1 gi=%0d sel=%b live=%b tb=%b -> why_a=%b why_b=%b why_d=%b exp=%b",
                          gi, sel, eth_live, tb_ok, why_a, why_b, why_d, exp_why);
        end
        // 三条实例（含硬件用的默认参数那一条）都要对，且必须**判满 16 组**才算这条跑过
        expect("G1 十六组激励 x 三个实例，why_ps 全部等于手算期望（16/16）", ngood == 16);

        // G2 关键反例：**原因必须比换手先出现**。
        //      如果有人图省事把 why_ps 写成"从 owner_eth 反推"，G1 也会过（owner 与输入本来相关），
        //      但这一条会红 —— 它才是"这不是第二份判决"的证据。
        sel = 2'd0; eth_live = 1'b1; tb_ok = 1'b1; row_busy = 1'b0; fill_busy = 1'b0;
        repeat (6) @(posedge clk);
        expect("G2a 先回到「一切正常、ETH 拿着屏幕、why=000」",
               owner_a === 1'b1 && why_a === 3'b000);
        fill_busy = 1'b1;                            // PS 引擎正在拷贝 ⇒ 此刻绝对不许换手
        eth_live  = 1'b0;                            // 流停了
        repeat (30) @(posedge clk);                  // 远小于 T_OFF=200
        expect("G2b owner 还压在 ETH（互锁 + 滞回），但原因已经报「没有流」⇒ 原因来自输入不是来自结果",
               owner_a === 1'b1 && why_a === 3'b010);
        fill_busy = 1'b0;
        repeat (600) @(posedge clk);
        expect("G2c 真让位之后：owner=PS 且原因仍是「没有流」（同一个原因，两种 owner 都成立）",
               owner_a === 1'b0 && why_a === 3'b010);
        // G3 时基坏掉要单独报出来（板级那条 ≈2.5 MHz 的坑，见 E 段），不能与「没有流」混成一个码
        eth_live = 1'b1; tb_ok = 1'b0;              // 位还是 1，只是量它的时钟被拉慢
        repeat (3) @(posedge clk);
        expect("G3 时基不可信 → why bit0=1（与 bit1「没有流」分开编码）", why_a === 3'b001);

        if (errors == 0) $display("PASS tb_v796_src_arb");
        else             $display("FAIL tb_v796_src_arb errors=%0d", errors);
        $finish;
    end
endmodule
