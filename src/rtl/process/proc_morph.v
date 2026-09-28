`timescale 1ns/1ps
// 级 5：形态学 —— 3×3 腐蚀 / 膨胀。放在阈值之后是因为它的定义就是"邻域内全 1 才 1 / 有 1 就 1"，本来就是
// 对面具图的操作（放在灰度图上做 min/max 也能写，但那不是形态学，是另一种局部对比度）。
// **结构逐条照 proc_box_blur 对齐**：同样的两条行缓存读法、同样的三拍 de 链（de_in→d1→d2→de_out）、同样的
// "中心抽头 p11 做旁路"。理由不是省事：窗口级各自挑一种 de/数据对齐方式，混在一条链里就会在切换效果的瞬间
// 错一行；blur/sharpen/sobel 用的是这个约定，新加的也用它。掩码只存 1 bit/像素（亮度判定在输入处做一次）
// ⇒ 两条掩码行缓存 = 512 bit × 2；另加**一条** 16 bit 行缓存，只为旁路能还原原色（中心抽头只要上一行）。
module proc_morph #(
    parameter H_ACTIVE = 512
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  mode,          // 0/3 旁路  1 腐蚀  2 膨胀
    input  wire [7:0]  threshold,
    input  wire        de_in,
    input  wire [11:0] x_in,
    input  wire [11:0] y_in,
    input  wire [15:0] din,
    output reg         de_out,
    output reg  [15:0] dout
);
    // mode 3 是"开/闭运算"的位置，但那是**两遍**窗口（先腐蚀再膨胀），一遍做不出来，
    // 也不许偷偷当成其中一种 —— 所以显式当旁路，代价写在注释里而不是藏在 mux 里。
    wire by = (mode == 2'd0) || (mode == 2'd3);

    // 与 proc_binary 同一个亮度公式、同一对白/黑 ⇒ 级 4 → 级 5 视觉上只有形状在变
    wire [4:0] r5 = din[15:11];
    wire [5:0] g6 = din[10:5];
    wire [4:0] b5 = din[4:0];
    wire [7:0] r8 = {r5, r5[4:2]};
    wire [7:0] g8 = {g6, g6[5:4]};
    wire [7:0] b8 = {b5, b5[4:2]};
    wire [15:0] y16 = r8 * 8'd77 + g8 * 8'd150 + b8 * 8'd29;
    wire        bin = (y16[15:8] >= threshold);

    // ⚠ 存储器**必须写成 `reg mb0 [0:H_ACTIVE-1]`（每个元素一格），不能写成 `reg [0:H_ACTIVE-1] mb0`
    //   （那是一根 1024 位的**向量**，`mb0[x_in]` 是按位取值）。后者综合器推断不出 RAM，报
    //   `Synth 8-7186 ... using registers` ⇒ 两条掩码行缓存变成 2×H_ACTIVE 个触发器，
    //   而两个异步读口各变成一棵 1024:1 的 LUT 树。r83 之前它就是这个状态（凭据：build/r80_build2.log）。
    (* ram_style = "distributed" *) reg mb0 [0:H_ACTIVE-1];          // 掩码：上上行
    (* ram_style = "distributed" *) reg mb1 [0:H_ACTIVE-1];          // 掩码：上一行
    // `mc1` 的读是**异步**的（组合读出），BRAM 做不到 ⇒ 原来写 `ram_style="block"` 只会被判
    // `Synth 8-6849 infeasible` 然后自己退回 LUTRAM。这里把话说明白，少四条假警告。
    (* ram_style = "distributed" *) reg [15:0] mc1 [0:H_ACTIVE-1];   // 原色：上一行（旁路用）

    always @(posedge clk) begin
        if (de_in) begin
            mb0[x_in] <= mb1[x_in];
            mb1[x_in] <= bin;
            mc1[x_in] <= din;
        end
    end
    // #92 第四笔：读地址钉在末列（行尾多跳那一拍 `x_in` 已在 porch 上，越界读 = 仿真 X / 硬件读到别的列）
    wire [11:0] x_rd = (x_in >= H_ACTIVE[11:0]) ? (H_ACTIVE[11:0] - 12'd1) : x_in;
    wire        b00 = mb0[x_rd];
    wire        b01 = mb1[x_rd];
    wire [15:0] c01 = mc1[x_rd];

    // 命名照 blur：第一维 0/1/2 = 上上/上/当前行，第二维 0/1/2 = 左/中/右
    reg k00, k01, k02, k10, k11, k12, k20, k21, k22;   // 窗口原始掩码（下面按边界复制成 m**）
    reg [15:0] p12, p11;
    reg [15:0] c20, c21, c22;                          // 当前行的原色（#97：陈旧行的中心要用它）
    reg dv_d1, dv_d2;
    // 只在"刚吃掉本行末列"那一跳多走一拍：判据、机理与三版演进全在 proc_box_blur.v 的 #92 第四笔那段
    // （这一版是四个窗口级共用同一套旗标的前提；用 de 断点当行尾会被一拍一像素的激励误触发）。
    reg [11:0] run;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)      run <= 12'd0;
        else if (de_in)  run <= run + 12'd1;
        else            run <= 12'd0;   // de 一断就清：那一拍非阻塞更新的旧值仍看得见，就是本行的宽度（详见 proc_box_blur.v 那五段）
    wire owed     = (run == H_ACTIVE[11:0]);
    wire line_end = owed && dv_d1 && !de_in;
    wire shift_w  = de_in || line_end;

    // ---------------------------------------------------------------- #97：四条圈的旗标（数由 tb_edge_rim 量，推导正本在 proc_box_blur.v）
    // 旧写法是**一根** `border_r` = `(x_in==0)||(x_in==H_ACTIVE-1)||(y_in==0)` 并在行尾补跳那一拍塞 `1'b1`：
    // 那一拍落到的其实是下一行第 0 槽 ⇒ 第 0 列被"旁路成原图"，真正的末列却没人管；加上"中心行 = 输入行 − 1"
    // ⇒ 每帧第一格吃的中心是上一帧的末行 —— 三条合起来就是用户念的"左边与上边那两条带"（这里只换形状）。
    reg [11:0] y_row_d;                    // this display line's y_in, latched at line end
    always @(posedge clk or negedge rst_n)
        if (!rst_n) y_row_d <= 12'h0FFF;
        else if (line_end) y_row_d <= y_in;
    wire row_first = (y_in != y_row_d);    // x2 raster: only the FIRST display row of a
                                           // source row can be missing the row above
    reg [2:0] no_left_r, no_right_r, no_above_r, stale_row_r;
    // ⚠ 复位只写在这**一个**块里（两个驱动源 = Synth 8-6859，bit 里恒 0 而仿真看不出来，#61）。
    always @(posedge clk or negedge rst_n)
    if (!rst_n) begin
        no_left_r <= 3'b0; no_right_r <= 3'b0; no_above_r <= 3'b0; stale_row_r <= 3'b0;
    end else if (shift_w) begin
        no_left_r  [0] <= ~de_in;                                     // 补跳那一拍 = 下一行第 0 槽
        no_right_r [0] <= de_in && (x_in == H_ACTIVE[11:0] - 12'd1);   // #103：坐标抽头对齐到 de 之后，武装位从 -2 改回 -1；拍 k 武装仍落槽位 k+1（正本见 proc_box_blur.v 的 #97 段）
        no_above_r [0] <= de_in && (y_in == 12'd1) && row_first;                    // 中心行 0，上面缺
        stale_row_r[0] <= de_in && (y_in == 12'd0);                    // 中心行 −1：整行都是旧的
        no_left_r  [1] <= no_left_r  [0];  no_left_r  [2] <= no_left_r  [1];
        no_right_r [1] <= no_right_r [0];  no_right_r [2] <= no_right_r [1];
        no_above_r [1] <= no_above_r [0];  no_above_r [2] <= no_above_r [1];
        stale_row_r[1] <= stale_row_r[0];  stale_row_r[2] <= stale_row_r[1];
    end
    wire no_left = no_left_r[2], no_right = no_right_r[2];
    wire no_above = no_above_r[2], stale_row = stale_row_r[2];
    // 缺的邻居复制中心（clamp-to-edge）：腐蚀在左沿不会因为"外面算 0"而被啃掉一圈，
    // 膨胀也不会因为行缓存里是上一帧的尾巴而凭空鼓一圈 —— 这两种都是"条带"。
    wire k00h = no_left ? k01 : k00, k02h = no_right ? k01 : k02;
    wire k10h = no_left ? k11 : k10, k12h = no_right ? k11 : k12;
    wire k20h = no_left ? k21 : k20, k22h = no_right ? k21 : k22;
    wire m00 = stale_row ? k20h : (no_above ? k10h : k00h);
    wire m01 = stale_row ? k21  : (no_above ? k11  : k01 );
    wire m02 = stale_row ? k22h : (no_above ? k12h : k02h);
    wire m10 = stale_row ? k20h : k10h;
    wire m11 = stale_row ? k21  : k11;
    wire m12 = stale_row ? k22h : k12h;
    wire m20 = k20h, m21 = k21, m22 = k22h;

    wire all1 = m00 & m01 & m02 & m10 & m11 & m12 & m20 & m21 & m22;
    wire any1 = m00 | m01 | m02 | m10 | m11 | m12 | m20 | m21 | m22;
    // 边界不再"发中心"（#97）：复制过邻居的 m** 已经是 clamp-to-edge 的窗口，
    // 腐蚀在最外圈啃不掉一圈、膨胀也鼓不出多余的一圈。
    wire res = (mode == 2'd1) ? all1 : any1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            k00<=0; k01<=0; k02<=0; k10<=0; k11<=0; k12<=0; k20<=0; k21<=0; k22<=0;
            p12<=0; p11<=0; c20<=0; c21<=0; c22<=0;
            dv_d1<=0; dv_d2<=0; de_out<=0; dout<=0;
        end else begin
            // 三路掩码与两条原色链**都**跟 `shift_w` 走（含行尾多跳那一拍）：只让上面两行跳的话，
            // 末列那一格的"下面一行"还停在倒数第二列 ⇒ 窗口整体错一列（#97 第五笔）。
            // 消隐期没有新像素 ⇒ 当前行重复末列一次（`bin`/`din` 在消隐期不是像素，这条不变）。
            if (shift_w) begin
                k00<=k01; k01<=k02; k02<=b00;
                k10<=k11; k11<=k12; k12<=b01;
                k20<=k21; k21<=k22; k22<=de_in ? bin : k22;
                p12<=c01; p11<=p12;             // 原色中心抽头，与 blur 的 p11 同一个位置
                c20<=c21; c21<=c22; c22<=de_in ? din : c22;
            end
            dv_d1 <= de_in;
            dv_d2 <= dv_d1;
            de_out <= dv_d2;                    // 三拍，不是两拍 —— 见文件头与 ISSUES #54
            // 旁路必须是"与其它三级同一个中心抽头的原色"（tb_v84 的差分判据），
            // 而陈旧行（帧的第一格）那一行的原色也在当前行那一路里 ⇒ 一起换。
            dout   <= by ? (stale_row ? c21 : p11) : (res ? 16'hFFFF : 16'h0000);
        end
    end
endmodule
