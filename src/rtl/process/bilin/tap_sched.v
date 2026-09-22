`timescale 1ns/1ps
// tap_sched —— 帧缓存读口的"每像素周期 5 槽"调度器：
//   右窗 1 个请求 → 4 个 RGB565 抽头 + Q8 小数位；左窗 1 个字号 → 1 个 64bit 字。
//
// 为什么必须这么排（实测结论，见 report/OVERNIGHT_LOG.md R11 追加 2、R18）：
//   * 旋转态的插值增益横向、纵向各约 20% ⇒ 必须读源图两行 ⇒ 一个输出像素要 4 个抽头；
//   * 原来的帧缓存读口每个像素周期恰好一次 16bit 读、零余量 ⇒ 连"只补横向"都不免费；
//   * 解法是复用**已经在片上跑的** 5 倍像素时钟（同一个 MMCM、同相、整数 5:1 关系）：
//     每像素周期 5 个快槽，右窗 4 + 左窗 1 = 恰好占满，**不新增任何 BRAM**。
//     （试过"在同一组阵列上再加一个逻辑读口"：80 → 160 个 RAMB36，实测见 R11。）
//
// 为什么地址输入是"字号 + 车道"而不是 (sx,sy)：
//   clk_pix 和 clk_pix5x 同相 ⇒ Vivado 对 clk_pix→clk_pix5x 路径按**最早的那个快沿**判，
//   Setup 预算只有 2 ns。所以凡是"从 clk_pix 触发器出发、在快域被用掉"的路径都必须是一根
//   直线（不能有乘法/加法/mux）。字号与车道由上层在 clk_pix 域算好（那里 20 ns 预算）送进来，
//   本模块内部的加法一律从快域触发器出发（4 ns 预算）。
//
// 槽位（interval 记号：slot=v 表示 t∈[20p+2v, 20p+2v+2)；always 块里的条件在"该 interval
// 结束的那个沿"执行，采到的是该 interval 内的值 —— 这就是为什么下面 s1 采的是 s0 发的读）：
//   s0 发左窗字（直线 aux_word）｜ 沿 s0：采右窗请求 word/lane/fx/fy
//   s1 发 A=base                ｜ 沿 s1：落 aux_q/aux_lane（左窗字）
//   s2 发 A+1                   ｜ 沿 s2：落 w_a
//   s3 发 B=base+ROW            ｜ 沿 s3：落 w_a1
//   s4 发 B+1                   ｜ 沿 s4：落 w_b
//   s0'（下一周期）             ｜ 沿 s0'：落 w_b1 + 把上一请求的 lane/fx/fy 推进工作区
//   s1'                         ｜ 沿 s1'：一次拍出 p00/p10/p01/p11 + ofx/ofy + vld（vld 只跟真请求）
// ⇒ 固定延迟 = 1 个像素周期 + 3 个快槽；输出保持一整个周期，上层用慢域触发器收。
module tap_sched #(
    parameter IMG_W = 512,
    parameter SLOTS = 5
)(
    input  wire        clk,               // 快时钟（clk_pix5x）
    input  wire        rst_n,

    input  wire        req,               // 自由节拍：每个 s0 都为 1
    input  wire [16:0] word,              // 右窗左上抽头所在字号（= 像素号 >> 2）
    input  wire [1:0]  lane,              // 左上抽头在字内的车道
    input  wire [7:0]  fx,
    input  wire [7:0]  fy,

    input  wire [16:0] aux_word,          // 左窗字号（clk_pix 域直线送进来）
    input  wire [1:0]  aux_lane,          // 左窗车道（字号里被丢掉的那两位，必须一起送）
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
    localparam [16:0] ROWW = IMG_W / 4;   // 一行的字数（IMG_W 是 4 的倍数 ⇒ 常数，无乘法器）
    localparam [2:0]  LAST = SLOTS - 1;

    reg [2:0]  slot;
    reg [16:0] base;
    reg [1:0]  lane_q, lane_w;             // _q = 本请求刚采到的；_w = 正在出抽头的那个请求的
    reg [7:0]  fx_q, fy_q, fx_w, fy_w;
    reg [63:0] w_a, w_a1, w_b, w_b1;
    // vld 必须跟着"真被采纳过的请求"走：抽头每拍都会照原样寄存器一次，灌水的头两拍里
    // 装的是复位值 —— 不加这级跟随，tb 的第一次 vld 就会把期望队列整体挪一格（今晚真踩过，
    // 现象是"错 123 条、每条的 got 都等于上一条的 exp"，一眼可辨）。
    reg        acc1, acc2;

    wire s0 = (slot == 3'd0);
    wire s1 = (slot == 3'd1);
    wire s2 = (slot == 3'd2);
    wire s3 = (slot == 3'd3);
    wire s4 = (slot == 3'd4);

    // 发地址：s0 给左窗，s1..s4 给右窗的 4 个字。
    // 注意 base+ROWW+1 在这里是"从快域触发器出发的两个常数加"，4 ns 预算够（不是 2 ns 跨域路径）。
    wire [16:0] a1   = base + 17'd1;
    wire [16:0] bw   = base + ROWW;
    wire [16:0] bw1  = bw + 17'd1;
    assign rd_word_addr = s1 ? base
                        :  s2 ? a1
                        :  s3 ? bw
                        :  s4 ? bw1
                        :  aux_word;                    // s0

    // 字内取车道：lane+1 只在 lane<3 时被用到（lane==3 走下一个字），
    // 所以 {lane,2'b1} 的回绕不会真的被选中。
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
            base <= 17'd0;
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

            // ---- 沿 s0：采新请求；同时把上一请求的属性推进工作区（它的抽头还要两拍后才出）----
            if (s0) begin
                if (req) begin
                    base   <= word;
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
                aux_lane_q<= aux_lane;
            end
            if (s2) w_a  <= rd_word;                // A
            if (s3) w_a1 <= rd_word;                // A+1
            if (s4) w_b  <= rd_word;                // B

            // ---- 沿 s1'：四个抽头齐了，一次拍出 ----
            if (s1) begin
                p00 <= pick(w_a,  lane_w);
                p10 <= (lane_w == 2'd3) ? w_a1[15:0] : pick(w_a,  lane_w + 2'd1);
                p01 <= pick(w_b,  lane_w);
                p11 <= (lane_w == 2'd3) ? w_b1[15:0] : pick(w_b,  lane_w + 2'd1);
                ofx <= fx_w;
                ofy <= fy_w;
                vld <= acc2;                          // 只有真请求采纳过才算一次输出
            end
        end
    end
endmodule
