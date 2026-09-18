`timescale 1ns/1ps
// Double-buffered frame buffer: AXI writes back buffer, video reads front.
// Swap on frame_done (AXI domain) synchronized to video vsync.
module frame_buffer_db #(
    parameter W = 512,
    parameter H = 300
)(
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,
    input  wire [15:0] wr_data,
    input  wire        wr_frame_done,

    input  wire        rd_clk,
    input  wire        rd_vsync,
    input  wire [18:0] rd_addr,
    output reg  [15:0] rd_data
);
    localparam DEPTH = W * H;

    (* ram_style = "block" *) reg [15:0] buf0 [0:DEPTH-1];
    (* ram_style = "block" *) reg [15:0] buf1 [0:DEPTH-1];

    reg wr_sel = 1'b0;
    reg rd_sel = 1'b0;

    reg wr_swap_tog = 1'b0;
    always @(posedge wr_clk) begin
        if (wr_en) begin
            if (wr_sel)
                buf1[wr_addr] <= wr_data;
            else
                buf0[wr_addr] <= wr_data;
        end
        if (wr_frame_done) begin
            wr_sel      <= ~wr_sel;       // next frame goes to the other bank
            wr_swap_tog <= ~wr_swap_tog;  // tell display to flip at next vsync
        end
    end

    reg s0, s1, s2;
    always @(posedge rd_clk) begin
        {s2, s1, s0} <= {s1, s0, wr_swap_tog};
    end
    wire swap_req = s2 ^ s1;

    reg vs_d0, vs_d1;
    always @(posedge rd_clk) begin
        vs_d0 <= rd_vsync;
        vs_d1 <= vs_d0;
    end
    wire vs_rise = vs_d0 & ~vs_d1;

    always @(posedge rd_clk) begin
        if (vs_rise && swap_req)
            rd_sel <= ~rd_sel;
    end

    wire [18:0] rd_a = rd_addr < DEPTH ? rd_addr : 19'd0;
    always @(posedge rd_clk) begin
        if (rd_sel)
            rd_data <= buf0[rd_a];
        else
            rd_data <= buf1[rd_a];
    end
endmodule
