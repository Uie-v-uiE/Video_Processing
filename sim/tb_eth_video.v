`timescale 1ns/1ps
// 功能：被测模块 `udp_tx + crc32_d8 + udp_rx + frame_reasm`（GMII 直环：u_tx 的 gmii_tx_en/txd 直接喂
//        u_rx 的 rx_dv/rxd，u_reasm 参数 IMG_W=8、IMG_H=4、FRAME_BYTES=128）；覆盖点＝一发一收的字节数
//        与载荷不被截断、两包（偏移 0 与偏移 64）拼满一帧后 frame_reasm 的帧计数出帧。
// 激励与检查：时钟 #4 翻转（8 ns，GMII 125 MHz），rst_n 拉低 4 拍后释放再等 2 拍；tx_len=68 配
//        tx_start 一拍发出 UDP 载荷（前 4 字节是帧内偏移，后 64 字节是第一包 k[7:0]、第二包 8'h80+k）；
//        每包等 tx_done，超过 5000 个时钟拍未等到即判 `FAIL timeout tx`，随后再放 20 拍；
//        判据 1 数 rec_en 拍数 n_rec 必须等于 68；判据 2 第二包之后 frame_reasm 的 stat_frames(sf) 必须
//        >= 1（wr_data 按 wr_addr 存进 cap[] 只做观测，本轮不参与判定）。
// 预期结果：通过时依次打印 `PASS udp payload len`、`PASS frame complete sf=<n> n_wr=<n>`，末行
//        `PASS tb_eth_video ALL`，同时 dump tb_eth_video.vcd 可看 txd→rec_en→wr_en 一条链的时序；
//        失败时打印 `FAIL timeout tx`、`FAIL n_rec=<n> exp 68` 或 `FAIL no frame complete sf=<n> n_wr=<n>`，
//        errors 加一并把末行改成 `FAIL tb_eth_video errors=<n>`。
// GMII-level UDP TX→RX loopback + video reassembly (no fork).
module tb_eth_video;
    localparam [47:0] MAC = 48'h00_11_22_33_44_55;
    localparam [31:0] IP  = {8'd192,8'd168,8'd1,8'd10};
    localparam [15:0] PORT = 16'd5001;

    reg clk=0, rst_n=0;
    always #4 clk=~clk;

    reg tx_start=0;
    wire [7:0] tx_data;
    reg [15:0] tx_len=0;
    wire tx_done, tx_req, tx_en;
    wire [7:0] txd;
    wire [31:0] crc_data, crc_next;
    wire crc_en, crc_clr;

    udp_tx #(.BOARD_MAC(MAC), .BOARD_IP(IP),
             .DES_MAC(48'hFF_FF_FF_FF_FF_FF), .DES_IP(IP)) u_tx (
        .clk(clk), .rst_n(rst_n),
        .tx_start_en(tx_start), .tx_data(tx_data), .tx_byte_num(tx_len),
        .des_mac(48'hFF_FF_FF_FF_FF_FF), .des_ip(IP),
        .crc_data(crc_data), .crc_next(crc_next[31:24]),
        .tx_done(tx_done), .tx_req(tx_req),
        .gmii_tx_en(tx_en), .gmii_txd(txd),
        .crc_en(crc_en), .crc_clr(crc_clr)
    );
    crc32_d8 u_crc (.clk(clk), .rst_n(rst_n), .data(txd),
                    .crc_en(crc_en), .crc_clr(crc_clr),
                    .crc_data(crc_data), .crc_next(crc_next));

    wire rec_done, rec_en;
    wire [7:0] rec_data;
    wire [15:0] rec_nbytes;

    udp_rx #(.BOARD_MAC(MAC), .BOARD_IP(IP)) u_rx (
        .clk(clk), .rst_n(rst_n),
        .gmii_rx_dv(tx_en), .gmii_rxd(txd),
        .rec_pkt_done(rec_done), .rec_en(rec_en), .rec_data(rec_data),
        .rec_byte_num(rec_nbytes)
    );

    reg in_pkt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) in_pkt<=0;
        else if (rec_done) in_pkt<=0;
        else if (rec_en) in_pkt<=1;
    end
    wire sof = rec_en && !in_pkt;

    wire wr_en, frame_done;
    wire [18:0] wr_addr;
    wire [15:0] wr_data;
    wire [31:0] sf,sp,sb,sd,so;

    frame_reasm #(.IMG_W(8), .IMG_H(4), .FRAME_BYTES(128)) u_reasm (
        .clk(clk), .rst_n(rst_n),
        .p_data(rec_data), .p_valid(rec_en), .p_sof(sof), .p_eof(rec_done), .p_good(1'b1),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .frame_done(frame_done), .frame_err(),
        .stat_frames(sf), .stat_pkts(sp), .stat_bytes(sb), .stat_bad(sd), .stat_oob_off(so)
    );

    reg [15:0] cap [0:63];
    always @(posedge clk) if (wr_en && wr_addr<64) cap[wr_addr] <= wr_data;

    integer errors=0, k, tmo;
    reg [7:0] pay [0:127];
    integer pidx=0;
    assign tx_data = pay[pidx];
    always @(posedge clk) begin
        if (tx_start) pidx <= 0;
        else if (tx_req) pidx <= pidx + 1;
    end

    task run_pkt(input [15:0] nbytes);
        begin
            tmo = 0;
            @(posedge clk);
            tx_len <= nbytes;
            tx_start <= 1;
            @(posedge clk);
            tx_start <= 0;
            while (!tx_done && tmo < 5000) begin
                @(posedge clk);
                tmo = tmo + 1;
            end
            if (!tx_done) begin
                $display("FAIL timeout tx");
                errors = errors + 1;
            end
            repeat (20) @(posedge clk);
        end
    endtask

    integer n_rec=0;
    always @(posedge clk) if (rec_en) n_rec = n_rec + 1;
    integer n_wr=0;
    always @(posedge clk) if (wr_en) n_wr = n_wr + 1;

    initial begin
        $dumpfile("tb_eth_video.vcd");
        $dumpvars(0, tb_eth_video);
        for (k=0;k<128;k=k+1) pay[k]=0;
        repeat(4) @(posedge clk);
        rst_n=1;
        repeat(2) @(posedge clk);

        pay[0]=0; pay[1]=0; pay[2]=0; pay[3]=0;
        for (k=0;k<64;k=k+1) pay[4+k] = k[7:0];
        run_pkt(68);
        if (n_rec != 68) begin
            $display("FAIL n_rec=%0d exp 68", n_rec);
            errors=errors+1;
        end else $display("PASS udp payload len");

        pay[0]=64; pay[1]=0; pay[2]=0; pay[3]=0;
        for (k=0;k<64;k=k+1) pay[4+k] = 8'h80 + k[7:0];
        run_pkt(68);

        if (sf < 1) begin
            $display("FAIL no frame complete sf=%0d n_wr=%0d", sf, n_wr);
            errors=errors+1;
        end else $display("PASS frame complete sf=%0d n_wr=%0d", sf, n_wr);

        if (errors==0) $display("PASS tb_eth_video ALL");
        else $display("FAIL tb_eth_video errors=%0d", errors);
        $finish;
    end
endmodule
