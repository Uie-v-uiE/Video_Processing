`timescale 1ns/1ps
// tb_eth_ctrl_arb — 发送仲裁的帧完整性判据。
// 场景：ICMP 帧发送途中来 UDP 信标请求、UDP 帧途中来 ARP 请求。
// 判据：① 一帧之内 gmii_txd 不许换值（换源=帧被截断）；② 三帧按 ICMP→UDP→ARP 顺序发完；
//       ③ 两次请求都被兑现（各有 granted 脉冲），不是被丢掉。
// 旧 eth_ctrl 在请求那一拍直接切 protocol_sw，这个台架会红在"帧中间换值"。
module tb_eth_ctrl_arb;
    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk;

    reg arp_rx_done = 0, arp_rx_type = 1;
    wire arp_tx_en, arp_tx_type;
    reg  arp_tx_done = 0;
    reg  arp_gmii_tx_en = 0;
    reg  [7:0] arp_gmii_txd = 8'hA1;

    reg  icmp_req = 0;
    reg  icmp_tx_done = 0;
    reg  icmp_gmii_tx_en = 0;
    reg  [7:0] icmp_gmii_txd = 8'hC1;

    reg  udp_req = 0;
    reg  udp_tx_done = 0;
    reg  udp_gmii_tx_en = 0;
    reg  [7:0] udp_gmii_txd = 8'hD1;

    wire udp_start_g, icmp_start_g;
    wire tx_req, rec_en;
    wire [7:0] rec_data, icmp_tx_data, udp_tx_data;
    wire gmii_tx_en;
    wire [7:0] gmii_txd;

    eth_ctrl u (
        .clk(clk), .rst_n(rst_n),
        .arp_rx_done(arp_rx_done), .arp_rx_type(arp_rx_type),
        .arp_tx_en(arp_tx_en), .arp_tx_type(arp_tx_type), .arp_tx_done(arp_tx_done),
        .arp_gmii_tx_en(arp_gmii_tx_en), .arp_gmii_txd(arp_gmii_txd),
        .icmp_tx_start_en(icmp_req), .icmp_tx_done(icmp_tx_done),
        .icmp_gmii_tx_en(icmp_gmii_tx_en), .icmp_gmii_txd(icmp_gmii_txd),
        .icmp_rec_en(1'b0), .icmp_rec_data(8'd0),
        .icmp_tx_req(1'b0), .icmp_tx_data(icmp_tx_data),
        .udp_tx_start_en(udp_req), .udp_tx_done(udp_tx_done),
        .udp_start_g(udp_start_g), .icmp_start_g(icmp_start_g),
        .udp_gmii_tx_en(udp_gmii_tx_en), .udp_gmii_txd(udp_gmii_txd),
        .udp_rec_data(8'd0), .udp_rec_en(1'b0),
        .udp_tx_req(1'b0), .udp_tx_data(udp_tx_data),
        .tx_data(8'd0), .tx_req(tx_req),
        .rec_en(rec_en), .rec_data(rec_data),
        .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd)
    );

    // 三路假发送器：granted 后拉 tx_en 12 拍，末拍给 done。
    reg [3:0] icnt = 0, ucnt = 0, acnt = 0;
    reg ien = 0, uen = 0, aen = 0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ien<=0; uen<=0; aen<=0; icnt<=0; ucnt<=0; acnt<=0;
            icmp_tx_done<=0; udp_tx_done<=0; arp_tx_done<=0;
        end else begin
            icmp_tx_done<=0; udp_tx_done<=0; arp_tx_done<=0;
            if (icmp_start_g) begin ien<=1; icnt<=4'd12; end
            else if (ien) begin
                if (icnt==0) begin ien<=0; icmp_tx_done<=1; end
                else icnt<=icnt-1'b1;
            end
            if (udp_start_g) begin uen<=1; ucnt<=4'd12; end
            else if (uen) begin
                if (ucnt==0) begin uen<=0; udp_tx_done<=1; end
                else ucnt<=ucnt-1'b1;
            end
            if (arp_tx_en) begin aen<=1; acnt<=4'd12; end
            else if (aen) begin
                if (acnt==0) begin aen<=0; arp_tx_done<=1; end
                else acnt<=acnt-1'b1;
            end
        end
    end
    always @(*) begin
        icmp_gmii_tx_en = ien; udp_gmii_tx_en = uen; arp_gmii_tx_en = aen;
    end

    // 监视器：一帧内字节必须恒定；记录每帧首字节。
    integer frames = 0, errors = 0, starts_icmp = 0, starts_udp = 0, starts_arp = 0;
    reg in_frame = 0;
    reg [7:0] cur, seq [0:3];
    // 换源还有一个形状：mux 先断一拍再接到新源 —— 帧被截短。
    // 每帧必须是 13 个 tx_en 周期；短了就是 FAIL，不能只比"帧内字节是否恒定"。
    reg prev_en = 0;
    integer fcount = 0;
    always @(posedge clk) begin
        prev_en <= gmii_tx_en;
        if (gmii_tx_en) fcount <= fcount + 1;
        if (prev_en && !gmii_tx_en) begin
            if (fcount != 13) begin
                $display("FAIL frame truncated: %0d bytes (exp 13)", fcount);
                errors = errors + 1;
            end
            fcount <= 0;
        end
        if (gmii_tx_en) begin
            if (!in_frame) begin
                in_frame <= 1;
                cur <= gmii_txd;
                if (frames < 3) seq[frames] <= gmii_txd;
                frames = frames + 1;
            end else if (gmii_txd !== cur) begin
                $display("FAIL frame %0d switched mid-frame: %02x -> %02x", frames-1, cur, gmii_txd);
                errors = errors + 1;
            end
        end else in_frame <= 0;
        if (icmp_start_g) starts_icmp = starts_icmp + 1;
        if (udp_start_g)  starts_udp  = starts_udp + 1;
        if (arp_tx_en)    starts_arp  = starts_arp + 1;
    end

    initial begin
        repeat (5) @(posedge clk); rst_n = 1;
        repeat (3) @(posedge clk);
        icmp_req <= 1; @(posedge clk); icmp_req <= 0;
        wait (gmii_tx_en);                 // ICMP 帧已在线上
        @(posedge clk); udp_req <= 1; @(posedge clk); udp_req <= 0;
        @(posedge clk); arp_rx_done <= 1; arp_rx_type <= 1'b0;
        @(posedge clk); arp_rx_done <= 0;
        wait (frames == 3);
        repeat (10) @(posedge clk);

        if (frames != 3) begin $display("FAIL frame count %0d", frames); errors=errors+1; end
        if (seq[0] !== 8'hC1) begin $display("FAIL T1 first=%02x exp C1", seq[0]); errors=errors+1; end
        if (seq[1] !== 8'hD1) begin $display("FAIL T2 second=%02x exp D1", seq[1]); errors=errors+1; end
        if (seq[2] !== 8'hA1) begin $display("FAIL T3 third=%02x exp A1", seq[2]); errors=errors+1; end
        if (starts_icmp != 1 || starts_udp != 1 || starts_arp != 1) begin
            $display("FAIL grants icmp=%0d udp=%0d arp=%0d (each must be 1)", starts_icmp, starts_udp, starts_arp);
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS tb_eth_ctrl_arb order=ICMP,UDP,ARP no mid-frame switch");
        else             $display("FAIL tb_eth_ctrl_arb errors=%0d", errors);
        $finish;
    end
    initial begin #100000; $display("FAIL tb_eth_ctrl_arb timeout frames=%0d", frames); $finish; end
endmodule
