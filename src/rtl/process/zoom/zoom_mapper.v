`timescale 1ns/1ps
// 右屏无极缩放逆映射：屏幕 (x,y) → 源图 (sx,sy)。
// inv_scale Q8: 256=1.0x（原始，最大），512=0.5x（缩小）。3 级流水，可与旋转叠加。
module zoom_mapper #(
    parameter IMAGE_W = 512,
    parameter IMAGE_H = 300
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [9:0]  inv_scale,   // Q8, 256=1.0, up to 512=0.5x
    input  wire [8:0]  angle,
    input  wire        rotate_en,
    input  wire [11:0] x_in,
    input  wire [11:0] y_in,
    output reg  [11:0] x_out,
    output reg  [11:0] y_out,
    output reg         oob,
    output reg  [7:0]  frac_x,
    output reg  [7:0]  frac_y
);
    wire signed [9:0] sin_v, cos_v;
    sin_rom u_sin (.angle(angle), .value(sin_v));
    cos_rom u_cos (.angle(angle), .value(cos_v));

    // 512 需 11-bit 有符号才为正
    wire signed [10:0] inv = $signed({1'b0, inv_scale});

    // s0: 中心偏移。旋转用数学坐标 yp_math=H/2-y
    reg signed [12:0] xp, yp_math, yp_disp;
    reg               rot_s0;
    always @(posedge clk) begin
        xp      <= $signed({1'b0, x_in}) - $signed(IMAGE_W / 2);
        yp_math <= $signed(IMAGE_H / 2) - $signed({1'b0, y_in});
        yp_disp <= $signed({1'b0, y_in}) - $signed(IMAGE_H / 2);
        rot_s0  <= rotate_en;
    end

    // s1
    reg signed [23:0] xr_m, yr_m;
    reg signed [12:0] xp_s1, yp_s1;
    reg               rot_s1;
    always @(posedge clk) begin
        xp_s1  <= xp;
        yp_s1  <= rot_s0 ? yp_math : yp_disp;
        rot_s1 <= rot_s0;
        if (rot_s0) begin
            xr_m <= $signed({{11{xp[12]}}, xp}) * cos_v
                  + $signed({{11{yp_math[12]}}, yp_math}) * sin_v;
            yr_m <= -($signed({{11{xp[12]}}, xp}) * sin_v)
                  +  $signed({{11{yp_math[12]}}, yp_math}) * cos_v;
        end else begin
            xr_m <= 24'sd0;
            yr_m <= 24'sd0;
        end
    end

    // s2: * inv_scale；inv>256 时边缘 OOB 填黑（缩小后四周空边）
    wire signed [31:0] rot_xs = xr_m * inv;
    wire signed [31:0] rot_ys = yr_m * inv;
    wire signed [31:0] raw_xs = xp_s1 * inv;
    wire signed [31:0] raw_ys = yp_s1 * inv;

    wire signed [31:0] xr_pix = rot_xs >>> 16;
    wire signed [31:0] yr_pix = rot_ys >>> 16;
    wire signed [31:0] xs_pix = raw_xs >>> 8;
    wire signed [31:0] ys_pix = raw_ys >>> 8;

    wire signed [31:0] sx_c = rot_s1 ? (xr_pix + (IMAGE_W / 2))
                                      : (xs_pix + (IMAGE_W / 2));
    // #104：旋转支以前在这里把小数直接丢掉（`frac_x/frac_y` 钉 0），于是 `bilin on` 在旋转态是空头支票。
    // 接回小数时**纵向那一次翻转必须连着 floor 一起改**：
    //   Y_disp = C − Y_math，而 Y_math = yr_pix + f/256（`>>>16` 是朝 −∞ 取整，所以 f∈[0,256)）
    //   ⇒ Y_disp = (C − yr_pix − 1) + (256 − f)/256  当 f≠0；f=0 时就是 C − yr_pix、小数 0。
    //   只把小数接给 bilin 而不减那一格，就会在旋转态整体错一行（画面上是沿角度方向的一条剪切）。
    wire [7:0] rot_fx = rot_xs[15:8];
    wire [7:0] rot_fy = rot_ys[15:8];
    wire       rot_y_has_frac = (rot_fy != 8'd0);
    wire signed [31:0] sy_c = rot_s1 ? ((IMAGE_H / 2) - yr_pix - (rot_y_has_frac ? 32'sd1 : 32'sd0))
                                      : (ys_pix + (IMAGE_H / 2));

    // floor 与 frac 必须自洽：`>>> 8` 是**朝 −∞** 取整，余下的低 8 位正好是 [0,1) 的小数 ⇒ x_out 与 frac_x
    // 指的是同一条数轴上的同一格（换成 `/256` + 取余就会在负数上错一格）。旋转支同理，只是要取 [15:8]。
    wire [7:0] fx = rot_s1 ? rot_fx : raw_xs[7:0];
    wire [7:0] fy = rot_s1 ? (~rot_fy + 8'd1) : raw_ys[7:0];   // 翻转之后小数也翻：256−f（f=0 时按 8 位回绕成 0，正好对）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_out  <= 12'd0;
            y_out  <= 12'd0;
            oob    <= 1'b1;
            frac_x <= 8'd0;
            frac_y <= 8'd0;
        end else if (sx_c < 0 || sx_c >= IMAGE_W || sy_c < 0 || sy_c >= IMAGE_H) begin
            x_out  <= 12'd0;
            y_out  <= 12'd0;
            oob    <= 1'b1;
            frac_x <= 8'd0;
            frac_y <= 8'd0;
        end else begin
            x_out  <= sx_c[11:0];
            y_out  <= sy_c[11:0];
            oob    <= 1'b0;
            frac_x <= fx;
            frac_y <= fy;
        end
    end
endmodule
