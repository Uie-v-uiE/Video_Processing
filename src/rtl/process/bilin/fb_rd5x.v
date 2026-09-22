`timescale 1ns/1ps
// fb_rd5x —— 显示侧唯一的帧缓存读口：一个 50 MHz 像素时钟 + 一个 250 MHz 同源 5 倍时钟，
// 每个像素周期发出 5 次读（左窗 1 次最近邻 + 右窗 4 次双线性抽头），产出一条与 V7.7 之前
// `fb_rd` 用法完全相同的 16bit 像素总线，只是延迟从 2 拍变成 LAT=5 拍。
//
// 为什么读口塞得下 5 次读：见 tap_sched 头部。一句话 —— 复用片上已经在跑的 clk_pix5x，
// 每像素周期 5 个快槽恰好被"右 4 + 左 1"占满，**不新增任何 BRAM**（加第二个逻辑读口
// 实测把帧缓存从 80 个 RAMB36 顶到 160 个，全片才 140 个）。
//
// 跨域纪律（build#14 用一次红色门禁换来的，别改回去）：
//   1. clk_pix 与 clk_pix5x 同相 ⇒ 慢域触发器的输出**最早**只能被下一个快沿采走，
//      所以"跨进快域"的那一拍只有一个快周期（4 ns）预算，不是 20 ns。
//   2. 于是：所有地址算术留在慢域（一整个 20 ns），跨过去的只有直线；
//      快域里只做一次 5 选 1 mux（输入全是快域触发器）。
//      build#14 把 base+ROWW 这类加法放在快域，实测要 5.3 ns ⇒ WNS −1.277、1400 个失败端点。
//   3. 快域→慢域最坏有 16 ns，所以抽头与左窗字都在快域先落一次触发器再交给慢域。
//   4. 插值的 12 个乘法留在慢域（bilin_lerp 两级流水）；快域 4 ns 塞不下，慢域本来就有预算。
//
// LAT = 5 的含义：从 (sx_l,sy_l)/(sx_r,sy_r,fx_r,fy_r) 在慢域有效，到 pix/oob_out/right_out
// 有效，正好 5 个 clk_pix 周期。这个数**由 sim/tb_fb_rd5x.v 用唯一平移量搜索量出来**，
// 不是纸上推的；顶层所有配准抽位都由它导出（pl_video_top.v 的 BUS_LAT/BAR_*_TAP/PIPE_TAP/SPLIT_TAP）。
module fb_rd5x #(
    parameter IMG_W = 512,
    parameter IMG_H = 300
)(
    input  wire        clk,            // clk_pix  50 MHz
    input  wire        clk5x,          // clk_pix5x 250 MHz，同源同相
    input  wire        rst_n,

    // 帧缓存写侧直通（AXI 拷贝 / FILL 都从这里进）
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,
    input  wire [63:0] wr_data,

    // 慢域输入（与 V7.7 的 sx_fb/sy_fb 处在同一级流水位置）
    input  wire [11:0] sx_l, sy_l,
    input  wire [11:0] sx_r, sy_r,
    input  wire [7:0]  fx_r, fy_r,
    input  wire        bilin_en,       // 0 ⇒ 小数钉 0，同一条通路原样退化成最近邻
    input  wire        sel_right,      // 本拍请求属于右窗
    input  wire        oob_l, oob_r,

    // 慢域输出：LAT 拍之后
    output wire [15:0] pix,
    output wire        oob_out,
    output wire        right_out
);
    localparam [16:0] ROW_WORDS = IMG_W / 4;      // 一行的字数（IMG_W 是 4 的倍数）

    // ---------------------------------------------------------------- 慢域地址级
    // 这里就是"纪律 2"的落点：四个抽头字号 + 左窗字号全部在本域算完（20 ns 预算），
    // 跨进快域的只是触发器输出直线。
    wire [18:0] pxl_r = sy_r * IMG_W + sx_r;
    wire [18:0] pxl_l = sy_l * IMG_W + sx_l;
    wire [16:0] wrd_r = pxl_r[18:2];
    wire [16:0] wrd_l = pxl_l[18:2];

    // 抽头越界保护：最后一列/行的 +1 抽头落在图外 ⇒ 把小数钉成 0，
    // 让 bilin_lerp 在 fx=0/fy=0 时恒等于 p00（这条性质由 tb_bilin_lerp 判据 2 保证）。
    // 图外的字地址本身不会读出 X：frame_buffer_w64 对读地址做了掩码夹取（见其注释）。
    wire [7:0] fx_use = (!bilin_en || sx_r >= IMG_W-1) ? 8'd0 : fx_r;
    wire [7:0] fy_use = (!bilin_en || sy_r >= IMG_H-1) ? 8'd0 : fy_r;
    wire       oob_in = sel_right ? oob_r : oob_l;

    reg [16:0] word_q, wordp1_q, row_q, rowp1_q, aux_word_q;
    reg [1:0]  lane_q, lane_l_q;
    reg [7:0]  fx_q, fy_q;
    reg [4:0]  sel_chain;                          // 侧带：LAT 拍移位
    reg [4:0]  oob_chain;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            word_q <= 17'd0; wordp1_q <= 17'd0; row_q <= 17'd0; rowp1_q <= 17'd0;
            aux_word_q <= 17'd0;
            lane_q <= 2'd0; lane_l_q <= 2'd0;
            fx_q <= 8'd0; fy_q <= 8'd0;
            sel_chain <= 5'b11111;                 // 复位期当"左窗"，输出被 oob 夹成黑
            oob_chain <= 5'b00000;
        end else begin
            word_q    <= wrd_r;
            wordp1_q  <= wrd_r + 17'd1;
            row_q     <= wrd_r + ROW_WORDS;
            rowp1_q   <= wrd_r + ROW_WORDS + 17'd1;
            aux_word_q<= wrd_l;
            lane_q    <= pxl_r[1:0];
            lane_l_q  <= pxl_l[1:0];
            fx_q      <= fx_use;
            fy_q      <= fy_use;
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
        .word(word_q), .word_p1(wordp1_q), .word_row(row_q), .word_row_p1(rowp1_q),
        .lane(lane_q), .fx(fx_q), .fy(fy_q),
        .aux_word(aux_word_q), .aux_lane(lane_l_q),
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
    // 抽头：快域在 s2..s4 内稳定，这里第一个 clk 沿收
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

    // 左窗：aux_q/aux_lane_q 是快域触发器，车道 mux 在慢域做（这里预算宽）
    reg [63:0] lw_q;
    reg [1:0]  ll_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin lw_q <= 64'd0; ll_q <= 2'd0; end
        else begin lw_q <= aux_q; ll_q <= aux_lane_q; end
    end
    // 左路本来就比右路快 2 拍（它只要一次读，右路要 4 次读 + 2 级插值），这里补齐 ——
    // 两条路必须同拍，否则切换窗口的瞬间画面会左右错开。
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

    assign pix       = sel_chain[4] ? pix_r    : left_p2;
    assign oob_out   = oob_chain[4];
    assign right_out = sel_chain[4];
endmodule
