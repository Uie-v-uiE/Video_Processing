`timescale 1ns/1ps
// frame_reasm — commits a frame only if EVERY source row was written this frame; missing rows
// leave old/zero pixels in DDR ⇒ a frozen frame shows black stripes that "move" while zooming.
// Clock domain: gmii_rx_clk / eth_rxc (125 MHz); all outputs are registered.
// v5.1 rewrote only the byte-count arithmetic (accept/reject decisions unchanged): the
// 3-operand 32-bit adder for `cover + pkt_pay + 1 >= FRAME_BYTES` owned all ten worst paths of
// this 125 MHz group (WNS +0.499); it is now two saturating running totals + a constant compare.
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
    // v7.6: 两个**只增不改行为**的观测口，给 link_monitor 用。frame_abort 只在「本帧字节预算已
    // 用完但验收门没过」的那一拍脉冲一次，rows_missed 与它同拍 = 还差多少源行没被写过（黑纹行数）。
    // 注意：连 FRAME_BYTES 都没凑够的短帧不脉冲 frame_abort（它没有"结束"可报），由 stall_ms 抓到。
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
    // Deliberate behaviour change vs v5.0: a running byte total cannot un-count a failed packet,
    // so a bad packet now sets this flag and the commit gate tests it (same verdict, 1 bit).
    reg        bad_frame;      // a failed packet landed in this frame

    // Byte accounting. cov  = payload bytes received for this frame, including the packet in
    // flight (what cover+pkt_pay used to add up to); pend = the same count for the in-flight
    // packet only, i.e. the byte offset its next payload byte lands on. Both saturate at
    // FRAME_BYTES, loss-free: the old code only ever asked "cov + 1 >= FRAME_BYTES", and for a
    // monotonic count that is the same question as "== FRAME_BYTES". Both are cleared at frame
    // start and at commit. `cov` is not `cover` — cover is a SystemVerilog keyword under -sv.
    localparam integer CW    = $clog2(FRAME_BYTES + 1);
    localparam [CW-1:0] SAT  = FRAME_BYTES;          // frame complete
    localparam [CW-1:0] SAT1 = FRAME_BYTES - 1;      // one byte short

    reg [CW-1:0] cov;
    reg [CW-1:0] pend;

    wire cov_sat  = (cov == SAT);
    wire cov_end  = (cov == SAT1);
    wire pend_sat = (pend == SAT);
    wire pend_end = (pend == SAT1);

    // The last byte of a packet shares its cycle with p_eof and the counters have not seen it
    // yet, so it is credited here (and only here) — same off-by-one guard v5.0 needed, one LUT deep.
    wire bytes_ok = cov_sat  | (cov_end  & p_valid);
    // the frame is over when a packet reaches FRAME_BYTES, whole or not
    wire last_pkt = pend_sat | (pend_end & p_valid);

    // per-row coverage this frame
    reg [IMG_H-1:0] row_ok;
    reg [15:0]      rows_hit;

    // byte_off → row: row = byte_off / (IMG_W*2). Must NOT use off[16:1] (a 16-bit pixel index
    // truncates ~172/300 rows → frame_done never → SRC1 black).
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
                                // #201：`wr_en` 必须和行覆盖统计吃同一个边界。原来这三行是无条件的，
                                // 而下面那个 `if (off < FRAME_BYTES)` 只管 `row_ok/rows_hit` ⇒ 发包方选的
                                // 偏移能把字写到帧缓存**之外**（`off[18:1]` 最大 131071，帧只有 153600 字节
                                // =76800 个字，越界后落在谁身上由下游 `axi_frame_saver64` 的乘法决定，而它
                                // 自己没有上界检查）。尺子：`sim/tb_reasm_bounds.v` 的 R1，改前红凭据
                                // `build/r98_201_before.txt`（越界包发了 2 次写、最大字索引 145 > 128）。
                                wr_data<={p_data,pix_lo};
                                wr_addr<=off[18:1];
                                wr_en  <=(off < FRAME_BYTES);
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
                    // Completeness gate: no failed packet this frame, every source row touched,
                    // AND all FRAME_BYTES arrived. The row bitmap alone lets a lost packet through
                    // as a "complete" row, and the hole (a never-written BRAM word = 0) survives a
                    // stopped stream as a black stripe.
                    if (rows_hit >= IMG_H[15:0] && bytes_ok && !bad_frame) begin
                        frame_done<=1;
                        cov<=0;
                        row_ok<=0;
                        rows_hit<=0;
                        bad_frame<=0;
                        stat_frames<=stat_frames+1;
                    end else begin
                        // short frame: keep the last good frame on screen and count it once, when
                        // the frame's last packet arrived. The EOF-cycle byte is credited here too.
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
