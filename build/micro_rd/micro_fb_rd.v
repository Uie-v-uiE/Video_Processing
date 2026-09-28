`timescale 1ns/1ps
// micro_fb_rd —— **探针，不是交付件**：只回答一个问题 ——
//   "帧缓存读口在 250 MHz 上，地址总线到 80 块 RAMB36 的这条路，到底还差多少？"
//
// 为什么单独做这个探针（2026-09-26 凌晨）：
//   双线性读口调度在旧几何下红过三次（build#14 −1.277、#15 −0.485、#16 换实现策略仍 −0.327），
//   当时的读出来的一句话是"3.844 ns 里布线占 3.255 ns（84.7%）、逻辑只有 2 级 LUT ⇒
//   是布局距离 + 80 个 tile 的高扇出，不是逻辑深度"（docs/log/OVERNIGHT_LOG.md R19 / tag v7.8-bilinear-wip）。
//   那是**布线**问题 ⇒ `build/tcl/ooc_newmods.tcl` 那种"综合级 OOC 时序"量不出来（它自己就声明
//   "这里的数字不是门禁"），只有真实 place+route 才算数。
//   而全流程一次构建 30+ 分钟，拿它试三个方案是浪费 ⇒ 把这**一条路径**单独 place+route。
//
// 三个 MODE 是同一份骨架的唯一区别，用来做**对照**：
//   MODE=0  旧形状：5 选 1，其中左窗那一路是**慢域触发器直接进 mux**（每个快沿都可能换）
//   MODE=1  新形状：4 选 1，输入全是快域触发器（r59b 之后只剩一条地址流，左窗那一路不需要读口）
//   MODE=2  新形状 + **BRAM 地址前再加一级寄存器**（就是把 2 级 LUT 从这条路里拿出来）
// ⚠ 这个骨架**没有**真设计里的其余逻辑（效果链、OSD、仲裁），所以拥挤度比真实设计宽松 ⇒
//   绝对数字会比全流程乐观。**结论只取三者之差**：如果 MODE=0 在探针里就已经红，
//   那它和真实构建是同一个方向；如果三个全绿，那探针只证明"新形状不是结构死路"，
//   仍然要用一次真构建收尾。判据写在 build/micro_rd/README.md。
module micro_fb_rd #(
    parameter integer MODE = 1,
    parameter integer IMG_W = 512,
    parameter integer IMG_H = 300
)(
    input  wire        sys_clk,
    input  wire        rst_n,
    output wire [31:0] acc,          // 把所有抽头都吃掉，防止综合把通路优化掉
    output wire [15:0] rd_now
);
    wire clk_pix, clk5x, clk_200m_unused, locked;
    clk_gen u_clk (
        .clk_in(sys_clk), .rst_n(rst_n),
        .clk_pix(clk_pix), .clk_pix5x(clk5x), .clk_200m(clk_200m_unused), .locked(locked)
    );
    wire rst_pix_n = rst_n & locked;

    // -------------------------------------------------- 慢域：请求节拍与四个抽头字号
    reg [15:0] lfsr = 16'hBEEF;
    always @(posedge clk_pix or negedge rst_pix_n)
        if (!rst_pix_n) lfsr <= 16'hBEEF;
        else            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[12] ^ lfsr[5] ^ lfsr[4]};

    reg [8:0] rowc = 9'd0;
    always @(posedge clk_pix or negedge rst_pix_n)
        if (!rst_pix_n) rowc <= 9'd0; else rowc <= rowc + 9'd1;

    wire [8:0]  sx    = lfsr[8:0];                                   // 0..511，正好一行的宽
    wire [8:0]  sy    = (rowc >= IMG_H - 1) ? (IMG_H - 2) : rowc;    // 留一行给 y+1
    wire [18:0] pxl   = {sy[8:0], sx[8:0]};                           // = sy*512+sx（2 的幂 ⇒ 拼接）
    wire [16:0] w     = pxl[18:2];
    wire [1:0]  lane  = pxl[1:0];
    wire [16:0] w_row = w + (IMG_W / 4);                              // 下一行同列

    reg [16:0] a_q, a1_q, b_q, b1_q;
    reg [1:0]  lane_q;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            a_q <= 0; a1_q <= 0; b_q <= 0; b1_q <= 0; lane_q <= 0;
        end else begin
            a_q  <= w;        a1_q <= w + 17'd1;
            b_q  <= w_row;    b1_q <= w_row + 17'd1;
            lane_q <= lane;
        end
    end

    // 左窗（最近邻）字号：MODE=0 复刻"慢域直线直接进 5 选 1"那个形状
    wire [16:0] aux_word_slow = pxl[18:2];

    // -------------------------------------------------- 快域：槽位轮盘与地址 mux
    reg [2:0] slot = 3'd0;
    always @(posedge clk5x or negedge rst_pix_n)
        if (!rst_pix_n) slot <= 3'd0;
        else            slot <= (slot == 3'd4) ? 3'd0 : slot + 3'd1;

    wire s0 = (slot == 3'd0), s1 = (slot == 3'd1), s2 = (slot == 3'd2),
         s3 = (slot == 3'd3), s4 = (slot == 3'd4);

    reg [16:0] aux_ff;                                               // 快域里的左窗地址（新形状不用）
    always @(posedge clk5x or negedge rst_pix_n)
        if (!rst_pix_n) aux_ff <= 0; else if (s4) aux_ff <= aux_word_slow;

    wire [16:0] mux_out = (MODE == 0)
        ? (s1 ? a_q : s2 ? a1_q : s3 ? b_q : s4 ? b1_q : aux_word_slow)   // 老形状：s0 直接吃慢域
        : (s1 ? a_q : s2 ? a1_q : s3 ? b_q : /*s4 与 s0 复用两个抽头位*/ b1_q);

    reg [16:0] addr_reg;                                             // MODE=2：地址前的一级寄存
    always @(posedge clk5x or negedge rst_pix_n)
        if (!rst_pix_n) addr_reg <= 0;
        else if (MODE == 2) addr_reg <= mux_out;

    wire [16:0] fb_addr_word = (MODE == 2) ? addr_reg : mux_out;

    // -------------------------------------------------- 帧缓存（80 块 RAMB36 的那个）
    reg  [16:0] wc = 17'd0;
    wire        wr_en   = 1'b1;
    wire [18:0] wr_addr = {wc, 2'b00};
    wire [63:0] wr_data = {lfsr, lfsr, lfsr, lfsr, lfsr[3:0], 13'b0};
    always @(posedge clk_pix or negedge rst_pix_n)
        if (!rst_pix_n) wc <= 0; else wc <= wc + 17'd1;

    wire [63:0] fb_word;
    wire [15:0] fb_pix;
    frame_buffer_w64 #(.W(IMG_W), .H(IMG_H)) u_fb (
        .wr_clk(clk_pix), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_clk(clk5x), .rd_addr({fb_addr_word, 2'b00}), .rd_data(fb_pix), .rd_data64(fb_word)
    );

    // -------------------------------------------------- 抽头采集（节拍对不对不在探针的账里）
    reg [63:0] w_a, w_a1, w_b, w_b1;
    always @(posedge clk5x or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            w_a <= 0; w_a1 <= 0; w_b <= 0; w_b1 <= 0;
        end else begin
            if (s2) w_a  <= fb_word;
            if (s3) w_a1 <= fb_word;
            if (s4) w_b  <= fb_word;
            if (s0) w_b1 <= fb_word;
        end
    end

    // ⚠ 这里**不能放加法器**：第一版探针写的是 `acc_q <= acc_q + 五个抽头`，
    //   于是最坏路径变成"BRAM 输出 → 32 位加法树"（10 级、6.2 ns，m0 −1.986 / m1 −2.303 全是它），
    //   把真正要问的"mux → 地址脚"整条盖住 —— 这是**假红**，而且是探针自己造的。
    //   换成异或折叠：既让四个抽头与 fb_pix 都不能被优化掉，逻辑深度只有 3 级。
    wire [15:0] fold = (w_a[15:0] ^ w_a1[31:16]) ^ (w_b[47:32] ^ w_b1[63:48]) ^ fb_pix;
    reg  [31:0] acc_q = 32'd0;
    always @(posedge clk5x or negedge rst_pix_n) begin
        if (!rst_pix_n) acc_q <= 0;
        else            acc_q <= {^fold, acc_q[31:1]};
    end
    assign acc    = acc_q;
    assign rd_now = fb_pix;
endmodule
