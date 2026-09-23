`timescale 1ns/1ps
// ku5p_cmd —— PC → 这块板的**命令通道**（自研；与遥测是一对：一个上报、一个下命令）。
//
// 为什么值得做：`ku5p_telem` 让 PC 能"听见"这块板，但它只能听。有了可用的命令路，
// 这块板才谈得上"可编程的前端节点"（ku5p/README.md §9 第 2 条），也是比赛谱系里
// "KU5P 做前端节点、Zynq 做显示与总控"那条异构链的第一步。
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
//
// ## 为什么是"逐字节状态机"而不是"收完再比较"（这一条是被报告逼出来的）
// 第一版把整包收进一个 64 位移位寄存器，然后在 `p_eof` 那一拍做组合判定：
// 24 bit 前缀比较 + 三个 `is_digit` + 十进制折叠 + 三向 mux 全挤在 125 MHz 的一拍里。
// 实测代价（`ku5p/build/ku5p_setup_r31_dsp.rpt` 与 `ku5p_setup.rpt`）：
//   · 写成 `v*16'd100` 时综合把它塞进 DSP48 ⇒ WNS 从 +1.916 掉到 **+0.647**；
//   · 换成移位相加（DSP 归零、级数 20→14）之后 WNS 反而掉到 **+0.192**。
// ⇒ 假设被自己的数据推翻：瓶颈不是乘法器，是**那条"包尾宽比较"组合锥**
//   （最差路径 Source = `u_rx_cmd/p_data_reg/C`、Destination = `u_cmd/cmd_clr_reg/D`）。
// 现在每拍只看**刚进来的那一个字节**：状态转移 = 8 bit 分类 + 一层 mux；数字累加是
// 寄存器到寄存器的独立小锥；包尾只比状态码（几个 1 bit 比较）。
//
// 注意 `st_nxt` 是**组合**的：厂商风格的 `p_eof` 与最后一个字节同拍，那一拍寄存器 `st`
// 还没吸收这个字节，判定必须用 `st_nxt`（台架 C 组专门喂这种时序，用 `st` 会立刻红）。
module ku5p_cmd #(
    parameter [7:0] DEF_PERIOD = 8'd1      // 上电默认：每秒一包（与遥测的 TICK_CYC 口径一致）
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
    // 一条命令 = 前缀树上的一条路，走到叶子才算好。
    localparam [3:0] S_IDLE = 4'd0,    // 还没收到有效字节
                     S_C    = 4'd1,    // 'C'
                     S_CL   = 4'd2,    // "CL"
                     S_CLR  = 4'd3,    // "CLR"            ← 叶子
                     S_S    = 4'd4,    // 'S'（SNAP 与 SPD 共用首字母，靠第二个字母分家）
                     S_SN   = 4'd5,    // "SN"
                     S_SNA  = 4'd6,    // "SNA"
                     S_SNAP = 4'd7,    // "SNAP"           ← 叶子
                     S_SPD  = 4'd8,    // "SPD"，还没来数字
                     S_D1   = 4'd9,    // "SPD<d>"         ← 叶子
                     S_D2   = 4'd10,   // "SPD<dd>"        ← 叶子
                     S_D3   = 4'd11,   // "SPD<ddd>"       ← 叶子（再多一个字节即作废）
                     S_SP   = 4'd12,   // "SP"
                     S_BAD  = 4'd15;   // 不匹配：这一包作废

    reg [3:0] st;
    reg [9:0] acc;                 // 十进制累加（3 位 ≤ 999）
    reg [3:0] st_nxt;
    reg [9:0] acc_nxt;

    // 单字节分类：全是 8 bit 比较，一拍一层 LUT。
    wire is_ws  = (p_data == 8'h20) || (p_data == 8'h09) ||
                  (p_data == 8'h0D) || (p_data == 8'h0A);
    wire is_dig = (p_data >= 8'h30) && (p_data <= 8'h39);
    wire [3:0] dv = p_data[3:0];                    // is_dig 时即 0..9
    // acc*10 + dv = (acc<<3) + (acc<<1) + dv。移位相加而不是乘法：这条小锥里不许出现 DSP48
    // （上一版就是因为 `*100` 被塞进 DSP，见文件头那段实测）。
    wire [9:0] acc10 = {acc[6:0], 3'd0} + {acc[8:0], 1'd0} + {6'd0, dv};

    // sof 与第一个载荷字节**同拍**，所以 sof 拍也要收
    wire take = p_valid && !is_ws;

    // ---------------- 组合次态 ----------------
    always @(*) begin
        st_nxt  = st;
        acc_nxt = acc;
        if (take) begin
            if (p_sof) begin
                acc_nxt = 10'd0;
                if      (p_data == "C") st_nxt = S_C;
                else if (p_data == "S") st_nxt = S_S;
                else                    st_nxt = S_BAD;
            end else case (st)
                // 根状态也要能认第一个字节：`p_sof` 与**首字节**同拍，但首字节可能是被忽略的
                // 空白（" SNAP "），于是真正的第一个有效字节落在 sof 之后那一拍。
                // 只认 sof 那一拍做根判定，带前导空白的命令会被当成从中间开始 —— B2 就是这么红的。
                S_IDLE: begin
                    acc_nxt = 10'd0;
                    if      (p_data == "C") st_nxt = S_C;
                    else if (p_data == "S") st_nxt = S_S;
                    else                    st_nxt = S_BAD;
                end
                S_C:    st_nxt = (p_data == "L") ? S_CL   : S_BAD;
                S_CL:   st_nxt = (p_data == "R") ? S_CLR  : S_BAD;
                S_S:    st_nxt = (p_data == "N") ? S_SN   :
                                (p_data == "P") ? S_SP   : S_BAD;
                S_SP:   st_nxt = (p_data == "D") ? S_SPD  : S_BAD;
                S_SN:   st_nxt = (p_data == "A") ? S_SNA  : S_BAD;
                S_SNA:  st_nxt = (p_data == "P") ? S_SNAP : S_BAD;
                S_SPD:  if (is_dig) begin st_nxt = S_D1; acc_nxt = {6'd0, dv}; end
                        else        st_nxt = S_BAD;
                S_D1:   if (is_dig) begin st_nxt = S_D2; acc_nxt = acc10; end
                        else        st_nxt = S_BAD;
                S_D2:   if (is_dig) begin st_nxt = S_D3; acc_nxt = acc10; end
                        else        st_nxt = S_BAD;
                default st_nxt = S_BAD;             // 叶子/坏态之后再来字节 = 坏命令
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; acc <= 10'd0;
            cmd_clr <= 1'b0; cmd_snap <= 1'b0; period_s <= DEF_PERIOD;
            cmds_ok <= 16'd0; cmds_bad <= 16'd0; cmd_seen <= 1'b0;
        end else begin
            cmd_clr <= 1'b0; cmd_snap <= 1'b0;      // 脉冲只活一拍
            st  <= st_nxt;
            acc <= acc_nxt;

            if (p_eof) begin                         // 包尾：执行 / 记账，然后把这一包丢掉
                st <= S_IDLE;
                if (p_good && (st_nxt == S_CLR || st_nxt == S_SNAP ||
                               ((st_nxt == S_D1 || st_nxt == S_D2 || st_nxt == S_D3) &&
                                acc_nxt != 10'd0))) begin
                    if (cmds_ok != 16'hFFFF) cmds_ok <= cmds_ok + 16'd1;
                    cmd_seen <= 1'b1;
                    if (st_nxt == S_CLR)  cmd_clr  <= 1'b1;
                    if (st_nxt == S_SNAP) cmd_snap <= 1'b1;
                    if (st_nxt == S_D1 || st_nxt == S_D2 || st_nxt == S_D3)
                        period_s <= (acc_nxt > 10'd255) ? 8'hFF : acc_nxt[7:0];
                end else if (p_good && (st_nxt != S_IDLE)) begin
                    // 空包（S_IDLE）既不记好也不记坏：否则 PC 上随手一个探测包就会污染 cmds_bad
                    if (cmds_bad != 16'hFFFF) cmds_bad <= cmds_bad + 16'd1;
                end
            end
        end
    end
endmodule
