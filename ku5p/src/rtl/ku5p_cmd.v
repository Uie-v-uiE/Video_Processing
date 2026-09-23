`timescale 1ns/1ps
// ku5p_cmd —— PC → 这块板的**命令通道**（自研；与遥测是一对：一个上报、一个下命令）。
//
// 为什么值得做：`ku5p_telem` 让 PC 能"听见"这块板，但它只能听。有了可用的命令路，
// 这块板才谈得上"可编程的前端节点"（ku5p/README.md §9 第 2 条），也是比赛谱系里
// "KU5P 做前端、Zynq 做显示与总控"那条异构链的第一步。
//
// 线上格式：UDP **目的端口 5002**（视频流是 5001，两路互不干扰，靠 `udp_rx_parser`
// 的目的端口过滤分开），载荷是**几条 ASCII 文本命令**：
//   CLR      把统计基线推到"现在" ⇒ 遥测里的计数变成"自本次 CLR 以来"
//   SNAP     立刻回一包遥测（同时就是这条命令的 ACK）
//   SPD<n>   改上报周期，n = 1..255 秒（十进制 1~3 位；>255 钳到 255，0 视为坏命令）
// 首尾空白（空格/Tab/CR/LF）被忽略 —— `echo`、PowerShell、串口转发各自的习惯不一样。
//
// 三个不是理所当然的决定：
// 1) **命令用文本而不是二进制**。板这边解析几条 ASCII 只要几十 LUT，PC 侧
//    `node src/host/ku5p_cmd.mjs` 就是一句 `dgram.send("CLR")`；更重要的是评审不查表
//    也能看懂 `SPD5` 是什么意思。
// 2) **CLR 不动 `frame_reasm` 的计数器，只推基线**。那些计数器是别人端口的输出，
//    要清零就得改那个模块（连带重跑它的台架和 Z7 侧同源的那三条板级结论）。
//    基线相减放在遥测侧，代价是包里字段的含义变成"自上次 CLR 以来" ——
//    这条语义同时写在 `ku5p_telem` 文件头与 PC 解析器里，两处必须一起改。
//    与主线的 `gapclr`（也只清"帧间隔统计"、不清终身计数）是同一套路子。
// 3) **判定只在 `p_eof` 那一拍做**：坏包（FCS 不对）不执行、也不记账；
//    有内容但不认识的记 `cmds_bad` —— 让"命令没生效"这件事本身可观测，而不是靠人盯屏幕猜。
module ku5p_cmd #(
    parameter [7:0] DEF_PERIOD = 8'd1,     // 上电默认：每秒一包（与遥测的 TICK_CYC 口径一致）
    parameter [3:0] MAX_LEN    = 4'd8      // 只认前 MAX_LEN 个有效字节（n 只有 4 位 ⇒ 上限 15）
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 来自一个 `udp_rx_parser #(.UDP_PORT(5002))` 的载荷流 ----
    input  wire [7:0]  p_data,
    input  wire        p_valid,
    input  wire        p_sof,
    input  wire        p_eof,
    input  wire        p_good,

    // ---- 命令效果 ----
    output reg         cmd_clr,        // 1 拍脉冲：遥测侧把基线推到现在
    output reg         cmd_snap,       // 1 拍脉冲：遥测侧立刻要一包
    output reg  [7:0]  period_s,       // 电平：上报周期（秒），恒 ≥1
    output reg  [15:0] cmds_ok,        // 执行成功的命令条数（饱和保持）
    output reg  [15:0] cmds_bad,       // 收到但**不认识**的条数（饱和保持）
    output reg         cmd_seen        // 电平：至少执行过一条好命令（上电为 0）
);
    // 有效字节**左移、从最低端塞进**一个 64 位寄存器：`{sh[55:0], 字节}`。
    // 这样"已经收到的 n 个字节"永远右对齐在 `sh[8n-1:0]`，且**第一个字节在这个字段的最高位**
    // —— 与 Verilog 字符串常量的摆放方向一致，所以比较可以直接写 `sh[23:0] == "CLR"`。
    // （反过来从高端灌、又想按固定位置取字节，会让每个字节的下标跟着 n 漂移：
    //  第一版就是这么写的，台架一次红十几条 —— 红得整齐反而是好消息，说明判据在一条路上。）
    reg [63:0] sh;
    reg [3:0]  n;                 // 已有几个有效字节（0..MAX_LEN）

    function is_ws; input [7:0] c;
        is_ws = (c == 8'h20) || (c == 8'h09) || (c == 8'h0D) || (c == 8'h0A);
    endfunction
    function is_digit; input [7:0] c;
        is_digit = (c >= 8'h30) && (c <= 8'h39);
    endfunction

    // 本拍的字节算不算"命令内容"（`p_sof` 与第一个载荷字节**同拍**，所以 sof 拍也要收）。
    // 只过滤空白（空格/Tab/CR/LF），**不过滤 0x00**：真命令里不会出现 NUL，而把它当内容
    // 会让"PC 侧拼错字符串/短一字节"这类错误在板级表现为 cmds_bad 增长而不是静默错位 ——
    // 台架里就靠这条把一处 56 位拼接（应当 64 位）的笔误抓了出来。
    wire take = p_valid && !is_ws(p_data);

    // 两种 p_eof 时序都必须认（与 `udp_rx_parser` 的契约一致）：
    //   ① 本板实际链路：最后一个字节**上一拍**已发出，p_eof 单独一拍（这一拍 take=0）；
    //   ② 厂商风格：p_eof 与最后一个字节同拍（take=1）⇒ 判定必须把它算进去，
    //      否则 "CLR" 只被看到 2 个字节。只认 ① 的写法在 ② 的激励下立刻红。
    wire [63:0] sh_e = take ? {sh[55:0], p_data} : sh;
    wire [3:0]  n_e  = p_sof ? (take ? 4'd1 : 4'd0)
                             : (take && (n < MAX_LEN)) ? (n + 4'd1) : n;

    // 命令前缀 = 这 n 个字节里最高的 3 个；数字 = 最低的 n-3 个（w0 恒是最后一个字节）。
    // 注意 `[base -: w]` 里的 base 是**最高位的下标**（含），所以是 `8*n-1` 而不是 `8*n`：
    // 写成 `8*n` 会把整段右移一位，xsim 实测 head=0x29A822 而不是 "SPD"=0x535044 ——
    // 这类"差一位"的错误台架一眼就红，比上板好查得多。
    wire [23:0] head = (n_e >= 4'd3) ? sh_e[(8*n_e - 1) -: 24] : 24'd0;
    wire [7:0]  w0 = sh_e[7:0], w1 = sh_e[15:8], w2 = sh_e[23:16];

    // ---- 组合判定 ----
    wire c_clr  = (n_e == 4'd3) && (sh_e[23:0] == "CLR");
    wire c_snap = (n_e == 4'd4) && (sh_e[31:0] == "SNAP");
    // "SPD" 与 "SNAP" 同前缀 S，靠第二个字母分开（P / N），所以不冲突。
    wire c_spd  = (n_e >= 4'd4) && (n_e <= 4'd6) && (head == "SPD") &&
                  is_digit(w0) && (n_e < 4'd5 || is_digit(w1)) &&
                  (n_e < 4'd6 || is_digit(w2));
    // 十进制折叠。这里**不能**写 `v2 * 16'd100`：操作数一宽，综合就把乘法器塞进 DSP48，
    // 而这条组合锥是从收包寄存器一路走到 `cmds_ok` 的 CE 的 —— r31 第一次构建实测
    // 最差路径 20 级、含 DSP_ALU/DSP_MULTIPLIER，WNS 从 +1.916 掉到 +0.647（ ku5p_setup.rpt 里
    // Source=u_rx_cmd/p_data_reg[5]/C、Destination=u_cmd/cmds_ok_reg[5]/CE 就是它）。
    // 改成移位相加：10d = 8d+2d，100d = 64d+32d+4d ⇒ 只有小位宽加法，没有 DSP。
    wire [3:0] q0 = w0[3:0], q1 = w1[3:0], q2 = w2[3:0];        // is_digit 已保证 ≤9
    wire [6:0] m10  = {q1, 3'd0} + {2'b0, q1, 1'b0};            // 8·q1 + 2·q1  ≤ 90
    wire [9:0] m100 = {q2, 6'd0} + {3'b0, q2, 3'd0} + {5'b0, q2, 2'd0};   // 64+32+4 ≤ 900
    wire [9:0] spd_val = (n_e == 4'd4) ? {6'd0, q0}
                         : (n_e == 4'd5) ? ({3'd0, m10} + {6'd0, q0})
                                        : ({m100} + {3'd0, m10} + {6'd0, q0});
    wire        spd_ok  = c_spd && (spd_val != 10'd0);     // SPD0 算坏命令，不是"1 秒"
    wire        any_ok  = p_good && (c_clr | c_snap | spd_ok);
    // 有内容、又不匹配 ⇒ 才记一条坏命令。空包不记账，否则 PC 上随手一个探测包
    // 就会把 cmds_bad 涨起来，那个数字就不再是"有人下错了命令"的意思。
    wire        bad_cmd = p_good && (n_e != 4'd0) && !any_ok;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sh <= 64'd0; n <= 4'd0;
            cmd_clr <= 1'b0; cmd_snap <= 1'b0; period_s <= DEF_PERIOD;
            cmds_ok <= 16'd0; cmds_bad <= 16'd0; cmd_seen <= 1'b0;
        end else begin
            cmd_clr <= 1'b0; cmd_snap <= 1'b0;         // 脉冲只活一拍

            if (take) sh <= {sh[55:0], p_data};
            // sof 拍重新计长（同拍的字节就是第 1 个），否则累加并钳在 MAX_LEN
            if (p_sof) n <= take ? 4'd1 : 4'd0;
            else if (take && (n < MAX_LEN)) n <= n + 4'd1;

            if (p_eof) begin                           // 包尾：执行 / 记账，然后把这一包丢掉
                if (any_ok) begin
                    if (cmds_ok != 16'hFFFF) cmds_ok <= cmds_ok + 16'd1;
                    cmd_seen <= 1'b1;
                    if (c_clr)  cmd_clr  <= 1'b1;
                    if (c_snap) cmd_snap <= 1'b1;
                    if (spd_ok) period_s <= (spd_val > 10'd255) ? 8'hFF : spd_val[7:0];
                end else if (bad_cmd) begin
                    if (cmds_bad != 16'hFFFF) cmds_bad <= cmds_bad + 16'd1;
                end
                n <= 4'd0;
            end
        end
    end
endmodule
