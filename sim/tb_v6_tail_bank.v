`timescale 1ns/1ps
// v6.4 遗留问题「帧尾 4 字节（最后 2 个像素）偶发丢失」的复现 + 回归 TB。
//
// 机理（R03 定位）：换页判据只看打包器空（saver_idle），而打包器的 idle 对
// 8192 深的 CDC 和它后面的两级读流水**完全不可见**。当打包器满过一轮（sv_full
// 反压）后恰好在帧的最后一个字中间放开，本帧最后两个 16bit lane 还排在 CDC 里；
// 此时 frame_done 已同步到 axi 域并拉起 force_flush，把已到达的半截字推走 ⇒
// 打包器排空 ⇒ saver_idle ⇒ 旧逻辑翻 bank。随后那 2 个 lane 进打包器时
// pack_base 已经换 bank ⇒ 它们被写进**下一帧**的缓冲区，刚提交的那块内存的
// 帧尾 4 字节停在旧值/0 上。相位相关 ⇒ 板上 8 次见到 4 次、与速率无关。
//
// 同一条激励同时灌进两条独立链做 A/B：
//   u_old = ddr_bank_commit #(.TAIL_GUARD(1'b0))   v6.4 行为
//   u_new = ddr_bank_commit #(.TAIL_GUARD(1'b1))   修复后
// 判据是双向的：旧链**必须**复现丢尾（否则激励退化、TB 失去意义，判 FAIL），
// 新链**必须**整帧完整（否则修复无效，判 FAIL）。
module tb_v6_tail_bank;

    localparam BANK0 = 32'h1000_0000;
    localparam BANK1 = 32'h1008_0000;
    localparam WORDS = 8;                    // 每帧 8 个 64bit 字，便于逐拍控制

    reg gmii_clk = 1'b0, axi_clk = 1'b0;
    reg rst_n = 1'b0, axi_rst_n = 1'b0;
    always #4  gmii_clk = ~gmii_clk;          // 125 MHz
    always #5  axi_clk  = ~axi_clk;           // 100 MHz

    // ---- 共享激励：gmii 域的「frame_reasm 输出口」----
    reg         s_wr_en   = 1'b0;
    reg  [18:0] s_wr_addr = 19'd0;
    reg  [15:0] s_wr_data = 16'd0;
    reg         s_flush   = 1'b0;
    reg         s_frame_done = 1'b0;
    reg         rd_allow   = 1'b1;

    wire [31:0] old_base, new_base;   // 两条链各自提交的 bank

    tail_lane #(.GUARD(1'b0)) u_old (
        .gmii_clk(gmii_clk), .axi_clk(axi_clk), .rst_n(rst_n), .axi_rst_n(axi_rst_n),
        .s_wr_en(s_wr_en), .s_wr_addr(s_wr_addr), .s_wr_data(s_wr_data),
        .s_flush(s_flush), .s_frame_done(s_frame_done), .rd_allow(rd_allow),
        .completed_base(old_base), .commit_pulse());
    tail_lane #(.GUARD(1'b1)) u_new (
        .gmii_clk(gmii_clk), .axi_clk(axi_clk), .rst_n(rst_n), .axi_rst_n(axi_rst_n),
        .s_wr_en(s_wr_en), .s_wr_addr(s_wr_addr), .s_wr_data(s_wr_data),
        .s_flush(s_flush), .s_frame_done(s_frame_done), .rd_allow(rd_allow),
        .completed_base(new_base), .commit_pulse());

    // ---- 激励任务 ----
    task push16;                             // 一个 16bit lane 写
        input [18:0] a; input [15:0] d;
        begin
            @(negedge gmii_clk); s_wr_en = 1; s_wr_addr = a; s_wr_data = d;
            @(negedge gmii_clk); s_wr_en = 0;
        end
    endtask

    task push_flush;                         // 包尾 flush 标记
        begin
            @(negedge gmii_clk); s_flush = 1;
            @(negedge gmii_clk); s_flush = 0;
        end
    endtask

    integer w, lane, errors;
    reg [15:0] want;

    // cut_lane < 0 ⇒ 整帧一次送完；否则在最后一字的第 cut_lane 个 lane 之后停读，
    // 把剩下的 lane 和 flush 标记留在 CDC 里（正是板上 sv_full 反压放开的位置）。
    task send_frame;
        input integer fn; input integer cut_lane;
        begin
            rd_allow = 1'b1;
            for (w = 0; w < WORDS; w = w + 1)
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    want = (w[15:0] + fn[15:0]) & 16'hffff;
                    case (lane)
                        0: push16(w*4 + 0, want);
                        1: push16(w*4 + 1, want);
                        2: push16(w*4 + 2, want);
                        default: push16(w*4 + 3, want);
                    endcase
                    if (w == WORDS-1 && lane == cut_lane) rd_allow = 1'b0;
                end
            push_flush;
            @(negedge gmii_clk); s_frame_done = 1;
            @(negedge gmii_clk); s_frame_done = 0;
        end
    endtask

    // ---- 判据：直接按层次引用读两条链的 bank 内存 ----
    reg [63:0] g_old, g_new;
    integer    hit_old, hit_new, first_bad;
    reg [15:0] ib;

    task check_frame;
        input integer fn;
        begin
            hit_old = 0; hit_new = 0; first_bad = -1;
            for (w = 0; w < WORDS; w = w + 1) begin
                want = (w[15:0] + fn[15:0]) & 16'hffff;
                ib   = (old_base == BANK1) ? (WORDS + w) : w;
                g_old = u_old.mem[ib];
                ib   = (new_base == BANK1) ? (WORDS + w) : w;
                g_new = u_new.mem[ib];
                if (g_old === {want, want, want, want}) hit_old = hit_old + 1;
                else if (first_bad < 0) first_bad = w;
                if (g_new === {want, want, want, want}) hit_new = hit_new + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        for (w = 0; w < 2*WORDS; w = w + 1) begin
            u_old.mem[w] = 64'h0;  u_new.mem[w] = 64'h0;
        end
        repeat (10) @(negedge gmii_clk);
        rst_n = 1; axi_rst_n = 1;
        repeat (20) @(negedge gmii_clk);

        // 帧 0：完整走一遍，两条链都应正常提交
        send_frame(0, -1);
        repeat (5000) @(posedge axi_clk);
        check_frame(0);
        $display("frame0: commits old=%0d new=%0d base old=%h new=%h 完整 old=%0d/%0d new=%0d/%0d",
                 u_old.commit_cnt, u_new.commit_cnt, old_base, new_base,
                 hit_old, WORDS, hit_new, WORDS);
        if (hit_old != WORDS || hit_new != WORDS) begin
            $display("FAIL frame0 基线就没落位（old=%0d new=%0d）", hit_old, hit_new);
            errors = errors + 1;
        end

        // 帧 1：最后一个字只交付 lane0/lane1 就停读，随后 frame_done 到达
        send_frame(1, 1);
        repeat (3000) @(posedge axi_clk);
        $display("停读期间: commits old=%0d new=%0d  （old 若已提前翻页则 new 仍是 1）",
                 u_old.commit_cnt, u_new.commit_cnt);

        rd_allow = 1'b1;                       // 反压解除，滞留的 lane 与标记继续走
        repeat (6000) @(posedge axi_clk);

        check_frame(1);
        if ($test$plusargs("TRACE")) for (w=0;w<WORDS;w=w+1) $display("MEM old[%0d]=%h  new[%0d]=%h", w, u_old.mem[w], w, u_new.mem[w]);
        $display("frame1: 完整 old=%0d/%0d (first_bad_word=%0d)  new=%0d/%0d",
                 hit_old, WORDS, first_bad, hit_new, WORDS);
        $display("  old: base=%h word7=%h%h%h%h", old_base,
                 g_old[63:48], g_old[47:32], g_old[31:16], g_old[15:0]);
        $display("  new: base=%h word7=%h%h%h%h", new_base,
                 g_new[63:48], g_new[47:32], g_new[31:16], g_new[15:0]);

        if (hit_old == WORDS) begin
            $display("FAIL 复现失效：TAIL_GUARD=0 的旧链帧尾竟然完整，激励没触发机理");
            errors = errors + 1;
        end else $display("  OK 旧链复现出帧尾丢失：缺 %0d 个字", WORDS - hit_old);

        if (hit_new != WORDS) begin
            $display("FAIL 修复无效：TAIL_GUARD=1 的新链仍有 %0d/%0d 个字不完整",
                     WORDS - hit_new, WORDS);
            errors = errors + 1;
        end else $display("  OK 新链整帧完整落在自己的 bank 0x%h", new_base);

        if (u_new.commit_cnt != 2) begin
            $display("FAIL 新链提交 %0d 次（期望 2），换页被过度延迟", u_new.commit_cnt);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS tb_v6_tail_bank");
        else             $display("FAIL tb_v6_tail_bank errors=%0d", errors);
        $finish;
    end

    initial begin
        #80_000_000;
        $display("FAIL tb_v6_tail_bank timeout");
        $finish;
    end
endmodule

// ---------------------------------------------------------------------------
// 一条完整入包链：CDC(dc_fifo) → axi_frame_saver64 → ddr_bank_commit → AXI3 从机
// ---------------------------------------------------------------------------
module tail_lane #(
    parameter GUARD = 1'b1
)(
    input  wire        gmii_clk,
    input  wire        axi_clk,
    input  wire        rst_n,
    input  wire        axi_rst_n,
    input  wire        s_wr_en,
    input  wire [18:0] s_wr_addr,
    input  wire [15:0] s_wr_data,
    input  wire        s_flush,
    input  wire        s_frame_done,
    input  wire        rd_allow,
    output wire [31:0] completed_base,
    output wire        commit_pulse
);
    localparam BANK0 = 32'h1000_0000;
    localparam BANK1 = 32'h1008_0000;
    localparam WORDS = 8;

    reg  flush_pend;
    wire fifo_full, fifo_empty, sv_full;
    wire [35:0] fifo_dout;
    reg         fifo_rd;
    reg  [35:0] cdc_d1;
    reg         cdc_d1_v;
    reg         sav_en, sav_flush;
    reg  [18:0] sav_a;
    reg  [15:0] sav_d;

    wire cdc_wr = (s_wr_en || s_flush || flush_pend) && !fifo_full;
    wire [35:0] cdc_data = s_wr_en ? {1'b0, s_wr_addr, s_wr_data}
                                   : {1'b1, 19'd0, 16'd0};

    always @(posedge gmii_clk or negedge rst_n) begin
        if (!rst_n) flush_pend <= 1'b0;
        else if (s_flush && s_wr_en && !fifo_full) flush_pend <= 1'b1;
        else if (flush_pend && !s_wr_en && !fifo_full) flush_pend <= 1'b0;
    end

    dc_fifo #(.DATA_W(36), .ADDR_W(13)) u_cdc (
        .wr_clk(gmii_clk), .wr_rst_n(rst_n),
        .wr_en(cdc_wr), .wr_data(cdc_data), .wr_full(fifo_full),
        .rd_clk(axi_clk), .rd_rst_n(axi_rst_n),
        .rd_en(fifo_rd), .rd_data(fifo_dout), .rd_empty(fifo_empty)
    );

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            fifo_rd <= 0; cdc_d1 <= 0; cdc_d1_v <= 0;
            sav_en <= 0; sav_flush <= 0; sav_a <= 0; sav_d <= 0;
        end else begin
            fifo_rd  <= !fifo_empty && !sv_full && rd_allow;
            cdc_d1   <= fifo_dout;
            cdc_d1_v <= fifo_rd;
            sav_en    <= cdc_d1_v && !cdc_d1[35];
            sav_flush <= cdc_d1_v &&  cdc_d1[35];
            if (cdc_d1_v) begin sav_a <= cdc_d1[34:16]; sav_d <= cdc_d1[15:0]; end
        end
    end

    wire        saver_idle;
    wire [31:0] sav_base;
    wire        pack_flush;

    ddr_bank_commit #(.BANK0(BANK0), .BANK1(BANK1), .TAIL_GUARD(GUARD)) u_commit (
        .gmii_clk(gmii_clk), .axi_clk(axi_clk), .rst_n(rst_n), .axi_rst_n(axi_rst_n),
        .frame_done(s_frame_done), .saver_idle(saver_idle),
        .sav_base(sav_base), .pack_flush(pack_flush),
        .cdc_empty(fifo_empty), .cdc_rd(fifo_rd), .cdc_d1_v(cdc_d1_v),
        .sav_en(sav_en), .sav_flush(sav_flush),
        .completed_base(completed_base), .commit_pulse(commit_pulse),
        .switch_req(), .force_flush()
    );

    // ---- AXI3 从机 + 两 bank 内存模型（WSTRB 逐字节生效，缺这个就看不见 lane 级 bug）----
    reg [63:0] mem [0:2*WORDS-1];
    reg        awready, wready;
    reg  [31:0] awaddr_r;
    reg  [3:0]  bpipe;
    reg  [15:0] idx;

    wire        awvalid, wvalid, wlast, bready, bvalid;
    wire [2:0]  awsize;
    wire [31:0] awaddr;
    wire [7:0]  awlen, wstrb;
    wire [63:0] wdata;

    axi_frame_saver64 #(.BASE_ADDR(BANK0)) u_sv (
        .clk(axi_clk), .rst_n(axi_rst_n), .enable(1'b1), .base_addr(sav_base),
        .wr_en(sav_en), .wr_addr(sav_a), .wr_data(sav_d), .flush(pack_flush),
        .fifo_full(sv_full), .idle(saver_idle), .busy(),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen),
        .m_axi_awsize(awsize), .m_axi_awburst(),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    // AW/W 同拍挂出，所以本拍的地址要用**当拍**的 awaddr（用寄存器版会晚一拍，
    // 整帧数据就错位成「只有 word0 对」——第一版栽过这个坑）。
    wire [31:0] cur_addr  = (awvalid && awready) ? awaddr : awaddr_r;
    wire [31:0] beat_base = (cur_addr >= BANK1) ? BANK1 : BANK0;
    wire [31:0] beat_off  = (cur_addr - beat_base) >> 3;
    wire        beat_bank1 = (cur_addr >= BANK1);

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            awready <= 1'b1; wready <= 1'b1; awaddr_r <= 32'd0; bpipe <= 4'd0;
        end else begin
            if (awvalid && awready) awaddr_r <= awaddr;
            if (wvalid && wready) begin
                if ($test$plusargs("TRACE")) $display("BEAT %0t off=%h idx=%0d wdata=%h wstrb=%h cur=%h", $time, cur_addr-beat_base, ((cur_addr>=BANK1)?WORDS:0)+((cur_addr-beat_base)>>3), wdata, wstrb, cur_addr);
                idx   = (beat_bank1 ? WORDS[15:0] : 16'd0) + beat_off[15:0];
                if (wstrb[1:0] == 2'b11) mem[idx][15:0]  <= wdata[15:0];
                if (wstrb[3:2] == 2'b11) mem[idx][31:16] <= wdata[31:16];
                if (wstrb[5:4] == 2'b11) mem[idx][47:32] <= wdata[47:32];
                if (wstrb[7:6] == 2'b11) mem[idx][63:48] <= wdata[63:48];
                bpipe <= {bpipe[2:0], 1'b1};
            end else bpipe <= {bpipe[2:0], 1'b0};
        end
    end
    assign bvalid = bpipe[3];
    assign bready = 1'b1;

    reg [31:0] commit_cnt_r;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) commit_cnt_r <= 32'd0;
        else if (commit_pulse) commit_cnt_r <= commit_cnt_r + 32'd1;
    end
    wire [31:0] commit_cnt = commit_cnt_r;
endmodule
