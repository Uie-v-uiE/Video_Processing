`timescale 1ns/1ps
// 3x3 box blur, sequential raster only. bypass => center pixel.
module proc_box_blur #(
    parameter H_ACTIVE = 640
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bypass,
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire        de_in,
    input  wire [11:0] x_in,
    input  wire [11:0] y_in,
    input  wire [15:0] din,
    output reg         de_out,
    output reg  [15:0] dout
);
    (* ram_style = "block" *) reg [15:0] lb0 [0:H_ACTIVE-1];
    (* ram_style = "block" *) reg [15:0] lb1 [0:H_ACTIVE-1];

    reg [15:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    reg        de_d1, de_d2;

    // #92 第四笔：行尾多跳一拍 —— 症状是"每行最后一列发出的中心其实是前一列的"（`tb_v89_align` 的 ID 判据：
    // 旁路下每一列都必须落在同一个偏移上，含每行最后一列；四级 + 整链全中，`first col=31 dc=-1`）。机理：中心
    // 抽头是 `p11 <= p12 <= 行缓存读` ⇒ **当拍读到的那一格要再跳一拍才成为中心**，而移位整个被 `de_in` 钉住
    // ⇒ 行内最后一个有效像素读完、下一拍就是消隐，那一跳永远不来 ⇒ 每行少发一个样本，而输出流仍按 `de_out` 数够格子 ⇒ 最后一格只能重复前一列（这一拍省不了）。
    // ⚠ 行尾只能"数连续有效像素"：`de_d1 && !de_in` 在一拍一像素的激励下每个像素后面都算行尾；再加
    //   `x_in == H_ACTIVE-1` 那一版模块级全绿、顶层却一次都没武装（顶层的 `x_d[3]` 与 `de_d[3]` 不同级）⇒ **依赖标签的判据不可用**。
    reg [11:0] run;                          // 本行已连续吃进的有效像素数
    always @(posedge clk or negedge rst_n)
        if (!rst_n)     run <= 12'd0;
        else if (de_in) run <= run + 12'd1;
        else            run <= 12'd0;   // 清零必须"de 一断就清"，不能等第二拍：行间隙只有一拍的激励里晚一拍清等于永远不清。而**同一拍里非阻塞更新的旧值仍然看得见** ⇒ de 落下那一拍 run 正好是本行的宽度，所以既不用 `>=`（那会被一拍一像素的激励误触发）也不用第二拍。
    wire owed     = (run == H_ACTIVE[11:0]); // 本行正好 H_ACTIVE 个有效像素 = 刚吃完的是末列
    wire line_end = owed && de_d1 && !de_in; // 只有一拍：就是现在欠那一跳
    wire shift_w  = de_in || line_end;
    // 多跳那一拍 `x_in` 已经走到 porch（顶层一屏 1344 计数，而行缓存只有 H_ACTIVE 深）：
    // 直接拿它当读地址，仿真越界给 X、硬件按位截断读到别的列 ⇒ 读地址钉在**末列**。
    // 这既是"复制边像素"(clamp-to-edge)，也让这一拍移进窗口的两个邻居与末列的中心一格不差。
    wire [11:0] x_rd = (x_in >= H_ACTIVE[11:0]) ? (H_ACTIVE[11:0] - 12'd1) : x_in;

    always @(posedge clk) begin
        if (de_in) begin
            lb0[x_in] <= lb1[x_in];
            lb1[x_in] <= din;
        end
    end

    wire [15:0] r0 = lb0[x_rd];
    wire [15:0] r1 = lb1[x_rd];

    // ---------------------------------------------------------------- #97：四条圈的旗标落在哪一格，由台架量、不由我推
    // `tb_edge_rim` 第一次把"边缘条带"变成一个坐标（**这一段是四个窗口级的正本**，其余三处指回这里）：
    //   ① 拍 k（`x_in==k` 那一拍）武装的旗标落在**槽位 k+1** ⇒ 旧写法 `x_in==0` 管的是第 1 列、真正的第 0 列没人
    //   管；② 行尾补跳那一拍武装的旗标落在**下一行的第 0 槽**（旧代码在这里塞 `1'b1`，那是"单旗标时代末列也算
    //   边界"的遗留）⇒ 第 0 列被 `border` 旁路成原图直出（实测 `got==raw`）⇒ **左边一条带**；
    //   ③ 中心行 = 输入行 − 1（mode=1 实测行平移 +1）⇒ 每帧第一个输出槽吃的中心是**上一帧的末行** ⇒ **上边缘那条带**：不是位置错、不是没裁黑，是内容陈旧（旧的 `y_in==0` 只标"缺上邻"、标不住整行都是旧的）。
    reg [11:0] y_row_d;                    // this display line's y_in, latched at line end
    always @(posedge clk or negedge rst_n)
        if (!rst_n) y_row_d <= 12'h0FFF;
        else if (line_end) y_row_d <= y_in;
    wire row_first = (y_in != y_row_d);    // x2 raster: only the FIRST display row of a
                                           // source row can be missing the row above
    reg [2:0] no_left_r, no_right_r, no_above_r, stale_row_r;   // ⚠ 复位只能写在这**一个**块里：写进主 always 的复位分支就是两个驱动源 ⇒ 综合报 `Synth 8-6859/8-6858 multi-driven net` 并把逻辑那一侧**忽略**（恒 0），而仿真看不出来（xsim 按进程后写覆盖）；门禁第 13 项拦的就是它，见 ISSUES #61
    always @(posedge clk or negedge rst_n)
    if (!rst_n) begin
        no_left_r <= 3'b0; no_right_r <= 3'b0; no_above_r <= 3'b0; stale_row_r <= 3'b0;
    end else if (shift_w) begin
        // 旗标链必须与中心链**同拍**移位（含行尾那一跳），否则边界位与内容差一格——
        // 那正是 #54 (A') 记过的"比的是发出去之后第几拍"那一族。
        no_left_r  [0] <= ~de_in;                                     // 补跳那一拍 = 下一行第 0 槽
        no_right_r [0] <= de_in && (x_in == H_ACTIVE[11:0] - 12'd2);   // 缺右邻：①的平移 ⇒ 拍 k 落槽位 k+1
        no_above_r [0] <= de_in && (y_in == 12'd1) && row_first;       // 缺上邻：中心行 0（上面那一行不存在）
        stale_row_r[0] <= de_in && (y_in == 12'd0);                    // 整行陈旧：中心行 −1 ⇒ 三行都用当前行
        no_left_r  [1] <= no_left_r  [0];  no_left_r  [2] <= no_left_r  [1];
        no_right_r [1] <= no_right_r [0];  no_right_r [2] <= no_right_r [1];
        no_above_r [1] <= no_above_r [0];  no_above_r [2] <= no_above_r [1];
        stale_row_r[1] <= stale_row_r[0];  stale_row_r[2] <= stale_row_r[1];
    end
    wire no_left   = no_left_r[2];
    wire no_right  = no_right_r[2];
    wire no_above  = no_above_r[2];
    wire stale_row = stale_row_r[2];

    // 水平：缺的邻居复制**中心那一列**（clamp-to-edge）⇒ 窗口宽度不变、值与内部连续，
    // 最外圈不再"直出原图"，那条断层就是用户报的带。
    wire [15:0] h00 = no_left ? p01 : p00;   wire [15:0] h02 = no_right ? p01 : p02;
    wire [15:0] h10 = no_left ? p11 : p10;   wire [15:0] h12 = no_right ? p11 : p12;
    wire [15:0] h20 = no_left ? p21 : p20;   wire [15:0] h22 = no_right ? p21 : p22;
    wire [15:0] h01 = p01, h11 = p11, h21 = p21;   // 中心列不需要复制，写出来只为垂直那一步能同形
    // 垂直：只缺上邻 ⇒ 上行复制中心行；整行陈旧 ⇒ 上行与中心行都复制**当前行**
    //（屏上这一格该给的就是帧的第一行，而它在 p2x 那一路里，不在行缓存里）。
    wire [15:0] e00 = stale_row ? h20 : (no_above ? h10 : h00);
    wire [15:0] e01 = stale_row ? h21 : (no_above ? h11 : h01);
    wire [15:0] e02 = stale_row ? h22 : (no_above ? h12 : h02);
    wire [15:0] e10 = stale_row ? h20 : h10;
    wire [15:0] e11 = stale_row ? h21 : h11;
    wire [15:0] e12 = stale_row ? h22 : h12;
    wire [15:0] e20 = h20, e21 = h21, e22 = h22;

    // 9-sample sums (5b*9=9b, 6b*9=10b)
    wire [9:0] rs = {5'd0,e00[15:11]}+{5'd0,e01[15:11]}+{5'd0,e02[15:11]}
                   +{5'd0,e10[15:11]}+{5'd0,e11[15:11]}+{5'd0,e12[15:11]}
                   +{5'd0,e20[15:11]}+{5'd0,e21[15:11]}+{5'd0,e22[15:11]};
    wire [10:0] gs = {5'd0,e00[10:5]}+{5'd0,e01[10:5]}+{5'd0,e02[10:5]}
                    +{5'd0,e10[10:5]}+{5'd0,e11[10:5]}+{5'd0,e12[10:5]}
                    +{5'd0,e20[10:5]}+{5'd0,e21[10:5]}+{5'd0,e22[10:5]};
    wire [9:0] bs = {5'd0,e00[4:0]}+{5'd0,e01[4:0]}+{5'd0,e02[4:0]}
                   +{5'd0,e10[4:0]}+{5'd0,e11[4:0]}+{5'd0,e12[4:0]}
                   +{5'd0,e20[4:0]}+{5'd0,e21[4:0]}+{5'd0,e22[4:0]};

    // *57 >> 9 ≈ /9  (57/512 ≈ 0.1113)
    wire [16:0] rp = rs * 17'd57;
    wire [17:0] gp = gs * 18'd57;
    wire [16:0] bp = bs * 17'd57;
    wire [4:0] r_avg = rp[13:9];
    wire [5:0] g_avg = gp[14:9];
    wire [4:0] b_avg = bp[13:9];
    wire [15:0] avg = {r_avg, g_avg, b_avg};

    // 中心抽头 `p11` 在陈旧行上是上一帧的尾巴 ⇒ 旁路也必须跟着换，否则"关掉效果"时
    // 上边缘那条陈旧带原样还在（这条由 tb_edge_rim 的 mode=1 与 R3 一起管）。
    wire [15:0] center = stale_row ? e21 : p11;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p00<=0; p01<=0; p02<=0; p10<=0; p11<=0; p12<=0; p20<=0; p21<=0; p22<=0;
            de_d1<=0; de_d2<=0; de_out<=0; dout<=0;
        end else begin
            // 中心那两行来自行缓存读，跟着 `shift_w` 走（含行尾多跳的那一拍）；
            // 当前行那一路只跟 `de_in` 走 —— 消隐期的 `din` 不是像素，移进窗口只会污染左边界。
            if (shift_w) begin
                p00<=p01; p01<=p02; p02<=r0;
                p10<=p11; p11<=p12; p12<=r1;
                // 行尾补跳那一拍，**当前行这一路也必须跳**：中心行与下一行只差一拍的话，
                // 末列那一格的三行窗口里"下面那一行"就还停在倒数第二列 ⇒ 窗口整体错位，
                // 补上来的那一格既不是 clamp 也不是原始平均（`tb_edge_rim` R4：
                // `got=8c51` 而 clamp=`b596`、raw=`d69a`、下一行折回=`83f0`，四个都不是）。
                // 消隐期没有新像素 ⇒ 把末列**重复一次**，与上面两行用 `x_rd` 钉末列同一手法。
                p20<=p21; p21<=p22; p22<=de_in ? din : p22;
            end
            de_d1 <= de_in;
            de_d2 <= de_d1;
            de_out <= de_d2;
            if (bypass)
                dout <= center;
            else
                dout <= avg;
        end
    end
endmodule
