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
        end
    end

    reg [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
    reg de_d1, de_d2;

    wire signed [10:0] gx = -$signed({3'b0,p00}) - $signed({2'b0,p10,1'b0}) - $signed({3'b0,p20})
                          + $signed({3'b0,p02}) + $signed({2'b0,p12,1'b0}) + $signed({3'b0,p22});
    wire signed [10:0] gy = -$signed({3'b0,p00}) - $signed({2'b0,p01,1'b0}) - $signed({3'b0,p02})
                          + $signed({3'b0,p20}) + $signed({2'b0,p21,1'b0}) + $signed({3'b0,p22});
    wire [10:0] agx = gx[10] ? -gx : gx;
    wire [10:0] agy = gy[10] ? -gy : gy;
    wire [11:0] mag = agx + agy;
    wire [7:0]  m8  = (mag > 12'd255) ? 8'd255 : mag[7:0];
    wire [15:0] sobel_out = {m8[7:3], m8[7:2], m8[7:3]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p00<=0;p01<=0;p02<=0;p10<=0;p11<=0;p12<=0;p20<=0;p21<=0;p22<=0;
            de_d1<=0; de_d2<=0; de_out<=0; dout<=0;
        end else begin
            if (de_in) begin
                p00<=p01; p01<=p02; p02<=lb0[x_in];
                p10<=p11; p11<=p12; p12<=lb1[x_in];
                p20<=p21; p21<=p22; p22<=y8;
            end
            de_d1 <= de_in;
            de_d2 <= de_d1;
            de_out <= de_d2;
            if (bypass)
                dout <= din;
            else
                dout <= sobel_out;
        end
    end
endmodule
