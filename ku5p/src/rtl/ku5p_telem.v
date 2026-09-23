`timescale 1ns/1ps
// ku5p_telem —— 把本板的收流统计打包成一包 UDP 遥测发给 PC（自研）。
//
// 为什么值得做：这块板没有 PS、没有串口、没有显示器，只有 4 个 LED。LED 能表达
// "见过帧 / 见过错"，但表达不了"15 fps 稳不稳、丢包几个"。做完这一步，
// KU5P 从一个"只能看灯的从板"变成 PC 能直接对接的异构节点（`node src/host/ku5p_stats.mjs`），
// 而且**顺带第一次真正用起了发送侧**（RGMII TX + udp_tx + CRC）——
// 之前 TX 只被 ARP/ICMP 应答用过，收流方向的统计从来没出过板。
//
// 三个不是理所当然的决定（都是台架逼出来的，判据在 sim/tb_ku5p_telem.v）：
// 1) **发的那一刻做快照**。统计寄存器是活的（每来一包都在涨），边发边读会让一包里
//    前后字节来自不同时刻。判据：发送途中继续改计数器，包内容必须等于发起前的快照。
// 2) **只在 ARP 学到对端之后才发**。厂商 udp_tx 在 des_mac==0 时会拿上一次的 eth_head
//    继续发 ⇒ 往一个随机 MAC 发包，所以 `peer_known` 是硬门，不是省电。
// 3) **字节要寄存一拍再交出去**。厂商 udp_tx 的 `tx_req` 在 UDP 头最后一个字节就提前拉高
//    （它自己的注释："提前读请求数据，等待数据有效时发送"），组合直出的第 0 字节会被吃掉；
//    厂商原本不踩这个坑，是因为它的数据源是 `eth_ctrl` 后面那个同步 FIFO —— 读出一拍延迟
//    正好抵掉这个提前量。这里等价地打一拍，把自己变成"和 FIFO 同一个契约"。
//
// 线上格式（大端，**42** 字节 UDP 载荷；PC 侧解析器在 src/host/ku5p_stats.mjs，两处必须一起改）：
//   [0:3] 'K''U''5''P'   [4] 版本   [5] 标志位
//   [6:7] 图像宽  [8:9] 图像高
//   [10:13] 完整帧数  [14:17] 包数  [18:21] 载荷字节数  [22:25] 校验/长度错包数
//   [26:29] 越界偏移字节数  [30:31] 本帧缺行数  [32:35] 上电秒数(低 32 位)
//   v0x02 新增：[36:37] 执行成功的命令数  [38:39] 被拒的命令数  [40] 当前上报周期(秒)
//              [41] 标志位 2：bit0=执行过命令，bit1=**基线已推过**（即下面四个计数是"自上次 CLR 以来"）
// 计数器都是 32 位只增（15 fps 下 stat_bytes 约 930 s 回绕一次），不做饱和。
// 载荷 42 ≥ 厂商 MIN_DATA_NUM(18) ⇒ 不会走它的"末尾重复补位"路径。
//
// **`CLR` 改的是这里的基线，不是计数器**（理由见 ku5p_cmd.v 文件头第 2 条）：
// 上报值 = 观测值 − 基线，基线在 `cmd_clr` 那一拍锁存当前观测值。
// 所以"上电到现在"与"自上次 CLR 以来"是同一个字段，靠 flags2.bit1 区分；
// `uptime_s` 不参与相减（它是"上电秒数"，语义必须唯一）。
//
// **字段诚实性（口径，别把 `bad` 读成"没有错包"）**：这块板的收侧在 R26 已经换成
// 自研那一对（`gmii_rx_mac` 逐字节算 FCS-32 + `udp_rx_parser` 目的端口过滤），
// `frame_reasm.p_good` 接的是**真值** ⇒ 这里的 `bad` 从"构造性为 0"变成可当证据的数字
// （ISSUES #38 结案的那一半）。仍然要留一句：FCS 判的是"这一帧在介质上没被打坏"，
// 不等于"内容合规"，内容级的验收是 `frame_reasm` 的行数/偏移门（`rows_missed` / `oob`）。
module ku5p_telem #(
    parameter [15:0] IMG_W    = 16'd512,
    parameter [15:0] IMG_H    = 16'd300,
    parameter [31:0] TICK_CYC = 32'd125_000_000,   // GMII 域 125 MHz ⇒ 1 秒
    parameter [7:0]  VERSION  = 8'h02
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 被打包的观测值（全部与 clk 同域，没有 CDC）----
    input  wire [31:0] stat_frames,
    input  wire [31:0] stat_pkts,
    input  wire [31:0] stat_bytes,
    input  wire [31:0] stat_bad,
    input  wire [31:0] stat_oob,
    input  wire [15:0] rows_missed,
    input  wire        link_up,
    input  wire        frames_seen,
    input  wire        abort_seen,
    input  wire        data_alive,
    input  wire        peer_known,     // ARP 已学到 PC 的 MAC/IP

    // ---- 命令通道（ku5p_cmd）带来的三个效果 ----
    input  wire [7:0]  period_s,       // 上报周期（秒）；0 按 1 处理，绝不允许"从此不发"
    input  wire        cmd_clr,        // 1 拍：把基线推到现在
    input  wire        cmd_snap,       // 1 拍：立刻要一包（兼作命令的 ACK）
    input  wire [15:0] cmds_ok,
    input  wire [15:0] cmds_bad,
    input  wire        cmd_seen,

    // ---- 与 ku5p_tx_arb 的握手：want 是电平，被 grant（= tx_start_en 回显）清掉 ----
    output wire        udp_rqs,

    // ---- 接到 udp 模块的发送数据口 ----
    input  wire        tx_start_en,
    input  wire        tx_req,
    output wire [7:0]  tx_data,
    output wire [15:0] tx_byte_num
);
    // 36 > 31：写成 `localparam [4:0] NBYTES = 5'd36` 会被**静默截断成 4**。
    // 现象（台架抓到过）：包发得出去、IP 总长 32、载荷是厂商补位规则重复的最后一个字节。
    // v0x02 是 42 字节 —— 宽度跟着长到 [6:0]，`idx <= NBYTES` 的比较才不会绕。
    localparam [6:0] NBYTES = 7'd42;

    // ---- 心跳：先分"秒"，再数到 period_s ----
    // 周期不做成 `div == period_s*125e6-1`：那会在 125 MHz 的每拍都挂一条 32×8 乘法路径，
    // 而秒分频器本来就有 ⇒ 改成"秒 × 计数"，代价是一个 8 位比较器。
    // `period_s == 0` 按 1 处理：顶层没接、或命令把 0 传进来时，最坏的后果必须是"发得更勤"，
    // 不能是"这块板从此不再上报"——那是把这块板上**唯一**的可观测通道弄丢。
    wire [7:0] pdiv = (period_s == 8'd0) ? 8'd1 : period_s;

    reg [31:0] div;
    reg [7:0]  sec_cnt;
    reg [31:0] uptime_s;
    reg        want;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div <= 32'd0; uptime_s <= 32'd0; want <= 1'b0; sec_cnt <= 8'd0;
        end else begin
            if (div == TICK_CYC - 32'd1) begin
                div <= 32'd0;
                if (sec_cnt + 8'd1 >= pdiv) begin
                    sec_cnt <= 8'd0;
                    if (peer_known) want <= 1'b1;      // 没学到对端就别占介质
                end else sec_cnt <= sec_cnt + 8'd1;
                if (~&uptime_s) uptime_s <= uptime_s + 32'd1;
            end else div <= div + 32'd1;
            if (cmd_snap && peer_known) want <= 1'b1;  // SNAP：命令的 ACK 也走同一包
            if (tx_start_en) want <= 1'b0;
        end
    end
    assign udp_rqs = want;

    // ---- CLR 的基线：动的不是计数器，而是"从哪儿减"（理由见 ku5p_cmd.v 第 2 条）----
    reg [31:0] b_frames, b_pkts, b_bytes, b_bad, b_oob;
    reg        base_active;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_frames <= 32'd0; b_pkts <= 32'd0; b_bytes <= 32'd0;
            b_bad <= 32'd0; b_oob <= 32'd0; base_active <= 1'b0;
        end else if (cmd_clr) begin
            b_frames <= stat_frames; b_pkts <= stat_pkts; b_bytes <= stat_bytes;
            b_bad    <= stat_bad;    b_oob  <= stat_oob;
            base_active <= 1'b1;
        end
    end

    // ---- 发起那一拍的快照（先相减再锁，保证一包里前后字节同一时刻）----
    reg [31:0] s_frames, s_pkts, s_bytes, s_bad, s_oob, s_secs;
    reg [15:0] s_rows, s_cok, s_cbad;
    reg [7:0]  s_flags, s_flags2, s_period;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {s_frames, s_pkts, s_bytes, s_bad, s_oob, s_secs} <= 192'd0;
            {s_rows, s_cok, s_cbad} <= 48'd0;
            {s_flags, s_flags2, s_period} <= 24'd0;
        end else if (tx_start_en) begin
            s_frames <= stat_frames - b_frames;
            s_pkts   <= stat_pkts   - b_pkts;
            s_bytes  <= stat_bytes  - b_bytes;
            s_bad    <= stat_bad    - b_bad;
            s_oob    <= stat_oob    - b_oob;
            s_secs   <= uptime_s;                  // 上电秒数**不相减**：语义必须唯一
            s_rows   <= rows_missed;
            s_cok    <= cmds_ok;   s_cbad <= cmds_bad;
            s_period <= pdiv;
            s_flags  <= {4'd0, data_alive, abort_seen, frames_seen, link_up};
            s_flags2 <= {6'd0, base_active, cmd_seen};
        end
    end

    // ---- 读指针：复位在 start，递增在 req（tx_req 是一整段电平，等价 FIFO 的 rd_en）----
    reg [6:0] idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)           idx <= 7'd0;
        else if (tx_start_en) idx <= 7'd0;
        else if (tx_req && idx <= NBYTES) idx <= idx + 7'd1;
    end

    // case 项一律用**无位宽十进制**：写成 5'd32 会先被截成 0（同一个位宽陷阱）。
    reg [7:0] b;
    always @(*) begin
        case (idx)
            0:  b = 8'h4B;   // 'K'
            1:  b = 8'h55;   // 'U'
            2:  b = 8'h35;   // '5'
            3:  b = 8'h50;   // 'P'
            4:  b = VERSION;
            5:  b = s_flags;
            6:  b = IMG_W[15:8];
            7:  b = IMG_W[7:0];
            8:  b = IMG_H[15:8];
            9:  b = IMG_H[7:0];
            10: b = s_frames[31:24];
            11: b = s_frames[23:16];
            12: b = s_frames[15:8];
            13: b = s_frames[7:0];
            14: b = s_pkts[31:24];
            15: b = s_pkts[23:16];
            16: b = s_pkts[15:8];
            17: b = s_pkts[7:0];
            18: b = s_bytes[31:24];
            19: b = s_bytes[23:16];
            20: b = s_bytes[15:8];
            21: b = s_bytes[7:0];
            22: b = s_bad[31:24];
            23: b = s_bad[23:16];
            24: b = s_bad[15:8];
            25: b = s_bad[7:0];
            26: b = s_oob[31:24];
            27: b = s_oob[23:16];
            28: b = s_oob[15:8];
            29: b = s_oob[7:0];
            30: b = s_rows[15:8];
            31: b = s_rows[7:0];
            32: b = s_secs[31:24];
            33: b = s_secs[23:16];
            34: b = s_secs[15:8];
            35: b = s_secs[7:0];
            // ---- v0x02：命令通道带来的 6 个字节 ----
            36: b = s_cok[15:8];
            37: b = s_cok[7:0];
            38: b = s_cbad[15:8];
            39: b = s_cbad[7:0];
            40: b = s_period;
            default: b = s_flags2;   // 41；再往后（厂商的提前 req）仍重复最后一字节
        endcase
    end

    // 与厂商 FIFO 数据口同契约的那一拍（见文件头第 3 条）
    reg [7:0] b_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) b_q <= 8'd0;
        else        b_q <= b;
    end

    assign tx_data     = b_q;
    assign tx_byte_num = {9'd0, NBYTES};      // NBYTES 现在 7 位：拼成 16 位的补零位数跟着变
endmodule
