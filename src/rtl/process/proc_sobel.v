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

    reg [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
    reg [15:0] c11, c12;                       // 与 p11/p12 同步搬的"原色中心抽头"（旁路用）
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

    // 边界守卫：一根**跟着有效像素走**的旗标链，判「这个中心像素的 3x3 是不是真在画面内」。
    // 为什么不用 x_d1/y_d1 直接和 0 比：那种写法比的是『发出去之后第几拍』，
    //   ① 与消隐宽度、一拍几个像素有关 —— 同一句判据在 512 宽连续栅格与 8 宽(一拍一个像素)
    //      的台架里挡住的列不一样（tb_rotate_window 就是这样被 SLOT_LAG=2 多挡了两列而假红的）；
    //   ② 中心抽头本来就滞后一格，比 0 挡住的是上一行的尾巴，本行第 0 格照样吃到上一行末尾
    //      —— 那就是用户看到的『分割线旁边的颜色条』(ISSUES #56 / #54 (A'))。
    // 旗标按**有效像素**移位（de_in 才动），内容与 p11 那个中心一格不差：
    //   首列（左邻缺）、末列（右邻缺）、首行（上一行缺，行缓存里是上一帧的尾巴）。
    reg [2:0] border_r;
    // ⚠ 复位只能写在这**一个**块里。以前图省事把它也写进主 always 的复位分支，
    //   于是 border_r 有两个驱动源 ⇒ 综合报 `Synth 8-6859/8-6858 multi-driven net`
    //   并且把常量那一侧保留、逻辑那一侧**忽略** ⇒ 旗标在 bit 里恒为 0，
    //   而**仿真看不出来**（xsim 按进程后写覆盖，行为看起来是对的）。
    //   这条由门禁第 13 项（多驱动 CRITICAL WARNING 计数）拦下，见 ISSUES #61。
    always @(posedge clk or negedge rst_n)
    if (!rst_n) border_r <= 3'b0;
    else if (shift_w) begin
        // 旗标链与中心链同拍移位（含行尾那一跳）；那一跳对应的正是末列 ⇒ 旗标钉 1。
        border_r[0] <= de_in ? ((x_in == 12'd0) || (x_in == H_ACTIVE-1) || (y_in == 12'd0)) : 1'b1;
        border_r[1] <= border_r[0];
        border_r[2] <= border_r[1];
    end
    // 三拍 = 一个像素从进来到 dout 的深度（行缓存读 → 窗口移位 → 输出寄存），
    // **按有效像素数**计 ⇒ 与消隐宽度、一拍几个像素无关（SLOT_LAG 那版就是错在按拍号）。
    // 凭据：tb_v92 的 DBG —— "发出槽位 0 的那一拍 x_in = 3" ⇒ 中心列 = x_in − 3。
    wire border = border_r[2];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p00<=0;p01<=0;p02<=0;p10<=0;p11<=0;p12<=0;p20<=0;p21<=0;p22<=0;
            c11<=0; c12<=0;
            de_d1<=0; de_d2<=0; de_out<=0; dout<=0;
        end else begin
            // 行缓存两路 + 原色中心跟着 `shift_w`（含行尾多跳的一拍）；当前行的灰度那一路
            // 只跟 `de_in`——消隐期的 `y8` 不是像素。
            if (shift_w) begin
                p00<=p01; p01<=p02; p02<=lb0[x_rd];
                p10<=p11; p11<=p12; p12<=lb1[x_rd];
                c11<=c12; c12<=up1p;           // 原色跟着中心抽头一起走
            end
            if (de_in) begin
                p20<=p21; p21<=p22; p22<=y8;
            end
            de_d1 <= de_in;
            de_d2 <= de_d1;
            de_out <= de_d2;
            // 旁路取**窗口中心抽头 p11**（不是 din）：与 proc_box_blur / proc_sharpen / proc_morph
            // 同一套约定。以前这里写 `dout <= din`，本级自己是对的，但整链里它一个人不跟随行约定
            // ⇒ ①开 Sobel 时画面跳一行，②它比标签快 2 列（tb_v89 量到的那个 "+2 列"就是它）。
            // 单独把本级做成"自洽旁路"反而更糟：混用约定会让"开关某一级"时画面跳一行（r45 试过）。
            if (bypass || border)
                dout <= c11;                   // 中心抽头的**原色**：旁路与边界都只是搬运
            else
                dout <= sobel_out;
        end
    end
endmodule
