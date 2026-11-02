`timescale 1ns/1ps
// 用途：axi_frame_saver64 的**满 FIFO + flush** 边界：半截 64bit 字不能被清掉。
// 输入：ModelSim/xsim 直接跑（无 plusargs）。
// 输出：PASS/FAIL 行。
//
// 背景（报告/审计里的"满 FIFO 静默丢字"）：打包器每 4 个 16bit lane 才推一个 64bit 字；
// 当 FIFO 恰好在**帧尾 flush** 时是满的，老代码的 `else if (flush && cur_dirty)` 会无条件清
// `cur_dirty`，而同一拍的 `pack_we` 又被 `!fifo_full` 挡住 ⇒ 这半截字永远没有机会再被推入，
// commit 也不会等它。这里把 AXI 从机按停，先灌满 512 格，再送 word 512 的 lane0..2 和一条
// flush；从机放开后，正确实现必须把 word 512（WSTRB=0x3F）写进 memory，老实现只写 512 个字。
//
// 为什么这个台架是可信的：它直接例化上板的 `axi_frame_saver64`，AXI 从机按 WSTRB 合并；判据是
// **写进 memory 的字数与逐字内容**，不是"idle 是否拉高"（老实现也会拉高 idle——这正是问题）。
module tb_saver_tail_full;
    localparam BASE  = 32'h1000_0000;
    localparam DEPTH = 512;
    localparam LAST  = 512;              // 要额外验证的半截字索引 (= DEPTH)

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;                // 100 MHz

    reg        wr_en = 0, flush = 0;
    reg [18:0] wr_addr = 0;
    reg [15:0] wr_data = 0;
    wire       fifo_full, idle, busy;

    wire [31:0] awaddr;
    wire [7:0]  awlen;
    wire [2:0]  awsize;
    wire [1:0]  awburst;
    wire        awvalid, awready;
    wire [63:0] wdata;
    wire [7:0]  wstrb;
    wire        wlast, wvalid, wready, bvalid, bready;

    axi_frame_saver64 #(.BASE_ADDR(BASE)) dut (
        .clk(clk), .rst_n(rst_n), .enable(1'b1), .base_addr(BASE),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .flush(flush), .fifo_full(fifo_full), .idle(idle), .busy(busy),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    // ---- 可停的 AXI 从机：stall=1 时两个 ready 都拉低；按 WSTRB 合并 ----
    reg stall = 1;
    assign awready = !stall;
    assign wready  = !stall;
    reg [63:0] mem [0:1023];
    integer wr_beats = 0;
    integer i;
    reg bvalid_r = 0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bvalid_r <= 0;
            wr_beats = 0;
        end else begin
            bvalid_r <= 0;
            if (awvalid && awready && wvalid && wready) begin
                if ((awaddr - BASE) < 1024*8) begin
                    for (i = 0; i < 8; i = i + 1)
                        if (wstrb[i])
                            mem[(awaddr - BASE) >> 3][i*8 +: 8] = wdata[i*8 +: 8];
                    wr_beats = wr_beats + 1;
                end
                bvalid_r <= 1;
            end
        end
    end
    assign bvalid = bvalid_r;

    task feed(input integer widx, input integer lane);
        begin
            @(negedge clk);
            wr_en   = 1'b1;
            // wr_addr 是 16bit 字索引（不是字节地址）：4 个 16bit lane 组成一个 64bit 字，
            // 所以 word i 的 lane j 地址 = 4*i + j。写成 8*i+2*j 会让 in_widx 每字跳 2，
            // 台架自己造出空洞（2026-10-22 第一次跑就是这么红的，读数 beats=513/257）。
            wr_addr = (widx * 4) + lane;
            wr_data = {widx[7:0], lane[7:0]};
            @(negedge clk);
            wr_en   = 1'b0;
        end
    endtask

    function [15:0] lane_val(input integer widx, input integer lane);
        begin
            lane_val = {widx[7:0], lane[7:0]};
        end
    endfunction

    integer k, j, errors = 0, full_seen = 0, tail_idx = 0;
    reg [63:0] exp64, got64;
    initial begin
        for (k = 0; k < 1024; k = k + 1) mem[k] = 64'h0;
        rst_n = 0;
        repeat (10) @(negedge clk);
        rst_n = 1;
        repeat (5) @(negedge clk);

        // 一直喂完整的 64bit 字，直到 FIFO 报满。满的那一拍 cur_* 里躺着一个**完整但还没推入**
        // 的字（它要等下一个字的 lane0 才推）——这正是 flush 撞上满 FIFO 的现场。
        // AXI 从机从开始就按停，所以最多只有 OUTST=8 个 beat 在 saver 内部，不会把 FIFO 排空。
        k = 0;
        while (!fifo_full && k < 2000) begin
            for (j = 0; j < 4; j = j + 1) feed(k, j);
            tail_idx = k;                 // 当前 cur_* 对应的字
            if (fifo_full) full_seen = 1;
            k = k + 1;
        end
        // 再等 20 拍确认（满判据本身是组合的，这一等只是让读数稳定）
        for (k = 0; k < 20; k = k + 1) begin
            @(negedge clk);
            if (fifo_full) full_seen = 1;
        end
        if (!fifo_full) begin
            $display("FAIL precondition: FIFO never reported full");
            errors = errors + 1;
        end
        // flush：老代码在这里清 cur_dirty，半截字被丢；正确实现保持 dirty
        @(negedge clk); flush = 1'b1;
        repeat (20) @(negedge clk);
        // 还没放开 AXI，尾字不允许被写出去；此时它只能"挂着"
        if (mem[tail_idx] !== 64'h0) begin
            $display("FAIL tail written before any space existed: %h", mem[tail_idx]);
            errors = errors + 1;
        end
        if (idle) begin
            $display("FAIL idle asserted while a pending word is still held");
            errors = errors + 1;
        end

        // 放开 AXI，排空
        stall = 0;
        k = 0;
        while (!idle && k < 20000) begin
            @(posedge clk); k = k + 1;
            if (fifo_full) full_seen = 1;
        end
        repeat (10) @(posedge clk);
        $display("drain: waited %0d cycles, wr_beats=%0d, idle=%0d", k, wr_beats, idle);
        if (!idle) begin
            $display("FAIL saver never went idle (timeout)");
            errors = errors + 1;
        end
        if (wr_beats != tail_idx + 1) begin
            $display("FAIL beats=%0d expected=%0d (tail word missing)", wr_beats, tail_idx + 1);
            errors = errors + 1;
        end

        // 逐字检查：word 0..tail_idx 每个都是完整 4 lane（尾字在满的时候还没被推走）
        for (k = 0; k <= tail_idx; k = k + 1) begin
            exp64 = {lane_val(k,3), lane_val(k,2), lane_val(k,1), lane_val(k,0)};
            got64 = mem[k];
            if (got64 !== exp64) begin
                if (errors < 4)
                    $display("FAIL word %0d got=%h expected=%h", k, got64, exp64);
                errors = errors + 1;
            end
        end
        if (full_seen == 0) begin
            $display("FAIL fifo_full never observed; the boundary was not exercised");
            errors = errors + 1;
        end else $display("PASS fifo_full observed (depth %0d)", DEPTH);
        if (errors == 0) $display("PASS tb_saver_tail_full");
        else            $display("FAIL tb_saver_tail_full errors=%0d", errors);
        $finish;
    end
    initial begin
        #2_000_000;
        $display("FAIL tb_saver_tail_full timeout");
        $finish;
    end
endmodule
