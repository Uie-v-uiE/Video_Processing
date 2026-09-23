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
module tb_v796_src_arb;
    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;             // 10 ns ⇒ 100 MHz，与 AXI 域同名同频

    reg  eth_live = 1'b0;
    reg  row_busy = 1'b0, fill_busy = 1'b0;
    wire owner_a, owner_b, owner_d;

    // 被测：机制用小常数，跑得快
    src_arb #(.T_OFF_CYC(200)) u_a (
        .clk(clk), .rst_n(rst_n), .eth_live(eth_live),
        .row_busy(row_busy), .fill_busy(fill_busy), .owner_eth(owner_a));
    // 对照 1：滞回长度设成 0 ⇒ 除了 busy 互锁以外没有任何东西推迟让位
    src_arb #(.T_OFF_CYC(0)) u_b (
        .clk(clk), .rst_n(rst_n), .eth_live(eth_live),
        .row_busy(row_busy), .fill_busy(fill_busy), .owner_eth(owner_b));
    // 对照 2：**默认参数**（硬件用的就是它）⇒ 用来证明 20 ms 这件事真的在 RTL 里
    src_arb u_d (
        .clk(clk), .rst_n(rst_n), .eth_live(eth_live),
        .row_busy(row_busy), .fill_busy(fill_busy), .owner_eth(owner_d));

    integer errors = 0, flips = 0, i;
    reg prev_a, pb;

    task expect(input [639:0] name, input cond);   // 90 个 ASCII 字符：32 位宽的 name 会把标签的头几个字节挤掉
        begin
            if (!cond) begin
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

        if (errors == 0) $display("PASS tb_v796_src_arb");
        else             $display("FAIL tb_v796_src_arb errors=%0d", errors);
        $finish;
    end
endmodule
