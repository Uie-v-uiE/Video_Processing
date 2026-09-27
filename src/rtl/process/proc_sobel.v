`timescale 1ns/1ps
// Sobel edge magnitude (Gx,Gy) on 3x3 window, output white edge on black
module proc_sobel #(
    parameter H_ACTIVE = 640
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bypass,
    input  wire        vs_in,
    input  wire        de_in,
    input  wire [11:0] x_in,
    input  wire [11:0] y_in,
    input  wire [15:0] din,
    output reg         de_out,
    output reg  [15:0] dout
);
    (* ram_style = "block" *) reg [7:0] lb0 [0:H_ACTIVE-1];
    (* ram_style = "block" *) reg [7:0] lb1 [0:H_ACTIVE-1];
    // 旁路用的**原色**上一行缓存（与 proc_morph 的 `mc1` 同一个写法）。
    // 为什么必须有它：本级的窗口链存的是 8 bit 亮度，而"旁路 = 只搬运不运算"要求搬的是
    // **原来那 16 bit 的 RGB565**，并且必须与其它三级取**同一个中心抽头**（tb_v84 的差分判据：
    // "morph 的旁路与 blur 的旁路逐位相同"）。以前写 `dout <= din` 是把"本级自洽"凌驾于"全链一致"，
    // 代价就是开/关 Sobel 时画面跳一行 + tb_v89 量到的 +2 列。
    (* ram_style = "block" *) reg [15:0] mc1 [0:H_ACTIVE-1];

    // luminance extract
    wire [4:0] r5 = din[15:11];
    wire [5:0] g6 = din[10:5];
    wire [4:0] b5 = din[4:0];
    wire [7:0] r8 = {r5, r5[4:2]};
    wire [7:0] g8 = {g6, g6[5:4]};
    wire [7:0] b8 = {b5, b5[4:2]};
    wire [15:0] y16 = r8 * 8'd77 + g8 * 8'd150 + b8 * 8'd29;
    wire [7:0]  y8  = y16[15:8];

    always @(posedge clk) begin
        if (de_in) begin
            lb0[x_in] <= lb1[x_in];
            lb1[x_in] <= y8;
            mc1[x_in] <= din;                  // 旁路要搬的原色（同一行、同一列）
        end
    end
    // #92 第四笔：行尾多跳一拍（见 proc_box_blur.v 同名注释）。读地址钉在末列——
    // 那一拍 `x_in` 已经在 porch 上，直接当行缓存地址用会越界（仿真给 X，硬件按位截断读到别的列）。
    wire [11:0] x_rd = (x_in >= H_ACTIVE[11:0]) ? (H_ACTIVE[11:0] - 12'd1) : x_in;
    wire [15:0] up1p = mc1[x_rd];              // 与 p11 同一抽头的**原色**版本（读在写之前）

    reg [7:0] q00,q01,q02,q10,q11,q12,q20,q21,q22;   // 窗口原始抽头（下面按边界复制成 p**）
    reg [15:0] c11, c12;                       // 与 p11/p12 同步搬的"原色中心抽头"（旁路用）
    reg [15:0] d20, d21, d22;                  // **当前行**的原色（#97：陈旧行要拿它当中心）
    reg de_d1, de_d2;
    // 只在"刚吃掉本行末列"那一跳多走一拍（见 proc_box_blur.v 那条 #92 第四笔的注释；
    // 拿 de 断点当行尾会被 `tb_rotate_window` 的一拍一像素激励误触发）。
    // 行尾多跳一拍：判据与理由全在 proc_box_blur.v 的 #92 第四笔那段（v1/v2/v3 各红在哪个台架）。
    // 一句话版：**数连续有效像素**，与 `x_in` 的起点/标签级无关；一拍一像素的激励数不满一行，不会误触发。
    reg [11:0] run;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)      run <= 12'd0;
        else if (de_in)  run <= run + 12'd1;
        else            run <= 12'd0;   // de 一断就清：那一拍非阻塞更新的旧值仍看得见，就是本行的宽度（详见 proc_box_blur.v 那五段）
    wire owed     = (run == H_ACTIVE[11:0]);
    wire line_end = owed && de_d1 && !de_in;
    wire shift_w  = de_in || line_end;

    // ---------------------------------------------------------------- #97：四条圈的旗标（数由 tb_edge_rim 量，推导正本在 proc_box_blur.v）
    // ① 拍 k 武装的旗标落在槽位 k+1；② 行尾补跳那一拍落在**下一行第 0 槽**（旧代码在这里塞 1
    // ⇒ 第 0 列被旁路 = 用户念的"左边一条带"）；③ 中心行 = 输入行 − 1 ⇒ 每帧第一格吃的中心
    // 是上一帧的末行（"上边缘那条带"）。四个窗口级用同一套旗标，这是 tb_v92/tb_v84
    // 能差分验证的前提（"开关某一级时不许画面跳一行"）。
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
        no_left_r  [0] <= ~de_in;
        no_right_r [0] <= de_in && (x_in == H_ACTIVE[11:0] - 12'd2);
        no_above_r [0] <= de_in && (y_in == 12'd1) && row_first;
        stale_row_r[0] <= de_in && (y_in == 12'd0);
        no_left_r  [1] <= no_left_r  [0];  no_left_r  [2] <= no_left_r  [1];
        no_right_r [1] <= no_right_r [0];  no_right_r [2] <= no_right_r [1];
        no_above_r [1] <= no_above_r [0];  no_above_r [2] <= no_above_r [1];
        stale_row_r[1] <= stale_row_r[0];  stale_row_r[2] <= stale_row_r[1];
    end
    wire no_left = no_left_r[2], no_right = no_right_r[2];
    wire no_above = no_above_r[2], stale_row = stale_row_r[2];
    // 缺的邻居复制中心（水平 h**、垂直 p** 两级），于是最外圈不再"直出原图"。
    wire [7:0] h00 = no_left ? q01 : q00;   wire [7:0] h02 = no_right ? q01 : q02;
    wire [7:0] h10 = no_left ? q11 : q10;   wire [7:0] h12 = no_right ? q11 : q12;
    wire [7:0] h20 = no_left ? q21 : q20;   wire [7:0] h22 = no_right ? q21 : q22;
    wire [7:0] h01 = q01, h11 = q11, h21 = q21;
    wire [7:0] p00 = stale_row ? h20 : (no_above ? h10 : h00);
    wire [7:0] p01 = stale_row ? h21 : (no_above ? h11 : h01);
    wire [7:0] p02 = stale_row ? h22 : (no_above ? h12 : h02);
    wire [7:0] p10 = stale_row ? h20 : h10;
    wire [7:0] p11 = stale_row ? h21 : h11;
    wire [7:0] p12 = stale_row ? h22 : h12;
    wire [7:0] p20 = h20, p21 = h21, p22 = h22;

    // 边界判据用的坐标：与 p11（窗口中心抽头）同一时刻的 x/y。
    // 以前本级**完全没有**边界判据（`y_in` 端口甚至从没被用过），于是：
    //   · 每行第 0 列的"左邻"= 上一行末尾的像素  ⇒ 右窗分割线旁边糊出一条竖的错色；
    //   · 每帧第 0 行的"上一行"= 上一帧最后一行  ⇒ 右窗顶部糊出一条横的。
    // 两条都是用户 2026-09-24 报的"碰到分割线会有颜色条"的成分，判据 = tb_v92 的 C2/C3。
    // 抽头深度（d1 还是 d2）与 blur/sharpen/morph 保持一致，由 tb_v92 的量出来定，不靠推。

    wire signed [10:0] gx = -$signed({3'b0,p00}) - $signed({2'b0,p10,1'b0}) - $signed({3'b0,p20})
                          + $signed({3'b0,p02}) + $signed({2'b0,p12,1'b0}) + $signed({3'b0,p22});
    wire signed [10:0] gy = -$signed({3'b0,p00}) - $signed({2'b0,p01,1'b0}) - $signed({3'b0,p02})
                          + $signed({3'b0,p20}) + $signed({2'b0,p21,1'b0}) + $signed({3'b0,p22});
    wire [10:0] agx = gx[10] ? -gx : gx;
    wire [10:0] agy = gy[10] ? -gy : gy;
    wire [11:0] mag = agx + agy;
    wire [7:0]  m8  = (mag > 12'd255) ? 8'd255 : mag[7:0];
    wire [15:0] sobel_out = {m8[7:3], m8[7:2], m8[7:3]};

    // 边界守卫已换成上面那四根旗标 + clamp-to-edge 抽头（#97）。
    // 旧写法是**一根** `border_r`：`(x_in==0)||(x_in==H_ACTIVE-1)||(y_in==0)`，并在行尾补跳那一拍
    // 塞 `1'b1`。两个错叠在一起：那一拍落到的其实是**下一行第 0 槽**（⇒ 第 0 列被旁路成原图），
    // 而真正的末列没人管（⇒ 窗口吃下一行折回的格子）。量出来的数与推导正本见 proc_box_blur.v 的 #97 段。

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q00<=0;q01<=0;q02<=0;q10<=0;q11<=0;q12<=0;q20<=0;q21<=0;q22<=0;
            c11<=0; c12<=0;
            d20<=0; d21<=0; d22<=0;
            de_d1<=0; de_d2<=0; de_out<=0; dout<=0;
        end else begin
            // 三路抽头与两条原色链**都**跟 `shift_w` 走（含行尾多跳的那一拍）：只让上面两行跳的话，
            // 末列那一格的"下面一行"还停在倒数第二列 ⇒ 窗口整体错一列（#97 第五笔，R4 逼出来的）。
            // 消隐期没有新像素 ⇒ 当前行重复末列一次；这与 `x_rd` 钉末列是同一手法，
            // 而"消隐期的 `y8`/`din` 不是像素"那一条仍然成立（重复的是上一格，不是总线上的垃圾）。
            if (shift_w) begin
                q00<=q01; q01<=q02; q02<=lb0[x_rd];
                q10<=q11; q11<=q12; q12<=lb1[x_rd];
                c11<=c12; c12<=up1p;           // 原色跟着中心抽头一起走
                q20<=q21; q21<=q22; q22<=de_in ? y8 : q22;
                d20<=d21; d21<=d22; d22<=de_in ? din : d22;
            end
            de_d1 <= de_in;
            de_d2 <= de_d1;
            de_out <= de_d2;
            // 旁路取**窗口中心抽头的原色**（不是 din）：与 proc_box_blur / proc_sharpen / proc_morph
            // 同一套约定。以前这里写 `dout <= din`，本级自己是对的，但整链里它一个人不跟随行约定
            // ⇒ ①开 Sobel 时画面跳一行，②它比标签快 2 列（tb_v89 量到的那个 "+2 列"就是它）。
            // 边界不再走旁路（#97）：走旁路就是"最外圈发原图"，那条断层正是用户报的带。
            if (bypass)
                dout <= stale_row ? d21 : c11;  // 陈旧行：中心用**当前行**的原色（上一帧的尾巴不该上屏）
            else
                dout <= sobel_out;
        end
    end
endmodule
