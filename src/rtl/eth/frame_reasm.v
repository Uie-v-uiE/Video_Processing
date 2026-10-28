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
    // per-row coverage this frame, stored in 5 x 64-bit banks (IMG_H=300 <= 320).
    // Why banks: the "this byte starts a new row" term used to be the CE driver of ALL 300
    // coverage FFs plus the 16 rows_hit FFs (r106 post-route report: fo=316, and that last hop
    // alone cost 1.980 ns of the 6.879 ns data path, route share 81.2 %). Each bank now takes
    // <= 64 loads and the row counter's enable takes 16. Bound: 5 x 64 = 320 rows -- a bigger
    // IMG_H must add banks AND widen rbank; the guard above endmodule says so in simulation.
    reg [63:0] rok0, rok1, rok2, rok3, rok4;
    reg [15:0]      rows_hit;

    // byte_off → row: row = byte_off / (IMG_W*2). Must NOT use off[16:1] (a 16-bit pixel index
    // truncates ~172/300 rows → frame_done never → SRC1 black).
    localparam integer ROW_STRIDE = IMG_W * 2;
    wire [31:0] row_idx = off / ROW_STRIDE;
    wire [8:0]  ridx  = row_idx[8:0];

    // 行覆盖流水（r135）：原来 off → 64:1 bank 读 → 5:1 bank 选 → 独热移位 → rows_hit CE
    // 全在同一个 125 MHz 拍里，fix3 的 WNS 就是这条（off_reg[11] 扇出 132、6 级、7.341 ns）。
    // 现在 word 写入时只把 ridx 打进一拍，下一拍再查/置位：off 只驱动一个 9 位寄存器，
    // 位图访问从寄存器出发，路径被切掉最长的一段。语义不变（同一行连续字：第一字置位后
    // 第二字下一拍已经读得到 1；跨帧时 p_eof / 帧头清位同时把在途的 cov_we 杀掉）。
    reg [8:0] cov_ridx;
    reg       cov_we;
    // r152：`|bank_one`（= 这一行本帧第一次出现）原来是 rows_hit 16 个 CE 的组合驱动。
    // r151 布线后它是最差内部路径（wr_addr_reg[10] → rows_hit_reg[*]/CE，6.311 ns，
    // 其中 route 4.826 ns、扇出 16），因为 bank 读的 5:1 选择 + 64:1 位选 + 行号比较
    // 全压在一个 CE 上。这里只把“是否新行”寄存一拍，rows_hit 的加一改由这个单 bit
    // 触发器驱动；bank 的置位仍在原拍完成，所以同一行连续字的第二次读已经看得到 1，
    // 不会重复计数。代价是 rows_hit 比原来晚一拍更新，而 frame_done 判的是“整行早已
    // 写过的行数”，最后一行在帧尾之前至少已收到几百个字，晚一拍不影响判定。
    reg       cov_new;
    // r155：stat_bad 的 32 位 CE 原来由 rows_hit/cov/bad_frame 的比较锥直接驱动，
    // r154 布线后它是 125 MHz 域最差路径（rows_hit_reg[5] → stat_bad_reg[28]/CE，
    // 5 级逻辑、route 5.3 ns）。统计计数器晚一拍没有功能影响，所以把“这一拍要不要
    // 加一”寄存成单 bit，CE 由它驱动；比较锥只剩一个负载，走线不再分叉到 32 位。
    reg       stat_bad_inc;
    // A9: 4 ms idle timer with a 12-bit prescaler. It drives one bit into the
    // header-clear cone; the counters stay out of the byte/row path.
    reg [11:0] idle_div;
    reg [6:0]  idle_cnt;
    reg        idle_clear;
    reg        gap_pending;

    wire [2:0]  rbank = cov_ridx[8:6];
    wire [5:0]  roff  = cov_ridx[5:0];
    wire        row_covered =
          (rbank == 3'd0) ? rok0[roff]
        : (rbank == 3'd1) ? rok1[roff]
        : (rbank == 3'd2) ? rok2[roff]
        : (rbank == 3'd3) ? rok3[roff]
        :                    rok4[roff];
    wire        new_row_w = (cov_ridx < IMG_H) && !row_covered;
    // rbank<=4 由 cov_ridx<IMG_H(=300) 保证（ridx<=299 ⇒ rbank=ridx[8:6]<=4）。
    wire [4:0]  bank_one  = new_row_w ? (5'b00001 << rbank) : 5'b00000;

    // 4-byte little-endian offset, complete in the S_OFF3 cycle
    wire [31:0] hdr = {p_data, off[23:0]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st<=S_OFF0; off<=0; pix_lo<=0; have_lo<=0;
            pkt_pay<=0; pkt_active<=0; cov<=0; pend<=0; bad_frame<=0;
            cov_ridx<=0; cov_we<=0; cov_new<=0; stat_bad_inc<=0; gap_pending<=0;
            wr_en<=0; wr_addr<=0; wr_data<=0; flush<=0;
            frame_done<=0; frame_err<=0;
            frame_abort<=0; rows_missed<=0;
            stat_frames<=0; stat_pkts<=0; stat_bytes<=0;
            stat_bad<=0; stat_oob_off<=0;
            rok0<=0; rok1<=0; rok2<=0; rok3<=0; rok4<=0; rows_hit<=0;
        end else begin
            wr_en<=0; flush<=0; frame_done<=0; frame_err<=0; frame_abort<=0;
            if (stat_bad_inc) stat_bad <= stat_bad + 1'b1;
            stat_bad_inc <= 1'b0;
            if (idle_clear) gap_pending <= 1'b1;

            // 上一拍 word 的行覆盖（流水级）。跨帧清位与 p_eof 在下面把 cov_we 清掉，
            // 所以在途的旧帧更新不会落到新帧的 rows_hit / rok 上。
            if (cov_we) begin
                cov_new <= (cov_ridx < IMG_H) && !row_covered;
                if (cov_ridx < IMG_H) begin
                    if (bank_one[0]) rok0[roff] <= 1'b1;
                    if (bank_one[1]) rok1[roff] <= 1'b1;
                    if (bank_one[2]) rok2[roff] <= 1'b1;
                    if (bank_one[3]) rok3[roff] <= 1'b1;
                    if (bank_one[4]) rok4[roff] <= 1'b1;
                end
            end else cov_new <= 1'b0;
            if (cov_new) rows_hit <= rows_hit + 16'd1;

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
                            if (hdr < 32'd4 || gap_pending) begin
                                cov<=0;
                                rok0<=0; rok1<=0; rok2<=0; rok3<=0; rok4<=0;
                                rows_hit<=0;
                                bad_frame<=0;
                                gap_pending<=0;
                                cov_we<=0;
                                // 旧帧最后一个字可能在这一拍正好算出 cov_new；新帧从 0 行开始时
                                // 必须把它一起清掉，否则下一拍会给新帧凭空加 1 行（#152 回归）。
                                cov_new<=0;
                            end
                        end
                        S_DATA: begin
                            if (!have_lo) begin
                                pix_lo<=p_data; have_lo<=1;
                            end else begin
                                // #201：`wr_en` 必须和行覆盖统计吃同一个边界。原来这三行是无条件的，
                                // 而下面那个 `if (off < FRAME_BYTES)` 只管 `rok0..rok4/rows_hit` ⇒ 发包方选的
                                // 偏移能把字写到帧缓存**之外**（`off[18:1]` 最大 131071，帧只有 153600 字节
                                // =76800 个字，越界后落在谁身上由下游 `axi_frame_saver64` 的乘法决定，而它
                                // 自己没有上界检查）。尺子：`sim/tb_reasm_bounds.v` 的 R1，改前红凭据
                                // `scripts/r98_201_before.txt`（越界包发了 2 次写、最大字索引 145 > 128）。
                                wr_data<={p_data,pix_lo};
                                wr_addr<=off[18:1];
                                wr_en  <=(off < FRAME_BYTES);
                                cov_ridx <= ridx;
                                cov_we   <= (off < FRAME_BYTES);
                                if (off >= FRAME_BYTES)
                                    stat_oob_off<=stat_oob_off+1;
                                if (off >= FRAME_BYTES)
                                    bad_frame<=1'b1;   // 越界包把本帧作废，别让字节账把它拼成完整帧
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
                cov_we<=0;
                stat_pkts<=stat_pkts+1;
                if (p_good) begin
                    // Completeness gate: no failed packet this frame, every source row touched,
                    // AND all FRAME_BYTES arrived. The row bitmap alone lets a lost packet through
                    // as a "complete" row, and the hole (a never-written BRAM word = 0) survives a
                    // stopped stream as a black stripe.
                    if (rows_hit >= IMG_H[15:0] && bytes_ok && !bad_frame) begin
                        frame_done<=1;
                        cov<=0;
                        rok0<=0; rok1<=0; rok2<=0; rok3<=0; rok4<=0;
                        rows_hit<=0;
                        cov_new<=0;   // 只在本帧已提交、rows_hit 正要清零时杀掉在途脉冲
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
                            stat_bad_inc <= 1'b1;
                            frame_abort <= 1'b1;
                            // 行数够但字节不够的作废，rows_missed 会是 0 —— 这不是
                            // bug，是在说"缺的不是行，是最后一包的字节"。
                            rows_missed <= (rows_hit >= IMG_H[15:0]) ? 16'd0
                                              : (IMG_H[15:0] - rows_hit);
                            // 作废帧不把字节账和行位图留给下一帧；否则下一帧丢首包时
                            // 两帧的账会拼在一起（A9 的另一条入口）。
                            cov<=0;
                            rok0<=0; rok1<=0; rok2<=0; rok3<=0; rok4<=0;
                            rows_hit<=0;
                            bad_frame<=0;
                            cov_we<=0;
                            cov_new<=0;
                            gap_pending<=0;
                        end
                    end
                    stat_bytes <= stat_bytes + pkt_pay + (p_valid ? 32'd1 : 32'd0);
                end else begin
                    stat_bad_inc<=1'b1;
                    frame_err<=1;
                    bad_frame<=1;   // voids the frame: see "byte accounting"
                end
                st<=S_OFF0; have_lo<=0; pkt_active<=0;
            end
        end
    end
// 界（#146 那一族的写法）：bank 数写死在 5。IMG_H 一旦超过 5*64，行覆盖就记丢、
// frame_done 永不成立（画面是黑纹而不是报错）。台架里当场喊；综合忽略 initial。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        idle_div<=0; idle_cnt<=0; idle_clear<=0;
    end else begin
        idle_clear<=1'b0;
        if (p_valid) begin
            idle_div<=0; idle_cnt<=0;
        end else if (idle_div == 12'hFFF) begin
            idle_div<=0;
            if (idle_cnt == 7'd123) begin idle_cnt<=0; idle_clear<=1'b1; end
            else idle_cnt<=idle_cnt+1'b1;
        end else idle_div<=idle_div+1'b1;
    end
end

initial begin
    if (IMG_H > 5 * 64)
        $error("frame_reasm: IMG_H=%0d exceeds 5 x 64 row-coverage banks (320); add banks and widen rbank", IMG_H);
end

endmodule
