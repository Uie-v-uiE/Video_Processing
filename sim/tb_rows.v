`timescale 1ns/1ps
// 功能：被测模块 `frame_reasm`（u，参数 IMG_W=8、IMG_H=4、FRAME_BYTES=64，一行 8×2=16 字节）；
//        覆盖点：源行没写满时不许发 frame_done，四行全部到齐之后才提交一次；字节数已够但只覆盖
//        3/4 行时也不许提交（r152：行计数不能退化成“每写一个字加一”）。
// 激励与检查：时钟 #5 翻转（10 ns 周期）；rst_n 拉低 20 拍后放开；send_packet(off0,8) 的包形是
//        4 拍送 4 字节偏移（p_sof 占第一拍、p_valid 全程）+ 每像素 2 拍共 8 像素 + 1 拍 p_eof；
//        偏移边界取 0、16、32、48；第一腿只发行 0 与行 1 两包，之后空跑 20 拍；
//        第二腿把四行发满，之后空跑 30 拍；第三腿发 0/16/32/32 四包（共 64 字节、三行），
//        行 2 重复，之后空跑 30 拍。
// 预期结果：通过时打印 `PASS no commit on 2/4 rows`、`PASS commit after all rows done_cnt=<n>`、
//        `PASS no commit when bytes complete but one row missing`，末行 `PASS tb_rows`；
//        失败时打印 `FAIL frame_done on incomplete rows (<n>)`、
//        `FAIL no frame_done after all rows` 或 `FAIL commit with full byte count but only 3/4 rows (<n>)`，
//        末行变 `FAIL tb_rows errors=<n>`。
// v5.0-fix: frame_done only after all source rows written
// r152: 第三腿是行计数流水化的能红判据（变异“每字加一”实测会红）
module tb_rows;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    reg p_valid=0, p_sof=0, p_eof=0, p_good=1;
    reg [7:0] p_data=0;
    wire wr_en, flush, frame_done, frame_err;
    wire [18:0] wr_addr; wire [15:0] wr_data;
    wire [31:0] s0,s1,s2,s3,s4;

    frame_reasm #(.IMG_W(8), .IMG_H(4), .FRAME_BYTES(64)) u (
        .clk(clk), .rst_n(rst_n),
        .p_data(p_data), .p_valid(p_valid), .p_sof(p_sof), .p_eof(p_eof), .p_good(p_good),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .flush(flush),
        .frame_done(frame_done), .frame_err(frame_err),
        .stat_frames(s0), .stat_pkts(s1), .stat_bytes(s2), .stat_bad(s3), .stat_oob_off(s4)
    );

    integer errors=0;
    integer done_cnt=0;
    integer base_done=0;
    always @(posedge clk) if (frame_done) done_cnt=done_cnt+1;

    task send_pix;
        input [31:0] byte_off;
        input [15:0] pix;
        begin
            // not used
        end
    endtask

    task send_packet;
        input [31:0] off0;
        input integer npix; // pixels from off0
        integer i;
        reg [31:0] off;
        begin
            off = off0;
            @(posedge clk); p_sof<=1; p_valid<=1; p_data<=off[7:0];
            @(posedge clk); p_sof<=0; p_data<=off[15:8];
            @(posedge clk); p_data<=off[23:16];
            @(posedge clk); p_data<=off[31:24];
            for (i=0;i<npix;i=i+1) begin
                @(posedge clk); p_data<=off[7:0]; // pix lo (dummy)
                @(posedge clk); p_data<=off[15:8]; // pix hi
                off = off + 2;
            end
            @(posedge clk); p_valid<=0; p_eof<=1;
            @(posedge clk); p_eof<=0;
        end
    endtask

    initial begin
        rst_n=0; repeat(20) @(posedge clk); rst_n=1;
        // Frame with only rows 0 and 1 (offsets 0-31 for 8px rows*2bytes*2rows=32)
        // IMG_W=8, row bytes=16. Partial: 2 rows only
        send_packet(32'd0, 8);  // row 0
        send_packet(32'd16, 8); // row 1
        repeat (20) @(posedge clk);
        if (done_cnt != 0) begin
            $display("FAIL frame_done on incomplete rows (%0d)", done_cnt);
            errors=errors+1;
        end else $display("PASS no commit on 2/4 rows");

        // Full frame: offsets covering 4 rows, 16 bytes each = 64
        send_packet(32'd0, 8);
        send_packet(32'd16, 8);
        send_packet(32'd32, 8);
        send_packet(32'd48, 8);
        repeat (30) @(posedge clk);
        if (done_cnt < 1) begin
            $display("FAIL no frame_done after all rows");
            errors=errors+1;
        end else $display("PASS commit after all rows done_cnt=%0d", done_cnt);

        // 字节数够、行数不够：4 包共 64 字节，但第 4 包重复第 3 行 ⇒ 只覆盖 3/4 行。
        // 这条专门用来卡住“rows_hit 每写一个字就加一”这类退化：旧台架的前两腿被
        // 字节门挡着，行计数即使翻倍也不会提前提交，判据会假绿（r152 变异实测）。
        base_done = done_cnt;
        send_packet(32'd0, 8);
        send_packet(32'd16, 8);
        send_packet(32'd32, 8);
        send_packet(32'd32, 8);
        repeat (30) @(posedge clk);
        if (done_cnt != base_done) begin
            $display("FAIL commit with full byte count but only 3/4 rows (%0d)", done_cnt-base_done);
            errors=errors+1;
        end else $display("PASS no commit when bytes complete but one row missing");

        if (errors==0) $display("PASS tb_rows");
        else $display("FAIL tb_rows errors=%0d", errors);
        $finish;
    end
endmodule
