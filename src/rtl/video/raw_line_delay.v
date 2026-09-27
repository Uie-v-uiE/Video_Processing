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
//   ⚠ 但"列不偏"只在**一行之内**成立：那多出来的 1 拍在行首会越过消隐，读到的是空歇期地址
//     （`x` 的低几位在消隐里根本不是列号）。下面对读地址做的消隐钳位补的就是这一格（#102）。
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
    parameter integer W     = 512,   // 一行多少个**有效**像素（4b 之后是源列数，不是面板列数）
    // 一路多少位。**#92 的教训写在这里而不是藏在调用处**：与像素同源的那份"越界"标签必须
    // 和像素**过同一条环**。顶层以前让 `pix_raw` 过环（4 行 + 1 拍）、让 `oob` 绕开环只走
    // 等长的 skid ⇒ 两者差 (4 行, 1 列)：画面右沿的最后一列被"别的格子"的越界位按黑，
    // 上下边界的越界位则来自别的行（屏上表现为"上边缘有东西闪"）。
    // 现在把标签打包进来一起走，代价是 RAM 宽度 +1 位：16→17 位仍在 RAMB36 的 18 位宽度模式里
    // ⇒ **一块 BRAM 都不多要**（这条要在构建后的 utilization.rpt 上核对，不许停在注释）。
    parameter integer DW    = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de,             // 本拍 d_in 是有效像素
    input  wire [11:0] x,              // 行内列号（0..W-1）
    input  wire [11:0] y,              // 显示行号（只用低 RLOG 位选行槽）
    input  wire [DW-1:0] d_in,
    output wire [DW-1:0] d_out,
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
        reg [DW-1:0] mem [0:DEPTH-1];
        integer m;
        initial for (m = 0; m < DEPTH; m = m + 1) mem[m] = {DW{1'b0}};

        wire [RLOG-1:0] wslot = y[RLOG-1:0];
        wire [RLOG-1:0] rslot = y[RLOG-1:0] - LINES[RLOG-1:0];        // 就是 (y-LINES) mod 2^RLOG
        wire [RLOG+CWID-1:0] widx = {wslot, x[CWID-1:0]};
        // ⚠ **行首那一格以前读的是消隐期的地址**（#102 的根因，r80 的 P100 探针量出来的，不是推的）：
        //   一行 1344 拍而有效列只有 1024 ⇒ 尾部那 320 拍里 `x[CWID-1:0]` 从 0 数到 319，
        //   RAM 读出的又是"上一拍发出去的那个地址"，于是**下一行第一个有效列**摆出来的
        //   恰好是消隐期最后一个地址读到的格子。台架读数：源列 **160**（= 显示列 320 那一格的内容），
        //   而定义要的是源列 0 —— 用户念的"从视频里切出来贴在屏幕左边缘的一条线"就是它，
        //   而且一帧 600 行、行行都有一格（原图抽头上是错列，处理抽头上是错行，见 #98/#102）。
        // 为什么不能"把读出再打一拍"或"把消隐期的读地址一律钳到 0"：
        //   前者把**每一列**都推后一格 = #92 第一笔那族整列错位（C1c/C2b 立刻红）；
        //   后者在**帧头**那一行仍然错一行 —— `V_TOTAL=625` 不是环深 8 的整数倍，
        //   竖消隐那 25 行把槽位相位挪走了，而"环深 ≥ LINES+1 且 2·IMG_H mod 环深 == 0"这条
        //   只在**有效行**之间成立。
        // 采用的做法 = **掉进消隐的那一拍做一次预读**，锁起来留给下一行的行首：
        //   · `bl_head = !de && v` 就是"de 刚掉下去"的那一拍（每行只有一次，竖消隐里没有）；
        //     那一拍的 `y` 还是**刚结束的那一行**，所以下一行的槽就是 `rslot+1`（`y` 在 h_cnt
        //     回绕时才加一，这是 `video_timing.v:37-45` 写死的次序）；
        //   · 这一拍发 `{rslot+1, 0}`，晚一拍回到 `q` ⇒ 再锁一拍进 `head_q`；
        //     其余消隐拍照常读（它们的值落在 `de_out=0` 的位置上，谁都看不见），
        //     所以**行末最后一列原本那次读一点没动** —— 模块台架的 T1/T3 语义因此保持不变；
        //   · 输出只在 `de && x==0`（真正的行首那一拍）选 `head_q` ⇒ 中间每一列的读数
        //     一个比特都没变，只有行首那一格从"别处的像素"变回"本行第一列"。
        //   帧头也顺带对了：`y=599` 掉进消隐那一拍算出的槽 = (599+1−LINES) mod 8 = 4 = 第 0 行要的槽，
        //   靠的正是 `2·IMG_H mod 环深 == 0`（600 mod 8 = 0），与上面那条注释同一个条件。
        reg [DW-1:0] q;
        reg [DW-1:0] head_q;               // 预读来的"下一行第 0 列"（见上面那一大段）
        reg        v;                      // de 延一拍（= de_out，也用来认"de 刚掉下去"那一拍）
        reg        look;                   // 上一拍刚发过预读 ⇒ 这一拍的 q 就是它
        wire bl_head = (!de && v);                       // de 刚掉下去那一拍
        wire [RLOG-1:0]  rslot_rd = bl_head ? (rslot + 1'b1) : rslot;
        wire [CWID-1:0]   x_rd     = bl_head ? {CWID{1'b0}} : x[CWID-1:0];
        wire [RLOG+CWID-1:0] ridx  = {rslot_rd, x_rd};
        always @(posedge clk) begin
            if (de) mem[widx] <= d_in;          // 写：本行本列
            q <= mem[ridx];                     // 读：LINES 行之前的同一列（同拍 ⇒ 只多 1 拍、列不偏）
        end
        // ⚠ `look/head_q` 只许在这**一个** always 里写：上面那个块没有异步复位（RAM 与其读出
        //   本来就不复位），把同一根寄存器分给两个进程综合会直接报多驱动（#68 那一族的老账）。
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                v <= 1'b0; look <= 1'b0; head_q <= {DW{1'b0}};
            end else begin
                v    <= de;                     // de 链与数据链**等长**（都只 1 拍）
                look <= bl_head;                // 预读发出去的那一拍，晚一拍才回到 q
                if (look) head_q <= q;
            end
        end
        assign d_out  = (de && x[CWID-1:0] == {CWID{1'b0}}) ? head_q : q;
        assign de_out = v;
    end
    endgenerate
endmodule
