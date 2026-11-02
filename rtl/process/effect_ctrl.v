`timescale 1ns/1ps
// Per-pixel effect enable decoder: "00111" style serial string handled on PS side
// This module just synchronizes and optionally soft-starts enables
module effect_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [4:0] effect_en_async,
    input  wire [7:0] threshold_async,
    output reg  [4:0] effect_en,
    output reg  [7:0] threshold
);
    reg [4:0] en_meta, en_sync;
    reg [7:0] th_meta, th_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en_meta <= 5'd0;
            en_sync <= 5'd0;
            th_meta <= 8'd80;
            th_sync <= 8'd80;
            effect_en <= 5'd0;
            threshold <= 8'd80;
        end else begin
            en_meta <= effect_en_async;
            en_sync <= en_meta;
            th_meta <= threshold_async;
            th_sync <= th_meta;
            effect_en <= en_sync;
            threshold <= th_sync;
        end
    end
endmodule
