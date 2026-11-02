`timescale 1ns/1ps
// 功能：被测模块 `frame_reasm`（例化 `uut`，.IMG_W(16) / .IMG_H(8) / .FRAME_BYTES(256) ⇒ 帧缓存
// 128 个 16 位字、合法字索引 0..127）；覆盖点：#201 —— 偏移越出帧缓存的包不许发 wr_en 但
// 必须被 stat_oob_off 数到，同时边界与正常路径不许被收紧。
// 激励与检查：#4 翻转时钟（8 ns = 125 MHz，与 gmii_rx_clk 同频）；每个场景 clean_start 在
// negedge 复位 4 拍、放开后再 2 拍并把 w_total/w_oob/w_max/done_pulse 清零；一包 = 4 个小端
// 偏移字节 + 4 个数据字节（p_sof 落在首字节、p_eof 落在末字节并带 p_good），逐字节每拍一个；
// 三个场景各喂一种：off=288（=FB+32，期望字索引 144/145 全越界，R1+R2 同根）、
// off=FB-4=252（末合法字对 126/127）、整帧 FB/4=64 包（off=k*4，k=0..63）；p_good 全程为 1。
// 判定条件：R1 越界包 w_total==0 && w_oob==0；R2 同一个包 (stat_oob-oob_before)>=1；
// R3 末字包 w_total==2 && w_max==WORDS-1(=127)；R4 整帧 done_pulse==1 && stat_frames==1 &&
// w_total==128 && w_max==127；R4a stat_pkts==64 && stat_bad==0（wr_addr>=WORDS 记为越界写，
// 由台架在 posedge 独立累加，不复用 RTL 的谓词）。
// 预期结果：通过时逐条打 `PASS R1..R4a <判据名>`，每段前带一条 INFO 现场行
// （如 `INFO R1 off=288 越界包：写次数=%0d（其中越界 %0d）最大字索引=%0d stat_oob_off +%0d`），
// errors==0 收尾打 `RESULT tb_reasm_bounds PASS`；失败时对应条打 `FAIL <判据名>`（R1 是
// 改前必红的那条，R2 改前改后都要绿），收尾打 `RESULT tb_reasm_bounds FAIL nfail=%0d`，
// 4 ms 看门狗到点打 `FAIL tb_reasm_bounds timeout` + `RESULT tb_reasm_bounds FAIL
// nfail=timeout`。
// tb_reasm_bounds —— #201 的尺子：`byte_off` 超出帧缓存的包**不许**发出 `wr_en`，但必须被数出来。
//
// 为什么现在要有它：`frame_reasm.v:120-125` 那三行（`wr_en<=1; wr_data<=…; wr_addr<=off[18:1];`）
// 是无条件写的，而紧跟着的 `if (off < FRAME_BYTES)` 只管理"行覆盖统计"（`row_ok/rows_hit`），
// 越界那一支只把 `stat_oob_off` 加一。也就是说**发包方自己选的偏移**能一路写到帧缓存之外：
// `off` 是 32 位而 `wr_addr` 取 `off[18:1]` ⇒ 索引能跑到 FRAME_BYTES/2 之后约 1.7 倍处；
// 下游 `axi_frame_saver64.v` 整个文件没有任何 `wr_addr` 上界检查（`:88/:110` 直接把索引乘进地址）。
// 这是网络上就能敲出来的（不需要任何权限，只要连着 ETH），严重度中—高。
//
// 几何与既有台架一致（W=16,H=8,FRAME_BYTES=256 ⇒ 128 个字，行距 32 字节 = 16 像素），
// 每包 4 个头字节 + 4 个数据字节 ⇒ 两个 16 位字。期望值全部由这个几何算，不从 RTL 抄谓词。
//
// 四条判据的分工（缺一条就是空转）：
//   R1 缺陷本身：越界包发出 0 次写 —— **改前必红**（今天它发 2 次）。
//   R2 不许静默：同一个包必须把 `stat_oob_off` 加上 —— 改前改后都要绿；
//      这一条存在是因为"修好"最省事的做法是连统计一起删，那等于把缺陷藏起来。
//   R3 边界不许收Too紧：最后一个合法字（索引 127）必须照写 —— 若把 `<` 写成 `<=`/`-2` 之类，
//      这里就少一次写，帧缓存右下角会黑一块，而位置类尺子（#92/#93）看不见它。
//   R4 正常路径不动：整帧 64 包必须仍然 `frame_done` 一次、`stat_frames` 加一。
module tb_reasm_bounds;
    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk;                      // 125 MHz，与 gmii_rx_clk 同频

    reg [7:0] p_data = 0;
    reg p_valid = 0, p_sof = 0, p_eof = 0, p_good = 0;
    wire        wr_en, frame_done, frame_err, flush;
    wire [18:0] wr_addr;
    wire [15:0] wr_data;
    wire [31:0] stat_frames, stat_pkts, stat_bytes, stat_bad, stat_oob;

    localparam integer W = 16, H = 8, FB = 256;
    localparam integer WORDS = FB/2;           // 合法字索引 0..127

    frame_reasm #(.IMG_W(W), .IMG_H(H), .FRAME_BYTES(FB)) uut (
        .clk(clk), .rst_n(rst_n),
        .p_data(p_data), .p_valid(p_valid), .p_sof(p_sof), .p_eof(p_eof), .p_good(p_good),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .flush(flush),
        .frame_done(frame_done), .frame_err(frame_err),
        .frame_abort(), .rows_missed(),
        .stat_frames(stat_frames), .stat_pkts(stat_pkts), .stat_bytes(stat_bytes),
        .stat_bad(stat_bad), .stat_oob_off(stat_oob));

    integer errors = 0;
    integer w_total = 0, w_oob = 0, w_max = 0;   // 本场景的写次数 / 越界写次数 / 最大字索引
    integer done_pulse = 0;

    always @(posedge clk) if (wr_en) begin
        w_total = w_total + 1;
        if (wr_addr >= WORDS) w_oob = w_oob + 1;
        if (wr_addr >  w_max) w_max = wr_addr;
    end
    always @(posedge clk) if (frame_done) done_pulse = done_pulse + 1;

    task chk(input [8*140:1] named, input ok);
        begin
            if (ok) $display("PASS %0s", named);
            else  begin $display("FAIL %0s", named); errors = errors + 1; end
        end
    endtask

    task send_byte(input [7:0] b, input sof, input eof, input good);
        begin
            @(posedge clk);
            p_data <= b; p_valid <= 1; p_sof <= sof; p_eof <= eof; p_good <= good;
            @(posedge clk);
            p_valid <= 0; p_sof <= 0; p_eof <= 0; p_good <= 0;
        end
    endtask

    // 一包 = 4 个小端偏移字节 + 4 个数据字节（两个 16 位字）
    task send_pkt(input [31:0] off, input [15:0] pix0, input [15:0] pix1, input good);
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

    task clean_start;
        begin
            @(negedge clk); rst_n = 0;
            repeat (4) @(negedge clk);
            w_total = 0; w_oob = 0; w_max = 0; done_pulse = 0;
            @(negedge clk); rst_n = 1;
            repeat (2) @(negedge clk);
        end
    endtask

    integer k, oob_before;

    initial begin
        // ---- R1 + R2：一个偏移落在帧缓存之外的包 ----
        // 几何：off = FB + 32 = 288 ⇒ 期望的字索引 144、145，都 >= WORDS(128) ⇒ 一次都不该写
        clean_start;
        oob_before = stat_oob;
        send_pkt(32'd288, 16'hBEEF, 16'hDA70, 1'b1);
        repeat (6) @(negedge clk);
        $display("INFO R1 off=288 越界包：写次数=%0d（其中越界 %0d）最大字索引=%0d stat_oob_off +%0d",
                 w_total, w_oob, w_max, stat_oob - oob_before);
        chk("R1 packet whose byte_off is outside the frame buffer must emit zero writes",
            w_total == 0 && w_oob == 0);
        // R2 同根但方向相反：越界必须**被数到**，修好以后也不许静默丢弃
        chk("R2 the same packet must still be counted in stat_oob_off (no silent drop)",
            (stat_oob - oob_before) >= 1);

        // ---- R3：最后一个合法字（索引 126、127）必须照写 ----
        clean_start;
        send_pkt(FB - 4, 16'h1234, 16'h5678, 1'b1);   // off=252 ⇒ 字 126、127
        repeat (6) @(negedge clk);
        $display("INFO R3 末字包：写次数=%0d 最大字索引=%0d 数据=%h/%h",
                 w_total, w_max, uut.wr_data, 16'h0);
        chk("R3 last legal word pair (indices 126,127) still writes both words",
            w_total == 2 && w_max == WORDS-1);

        // ---- R4：整帧 64 包 ⇒ 仍然提交一帧，正常路径一个字节都不动 ----
        clean_start;
        for (k = 0; k < FB/4; k = k + 1)
            send_pkt(k * 4, 16'hA500 + k[15:0], 16'h5A00 + k[15:0], 1'b1);
        repeat (10) @(negedge clk);
        $display("INFO R4 整帧：写次数=%0d 最大字索引=%0d frame_done=%0d stat_frames=%0d stat_bad=%0d",
                 w_total, w_max, done_pulse, stat_frames, stat_bad);
        chk("R4 a complete frame (64 packets, all 256 bytes) still commits exactly once",
            done_pulse == 1 && stat_frames == 1 && w_total == WORDS && w_max == WORDS-1);
        chk("R4a opportunity floor: all 64 packets were accepted (stat_pkts==64, no bad)",
            stat_pkts == FB/4 && stat_bad == 0);

        $display("");
        if (errors == 0) $display("RESULT tb_reasm_bounds PASS");
        else             $display("RESULT tb_reasm_bounds FAIL nfail=%0d", errors);
        $finish;
    end

    initial begin
        #4_000_000;
        $display("FAIL tb_reasm_bounds timeout");
        $display("RESULT tb_reasm_bounds FAIL nfail=timeout");
        $finish;
    end
endmodule
