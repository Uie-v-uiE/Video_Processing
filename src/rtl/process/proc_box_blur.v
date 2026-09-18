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
    reg [11:0] y_d1;

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p00<=0; p01<=0; p02<=0; p10<=0; p11<=0; p12<=0; p20<=0; p21<=0; p22<=0;
            de_d1<=0; de_d2<=0; y_d1<=0; de_out<=0; dout<=0;
        end else begin
            if (de_in) begin
                p00<=p01; p01<=p02; p02<=r0;
                p10<=p11; p11<=p12; p12<=r1;
                p20<=p21; p21<=p22; p22<=din;
            end
            de_d1 <= de_in;
            y_d1  <= y_in;
            de_d2 <= de_d1;
            de_out <= de_d2;
            if (bypass || y_d1 == 12'd0)
                dout <= p11;
            else
                dout <= avg;
        end
    end
endmodule
