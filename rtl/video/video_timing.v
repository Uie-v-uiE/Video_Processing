`timescale 1ns/1ps
// 320x180 or 640x360 video timing generator
// Default: 640x360 active, used both as source geometry and as reference for scaling
module video_timing #(
    parameter H_ACTIVE = 640,
    parameter V_ACTIVE = 360,
    parameter H_FP     = 16,
    parameter H_SYNC   = 64,
    parameter H_BP     = 80,
    parameter V_FP     = 4,
    parameter V_SYNC   = 6,
    parameter V_BP     = 12,
    parameter H_POL    = 1'b0,
    parameter V_POL    = 1'b1
)(
    input  wire        clk,
    input  wire        rst_n,
    output reg  [11:0] x,
    output reg  [11:0] y,
    output reg         hs,
    output reg         vs,
    output reg         de,
    output reg         frame_start,
    output reg         frame_done
);
    localparam H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
    localparam V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

    reg [11:0] h_cnt;
    reg [11:0] v_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 12'd0;
            v_cnt <= 12'd0;
        end else begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 12'd0;
                if (v_cnt == V_TOTAL - 1)
                    v_cnt <= 12'd0;
                else
                    v_cnt <= v_cnt + 12'd1;
            end else begin
                h_cnt <= h_cnt + 12'd1;
            end
        end
    end

    wire hs_act = (h_cnt >= H_ACTIVE + H_FP) && (h_cnt < H_ACTIVE + H_FP + H_SYNC);
    wire vs_act = (v_cnt >= V_ACTIVE + V_FP) && (v_cnt < V_ACTIVE + V_FP + V_SYNC);
    wire de_act = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 12'd0;
            y <= 12'd0;
            hs <= 1'b0;
            vs <= 1'b0;
            de <= 1'b0;
            frame_start <= 1'b0;
            frame_done  <= 1'b0;
        end else begin
            x <= h_cnt;
            y <= v_cnt;
            hs <= H_POL ? hs_act : ~hs_act;
            vs <= V_POL ? vs_act : ~vs_act;
            de <= de_act;
            frame_start <= de_act && (h_cnt == 12'd0) && (v_cnt == 12'd0);
            frame_done  <= (h_cnt == H_TOTAL-1) && (v_cnt == V_TOTAL-1);
        end
    end
endmodule
