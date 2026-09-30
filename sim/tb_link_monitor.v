`timescale 1ns/1ps
// tb_link_monitor —— 例化 frame_reasm + link_monitor（测试时基一份，再用生产 CLK_HZ=125e6 例第二份只问 ms_tick）+ snap_cross，验链路健康自诊断**不误报平安**：丢字、断包、断流、帧间隔、心跳，每一条都要看得见。
// 判据索引：A 反例（挡住 CDC 写口 ⇒ drop_words 必须非 0；没有 full 时必须恒 0，否则这数字是噪声）· B/B2/B3（两帧正常提交；发布与统计寄存器**分家**判——B2 红=算术坏了、B 红 B2 绿=发布路径坏了，B2-mut 是它自己的反例；缺一个中间包 ⇒ frame_abort 恰好一次、rows_missed=1 并进快照 lane1/lane2；坏包那条上板恒 0 的路）· C 断流后快照必须继续刷新（否则 stall_ms 冻住，OSD 把"线被拔了"显示成"一切正常"）· D 第一个 frame_done 只建立基准，不许把"上电到现在"写进 min/max · E 长间隔饱和 0xFFFF 不许回卷 · F gapclr 只清帧间隔统计、别的计数不动 · **F2/F2e（#180）gapclr 是电平：举着跨帧边界（F2a–F2d，今天就是绿的，它是地板）与"放开那一拍正好压在记账那一拍"（F2e，用第三台 u_lm_syn 手摆出来，改前红）** · snap_cross 不撕裂 + hb_slow（拔线时钟退化工况）+ hb_gone。每条期望值写在各字母段的判行上。
// 跑法：bash sim/run_one.sh tb_link_monitor
module tb_link_monitor;
    localparam integer IMG_W = 8, IMG_H = 4, FRAME_BYTES = 64, PAY = 16;
    localparam integer PKTS  = FRAME_BYTES / PAY;   // 4
    localparam integer LMW   = 320;
    localparam integer GAP   = 50;          // 帧间隔一律取 50 拍（> SETTLE=32）保证每帧都能发布；CLK_HZ=1000 ⇒ 1 拍 = 1 ms，
                                            // 否则等 200 ms 断流要跑 2500 万拍（时基换算见 E 段那条饱和判据）

    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk;

    reg pclk = 0, prst_n = 0;
    always #62.5 pclk = ~pclk;                       // 8 MHz 的"目的域"

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
    // v7.6c：帧间隔统计清零入口 —— 板级 gap_max 停在 34066 ms = 16bit 毫秒计数回卷的假数（真实间隔 > 65.5 s）；
    // 修法是时基加宽 + 饱和 + 可清零，饱和由 E 段判、清零由 F 段判。
    reg        lm_gapclr = 0;
    wire cdc_wr_req = wr_en | flush;

    // F2e 那一台的输入（声明放在这里：sy_frame 这个 task 在实例之前就要用它们）
    reg         sy_rst = 0, sy_clr = 0, sy_done = 0;

    // ---- #124：参考计数器。判据要问的不是"drop_words 非 0"，而是"它数的次数对不对"。
    //      差别很要命：板上"零丢包"那句话说的是 `drop_words == 0`，而这个寄存器以前只被
    //      "非 0 就行 / 不动就行"级别的判据看过 ⇒ 任何一次把事件挪一拍、少记一次边沿的改动都能全绿。
    //      这里用与 link_monitor 同样的两个式子在台架里独立数一遍，收尾逐字比对。
    reg [31:0] ref_drop = 32'd0, ref_ep = 32'd0;
    reg        ref_full_d = 1'b0;
    always @(posedge clk) if (rst_n) begin
        if (cdc_wr_req && cdc_full)     ref_drop <= ref_drop + 1'b1;
        if (cdc_full && !ref_full_d)    ref_ep   <= ref_ep   + 1'b1;
        ref_full_d <= cdc_full;
    end
    // E2 用：一拍一拍的 0/1 交替，把"满只高一拍"这种边界造出来（隔离的单次事件最容易丢）
    reg        flip_en = 1'b0;
    // "最后一张快照在源钟停之后还在"这一条的期望值：原来写的是 `d_bus !== 0`，
    // 而目的侧那一路本来就会被灌成非 0（xdomain 循环留下的 00FF0001×100），所以那条判据**永远不会红**。
    // 现在先把停钟前一刻的读数钉住，再比"停钟之后有没有变"——这才是要判的那件事。
    reg [63:0] d_bus_hold = 64'hx;
    always @(negedge clk) if (flip_en) cdc_full = ~cdc_full;

    wire [LMW-1:0] lm_bus;
    wire           lm_bus_tog, lm_hb;
    link_monitor #(.CLK_HZ(1000), .SETTLE(32), .LIVE_MS(16'd200)) u_lm (
        .clk(clk), .rst_n(rst_n),
        .cdc_wr_req(cdc_wr_req), .cdc_full(cdc_full),
        .frame_done(frame_done), .frame_abort(frame_abort),
        .frame_err(frame_err), .rows_missed(rows_missed),
        .in_pkts(s_pkts), .in_bytes(s_bytes), .gapclr(lm_gapclr),
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

    // F2e 那一台的手摆帧：frame_done 举一整拍（下一个 posedge 被 link_monitor 采到 = 记账拍），
    // 之后再空 per-1 拍 ⇒ 两次记账拍之间正好差 per 拍（CLK_HZ=1000 ⇒ 一拍就是一"ms"）
    task sy_frame;
        input integer per;
        begin
            @(negedge clk); sy_done = 1;
            @(negedge clk); sy_done = 0;
            repeat (per - 1) @(negedge clk);
        end
    endtask

    // ---- 生产时基守门 ----
    // 为了跑得动把 CLK_HZ 改成 1000（一拍一 ms），这正好掩盖过一类致命错：ms_div 写死 16 bit 时装不下 125000、比较恒假
    // ⇒ 真实时钟下 ms_tick 永远不来，ms16/stall/gap/心跳在板上全死。故用**生产参数**再例化一份，只问 ms_tick 响过没有。
    wire [LMW-1:0] p_lm_bus;
    wire           p_lm_tog, p_lm_hb;
    link_monitor #(.CLK_HZ(125_000_000), .SETTLE(32), .LIVE_MS(16'd200)) u_lm_prod (
        .clk(clk), .rst_n(rst_n),
        .cdc_wr_req(1'b0), .cdc_full(1'b0),
        .frame_done(1'b0), .frame_abort(1'b0), .frame_err(1'b0),
        .rows_missed(16'd0), .in_pkts(32'd0), .in_bytes(32'd0), .gapclr(1'b0),
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

    localparam integer SW = 64;
    reg  [SW-1:0] s_bus = 0;
    reg           s_tog = 0, s_hb = 0;
    wire [SW-1:0] d_bus;
    wire          d_gone, d_slow;
    snap_cross #(.W(SW), .DST_HZ(8_000_000), .HB_TO_MS(50)) u_sc (
        .dst_clk(pclk), .dst_rst_n(prst_n),
        .bus(s_bus), .bus_tog(s_tog), .hb_tog(s_hb),
        .bus_q(d_bus), .hb_gone(d_gone), .hb_slow(d_slow)
    );

    // ---- F2e 用的第三台：输入全部由台架逐拍手摆（不挂 frame_reasm）----
    // 为什么要单独一台：#180 剩下那一种可达形状是"gapclr 放开的那一拍 == frame_done 被采的那一拍"，
    // 拿真帧流去等这个对齐要靠抢沿（等不到就是看门狗超时，等到了也不知道是不是同一个沿）；
    // 这一台把两个输入在同一个 negedge 一起举起 ⇒ 下一个 posedge 一定同时被采。
    wire [LMW-1:0] sy_bus;
    wire        sy_tog, sy_hb;
    link_monitor #(.CLK_HZ(1000), .SETTLE(32), .LIVE_MS(16'd200)) u_lm_syn (
        .clk(clk), .rst_n(sy_rst),
        .cdc_wr_req(1'b0), .cdc_full(1'b0),
        .frame_done(sy_done), .frame_abort(1'b0), .frame_err(1'b0),
        .rows_missed(16'd0), .in_pkts(32'd0), .in_bytes(32'd0), .gapclr(sy_clr),
        .lm_bus(sy_bus), .lm_bus_tog(sy_tog), .lm_hb(sy_hb)
    );
    wire [15:0] S_LAST = sy_bus[3*32 +: 16];
    wire [15:0] S_MIN  = sy_bus[4*32 +: 16];
    wire [15:0] S_MAX  = sy_bus[4*32+16 +: 16];
    wire [31:0] S_SUM  = sy_bus[5*32 +: 32];
    wire [4:0]  S_FLAG = sy_bus[7*32 +: 5];
    // 每一次"记账拍"都打一行改前的寄存器现场：F2e 那条红必须能被读成机理，
    // 而不是"某处数字对不上"。（这台实例只在 F2e 那一段被手摆，平时安静。）
    always @(posedge clk) if (sy_rst && sy_done)
        $display("PROBE sy-edge gapcnt=%0d clr=%b have_base=%b valid=%b min=%0d max=%0d sum=%0d",
                 u_lm_syn.gap_cnt, sy_clr, u_lm_syn.have_base, u_lm_syn.gap_valid,
                 u_lm_syn.gap_min, u_lm_syn.gap_max, u_lm_syn.gap_sum);

    // B2 的判据本体。写成 `reg + always @*` 而不是 `wire`：反例测试要在仿真期 force 一个假的 `gap_sum` 看它会不会变红，而 `wire` 表达式不随 force 重算 ⇒ 那种写法测不出"判据根本没看 sum"。
    reg b2_ok;
    always @* b2_ok = u_lm.gap_valid
                   && (u_lm.gap_min <= u_lm.gap_last) && (u_lm.gap_last <= u_lm.gap_max)
                   && (u_lm.gap_min === u_lm.gap_max)
                   && (u_lm.gap_sum === {16'd0, u_lm.gap_max});

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
        // r79/#46 落点：这里**不再多等拍** —— 减法从关键路径拿掉后记账与 `frame_done` 同拍（`gap_cnt` 就是读数），
        // 判据的时间契约与 r78 完全一致。（先前"拆两拍"的版本要多等一拍，那会真削弱判据：晚两拍的错也照样放过。）
        if (!P_FLAGS[4]) begin
            // 红话必须自带几何量：总线侧与寄存器侧同时摆出来，才分得清"没记账"与"记了但快照没带上"。
            $display("FAIL gap_valid clear after 2 frames | 总线 FLAGS=%b max=%0d last=%0d || 寄存器 gap_valid=%b have_base=%b gap_cnt=%0d gap_max=%0d gap_last=%0d",
                     P_FLAGS, P_GAP_MAX, P_GAP_LAST,
                     u_lm.gap_valid, u_lm.have_base, u_lm.gap_cnt, u_lm.gap_max, u_lm.gap_last);
            errors = errors + 1;
        end else if (!(P_GAP_MIN <= P_GAP_LAST && P_GAP_LAST <= P_GAP_MAX)) begin
            $display("FAIL gap_last=%0d outside [min=%0d,max=%0d]", P_GAP_LAST, P_GAP_MIN, P_GAP_MAX);
            errors = errors + 1;
        end else if ((P_GAP_MAX - P_GAP_MIN) > 16'd2) begin
            // D：TB 里每帧节奏完全一样 ⇒ min 必须等于 max；若第一个 frame_done 把"复位到现在"折进间隔，min 会明显小于 max，这里就会红。
            $display("FAIL gap spread min=%0d max=%0d although the stimulus is periodic",
                     P_GAP_MIN, P_GAP_MAX);
            errors = errors + 1;
        end else $display("PASS gap min=%0d last=%0d max=%0d sum=%0d ms",
                         P_GAP_MIN, P_GAP_LAST, P_GAP_MAX, P_GAP_SUM);
        // ============ B2 统计与发布**分家**（ISSUES #95 第 1 步）============
        // 上面三条读的是 `lm_bus`（发布出来的那一份），这一段读统计寄存器本身：拆成几级寄存器后"统计落地"与"快照发布"
        // 不再是同一拍，不分开就说不清**红的是哪一半**（判据只能整体回退）。分家后：B2 红 = 算术坏了；B 红而 B2 绿 = 发布路径/节拍坏了。
        if (!b2_ok) begin
            $display("FAIL B2 gap registers: valid=%b min=%0d last=%0d max=%0d sum=%0d（两帧之间应当只有一个间隔）",
                     u_lm.gap_valid, u_lm.gap_min, u_lm.gap_last, u_lm.gap_max, u_lm.gap_sum);
            errors = errors + 1;
        end else $display("PASS B2 statistics registers self-consistent (min=last=max=%0d sum=%0d)",
                         u_lm.gap_max, u_lm.gap_sum);
        // B2 自己的反例（判据要有自己的测试，"绿给绿的人看"不算数）：不改 RTL（构建正在读 src/rtl），改用仿真期 force 把 sum 弄成"多算了一项"——`b2_ok` 必须变假，变不了就说明这条判据根本不看 sum ⇒ 假绿，记一条错。
        force u_lm.gap_sum = u_lm.gap_max + 32'd1;
        #1;
        if (b2_ok === 1'b1) begin
            $display("FAIL B2-mut force 过的 gap_sum 仍然让判据说绿 ⇒ b2_ok 没有真的在看 sum"); errors = errors + 1;
        end else $display("PASS B2-mut forced gap_sum is caught（判据不是假绿）");
        release u_lm.gap_sum;
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

        // cdc_full 必须在**负沿**驱动：正沿上做阻塞赋值会和 DUT 的 always @(posedge) 抢同一时刻 ⇒ full_d 与本拍一起变 1，
        // cdc_rise 永远看不到上升沿（第一版就是这么误报的）。
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

        // 先让快照发布一次再读：P_* 是从 snap_cross 的那条总线解码出来的**快照**，
        // 堵口那一帧结束时最后一拍的事件还没进下一次发布 ⇒ 直接读会少 1（这不是计数错，是拿错了时刻。
        // 我自己第一版就把它读成了"实验版丢了一次事件"——见 ISSUES #124 的更正段）。
        send_frame(0, GAP); repeat (40) @(posedge clk);
        // ============ E1（#124 的采纳前提）：整帧堵口之后，两个计数器必须与参考**逐字相等** ============
        // 参考跑的是同样的式子，但它独立于 DUT（DUT 里那条使能被寄存、被改写、被合成都改得出来）；
        // 相等说明"每一次满+写的事件都被记了一次、且只记一次"，不等就是丢或多。
        if (P_DROP !== ref_drop) begin
            $display("FAIL E1 drop_words=%0d 但参考数到 %0d 计数器与事件不再一一对应", P_DROP, ref_drop);
            errors = errors + 1;
        end else $display("PASS E1 drop_words == 参考计数 (%0d)", ref_drop);
        if (P_CDC_EP !== ref_ep[15:0]) begin
            $display("FAIL E1 cdc_episodes=%0d 但参考数到 %0d 次进入满状态", P_CDC_EP, ref_ep);
            errors = errors + 1;
        end else $display("PASS E1 cdc_episodes == 参考计数 (%0d)", ref_ep[15:0]);

        // ============ E2：满只持续一拍的边界事件（最容易丢的一种），再逐字比一次 ============
        // A 段那种"整帧都满"是最宽松的激励：一次边沿、一次事件，丢了也很难看出来。
        // flip_en 把 cdc_full 打成 1/0/1/0，于是每一拍都可能造出"单个事件 + 单次进满"。
        flip_en = 1'b1;
        send_frame(-1, GAP);
        @(negedge clk); flip_en = 1'b0; @(negedge clk); cdc_full = 1'b0;
        send_frame(0, GAP);              // 干净收尾：不留在 full 上
        repeat (40) @(posedge clk);
        if (P_DROP !== ref_drop) begin
            $display("FAIL E2 drop_words=%0d 但参考数到 %0d 满只高一拍的边界事件被丢或被重记", P_DROP, ref_drop);
            errors = errors + 1;
        end else $display("PASS E2 单拍满事件计数一致 (drop=%0d)", ref_drop);
        if (P_CDC_EP !== ref_ep[15:0]) begin
            $display("FAIL E2 cdc_episodes=%0d 但参考数到 %0d 进满边沿在单拍宽度下数错", P_CDC_EP, ref_ep);
            errors = errors + 1;
        end else $display("PASS E2 单拍进满边沿计数一致 (ep=%0d)", ref_ep[15:0]);
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

        // ============ E 长间隔必须饱和，不许回卷（板级抓到过 34066 的假数）============
        // TB 里 1 拍 = 1 ms（CLK_HZ=1000）⇒ 空转 70000 拍就是一个 70 s 的间隔。
        repeat (70_000) @(posedge clk);
        send_frame(-1, GAP);
        if (P_GAP_MAX !== 16'hFFFF) begin
            $display("FAIL gap_max=%0d after a 70 s gap, expected to saturate at 0xFFFF", P_GAP_MAX);
            errors = errors + 1;
        end else $display("PASS a >65.5 s gap saturates at 0xFFFF instead of wrapping");

        // ============ F gapclr 只清帧间隔统计，别的计数不动 ============
        begin : clr_case
            integer bad_before; bad_before = P_FRAMES_BAD;
            @(negedge clk); lm_gapclr = 1;
            repeat (4) @(posedge clk);
            @(negedge clk); lm_gapclr = 0;
            repeat (GAP) @(posedge clk);
            send_frame(-1, GAP);              // 第一帧只重建基准
            if (P_GAP_MAX !== 16'd0 || P_FLAGS[4] !== 1'b0) begin
                $display("FAIL gap stats survived gapclr (max=%0d gap_valid=%0b)",
                         P_GAP_MAX, P_FLAGS[4]);
                errors = errors + 1;
            end else $display("PASS gapclr zeroes the interval stats and re-baselines cleanly");
            if (P_FRAMES_BAD !== bad_before) begin
                $display("FAIL gapclr touched other counters (%0d -> %0d)",
                         bad_before, P_FRAMES_BAD);
                errors = errors + 1;
            end else $display("PASS gapclr leaves drop/bad/pkts/bytes alone");
            send_frame(-1, GAP);              // 第二帧起重新能量出间隔
            if (P_GAP_MAX === 16'd0) begin
                $display("FAIL gap stats never re-calibrated after gapclr"); errors = errors + 1;
            end else $display("PASS interval stats re-calibrate after the clear");
        end

        // ============ F2 gapclr 举着**跨过整个帧边界**（今天这一支是绿的，它是地板）============
        // 台账里原先写的症状是"清零被 frame_done 那一拍盖掉 ⇒ gap_min 永远钉在 0"。这一段就是照着
        // 那句话写的尺子，跑出来**全绿**：清零块（:116）只要 gapclr 还举着就**每一拍重跑**，
        // 帧边界那一拍即使被 :135 盖回去，下一拍又被清回来 ⇒ 从快照口看不出差别。
        // 所以 F2a–F2d 留作**地板与对照**（改前后都必须绿；它们防的是"清零把手臂上的别的计数也清了"
        // 和"间隔计从来就不动"这两种假象），真正的可达标本在下面的 F2e，用第三台手摆。
        begin : clr_straddle
            integer k2, mn_s, mx_s, mn_p, mx_p;
            send_frame(-1, GAP); send_frame(-1, GAP);     // 先把统计立起来（E/F 之后本来就有数）
            @(negedge clk); lm_gapclr = 1;                // 举住：PS 侧这是一段电平，不是一拍
            for (k2 = 0; k2 < 3; k2 = k2 + 1) send_frame(-1, GAP);   // 举着期间过了三个帧边界
            $display("PROBE F2 held over 3 frame edges: valid=%0b min=%0d max=%0d last=%0d sum=%0d have_base=%0b",
                     P_FLAGS[4], P_GAP_MIN, P_GAP_MAX, P_GAP_LAST, P_GAP_SUM, u_lm.have_base);
            if (P_FLAGS[4] !== 1'b0) begin
                $display("FAIL F2a gapclr held across frame edges yet gap_valid still claims ready");
                errors = errors + 1;
            end else $display("PASS F2a the clear wins: stats stay not-ready while gapclr is held");
            if (P_GAP_MIN !== 16'd0 || P_GAP_MAX !== 16'd0 || P_GAP_LAST !== 16'd0
                || P_GAP_SUM !== 32'd0) begin
                $display("FAIL F2b published lanes are not really cleared during the hold");
                errors = errors + 1;
            end else $display("PASS F2b lane3/4/5 all read zero while gapclr is held");
            @(negedge clk); lm_gapclr = 0;                // 放开
            send_frame(-1, GAP);                          // 第一帧只重建基准
            send_frame(-1, GAP);                          // 第二帧起才量得到间隔
            mn_s = P_GAP_MIN; mx_s = P_GAP_MAX;
            $display("PROBE F2 after release: valid=%0b min=%0d max=%0d last=%0d sum=%0d",
                     P_FLAGS[4], P_GAP_MIN, P_GAP_MAX, P_GAP_LAST, P_GAP_SUM);
            if (mn_s < 16'd1 || mn_s > mx_s) begin
                $display("FAIL F2c min=%0d max=%0d after a straddling clear (min pinned at 0 = #180)",
                         mn_s, mx_s);
                errors = errors + 1;
            end else $display("PASS F2c a straddling clear re-calibrates min honestly");
            // 反配对（正对照）：**同样的帧**，只是清零只举两拍、一次也不跨帧边界 ⇒ min 必须与 max 相等且非 0。
            // 少了它，F2c 的绿可能只是"这台架的 min 从来就不动"；它同时是 F 段那条的对偶。
            send_frame(-1, GAP);                          // 让 min/max 先有一次数（下面的清零才谈得上"清掉"）
            @(negedge clk); lm_gapclr = 1;
            repeat (2) @(posedge clk);                    // 两拍就放开：这一段里一个帧边界都不过
            @(negedge clk); lm_gapclr = 0;
            send_frame(-1, GAP);                          // 第一帧只重建基准
            send_frame(-1, GAP);                          // 第二帧起才量得到间隔
            mn_p = P_GAP_MIN; mx_p = P_GAP_MAX;
            $display("PROBE F2d pulse clear: min=%0d max=%0d last=%0d sum=%0d valid=%0b",
                     P_GAP_MIN, P_GAP_MAX, P_GAP_LAST, P_GAP_SUM, P_FLAGS[4]);
            if (mn_p < 16'd1 || mn_p > mx_p) begin
                $display("FAIL F2d a NON-straddling clear also broke min (=%0d max=%0d) —— 尺子坏了",
                         mn_p, mx_p);
                errors = errors + 1;
            end else $display("PASS F2d control: a short clear leaves min=max=%0d (the meter itself works)", mn_p);
        end

        // ============ F2e（#180 的**真标本**）放开的这一拍正好压在记账那一拍上 ============
        // 上面那一段跑出来是**绿的**，而它把我原先记进台账的那句"举着跨帧边界必然撞"**否掉了**：
        // gapclr 只要还举着，:116 的清零块每一拍都重跑 ⇒ 帧边界那一拍即使被 :135 的 frame_done 支
        // 盖回去（have_base、gap_min 又被写一次），下一拍就被清回来 ⇒ 从快照口看不出来。
        // 还剩一种可达形状，而且是**永久的**：放开的时机与某个 frame_done 被采到的那一拍重合。
        // 那一拍上 :116 写 `gap_sum<=0`、:140 写 `gap_sum <= gap_sum + gap_new`，**后写者赢** ⇒
        // 清零没生效，lane5 里留着"这次清零之前"的历史 Σ；之后每帧只往上加 ⇒ 上位机那一句
        // `均值 = lane5/(frames_ok-1)` 从此偏大，而且除了再按一次清零不会自己好。
        // 可达性（两句都要说）：①bit26 是 PS 的电平（system_top.v:193 → eth_udp_video_top.v:280 三级同步），
        // 而**今天的 main.c 里 ctrl_write() 整字写回、26 位恒 0** ⇒ 板上这一支今天走不到；
        // ②即使固件按文档所说用它，也得"放开的这一拍正好压在一帧的记账拍上"（一帧 130 拍 ⇒ 约 1/130）。
        // 所以这是一条**低severity但永久**的读数债，不是"必然错"。
        // 用**第三个合成激励的实例**来判（u_lm_syn）：上面那台挂着真 frame_reasm 的帧流，
        // "放开的那一拍正好是记账的那一拍"这种对齐要靠抢沿，抢不抢得到全看台架自己的相位；
        // 这一台把 frame_done 与 gapclr 在**同一个 negedge** 一起举起来 ⇒ 下一个 posedge 两件事
        // 一定同时被采 ⇒ 撞是构造出来的、不是等来的（上一版在这里等真 frame_done，等不到 ⇒ 看门狗超时）。
        begin : syn_case
            integer k3;
            sy_rst = 0;
            repeat (3) @(negedge clk);
            sy_rst = 1;
            // 先走 4 帧建立历史：第一帧只建基准 ⇒ Σ = 3×130 = 390
            for (k3 = 0; k3 < 4; k3 = k3 + 1) sy_frame(130);
            $display("PROBE F2 syn pre-history: last=%0d sum=%0d min=%0d max=%0d valid=%0b",
                     S_LAST, S_SUM, S_MIN, S_MAX, S_FLAG[4]);
            // A 对照：清零举三拍，这三拍里**一个帧边界都没有** ⇒ 两棵树都必须清干净
            @(negedge clk); sy_clr = 1;
            repeat (3) @(posedge clk);
            @(negedge clk); sy_clr = 0;
            repeat (127) @(negedge clk);              // 与下一帧拉开一个整周期（sy_frame 的第一拍是"举起"那一拍）
            for (k3 = 0; k3 < 2; k3 = k3 + 1) sy_frame(130);
            $display("PROBE F2e A non-straddling clear: last=%0d sum=%0d min=%0d max=%0d valid=%0b",
                     S_LAST, S_SUM, S_MIN, S_MAX, S_FLAG[4]);
            if (S_SUM > 32'd261) begin
                $display("FAIL F2e A control is broken too: sum=%0d after a clean clear (ruler bug, not RTL)",
                         S_SUM);
                errors = errors + 1;
            end else $display("PASS F2e A control: a clean clear leaves sum=%0d (<= 2 x 130)", S_SUM);
            // B 相撞：清零与 frame_done 同一拍举起、下一拍一起放开 ⇒ 采到的那一拍两件都写 gap_sum
            @(negedge clk); sy_clr = 1; sy_done = 1;      // 下一个 posedge：gapclr=1 且 frame_done=1
            @(negedge clk); sy_clr = 0; sy_done = 0;
            repeat (127) @(negedge clk);                  // 与下一帧拉开：不让"相距一拍"变成另一种标本
            for (k3 = 0; k3 < 2; k3 = k3 + 1) sy_frame(130);
            $display("PROBE F2e B released-on-accounting: last=%0d sum=%0d min=%0d max=%0d valid=%0b",
                     S_LAST, S_SUM, S_MIN, S_MAX, S_FLAG[4]);
            if (S_SUM > 32'd261) begin
                $display("FAIL F2e B lane5 kept pre-clear history: sum=%0d > 2x130 (the clear lost the same-cycle race)",
                         S_SUM);
                errors = errors + 1;
            end else $display("PASS F2e B a clear landing on the accounting edge still zeroes lane5");
        end

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
            // 心跳间隔 1.5 us（远小于 SLOW_MS=5ms）⇒ 判“时基正常”，不许误报
            if (d_slow !== 1'b0) begin
                $display("FAIL hb_slow asserted although the heartbeat is faster than SLOW_MS");
                errors = errors + 1;
            end else $display("PASS hb_slow clear while the heartbeat is at nominal rate");
        end

        // 板级实测：拔线后 RTL8211F 不停 RXC，而是把它拉到约 1/48 ⇒ 心跳"还在，但间隔变成 ~50 ms"。这里用 8 ms 的间隔
        // 复现它，判 hb_slow 必须亮 —— 这是 hb_gone 永远看不见的那个工况。
        begin : slow_case
            integer j;
            for (j = 0; j < 3; j = j + 1) begin
                repeat (64_000) @(posedge pclk);   // 8 ms @8 MHz，落在 5..50 ms 之间
                s_hb = ~s_hb;
            end
            repeat (20) @(posedge pclk);
            if (d_slow !== 1'b1) begin
                $display("FAIL hb_slow stayed low although the heartbeat period was 8x SLOW_MS");
                errors = errors + 1;
            end else $display("[tb_link_monitor.v:357] PASS hb_slow asserts when the source clock is degraded (拔线工况)");
            if (d_gone !== 1'b0) begin
                $display("FAIL hb_gone fired while heartbeats were still arriving"); errors = errors + 1;
            end else $display("[tb_link_monitor.v:360] PASS hb_gone correctly stays clear (它看不见这件事，正是加 hb_slow 的理由)");
        end

        s_hb = 0;                                // 源时钟停了
        d_bus_hold = d_bus;                       // 钉住"停钟之前目的侧到底读到什么"
        repeat (500_000) @(posedge pclk);        // 62.5 ms @8 MHz > HB_TO_MS=50
        if (d_gone !== 1'b1) begin
            $display("FAIL hb_gone did not assert after the heartbeat died");
            errors = errors + 1;
        end else $display("PASS hb_gone asserts when the source clock stops");
        if (d_bus !== d_bus_hold) begin
            $display("FAIL dst bus lost its value after hb_gone: held=%h now=%h", d_bus_hold, d_bus);
            errors = errors + 1;
        end else $display("[tb_link_monitor.v:371] PASS the last snapshot survives the source clock dying (显示端仍能看到数字，比的是停钟前钉住的那 %h)", d_bus_hold);

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
