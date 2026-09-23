`timescale 1ns/1ps
// tb_v795_rx_fcs —— 证明"收侧自己算 FCS"这件事真的成立，并把残值常数钉住。
//
// 为什么要独立算 FCS：RTL 里用的是发送侧同一个 `crc32_d8`，如果我只拿它自己来验它自己，
// 那"残值是常数"这件事可以是同义反复（两边一起错也照样过）。所以这里的帧**由 TB 用另一套实现
// 造出来**：标准以太网 CRC-32（反射、多项式 0xEDB88320、初值 FFFFFFFF、末异或 FFFFFFFF），
// 也就是 `sim/tb_ku5p_telem.v` 里那套已经被 Node 独立算过一遍的实现（残值 0x2144DF1C 那一条）。
// ⇒ 如果 `crc32_d8` 的约定不是标准以太网，那么：
//    ① 两种不同内容的帧会算出**两个不同的残值**（T1 vs T2 会红），
//    ② 或者干脆连"好帧"都不认（T1 的 m_good 会红）。
// 两种情况都会被抓到，所以这 4 条判据是有牙的。
module tb_v795_rx_fcs;

    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk;                 // 125 MHz

    reg [7:0] rxd = 8'h00;
    reg       dv  = 1'b0;
    reg       er  = 1'b0;
    wire [7:0] m_data;
    wire       m_valid, m_sof, m_eof, m_good, m_bad;

    gmii_rx_mac dut (
        .clk(clk), .rst_n(rst_n), .gmii_rxd(rxd), .gmii_rx_dv(dv), .gmii_rx_er(er),
        .m_data(m_data), .m_valid(m_valid), .m_sof(m_sof), .m_eof(m_eof),
        .m_good(m_good), .m_bad(m_bad)
    );

    // ---- 独立实现的标准 CRC-32（反射 / EDB88320）----
    function [31:0] crc32_step;
        input [7:0]  b;
        input [31:0] seed;
        integer i; reg [31:0] c;
        begin
            c = seed ^ {24'd0, b};
            for (i = 0; i < 8; i = i + 1)
                if (c & 32'd1) c = (c >> 1) ^ 32'hEDB8_8320;
                else           c =  c >> 1;
            crc32_step = c;
        end
    endfunction

    // ---- 帧缓冲：preamble(7)+SFD(1)+DA(6)+SA(2)+type(2)+payload+FCS(4) ----
    localparam integer HDR  = 7 + 1 + 6 + 6 + 2;      // 前导码/SFD 之后到 type 结束
    localparam integer PAY  = 46;                     // 46 字节载荷 ⇒ 整帧 60+4 = 64 字节（以太网最小帧）
    localparam integer FLEN = HDR + PAY + 4;
    reg [7:0] fr [0:FLEN-1];

    task build_frame;
        input integer seed;                            // 换 seed 就换内容（残值必须不变）
        integer k; reg [31:0] c; reg [7:0] b;
        begin
            for (k = 0; k < 7; k = k + 1) fr[k] = 8'h55;
            fr[7]  = 8'hD5;
            fr[8]  = 8'h01; fr[9]  = 8'h23; fr[10] = 8'h45;      // DA
            fr[11] = 8'h67; fr[12] = 8'h89; fr[13] = 8'hab;
            fr[14] = 8'hc0; fr[15] = 8'ha8; fr[16] = 8'h00;      // SA
            fr[17] = 8'h01; fr[18] = 8'h12; fr[19] = 8'h34;
            fr[20] = 8'h08; fr[21] = 8'h00;                      // type = IPv4
            c = 32'hFFFF_FFFF;
            for (k = HDR; k < HDR + PAY; k = k + 1) begin
                b = k[7:0] ^ seed[7:0];
                fr[k] = b;
                c = crc32_step(b, c);
            end
            c = c ^ 32'hFFFF_FFFF;                    // 标准末异或
            // FCS 在线上是 LSB 先出
            fr[HDR+PAY+0] = c[ 7: 0];
            fr[HDR+PAY+1] = c[15: 8];
            fr[HDR+PAY+2] = c[23:16];
            fr[HDR+PAY+3] = c[31:24];
        end
    endtask

    // 发一帧（len 可短于整帧，用来造"太短"的反例）
    // 计数放在**独立 always**里：第一版把 `if (m_good)` 写在 send_frame 的字节循环里，
    // 而 m_good 是在 DV 落下之后那一拍才脉冲的 —— 循环早就退出了，于是 good/bad 恒 0，
    // 看起来像"DUT 不判帧"，其实是台架自己没采到（这类错必须先怀疑量具）。
    integer good_cnt, bad_cnt, byte_cnt;
    always @(posedge clk) begin
        if (m_valid) byte_cnt = byte_cnt + 1;
        if (m_good)  good_cnt = good_cnt + 1;
        if (m_bad)   bad_cnt  = bad_cnt  + 1;
    end

    task send_frame;
        input integer len;
        input integer flip;                            // >=0 ⇒ 把该下标的字节翻 1 bit（制造坏帧）
        integer k;
        begin
            for (k = 0; k < len; k = k + 1) begin
                @(negedge clk);
                rxd = fr[k];
                if (k == flip) rxd = rxd ^ 8'h01;
                dv = 1'b1; er = 1'b0;
            end
            @(negedge clk); dv = 1'b0; er = 1'b0;
            repeat (6) @(posedge clk);                 // 让帧尾脉冲被上面的 always 采到
        end
    endtask

    integer errors = 0;
    task chk(input [255:0] name, input integer got, input integer exp);
        begin
            if (got !== exp) begin
                $display("FAIL %0s got=%0d expect=%0d", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    reg [31:0] res1, res2;
    initial begin
        good_cnt = 0; bad_cnt = 0; byte_cnt = 0;
        rst_n = 0; repeat (3) @(posedge clk); #1 rst_n = 1; repeat (3) @(posedge clk); #1;

        // T0：**先验量具自己** —— 把 TB 亲手造的整帧（含 FCS）过一遍标准 CRC。
        // 反射 CRC-32（0xEDB88320，初值 FFFFFFFF）有个性质：**"消息 + 附带的 4 字节 FCS" 再过一遍，
        // 累加器必然停在一个与内容无关的常数** —— 不做末异或是 0xDEBB20E3，做末异或是 0x2144DF1C
        // （两者互为按位取反，所以这一条同时把 `tb_ku5p_telem` 里钉的那个常数也对上了）。
        // 这一条不过，就说明本台架造的帧根本不是合法以太网帧，后面四条判据全部无意义。
        begin : t0
            integer q; reg [31:0] c0;
            build_frame(8'h00);
            c0 = 32'hFFFF_FFFF;
            for (q = HDR; q < FLEN; q = q + 1) c0 = crc32_step(fr[q], c0);
            if (c0 !== 32'hDEBB_20E3) begin
                $display("FAIL T0 台架自校：造出来的帧不是标准 FCS（校验值=%h，应为 debb20e3）", c0);
                errors = errors + 1;
            end else if ((c0 ^ 32'hFFFF_FFFF) !== 32'h2144_DF1C) begin
                $display("FAIL T0 与 tb_ku5p_telem 的常数口径不一致");
                errors = errors + 1;
            end else $display("INFO T0 量具自校通过（debb20e3 == ~2144df1c）");
        end

        // T1：内容 A 的合法帧 ⇒ 必须判好；记下这一帧算完的残值
        build_frame(8'h00);
        send_frame(FLEN, -1);
        res1 = dut.crc_q;                              // DUT 内部残值（层次引用，只为把常数量出来）
        chk("T1 好帧计入 good", good_cnt, 1);
        chk("T1 好帧不计坏",    bad_cnt,  0);
        $display("INFO T1 residue=%h（内容 A）", res1);

        // T2：换内容的合法帧 ⇒ 残值必须与 T1 **相同**，且仍判好
        build_frame(8'h5A);
        send_frame(FLEN, -1);
        res2 = dut.crc_q;
        chk("T2 好帧计入 good", good_cnt, 2);
        chk("T2 好帧不计坏",    bad_cnt,  0);
        if (res2 !== res1) begin
            $display("FAIL 残值与内容有关（%h vs %h）⇒ 这个约定不是标准以太网，或者判据形式错了", res1, res2);
            errors = errors + 1;
        end
        $display("INFO T2 residue=%h（内容 B，必须与 A 相同）", res2);

        // T3：载荷里翻一个 bit，FCS 没跟着改 ⇒ 必须判坏（这是本模块存在的全部理由）
        build_frame(8'h5A);
        send_frame(FLEN, HDR + 3);
        chk("T3 坏帧计入 bad",  bad_cnt,  1);
        chk("T3 坏帧不判好",    good_cnt, 2);

        // T4：整帧太短（<64 字节）⇒ 也算坏（长度规则不能被 FCS 顶掉）
        build_frame(8'h00);
        send_frame(HDR + 20, -1);
        chk("T4 短帧计入 bad",  bad_cnt,  2);
        chk("T4 短帧不判好",    good_cnt, 2);

        // T5：残值常数被钉住 —— RTL 里的 localparam 必须等于实测值
        chk("T5 RTL 常数 == 实测残值", (dut.FCS_RESIDUE === res1) ? 1 : 0, 1);
        $display("INFO 字节数=%0d good=%0d bad=%0d", byte_cnt, good_cnt, bad_cnt);

        if (errors == 0) $display("PASS tb_v795_rx_fcs");
        else             $display("FAIL tb_v795_rx_fcs errors=%0d", errors);
        $finish;
    end

    initial begin
        #500_000;
        $display("FAIL watchdog：台架超时未跑完");
        $finish;
    end
endmodule
