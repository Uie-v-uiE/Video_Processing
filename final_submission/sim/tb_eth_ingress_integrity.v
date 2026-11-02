`timescale 1ns/1ps
// 功能：被测模块 `frame_reasm`→`dc_fifo`→`axi_frame_saver64` 的整条入包链（glue 与
//        eth_udp_video_top 一致）；覆盖点：逐级计数把丢字定位到某一级，并量 CDC 与打包器 FIFO
//        的峰值占用（#105/#120 的深度证据）。
// 激励与检查：gmii_rx_clk #4=8 ns、axi_clk #5=10 ns；rst_n 低 10 个 gmii 负沿后释放、再空 10 拍。
//        每包在 negedge 每字节 1 拍挂 [u32 小端 offset][载荷]，图案=字号 w 的 4 个 16bit lane
//        全等于 w；包间空 gap_cyc=GAP=10230 拍（+GAP0 置 0=线速连灌）；载荷 PL_B=PAYLOAD=1392
//        （+MISALIGN 改 1396，非 8 的倍数）。PART 灌 TB_PKTS=60 包→TB_WORDS=(60*PL_B)/8=10440
//        （MISALIGN 10470）；+FULL 灌满一帧 221 包→TB_WORDS=WORDS=38400。AXI 从机每 beat 停
//        RDDR_BEATS=20 拍、按 WSTRB 逐字节合并进 mem。判定条件：mem[pi]==={pi[15:0],pi[15:0],
//        pi[15:0],pi[15:0]} 的字数 w_ok==TB_WORDS，且 cdc_drop==0、sv_drop==0、cdc_peak>0、
//        sv_peak>0、s_frames==FULL（PART 期望 0、+FULL 期望 1）；排空上限 2000000 个 axi 拍。
// 预期结果：通过时打印 mode=... words=<TB_WORDS>、drain: waited <t> axi cycles、
//        [tb_eth_ingress_integrity:stage] 逐级计数行、words exact=<TB_WORDS>/<TB_WORDS> half=0
//        allzero=0 other=0 lanes_bad=0、两条 PROBE 峰值行、PASS cdc peak probe alive、
//        PASS packer peak probe alive、PASS ingress lossless、PASS full frame committed exactly
//        once（PART 下为 PASS partial frame not committed），末行 PASS tb_eth_ingress_integrity。
//        失败时打 FAIL ingress loses data、FAIL cdc peak probe never saw a non-empty FIFO、
//        FAIL packer peak probe never saw a non-empty FIFO ...、FAIL frames_done=<n> expected=<n>，
//        并附 first bad word=<w> got=<值> expected=<值>，末行 FAIL tb_eth_ingress_integrity errors=<n>；
//        #80_000_000 超时打 FAIL tb_eth_ingress_integrity timeout。
// v6 入包完整性 TB（跑法：bash sim/run_one.sh tb_eth_ingress_integrity）
// 板上 JTAG 回读 DDR：38400 个 64bit 字里绝大多数只有 lane{0,2} 或 lane{1,3} 落了数据
//   （WSTRB mask 1010 / 0101），约 40% 的 16bit lane 从来没被写过；改「包间」限速不影响比例。
// 用和 eth_udp_video_top 完全相同的胶水串起 frame_reasm → dc_fifo → axi_frame_saver64 → AXI 从机，
//   灌包后逐字比对 AXI 端收到的 64bit 字并统计每一级计数 ⇒ 直接指出丢在哪一级。
// 判据：words exact == 本次应落字数，且 cdc_drop == 0、packer_drop == 0；只灌部分包时 frames_done 必须为 0。
module tb_eth_ingress_integrity;
    localparam IMG_W = 512, IMG_H = 300;
    localparam FRAME_BYTES = IMG_W * IMG_H * 2;                    // 307200
    localparam PAYLOAD     = 1392;                                 // 8 的倍数
    localparam TB_PKTS  = 60;   // 默认只灌前 60 包：60×174 个字，仿真量足够又不太长
    localparam GAP      = 10230;  // 包间空拍：等效上位机 15 MB/s 限速
    localparam WORDS       = FRAME_BYTES / 8;                      // 38400
    localparam BASE        = 32'h1000_0000;
    // +FULL：灌满一整帧 221 包，最后一包只有 960 B（=307200-220×1392），
    // 用来查**帧尾那半个 u32**（板上 frameid 回读发现每帧最后 4 字节是 0）
    integer PKTS, TB_WORDS;
    integer FULL;
    integer gap_cyc;               // +GAP0 = 0：GMII 线速连灌（#105 要的压力）
    // +MISALIGN：分包长度改 1396 B（不是 8 的倍数），复现板上的「规律黑点」——包边界落在 64bit
    // 字中间 ⇒ 同一个字被相邻两包各推一次；v6.4 前 WSTRB 恒 0xFF 会把前一次覆盖成 0，现在两种分包都必须整帧全对。
    integer MIS;
    integer PL_B;                 // 实际分包载荷字节数

    reg gmii_rx_clk = 0, axi_clk = 0, rst_n = 0;
    wire axi_rst_n = rst_n;
    always #4  gmii_rx_clk = ~gmii_rx_clk;   // 125 MHz
    always #5  axi_clk     = ~axi_clk;       // 100 MHz

    reg        p_valid = 0, p_sof = 0, p_eof = 0;
    reg  [7:0] p_data  = 0;
    wire       p_good  = 1'b1;
    wire       udp_sof;

    wire        fb_wr_en, reasm_flush, frame_done, frame_err;
    wire [18:0] fb_wr_addr;
    wire [15:0] fb_wr_data;
    wire [31:0] s_frames, s_pkts, s_bytes, s_bad, s_oob;

    frame_reasm #(.IMG_W(IMG_W), .IMG_H(IMG_H), .FRAME_BYTES(FRAME_BYTES)) u_re (
        .clk(gmii_rx_clk), .rst_n(rst_n),
        .p_data(p_data), .p_valid(p_valid), .p_sof(udp_sof),
        .p_eof(p_eof), .p_good(p_good),  // p_sof 由和顶层一样的 udp_sof 检测产生
        .wr_en(fb_wr_en), .wr_addr(fb_wr_addr), .wr_data(fb_wr_data),
        .flush(reasm_flush), .frame_done(frame_done), .frame_err(frame_err),
        .stat_frames(s_frames), .stat_pkts(s_pkts), .stat_bytes(s_bytes),
        .stat_bad(s_bad), .stat_oob_off(s_oob)
    );

    // 与 eth_udp_video_top 相同的 sof 检测 / CDC 胶水
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
    wire        cdc_is_flush = !fb_wr_en && (flush_pend || reasm_flush);
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
    wire        sv_fifo_full;
    reg  [18:0] sav_a;
    reg  [15:0] sav_d;
    integer     cdc_ok = 0, cdc_drop = 0, cdc_rd = 0;

    dc_fifo #(.DATA_W(36), .ADDR_W(13)) u_cdc (
        .wr_clk(gmii_rx_clk), .wr_rst_n(rst_n),
        .wr_en(cdc_wr), .wr_data(cdc_data),
        .wr_full(fifo_full),
        .rd_clk(axi_clk), .rd_rst_n(axi_rst_n),
        .rd_en(fifo_rd), .rd_data(fifo_dout), .rd_empty(fifo_empty)
    );

    // ---- #105 的"吸收量"探针（2026-09-29 加）----
    // 想问的是：**8192 格的深度是不是过剩？** 只有量出峰值占用才答得了；没量过就降深度，
    // 等于拿"零丢包"那句承诺赌（ISSUES #105 里写过的同一条）。
    // ⚠ 三点自限，别把这一行数读成它管不了的东西：
    //   ① 这是**跨域同拍采样**两个域各自的二进制指针（写 125 MHz / 读 100 MHz），瞬时值可能差 ±1 格
    //      —— 对"要不要降到 1024"这个数量级的决策无所谓，对"证明探针活着"也无所谓；
    //   ② 这一跑的流量形状是**本台架生成的那一种**（默认 60 包 / 包间 GAP=10230 等效限速 15 MB/s；
    //      +FULL 才是一整帧 221 包连灌）。**读侧被 `sv_full` 堵住的窗口**才是深度的真正来源，
    //      而那一半在这里没有建模 ⇒ 峰值只是下界，不是设计界；
    //   ③ 所以判据只判"探针看见过非空"（`peak>0`）：如果它一直是 0，要么探针接错了名字，
    //      要么这个模型里 CDC 从来没缓冲过东西 ⇒ 这条 PASS 就没有意义（#81/#90 那一族"空判"）。
    reg  [13:0] cdc_peak = 14'd0;
    reg  [13:0] cdc_now;
    always @(u_cdc.wbin or u_cdc.rbin) begin
        cdc_now = u_cdc.wbin - u_cdc.rbin;
        if (cdc_now > cdc_peak) cdc_peak = cdc_now;
    end

    // 同一把尺子量**打包器 FIFO**（`u_sv` 里 `{q_addr,q_data,q_keep}` = 100 bit × 512 格 ≈ 800 个
    // LUT64E，是全设计 LUTRAM 4044 里最大的单一消费者）。要判"FW 从 9 降到 8 能不能换 400 个 LUT"，
    // 缺的就是这个峰值占用数（#120 对 CDC 深度做的就是这件事）—— 先量，不动源。
    // 自限与上面三条同构：单域同拍采样，读侧被 DDR 端口独占挡住的窗口由本台架的 AXI 从机建模。
    reg  [9:0] sv_peak = 10'd0;
    reg  [9:0] sv_now;
    always @(u_sv.wptr or u_sv.rptr) begin
        sv_now = u_sv.wptr - u_sv.rptr;
        if (sv_now > sv_peak) sv_peak = sv_now;
    end

    // 统计：reasm 发出了 wr_en 但没进 CDC（被 flush 抢占 / 满）
    always @(posedge gmii_rx_clk or negedge rst_n) begin
        if (!rst_n) begin cdc_ok = 0; cdc_drop = 0; end
        else if (fb_wr_en) begin
            if (cdc_wr && !cdc_is_flush) cdc_ok = cdc_ok + 1;
            else                         cdc_drop = cdc_drop + 1;
        end
    end

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            fifo_rd <= 0; cdc_d1 <= 0; cdc_d1_v <= 0;
            sav_en <= 0; sav_flush <= 0; sav_a <= 0; sav_d <= 0;
        end else begin
            fifo_rd  <= !fifo_empty && !sv_fifo_full;
            cdc_d1   <= fifo_dout;
            cdc_d1_v <= fifo_rd;
            sav_en    <= cdc_d1_v && !cdc_d1[35];
            sav_flush <= cdc_d1_v &&  cdc_d1[35];
            if (cdc_d1_v) begin
                sav_a <= cdc_d1[34:16];
                sav_d <= cdc_d1[15:0];
                cdc_rd = cdc_rd + 1;
            end
        end
    end

    // 真实打包 + AXI 写引擎
    reg         m_awready, m_wready, m_bvalid;
    wire [31:0] m_awaddr;
    wire [7:0]  m_awlen;
    wire [2:0]  m_awsize;
    wire [1:0]  m_awburst;
    wire        m_awvalid;
    wire [63:0] m_wdata;
    wire [7:0]  m_wstrb;
    wire        m_wlast, m_wvalid;
    wire        m_bready;


    axi_frame_saver64 #(.BASE_ADDR(BASE)) u_sv (
        .clk(axi_clk), .rst_n(rst_n), .enable(1'b1), .base_addr(BASE),
        .wr_en(sav_en), .wr_addr(sav_a), .wr_data(sav_d),
        .flush(sav_flush), .fifo_full(sv_fifo_full), .idle(), .busy(),
        .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen), .m_axi_awsize(m_awsize),
        .m_axi_awburst(m_awburst), .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb), .m_axi_wlast(m_wlast),
        .m_axi_wvalid(m_wvalid), .m_axi_wready(m_wready),
        .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready)
    );

    integer sv_drop = 0, axi_wr = 0;
    always @(posedge axi_clk) if (sav_en && sv_fifo_full) sv_drop = sv_drop + 1;

    reg [31:0] aw_addr_r;
    reg [31:0] bsh;
    reg [63:0] mem [0:WORDS-1];
    // 模拟真实系统里 DDR/HP0 的积压：每接受一个 beat 就停发 ready 若干拍
    // （显示拷贝与入包写共用同一条 64bit 通道）。v6.3 起 saver 是**流水化**的（AW/W 同拍挂出、
    // 不逐字等 B），所以从机必须用标准握手接收并按序回 B（B 管道深度 4，够 2 拍/beat 的稳态）。
    localparam RDDR_BEATS = 20;  // 每个 beat 占用端口 ≈20 拍(真实 HP0+DDR 量级)
    integer rd_hold;
    integer si;                       // WSTRB 合并循环
    wire svc      = (rd_hold == 0);
    wire new_beat = m_awvalid && m_wvalid && m_awready && m_wready;
    always @(posedge axi_clk or negedge rst_n) begin
        if (!rst_n) begin
            m_awready <= 1; m_wready <= 1; m_bvalid <= 0;
            aw_addr_r <= 0; bsh <= 0;
            rd_hold = 0;
        end else begin
            if (rd_hold > 0) rd_hold = rd_hold - 1;
            m_awready <= svc;
            m_wready  <= svc;
            m_bvalid  <= bsh[0];
            if (new_beat) begin
                aw_addr_r <= m_awaddr;
                rd_hold   = RDDR_BEATS;
                bsh       <= (bsh >> 1) | 32'h0000_0008;   // 4 拍后回 B
                // 真实从机要按 WSTRB 合并，否则测不出「同一字被两包分两次写」的覆盖问题
                if ((m_awaddr - BASE) < (WORDS * 8)) begin
                    for (si = 0; si < 8; si = si + 1)
                        if (m_wstrb[si])
                            mem[(m_awaddr - BASE) >> 3][si*8 +: 8] = m_wdata[si*8 +: 8];
                    axi_wr = axi_wr + 1;
                end
            end else begin
                bsh <= bsh >> 1;
            end
        end
    end

    // 激励：每个字节只占一个 gmii 周期（negedge 更新、正沿采样一次）——
    // 调用末尾多等一个 negedge 就成每字节 2 拍，reasm 把同一字节配成像素 ⇒ 仿真里出现假丢字。
    task send_byte;
        input [7:0] b;
        input       sof;
        input       eof;
        begin
            @(negedge gmii_rx_clk);
            p_data = b; p_valid = 1; p_sof = sof; p_eof = eof;
        end
    endtask

    // 图案：字号 w 的 4 个 16bit lane 都等于 w（与板上 wordid 测试一致）
    function [7:0] byte_at;
        input [31:0] off;
        reg [15:0] w;
        begin
            w = off[31:3];
            byte_at = off[0] ? w[15:8] : w[7:0];
        end
    endfunction

    integer pi, bi, errors, first_bad;
    integer w_ok, w_half, w_zero, w_other, lane_bad;
    reg [63:0] exp64, got64;
    reg [15:0] l0, l1, l2, l3;
    reg [31:0] off0, pkt_bytes;

    task send_pkt;
        input integer n;
        begin
            off0 = n * PL_B;
            pkt_bytes = ((FRAME_BYTES - off0) < PL_B) ? (FRAME_BYTES - off0)
                                                       : PL_B;
            send_byte(off0[7:0],   1'b1, 1'b0);
            send_byte(off0[15:8],  1'b0, 1'b0);
            send_byte(off0[23:16], 1'b0, 1'b0);
            send_byte(off0[31:24], 1'b0, 1'b0);
            for (bi = 0; bi < pkt_bytes; bi = bi + 1)
                send_byte(byte_at(off0 + bi), 1'b0,
                          (bi == pkt_bytes - 1) ? 1'b1 : 1'b0);
            // 包间一个空拍（等效上位机限速；真实 gmii_rx_dv 在帧间会掉）
            @(negedge gmii_rx_clk);
            p_valid = 0; p_eof = 0; p_sof = 0;
            repeat (gap_cyc) @(negedge gmii_rx_clk);
        end
    endtask

    initial begin
        errors = 0; first_bad = -1;
        FULL = 0;
        gap_cyc = GAP;
        if ($test$plusargs("FULL")) FULL = 1;
        // ⚠ **#105 要的正是这一档**：包间空拍按 `GAP=10230` 灌，等效上位机限速 15 MB/s ⇒ 峰值占用只有
        //   3 格（02:51 量到的），那个数**说明不了深度可以降**——因为写侧根本没压满过。
        //   `+GAP0` 把包间空拍去掉 = GMII 线速连灌，才是 CDC 深度的真压力（读侧 `sv_full` 的阻塞窗口
        //   由这个 AXI 从机模型给出）。跑法（plusargs 在 xsim 里只能这么给，见 `sim/run_sim.tcl:70`）：
        //     xsim snap -R --testplusarg FULL --testplusarg GAP0
        if ($test$plusargs("GAP0")) gap_cyc = 0;
        MIS = 0;
        if ($test$plusargs("MISALIGN")) MIS = 1;
        PL_B = MIS ? 1396 : PAYLOAD;
        PKTS     = FULL ? (FRAME_BYTES + PL_B - 1) / PL_B : TB_PKTS;   // 221 / 60
        TB_WORDS = FULL ? WORDS : (TB_PKTS * PL_B) / 8;                // 38400 / 10440|10470
        $display("mode=%0s payload=%0d pkts=%0d words=%0d",
                 FULL ? "FULL" : "PART", PL_B, PKTS, TB_WORDS);
        for (pi = 0; pi < WORDS; pi = pi + 1) mem[pi] = 64'h0;
        rst_n = 0; repeat (10) @(negedge gmii_rx_clk); rst_n = 1;
        repeat (10) @(negedge gmii_rx_clk);
        for (pi = 0; pi < PKTS; pi = pi + 1) send_pkt(pi);
        // 等排空（AXI 写完 TB_WORDS 个字，或超时）
        begin : drain
            integer t;
            t = 0;
            while (axi_wr < TB_WORDS && t < 2000000) begin
                @(posedge axi_clk); t = t + 1;
            end
            repeat (5000) @(posedge axi_clk);
            $display("drain: waited %0d axi cycles, axi_wr=%0d", t, axi_wr);
        end

        w_ok = 0; w_half = 0; w_zero = 0; w_other = 0; lane_bad = 0;
        for (pi = 0; pi < TB_WORDS; pi = pi + 1) begin
            exp64 = {pi[15:0], pi[15:0], pi[15:0], pi[15:0]};
            got64 = mem[pi];
            l0 = got64[15:0]; l1 = got64[31:16]; l2 = got64[47:32]; l3 = got64[63:48];
            if (got64 === exp64) w_ok = w_ok + 1;
            else begin
                if (l0 === 16'd0 && l1 === 16'd0 && l2 === 16'd0 && l3 === 16'd0)
                    w_zero = w_zero + 1;
                else if (((l1 === 16'd0 && l3 === 16'd0) && (l0 !== 16'd0 || l2 !== 16'd0)) ||
                         ((l0 === 16'd0 && l2 === 16'd0) && (l1 !== 16'd0 || l3 !== 16'd0)))
                    w_half = w_half + 1;
                else
                    w_other = w_other + 1;
                if (l0 !== pi[15:0]) lane_bad = lane_bad + 1;
                if (l1 !== pi[15:0]) lane_bad = lane_bad + 1;
                if (l2 !== pi[15:0]) lane_bad = lane_bad + 1;
                if (l3 !== pi[15:0]) lane_bad = lane_bad + 1;
                if (first_bad < 0) first_bad = pi;
            end
        end
        $display("[tb_eth_ingress_integrity:stage] stage counts: reasm_wr→cdc ok=%0d lost=%0d | cdc_rd=%0d | packer_drop=%0d | axi_wr=%0d (need %0d)",
                 cdc_ok, cdc_drop, cdc_rd, sv_drop, axi_wr, TB_WORDS);
        $display("reasm stats: frames=%0d pkts=%0d bytes=%0d bad=%0d oob=%0d",
                 s_frames, s_pkts, s_bytes, s_bad, s_oob);
        $display("words exact=%0d/%0d  half(1010/0101)=%0d  allzero=%0d  other=%0d  lanes_bad=%0d/%0d",
                 w_ok, TB_WORDS, w_half, w_zero, w_other, lane_bad, TB_WORDS*4);
        if (first_bad >= 0)
            $display("first bad word=%0d got=%h expected=%h",
                     first_bad, mem[first_bad],
                     {first_bad[15:0], first_bad[15:0], first_bad[15:0], first_bad[15:0]});
        $display("tail3: [%0d]=%h [%0d]=%h [%0d]=%h",
                 TB_WORDS-3, mem[TB_WORDS-3], TB_WORDS-2, mem[TB_WORDS-2],
                 TB_WORDS-1, mem[TB_WORDS-1]);
        $display("PROBE cdc peak_occupancy=%0d words of depth=%0d  （本次流量形状下的**下界**：读侧 sv_full 阻塞窗口未建模 ⇒ 不是设计界，见文件头 ①②③）",
                 cdc_peak, (1 << 13));
        if (cdc_peak == 0) begin
            $display("FAIL cdc peak probe never saw a non-empty FIFO");
            errors = errors + 1;
        end else $display("PASS cdc peak probe alive");
        $display("PROBE packer peak_occupancy=%0d words of depth=%0d  （FW=%0d；这一数决定 100bit×512 那 ~800 个 LUTRAM 能不能削 —— 峰值远低于半深才谈得上降 FW）",
                 sv_peak, (1 << 9), 9);
        if (sv_peak == 0) begin
            $display("FAIL packer peak probe never saw a non-empty FIFO (wrong name or no backpressure)");
            errors = errors + 1;
        end else $display("PASS packer peak probe alive");
        if (w_ok != TB_WORDS || cdc_drop != 0 || sv_drop != 0) begin
            $display("FAIL ingress loses data");
            errors = errors + 1;
        end else $display("PASS ingress lossless");
        if (s_frames != FULL) begin
            $display("FAIL frames_done=%0d expected=%0d (pkts=%0d words=%0d)",
                     s_frames, FULL, s_pkts, axi_wr);
            errors = errors + 1;
        end else if (FULL) $display("PASS full frame committed exactly once");
        else $display("PASS partial frame not committed");
        if (errors == 0) $display("PASS tb_eth_ingress_integrity");
        else $display("FAIL tb_eth_ingress_integrity errors=%0d", errors);
        $finish;
    end

    initial begin
        #80_000_000;
        $display("FAIL tb_eth_ingress_integrity timeout");
        $finish;
    end
endmodule
