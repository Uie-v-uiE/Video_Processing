`timescale 1ns/1ps
// fb_bilin：显示侧唯一的帧缓存读口，做双线性插值。
// 输入每拍的 sx/sy + Q8 小数 fx/fy 请求流，输出 16bit 像素 pix 和同级的 oob_out。
// 每个源像素用满它天然的 4 个 50 MHz 拍（2 显示列 × 2 显示行），一个读口每拍一次读，全程不进快域。
// 延迟：地址寄存 1 拍 + BRAM 1 拍 ⇒ 请求到数据 2 拍；结果缓冲使内容整体晚 1 对显示行（= 2 显示行）。
// 时钟域：clk_pix 50 MHz 单域（wr_clk 只是帧缓存的写侧直通）。
module fb_bilin #(
    parameter IMG_W = 512,
    parameter IMG_H = 300
)(
    input  wire        clk,            // clk_pix 50 MHz：读口挂在这里，没有第二个时钟域
    input  wire        rst_n,

    // 帧缓存写侧直通（AXI 拷贝 / FILL 都从这里进）
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,        // 64bit 字下标
    input  wire [63:0] wr_data,

    // 慢域请求流：一对显示列里两拍同值、一对显示行里两拍同值（都由 x>>1 / y>>1 而来）
    input  wire [11:0] sx, sy,
    input  wire [8:0]  jd,             // **显示**列对号 = x[9:1]：暂存/结果缓冲用它索引，见下面那条 ⚠
    input  wire [7:0]  fx, fy,         // Q8 小数（zoom_mapper 的 frac_x / frac_y）
    input  wire        bilin_en,       // 0 ⇒ 逐位等于最近邻
    input  wire        col0,           // ~x[0]
    input  wire        row0,           // ~y[0]
    input  wire        pair_odd,       //  y[1]：乒乓的半号（写用当对、读用上一对）
    input  wire        req_vld,        //  与 sx/sy 同拍的 de：消隐期不许写任何 RAM（否则脏一个格子）
    input  wire        oob_in,

    output wire [15:0] pix,
    output wire        oob_out
);
    localparam [16:0] ROW_WORDS = IMG_W / 4;   // 一行几个 64bit 字（IMG_W 是 4 的倍数）

    // 地址级（全在慢域）
    // 槽位：`col0 = ~x[0]`、`row0 = ~y[0]` 分别是一对显示列 / 一对显示行的**第一**拍 ⇒
    //   (row0,col0) = (1,1)→发 A ｜ (1,0)→发 A+1 ｜ (0,1)→发 B ｜ (0,0)→发 B+1（一个读口、每拍一次）。
    // `frame_buffer_w64` 读延迟 1 拍（内部那级 BRAM 输出寄存器）+ 这里地址先打一拍 ⇒ 请求到数据 **2 拍**
    //   ⇒ 顶层 `MIX_D` 那串 `3 + 1 + 1 + LATENCY` 的两个 `1` 就是 `addr_q` 与 BRAM，账一个字不改。
    // IMG_W 是 2 的幂 ⇒ `sy * IMG_W` 综合成连线；是 4 的倍数 ⇒ ROW_WORDS = IMG_W/4 整除。
    wire [18:0] pxl  = sy * IMG_W + sx;
    wire [16:0] w_a  = pxl[18:2];
    wire [1:0]  lane = pxl[1:0];
    wire [16:0] w_b  = w_a + ROW_WORDS;
    // 末列/末行的 +1 抽头落在图外 ⇒ 两件事一起做：① 小数钉 0（lerp 恒等于 p00/p01）；
    //   ② 抽头**折回图内**（下面 kx/ky 那两条 mux）。越界由顶层的 `oob` 回黑：同一个像素、同一拍。
    // `bilin_en=0` 走同一道钉子 ⇒ 本模块逐位等于最近邻，板上 on/off 来回切不需要重新构建。
    // ⚠ 只做 ① 不够：末行那次 `w_b = w_a + ROW_WORDS` 会读到帧缓存的**填充区** —— 硬件里是 BRAM 上电的 0、
    //   xsim 里是 X，而 X×0=X ⇒ 整行被污染。折回后对填充区零依赖。
    wire [7:0]  fx_use = (!bilin_en || sx >= IMG_W-1) ? 8'd0 : fx;
    wire [7:0]  fy_use = (!bilin_en || sy >= IMG_H-1) ? 8'd0 : fy;
    wire        kx_use = !bilin_en || sx >= IMG_W-1;   // 横向抽头折回
    wire        ky_use = !bilin_en || sy >= IMG_H-1;   // 纵向抽头折回
    // 先选行（A/B）再选列（+1）：两个 17bit 加器串成一级 mux 之后，而不是四个候选字。
    wire [16:0] addr_nxt = (row0 ? w_a : w_b) + (col0 ? 17'd0 : 17'd1);

    reg [16:0] addr_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) addr_q <= 17'd0;
        else        addr_q <= addr_nxt;
    end

    wire [63:0] fb_word;
    frame_buffer_w64 #(.W(IMG_W), .H(IMG_H)) u_fb (
        .wr_clk(wr_clk), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_clk(clk), .rd_addr({addr_q, 2'b00}), .rd_data(), .rd_data64(fb_word)
    );

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

    // 请求属性跟着数据走（数据 = 请求 + 2）
    // 四级：d1/d2 与"当拍到达的数据"配对，d3/d4 与"lerp 输出那一拍"配对。
    // 不许给标签另开一条延迟链：标签与内容不同级就是错。
    reg [1:0]  lane_d1, lane_d2;
    reg [7:0]  fx_d1,  fx_d2,  fy_d1,  fy_d2;
    reg [8:0]  j_d1,   j_d2,  j_d3,   j_d4;
    reg        r0_d1,  r0_d2,  c0_d1,  c0_d2;
    reg        h_d1,   h_d2,   h_d3,   h_d4;      // pair_odd
    reg        oob_d1, oob_d2, oob_d3, oob_d4;
    reg        v_d1,   v_d2;                      // req_vld
    reg        kx_d1,  kx_d2, ky_d1, ky_d2;       // 抽头折回位（与 fx_d2/fy_d2 同级）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lane_d1 <= 0; lane_d2 <= 0;
            fx_d1 <= 0; fx_d2 <= 0; fy_d1 <= 0; fy_d2 <= 0;
            j_d1 <= 0; j_d2 <= 0; j_d3 <= 0; j_d4 <= 0;
            r0_d1 <= 1'b1; r0_d2 <= 1'b1; c0_d1 <= 1'b1; c0_d2 <= 1'b1;
            h_d1 <= 1'b0; h_d2 <= 1'b0; h_d3 <= 1'b0; h_d4 <= 1'b0;
            oob_d1 <= 1'b1; oob_d2 <= 1'b1; oob_d3 <= 1'b1; oob_d4 <= 1'b1;
            v_d1 <= 1'b0; v_d2 <= 1'b0;
            kx_d1 <= 1'b0; kx_d2 <= 1'b0; ky_d1 <= 1'b0; ky_d2 <= 1'b0;
        end else begin
            lane_d1 <= lane;    lane_d2 <= lane_d1;
            fx_d1   <= fx_use;  fx_d2   <= fx_d1;
            fy_d1   <= fy_use;  fy_d2   <= fy_d1;
            j_d1    <= jd;    j_d2    <= j_d1;   j_d3 <= j_d2; j_d4 <= j_d3;
            r0_d1   <= row0;    r0_d2   <= r0_d1;
            c0_d1   <= col0;    c0_d2   <= c0_d1;
            h_d1    <= pair_odd; h_d2   <= h_d1; h_d3 <= h_d2; h_d4 <= h_d3;
            oob_d1  <= oob_in;  oob_d2  <= oob_d1; oob_d3 <= oob_d2; oob_d4 <= oob_d3;
            v_d1    <= req_vld; v_d2    <= v_d1;
            kx_d1   <= kx_use;  kx_d2   <= kx_d1;
            ky_d1   <= ky_use;  ky_d2   <= ky_d1;
        end
    end

    // 四个相位：本拍到达的数据是 A / A+1 / B / B+1 中的哪一个（用请求相位判，已含那 2 拍）
    wire ph_a0 = v_d2 &&  r0_d2 &&  c0_d2;
    wire ph_a1 = v_d2 &&  r0_d2 && !c0_d2;
    wire ph_b0 = v_d2 && !r0_d2 &&  c0_d2;
    wire ph_b1 = v_d2 && !r0_d2 && !c0_d2;

    reg [63:0] a_hold, b_hold;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin a_hold <= 64'd0; b_hold <= 64'd0; end
        else begin
            if (ph_a0) a_hold <= fb_word;
            if (ph_b0) b_hold <= fb_word;
        end
    end

    // y0 行凑齐 ⇒ 写抽头暂存（512×32，1W1R）
    // lane 在同一对显示列里恒定（sx 不变）⇒ 两个半字都用当拍的 lane_d2 选，不另存副本。
    // ⚠ 索引必须是 `jd` = **显示**列对号 x[9:1]，不能是源列 `sx`：旋转时一条源图线在 x 方向会
    //   **停滞甚至倒退** ⇒ 同一个 sx 在这一行里被**另一个源行**重写 ⇒ y1 拍读到的是别的像素的 A 行抽头。
    //   这个错与 `bilin_en` 无关（off 时 p00 也来自这块 RAM）。
    wire [15:0] p00_y0 = pick(a_hold, lane_d2);
    wire [15:0] p10_y0 = (lane_d2 == 2'd3) ? fb_word[15:0]
                                           : pick(a_hold, lane_d2 + 2'd1);
    (* ram_style = "block" *) reg [31:0] tap_hold [0:IMG_W-1];
    reg [31:0] tap_r;
    wire [15:0] p10_y0c = kx_d2 ? p00_y0 : p10_y0;     // 末列：右邻折回 = p00（见上面那条 ⚠）
    // ⚠ 这块 RAM 的读写必须放在**只关心时钟**的 always 里（不带 async reset）：
    //   写口带异步复位综合不出 BRAM —— Vivado 报 `ERROR: [Synth 8-91] ambiguous clock in event control`
    //   并整个模块作废，xsim 完全看不出来。少掉的是 `tap_r` 这个输出寄存器的复位：
    //   它是数据不是控制，复位后第一拍本来就无意义。
    always @(posedge clk) begin
        // 读地址 `j_d1`：读出的正是"两拍前那个请求"的 j（= 当拍的 j_d2），与 B+1 同拍到位。
        // 写只发生在 y0 行、读只用在 y0+1 行 ⇒ 同一拍同地址不会读写相撞。
        tap_r <= tap_hold[j_d1];
        if (ph_a1) tap_hold[j_d2] <= {p10_y0c, p00_y0};
    end

    // y0+1 行凑齐 ⇒ 这一拍喂 lerp
    wire [15:0] p01_raw  = pick(b_hold, lane_d2);
    wire [15:0] p11_raw  = (lane_d2 == 2'd3) ? fb_word[15:0]
                                             : pick(b_hold, lane_d2 + 2'd1);
    // 末行/末列折回（与 lerp 的输入同拍，用 kx_d2/ky_d2）：越界方向取图内那一格 ⇒ 填充区不参与。
    wire [15:0] p01      = ky_d2 ? tap_r[15:0]  : p01_raw;
    wire [15:0] p11      = ky_d2 ? tap_r[31:16] : (kx_d2 ? p01_raw : p11_raw);
    wire        assemble = ph_b1;
    // lerp 自己声明两级 ⇒ 输出在输入那拍之后的第 2 拍。写拍与"请求属性"必须一起延到那一拍。
    reg asm_d1, asm_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin asm_d1 <= 1'b0; asm_d2 <= 1'b0; end
        else begin asm_d1 <= assemble; asm_d2 <= asm_d1; end
    end

    wire [15:0] lerp_pix;
    bilin_lerp u_lerp (
        .clk(clk), .rst_n(rst_n),
        .p00(tap_r[15:0]), .p10(tap_r[31:16]), .p01(p01), .p11(p11),
        .fx(fx_d2), .fy(fy_d2), .pix(lerp_pix), .vld()
    );

    // 结果缓冲（1024×17 乒乓）
    //   半号 = pair_odd = y[1]：写"本对"、读"上一对" ⇒ 同一个 j 永远落在不同半 ⇒ 单口够用。
    //   ⚠ 这里不许再开第二个逻辑读口：实测 BRAM 从 80 块顶到 160 块 RAMB36，全片才 140。
    //   1024×17 = 一块 RAMB36（36bit 宽模式），深度必须留成 2 的幂，非 2 幂会被推断向上填充。
    // ⇒ 内容整体晚 **1 对显示行 = 2 个显示行**（一行 1344 拍、一帧 625 行 @50 MHz = 53.76 µs）⇒ 顶层喂给
    //   mapper 的行号必须再加这 2 行（`y_right_adv` 的 `BILIN_ROWS`）；`raw_line_delay` 的 LINES 一个都不动。
    (* ram_style = "block" *) reg [16:0] res [0:2*IMG_W-1];
    reg [16:0] res_q;
    // 同上：这块 RAM 也不能带异步复位（`Synth 8-91`）。`res_q` 复位后前两拍是 X ⇒ 判据只能从那之后开始数。
    always @(posedge clk) begin
        if (asm_d2) res[{h_d4, j_d4}] <= {oob_d4, lerp_pix};
        // 读地址 = 请求那一拍的 {半号, j} 各延 1 拍（h_d1/j_d1 在 c+1 拍正好等于 c 拍的请求）
        // ⇒ 数据在 c+2 拍到 ⇒ 与"地址打一拍 + BRAM 一拍"同深，也与写侧延 4 拍的标签同深度。
        res_q <= res[{~h_d1, j_d1}];
    end

    // LAT（请求 → `pix` 几拍）**本模块不声明**：由 `sim/tb_fb_bilinear.v` 用唯一平移量搜索量出来并钉住；
    //   乒乓极性同样由它钉 —— 那一处错就是"每行前半新后半旧"的撕裂／整对错位，不许靠改字面量试到绿。
    assign pix     = res_q[15:0];
    // oob 与像素同一次写入、同一拍读出 ⇒ 天生同级。
    assign oob_out = res_q[16];
endmodule
