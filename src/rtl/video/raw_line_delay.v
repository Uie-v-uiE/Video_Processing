`timescale 1ns/1ps
// raw_line_delay —— 把一路像素流整体延后 N 个显示行的行环形缓存（V8-4b，ISSUES #62 / #68）。单像素时钟，读写同拍。
// 用途：4b 之后屏上只有一条读地址流 `pix = FB[ mapper(cx, cy + OFF_LINES) ]`，链子**出口**对应显示行 y、**入口**
//   同一拍对应 y + OFF_LINES（#54 (B)：数据不能提前，只有地址能提前）⇒ 两个抽头要逐像素混就得把入口补延后 N 行。
// 结构是**一块 1W1R 的行环形 RAM**：写槽 = y 的低几位、读槽 = (y − LINES) 的同一几位，同拍写本行、读 LINES 行前
//   的同一列 ⇒ 延迟恰好 = LINES 行 + 1 拍、**列不偏**。**不是**几级 `line_cache` 串起来（第一版就是，被
//   `tb_raw_delay` 当场打掉）：串 N 个 = 延后 N 行**又**多花 N 拍 ⇒ 列偏 N 格，而这种错在模块级台架看不见。
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
    // 环深取 2^RLOG ≥ LINES+1 ⇒ `mod` 就是**切位**，不留运行时除法/取模（#58 那条硬件规矩）。
    // LINES=4 ⇒ RLOG=3、环 8 行、深度 8×512×16 ≈ 4 块 RAMB36（级联方案要 8 块，省一半）。
    // ⚠ N 只有一个合法出处：`u_pipe.OFF_LINES`（顶层像取 `LATENCY` 那样在 elaboration 期取它）。刻意不给
    //   "猜出来的默认值"：链子哪天改成寄存读出、OFF_LINES 变了，这条链自动跟着变。
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
        // ⚠ 但"列不偏"只在**一行之内**成立：多出的那 1 拍在行首会越过消隐，读到空歇期的地址 —— #102 的
        //   根因（r80 的 P100 探针量出来的，不是推的）。一行 1344 拍而有效列只有 1024 ⇒ 尾部那 320 拍里
        //   `x[CWID-1:0]` 从 0 数到 319，而 RAM 读出的是**上一拍发出去的那个地址** ⇒ 下一行第一个有效列
        //   摆出的恰好是消隐期最后那个格子（台架读数源列 **160** = 显示列 320 那一格，定义要源列 0）。
        //   一帧 600 行、行行都有一格 —— 用户念的"从视频里切出来贴在屏幕左边缘的一条线"就是它。
        // 头 LINES 行读到的是 RAM 旧内容，落在**帧首那几条线**，与"最上面 4 行没有上一行可算"同一族，不是新缺陷。
        reg [DW-1:0] q;
        reg [DW-1:0] head_q;               // 预读来的"下一行第 0 列"
        reg        v;                      // de 延一拍（= de_out，也用来认"de 刚掉下去"那一拍）
        reg        look;                   // 上一拍刚发过预读 ⇒ 这一拍的 q 就是它
        // 做法 = **掉进消隐的那一拍做一次预读**，锁起来留给下一行的行首：`bl_head = !de && v` 就是
        // "de 刚掉下去"那一拍（每行只有一次，竖消隐里没有）；那一拍的 `y` 还是**刚结束的那一行** ⇒
        // 下一行的槽是 `rslot+1`（`y` 在 h_cnt 回绕时才加一，`video_timing.v:37-45` 写死的次序）。
        // 输出只在 `de && x==0` 选 `head_q` ⇒ 中间每一列一个比特都没变，行末最后一列原本那次读也没动
        //（模块台架 T1/T3 语义不变）。帧头顺带也对：(599+1−LINES) mod 8 = 4 = 第 0 行要的槽。
        wire bl_head = (!de && v);                       // de 刚掉下去那一拍
        wire [RLOG-1:0]  rslot_rd = bl_head ? (rslot + 1'b1) : rslot;
        wire [CWID-1:0]   x_rd     = bl_head ? {CWID{1'b0}} : x[CWID-1:0];
        wire [RLOG+CWID-1:0] ridx  = {rslot_rd, x_rd};
        // ⚠ 两种"看起来更简单"的办法都是错的，别再试：把读出**再打一拍** ⇒ 每一列都推后一格，
        //   正是 #92 那族整列错位（C1c/C2b 立刻红）；消隐期读地址**一律钳到 0** ⇒ 帧头那一行仍错一行，
        //   因为 `V_TOTAL=625` 不是环深 8 的整数倍，竖消隐那 25 行把槽位相位挪走了。
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
