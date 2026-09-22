`timescale 1ns/1ps
// tb_link_monitor — V7.6 (P0-A) 链路健康自诊断引擎的验收。
//
// 四条必须成立、**不成立就会误报平安**的性质：
//   A 反例判据：挡住 CDC 写口（fifo_full 拉住）⇒ drop_words 必须非 0；
//     反向也要成立：没有 full 时必须恒 0，否则这个数字是噪声。
//   B 缺一个**中间包**（最后一个包到了、行没凑齐）⇒ frame_abort 恰好一次、
//     rows_missed=1，并出现在快照 lane1/lane2 里。
//   C 断流之后快照必须**继续刷新**，否则 stall_ms 冻在最后一个值上，
//     OSD 会把"线被拔了"显示成"一切正常"。
//   D 第一个 frame_done 只建立基准，不得把"上电到现在"当成帧间隔写进 min/max。
// 外加 snap_cross 的两条：跨域取到的必须是完整快照（不撕烈）、心跳停了要报。
//
// 时间尺度：link_monitor 用 CLK_HZ=1000 例化 ⇒ 1 个源时钟 = 1 ms，否则等 200 ms
// 断流要跑 2500 万拍。帧间隔一律取 50 拍（> SETTLE=32），保证每帧都能发布。
module tb_link_monitor;
    localparam integer IMG_W = 8, IMG_H = 4, FRAME_BYTES = 64, PAY = 16;
    localparam integer PKTS  = FRAME_BYTES / PAY;   // 4
    localparam integer LMW   = 320;
    localparam integer GAP   = 50;

    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk;

    reg pclk = 0, prst_n = 0;
    always #62.5 pclk = ~pclk;                       // 8 MHz 的"目的域"

    // ---------------------------------------------------------------- 激励
    reg        p_valid = 0, p_sof = 0, p_eof = 0, p_good = 1;
    reg  [7:0] p_data = 0;
    wire       wr_en, flush, frame_done, frame_err, frame_abort;
    wire [15:0] rows_missed;
    wire [18:0] wr_addr;
    wire [15:0] wr_data;
    wire [31:0] s_frames, s_pkts, s_bytes, s_bad, s_oob;

    frame_reasm #(.IMG_W(IMG_W), .IMG_H(IMG_H), .FRAME_BYTES(FRAME_BYTES)) u_re (
        .clk(clk), .rst_n(rst_n),
        .p_data(p_data), .p_valid(p_valid), .p_sof(p_sof), .p_eof(p_eof),
        .p_good(p_good),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .flush(flush),
        .frame_done(frame_done), .frame_err(frame_err),
        .frame_abort(frame_abort), .rows_missed(rows_missed),
        .stat_frames(s_frames), .stat_pkts(s_pkts),
        .stat_bytes(s_bytes), .stat_bad(s_bad), .stat_oob_off(s_oob)
    );

    // CDC 写口模型：与 eth_udp_video_top 里 cdc_wr 的同一式子
    reg  cdc_full = 0;
    wire cdc_wr_req = wr_en | flush;

    wire [LMW-1:0] lm_bus;
    wire           lm_bus_tog, lm_hb;
    link_monitor #(.CLK_HZ(1000), .SETTLE(32), .LIVE_MS(16'd200)) u_lm (
        .clk(clk), .rst_n(rst_n),
        .cdc_wr_req(cdc_wr_req), .cdc_full(cdc_full),
        .frame_done(frame_done), .frame_abort(frame_abort),
        .frame_err(frame_err), .rows_missed(rows_missed),
        .in_pkts(s_pkts), .in_bytes(s_bytes),
        .lm_bus(lm_bus), .lm_bus_tog(lm_bus_tog), .lm_hb(lm_hb)
    );

    // 快照解码（lane 定义与 link_monitor 里的注释一一对应）
    wire [31:0] P_DROP       = lm_bus[0*32 +: 32];
    wire [15:0] P_FRAMES_BAD = lm_bus[1*32 +: 16];
    wire [15:0] P_PKT_ERR    = lm_bus[1*32+16 +: 16];
    wire [15:0] P_STALL      = lm_bus[2*32 +: 16];
    wire [15:0] P_ROWS_MAX   = lm_bus[2*32+16 +: 16];
    wire [15:0] P_GAP_LAST   = lm_bus[3*32 +: 16];
    wire [15:0] P_GAP_MIN    = lm_bus[4*32 +: 16];
    wire [15:0] P_GAP_MAX    = lm_bus[4*32+16 +: 16];
    wire [31:0] P_GAP_SUM    = lm_bus[5*32 +: 32];
    wire [15:0] P_CDC_EP     = lm_bus[6*32 +: 16];
    wire [4:0]  P_FLAGS      = lm_bus[7*32 +: 5];
    wire [31:0] P_PKTS       = lm_bus[8*32 +: 32];
    wire [31:0] P_BYTES      = lm_bus[9*32 +: 32];

    task send_pkt;
        input integer off;
        input integer skip;
        integer i, n;
        begin
            if (skip) begin
                repeat (5) @(posedge clk);
            end else begin
                n = FRAME_BYTES - off;
                if (n > PAY) n = PAY;
                @(negedge clk);
                p_valid <= 1; p_sof <= 1; p_eof <= 0; p_data <= off[7:0];
                @(negedge clk); p_sof <= 0; p_data <= off[15:8];
                @(negedge clk); p_data <= off[23:16];
                @(negedge clk); p_data <= off[31:24];
                for (i = 0; i < n; i = i + 1) begin
                    @(negedge clk);
                    p_data <= (off + i) & 8'hFF;
                    p_eof  <= (i == n - 1);
                end
                @(negedge clk); p_valid <= 0; p_eof <= 0;
            end
        end
    endtask

    task send_frame;
        input integer drop;      // 要丢掉的包序号，-1 = 完整
        input integer gap;       // 帧后再空多少拍（1 拍 = 1 ms）
        integer k;
        begin
            for (k = 0; k < PKTS; k = k + 1) send_pkt(k * PAY, (k == drop));
            repeat (gap) @(posedge clk);
        end
    endtask

    // ---- 生产时基守门 ----
    // 上面为了跑得动，把 CLK_HZ 改成了 1000（TC=1，一拍一 ms）。这正好掩盖过一类
    // 致命错：ms_div 写死 16 bit 时装不下 125000，比较恒假 ⇒ 真实时钟下 ms_tick
    // 永远不来，ms16/stall/gap/心跳在板上全死。这里用**生产参数**再例化一份，
    // 只问一件事：跑完这段仿真之后，它的 ms_tick 到底有没有响过。
    wire [LMW-1:0] p_lm_bus;
    wire           p_lm_tog, p_lm_hb;
    link_monitor #(.CLK_HZ(125_000_000), .SETTLE(32), .LIVE_MS(16'd200)) u_lm_prod (
        .clk(clk), .rst_n(rst_n),
        .cdc_wr_req(1'b0), .cdc_full(1'b0),
        .frame_done(1'b0), .frame_abort(1'b0), .frame_err(1'b0),
        .rows_missed(16'd0), .in_pkts(32'd0), .in_bytes(32'd0),
        .lm_bus(p_lm_bus), .lm_bus_tog(p_lm_tog), .lm_hb(p_lm_hb)
    );
    integer prod_ticks = 0;
    integer prod_cycles = 0;
    always @(posedge clk) begin
        prod_cycles = prod_cycles + 1;
        if (u_lm_prod.ms_tick) prod_ticks = prod_ticks + 1;
    end

    integer errors = 0;
    integer aborts = 0;
    integer pubs   = 0;
    reg     upd_after_stop = 0;
    reg     prev_tog = 0;
    always @(negedge clk) begin
        if (frame_abort) aborts = aborts + 1;
        if (lm_bus_tog !== prev_tog) begin
            pubs = pubs + 1;
            if (P_STALL >= 16'd200) upd_after_stop = 1;
        end
        prev_tog <= lm_bus_tog;
    end

    // ---------------------------------------------------------------- 跨域
    localparam integer SW = 64;
    reg  [SW-1:0] s_bus = 0;
    reg           s_tog = 0, s_hb = 0;
    wire [SW-1:0] d_bus;
    wire          d_gone;
    snap_cross #(.W(SW), .DST_HZ(8_000_000), .HB_TO_MS(50)) u_sc (
        .dst_clk(pclk), .dst_rst_n(prst_n),
        .bus(s_bus), .bus_tog(s_tog), .hb_tog(s_hb),
        .bus_q(d_bus), .hb_gone(d_gone)
    );

    initial begin
        rst_n = 0; prst_n = 0;
        repeat (10) @(posedge clk);  rst_n  = 1;
        repeat (20) @(posedge pclk); prst_n = 1;

        // ============ A 起点：没挡过写口 ⇒ 0 ============
        if (P_DROP !== 32'd0) begin
            $display("FAIL drop_words starts non-zero (%0d)", P_DROP); errors = errors + 1;
        end else $display("PASS drop_words starts at 0");

        // ============ B 两帧正常：0 丢字 + 间隔被量出来 ============
        send_frame(-1, GAP);
        send_frame(-1, GAP);
        if (s_frames !== 32'd2) begin
            $display("FAIL expected 2 committed frames, got %0d", s_frames); errors = errors + 1;
        end else $display("PASS two complete frames commit");
        if (P_FRAMES_BAD !== 16'd0 || aborts !== 0) begin
            $display("FAIL clean frames reported bad (aborts=%0d bus=%0d)", aborts, P_FRAMES_BAD);
            errors = errors + 1;
        end else $display("PASS clean frames raise no abort");
        if (!P_FLAGS[4]) begin
            $display("FAIL gap_valid clear after 2 frames"); errors = errors + 1;
        end else if (!(P_GAP_MIN <= P_GAP_LAST && P_GAP_LAST <= P_GAP_MAX)) begin
            $display("FAIL gap_last=%0d outside [min=%0d,max=%0d]", P_GAP_LAST, P_GAP_MIN, P_GAP_MAX);
            errors = errors + 1;
        end else if ((P_GAP_MAX - P_GAP_MIN) > 16'd2) begin
            // D：TB 里每帧节奏完全一样 ⇒ min 必须等于 max。若第一个 frame_done
            // 把"复位到现在"折进间隔，min 会明显小于 max，这里就会红。
            $display("FAIL gap spread min=%0d max=%0d although the stimulus is periodic",
                     P_GAP_MIN, P_GAP_MAX);
            errors = errors + 1;
        end else $display("PASS gap min=%0d last=%0d max=%0d sum=%0d ms",
                         P_GAP_MIN, P_GAP_LAST, P_GAP_MAX, P_GAP_SUM);
        if (!P_FLAGS[3]) begin
            $display("FAIL stream_live clear while frames are flowing"); errors = errors + 1;
        end else $display("PASS stream_live set while flowing");
        if (P_BYTES !== 32'd128 || P_PKTS !== 32'd8) begin
            $display("FAIL published bytes=%0d pkts=%0d, expected 128/8", P_BYTES, P_PKTS);
            errors = errors + 1;
        end else $display("PASS published byte/pkt counters match reasm");
        // lane 宽度守卫：任何一段拼错 bit 数都会把这些保留位污染掉
        if (lm_bus[3*32+31 -: 16] !== 16'd0 || lm_bus[6*32+31 -: 16] !== 16'd0
            || lm_bus[7*32+31 -: 27] !== 27'd0) begin
            $display("FAIL reserved bits non-zero, bus = %h", lm_bus); errors = errors + 1;
        end else $display("PASS lane packing has no width error");

        // ============ B2 缺一个中间包 ============
        send_frame(1, GAP);          // 丢掉 row1 的包，最后一个包照到
        if (aborts !== 1) begin
            $display("FAIL lost middle packet did not abort (aborts=%0d)", aborts);
            errors = errors + 1;
        end else $display("PASS lost middle packet aborts the frame exactly once");
        if (P_ROWS_MAX !== 16'd1) begin
            $display("FAIL rows_miss_max=%0d, expected 1", P_ROWS_MAX); errors = errors + 1;
        end else $display("PASS rows_miss_max publishes the missing-row count");
        if (P_FRAMES_BAD !== 16'd1) begin
            $display("FAIL published frames_bad=%0d, expected 1", P_FRAMES_BAD);
            errors = errors + 1;
        end else $display("PASS frames_bad reaches the snapshot");
        if (s_frames !== 32'd2) begin
            $display("FAIL aborted frame still committed (frames=%0d)", s_frames);
            errors = errors + 1;
        end else $display("PASS aborted frame is not committed");
        if (!P_FLAGS[1]) begin
            $display("FAIL abort_seen clear"); errors = errors + 1;
        end else $display("PASS abort_seen latches");

        // ============ B3 坏包（上板恒 0 的那条路，仿真里必须看得见）============
        p_good = 0; send_pkt(0, 0); p_good = 1;
        send_frame(-1, GAP);
        if (P_PKT_ERR < 16'd1) begin
            $display("FAIL bad packet not published (pkt_err=%0d)", P_PKT_ERR);
            errors = errors + 1;
        end else $display("PASS bad packet raises pkt_err (%0d)", P_PKT_ERR);

        // ============ A 反例判据：挡住 CDC 写口 ⇒ drop 必须涨 ============
        if (P_DROP !== 32'd0) begin
            $display("FAIL drop_words moved without fifo_full (%0d)", P_DROP);
            errors = errors + 1;
        end else $display("PASS negative control: no fifo_full, no drops");

        // cdc_full 必须在**负沿**驱动：在正沿上做阻塞赋值会和 DUT 的
        // always @(posedge) 抢同一时刻，full_d 可能和本拍一起变 1，
        // 于是 cdc_rise 永远看不到上升沿（第一版就是这么误报的）。
        @(negedge clk); cdc_full = 1;
        send_frame(-1, GAP);         // 整帧数据全撞在 full 上
        @(negedge clk); cdc_full = 0;
        repeat (40) @(posedge clk);
        if (P_DROP === 32'd0) begin
            $display("FAIL FALSIFIER: CDC port blocked for a whole frame but drop_words=0");
            errors = errors + 1;
        end else $display("PASS FALSIFIER: drop_words=%0d after blocking the CDC port", P_DROP);
        if (P_CDC_EP === 16'd0) begin
            $display("FAIL cdc_episodes=0 although fifo_full was held"); errors = errors + 1;
        end else $display("PASS cdc_episodes=%0d", P_CDC_EP);
        if (!P_FLAGS[0]) begin
            $display("FAIL drop_seen clear after drops"); errors = errors + 1;
        end else $display("PASS drop_seen flag latches");

        // ============ C 断流后快照必须继续刷新 ============
        upd_after_stop = 0;
        repeat (400) @(posedge clk);
        if (!upd_after_stop) begin
            $display("FAIL snapshot froze after the stream stopped"); errors = errors + 1;
        end else $display("PASS snapshot keeps refreshing while stalled");
        if (P_STALL < 16'd300) begin
            $display("FAIL stall_ms=%0d, expected past 300 after 400 ms silence", P_STALL);
            errors = errors + 1;
        end else $display("PASS stall_ms=%0d after 400 ms of silence", P_STALL);
        if (P_FLAGS[3]) begin
            $display("FAIL stream_live still set after 400 ms stall"); errors = errors + 1;
        end else $display("PASS stream_live clears when the stream dies");

        send_frame(-1, GAP);
        if (P_STALL > 16'd60) begin
            $display("FAIL stall did not reset on the next frame (%0d)", P_STALL);
            errors = errors + 1;
        end else $display("PASS a new frame clears stall_ms");

        // ============ D snap_cross：不撕烈 + 心跳超时 ============
        if (d_gone !== 1'b1) begin
            $display("FAIL hb_gone should be 1 before any heartbeat"); errors = errors + 1;
        end else $display("PASS snap_cross starts with hb_gone=1");

        begin : xdomain
            integer i2, tears;
            tears = 0;
            for (i2 = 1; i2 <= 100; i2 = i2 + 1) begin
                s_bus = i2 * 32'h00FF_0001;      // 每次换一个任意图案
                s_tog = ~s_tog;                  // 与总线同拍翻转（源协议）
                s_hb  = ~s_hb;
                repeat (12) @(posedge pclk);     // ≥3 级同步 + 捕获余量
                if (d_bus !== s_bus) begin
                    tears = tears + 1;
                    if (tears < 4) $display("  torn: dst=%h src=%h at i=%0d", d_bus, s_bus, i2);
                end
            end
            if (tears > 0) begin
                $display("FAIL snapshot tore %0d/100 times across the clock domain", tears);
                errors = errors + 1;
            end else $display("PASS snap_cross captured 100/100 intact snapshots");
        end

        s_hb = 0;                                // 源时钟停了
        repeat (500_000) @(posedge pclk);        // 62.5 ms @8 MHz > HB_TO_MS=50
        if (d_gone !== 1'b1) begin
            $display("FAIL hb_gone did not assert after the heartbeat died");
            errors = errors + 1;
        end else $display("PASS hb_gone asserts when the source clock stops");
        if (d_bus === 64'd0) begin
            $display("FAIL dst bus lost its value after hb_gone"); errors = errors + 1;
        end else $display("PASS the last snapshot survives the source clock dying (显示端仍能看到数字)");

        $display("INFO pubs=%0d frames=%0d aborts=%0d drops=%0d stall=%0d",
                 pubs, s_frames, aborts, P_DROP, P_STALL);
        if (prod_ticks < 1) begin
            $display("FAIL production timebase (CLK_HZ=125e6) never produced one ms_tick in %0d cycles",
                     prod_cycles);
            errors = errors + 1;
        end else $display("PASS production timebase: %0d ms_ticks in %0d cycles (125000/ms)",
                          prod_ticks, prod_cycles);
        if (errors == 0) $display("RESULT tb_link_monitor PASS");
        else             $display("RESULT tb_link_monitor FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #200_000_000;                             // 200 ms 看门狗
        $display("RESULT tb_link_monitor FAIL timeout");
        $finish;
    end
endmodule
