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
// 线上格式（大端，36 字节 UDP 载荷；PC 侧解析器在 src/host/ku5p_stats.mjs，两处必须一起改）：
//   [0:3] 'K''U''5''P'   [4] 版本   [5] 标志位
//   [6:7] 图像宽  [8:9] 图像高
//   [10:13] 完整帧数  [14:17] 包数  [18:21] 载荷字节数  [22:25] 校验/长度错包数
//   [26:29] 越界偏移字节数  [30:31] 本帧缺行数  [32:35] 上电秒数(低 32 位)
// 计数器都是 32 位只增（15 fps 下 stat_bytes 约 930 s 回绕一次），不做饱和。
// 载荷 36 ≥ 厂商 MIN_DATA_NUM(18) ⇒ 不会走它的"末尾重复补位"路径。
//
// **字段诚实性（重要，别把它当成"错误为 0"）**：[22:25] 那个 `bad` 目前是
// **构造性为 0** —— `frame_reasm.p_good` 在两个板的顶层都硬接 1'b1（顶层 udp 收包用的是
// 厂商 `udp_rx`，它不看 ER/帧长），所以 `stat_bad` 那条累加永远不会走。
// 现场能当"健康证据"用的是 `oob`（越界偏移）、`rows_missed`、以及 flags 里的 `abort_seen`。
// 修法已经想清楚且**代码已在仓库里**：自研 `gmii_rx_mac` 出 `m_good/m_bad`
// （无 ER 且 len≥64；注意这不是真 CRC-32 校验），`udp_rx_parser` 吃它并产出 `p_good`
// 与三个 drop 统计，`sim/tb_udp_parser.v` 有判据 —— 只是两个顶层都还没换上去。
// 登记在 report/ISSUES.md #29。
module ku5p_telem #(
    parameter [15:0] IMG_W    = 16'd512,
    parameter [15:0] IMG_H    = 16'd300,
    parameter [31:0] TICK_CYC = 32'd125_000_000,   // GMII 域 125 MHz ⇒ 1 秒
    parameter [7:0]  VERSION  = 8'h01
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
    localparam [5:0] NBYTES = 6'd36;

    // ---- 心跳：到点置 want，等仲裁放行 ----
    reg [31:0] div;
    reg [31:0] uptime_s;
    reg        want;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div <= 32'd0; uptime_s <= 32'd0; want <= 1'b0;
        end else begin
            if (div == TICK_CYC - 32'd1) begin
                div <= 32'd0;
                if (peer_known) want <= 1'b1;      // 没学到对端就别占介质
                if (~&uptime_s) uptime_s <= uptime_s + 32'd1;
            end else div <= div + 32'd1;
            if (tx_start_en) want <= 1'b0;
        end
    end
    assign udp_rqs = want;

    // ---- 发起那一拍的快照 ----
    reg [31:0] s_frames, s_pkts, s_bytes, s_bad, s_oob, s_secs;
    reg [15:0] s_rows;
    reg [7:0]  s_flags;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {s_frames, s_pkts, s_bytes, s_bad, s_oob, s_secs} <= 192'd0;
            {s_rows, s_flags} <= 24'd0;
        end else if (tx_start_en) begin
            s_frames <= stat_frames; s_pkts   <= stat_pkts;
            s_bytes  <= stat_bytes;  s_bad    <= stat_bad;
            s_oob    <= stat_oob;    s_secs   <= uptime_s;
            s_rows   <= rows_missed;
            s_flags  <= {4'd0, data_alive, abort_seen, frames_seen, link_up};
        end
    end

    // ---- 读指针：复位在 start，递增在 req（tx_req 是一整段电平，等价 FIFO 的 rd_en）----
    reg [5:0] idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)           idx <= 6'd0;
        else if (tx_start_en) idx <= 6'd0;
        else if (tx_req && idx <= NBYTES) idx <= idx + 6'd1;
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
            default: b = s_secs[7:0];   // 35
        endcase
    end

    // 与厂商 FIFO 数据口同契约的那一拍（见文件头第 3 条）
    reg [7:0] b_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) b_q <= 8'd0;
        else        b_q <= b;
    end

    assign tx_data     = b_q;
    assign tx_byte_num = {10'd0, NBYTES};
endmodule
