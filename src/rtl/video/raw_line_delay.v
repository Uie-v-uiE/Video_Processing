`timescale 1ns/1ps
// raw_line_delay —— 把一路像素流整体延后 N 个显示行的行环形缓存（V8-4b 第 3 步，ISSUES #62 / #68）
//
// 为什么需要它（这一段就是"不需要第二个读口"的关键）：
//   4b 之后屏上只有一条读地址流：`pix = FB[ mapper(cx, cy + OFF_LINES) ]`。
//   那个提前量补的是"行缓存式 3×3 滤波必然滞后一整行"（#54 (B)：数据不能提前，只有地址能提前），
//   所以**链子出口**对应显示行 y，而**链子入口**同一拍对应的是 y + OFF_LINES。
//   要把这两个抽头逐像素混在一起，就得把入口那一路补延后 OFF_LINES 行 ⇒ 就是这块。
//
// 为什么**不是**几级 `line_cache` 串起来（第一版就是那么写的，被 `tb_v100_raw_delay` 当场打掉）：
//   串 N 个行缓存 = 延后 N 行**又**多花 N 拍 ⇒ 列方向偏 N 格。
//   实测凭据 `build/tb_v100_console.txt`：row=4 / k=4 那一格读出 (0,0) 而不是 (0,4)，
//   也就是传递函数 = (行 −4, 列 −4)。缝两边差 4 列 = 一条 4 像素宽的竖带；
//   而这种错在**模块级**台架里看不见（每台架只喂自己那一级）—— 又一次"只有顶层才看得见"。
//   ⇒ 正确结构是**一块 1W1R 的行环形 RAM**：写槽 = y 的低几位，读槽 = (y − LINES) 的同一几位，
//     同一拍里写本行、读 LINES 行之前的那一列 ⇒ 延迟恰好 = LINES 行 + 1 拍，**列不偏**。
//
// 环深取 2^RLOG ≥ LINES+1 ⇒ `mod` 就是**切位**，不留运行时除法/取模（#58 那条硬件规矩）。
//   LINES=4 ⇒ RLOG=3、环 8 行、深度 8×512×16 ⇒ 约 4 块 RAMB36（级联方案要 8 块，省一半）。
//
// ⚠ N 只有一个合法出处：`u_pipe.OFF_LINES`（顶层像取 `LATENCY` 那样在 elaboration 期取它）。
//   刻意不给"猜出来的默认值"：链子哪天改成寄存读出、OFF_LINES 变了，这条链自动跟着变。
// ⚠ 头 LINES 行读到的是 RAM 旧内容 —— 屏上落在**帧首那几条线**，与 `board/README.md` 第 12 行
//   讲的"最上面 4 行本来就没有上一行可算"同一族，不是新缺陷（台架 T2 明说不判那几行）。
module raw_line_delay #(
    parameter integer LINES = 4,     // 延后几行（唯一合法来源：u_pipe.OFF_LINES）
    parameter integer W     = 512    // 一行多少个**有效**像素（4b 之后是源列数，不是面板列数）
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de,             // 本拍 d_in 是有效像素
    input  wire [11:0] x,              // 行内列号（0..W-1）
    input  wire [11:0] y,              // 显示行号（只用低 RLOG 位选行槽）
    input  wire [15:0] d_in,
    output wire [15:0] d_out,
    output wire        de_out
);
    // clog2 在 elaboration 期算完，不留硬件
    function integer clog2;
        input integer v;
        integer i;
        begin
            clog2 = 0;
            for (i = 0; (1 << i) < v; i = i + 1) clog2 = i + 1;
        end
    endfunction
    localparam integer RLOG  = (LINES > 0) ? clog2(LINES + 1) : 1;   // 行槽位数
    localparam integer CWID  = clog2(W);                             // 列地址位数（W=512 ⇒ 9）
    localparam integer DEPTH = (1 << RLOG) * W;                      // 环深 × 每行列数

    generate
    if (LINES == 0) begin : g_pass
        // 直通：一个 RAM 都不推出来（链子哪天不滞后，顶层不必删例化）
        assign d_out  = d_in;
        assign de_out = de;
    end else begin : g_ring
        reg [15:0] mem [0:DEPTH-1];
        integer m;
        initial for (m = 0; m < DEPTH; m = m + 1) mem[m] = 16'h0000;

        wire [RLOG-1:0] wslot = y[RLOG-1:0];
        wire [RLOG-1:0] rslot = y[RLOG-1:0] - LINES[RLOG-1:0];        // 就是 (y-LINES) mod 2^RLOG
        wire [RLOG+CWID-1:0] widx = {wslot, x[CWID-1:0]};
        wire [RLOG+CWID-1:0] ridx = {rslot, x[CWID-1:0]};

        reg [15:0] q;
        reg        v;
        always @(posedge clk) begin
            if (de) mem[widx] <= d_in;          // 写：本行本列
            q <= mem[ridx];                     // 读：LINES 行之前的同一列（同拍 ⇒ 只多 1 拍、列不偏）
        end
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) v <= 1'b0;
            else        v <= de;                // de 链与数据链**等长**（都只 1 拍）
        end
        assign d_out  = q;
        assign de_out = v;
    end
    endgenerate
endmodule
