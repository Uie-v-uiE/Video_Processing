`timescale 1ns/1ps
// tap_sched —— 帧缓存读口的"每像素周期 5 槽"调度器：
//   右窗 1 个请求 → 4 个 RGB565 抽头；左窗 1 个像素地址 → 1 个像素。
//
// 为什么需要它（实测见 report/OVERNIGHT_LOG.md R11 追加 2、R18、R19、R20）：
//   * 旋转态的插值增益横向、纵向各约 20% ⇒ 必须读源图两行；
//   * 原来的帧缓存读口每个像素周期恰好一次 16bit 读、零余量 ⇒ 连"只补横向"都不免费；
//   * 解法：复用片上已经在跑的 clk_pix5x（同一 MMCM、同相、整数 5:1，不是异步 CDC），
//     每像素周期 5 个快槽 = 5 次读，右窗 4 + 左窗 1，**不新增任何 BRAM**
//     （在同一组阵列上"再加一个逻辑读口"实测 80 → 160 个 RAMB36）。
//
// 两条用红色门禁换来的纪律
// ------------------------------------------------------------------
// 1) 快域不做算术。clk_pix 与 clk_pix5x 同相 ⇒ 慢域触发器最早只能被下一个快沿采走，
//    跨进快域只有 4 ns 预算。build#14 把 `base+ROWW` 放在快域 ⇒ WNS −1.277 / 1400 端点。
//    现在四个抽头地址 + 左窗地址全部在慢域算好并各打一拍（fb_rd5x），跨进来的都是直线。
// 2) 地址必须在**贴着 BRAM 的那一级**寄存。build#15 只剩 −0.485，而它的报告显示
//    最差路径是 `slot_reg → 5 选 1 mux → RAMB36 ADDRBWRADDR`，
//    数据延迟 3.844 ns 里**布线占 3.255 ns（84.7%）**、只有 2 级 LUT ——
//    也就是"mux 到 80 个 BRAM tile"这一段没有预算可分。加一级地址寄存之后，
//    mux→寄存器 与 寄存器→BRAM 各得一个完整 4 ns，长的那段独自享受整周期。
//    ⇒ 本模块对外输出的 `rd_word_addr` 是**寄存后的**地址；读口数据因此晚一拍回来，
//      下面的槽位表已经按这个新节拍排好（不是简单 +1，采样沿都换了）。
//
// 槽位表（period p；"摆出"= 本 interval 在总线上；"到达"= rd_word 本 interval 有效）
//   s0  mux 选 A(p)      → 总线 s1   → 数据 s2   → 沿 s2 落 w_a
//   s1  mux 选 A+1       → 总线 s2   → 数据 s3   → 沿 s3 落 w_a1
//   s2  mux 选 B         → 总线 s3   → 数据 s4   → 沿 s4 落 w_b
//   s3  mux 选 B+1       → 总线 s4   → 数据 s0'  → 沿 s0' 落 w_b1（同时把属性推进工作区）
//   s4  mux 选 aux(p)    → 总线 s0'  → 数据 s1'  → 沿 s1' 落 aux_q/aux_lane_q + 拍 4 个抽头 + vld
//   沿 s4 同时采集新请求的 5 个地址（于是 s0 就能选中 A）
// ⇒ 右窗固定延迟 = 1 个像素周期 + 1 个快槽；输出保持一整个周期，上层用慢域触发器收。
module tap_sched #(
    parameter IMG_W = 512,
    parameter SLOTS = 5
)(
    input  wire        clk,               // 快时钟（clk_pix5x）
    input  wire        rst_n,

    input  wire        req,               // 自由节拍：每个采集沿都为 1
    input  wire [16:0] word,              // A   = 左上抽头字
    input  wire [16:0] word_p1,           // A+1
    input  wire [16:0] word_row,          // B   = 下一行同列
    input  wire [16:0] word_row_p1,       // B+1
    input  wire [1:0]  lane,              // 左上抽头在字内的车道
    input  wire [7:0]  fx,
    input  wire [7:0]  fy,

    input  wire [16:0] aux_word,          // 左窗字（慢域直线）
    input  wire [1:0]  aux_lane,          // 左窗车道（与字号同一个沿采集，成对进出）
    output reg  [63:0] aux_q,
    output reg  [1:0]  aux_lane_q,

    output reg  [16:0] rd_word_addr,      // **寄存后**的帧缓存字地址
    input  wire [63:0] rd_word,           // 帧缓存字输出（比地址总线的采样沿晚一整拍）

    output reg  [15:0] p00,
    output reg  [15:0] p10,
    output reg  [15:0] p01,
    output reg  [15:0] p11,
    output reg  [7:0]  ofx,
    output reg  [7:0]  ofy,
    output reg         vld
);
    localparam [2:0] LAST = SLOTS - 1;

    reg [2:0]   slot;
    reg [16:0]  a_q, a1_q, b_q, b1_q, aux_addr_q;
    reg [1:0]   aux_lane_x;
    reg [1:0]   lane_q, lane_w;
    reg [7:0]   fx_q, fy_q, fx_w, fy_w;
    reg [63:0]  w_a, w_a1, w_b, w_b1;
    reg         acc1, acc2, acc3;         // vld 只跟真被采纳过的请求（见 tb 里那条挪格现象）
                                          // 请求在 s4(p-1) 被采纳、抽头在 s1(p+1) 才出 ⇒ 要走三级

    wire s0 = (slot == 3'd0);
    wire s1 = (slot == 3'd1);
    wire s2 = (slot == 3'd2);
    wire s3 = (slot == 3'd3);
    wire s4 = (slot == 3'd4);

    function [15:0] pick;
        input [63:0] w;
        input [1:0]  l;
        begin
            case (l)
                2'd0:    pick = w[15:0];
                2'd1:    pick = w[31:16];
                2'd2:    pick = w[47:32];
                default: pick = w[63:48];
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slot <= 3'd0;
            rd_word_addr <= 17'd0;
            a_q <= 17'd0; a1_q <= 17'd0; b_q <= 17'd0; b1_q <= 17'd0;
            aux_addr_q <= 17'd0; aux_lane_x <= 2'd0;
            lane_q <= 2'd0; lane_w <= 2'd0;
            fx_q <= 8'd0; fy_q <= 8'd0; fx_w <= 8'd0; fy_w <= 8'd0;
            w_a <= 64'd0; w_a1 <= 64'd0; w_b <= 64'd0; w_b1 <= 64'd0;
            acc1 <= 1'b0; acc2 <= 1'b0; acc3 <= 1'b0;
            aux_q <= 64'd0; aux_lane_q <= 2'd0;
            p00 <= 16'd0; p10 <= 16'd0; p01 <= 16'd0; p11 <= 16'd0;
            ofx <= 8'd0; ofy <= 8'd0; vld <= 1'b0;
        end else begin
            slot <= (slot == LAST) ? 3'd0 : slot + 3'd1;
            vld  <= 1'b0;

            // ---- 地址总线：本拍选谁，下一拍才出现在总线上（纪律 2）----
            rd_word_addr <= s0 ? a_q
                         :  s1 ? a1_q
                         :  s2 ? b_q
                         :  s3 ? b1_q
                         :  aux_addr_q;

            // ---- 沿 s3：把左窗的 (字, 车道) 成对采进来，供 s4 选中 ----
            if (s3) begin
                aux_addr_q <= aux_word;
                aux_lane_x <= aux_lane;
            end

            // ---- 沿 s4：采新请求（于是 s0 就能选中 A）----
            if (s4) begin
                if (req) begin
                    a_q  <= word;
                    a1_q <= word_p1;
                    b_q  <= word_row;
                    b1_q <= word_row_p1;
                    lane_q <= lane;
                    fx_q   <= fx;
                    fy_q   <= fy;
                end
                acc1 <= req;
            end

            // ---- 沿 s0'：收 B+1，并把上一请求的属性推进工作区 ----
            if (s0) begin
                w_b1   <= rd_word;
                lane_w <= lane_q;
                fx_w   <= fx_q;
                fy_w   <= fy_q;
                acc2   <= acc1;
                acc3   <= acc2;
            end
            if (s2) w_a  <= rd_word;                // A
            if (s3) w_a1 <= rd_word;                // A+1
            if (s4) w_b  <= rd_word;                // B

            // ---- 沿 s1'：四个抽头 + 左窗字全部到位，一次拍出 ----
            if (s1) begin
                aux_q     <= rd_word;               // 左窗（s0' 出现在总线上）
                aux_lane_q<= aux_lane_x;
                p00 <= pick(w_a,  lane_w);
                p10 <= (lane_w == 2'd3) ? w_a1[15:0] : pick(w_a,  lane_w + 2'd1);
                p01 <= pick(w_b,  lane_w);
                p11 <= (lane_w == 2'd3) ? w_b1[15:0] : pick(w_b,  lane_w + 2'd1);
                ofx <= fx_w;
                ofy <= fy_w;
                vld <= acc3;
            end
        end
    end
endmodule
