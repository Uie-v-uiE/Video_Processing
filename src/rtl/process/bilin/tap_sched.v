`timescale 1ns/1ps
// tap_sched —— 帧缓存读口的"每像素周期 5 槽"调度器：
//   右窗 1 个请求 → 4 个 RGB565 抽头 + Q8 小数位；左窗 1 个字号 → 1 个 64bit 字。
//
// 为什么需要它（实测结论，见 report/OVERNIGHT_LOG.md R11 追加 2、R18、R19）：
//   * 旋转态的插值增益横向、纵向各约 20% ⇒ 必须读源图两行；
//   * 原来的帧缓存读口每个像素周期恰好一次 16bit 读、零余量 ⇒ 连"只补横向"都不免费；
//   * 解法是复用**已经在片上跑的** 5 倍像素时钟（同一个 MMCM、同相、整数 5:1）：
//     每像素周期 5 个快槽，右窗 4 + 左窗 1 = 恰好占满，**不新增任何 BRAM**。
//     （试过"在同一组阵列上再加一个逻辑读口"：80 → 160 个 RAMB36，实测见 R11。）
//
// 快域里一律不做算术（build#14 用 −1.277 ns / 1400 个失败端点换来的教训）：
//   clk_pix5x 周期 4 ns，而慢域触发器的输出最早只能在**下一个快沿**被采走 ⇒
//   跨到快域的那一拍只有 4 ns 预算，不是 20 ns。build#14 里"快域做 base+ROWW 加法再进 5:1 mux"
//   实测需要约 5.3 ns ⇒ 整条读口判红。所以：
//     - 四个抽头字号 + 左窗字号 **全部在慢域算好并各自打一拍**（慢域有 20 ns）；
//     - 进快域的是直线（无逻辑）；
//     - 快域只做一次 5 选 1 地址 mux（输入都是快域触发器）。
//   这条纪律比"看起来省了几级寄存器"重要：它是有门的，门就是 timing_summary。
//
// 槽位（interval 记号：slot=v 表示第 v 个快周期；always 块里的条件在"该 interval 结束的沿"
// 执行，采到的是该 interval 内的值 —— 这就是为什么 s1 采到的是 s0 发出的读）：
//   s0 发左窗字（wL_x）           ｜ 沿 s0：采右窗的 4 个字号 + lane + fx/fy
//   s1 发 A                       ｜ 沿 s1：落 aux_q/aux_lane_q（左窗字到达）
//   s2 发 A+1                     ｜ 沿 s2：落 w_a
//   s3 发 B                       ｜ 沿 s3：落 w_a1
//   s4 发 B+1                     ｜ 沿 s4：落 w_b
//   s0'（下一周期）               ｜ 沿 s0'：落 w_b1 + 把上一请求的属性推进工作区
//   s1'                           ｜ 沿 s1'：一次拍出 p00/p10/p01/p11 + ofx/ofy + vld（vld 只跟真请求）
module tap_sched #(
    parameter IMG_W = 512,
    parameter SLOTS = 5
)(
    input  wire        clk,               // 快时钟（clk_pix5x）
    input  wire        rst_n,

    input  wire        req,               // 自由节拍：每个 s0 都为 1
    input  wire [16:0] word,              // A   = 左上抽头所在字号
    input  wire [16:0] word_p1,           // A+1（lane==3 时才真用得上，但每拍都发，节拍固定）
    input  wire [16:0] word_row,          // B   = 下一行同列
    input  wire [16:0] word_row_p1,       // B+1
    input  wire [1:0]  lane,              // 左上抽头在字内的车道
    input  wire [7:0]  fx,
    input  wire [7:0]  fy,

    input  wire [16:0] aux_word,          // 左窗字号（慢域直线）
    input  wire [1:0]  aux_lane,          // 左窗车道（字号里被丢掉的低 2 位，必须一起送）
    output reg  [63:0] aux_q,             // 左窗字
    output reg  [1:0]  aux_lane_q,        // 与 aux_q 同拍对齐的车道

    output wire [16:0] rd_word_addr,      // 组合送到帧缓存的字地址
    input  wire [63:0] rd_word,           // 帧缓存字输出：地址摆出后延迟 1 个快周期

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
    reg [16:0]  a_q, a1_q, b_q, b1_q, aux_q_addr;   // 快域地址池：mux 的输入全是本域触发器
    reg [1:0]   aux_lane_x;                        // 与 aux_q_addr **同一个沿**采，保证字/车道成对
    reg [1:0]   lane_q, lane_w;
    reg [7:0]   fx_q, fy_q, fx_w, fy_w;
    reg [63:0]  w_a, w_a1, w_b, w_b1;
    // vld 必须跟着"真被采纳过的请求"走：抽头每拍都会照原样寄存器一次，灌水的头两拍里
    // 装的是复位值 —— 不加这级跟随，台架第一次 vld 就会把期望队列整体挪一格
    //（现象是"错 123 条、每条的 got 都等于上一条的 exp"）。
    reg         acc1, acc2;

    wire s0 = (slot == 3'd0);
    wire s1 = (slot == 3'd1);
    wire s2 = (slot == 3'd2);
    wire s3 = (slot == 3'd3);
    wire s4 = (slot == 3'd4);

    // 5 选 1：输入全是快域触发器（含 aux_q_addr，它在 s0 沿由慢域直线送入）
    assign rd_word_addr = s1 ? a_q
                        :  s2 ? a1_q
                        :  s3 ? b_q
                        :  s4 ? b1_q
                        :  aux_q_addr;                  // s0

    // 字内取车道：lane+1 只在 lane<3 时被用到（lane==3 走下一个字），回绕不会被选中
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
            a_q <= 17'd0; a1_q <= 17'd0; b_q <= 17'd0; b1_q <= 17'd0; aux_q_addr <= 17'd0;
            aux_lane_x <= 2'd0;
            lane_q <= 2'd0; lane_w <= 2'd0;
            fx_q <= 8'd0; fy_q <= 8'd0; fx_w <= 8'd0; fy_w <= 8'd0;
            w_a <= 64'd0; w_a1 <= 64'd0; w_b <= 64'd0; w_b1 <= 64'd0;
            acc1 <= 1'b0; acc2 <= 1'b0;
            aux_q <= 64'd0; aux_lane_q <= 2'd0;
            p00 <= 16'd0; p10 <= 16'd0; p01 <= 16'd0; p11 <= 16'd0;
            ofx <= 8'd0; ofy <= 8'd0; vld <= 1'b0;
        end else begin
            slot <= (slot == LAST) ? 3'd0 : slot + 3'd1;
            vld  <= 1'b0;

            // 左窗地址与车道在**每个 s0 起始沿**一起被采进快域（慢域那一整拍都稳定，
            // 这里只是把直线落一拍，好让 s0 的 mux 输入全是本域触发器）。
            // 必须成对：地址是"上一拍的字号"，车道也必须是同一拍的 —— 分开采就会
            // 字对车道错，板上的现象正是"整列颜色对、左右偏一格"（台架抓到过一次）。
            aux_q_addr <= aux_word;
            aux_lane_x <= aux_lane;

            // ---- 沿 s0：采本请求的 4 个字号与属性；把上一请求的属性推进工作区 ----
            if (s0) begin
                if (req) begin
                    a_q  <= word;
                    a1_q <= word_p1;
                    b_q  <= word_row;
                    b1_q <= word_row_p1;
                    lane_q <= lane;
                    fx_q   <= fx;
                    fy_q   <= fy;
                end
                lane_w <= lane_q;
                fx_w   <= fx_q;
                fy_w   <= fy_q;
                acc2   <= acc1;
                acc1   <= req;
                w_b1   <= rd_word;                  // 上一请求 s4 发的 B+1，本 interval 数据有效
            end

            if (s1) begin                           // 左窗字（s0 发）到
                aux_q     <= rd_word;
                aux_lane_q<= aux_lane_x;            // 与这个字同一次采集的车道，不是本拍的输入
            end
            if (s2) w_a  <= rd_word;                // A
            if (s3) w_a1 <= rd_word;                // A+1
            if (s4) w_b  <= rd_word;                // B

            // ---- 沿 s1'：四个抽头齐了，一次拍出 ----
            if (s1) begin
                p00 <= pick(w_a,  lane_w);
                p10 <= (lane_w == 2'd3) ? w_a1[15:0]  : pick(w_a,  lane_w + 2'd1);
                p01 <= pick(w_b,  lane_w);
                p11 <= (lane_w == 2'd3) ? w_b1[15:0]  : pick(w_b,  lane_w + 2'd1);
                ofx <= fx_w;
                ofy <= fy_w;
                vld <= acc2;
            end
        end
    end
endmodule
