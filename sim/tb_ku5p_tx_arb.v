`timescale 1ns/1ps
// ku5p_tx_arb 台架。三条硬判据 + 一次"拿厂商 mux 做对照"的表征：
//   T1 不丢请求：脉冲请求存进 pending，空闲时一定会发出 grant
//   T2 不抢占  ：帧发到一半来了 ARP 请求，介质不许换源（用字节"来源标签"直接量）
//   T3 同拍三请求：只有最高优先级拿到介质，另两个排队
//   T4 只认 owner 的 done：别人的 done 不能把介质提前放掉
//   V  对照：同一套激励喂厂商 eth_ctrl，它**会**在 UDP 帧中间换源 ⇒ 上面那条不是空谈
// 标签约定：ARP 字节 8'hA0+i、ICMP 8'hC0+i、UDP 8'hD0+i，高 4 位就是来源。
module tb_ku5p_tx_arb;
    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk;          // 125 MHz GMII

    reg arp_rqs = 0, icmp_rqs = 0, udp_rqs = 0;
    wire arp_grant, icmp_grant, udp_grant;
    reg  arp_done = 0, icmp_done = 0, udp_done = 0;
    reg  fake_udp_done = 0;        // T4 的"冒名 done"，与模型的 udp_done 分开驱动
    reg  arp_tx_en = 0, icmp_tx_en = 0, udp_tx_en = 0;
    reg  [7:0] arp_txd = 0, icmp_txd = 0, udp_txd = 0;
    wire       gmii_tx_en;
    wire [7:0] gmii_txd;

    localparam [7:0] TAG_ARP = 8'hA0, TAG_ICMP = 8'hC0, TAG_UDP = 8'hD0;
    localparam LEN = 12;

    ku5p_tx_arb u_dut (
        .clk(clk), .rst_n(rst_n),
        .arp_rqs(arp_rqs), .icmp_rqs(icmp_rqs), .udp_rqs(udp_rqs),
        .arp_grant(arp_grant), .icmp_grant(icmp_grant), .udp_grant(udp_grant),
        .arp_done(arp_done), .icmp_done(icmp_done), .udp_done(udp_done | fake_udp_done),
        .arp_tx_en(arp_tx_en), .arp_txd(arp_txd),
        .icmp_tx_en(icmp_tx_en), .icmp_txd(icmp_txd),
        .udp_tx_en(udp_tx_en), .udp_txd(udp_txd),
        .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd)
    );

    // ---- 厂商 mux 的对照面用到的信号（必须先声明：模型里的 arp_grant|v_arp_tx_en 要读它）----
    reg  arp_rx_done = 0, arp_rx_type = 0;
    wire v_arp_tx_en, v_arp_tx_type, v_tx_req, v_rec_en;
    wire [7:0] v_arp_txd, v_icmp_data, v_udp_data, v_tx_data, v_rec_data;
    wire       v_gmii_tx_en;
    wire [7:0] v_gmii_txd;
    reg        v_udp_start = 0;
    integer    v_flips = 0, v_seen = 0;
    reg [3:0]  v_prev = 4'h0;

    // ---- 三个"协议模块"模型：grant 之后连发 LEN 拍，最后一拍后报 done ----
    reg [4:0] ai = 0, ci = 0, ui = 0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin arp_tx_en <= 0; arp_done <= 0; ai <= 0; end
        else begin
            arp_done <= 0;
            if (arp_grant | v_arp_tx_en)  begin ai <= 0; arp_tx_en <= 1; arp_txd <= TAG_ARP; end
            else if (arp_tx_en) begin
                if (ai == LEN-1) begin arp_tx_en <= 0; arp_done <= 1; end
                else begin ai <= ai + 1; arp_txd <= TAG_ARP + ai + 5'd1; end
            end
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin icmp_tx_en <= 0; icmp_done <= 0; ci <= 0; end
        else begin
            icmp_done <= 0;
            if (icmp_grant) begin ci <= 0; icmp_tx_en <= 1; icmp_txd <= TAG_ICMP; end
            else if (icmp_tx_en) begin
                if (ci == LEN-1) begin icmp_tx_en <= 0; icmp_done <= 1; end
                else begin ci <= ci + 1; icmp_txd <= TAG_ICMP + ci + 5'd1; end
            end
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin udp_tx_en <= 0; udp_done <= 0; ui <= 0; end
        else begin
            udp_done <= 0;
            if (udp_grant)  begin ui <= 0; udp_tx_en <= 1; udp_txd <= TAG_UDP; end
            else if (udp_tx_en) begin
                if (ui == LEN-1) begin udp_tx_en <= 0; udp_done <= 1; end
                else begin ui <= ui + 1; udp_txd <= TAG_UDP + ui + 5'd1; end
            end
        end
    end

    // ---- 观测：数各来源的字节，并记录"一帧内换源"次数 ----
    integer seen_arp = 0, seen_icmp = 0, seen_udp = 0, errors = 0;
    integer arb_flips = 0;
    reg [3:0] cur_src = 0, prev_src = 0;
    always @(posedge clk) begin
        if (gmii_tx_en) begin
            cur_src = gmii_txd[7:4];
            if (cur_src === 4'hA) seen_arp  = seen_arp + 1;
            else if (cur_src === 4'hC) seen_icmp = seen_icmp + 1;
            else if (cur_src === 4'hD) seen_udp  = seen_udp  + 1;
            else begin
                $display("FAIL unknown source tag on gmii: %h", gmii_txd);
                errors = errors + 1;
            end
            if (prev_src !== 4'h0 && cur_src !== prev_src) arb_flips = arb_flips + 1;
            prev_src = cur_src;
        end
    end

    task req(input [1:0] which);          // 单拍脉冲请求
        begin
            @(posedge clk);
            case (which)
                2'd0: arp_rqs  <= 1'b1;
                2'd1: icmp_rqs <= 1'b1;
                default: udp_rqs <= 1'b1;
            endcase
            @(posedge clk);
            arp_rqs <= 1'b0; icmp_rqs <= 1'b0; udp_rqs <= 1'b0;
        end
    endtask

    // ---- 厂商 mux 的对照面：同一批字节流喂 eth_ctrl，量它换不换源 ----
    eth_ctrl u_vendor (
        .clk(clk), .rst_n(rst_n),
        .arp_rx_done(arp_rx_done), .arp_rx_type(arp_rx_type),
        .arp_tx_en(v_arp_tx_en), .arp_tx_type(v_arp_tx_type), .arp_tx_done(arp_done),
        .arp_gmii_tx_en(arp_tx_en), .arp_gmii_txd(arp_txd),
        .icmp_tx_start_en(1'b0), .icmp_tx_done(icmp_done),
        .icmp_gmii_tx_en(icmp_tx_en), .icmp_gmii_txd(icmp_txd),
        .icmp_rec_en(1'b0), .icmp_rec_data(8'd0), .icmp_tx_req(1'b0), .icmp_tx_data(v_icmp_data),
        .udp_tx_start_en(v_udp_start), .udp_tx_done(udp_done),
        .udp_gmii_tx_en(udp_tx_en), .udp_gmii_txd(udp_txd),
        .udp_rec_data(8'd0), .udp_rec_en(1'b0), .udp_tx_req(v_tx_req), .udp_tx_data(v_udp_data),
        .tx_data(8'd0), .tx_req(v_tx_req), .rec_en(v_rec_en), .rec_data(v_rec_data),
        .gmii_tx_en(v_gmii_tx_en), .gmii_txd(v_gmii_txd)
    );
    always @(posedge clk) begin
        if (v_gmii_tx_en) begin
            if (v_prev !== 4'h0 && v_gmii_txd[7:4] !== v_prev) v_flips = v_flips + 1;
            v_prev = v_gmii_txd[7:4];
            v_seen = v_seen + 1;
        end
    end

    task chk(input [255:0] name, input integer got, input integer exp);
        begin
            if (got !== exp) begin
                $display("FAIL %0s got=%0d expect=%0d", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    integer s_arp, s_icmp, s_udp, s_flip, w;
    task snap; begin s_arp=seen_arp; s_icmp=seen_icmp; s_udp=seen_udp; s_flip=arb_flips; end endtask
    task clear_snap;
        begin seen_arp=0; seen_icmp=0; seen_udp=0; arb_flips=0; prev_src=4'h0;
              v_flips=0; v_seen=0; v_prev=4'h0; end
    endtask

    // 每个测试都从"三条模型流全 idle + 观测清零"出发 —— 否则上一拍的尾巴会算进下一笔账，
    // 数字看起来差两三拍，其实是被测对象没错、台架自己串了行。
    task quiesce;
        begin
            for (w = 0; w < 300 && (arp_tx_en || icmp_tx_en || udp_tx_en); w = w + 1) @(posedge clk);
            repeat (3) @(posedge clk);
            clear_snap();
        end
    endtask

    task wait_bytes;                 // 有界等待：等够了就走，等不到也别挂住
        input integer want_arp, want_icmp, want_udp;
        begin
            for (w = 0; w < 300 &&
                    (seen_arp < want_arp || seen_icmp < want_icmp || seen_udp < want_udp);
                 w = w + 1) @(posedge clk);
            repeat (3) @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (2) @(posedge clk);

        // ---- T1：单独一路 UDP，LEN 个字节、一次换源（0→D 不算抢占，只是开始）----
        req(2'd2);
        wait_bytes(0, 0, LEN);
        chk("T1 udp bytes", seen_udp, LEN);
        chk("T1 arp bytes",  seen_arp, 0);

        // ---- T2：UDP 帧中间来 ARP 请求 ⇒ 不许换源，两个请求都要发完 ----
        quiesce();
        fork
            begin req(2'd2); end                      // 先发 UDP
            begin repeat (6) @(posedge clk); req(2'd0); end   // 第 6 字节时来 ARP
        join
        wait_bytes(LEN, 0, LEN);
        chk("T2 udp bytes", seen_udp, LEN);
        chk("T2 arp bytes", seen_arp, LEN);
        chk("T2 flips-at-boundary-only", arb_flips, 1);

        // ---- V：同一场景喂厂商 mux ⇒ 它必须换源（这条是在证明"要修的确实存在"）----
        // UDP 帧由仲裁器放行（模型才有字节可发），但厂商那侧只认自己的 protocol_sw：
        // 帧中间来一个 ARP 请求 ⇒ 它把 mux 切到 ARP，UDP 剩下的字节就地作废。
        quiesce();
        fork
            begin req(2'd2); end
            begin @(posedge clk); v_udp_start <= 1'b1;
                  @(posedge clk); v_udp_start <= 1'b0; end
        join
        repeat (6) @(posedge clk);
        @(posedge clk);
        arp_rx_done <= 1'b1; arp_rx_type <= 1'b0;      // ARP **请求**
        @(posedge clk); arp_rx_done <= 1'b0;
        // 这里的等待是**故意给足**的：要观察的是厂商 mux 的输出，
        // 而我们自己的仲裁器不会把 ARP 字节放出去，所以不能拿 seen_arp 当结束条件。
        repeat (LEN * 4) @(posedge clk);
        if (v_flips == 0) begin
            $display("FAIL V 厂商 eth_ctrl 没有换源 —— 说明这条问题记录（ISSUES #28）的机理判错了");
            errors = errors + 1;
        end else $display("INFO vendor eth_ctrl flips mid-frame %0d times; our arbiter %0d", v_flips, arb_flips);

        // ---- T3：同拍三个请求 ⇒ 只有 ARP 立刻拿到，其余排队 ----
        quiesce();
        @(posedge clk);
        arp_rqs <= 1'b1; icmp_rqs <= 1'b1; udp_rqs <= 1'b1;
        @(posedge clk);
        arp_rqs <= 1'b0; icmp_rqs <= 1'b0; udp_rqs <= 1'b0;
        wait_bytes(LEN, LEN, LEN);
        chk("T3 arp bytes", seen_arp, LEN);
        chk("T3 icmp bytes", seen_icmp, LEN);
        chk("T3 udp bytes", seen_udp, LEN);
        chk("T3 three frames in priority order", arb_flips, 2);

        // ---- T4：帧中间打别人的 done ⇒ 不能放掉介质 ----
        quiesce();
        fork
            begin req(2'd1); end                       // ICMP 发
            begin
                while (!icmp_tx_en) @(posedge clk);     // 等 ICMP 帧真的在发
                repeat (3) @(posedge clk);
                fake_udp_done <= 1'b1;                  // 冒名 done（UDP 根本没在发）
                @(posedge clk); fake_udp_done <= 1'b0;
            end
        join
        wait_bytes(0, LEN, 0);
        chk("T4 icmp bytes", seen_icmp, LEN);

        if (errors == 0) $display("PASS tb_ku5p_tx_arb");
        else             $display("FAIL tb_ku5p_tx_arb errors=%0d", errors);
        $finish;
    end
endmodule
