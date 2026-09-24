`timescale 1ns/1ps
// 台架：ku5p/src/rtl/ku5p_cmd.v（PC → KU5P 的文本命令通道）
//
// 要钉住的四件事（每件都配反面对照，否则测了等于没测）：
//   A 三条命令的**语义**：CLR 出脉冲、SNAP 出脉冲、SPD<n> 落周期，且互相不误触发。
//     反面对照：SPD0 / SPD1X / 光"SPD" / HELLO 必须算坏命令 —— 近似匹配是最容易写错的一类，
//     而它坏了之后的现象是"命令好像生效了"，板上看不出来。
//   B 首尾空白被忽略：`CLR\r\n`、" SNAP " 与裸命令等价。
//     反面对照：**空载荷**既不记好也不记坏 —— 否则 PC 上一个探测包就把 cmds_bad 涨起来，
//     那个数字就不再是"有人下错了命令"的意思。
//   C **两种 p_eof 时序都必须认**：本板链路是"最后一个字节上一拍发出、eof 单独一拍"，
//     厂商风格是"eof 与最后一个字节同拍"。只认前者，`udp_rx_parser` 换个例化方式就会把
//     每条命令看成短一字节。这一段是本次唯一"新写而不是复用"的逻辑，所以必须有反例激励。
//   D 坏包（p_good=0）不执行、也不记账："命令没生效"要能被 cmds_ok 不动这件事观测到。
//
// 最后有一条**总账**（ok/bad 的绝对值必须等于逐条激励累加出来的数）：
// 中间任何一条判据被改坏、或者 DUT 多记/漏记一次，总账就会红。
module tb_v80_ku5p_cmd;
    localparam integer MAXB = 8;

    // 命令字面量一律**左对齐**填进 64 bit：`send` 取的是 bytes[63-8i -: 8]，
    // 写成 {"CLR",40'd0} 才是 'C''L''R' 依次在前三个字节（裸字符串常量是右对齐的）。
    // **尾部补零的位数必须把拼接凑满 64 位**：`{"SPD999",8'd0}` 只有 56 位，赋给 64 位
    // localparam 时会在**高端**补零 ⇒ 第一个字节成了 0x00、命令短一字节。
    // 台架里 A5 那一条红就是这么来的（而 DUT 故意不过滤 0x00，见下一行注释）。
    localparam [63:0] C_CLR     = {"CLR",   40'd0};
    // `\r` **不是** Verilog 的转义（1364 只认 \n \t \v \f \a \? \\ 和 \<八进制>），
    // xvlog 会把它当普通字母 ⇒ "CLR\r\n" 实际上是 'C''L''R''r'，多出来一个非空白的 0x72。
    // 这种笔误在板上会表现为"命令偶尔不生效"，所以这里用字节列表写死，并且台架一眼就红。
    localparam [63:0] C_CLR_CRLF= {8'h43,8'h4C,8'h52,8'h0D,8'h0A, 24'd0};   // "CLR" + CR + LF
    localparam [63:0] C_SNAP    = {"SNAP",  32'd0};
    localparam [63:0] C_SPACES  = {" SNAP ", 16'd0};
    localparam [63:0] C_SPD5    = {"SPD5",  32'd0};
    localparam [63:0] C_SPD12   = {"SPD12", 24'd0};
    localparam [63:0] C_SPD999  = {"SPD999", 16'd0};
    localparam [63:0] C_SPD0    = {"SPD0",  32'd0};
    localparam [63:0] C_SPD1X   = {"SPD1X", 24'd0};
    localparam [63:0] C_SPD     = {"SPD",   40'd0};
    localparam [63:0] C_SNA     = {"SNA",   40'd0};
    localparam [63:0] C_SPD7    = {"SPD7",  32'd0};

    reg clk = 1'b0, rst_n = 1'b0;
    always #4 clk = ~clk;

    reg         p_valid = 0, p_sof = 0, p_eof = 0, p_good = 1;
    reg  [7:0]  p_data  = 0;

    wire        cmd_clr, cmd_snap, cmd_seen;
    wire [7:0]  period_s;
    wire [15:0] cmds_ok, cmds_bad;

    ku5p_cmd #(.DEF_PERIOD(8'd1)) dut (
        .clk(clk), .rst_n(rst_n),
        .p_data(p_data), .p_valid(p_valid), .p_sof(p_sof), .p_eof(p_eof), .p_good(p_good),
        .cmd_clr(cmd_clr), .cmd_snap(cmd_snap), .period_s(period_s),
        .cmds_ok(cmds_ok), .cmds_bad(cmds_bad), .cmd_seen(cmd_seen)
    );

    integer errors = 0;

    task expect(input [639:0] name, input cond);
        begin
            if (cond !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL %0s (t=%0t)", name, $time);
            end else $display("PASS %0s", name);
        end
    endtask

    // 发一包命令。style=0：eof 单独一拍（本板链路的契约）；style=1：eof 与最后一个字节同拍（厂商风格）
    task send;
        input integer style;
        input [63:0]  bytes;
        input integer n;               // 有效字节数（含空白，DUT 自己会忽略）
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(negedge clk);
                p_data  <= bytes[8*(MAXB-1-i) +: 8];
                p_valid <= 1'b1;
                p_sof   <= (i == 0);
                p_eof   <= (style == 1) && (i == n-1);
            end
            @(negedge clk);
            p_valid <= 1'b0;
            p_sof   <= 1'b0;
            p_eof   <= (style == 0);            // style①：eof 单独一拍；**空载荷也必须发 eof**，
                                                // 否则 B3 那一条测的是"什么都没发生"而不是"空包不记账"
            @(negedge clk);
            p_eof   <= 1'b0;
            @(negedge clk);                          // 留一拍让寄存器输出稳定
        end
    endtask

    // 脉冲只活一拍 ⇒ 用粘滞位捕捉，再在每条激励前显式清（不清就会拿上一条的余温判这一条）
    reg saw_clr, saw_snap;
    always @(posedge clk) begin
        if (cmd_clr)  saw_clr  <= 1'b1;
        if (cmd_snap) saw_snap <= 1'b1;
    end
    task watch_clear;
        begin
            @(negedge clk);
            saw_clr = 1'b0; saw_snap = 1'b0;
        end
    endtask

    // 探针跟着实现走（它是观测，不是判据）：逐字节状态机版本看 st/acc 就够
    always @(posedge clk) if (p_eof)
        $display("MON t=%0t st=%0d st_nxt=%0d acc=%0d clr=%b snp=%b ok=%b bad=%b",
                 $time, dut.st, dut.st_nxt, dut.acc_nxt, dut.cmd_clr, dut.cmd_snap,
                 dut.cmds_ok, dut.cmds_bad);

    initial begin
        $dumpfile("tb_v80_ku5p_cmd.vcd");
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // ---- R 复位值 ----
        expect("R0 period defaults to 1 s",       period_s === 8'd1);
        expect("R1 no command counted yet",       cmds_ok === 16'd0 && cmds_bad === 16'd0);
        expect("R2 cmd_seen clear",               cmd_seen === 1'b0);
        expect("R3 no pulses out of reset",       cmd_clr === 1'b0 && cmd_snap === 1'b0);

        // ---- A1/A2 两条脉冲命令 ----
        watch_clear;  send(0, C_CLR, 3);
        expect("A1 CLR raised cmd_clr only",      saw_clr === 1'b1 && saw_snap === 1'b0);
        expect("A1b CLR counted as ok",           cmds_ok === 16'd1 && cmds_bad === 16'd0);
        expect("A1c cmd_seen latched",            cmd_seen === 1'b1);
        watch_clear;  send(0, C_SNAP, 4);
        expect("A2 SNAP raised cmd_snap only",    saw_snap === 1'b1 && saw_clr === 1'b0);
        expect("A2b SNAP counted as ok",          cmds_ok === 16'd2);

        // ---- A3~A8 SPD：位数、钳位、以及三种必须被拒的写法 ----
        send(0, C_SPD5, 4);
        expect("A3 SPD5 -> period 5",             period_s === 8'd5);
        expect("A3b counted ok",                  cmds_ok === 16'd3);
        send(0, C_SPD12, 5);
        expect("A4 SPD12 -> period 12",           period_s === 8'd12);
        expect("A4b two digits counted",          cmds_ok === 16'd4);
        send(0, C_SPD999, 6);
        expect("A5 SPD999 clamps to 255",         period_s === 8'hFF);
        expect("A5b clamp is still a good cmd",   cmds_ok === 16'd5);
        send(0, C_SPD0, 4);
        expect("A6 SPD0 rejected, period kept",   period_s === 8'hFF && cmds_bad === 16'd1);
        expect("A6b rejection did not count as ok", cmds_ok === 16'd5);
        send(0, C_SPD1X, 5);
        expect("A7 non-digit rejected",           cmds_bad === 16'd2);
        send(0, C_SPD, 3);
        expect("A8 bare SPD rejected",            cmds_bad === 16'd3);
        watch_clear;  send(0, C_SNA, 3);
        expect("A9 SNA is not SNAP and not CLR",  cmds_bad === 16'd4 && saw_clr === 1'b0
                                                && saw_snap === 1'b0);

        // ---- B 空白与空包 ----
        watch_clear;  send(0, C_CLR_CRLF, 5);
        expect("B1 trailing CR/LF ignored",       saw_clr === 1'b1);
        expect("B1b one good command",            cmds_ok === 16'd6);
        watch_clear;  send(0, C_SPACES, 6);
        expect("B2 leading/trailing space ignored", saw_snap === 1'b1 && saw_clr === 1'b0);
        expect("B2b counted once, not twice",     cmds_ok === 16'd7);
        watch_clear;  send(0, 64'd0, 0);
        expect("B3 empty payload: nothing fires", saw_clr === 1'b0 && saw_snap === 1'b0);
        expect("B3b empty payload charged as neither ok nor bad",
               cmds_ok === 16'd7 && cmds_bad === 16'd4);

        // ---- C 厂商风格的 eof（与最后一个字节同拍）----
        watch_clear;  send(1, C_CLR, 3);
        expect("C1 vendor-style eof still executes CLR", saw_clr === 1'b1);
        send(1, C_SPD7, 4);
        expect("C2 vendor-style SPD7 -> period 7", period_s === 8'd7);
        expect("C2b both vendor cmds counted",    cmds_ok === 16'd9);

        // ---- D 坏包：不执行也不记账 ----
        watch_clear;
        p_good = 0;  send(0, C_CLR, 3);  p_good = 1;
        @(negedge clk);
        expect("D1 bad packet did not execute",   saw_clr === 1'b0);
        expect("D1b bad packet charged to neither counter",
               cmds_ok === 16'd9 && cmds_bad === 16'd4);
        // 反面对照：同一串字节在包好时必须执行（否则 D1 只是"什么都没发生"的假绿）
        watch_clear;  send(0, C_CLR, 3);
        expect("D2 same bytes in a good packet DO execute", saw_clr === 1'b1);
        expect("D2b ok count moved",              cmds_ok === 16'd10);

        // ---- 总账：逐条累加 = 绝对值 ----
        // 好命令 10 条 = CLR, SNAP, SPD5, SPD12, SPD999, CLR\r\n, " SNAP ", CLR②, SPD7②, CLR(坏包后重发)
        // 坏命令 4 条  = SPD0, SPD1X, SPD, SNA
        expect("SUM ok=10 bad=4 (running total closes)",
               cmds_ok === 16'd10 && cmds_bad === 16'd4);

        if (errors == 0) $display("PASS tb_v80_ku5p_cmd");
        else             $display("FAIL tb_v80_ku5p_cmd errors=%0d", errors);
        $finish;
    end

    initial begin
        #200_000;                                 // 200 us 看门狗（本台架只需要几千拍）
        $display("FAIL tb_v80_ku5p_cmd timeout");
        $finish;
    end
endmodule
