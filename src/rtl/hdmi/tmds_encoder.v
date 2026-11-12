`timescale 1ns/1ps
// DVI/HDMI TMDS 8b/10b encoder (channel)
module tmds_encoder (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] din,
    input  wire       c0,
    input  wire       c1,
    input  wire       de,
    output reg  [9:0] dout
);
    // ones count
    function [3:0] ones;
        input [7:0] v;
        begin
            ones = v[0]+v[1]+v[2]+v[3]+v[4]+v[5]+v[6]+v[7];
        end
    endfunction

    wire [3:0] n1 = ones(din);
    wire use_xnor = (n1 > 4'd4) || (n1 == 4'd4 && din[0] == 1'b0);

    reg [8:0] q_m;
    // 显式展开 9 位：for 循环在综合里本来就会展开，写成展开形式让静态分析能证明每位都有驱动
    always @(*) begin
        q_m[0] = din[0];
        if (use_xnor) begin
            q_m[1] = ~(q_m[0] ^ din[1]);
            q_m[2] = ~(q_m[1] ^ din[2]);
            q_m[3] = ~(q_m[2] ^ din[3]);
            q_m[4] = ~(q_m[3] ^ din[4]);
            q_m[5] = ~(q_m[4] ^ din[5]);
            q_m[6] = ~(q_m[5] ^ din[6]);
            q_m[7] = ~(q_m[6] ^ din[7]);
            q_m[8] = 1'b0;
        end else begin
            q_m[1] = q_m[0] ^ din[1];
            q_m[2] = q_m[1] ^ din[2];
            q_m[3] = q_m[2] ^ din[3];
            q_m[4] = q_m[3] ^ din[4];
            q_m[5] = q_m[4] ^ din[5];
            q_m[6] = q_m[5] ^ din[6];
            q_m[7] = q_m[6] ^ din[7];
            q_m[8] = 1'b1;
        end
    end

    reg signed [5:0] cnt;
    wire [3:0] n1q = ones(q_m[7:0]);
    wire [3:0] n0q = 4'd8 - n1q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout <= 10'b1101010100;
            cnt  <= 6'sd0;
        end else if (!de) begin
            cnt <= 6'sd0;
            case ({c1, c0})
                2'b00: dout <= 10'b1101010100;
                2'b01: dout <= 10'b0010101011;
                2'b10: dout <= 10'b0101010100;
                default: dout <= 10'b1010101011;
            endcase
        end else begin
            if (cnt == 0 || n1q == n0q) begin
                dout[9] <= ~q_m[8];
                dout[8] <= q_m[8];
                dout[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
                if (q_m[8] == 1'b0)
                    cnt <= cnt + (n0q - n1q);
                else
                    cnt <= cnt + (n1q - n0q);
            end else if ((cnt > 0 && n1q > n0q) || (cnt < 0 && n0q > n1q)) begin
                dout[9] <= 1'b1;
                dout[8] <= q_m[8];
                dout[7:0] <= ~q_m[7:0];
                cnt <= cnt + {2'b00, q_m[8], 1'b0} + (n0q - n1q);
            end else begin
                dout[9] <= 1'b0;
                dout[8] <= q_m[8];
                dout[7:0] <= q_m[7:0];
                cnt <= cnt - {2'b00, ~q_m[8], 1'b0} + (n1q - n0q);
            end
        end
    end
endmodule
