`timescale 1ns/1ps
// Dual-pane: left original / right processed+zoomed.
// Display 1024x600, each pane 512 wide, source 512x300 with 2x vertical scale.
module split_display #(
    parameter PANE_W = 512
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        de,
    input  wire        hs,
    input  wire        vs,
    input  wire [15:0] orig_pix,
    input  wire [15:0] proc_pix,
    input  wire [1:0]  angle_idx,
    input  wire        oob_l,
    input  wire        oob_r,
    output reg  [7:0]  r,
    output reg  [7:0]  g,
    output reg  [7:0]  b,
    output reg         de_out,
    output reg         hs_out,
    output reg         vs_out
);
    wire        left = (x < PANE_W);
    wire        oob  = left ? oob_l : oob_r;
    wire [15:0] sel  = oob ? 16'h0000 : (left ? orig_pix : proc_pix);
    wire [4:0]  r5   = sel[15:11];
    wire [5:0]  g6   = sel[10:5];
    wire [4:0]  b5   = sel[4:0];
    wire        sep  = (x == PANE_W-1) || (x == PANE_W);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r <= 0; g <= 0; b <= 0;
            de_out <= 0; hs_out <= 0; vs_out <= 0;
        end else begin
            de_out <= de;
            hs_out <= hs;
            vs_out <= vs;
            if (sep && de) begin
                r <= 8'h40; g <= 8'h40; b <= 8'hFF;
            end else begin
                r <= {r5, r5[4:2]};
                g <= {g6, g6[5:4]};
                b <= {b5, b5[4:2]};
            end
        end
    end
endmodule
