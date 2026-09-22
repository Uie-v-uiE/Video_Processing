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

    // 小数位（V7.8 双线性）。rot_* 是 Q16（xr_m 为 Q8，再乘 inv 的 Q8），整数部分已经被
    // >>>16 拿走，[15:8] 就是 Q8 小数。两条分支的符号不一样，这里必须分开处理：
    //   x 方向是加法（+IMAGE_W/2 是整数，不改变小数）⇒ 直接取 rot_xs[15:8]；
    //   y 方向是减法（sy = H/2 - yr）⇒ floor(sy) 比 (H/2 - yr_pix) 小 1（小数非零时），
    //     所以整数抽头退一格、小数取 256-f。漏掉这一步的现象是「旋转时上下各错一行」，
    //     而且它不会报任何错 —— 只有屏上看得出，所以判据放在 tb_zoom_mapper 里。
    wire [7:0] frx_r = rot_xs[15:8];
    wire [7:0] fry_r = rot_ys[15:8];
    wire       ysub  = (fry_r != 8'd0);

    wire signed [31:0] sx_c = rot_s1 ? (xr_pix + (IMAGE_W / 2))
                                      : (xs_pix + (IMAGE_W / 2));
    wire signed [31:0] sy_c = rot_s1 ? ((IMAGE_H / 2) - yr_pix - $signed({31'd0, ysub}))
                                      : (ys_pix + (IMAGE_H / 2));

    wire [7:0] fx = rot_s1 ? frx_r : raw_xs[7:0];
    wire [7:0] fy = rot_s1 ? (ysub ? (8'd0 - fry_r) : 8'd0) : raw_ys[7:0];

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
