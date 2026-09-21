`timescale 1ns/1ps
// frame_buffer_w64 回读自检 TB（R04 新增：这仓库此前**没有任何** TB 覆盖显示帧缓存）。
//
// 为什么必须有：R04 把 38400 深的单阵列改成 32768 + 8192 两块 2 的幂阵列，
// 省 48 个 BRAM tile 的代价是地址映射多了一层块选择。地址映射错一个位，屏上
// 就是整块错位或右侧 1/4 花掉，而「报告好不好看」完全看不出来。
//
// 覆盖：
//   1) 全帧 38400 个字写完 ⇒ 逐像素 153600 次连续回读比对（流水式，一拍一个）
//   2) 读延迟契约：加地址后的**下一拍**必须出数。流水核对下，延迟一旦变成 2 拍
//      整个序列会错位 ⇒ 立刻全红。这条同时是 v6.4 读时序契约的守卫。
//   3) 分块边界（低块尾 / 高块头）与帧尾最后一个字定点复核
//   4) 越界读返回黑（split_display 靠这个画 OOB 边框）
//   5) 越界写不得污染已经写好的像素
//
// 坑记：未标位宽的延时常量会被截成 32 位（#20_000_000_000 实际只有 2.82 ms），
// 大延时必须写成 #(64'd...)。
module tb_fb_roundtrip;
    localparam W = 512, H = 300;
    localparam PX = W * H;                 // 153600
    localparam WORDS = PX / 4;             // 38400
    localparam D_LO  = 32768;              // 被测模块里的低块深度
    localparam TAIL  = 72;                 // 越界读的数量
    localparam TOTAL = PX + TAIL;

    reg wr_clk = 1'b0, rd_clk = 1'b0;
    always #5  wr_clk = ~wr_clk;           // 100 MHz，等效 axi_clk
    always #10 rd_clk = ~rd_clk;           //  50 MHz，等效 clk_pix

    reg         wr_en   = 1'b0;
    reg  [18:0] wr_addr = 19'd0;
    reg  [63:0] wr_data = 64'd0;
    reg  [18:0] rd_addr = 19'd0;
    wire [15:0] rd_data;

    frame_buffer_w64 #(.W(W), .H(H)) u_dut (
        .wr_clk(wr_clk), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_clk(rd_clk), .rd_addr(rd_addr), .rd_data(rd_data)
    );

    // 像素值 = 像素号 ^ 0x5A5A（逐像素唯一，错位一定看得见）
    function [15:0] pix_of;
        input [18:0] p;
        pix_of = p[15:0] ^ 16'h5A5A;
    endfunction

    function [63:0] word_of;
        input [18:0] w;
        word_of = {pix_of(w*4+3), pix_of(w*4+2), pix_of(w*4+1), pix_of(w*4+0)};
    endfunction

    function [15:0] exp_of;                // 越界 ⇒ 黑
        input [18:0] p;
        exp_of = (p < PX) ? pix_of(p) : 16'h0000;
    endfunction

    integer w, p, badcnt, shown;
    reg [15:0] got, want_v;

    task wr_word;                          // 一拍写一个字
        input [18:0] idx;
        begin
            @(negedge wr_clk);
            wr_en = 1'b1; wr_addr = idx; wr_data = word_of(idx);
            @(negedge wr_clk);
            wr_en = 1'b0;
        end
    endtask

    task point_check;                      // 定点核对一个像素（用非流水路径）
        input [18:0] px;
        begin
            @(negedge rd_clk); rd_addr = px;
            @(posedge rd_clk); #1;
            if (rd_data !== exp_of(px)) begin
                badcnt = badcnt + 1;
                $display("  MISMATCH(定点) p=%0d got=%h want=%h", px, rd_data, exp_of(px));
            end
        end
    endtask

    initial begin
        badcnt = 0; shown = 0;

        for (w = 0; w < WORDS; w = w + 1) wr_word(w);
        wr_word(WORDS);                    // 越界写：第 38401 个字
        wr_word(19'h7FFFF);                // 地址全 1，最坏情况
        @(negedge wr_clk); wr_en = 1'b0;
        $display("写入完成 %0d 字 + 2 次越界写，t=%0t", WORDS, $time);

        // ---- 流水回读：第 p 拍的 rd_data 必须等于 exp_of(p) ----
        rd_addr = 19'd0;
        for (p = 0; p < TOTAL; p = p + 1) begin
            @(posedge rd_clk); #1;
            got    = rd_data;
            want_v = exp_of(p[18:0]);
            if (got !== want_v) begin
                badcnt = badcnt + 1;
                if (shown < 10) begin
                    $display("  MISMATCH(流水) p=%0d got=%h want=%h", p, got, want_v);
                    shown = shown + 1;
                end
            end
            rd_addr = p[18:0] + 19'd1;
        end

        // ---- 分块边界 + 帧尾定点复核 ----
        for (p = (D_LO-2)*4; p < (D_LO+2)*4; p = p + 1) point_check(p[18:0]);
        for (p = (WORDS-1)*4; p < WORDS*4; p = p + 1)   point_check(p[18:0]);

        $display("tb_fb_roundtrip: 比对 %0d 次（流水 %0d + 越界读 %0d + 边界/帧尾定点 16），错 %0d 次",
                 TOTAL + 16, TOTAL, TAIL, badcnt);
        if (badcnt == 0) $display("PASS tb_fb_roundtrip");
        else             $display("FAIL tb_fb_roundtrip bad=%0d", badcnt);
        $finish;
    end

    initial begin
        #(64'd400_000_000_000);            // 400 ms，必须标位宽
        $display("FAIL tb_fb_roundtrip timeout");
        $finish;
    end
endmodule
