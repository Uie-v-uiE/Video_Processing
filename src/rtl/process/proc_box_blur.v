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

    always @(posedge clk) begin
        if (de_in) begin
            lb0[x_in] <= lb1[x_in];
            lb1[x_in] <= din;
        end
    end

    wire [15:0] r0 = lb0[x_in];
    wire [15:0] r1 = lb1[x_in];

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
    else if (de_in) begin
        border_r[0] <= (x_in == 12'd0) || (x_in == H_ACTIVE-1) || (y_in == 12'd0);
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
            if (de_in) begin
                p00<=p01; p01<=p02; p02<=r0;
                p10<=p11; p11<=p12; p12<=r1;
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
