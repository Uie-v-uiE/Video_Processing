`timescale 1ns/1ps
// 功能：被测模块 `frame_reasm` #(.IMG_W(16), .IMG_H(8), .FRAME_BYTES(256))（一帧 128 像素 =
//        256 字节）；覆盖点：正序拼满一帧、乱序（先高偏移后低偏移）、s_good=0 的坏包计数、
//        重复包覆盖、第二次成帧，以及 wr_en/wr_addr/wr_data 写口落点与 stat_* 计数器。
// 激励与检查：时钟 always #4 clk=~clk（8 ns = 125 MHz），rst_n 拉低 5 拍后释放再等 2 拍；
//        每字节 send_byte 占 2 拍；每包 send_pkt 发 8 字节 = 偏移低字节（带 sof）+ 偏移中/高
//        两字节 + pix0 两字节 + pix1 两字节（带 eof 与 good）；台架在 posedge 抓 wr_en 并把
//        wr_addr<128 的 wr_data 记进 capture[]。正常段连发 64 包（偏移 k*4、k=0..63）覆盖
//        256 字节，判 s_frames==1、capture[0]==16'h1000、capture[1]==16'h2000；乱序段
//        send_pkt(8,16'hBEEF,16'hCAFE,1) 再 send_pkt(0,16'h1111,16'h2222,1)，判
//        capture[4]==16'hBEEF 且 capture[0]==16'h1111；坏包段 send_pkt(0,...,good=0) 判
//        s_bad≠0；重复段同一偏移连发两遍 16'hAAAA/16'h5555，判 capture[0]==16'hAAAA；
//        最后再发 64 包，判 s_frames==2。每段之间留 3~5 拍。
// 预期结果：通过时逐条打印 PASS normal full frame / PASS pixel0 / PASS pixel1 /
//        PASS OOS later-first / PASS OOS later-second / PASS bad counted /
//        PASS duplicate overwrite / PASS second frame after jump，末行 PASS tb_udp_reasm ALL；
//        失败时对应条打印 FAIL <判据名>: got <实测> exp <期望> 或 FAIL capture[0]=<hex> /
//        FAIL OOS addr4=<hex> / FAIL OOS addr0=<hex> / FAIL dup=<hex> / FAIL bad not counted，
//        errors 累加并末行改打 FAIL tb_udp_reasm errors=<n>。
// UDP frame reassembly TB: normal, OOS, drop, duplicate, frame jump, timeout-like bad
module tb_udp_reasm;
    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk; // 125 MHz

    reg [7:0] p_data = 0;
    reg p_valid = 0, p_sof = 0, p_eof = 0, p_good = 0;

    wire wr_en;
    wire [18:0] wr_addr;
    wire [15:0] wr_data;
    wire frame_done, frame_err;
    wire [31:0] s_frames, s_pkts, s_bytes, s_bad, s_oob;

    localparam W = 16, H = 8; // tiny frame: 16*8*2 = 256 bytes
    frame_reasm #(.IMG_W(W), .IMG_H(H), .FRAME_BYTES(256)) uut (
        .clk(clk), .rst_n(rst_n),
        .p_data(p_data), .p_valid(p_valid), .p_sof(p_sof), .p_eof(p_eof), .p_good(p_good),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .frame_done(frame_done), .frame_err(frame_err),
        .stat_frames(s_frames), .stat_pkts(s_pkts),
        .stat_bytes(s_bytes), .stat_bad(s_bad), .stat_oob_off(s_oob)
    );

    integer errors = 0;
    reg [15:0] capture [0:255];
    integer ncap = 0;

    always @(posedge clk) begin
        if (wr_en) begin
            if (wr_addr < 128) begin
                capture[wr_addr] <= wr_data;
                ncap <= ncap + 1;
            end
        end
    end

    task send_byte(input [7:0] b, input sof, input eof, input good);
        begin
            @(posedge clk);
            p_data <= b; p_valid <= 1; p_sof <= sof; p_eof <= eof; p_good <= good;
            @(posedge clk);
            p_valid <= 0; p_sof <= 0; p_eof <= 0; p_good <= 0;
        end
    endtask

    task send_pkt(input [31:0] off, input [15:0] pix0, input [15:0] pix1, input good);
        integer i;
        begin
            send_byte(off[7:0],   1, 0, 0);
            send_byte(off[15:8],  0, 0, 0);
            send_byte(off[23:16], 0, 0, 0);
            send_byte(off[31:24], 0, 0, 0);
            send_byte(pix0[7:0],  0, 0, 0);
            send_byte(pix0[15:8], 0, 0, 0);
            send_byte(pix1[7:0],  0, 0, 0);
            send_byte(pix1[15:8], 0, 1, good);
        end
    endtask

    task expect_eq(input [31:0] a, input [31:0] b, input [255:0] msg);
        begin
            if (a !== b) begin
                $display("FAIL %0s: got %0d exp %0d", msg, a, b);
                errors = errors + 1;
            end else
                $display("PASS %0s", msg);
        end
    endtask

    integer k;
    initial begin
        $dumpfile("tb_udp_reasm.vcd");
        $dumpvars(0, tb_udp_reasm);
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // 1) normal in-order packets covering a full tiny frame
        // 128 pixels * 2 = 256 bytes; 4 pixels/pkt => 8 bytes payload + 4 off = 12, use 2 pix/pkt
        for (k = 0; k < 64; k = k + 1) begin
            send_pkt(k*4, k[15:0]+16'h1000, k[15:0]+16'h2000, 1);
        end
        repeat (5) @(posedge clk);
        expect_eq(s_frames, 1, "normal full frame");
        if (capture[0] !== 16'h1000) begin
            $display("FAIL capture[0]=%h", capture[0]);
            errors = errors + 1;
        end else $display("PASS pixel0");
        if (capture[1] !== 16'h2000) begin
            $display("FAIL capture[1]=%h", capture[1]);
            errors = errors + 1;
        end else $display("PASS pixel1");

        // 2) out-of-order: send later offset first
        send_pkt(8, 16'hBEEF, 16'hCAFE, 1);
        send_pkt(0, 16'h1111, 16'h2222, 1);
        repeat (3) @(posedge clk);
        if (capture[4] !== 16'hBEEF) begin
            $display("FAIL OOS addr4=%h", capture[4]);
            errors = errors + 1;
        end else $display("PASS OOS later-first");
        if (capture[0] !== 16'h1111) begin
            $display("FAIL OOS addr0=%h", capture[0]);
            errors = errors + 1;
        end else $display("PASS OOS later-second");

        // 3) bad packet increments bad counter, no frame
        send_pkt(0, 16'h0000, 16'h0000, 0);
        repeat (3) @(posedge clk);
        if (s_bad == 0) begin
            $display("FAIL bad not counted");
            errors = errors + 1;
        end else $display("PASS bad counted");

        // 4) duplicate packet just overwrites
        send_pkt(0, 16'hAAAA, 16'h5555, 1);
        send_pkt(0, 16'hAAAA, 16'h5555, 1);
        repeat (3) @(posedge clk);
        if (capture[0] !== 16'hAAAA) begin
            $display("FAIL dup=%h", capture[0]);
            errors = errors + 1;
        end else $display("PASS duplicate overwrite");

        // 5) frame id jump: enough new coverage to complete another frame
        for (k = 0; k < 64; k = k + 1)
            send_pkt(k*4, k[15:0], k[15:0], 1);
        repeat (5) @(posedge clk);
        expect_eq(s_frames, 2, "second frame after jump");

        if (errors == 0) $display("PASS tb_udp_reasm ALL");
        else $display("FAIL tb_udp_reasm errors=%0d", errors);
        $finish;
    end
endmodule
