`timescale 1ns/1ps
// Frame reassembly: payload = [u32 LE offset][rgb565 data]
module frame_reasm #(
    parameter IMG_W       = 512,
    parameter IMG_H       = 300,
    parameter FRAME_BYTES = 307200
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  p_data,
    input  wire        p_valid,
    input  wire        p_sof,
    input  wire        p_eof,
    input  wire        p_good,

    output reg         wr_en,
    output reg  [18:0] wr_addr,
    output reg  [15:0] wr_data,

    output reg         frame_done,
    output reg         frame_err,
    output reg  [31:0] stat_frames,
    output reg  [31:0] stat_pkts,
    output reg  [31:0] stat_bytes,
    output reg  [31:0] stat_bad,
    output reg  [31:0] stat_oob_off
);
    localparam [2:0] S_OFF0=0, S_OFF1=1, S_OFF2=2, S_OFF3=3, S_DATA=4;

    reg [2:0]  st;
    reg [31:0] off;
    reg [7:0]  pix_lo;
    reg        have_lo;
    reg [31:0] cover;
    reg [31:0] pkt_pay;
    reg        pkt_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_OFF0;
            off <= 32'd0;
            pix_lo <= 8'd0;
            have_lo <= 1'b0;
            cover <= 32'd0;
            pkt_pay <= 32'd0;
            pkt_active <= 1'b0;
            wr_en <= 1'b0;
            wr_addr <= 19'd0;
            wr_data <= 16'd0;
            frame_done <= 1'b0;
            frame_err <= 1'b0;
            stat_frames <= 32'd0;
            stat_pkts <= 32'd0;
            stat_bytes <= 32'd0;
            stat_bad <= 32'd0;
            stat_oob_off <= 32'd0;
        end else begin
            wr_en <= 1'b0;
            frame_done <= 1'b0;
            frame_err <= 1'b0;

            if (p_valid) begin
                if (p_sof) begin
                    st <= S_OFF0;
                    have_lo <= 1'b0;
                    pkt_pay <= 32'd0;
                    pkt_active <= 1'b1;
                    // consume this byte as offset[7:0]
                    off <= {24'd0, p_data};
                    st <= S_OFF1;
                end else begin
                    case (st)
                        S_OFF0: begin off <= {24'd0, p_data}; st <= S_OFF1; end
                        S_OFF1: begin off[15:8]  <= p_data; st <= S_OFF2; end
                        S_OFF2: begin off[23:16] <= p_data; st <= S_OFF3; end
                        S_OFF3: begin off[31:24] <= p_data; st <= S_DATA; end
                        S_DATA: begin
                            if (!have_lo) begin
                                pix_lo <= p_data;
                                have_lo <= 1'b1;
                            end else begin
                                wr_en   <= 1'b1;
                                wr_data <= {p_data, pix_lo};
                                wr_addr <= off[18:1]; // pixel index = off/2
                                if (off >= FRAME_BYTES)
                                    stat_oob_off <= stat_oob_off + 32'd1;
                                have_lo <= 1'b0;
                                off     <= off + 32'd2;
                            end
                            pkt_pay <= pkt_pay + 32'd1;
                        end
                        default: st <= S_OFF0;
                    endcase
                end
            end

            if (p_eof && pkt_active) begin
                stat_pkts <= stat_pkts + 32'd1;
                // pkt_pay counts RGB payload bytes only (not the 4-byte offset)
                if (p_good) begin
                    if (cover + pkt_pay + (p_valid ? 32'd1 : 32'd0) >= FRAME_BYTES) begin
                        frame_done <= 1'b1;
                        cover <= 32'd0;
                        stat_frames <= stat_frames + 32'd1;
                        stat_bytes <= stat_bytes + pkt_pay + (p_valid ? 32'd1 : 32'd0);
                    end else begin
                        cover <= cover + pkt_pay + (p_valid ? 32'd1 : 32'd0);
                        stat_bytes <= stat_bytes + pkt_pay + (p_valid ? 32'd1 : 32'd0);
                    end
                end else begin
                    stat_bad <= stat_bad + 32'd1;
                    frame_err <= 1'b1;
                end
                st <= S_OFF0;
                have_lo <= 1'b0;
                pkt_active <= 1'b0;
            end
        end
    end
endmodule
