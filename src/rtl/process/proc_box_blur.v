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

    // ---------------------------------------------------------------- #92 第四笔：行尾多跳一拍
    // 症状（`tb_v89_align` 的 ID 判据，2026-09-26 夜）：**每一行的最后一列**发出的中心是**前一列**
    // 的（`off-col samples=28/896 in 1 cols | first col=31 dc=-1`，四个窗口级一模一样），
    // 顶层台架 `tb_v98` 的 C2 于是量到 `inbad=484 badpairs=1 firstpair=511`。
    // 机理：中心抽头是 `p11 <= p12 <= r1`，也就是"当拍读到的那一格要**再跳一拍**才成为中心"；
    // 而移位整个被 `de_in` 钉住 ⇒ 行内最后一个有效像素读完，下一拍就是消隐，那一跳永远不来。
    // ⇒ 每行少发一个样本，输出流却按 `de_out` 数够格子 ⇒ 最后一格只能重复前一列。
    // 修法：行尾**多跳一拍**，但只在"刚吃完本行最后一格"那一跳——`de` 中间断开（台架一拍一像素、
    // 或将来加时钟使能）时不许把它当成行尾，那是 #92 之后 `tb_rotate_window` 红给我看的：
    // 它按"一拍有效、一拍空"推像素，用 `de_d1 && !de_in` 会在**每个像素后面**多跳一次 ⇒ 模糊整个坏掉。
    // **两个条件都要**，缺一不可（每一半都红过一次，别只看一半就下结论）：
    //   · 只按"de 停了" ⇒ `tb_rotate_window` 一拍一像素地推，每个像素后面都算"行尾" ⇒ 模糊整个坏掉；
    //   · 只按"坐标到了末列" ⇒ 在 `proc_pipeline` 里坐标线与逐级 de 不同拍，武装得比行尾早，
    //     那一跳落在线中间，行尾真正欠的那一跳还是没来（`tb_v89` 的 ID 只剩 chain 红，实测
    //     `OBS lastcol: standalone_blur=128 chain_blur=127` ⇒ 链子里武装确实发生了）。
    // 合起来：**这一行的末列已经吃到** 且 **de 刚刚停下** ⇒ 就是现在，多跳这一拍（一次性）。
    reg owed;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) owed <= 1'b0;
        else if (de_in && (x_in == H_ACTIVE[11:0] - 12'd1)) owed <= 1'b1;
        else if (owed && de_d1 && !de_in)                  owed <= 1'b0;
    wire line_end = owed && de_d1 && !de_in;
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

    // 9-sample sums (5b*9=9b, 6b*9=10b)
    wire [9:0] rs = {5'd0,p00[15:11]}+{5'd0,p01[15:11]}+{5'd0,p02[15:11]}
                   +{5'd0,p10[15:11]}+{5'd0,p11[15:11]}+{5'd0,p12[15:11]}
                   +{5'd0,p20[15:11]}+{5'd0,p21[15:11]}+{5'd0,p22[15:11]};
    wire [10:0] gs = {5'd0,p00[10:5]}+{5'd0,p01[10:5]}+{5'd0,p02[10:5]}
                    +{5'd0,p10[10:5]}+{5'd0,p11[10:5]}+{5'd0,p12[10:5]}
                    +{5'd0,p20[10:5]}+{5'd0,p21[10:5]}+{5'd0,p22[10:5]};
    wire [9:0] bs = {5'd0,p00[4:0]}+{5'd0,p01[4:0]}+{5'd0,p02[4:0]}
                   +{5'd0,p10[4:0]}+{5'd0,p11[4:0]}+{5'd0,p12[4:0]}
                   +{5'd0,p20[4:0]}+{5'd0,p21[4:0]}+{5'd0,p22[4:0]};

    // *57 >> 9 ≈ /9  (57/512 ≈ 0.1113)
    wire [16:0] rp = rs * 17'd57;
    wire [17:0] gp = gs * 18'd57;
    wire [16:0] bp = bs * 17'd57;
    wire [4:0] r_avg = rp[13:9];
    wire [5:0] g_avg = gp[14:9];
    wire [4:0] b_avg = bp[13:9];
    wire [15:0] avg = {r_avg, g_avg, b_avg};

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
        // 旗标链必须与中心链**同拍**移位（含行尾那一跳），否则边界位与内容差一格——
        // 那正是 #54 (A') 记过的"比的是发出去之后第几拍"那一族。多跳那一拍对应的正是末列 ⇒ 旗标 1。
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
            p00<=0; p01<=0; p02<=0; p10<=0; p11<=0; p12<=0; p20<=0; p21<=0; p22<=0;
            de_d1<=0; de_d2<=0; de_out<=0; dout<=0;
        end else begin
            // 中心那两行来自行缓存读，跟着 `shift_w` 走（含行尾多跳的那一拍）；
            // 当前行那一路只跟 `de_in` 走 —— 消隐期的 `din` 不是像素，移进窗口只会污染左边界。
            if (shift_w) begin
                p00<=p01; p01<=p02; p02<=r0;
                p10<=p11; p11<=p12; p12<=r1;
            end
            if (de_in) begin
                p20<=p21; p21<=p22; p22<=din;
            end
            de_d1 <= de_in;
            de_d2 <= de_d1;
            de_out <= de_d2;
            if (bypass || border)
                dout <= p11;
            else
                dout <= avg;
        end
    end
endmodule
