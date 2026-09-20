`timescale 1ns/1ps
// v6 乒乓提交 TB
//
// 板上实测：单帧（发完就停）任何速率都 100% 落位；连续推流时**每帧只有约 53%
// 的 64bit 字**真正写进它自己的 bank（各帧占比 53/26/21，正好是「每帧独立丢 47%」
// 的几何分布）。差别只发生在「帧提交 → 等 saver_idle → 翻 bank」这条路径上，
// 而 tb_v6_ingress_integrity 里没有这段 glue。
//
// 本 TB 把 eth_udp_video_top 的提交/翻 bank glue 原样搬过来：
//   frame_reasm → CDC(1条/拍) → axi_frame_saver64(base=sav_base)
//   frame_done 跨时钟 → switch_req/force_flush → saver_idle 时翻 bank + commit
// 连续灌 3 个完整帧，AXI 从机带可配置写延迟，按 bank 分别统计每帧落位率。
module tb_v6_pingpong;
    localparam IMG_W = 512, IMG_H = 60;            // 60 行小帧：仿真时长可控，缓冲压力比例不变
    localparam FRAME_BYTES = IMG_W * IMG_H * 2;    // 61440
    localparam PAYLOAD     = 1392;
    localparam PKTS        = (FRAME_BYTES + PAYLOAD - 1) / PAYLOAD;   // 45
    localparam WORDS       = FRAME_BYTES / 8;      // 7680
    localparam BANK0       = 32'h1000_0000;
    localparam BANK1       = 32'h1008_0000;
    localparam NFRAMES     = 2;
    localparam GAP         = 10230;    // 包间空拍 ≈ 上位机 15 MBps 限速

    // 可扫描项（+W_LAT=n +COPY_CYC=n +GAP=n）
   integer W_LAT;    // 每个 beat 占用端口的拍数：0=HP0 空手 1 拍/字，20=旧模型
    integer CP_CYC;   // 每次提交后端口被显示拷贝独占的拍数
    initial begin
        W_LAT = 0; CP_CYC = 67200;
        if ($value$plusargs("W_LAT=%d", W_LAT)) ;
        if ($value$plusargs("COPY_CYC=%d", CP_CYC)) ;
    end

    reg gmii_rx_clk = 0, axi_clk = 0, rst_n = 0, axi_rst_n = 0;
    always #4 gmii_rx_clk = ~gmii_rx_clk;
    always #5 axi_clk     = ~axi_clk;

    reg        p_valid = 0, p_eof = 0;
    reg  [7:0] p_data  = 0;
    wire       udp_sof;

    wire        fb_wr_en, reasm_flush, frame_done, frame_err;
    wire [18:0] fb_wr_addr;
    wire [15:0] fb_wr_data;
    wire [31:0] s_frames, s_pkts, s_bytes, s_bad, s_oob;

    frame_reasm #(.IMG_W(IMG_W), .IMG_H(IMG_H), .FRAME_BYTES(FRAME_BYTES)) u_re (
        .clk(gmii_rx_clk), .rst_n(rst_n),
        .p_data(p_data), .p_valid(p_valid), .p_sof(udp_sof),
        .p_eof(p_eof), .p_good(1'b1),
        .wr_en(fb_wr_en), .wr_addr(fb_wr_addr), .wr_data(fb_wr_data),
        .flush(reasm_flush), .frame_done(frame_done), .frame_err(frame_err),
        .stat_frames(s_frames), .stat_pkts(s_pkts), .stat_bytes(s_bytes),
        .stat_bad(s_bad), .stat_oob_off(s_oob)
    );

    reg in_udp_pkt;
    always @(posedge gmii_rx_clk or negedge rst_n) begin
        if (!rst_n) in_udp_pkt <= 1'b0;
        else if (p_eof)   in_udp_pkt <= 1'b0;
        else if (p_valid) in_udp_pkt <= 1'b1;
    end
    assign udp_sof = p_valid && !in_udp_pkt;

    reg         flush_pend;
    wire        fifo_full;
    wire        cdc_wr = (fb_wr_en || reasm_flush || flush_pend) && !fifo_full;
    wire [35:0] cdc_data = fb_wr_en ? {1'b0, fb_wr_addr, fb_wr_data}
                                    : {1'b1, 19'd0, 16'd0};
    always @(posedge gmii_rx_clk or negedge rst_n) begin
        if (!rst_n) flush_pend <= 1'b0;
        else if (reasm_flush && fb_wr_en && !fifo_full) flush_pend <= 1'b1;
        else if (flush_pend && !fb_wr_en && !fifo_full) flush_pend <= 1'b0;
    end

    wire [35:0] fifo_dout;
    wire        fifo_empty;
    reg         fifo_rd;
    reg  [35:0] cdc_d1;
    reg         cdc_d1_v;
    reg         sav_en, sav_flush;
    wire        sv_full;
    reg  [18:0] sav_a;
    reg  [15:0] sav_d;

    dc_fifo #(.DATA_W(36), .ADDR_W(13)) u_cdc (
        .wr_clk(gmii_rx_clk), .wr_rst_n(rst_n),
        .wr_en(cdc_wr), .wr_data(cdc_data), .wr_full(fifo_full),
        .rd_clk(axi_clk), .rd_rst_n(axi_rst_n),
        .rd_en(fifo_rd), .rd_data(fifo_dout), .rd_empty(fifo_empty)
    );

    // 丢字探针：CDC 写侧被满挡掉 = 逐 16bit 空洞（板上的拖影/黑纹）
    integer cdc_drop = 0, svf_cyc = 0;
    always @(posedge gmii_rx_clk) if (rst_n) begin
        if ((fb_wr_en || reasm_flush || flush_pend) && fifo_full) cdc_drop = cdc_drop + 1;
    end
    always @(posedge axi_clk) if (axi_rst_n) begin
        if (sv_full) svf_cyc = svf_cyc + 1;
    end

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            fifo_rd<=0; cdc_d1<=0; cdc_d1_v<=0;
            sav_en<=0; sav_flush<=0; sav_a<=0; sav_d<=0;
        end else begin
            fifo_rd  <= !fifo_empty && !sv_full;
            cdc_d1   <= fifo_dout;
            cdc_d1_v <= fifo_rd;
            sav_en    <= cdc_d1_v && !cdc_d1[35];
            sav_flush <= cdc_d1_v &&  cdc_d1[35];
            if (cdc_d1_v) begin sav_a <= cdc_d1[34:16]; sav_d <= cdc_d1[15:0]; end
        end
    end

    // ---- 提交 + 乒乓 bank（照搬 eth_udp_video_top）----
    reg frame_done_tog = 1'b0;
    always @(posedge gmii_rx_clk or negedge rst_n) begin
        if (!rst_n) frame_done_tog <= 1'b0;
        else if (frame_done) frame_done_tog <= ~frame_done_tog;
    end
    (* ASYNC_REG = "TRUE" *) reg fd0, fd1, fd2;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) {fd2,fd1,fd0} <= 3'b0;
        else {fd2,fd1,fd0} <= {fd1,fd0,frame_done_tog};
    end
    wire fd_axi = fd1 ^ fd2;

    reg bank = 1'b0;
    reg [31:0] completed_base = BANK0;
    reg commit_pulse = 1'b0, switch_req = 1'b0, force_flush = 1'b0;
    wire saver_idle;
    wire [31:0] sav_base = bank ? BANK1 : BANK0;

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            bank <= 0; completed_base <= BANK0;
            commit_pulse <= 0; switch_req <= 0; force_flush <= 0;
        end else begin
            commit_pulse <= 1'b0;
            if (fd_axi) begin switch_req <= 1; force_flush <= 1; end
            if (switch_req && saver_idle) begin
                completed_base <= sav_base;
                bank           <= ~bank;
                commit_pulse   <= 1;
                switch_req     <= 0;
                force_flush    <= 0;
            end
            if (saver_idle && !switch_req) force_flush <= 1'b0;
        end
    end

    integer commit_cnt = 0;
    // 诊断：force_flush 每次拉高持续多少 axi 拍（连续推流下若远大于排空所需，
    // 说明 bank 翻转被 saver_idle 卡住，flush 长期挂着会毁掉后续帧）
    integer ff_len = 0, ff_total = 0, ff_max = 0, ff_pulses = 0;
    reg     ff_prev = 1'b0;
    always @(posedge axi_clk) begin
        if (force_flush && !ff_prev) ff_len = 0;
        if (force_flush) ff_len = ff_len + 1;
        if (!force_flush && ff_prev) begin
            ff_total  = ff_total + ff_len;
            if (ff_len > ff_max) ff_max = ff_len;
            ff_pulses = ff_pulses + 1;
        end
        ff_prev = force_flush;
    end
    reg [31:0] commit_bank [0:NFRAMES];
    integer    commit_idx  = 0;
    always @(posedge axi_clk) if (commit_pulse) begin
        commit_cnt = commit_cnt + 1;
        if (commit_idx < NFRAMES) begin
            commit_bank[commit_idx] = completed_base;
            commit_idx = commit_idx + 1;
        end
        $display("COMMIT %0d completed_base=%h (bank was %b)",
                 commit_cnt, completed_base, bank);
    end

    wire [31:0] m_awaddr;
    wire [7:0]  m_awlen;
    wire [2:0]  m_awsize;
    wire [1:0]  m_awburst;
    wire        m_awvalid;
    reg         m_awready;
    wire [63:0] m_wdata;
    wire [7:0]  m_wstrb;
    wire        m_wlast, m_wvalid;
    reg         m_wready, m_bvalid;
    wire        m_bready;

    axi_frame_saver64 #(.BASE_ADDR(BANK0)) u_sv (
        .clk(axi_clk), .rst_n(axi_rst_n), .enable(1'b1),
        .base_addr(sav_base),
        .wr_en(sav_en), .wr_addr(sav_a), .wr_data(sav_d),
        .flush(sav_flush | force_flush),
        .fifo_full(sv_full), .idle(saver_idle), .busy(),
        .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen), .m_axi_awsize(m_awsize),
        .m_axi_awburst(m_awburst), .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb), .m_axi_wlast(m_wlast),
        .m_axi_wvalid(m_wvalid), .m_axi_wready(m_wready),
        .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready)
    );

    // ---- 并发显示拷贝的等效建模 ----
    // 真实系统里 axi_frame_writer_gated 在 V-blank 用同一条 HP0 读整帧。这里不重做
    // 读引擎，而是等效成「每次提交后端口被读独占 CP_CYC 拍」：期间 awready/wready
    // 拉低 ⇒ 打包器积压 ⇒ FIFO 溢出丢字。扫 CP_CYC 即可标定每次提交毁掉多少帧。
    integer cp_dn = 0;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n)        cp_dn <= 0;
        else if (commit_pulse) cp_dn <= CP_CYC;
        else if (cp_dn > 0)    cp_dn <= cp_dn - 1;
    end
    wire port_taken = (cp_dn > 0);

    // ---- 带端口占用模型的 AXI3 从机 + 两个 bank 的内存模型 ----
    // AW/W 同时接收（DUT 是同拍挂出、各自保持到被接收），B 用移位管道返回，
    // 因此从机可以承载多个在途写而不会把响应弄丢（旧模型只有 1 个 B 寄存器）。
    reg [63:0] mem0 [0:WORDS-1];
    reg [63:0] mem1 [0:WORDS-1];
    integer bwait, wr0, wr1;
    reg [31:0] bsh;
    reg [31:0] abuf;
    wire svc      = (bwait == 0) && !port_taken;
    // 必须用**寄存器版**的 ready 做握手：用组合的 svc 会把同一个 beat 数两次
    // （ready 晚一拍才到 DUT），于是多发一个 B ⇒ DUT 的 outst 反向减到回绕 ⇒ 死锁
    wire new_beat = m_awvalid && m_wvalid && m_awready && m_wready;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            m_awready <= 1; m_wready <= 1; m_bvalid <= 0;
            bwait = 0; abuf = 0; wr0 = 0; wr1 = 0; bsh = 0;
        end else begin
            if (bwait > 0) bwait = bwait - 1;
            m_awready <= svc;
            m_wready  <= svc;
            if (new_beat) begin
                abuf <= m_awaddr;
                if (m_awaddr < BANK1) begin mem0[(m_awaddr - BANK0) >> 3] <= m_wdata; wr0 = wr0 + 1; end
                else                  begin mem1[(m_awaddr - BANK1) >> 3] <= m_wdata; wr1 = wr1 + 1; end
                if (wr0 + wr1 < 4) $display("  DBG axi wr#%0d addr=%h data=%h", wr0+wr1, m_awaddr, m_wdata);
                bwait <= W_LAT;
            end
            m_bvalid <= bsh[0];
            bsh <= (bsh >> 1) | (new_beat ? (32'd1 << 3) : 32'd0);
        end
    end

    // ---- 激励 ----
    task send_byte;
        input [7:0] b; input sof; input eof;
        begin
            @(negedge gmii_rx_clk);
            p_data = b; p_valid = 1; p_eof = eof;
            if (sof) begin end
        end
    endtask

    integer f, pi, bi, errors;
    reg [31:0] off0, pkt_bytes;
    reg [15:0] want;
    reg [63:0] expw, gotw;
    integer hit0, hit1, other, firstmiss;

    task send_frame;
        input integer fn;
        begin
            for (pi = 0; pi < PKTS; pi = pi + 1) begin
                off0 = pi * PAYLOAD;
                pkt_bytes = ((FRAME_BYTES - off0) < PAYLOAD) ? (FRAME_BYTES - off0) : PAYLOAD;
                send_byte(off0[7:0],   1'b1, 1'b0);
                send_byte(off0[15:8],  1'b0, 1'b0);
                send_byte(off0[23:16], 1'b0, 1'b0);
                send_byte(off0[31:24], 1'b0, 1'b0);
                for (bi = 0; bi < pkt_bytes; bi = bi + 1) begin
                    want = (((off0 + bi) >> 3) + fn[15:0]) & 16'hffff;  // 字号 + 帧号
                    if (bi[0]) send_byte(want[15:8], 1'b0, (bi == pkt_bytes-1));
                    else       send_byte(want[7:0],  1'b0, (bi == pkt_bytes-1));
                end
                @(negedge gmii_rx_clk);
                p_valid = 0; p_eof = 0;
                repeat (GAP) @(negedge gmii_rx_clk);
            end
        end
    endtask

    // 统计某个 bank 里属于帧 fn 的字有多少
    task count_bank;
        input integer fn;
        input [31:0]  base;
        begin
            hit0 = 0; hit1 = 0; other = 0; firstmiss = -1;
            for (pi = 0; pi < WORDS; pi = pi + 1) begin
                want = (pi[15:0] + fn[15:0]) & 16'hffff;
                expw = {want, want, want, want};
                gotw = (base == BANK0) ? mem0[pi] : mem1[pi];
                if (gotw === expw) hit0 = hit0 + 1;
                else begin
                    if (((gotw[15:0] - pi[15:0]) & 16'hffff) == fn[15:0] ||
                        ((gotw[31:16] - pi[15:0]) & 16'hffff) == fn[15:0] ||
                        ((gotw[47:32] - pi[15:0]) & 16'hffff) == fn[15:0] ||
                        ((gotw[63:48] - pi[15:0]) & 16'hffff) == fn[15:0]) hit1 = hit1 + 1;
                    else other = other + 1;
                    if (firstmiss < 0) firstmiss = pi;
                end
            end
        end
    endtask

    initial begin
        errors = 0;
        for (pi = 0; pi < WORDS; pi = pi + 1) begin mem0[pi] = 64'h0; mem1[pi] = 64'h0; end
        rst_n = 0; axi_rst_n = 0;
        repeat (20) @(negedge gmii_rx_clk);
        rst_n = 1; axi_rst_n = 1;
        repeat (20) @(negedge gmii_rx_clk);

        for (f = 0; f < NFRAMES; f = f + 1) begin
            send_frame(f);
            begin : drain
                integer t;
                t = 0;
                while ((!saver_idle || switch_req) && t < 3000000) begin
                    @(posedge axi_clk); t = t + 1;
                end
                if (t >= 2999999) $display("  STUCK dump: outst=%0d rptr=%0d wptr=%0d aw_wait=%b w_wait=%b busy=%b cur_dirty=%b cp_dn=%0d bready=%b bvalid=%b",
                     u_sv.outst, u_sv.rptr, u_sv.wptr, u_sv.aw_wait, u_sv.w_wait,
                     u_sv.busy, u_sv.cur_dirty, cp_dn, m_bready, m_bvalid);
                repeat (20000) @(posedge axi_clk);
                $display("  drain waited %0d axi cycles (idle=%0b switch_req=%0b)",
                         t, saver_idle, switch_req);
            end
            $display("---- after frame %0d: commits=%0d frames_done=%0d pkts=%0d bytes=%0d bad=%0d ----",
                     f, commit_cnt, s_frames, s_pkts, s_bytes, s_bad);
            count_bank(f, BANK0);
            $display("  frame%0d in BANK0: exact=%0d/%0d (%0d%%) partial=%0d none=%0d firstmiss=%0d",
                     f, hit0, WORDS, hit0*100/WORDS, hit1, other, firstmiss);
            $display("    BANK0[0..3]=%h %h %h %h   [mid]=%h", mem0[0], mem0[1], mem0[2], mem0[3], mem0[WORDS/2]);
            count_bank(f, BANK1);
            $display("  frame%0d in BANK1: exact=%0d/%0d (%0d%%) partial=%0d none=%0d firstmiss=%0d",
                     f, hit0, WORDS, hit0*100/WORDS, hit1, other, firstmiss);
        end

        $display("force_flush: pulses=%0d total_cycles=%0d max=%0d (1 帧=%0d 拍)",
                 ff_pulses, ff_total, ff_max, FRAME_BYTES/8*(W_LAT+1));
        $display("探针: cdc_drop(16bit字)=%0d  packer_full 持续=%0d 拍  beats 收到=%0d/%0d W_LAT=%0d COPY_CYC=%0d",
                 cdc_drop, svf_cyc, wr0 + wr1, WORDS*NFRAMES, W_LAT, CP_CYC);
        if (commit_cnt != NFRAMES) begin
            $display("FAIL commits=%0d expected=%0d", commit_cnt, NFRAMES);
            errors = errors + 1;
        end
        count_bank(NFRAMES-1, commit_bank[NFRAMES-1]);
        $display("LAST frame%0d in its committed bank 0x%h: exact=%0d/%0d (%0d%%)",
                 NFRAMES-1, commit_bank[NFRAMES-1], hit0, WORDS, hit0*100/WORDS);
        if (hit0 != WORDS) begin
            $display("FAIL last frame did not fully land in its own bank (partial=%0d none=%0d)",
                     hit1, other);
            errors = errors + 1;
        end else $display("PASS last frame fully landed");

        if (errors == 0) $display("PASS tb_v6_pingpong");
        else $display("FAIL tb_v6_pingpong errors=%0d", errors);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("FAIL tb_v6_pingpong timeout");
        $finish;
    end
endmodule
