`timescale 1ns/1ps
// proc_pipeline：显示通路的效果链，级 0 gamma + 五级可选算法，每级可逐位旁路。
// 输入 de/x/y/din 像素流，输出 de_out/dout；固定 15 拍延迟，与哪一级开、同级选哪个算法都无关。
// 内容偏移固定 −4 行、0 列：四个窗口级各贡献 −1 行，点运算级不贡献。
// stage_sel 位定义（每一位一个算法，只有级 5 那两位互斥）：
//   [0]灰度 [1]反色 [2]3×3 模糊 [3]3×3 锐化 [4]Sobel [5]二值化 [6]判决反相(仅 [5]=1 有意义) [7]腐蚀 [8]膨胀
// 时钟域：clk = clk_pix 单域；gamma 表项由 PS 侧经同步器（effect_ctrl）写进来。
module proc_pipeline #(
    // ⚠ `H_ACTIVE` 是**一行有多少个有效拍**，不是显示屏有多宽：今天 512 个有效拍对应源列 0..511，
    //   纵向 2× 是"同一个源行喂两次"、拉伸在链子外面。若哪天为了"整屏单地址流"把它改成 1024，
    //   **滤波的空间尺度会悄悄变两倍**（同级相邻两列在源上只差半格）—— 那是观感变化不是免费优化。
    //   等价且不改观感的喂法是"只在偶数列进链"（`de_in = de_d[3] && !x_d[3][0]`）：一行仍 512 个有效拍。
    parameter H_ACTIVE = 512,
    // 延迟：**固定 15 拍**，与哪一级开、同级选哪个算法无关（每级 de 链不受 bypass 影响，同级两个算法是
    // **串联**的，所以两个都占自己的拍数）。逐拍账：灰度1+反色1+模糊3+锐化3+Sobel3+阈值1+形态学3=15
    // ⚠ 窗口级是**三拍**不是两拍（`de_in → de_d1 → de_d2 → de_out` 三级寄存器）：顶层不许另写一个数、
    //   只取 `u_pipe.LATENCY`，tb_v86 **实测** de_in→de_out 再与它比 ⇒ 任一处漂移就有测试可红。级 0
    //   的 gamma 是分布式 RAM 组合读出 ⇒ **不占拍**；谁改成寄存读出（BRAM 风格）LATENCY 必须同时改成 16。
    parameter integer LATENCY = 15,     // 声明的是本模块的固有延迟，**不许由外部覆盖**
    // 内容偏移（以"喂进来的流的一行"为单位）：**四个窗口级各贡献 −1 行**，点运算级不贡献 ⇒ 整链固定
    //   −4 行、0 列。这不是笔误：行缓存式 3×3 滤波在收到第 y 行时才算得出第 y−1 行的窗口，因果性决定它必然
    //   滞后一行。顶层能补：帧缓存是随机地址的，把右窗读坐标对应的**显示行**提前 OFF_LINES 行，链子
    //   自己的滞后正好把它抵消（零 BRAM，见 pl_video_top 的 cy_r）。
    parameter integer OFF_LINES = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [8:0]  stage_sel,
    input  wire [7:0]  threshold,
    input  wire        gamma_en,        // 级 0：0 = 逐位旁路（tb_v88 的 T1 钉"关着就必须一动不动"）
    input  wire        gamma_wr,        // 翻转位：与 idx/data 同源同深度地过同步器（effect_ctrl）
    input  wire [7:0]  gamma_idx,
    input  wire [7:0]  gamma_data,
    input  wire        rotate_active,     // 状态用；窗口滤波本来就在目标域里做
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire        de_in,
    input  wire [11:0] x_in,
    input  wire [11:0] y_in,
    input  wire [15:0] din,
    output wire [7:0]  off_rows,        // = OFF_LINES：见上面的参数注释
    output wire        de_out,
    output wire [15:0] dout
);
assign off_rows = OFF_LINES[7:0];

    // 九位控制字**逐位直连**，不留第二条兜底口径（两套口径并存时同一个设置就有两种答案）。
    // 级序：gamma → 颜色 → 滤波 → 边缘 → 阈值 → 形态学（阈值在滤波**之后**，形态学是对面具图的操作）。
    wire w_gray  = stage_sel[0];
    wire w_inv   = stage_sel[1];
    wire w_blur  = stage_sel[2];
    wire w_sharp = stage_sel[3];
    wire w_sobel = stage_sel[4];
    wire w_bin   = stage_sel[5];
    wire bin_pol = stage_sel[6];
    wire w_erode = stage_sel[7] & ~stage_sel[8];   // 腐蚀与膨胀**互斥**：两位同时为 1 时两个都不做
    wire w_dilate = stage_sel[8] & ~stage_sel[7];   // （开/闭要两遍 3×3 窗口，这里只有一遍，明确旁路）
    wire [1:0] morph_mode = w_erode ? 2'd1 : (w_dilate ? 2'd2 : 2'd0);

    wire        de1a; wire [15:0] d1a;
    wire        de1b; wire [15:0] d1b;
    wire        de2a; wire [15:0] d2a;
    wire        de2b; wire [15:0] d2b;
    wire        de3;  wire [15:0] d3;
    wire        de4;  wire [15:0] d4;

    // 坐标也要跟着级走
    // 四个窗口级不能共用**顶层那一份** x_in/y_in：每一级的 de_in 是上一级的输出、逐累积地晚 1/3/3/3 拍
    // ⇒ 第 k 级拿到像素那一刻，顶层 x_in 已经在说"第 (n+累积延迟) 个像素"：行缓存按列号写，于是**写进去的
    // 列号与数据差着累积延迟**，且消隐越长差得越多。修法：给坐标装一条与 de 同节奏的自由运行延迟线，
    // 每级取自己那一拍；抽头号 = 该级 de_in 之前累积的拍数（2→blur、5→sharp、8→sobel、12→morph）。
    // ⚠ `xd[k]` 必须是**恰好 k 拍**（#103 的根因就在这条口径上）：以前第一跳写的是 `xd[0] <= x_in`，
    //   于是 `xd[k]` 其实是 k+1 拍 ⇒ 四个窗口级的列标签比它自己的数据**晚一整拍**，后果有两条，都在硬件上：
    //     ① 每行最后一个有效拍上 `x_in` 只到 H_ACTIVE-2 ⇒ 槽位 H_ACTIVE-1 永远没人写（上电读 0）；
    //     ② 每行第一个有效拍上 `x_in` 还停在消隐末尾（顶层一屏数到 1343）⇒ **写地址越界**：xsim 把这一笔
    //        丢掉，硬件按地址位截断成 `1343 mod 1024 = 319` ⇒ 每行往 319 号槽写进消隐期的 0x0000，
    //        读回它的是真实列 320 那一拍 ⇒ 板上一根钉死在显示列 320（源列 160）的 1 像素纯黑竖线。
    //   判据：`sim/tb_v103_pipe_bypass.v` 的 C10d（槽位完整性）与 C10f（越界写），改前两条都红。
    reg [11:0] xd [1:12];               // 这条链是**纯寄存器**、每拍一跳、不参与任何运算 ⇒ 不会把组合链拉长；每一跳 12 bit，代价 = 2×12×12 = 288 个触发器（Slice 寄存器 7936 的 3.6 %）
    reg [11:0] yd [1:12];
    integer cp;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (cp = 1; cp <= 12; cp = cp + 1) begin xd[cp] <= 12'd0; yd[cp] <= 12'd0; end
        end else begin
            xd[1] <= x_in; yd[1] <= y_in;
            for (cp = 2; cp <= 12; cp = cp + 1) begin
                xd[cp] <= xd[cp-1]; yd[cp] <= yd[cp-1];
            end
        end
    end
    wire [11:0] x_blur = xd[2],  y_blur = yd[2];
    wire [11:0] x_sharp = xd[5], y_sharp = yd[5];
    wire [11:0] x_sobel = xd[8], y_sobel = yd[8];
    wire [11:0] x_morph = xd[12], y_morph = yd[12];

    // 级 0 明暗：gamma。**组合读出，不占拍数**，所以它不在上面那串逐拍账里。
    wire [15:0] d0;
    gamma_lut u_gamma (
        .clk(clk), .rst_n(rst_n),
        .en(gamma_en), .wr(gamma_wr), .idx(gamma_idx), .data(gamma_data),
        .din(din), .dout(d0)
    );

    // 级 1 颜色
    proc_gray u_gray (
        .clk(clk), .rst_n(rst_n), .bypass(~w_gray),
        .de_in(de_in), .din(d0), .de_out(de1a), .dout(d1a)
    );
    proc_invert u_inv (
        .clk(clk), .rst_n(rst_n), .bypass(~w_inv),
        .de_in(de1a), .din(d1a), .de_out(de1b), .dout(d1b)
    );

    // 级 2 滤波：两个选项串接，只开其中一个时另一个纯旁路
    proc_box_blur #(.H_ACTIVE(H_ACTIVE)) u_blur (
        .clk(clk), .rst_n(rst_n), .bypass(~w_blur),
        .hs_in(hs_in), .vs_in(vs_in), .de_in(de1b),
        .x_in(x_blur), .y_in(y_blur), .din(d1b),
        .de_out(de2a), .dout(d2a)
    );
    proc_sharpen #(.H_ACTIVE(H_ACTIVE)) u_sharp (
        .clk(clk), .rst_n(rst_n), .bypass(~w_sharp),
        .de_in(de2a), .x_in(x_sharp), .y_in(y_sharp), .din(d2a),
        .de_out(de2b), .dout(d2b)
    );

    // 级 3 边缘
    proc_sobel #(.H_ACTIVE(H_ACTIVE)) u_sobel (
        .clk(clk), .rst_n(rst_n), .bypass(~w_sobel),
        .vs_in(vs_in), .de_in(de2b),
        .x_in(x_sobel), .y_in(y_sobel), .din(d2b),
        .de_out(de3), .dout(d3)
    );

    // 级 4 阈值
    proc_binary u_bin (
        .clk(clk), .rst_n(rst_n), .bypass(~w_bin), .threshold(threshold), .pol(bin_pol),
        .de_in(de3), .din(d3), .de_out(de4), .dout(d4)
    );

    // 级 5 形态学
    proc_morph #(.H_ACTIVE(H_ACTIVE)) u_morph (
        .clk(clk), .rst_n(rst_n), .mode(morph_mode), .threshold(threshold),
        .de_in(de4), .x_in(x_morph), .y_in(y_morph), .din(d4),
        .de_out(de_out), .dout(dout)
    );
endmodule
