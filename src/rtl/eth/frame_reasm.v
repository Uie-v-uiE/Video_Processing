`timescale 1ns/1ps
// frame_reasm v5.1 — commit only if EVERY source row was written this frame.
// Missing rows leave old/zero pixels in DDR → frozen frame shows black + ghost.
// Zoom animation makes those holes look like "moving" black stripes.
//
// v5.1 is a timing-only rewrite of the byte-count arithmetic (the accept/reject
// decisions are unchanged). The 3-operand 32-bit adder that used to evaluate
// `cover + pkt_pay + 1 >= FRAME_BYTES` on the fly owned all ten worst paths of
// the 125 MHz eth_rxc group (WNS +0.499): its carry chain started behind a
// 1.95 ns route out of udp_rx's rec_en. It is replaced by two saturating
// running totals, so the test became a constant compare of a local register
// and p_valid only has to reach one LUT input.
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
    // v7.6: 两个**只增不改行为**的观测口，给 link_monitor 用。
    // frame_abort 只在「本帧字节预算已用完、但验收门没过」的那一拍脉冲一次；
    // rows_missed 与它同拍有效 = 还差多少源行没被写过（黑纹的行数）。
    // 注意：一个连 FRAME_BYTES 都没凑够的短帧不会脉冲 frame_abort（它没有
    // "结束"这件事可报），那种情况由 link_monitor 的 stall_ms 抓到。
    output reg         frame_abort,
    output reg  [15:0] rows_missed,
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
    reg        bad_frame;      // a failed packet landed in this frame

    // ---- byte accounting ----------------------------------------------
    // cov  = payload bytes received for this frame, including the packet in
    //        flight (it is what cover+pkt_pay used to add up to);
    // pend = the same count for the packet in flight only, i.e. the byte
    //        offset its next payload byte lands on.
    // Both saturate at FRAME_BYTES.
    //
    // Saturation is loss-free here: the old code only ever asked
    // "cov + 1 >= FRAME_BYTES", and for a monotonically growing count
    // ">= FRAME_BYTES" and "== FRAME_BYTES" are the same question. Both
    // counters are cleared at frame start and at commit, so a frame can never
    // inherit a saturated value from an earlier one.
    //
    // `cov` is not called `cover`: that is a SystemVerilog keyword and xvlog
    // rejects it as an identifier as soon as a file is compiled with -sv.
    //
    // One behavioural difference vs v5.0, and it is deliberate: v5.0 subtracted
    // a failed packet out of the byte total, which is what made a bad packet
    // reject the frame. A running per-byte total cannot un-count bytes that
    // were already folded in, so a failed packet now sets `bad_frame` and the
    // commit gate tests that flag instead. Same verdict, one bit cheaper, and
    // it no longer needs the frame's byte total to remember every packet.
    localparam integer CW    = $clog2(FRAME_BYTES + 1);
    localparam [CW-1:0] SAT  = FRAME_BYTES;          // frame complete
    localparam [CW-1:0] SAT1 = FRAME_BYTES - 1;      // one byte short

    reg [CW-1:0] cov;
    reg [CW-1:0] pend;

    wire cov_sat  = (cov == SAT);
    wire cov_end  = (cov == SAT1);
    wire pend_sat = (pend == SAT);
    wire pend_end = (pend == SAT1);

    // The last byte of a packet shares its cycle with p_eof and the counters
    // have not seen it yet, so it is credited here (and only here) — the same
    // off-by-one guard v5.0 needed, now one LUT deep instead of an adder.
    wire bytes_ok = cov_sat  | (cov_end  & p_valid);
    // the frame is over when a packet reaches FRAME_BYTES, whole or not
    wire last_pkt = pend_sat | (pend_end & p_valid);

    // per-row coverage this frame
    reg [IMG_H-1:0] row_ok;
    reg [15:0]      rows_hit;

    // byte_off → row: row = byte_off / (IMG_W*2)
    // IMG_W=512 → ROW_STRIDE=1024 → off>>10. Must NOT use off[16:1] (16-bit
    // pixel index truncates ~172/300 rows → frame_done never → SRC1 black).
    localparam integer ROW_STRIDE = IMG_W * 2;
    wire [31:0] row_idx = off / ROW_STRIDE;

    // 4-byte little-endian offset, complete in the S_OFF3 cycle
    wire [31:0] hdr = {p_data, off[23:0]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st<=S_OFF0; off<=0; pix_lo<=0; have_lo<=0;
            pkt_pay<=0; pkt_active<=0; cov<=0; pend<=0; bad_frame<=0;
            wr_en<=0; wr_addr<=0; wr_data<=0; flush<=0;
            frame_done<=0; frame_err<=0;
            frame_abort<=0; rows_missed<=0;
            stat_frames<=0; stat_pkts<=0; stat_bytes<=0;
            stat_bad<=0; stat_oob_off<=0;
            row_ok<=0; rows_hit<=0;
        end else begin
            wr_en<=0; flush<=0; frame_done<=0; frame_err<=0; frame_abort<=0;

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
                            pkt_start <= hdr;
                            pend      <= (hdr >= FRAME_BYTES) ? SAT : hdr[CW-1:0];
                            if (hdr < 32'd4) begin
                                cov<=0;
                                row_ok<=0;
                                rows_hit<=0;
                                bad_frame<=0;
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
                            if (!cov_sat)  cov  <= cov  + 1'b1;
                            if (!pend_sat) pend <= pend + 1'b1;
                        end
                        default: st<=S_OFF0;
                    endcase
                end
            end

            if (p_eof && pkt_active) begin
                flush<=1;
                stat_pkts<=stat_pkts+1;
                if (p_good) begin
                    // Completeness gate: no failed packet this frame, every
                    // source row touched, AND all FRAME_BYTES arrived. The row
                    // bitmap alone lets a lost packet through as a "complete"
                    // row, and the hole (a BRAM word never written = 0) shows
                    // as a black stripe that survives a stopped stream.
                    if (rows_hit >= IMG_H[15:0] && bytes_ok && !bad_frame) begin
                        frame_done<=1;
                        cov<=0;
                        row_ok<=0;
                        rows_hit<=0;
                        bad_frame<=0;
                        stat_frames<=stat_frames+1;
                    end else begin
                        // short frame: keep the last good frame on screen and
                        // count it once, when the frame's last packet arrived.
                        // The EOF-cycle byte is credited here, exactly like
                        // v5.0's `cov <= cov + pkt_pay + p_valid` did.
                        if (p_valid) begin
                            if (!cov_sat)  cov  <= cov  + 1'b1;
                            if (!pend_sat) pend <= pend + 1'b1;
                        end
                        if (last_pkt) begin
                            stat_bad    <= stat_bad + 1;
                            frame_abort <= 1'b1;
                            // 行数够但字节不够的作废，rows_missed 会是 0 —— 这不是
                            // bug，是在说"缺的不是行，是最后一包的字节"。
                            rows_missed <= (rows_hit >= IMG_H[15:0]) ? 16'd0
                                              : (IMG_H[15:0] - rows_hit);
                        end
                    end
                    stat_bytes <= stat_bytes + pkt_pay + (p_valid ? 32'd1 : 32'd0);
                end else begin
                    stat_bad<=stat_bad+1;
                    frame_err<=1;
                    bad_frame<=1;   // voids the frame: see "byte accounting"
                end
                st<=S_OFF0; have_lo<=0; pkt_active<=0;
            end
        end
    end
endmodule
