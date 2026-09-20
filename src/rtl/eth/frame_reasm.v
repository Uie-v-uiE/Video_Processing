`timescale 1ns/1ps
// frame_reasm v5.0-fix — commit only if EVERY source row was written this frame.
// Missing rows leave old/zero pixels in DDR → frozen frame shows black + ghost.
// Zoom animation makes those holes look like "moving" black stripes.
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
    output reg         flush,
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
    reg [31:0] pkt_pay;
    reg [31:0] pkt_start;
    reg        pkt_active;
    reg [31:0] cover;

    // per-row coverage this frame
    reg [IMG_H-1:0] row_ok;
    reg [15:0]      rows_hit;

    // byte_off → row: row = byte_off / (IMG_W*2)
    // IMG_W=512 → ROW_STRIDE=1024 → off>>10. Must NOT use off[16:1] (16-bit
    // pixel index truncates ~172/300 rows → frame_done never → SRC1 black).
    localparam integer ROW_STRIDE = IMG_W * 2;
    wire [31:0] row_idx = off / ROW_STRIDE;

    // payload bytes of this packet + everything received earlier this frame.
    // On the last byte p_valid && p_eof share a cycle and pkt_pay has not
    // counted it yet, so add that byte here (and only here) to avoid an
    // off-by-one that would reject the final packet forever.
    wire [31:0] bytes_all = cover + pkt_pay + (p_valid ? 32'd1 : 32'd0);
    // the frame is over when a packet reaches FRAME_BYTES, whole or not
    wire [31:0] pkt_end   = pkt_start + pkt_pay + (p_valid ? 32'd1 : 32'd0);
    wire        last_pkt  = pkt_end >= FRAME_BYTES;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st<=S_OFF0; off<=0; pix_lo<=0; have_lo<=0;
            pkt_pay<=0; pkt_active<=0; cover<=0;
            wr_en<=0; wr_addr<=0; wr_data<=0; flush<=0;
            frame_done<=0; frame_err<=0;
            stat_frames<=0; stat_pkts<=0; stat_bytes<=0;
            stat_bad<=0; stat_oob_off<=0;
            row_ok<=0; rows_hit<=0;
        end else begin
            wr_en<=0; flush<=0; frame_done<=0; frame_err<=0;

            if (p_valid) begin
                if (p_sof) begin
                    st<=S_OFF1; have_lo<=0; pkt_pay<=0; pkt_active<=1;
                    off<={24'd0,p_data};
                end else begin
                    case (st)
                        S_OFF0: begin off<={24'd0,p_data}; st<=S_OFF1; end
                        S_OFF1: begin off[15:8]<=p_data; st<=S_OFF2; end
                        S_OFF2: begin off[23:16]<=p_data; st<=S_OFF3; end
                        S_OFF3: begin
                            off[31:24]<=p_data; st<=S_DATA;
                            pkt_start <= {p_data, off[23:0]};
                            if ({p_data,off[23:0]} < 32'd4) begin
                                cover<=0;
                                row_ok<=0;
                                rows_hit<=0;
                            end
                        end
                        S_DATA: begin
                            if (!have_lo) begin
                                pix_lo<=p_data; have_lo<=1;
                            end else begin
                                wr_en<=1;
                                wr_data<={p_data,pix_lo};
                                wr_addr<=off[18:1];
                                if (off < FRAME_BYTES) begin
                                    if (row_idx < IMG_H && !row_ok[row_idx[8:0]]) begin
                                        row_ok[row_idx[8:0]] <= 1'b1;
                                        rows_hit <= rows_hit + 16'd1;
                                    end
                                end else
                                    stat_oob_off<=stat_oob_off+1;
                                have_lo<=0;
                                off<=off+2;
                            end
                            pkt_pay<=pkt_pay+1;
                        end
                        default: st<=S_OFF0;
                    endcase
                end
            end

            if (p_eof && pkt_active) begin
                flush<=1;
                stat_pkts<=stat_pkts+1;
                if (p_good) begin
                    // Completeness gate: every source row touched AND all
                    // FRAME_BYTES arrived. The row bitmap alone lets a lost
                    // packet through as a "complete" row, and the hole (a BRAM
                    // word never written = 0) shows as a black stripe that
                    // survives a stopped stream.
                    if (rows_hit >= IMG_H[15:0] && bytes_all >= FRAME_BYTES) begin
                        frame_done<=1;
                        cover<=0;
                        row_ok<=0;
                        rows_hit<=0;
                        stat_frames<=stat_frames+1;
                    end else begin
                        // short frame: keep the last good frame on screen and
                        // count it once, when the frame's last packet arrived
                        cover <= bytes_all;
                        if (last_pkt) stat_bad <= stat_bad + 1;
                    end
                    stat_bytes <= stat_bytes + pkt_pay + (p_valid ? 32'd1 : 32'd0);
                end else begin
                    stat_bad<=stat_bad+1;
                    frame_err<=1;
                end
                st<=S_OFF0; have_lo<=0; pkt_active<=0;
            end
        end
    end
endmodule
