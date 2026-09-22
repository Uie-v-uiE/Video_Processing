`timescale 1ns/1ps
// tap_sched —— 双线性插值的读口调度：一个右窗像素请求 → 4 个 RGB565 抽头 + Q8 小数位。
//
// 为什么需要它（实测结论，见 report/OVERNIGHT_LOG.md R11 追加 2）：旋转态的增益横向、
// 纵向各只占约 20% ⇒ 必须读源图两行；而现有帧缓存读口每个像素周期恰好一次 16bit 读、
// 零余量 ⇒ 连"只补横向"都不免费。解法是复用已经在用的 5 倍像素时钟（同源、非异步 CDC）：
// 每像素周期 5 个槽，右窗用 4 个，**不新增任何 BRAM**（再加一个逻辑读口会把帧缓存从
// 80 个 RAMB36 顶到 160 个，实测见 sim/probes）。
//
// 槽位（SLOTS=5）：
//   0 采请求 + 发 A        1 发 A+1   收 A
//   1 发 B                 2 收 A+1
//   …                      4 收 B+1 并同拍出结果
// 一个请求正好占满一个像素周期 ⇒ 下一请求在**下一个** slot0 进入，
// 而它和上一请求的输出同拍但用不同寄存器 —— 所以**一套属性寄存器就够**，不需要双 bank。
//
// 前提：IMG_W 是 4 的倍数 ⇒ 行偏移在"字地址"里是常数 IMG_W/4（调度器里没有乘法器）。
module tap_sched #(
    parameter IMG_W = 512,
    parameter SLOTS = 5
)(
    input  wire        clk,               // 快时钟（clk_pix5x）
    input  wire        rst_n,

    input  wire        req,               // 只在 fetching=1 的那一拍有效
    input  wire [11:0] sx,
    input  wire [11:0] sy,
    input  wire [7:0]  fx,
    input  wire [7:0]  fy,

    output wire        fetching,          // 本拍是请求采样槽（slot 0）
    output wire        rd_en,
    output wire [18:0] rd_word_addr,      // 帧缓存 64bit 读口的字地址（组合输出）
    input  wire [63:0] rd_word,           // 延迟 1 个快时钟周期

    output reg  [15:0] p00,
    output reg  [15:0] p10,
    output reg  [15:0] p01,
    output reg  [15:0] p11,
    output reg  [7:0]  ofx,
    output reg  [7:0]  ofy,
    output reg         vld
);
    localparam [18:0] ROWW = IMG_W / 4;          // 一行的字数（IMG_W % 4 == 0 才有意义）
    localparam [ 2:0] LAST = SLOTS - 1;

    reg [2:0]  slot;
    reg [2:0]  iss;                              // 本请求已发出的地址数 0..4
    reg [1:0]  cap;                              // 已收回的字数 0..2（第 3 个当拍出结果）
    reg [18:0] base;
    reg [1:0]  lane;
    reg [7:0]  fx_s, fy_s;
    reg [63:0] w_a, w_a1, w_b;
    reg        rd_last;                          // 上一拍发过读 ⇒ 本拍 rd_word 有效

    // 请求的组合地址（slot0 用输入的即时值发第一个地址）
    wire [18:0] pixnum = sy * ROWW[9:0] * 4 + sx;
    wire [18:0] word_n = pixnum >> 2;
    wire [1:0]  lane_n = pixnum[1:0];

    wire [5:0] lo    = {4'b0, lane} << 4;             // lane*16 ∈ {0,16,32,48}
    wire [5:0] lo_nx = (lo + 6'd16) & 6'd48;          // lane==3 时这条分支不被使用，夹住防越界

    assign fetching = (slot == 3'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slot <= 3'd0; iss <= 3'd0; cap <= 2'd0;
            base <= 19'd0; lane <= 2'd0; fx_s <= 8'd0; fy_s <= 8'd0;
            w_a <= 64'd0; w_a1 <= 64'd0; w_b <= 64'd0;
            rd_last <= 1'b0;
            p00 <= 16'd0; p10 <= 16'd0; p01 <= 16'd0; p11 <= 16'd0;
            ofx <= 8'd0; ofy <= 8'd0; vld <= 1'b0;
        end else begin
            // ---- 槽计数 ----
            slot <= (slot == LAST) ? 3'd0 : slot + 3'd1;

            vld <= 1'b0;

            // ---- 收字（上一拍发过读）----
            if (rd_last) begin
                case (cap)
                    2'd0: begin w_a  <= rd_word; cap <= 2'd1; end
                    2'd1: begin w_a1 <= rd_word; cap <= 2'd2; end
                    2'd2: begin w_b  <= rd_word; cap <= 2'd3; end
                    default: ;                       // 第 4 个字在本拍直接用 rd_word，不落寄存器
                endcase
            end

            // ---- 登记本拍的发地址结果（地址本身是组合的，见下面的 assign）----
            if (fetching && req) begin               // slot0：新请求
                base  <= word_n;
                lane  <= lane_n;
                fx_s  <= fx;
                fy_s  <= fy;
                iss   <= 3'd1;
                cap   <= 2'd0;
            end else if (iss != 3'd0 && iss != 3'd4) begin
                iss <= iss + 3'd1;                   // slot1..3 各再发一个字
            end else if (iss == 3'd4 && slot == LAST) begin
                iss <= 3'd0;
            end

            // ---- 出结果：slot LAST 且第 4 个字这一拍到 ----
            if (slot == LAST && rd_last && iss == 3'd4) begin
                p00 <= w_a [lo     +: 16];
                p10 <= (lane == 2'd3) ? w_a1[15:0] : w_a [lo_nx +: 16];
                p01 <= w_b [lo     +: 16];
                p11 <= (lane == 2'd3) ? rd_word[15:0] : w_b [lo_nx +: 16];
                ofx <= fx_s;
                ofy <= fy_s;
                vld <= 1'b1;
                iss <= 3'd0;
                cap <= 2'd0;
            end

            rd_last <= rd_en;
        end
    end

    // 组合发地址：一个请求固定 4 拍（A、A+1、B、B+1），落在 slot0..slot3。
    // 注册 rd_en 会把整串推后一槽 ⇒ slot4 输出时第 4 个字还没到，只能拿到上一请求的 w_b。
    wire start = (slot == 3'd0) && req;
    assign rd_en = start || ((iss != 3'd0) && (iss != 3'd4));
    assign rd_word_addr = start  ? word_n
                        : (iss == 3'd1) ? (base + 19'd1)
                        : (iss == 3'd2) ? (base + ROWW)
                        : (iss == 3'd3) ? (base + ROWW + 19'd1)
                        : 19'd0;
endmodule
