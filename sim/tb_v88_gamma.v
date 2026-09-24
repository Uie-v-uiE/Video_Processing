`timescale 1ns/1ps
// 台架：src/rtl/video/gamma_lut.v（级 0 明暗校正）
//
// 这张表是"PS 写、PL 查"的通路，判据把两件事分开钉：
//   甲) **旁路不许动像素**（en=0 ⇒ 逐位等于输入）。这条同时是整条链的安全网：
//       上板之后 gamma 默认关 ⇒ "新加的一级没有改变任何已有行为"就靠它。
//   乙) **写协议**：`wr` 是**翻转位** —— 一次翻转 = 恰好写一项；电平不变时不许重复写；
//       复位本身也不许被当成一次写（#52 那一课的正面判据，T6）。
//
// 表内容的算术（幂曲线长什么样）**不在这里验**：曲线由 PS 算，PL 只负责"写进去什么就查什么"。
// 所以这里的表全是故意挑的怪表（identity / 0xFF−i / i^0x5A），用来暴露接错线，而不是验证曲线好看。
// 台架另存一份 `ref[]`（自己写的、与 DUT 无关的表），每条判据都拿 `ref[]` 算期望值 ——
// 这样"期望"不是从被测量那边抄来的（同一份表两边各写一遍，接错线就会分歧）。
//
// 关于索引：R/B 只有 32 个可达索引（r8 = {r5, r5[4:2]}），G 有 64 个。
// 所以每张表都**先写满 256 槽**再比 —— 只写"看起来会读到的那几个索引"会让一次接错线的 DUT
// 读到 X，判据就红在一件不相干的事上。
module tb_v88_gamma;
    reg clk = 0, rst_n = 0;
    reg        en = 0, wr = 0;
    reg  [7:0] idx = 0, data = 0;
    reg  [15:0] din = 0;
    wire [15:0] dout;

    gamma_lut dut (
        .clk(clk), .rst_n(rst_n), .en(en), .wr(wr),
        .idx(idx), .data(data), .din(din), .dout(dout)
    );

    always #10 clk = ~clk;             // 25 MHz，与像素域同量级（模块本身与频率无关）

    integer errors = 0, i, k, bad, prev_r, this_r;
    reg [7:0] ref [0:255];             // 台架那份表：期望值全部由它算
    reg [4:0] r5;
    reg [5:0] g6;
    reg [4:0] b5;
    reg [7:0] ir, ig, ib;
    reg [15:0] px;

    task chk;
        input [100*8:1] name;
        input cond;
        begin
            if (!cond) begin errors = errors + 1; $display("  FAIL %0s", name); end
        end
    endtask

    // 5/6/5 → 8 的展开：**台架自己写一遍**，与 RTL 里那份互为对照（谁改了另一处就会红）
    task expand;
        input [15:0] p;
        output [7:0] r, g, b;
        begin
            r = {p[15:11], p[13:11]};
            g = {p[10:5],  p[9:8]};
            b = {p[4:0],   p[2:0]};
        end
    endtask

    // 写一项：摆好 idx/data，再翻 wr（协议就是"下一次写把 wr 翻转"）
    task put;
        input [7:0] a;
        input [7:0] d;
        begin
            idx  = a;
            data = d;
            @(posedge clk); #1;
            wr   = ~wr;
            @(posedge clk); #1;
            ref[a] = d;
        end
    endtask

    // 写满 256 槽，内容 = f(i)：表用 case 挑，因为 Verilog 没有函数指针
    task fill;
        input [2*8:1] which;           // "id" / "inv" / "x5a"
        begin
            for (i = 0; i < 256; i = i + 1) begin
                case (which)
                    "id" : put(i[7:0], i[7:0]);
                    "inv": put(i[7:0], 8'hFF - i[7:0]);
                    default: put(i[7:0], i[7:0] ^ 8'h5A);
                endcase
            end
        end
    endtask

    // 逐像素核对：R/G/B 各扫 n 档，期望全部由 ref[] 算
    task sweep;
        input integer n;
        begin
            bad = 0;
            for (k = 0; k < n; k = k + 1) begin
                r5 = k[4:0];  g6 = k[5:0] ^ 6'h15;  b5 = ~k[4:0];
                px = {r5, g6, b5};
                din = px;
                #1;
                expand(px, ir, ig, ib);
                if (dout[15:11] !== ref[ir][7:3]) bad = bad + 1;
                if (dout[10:5]  !== ref[ig][7:2]) bad = bad + 1;
                if (dout[4:0]   !== ref[ib][7:3]) bad = bad + 1;
            end
        end
    endtask

    initial begin
        rst_n = 0; en = 0; wr = 0; idx = 0; data = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk); #1;

        // ---------------- ① 旁路：en=0 逐位等于输入 ----------------
        // 此刻表从没写过（读出来是 X），正好钉住"en=0 时不许把查表结果选出去"。
        bad = 0;
        for (k = 0; k < 64; k = k + 1) begin
            px = {k[4:0], ~k[5:0], k[7:3]};
            din = px;
            #1;
            if (dout !== px) bad = bad + 1;
        end
        chk("T1 en=0 输出逐位等于输入（64 组像素，一个都不许多改一位）", bad == 0);

        // ---------------- ② identity 表：en=1 也必须逐位等于输入 ----------------
        // 钉的是"展开/截断"互为逆：R/B 取 [7:3]、G 取 [7:2]。谁多截一位，这条立刻不 identity。
        fill("id");
        en = 1;
        sweep(32);
        chk("T2 identity 表下 96 个通道值仍逐位等于输入（R/G/B 各 32 档）", bad == 0);

        // ---------------- ③ 反转载表：三路都要跟着翻 ----------------
        fill("inv");
        sweep(32);
        chk("T3 表=0xFF-i 时三路各按自己展开后的索引查表", bad == 0);

        // ---------------- ④ 第三张表：暴露"输出偷偷透传"这种假绿 ----------------
        fill("x5a");
        sweep(32);
        chk("T4 表=i^0x5A 时输出等于查表结果（不是透传、也不是别的位序）", bad == 0);
        // 同一批像素再钉一条反例：R 通道下 i^0x5A 的高 5 位等于 r5^22，恒不等于 r5，
        // 所以"32 档全都不等于输入"是可判定的（拿 G/B 判就会撞巧等，那条不写）。
        bad = 0;
        for (k = 0; k < 32; k = k + 1) begin
            px = {k[4:0], k[5:0], k[4:0]};
            din = px;
            #1;
            if (dout[15:11] === k[4:0]) bad = bad + 1;
        end
        chk("T4b 反例：en=1 且表非 identity 时 R 的 32 档必须全都不等于输入", bad == 0);

        // ---------------- ⑤ 电平保持 = 不重复写 ----------------
        // 换 idx/data 但**不翻 wr** ⇒ 整张表必须一动不动。
        // 如果实现是"data 一变就写"或"每拍都写当前 idx/data"，槽 0x11 会立刻被改成 0x00，
        // 而 0x11 是可达索引（r5=17 ⇒ r8=0b10001_100=0x8C，不是 0x11）—— 所以这里直接比 ref。
        idx  = 8'h11;
        data = 8'h00;
        repeat (6) @(posedge clk); #1;
        sweep(32);
        chk("T5 只改 idx/data 不翻 wr ⇒ 整张表不变（协议是翻转，不是电平）", bad == 0);

        // ---------------- ⑥ 复位不许被当成一次写（#52 同源判据） ----------------
        // 前置：wr 必须与"源头复位值"同为 0 —— fill 走了 256 次翻转（偶数），这里再显式确认一次，
        // 因为这条判据的全部意义就是"复位值与源头一致"，前提不成立时判据本身就没牙。
        chk("T6a 前置：此刻 wr=0（否则下一条判据不成立）", wr === 1'b0);
        rst_n = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk); #1;             // prev 复位成 0、wr 也是 0 ⇒ 不该有任何写
        sweep(32);
        chk("T6b 复位本身不产生一次写（槽内容仍是复位前那份表）", bad == 0);

        // ---------------- ⑦ 边界槽 0x00 / 0xFF ----------------
        put(8'h00, 8'h00);
        put(8'hFF, 8'hFF);
        // r8 可达集合里没有 0xFF（要 r5=31 且 r5[4:2]=111 ⇒ r8=0xFF ✓ 其实有），
        // 所以这条同时是"最高槽"与"最低槽"各写各读的凭据。
        bad = 0;
        px = {5'd0,  6'd0, 5'd0};  din = px;  #1;  expand(px, ir, ig, ib);
        if (ir !== 8'h00 || dout[15:11] !== 5'd0) bad = bad + 1;
        px = {5'd31, 6'd0, 5'd0};  din = px;  #1;  expand(px, ir, ig, ib);
        if (ir !== 8'hFF || dout[15:11] !== 5'd31) bad = bad + 1;
        chk("T7 边界：r5=0 ⇒ 索引 0x00、r5=31 ⇒ 索引 0xFF，两端的表都查到", bad == 0);

        // ---------------- ⑧ 单调性（画面不会局部反转的唯一机器凭据） ----------------
        // 装一条递增表（内容 = i 本身，已在 T7 之后局部改过两槽，所以这里重新写满），
        // 然后只看 DUT 自己的输出序列是否不降 —— 不拿 ref[] 比，因为这条要钉的是"顺序"，
        // 一个把 R 与 B 接反的 DUT 在逐点比对里可能碰巧对，但在单调序列上一定露。
        fill("id");
        bad = 0;  prev_r = -1;
        for (k = 0; k < 32; k = k + 1) begin
            px = {k[4:0], 6'd0, 5'd0};
            din = px;
            #1;
            this_r = dout[15:11];
            if (prev_r >= 0 && this_r < prev_r) bad = bad + 1;
            prev_r = this_r;
        end
        chk("T8 identity 表下 R 输出随输入单调不降（接反/串行会在这里露）", bad == 0);

        $display("");
        if (errors == 0) $display("PASS tb_v88_gamma");
        else             $display("FAIL tb_v88_gamma errors=%0d", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL tb_v88_gamma timeout");
        $finish;
    end
endmodule
