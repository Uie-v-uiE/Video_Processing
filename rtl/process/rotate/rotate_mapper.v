`timescale 1ns/1ps
// Inverse map display/canvas (x,y) -> source (sx,sy) for angle 0..359.
// Math: center image, flip Y, rotate by -angle (matches reference matlab).
// Multiplies registered in 2 stages for timing at 75 MHz.
module rotate_mapper #(
    parameter IMAGE_W = 640,
    parameter IMAGE_H = 360
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [8:0]  angle,
    input  wire        enable,
    input  wire [11:0] x_in,
    input  wire [11:0] y_in,
    output reg  [11:0] x_out,
    output reg  [11:0] y_out,
    output reg         oob
);
    wire signed [9:0] sin_v, cos_v;
    sin_rom u_sin (.angle(angle), .value(sin_v));
    cos_rom u_cos (.angle(angle), .value(cos_v));

    // stage 0: center + Y flip
    reg signed [12:0] xp, yp;
    always @(posedge clk) begin
        xp <= x_in - (IMAGE_W / 2);
        yp <= (IMAGE_H / 2) - y_in;
    end

    // stage 1: multiplies
    reg signed [23:0] xr_m, yr_m;
    always @(posedge clk) begin
        xr_m <= $signed({{11{xp[12]}}, xp}) * cos_v
              + $signed({{11{yp[12]}}, yp}) * sin_v;
        yr_m <= -($signed({{11{xp[12]}}, xp}) * sin_v)
              +  $signed({{11{yp[12]}}, yp}) * cos_v;
    end

    // stage 2: shift + reverse
    wire signed [23:0] xr = xr_m >>> 8;
    wire signed [23:0] yr = yr_m >>> 8;
    wire signed [24:0] xs = xr + (IMAGE_W / 2);
    wire signed [24:0] ys = (IMAGE_H / 2) - yr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_out <= 12'd0;
            y_out <= 12'd0;
            oob   <= 1'b1;
        end else if (!enable) begin
            x_out <= x_in;
            y_out <= y_in;
            oob   <= (x_in >= IMAGE_W) || (y_in >= IMAGE_H);
        end else begin
            if (xs < 0 || xs >= IMAGE_W || ys < 0 || ys >= IMAGE_H) begin
                x_out <= 12'd0;
                y_out <= 12'd0;
                oob   <= 1'b1;
            end else begin
                x_out <= xs[11:0];
                y_out <= ys[11:0];
                oob   <= 1'b0;
            end
        end
    end
endmodule
