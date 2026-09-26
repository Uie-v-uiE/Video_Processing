`timescale 1ns/1ps
// fb_bilin —— 显示侧唯一的帧缓存读口：**双线性，每个源像素用满它天然的 4 个 50 MHz 拍，全程不进快域**。
//
// 为什么这条路成立、而 2026-09-23 那三次红不该再照原样走（完整算式与被排除的五条岔路在
// report/ISSUES.md #76 段二，这里只留结论）：
//   r59b 之后整屏一个视口：`cx = x>>1`、`cy = (y+OFF)>>1` ⇒ 同一个源像素要显示 **2 列 × 2 行 = 4 个慢拍**，
//   而双线性需要的正好是 4 个字：A=word(px,py)、A+1、B=word(px,py+1)、B+1。
//   旧形状是"每像素周期 5 次读 ⇒ 必须 250 MHz ⇒ 5 选 1 地址 mux ⇒ mux→RAMB36 地址脚 4 ns 预算里
//   布线占 3.255 ns"（build#14 −1.277 / #15 −0.485 / #16 −0.327）。这里读口挂在 clk_pix(50 MHz)：
//   一个 20 ns 的预算里做"行偏移 + 末列 +1 + 4 选 1"，**快域一次都不出现**。
//   `build/micro_rd/` 的三个 MODE 从反面印证：就算把地址前再插一级寄存让那条路不再违例，
//   250 MHz 下 RAMB36 自己的 clk→out 已吃掉 4 ns 里的 2.2 ns ⇒ 整条路贴着器件下限。
//
// ------------------------------------------------------------------------ 槽位与延迟
// `col0 = ~x[0]`、`row0 = ~y[0]`（一对显示列 / 一对显示行的**第一**拍）：
//   (row0,col0)=(1,1)→发 A ｜ (1,0)→发 A+1 ｜ (0,1)→发 B ｜ (0,0)→发 B+1
//   `frame_buffer_w64` 的读延迟是 **1 拍**（它内部那级 BRAM 输出寄存器），这里地址先打一拍
//   ⇒ 从请求到数据 **2 拍**，与顶层今天 `rd_addr_q` + BRAM 的形状逐位同深 ⇒ **`MIX_D` 的账一个字不改**
//   （顶层注释里那串 `3 + 1 + 1 + LATENCY` 的两个 `1` 分别是这里的 `addr_q` 与 BRAM）。
//   同一份延迟也用在结果侧：请求 → `j_d1`（1 拍）→ 结果 RAM（1 拍）= 2 拍 ⇒ 输出 `pix` 与
//   顶层 `x_d[MIX_D]`、`oob_fb_d1` 原来站位一致，替换读口不动混色级的对齐。
//
// 四元组怎样凑齐（关键：**读口只有一个，且每拍一次**）：
//   y0 行的两拍凑出 {p00,p10} ⇒ 写进**抽头暂存**（512×32，按 `jd` = **显示**列对号 x[9:1] 索引；
//     一个显示列对一份，下一次重写是 2 个显示行之后 ⇒ 读地址用 `j_d1`、读写永不撞同一拍）；
//     ⚠ **不能按源列 `sx` 索引**（r63 原来就是这么写的，2026-09-26 用户报"旋转时整屏噪点"才暴露）：
//     那样默认"源列沿显示行走至少单调 +1"。旋转时一条源图线在 x 方向会**停滞甚至倒退**，
//     同一个 sx 会在这一行里被**另一个源行**重写 ⇒ y1 拍读到的是别的像素的 A 行抽头 ⇒ 满屏噪点。
//     而且这个错与 `bilin_en` 无关：`bilin off` 时 p00 也来自这块暂存 RAM。
//     显示列对号才是天生唯一的：一对显示列一个号，一行 512 个，与几何怎么走无关。
//     台架凭据：`tb_v101` 的**第 D 段**（段 D = 旋转样子的映射：源列每 4 个显示列对重复一次、源行沿着一行走），
//     旧索引下它把 L3/L4/L5 三条一起判红，新索引下九条全绿；L8 现在要求段 D 真的被量到（>4000 样本）。
//     老判据全是轴对齐的 ⇒ 这个错在 r63 的两份台架里都量不出来（"判据不覆盖 = 没有判据"，#68 同族）。
//   y0+1 行的两拍凑出 {p01,p11}，同时 `tap_r` 已经把同一格的 {p00,p10} 取回来 ⇒ 这一拍喂 `bilin_lerp`；
//   lerp 是两级流水 ⇒ 结果在请求后第 4 拍到达，写进**结果缓冲**（1024×17 = 两半 × 512，
//     半号 = `pair_odd` = y[1]），由**下一对显示行**读出 ⇒
//   **内容整体晚 1 对显示行 = 2 个显示行**（一行 1344 拍、一帧 625 行 @50 MHz ⇒ 53.76 µs）。
//
// 顶层唯一必须跟着改的一处（#76 段二第 2 条）：喂给 mapper 的行号再加 2 个显示行
//   （`y_right_adv = y + pipe_off_rows` → `y + 2 + pipe_off_rows`），这样"显示在第 Y 行的内容"
//   与今天逐位同源；`raw_line_delay` 的 LINES 一个都不动（两个抽头一起吃同一份晚 2 行，
//   它们的相对关系不变）。列对齐也不受影响：晚的是**整行**。
//   代价：帧首多 2 行"上一帧尾巴"（与今天 `OFF_LINES` 环热身同一类，只是更长两行）——
//   这条不是注释，是 tb_v98 的 C1d 逐行数出来的（`行环热身跳过` 那一项）。
//
// bilin_en=0 必须**逐位等于今天的最近邻**：fx/fy 钉 0 ⇒ `bilin_lerp` 恒等于 p00（tb_bilin_lerp 判据 1），
//   而 p00 = pick(A,lane) 就是今天 `fb_rd` 那一格 ⇒ 板上 `bilin on/off` 来回切不需要重新构建。
//   （今天越界由 RAM 的 `blank` 回黑，这里交给顶层的 `oob` 回黑：同一个像素、同一拍，见 `pix_raw`。）
//
// LAT（从请求到 `pix` 几拍）**本模块不声明**：由 `sim/tb_v101_fb_bilin.v` 用唯一平移量搜索
//   量出来并钉住（#54/#68 的老规矩）。乒乓极性也由同一份台架钉：它错就是"每行前半新后半旧"的
//   撕裂／整对错位，量不出来就不许靠改字面量试到绿。
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

    // ------------------------------------------------------------------ 地址级（全在慢域）
    // IMG_W 是 2 的幂 ⇒ 这个乘法综合成连线，不落 DSP（换成非 2 幂要先看 synth 报告再提）。
    wire [18:0] pxl  = sy * IMG_W + sx;
    wire [16:0] w_a  = pxl[18:2];
    wire [1:0]  lane = pxl[1:0];
    wire [16:0] w_b  = w_a + ROW_WORDS;
    // 末列/末行的 +1 抽头落在图外 ⇒ 两件事一起做：① 小数钉 0（lerp 恒等于 p00/p01，性质由
    //   tb_bilin_lerp 判据 1 钉）；② 抽头**折回图内**（下面 kx/ky 那两条 mux）。
    // ⚠ 只做 ① 不够：末行那次 `w_b = w_a + ROW_WORDS` 会读到帧缓存的**填充区** —— 硬件里是 BRAM
    //   上电的 0，xsim 里是 X，而 X×0=X ⇒ 整行被污染（r63 第一版 top 台架的 C1e 就是这么判红的）。
    //   折回之后输出对"填充区是什么"零依赖：硬件不赌上电值，仿真也不会传染 X。
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

    // ------------------------------------------------- 请求属性跟着数据走（数据 = 请求 + 2）
    // 四级：d1/d2 与"当拍到达的数据"配对，d3/d4 与"lerp 输出那一拍"配对。
    // 不许给标签另开一条延迟链（#68 那一族全是"标签与内容不同级"）。
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

    // ------------------------------------------------ y0 行凑齐 ⇒ 写抽头暂存（512×32，1W1R）
    // lane 在同一对显示列里恒定（sx 不变）⇒ 两个半字都用当拍的 lane_d2 选，不另存副本。
    wire [15:0] p00_y0 = pick(a_hold, lane_d2);
    wire [15:0] p10_y0 = (lane_d2 == 2'd3) ? fb_word[15:0]
                                           : pick(a_hold, lane_d2 + 2'd1);
    (* ram_style = "block" *) reg [31:0] tap_hold [0:IMG_W-1];
    reg [31:0] tap_r;
    wire [15:0] p10_y0c = kx_d2 ? p00_y0 : p10_y0;     // 末列：右邻折回 = p00（见上面那条 ⚠）
    // ⚠ 这块 RAM 的读写必须放在**只关心时钟**的 always 里（不带 async reset）：
    //   写口带异步复位综合不出 BRAM —— Vivado 报 `ERROR: [Synth 8-91] ambiguous clock in event control`
    //   并整个模块作废（r63 第一次构建就是这么死的，xsim 完全看不出来）。参考件 `frame_buffer_w64`
    //   用的就是同一个形状：`always @(posedge wr_clk)` 写、`always @(posedge rd_clk)` 读。
    //   少掉的是 `tap_r` 这个输出寄存器的复位：它是数据不是控制，复位后第一拍本来就无意义。
    always @(posedge clk) begin
        // 读地址 `j_d1`：读出的正是"两拍前那个请求"的 j（= 当拍的 j_d2），与 B+1 同拍到位。
        // 写只发生在 y0 行、读只用在 y0+1 行 ⇒ 同一拍同地址不会读写相撞。
        tap_r <= tap_hold[j_d1];
        if (ph_a1) tap_hold[j_d2] <= {p10_y0c, p00_y0};
    end

    // --------------------------------------------- y0+1 行凑齐 ⇒ 这一拍喂 lerp
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

    // ---------------------------------------------------------------- 结果缓冲（1024×17 乒乓）
    //   半号 = pair_odd = y[1]：写"本对"、读"上一对" ⇒ 同一个 j 永远落在不同半 ⇒ 单口够用。
    //   （当年试过开第二个逻辑读口：帧缓存 80 → 160 块 RAMB36，全片才 140 —— 撞过的墙。）
    //   1024×17 = 一块 RAMB36（36bit 宽模式）。深度必须留成 2 的幂：非 2 幂会被推断向上填充，
    //   见 frame_buffer_w64 文件头那个 128 块 vs 80 块的对照实验。
    (* ram_style = "block" *) reg [16:0] res [0:2*IMG_W-1];
    reg [16:0] res_q;
    // 同上：这块 RAM 也不能带异步复位（`Synth 8-91`）。`res_q` 复位后前两拍是 X，
    //   台架的 L7「无 X」从 `LAG` 之后才开始数，正是把这段热身挡在判据之外（见 tb_v101 头）。
    always @(posedge clk) begin
        if (asm_d2) res[{h_d4, j_d4}] <= {oob_d4, lerp_pix};
        // 读地址 = 请求那一拍的 {半号, j} 各延 1 拍（h_d1/j_d1 在 c+1 拍正好等于 c 拍的请求）
        // ⇒ 数据在 c+2 拍到 ⇒ 与今天 `rd_addr_q`+BRAM 同深，也与写侧延 4 拍的标签同深度。
        res_q <= res[{~h_d1, j_d1}];
    end

    assign pix     = res_q[15:0];
    // oob 与像素同一次写入、同一拍读出 ⇒ 天生同级（#68 那一族的病灶就在这）。
    assign oob_out = res_q[16];
endmodule
