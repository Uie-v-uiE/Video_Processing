`timescale 1ns/1ps
// fb_rd5x —— 显示侧唯一的帧缓存读口：一个 50 MHz 像素时钟 + 一个 250 MHz 同源 5 倍时钟，
// 每个像素周期发出 5 次读（左窗 1 次最近邻 + 右窗 4 次双线性抽头），产出一条与今天
// `fb_rd` 用法完全相同的 16bit 像素总线，只是延迟从 2 拍变成 LAT=5 拍。
//
// 为什么读口能塞下 5 次读：见 tap_sched 头部（同一个 MMCM、同相、整数 5:1 ⇒ 不是异步 CDC，
// 每像素周期正好 5 个快槽，右窗 4 + 左窗 1 = 恰好占满，不新增任何 BRAM）。
//
// 跨域纪律（这个模块存在的核心理由，也是它最容易被后人改坏的地方）：
//   * clk_pix 和 clk_pix5x 同相 ⇒ Vivado 判 clk_pix→clk_pix5x 路径只给**一个快周期 2 ns**。
//     所以任何从慢域触发器出发、被快域用掉的信号，中途**不允许有任何组合逻辑**：
//     字号/车道/小数全部在慢域算完（那里一整个 20 ns 预算），跨过去的是直线。
//   * 反方向（快域→慢域）最坏有 18 ns，所以抽头/左窗字都在快域先落一次触发器再交给慢域。
//   * 插值算术（bilin_lerp 的 12 个乘法）留在慢域 —— 快域 4 ns 塞不下，而且慢域本来就有预算。
//
// LAT = 5 的含义：从 (sx_l,sy_l)/(sx_r,sy_r,fx_r,fy_r) 在慢域有效，到 pix/oob_out/right_out
// 有效，正好 5 个 clk_pix 周期。这个数**由 sim/tb_fb_rd5x.v 逐拍量出来**，不是纸上推的；
// 顶层所有配准抽位都由它导出（见 pl_video_top.v 的 RD_LAT），不要手改数字。
module fb_rd5x #(
    parameter IMG_W     = 512,
    parameter IMG_H     = 300,
    parameter BILIN_EN  = 1      // 0 ⇒ 右窗小数强制 0，通路一模一样地退化成最近邻（A/B 与回退用）
)(
    input  wire        clk,            // clk_pix  50 MHz
    input  wire        clk5x,          // clk_pix5x 250 MHz，同源同相
    input  wire        rst_n,

    // 帧缓存写侧直通（AXI 拷贝 / FILL 都从这里进）
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,
    input  wire [63:0] wr_data,

    // 慢域输入（与今天的 sx_fb/sy_fb 同一级流水位置）
    input  wire [11:0] sx_l, sy_l,
    input  wire [11:0] sx_r, sy_r,
    input  wire [7:0]  fx_r, fy_r,
    input  wire        sel_right,      // 本拍请求属于右窗
    input  wire        oob_l, oob_r,

    // 慢域输出：LAT 拍之后
    output wire [15:0] pix,
    output wire        oob_out,
    output wire        right_out
);
    localparam LAT = 5;

    // ---------------------------------------------------------------- 慢域地址级
    wire [18:0] pxl_r = sy_r * IMG_W + sx_r;      // 20 ns 预算：乘常数 = 移位加
    wire [18:0] pxl_l = sy_l * IMG_W + sx_l;

    // 抽头越界保护：最后一列/行的 +1 抽头落在图外 ⇒ 把小数钉成 0，
    // 让 bilin_lerp 在 fx=0/fy=0 时恒等于 p00（这条性质由 tb_bilin_lerp 判据 2 保证）。
    // 图外的字地址本身不会读出 X：frame_buffer_w64 对读地址做了掩码夹取（见其注释）。
    wire [7:0] fx_use = (BILIN_EN == 0 || sx_r >= IMG_W-1) ? 8'd0 : fx_r;
    wire [7:0] fy_use = (BILIN_EN == 0 || sy_r >= IMG_H-1) ? 8'd0 : fy_r;
    wire       oob_in = sel_right ? oob_r : oob_l;

    reg [16:0] word_r_q, word_l_q;
    reg [1:0]  lane_r_q, lane_l_q;
    reg [7:0]  fx_q, fy_q;
    reg [4:0]  sel_chain;                          // 侧带：LAT 拍移位
    reg [4:0]  oob_chain;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            word_r_q <= 17'd0; word_l_q <= 17'd0;
            lane_r_q <= 2'd0;  lane_l_q <= 2'd0;
            fx_q <= 8'd0; fy_q <= 8'd0;
            sel_chain <= 5'b11111;                 // 复位期当"左窗"，输出被 oob 夹成黑
            oob_chain <= 5'b00000;
        end else begin
            word_r_q <= pxl_r[18:2];
            word_l_q <= pxl_l[18:2];
            lane_r_q <= pxl_r[1:0];
            lane_l_q <= pxl_l[1:0];
            fx_q     <= fx_use;
            fy_q     <= fy_use;
            sel_chain <= {sel_chain[3:0], sel_right};
            oob_chain <= {oob_chain[3:0], oob_in};
        end
    end

    // ---------------------------------------------------------------- 快域调度
    wire [16:0] rd_word_addr;
    wire [63:0] fb_word;
    wire [63:0] aux_q;
    wire [1:0]  aux_lane_q;
    wire [15:0] p00, p10, p01, p11;
    wire [7:0]  ofx, ofy;
    wire        tap_vld;

    tap_sched #(.IMG_W(IMG_W)) u_sched (
        .clk(clk5x), .rst_n(rst_n),
        .req(1'b1),                       // 自由节拍：每个像素周期一个请求，永不停
        .word(word_r_q), .lane(lane_r_q), .fx(fx_q), .fy(fy_q),
        .aux_word(word_l_q), .aux_lane(lane_l_q),
        .aux_q(aux_q), .aux_lane_q(aux_lane_q),
        .rd_word_addr(rd_word_addr), .rd_word(fb_word),
        .p00(p00), .p10(p10), .p01(p01), .p11(p11),
        .ofx(ofx), .ofy(ofy), .vld(tap_vld)
    );

    frame_buffer_w64 #(.W(IMG_W), .H(IMG_H)) u_fb (
        .wr_clk(wr_clk), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_clk(clk5x), .rd_addr({rd_word_addr, 2'b00}),
        .rd_data(), .rd_data64(fb_word)
    );

    // ---------------------------------------------------------------- 慢域收口
    // 抽头：快域在 s2..s4 内稳定，这里第一个 clk 沿收（LAT 记账的第 2 拍）
    reg [15:0] ta_r, tb_r, tc_r, td_r;
    reg [7:0]  fx_r_r, fy_r_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ta_r <= 16'd0; tb_r <= 16'd0; tc_r <= 16'd0; td_r <= 16'd0;
            fx_r_r <= 8'd0; fy_r_r <= 8'd0;
        end else begin
            ta_r <= p00; tb_r <= p10; tc_r <= p01; td_r <= p11;
            fx_r_r <= ofx; fy_r_r <= ofy;
        end
    end

    // 左窗：aux_q/aux_lane_q 是快域触发器，车道 mux 在慢域做（预算 18 ns 起）
    reg [63:0] lw_q;
    reg [1:0]  ll_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin lw_q <= 64'd0; ll_q <= 2'd0; end
        else begin lw_q <= aux_q; ll_q <= aux_lane_q; end
    end
    // 左路本来就比右路快 2 拍（它只要一次读，右路要 4 次读 + 2 级插值），
    // 这里把它补齐到同一拍 —— 两条路必须同拍，否则切换窗口时画面会左右错开。
    reg [15:0] left_p0, left_p1, left_p2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            left_p0 <= 16'd0; left_p1 <= 16'd0; left_p2 <= 16'd0;
        end else begin
            case (ll_q)
                2'd0:    left_p0 <= lw_q[15:0];
                2'd1:    left_p0 <= lw_q[31:16];
                2'd2:    left_p0 <= lw_q[47:32];
                default: left_p0 <= lw_q[63:48];
            endcase
            left_p1 <= left_p0;
            left_p2 <= left_p1;
        end
    end

    wire [15:0] pix_r;
    bilin_lerp u_lerp (
        .clk(clk), .rst_n(rst_n),
        .p00(ta_r), .p10(tb_r), .p01(tc_r), .p11(td_r),
        .fx(fx_r_r), .fy(fy_r_r), .pix(pix_r), .vld()
    );

    assign pix       = sel_chain[4] ? pix_r  : left_p2;
    assign oob_out   = oob_chain[4];
    assign right_out = sel_chain[4];
endmodule
