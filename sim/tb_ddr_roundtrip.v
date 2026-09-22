`timescale 1ns/1ps
// End-to-end: axi_frame_saver → AXI mem → axi_frame_writer → frame_buffer
// Pixel-exact self-check. Also covers address jumps and idle drain.
module tb_ddr_roundtrip;
    localparam IMG_W = 64;
    localparam IMG_H = 4;
    localparam NPIX  = IMG_W * IMG_H; // 256

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk; // 100 MHz

    // ---- AXI wires ----
    wire [31:0] awaddr, araddr;
    wire [7:0]  awlen, arlen;
    wire [2:0]  awsize, arsize;
    wire [1:0]  awburst, arburst;
    wire        awvalid, awready, wvalid, wready, wlast;
    wire [63:0] wdata;
    wire [7:0]  wstrb;
    wire        bvalid, bready;
    wire        arvalid, arready, rvalid, rready, rlast;
    wire [63:0] rdata;

    // ---- saver ----
    reg        sav_en = 0;
    reg [1:0]  sav_slot = 0;
    reg [18:0] sav_a = 0;
    reg [15:0] sav_d = 0;
    wire       sav_idle, sav_busy;
    wire [19:0] wc0, wc1, wc2;
    wire [15:0] sav_drop;

    axi_frame_saver #(
        .SLOT0(32'h1000_0000), .SLOT_STRIDE(32'h0000_1000), .MAX_OUT(8)
    ) u_saver (
        .clk(clk), .rst_n(rst_n), .enable(1'b1),
        .wr_en(sav_en), .wr_slot(sav_slot), .wr_addr(sav_a), .wr_data(sav_d),
        .idle(sav_idle), .busy(sav_busy), .drop_cnt(sav_drop),
        .wr_count0(wc0), .wr_count1(wc1), .wr_count2(wc2),
        .cnt_clear_en(1'b0), .cnt_clear_slot(2'd0),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    // ---- writer ----
    reg         wtr_start = 0;
    reg  [31:0] wtr_base = 32'h1000_0000;
    wire        wtr_busy, wtr_done;
    wire        fb_we;
    wire [16:0] fb_wa;
    wire [63:0] fb_wd;

    axi_frame_writer #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_writer (
        .clk(clk), .rst_n(rst_n), .enable(1'b1), .frame_start(wtr_start),
        .base_addr(wtr_base),
        .frame_busy(wtr_busy), .frame_done(wtr_done),
        .fb_wr_en(fb_we), .fb_wr_waddr(fb_wa), .fb_wr_wdata(fb_wd),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid),
        .m_axi_rready(rready)
    );

    // ---- frame_buffer (small) ----
    reg  [18:0] rd_addr = 0;
    wire [15:0] rd_data;
    frame_buffer #(.W(IMG_W), .H(IMG_H)) u_fb (
        .wr_clk(clk), .wr_en(fb_we), .wr_waddr(fb_wa), .wr_wdata(fb_wd),
        .rd_clk(clk), .rd_addr(rd_addr), .rd_data(rd_data)
    );

    // =====================================================================
    // AXI3 slave: 64-bit, sparse (use associative-like large array)
    // Address map: 0x1000_0000, 0x1010_0000, 0x1020_0000
    // =====================================================================
    reg [63:0] mem [0:32767]; // 256 KB — enough for 3 small slots

    function [31:0] mem_idx;
        input [31:0] addr;
        begin
            mem_idx = (addr - 32'h1000_0000) >> 3;
        end
    endfunction

    // Write channel: simple — accept AW+W together
    assign awready = awvalid && wvalid;
    assign wready  = awvalid && wvalid;
    reg bvalid_r = 0;
    assign bvalid = bvalid_r;
    integer wi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) bvalid_r <= 0;
        else begin
            if (awvalid && wvalid && awready) begin
                wi = mem_idx(awaddr);
                if (wi >= 0 && wi < 32768) begin
                    if (wstrb[0]) mem[wi][7:0]   = wdata[7:0];
                    if (wstrb[1]) mem[wi][15:8]  = wdata[15:8];
                    if (wstrb[2]) mem[wi][23:16] = wdata[23:16];
                    if (wstrb[3]) mem[wi][31:24] = wdata[31:24];
                    if (wstrb[4]) mem[wi][39:32] = wdata[39:32];
                    if (wstrb[5]) mem[wi][47:40] = wdata[47:40];
                    if (wstrb[6]) mem[wi][55:48] = wdata[55:48];
                    if (wstrb[7]) mem[wi][63:56] = wdata[63:56];
                end
                bvalid_r <= 1;
            end else
                bvalid_r <= 0;
        end
    end

    // Read channel: up to 16-beat bursts
    reg        rd_busy = 0;
    reg [1:0]  rd_gap = 0;
    assign arready = arvalid && (rd_busy == 0);
    reg        rvalid_r = 0, rlast_r = 0;
    reg [63:0] rdata_r = 0;
    reg [31:0] raddr;
    reg [7:0]  rbeats;
    assign rvalid = rvalid_r;
    assign rdata  = rdata_r;
    assign rlast  = rlast_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid_r <= 0; rlast_r <= 0; rd_busy <= 0; rbeats <= 0; raddr <= 0; rd_gap <= 0;
        end else begin
            if (arvalid && arready) begin
                raddr  <= araddr;
                rbeats <= 0;
                rd_busy <= 1;
                rd_gap  <= 2'd1;
                rvalid_r <= 0;
            end else if (rd_busy) begin
                if (rd_gap != 0) begin
                    rd_gap <= rd_gap - 2'd1;
                    rvalid_r <= 0;
                end else begin
                    rvalid_r <= 1;
                    rdata_r  <= mem[mem_idx(raddr)];
                    rlast_r  <= (rbeats == arlen);
                    if (rvalid_r && rready) begin
                        if (rlast_r) begin
                            rd_busy <= 0;
                            rvalid_r <= 0;
                            rlast_r  <= 0;
                        end else begin
                            rbeats <= rbeats + 8'd1;
                            raddr  <= raddr + 32'd8;
                            rd_gap <= 2'd1;
                            rvalid_r <= 0;
                        end
                    end
                end
            end else begin
                rvalid_r <= 0;
            end
        end
    end

    // =====================================================================
    // Stimulus
    // =====================================================================
    integer errors = 0;
    integer i;
    reg [15:0] exp [0:NPIX-1];

    task write_pix;
        input [1:0] slot;
        input [18:0] addr;
        input [15:0] data;
        begin
            @(posedge clk);
            sav_en <= 1; sav_slot <= slot; sav_a <= addr; sav_d <= data;
            @(posedge clk);
            sav_en <= 0;
        end
    endtask

    // burst-write a run of consecutive pixels (1 per cycle)
    task write_run;
        input [1:0] slot;
        input [18:0] start_a;
        input integer n;
        input [15:0] base_d;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(posedge clk);
                sav_en <= 1; sav_slot <= slot;
                sav_a <= start_a + k[18:0];
                sav_d <= base_d + k[15:0];
            end
            @(posedge clk);
            sav_en <= 0;
        end
    endtask

    task wait_idle;
        begin
            wait (sav_idle);
            repeat (20) @(posedge clk);
        end
    endtask

    integer cycles0;
    // debug: log AR and a few BRAM writes
    always @(posedge clk) begin
        // lightweight: only non-slot0 AW
        if (awvalid && awready && awaddr[19:16] != 4'h0)
            $display("  MEMWR addr=%h", awaddr);
    end
    initial begin
        $display("=== tb_ddr_roundtrip start ===");
        for (i = 0; i < 32768; i = i + 1)
            mem[i] = 64'hDEAD_BEEF_CAFE_BABE;
        for (i = 0; i < NPIX; i = i + 1)
            exp[i] = 16'h1000 + i[15:0];

        repeat (5) @(posedge clk);
        rst_n <= 1;
        repeat (5) @(posedge clk);

        // ---- Test 1: sequential full frame into slot 0 ----
        $display("[T1] sequential %0d pixels slot0", NPIX);
        write_run(2'd0, 19'd0, NPIX, 16'h1000);
        wait_idle;
        $display("    wc0=%0d drop=%0d", wc0, sav_drop);
        if (wc0 !== NPIX) begin
            $display("FAIL T1: wc0=%0d expected %0d", wc0, NPIX);
            errors = errors + 1;
        end
        if (sav_drop !== 0) begin
            $display("FAIL T1: drop=%0d", sav_drop);
            errors = errors + 1;
        end
        // spot-check DDR
        if (mem[0][15:0] !== 16'h1000 || mem[0][63:48] !== 16'h1003) begin
            $display("FAIL T1: mem[0]=%h", mem[0]);
            errors = errors + 1;
        end
        if (mem[1][15:0] !== 16'h1004) begin
            $display("FAIL T1: mem[1]=%h", mem[1]);
            errors = errors + 1;
        end
        $display("    mem[16]=%h (expect pix64-67=1040,1041,1042,1043)", mem[16]);
        $display("    mem[17]=%h", mem[17]);
        if (mem[1][15:0] !== 16'h1004) begin
            $display("FAIL T1: mem[1]=%h", mem[1]);
            errors = errors + 1;
        end

        // ---- Test 2: writer round-trip slot 0 ----
        $display("[T2] writer round-trip slot0");
        wtr_base <= 32'h1000_0000;
        @(posedge clk);
        wtr_start <= 1;
        @(posedge clk);
        wtr_start <= 0;
        cycles0 = 0;
        while (!wtr_done && cycles0 < 100000) begin
            @(posedge clk);
            cycles0 = cycles0 + 1;
        end
        if (!wtr_done) begin
            $display("FAIL T2: writer timeout");
            errors = errors + 1;
        end else begin
            $display("    writer done in %0d cycles (%.1f us)", cycles0, cycles0 / 100.0);
        end

        // verify frame_buffer contents (need 1-cycle read latency)
        for (i = 0; i < NPIX; i = i + 1) begin
            rd_addr <= i[18:0];
            @(posedge clk);
            @(posedge clk);
            if (rd_data !== exp[i]) begin
                $display("FAIL T2: fb[%0d]=%h exp %h", i, rd_data, exp[i]);
                errors = errors + 1;
                if (errors > 20) begin
                    $display("too many errors, stop");
                    $finish;
                end
            end
        end
        $display("    fb pixel check done, errors so far=%0d", errors);

        // ---- Test 3: address jump (non-contiguous) ----
        $display("[T3] address jump");
        // write pixels 0..3, then jump to 10..13, then 20
        write_run(2'd0, 19'd0,  4, 16'h2000);
        write_run(2'd0, 19'd10, 4, 16'h3000);
        write_pix(2'd0, 19'd20, 16'h4000);
        wait_idle;
        if (mem[0][15:0] !== 16'h2000) begin
            $display("FAIL T3: pix0=%h", mem[0][15:0]);
            errors = errors + 1;
        end
        if (mem[2][47:32] !== 16'h3000) begin // word2 lanes: pix8,9,10,11; pix10=3000
            $display("FAIL T3: pix10=%h mem[2]=%h", mem[2][47:32], mem[2]);
            errors = errors + 1;
        end
        if (mem[5][15:0] !== 16'h4000) begin // pix 20 → word 5, lane 0
            $display("FAIL T3: pix20=%h mem[5]=%h", mem[5][15:0], mem[5]);
            errors = errors + 1;
        end

        // ---- Test 4: slot isolation ----
        $display("[T4] slot isolation");
        // slot1 base = 0x10100000 → idx = 0x10000/8 = 8192
        write_run(2'd1, 19'd0, 4, 16'h5555);
        wait_idle;
        // slot1 @ +0x1000 → idx 512
        $display("    after slot1: mem[512]=%h wc1=%0d", mem[512], wc1);
        if (mem[512][15:0] !== 16'h5555 || mem[512][63:48] !== 16'h5558) begin
            $display("FAIL T4: slot1 mem[512]=%h", mem[512]);
            errors = errors + 1;
        end
        if (wc1 !== 4) begin
            $display("FAIL T4: wc1=%0d expected 4", wc1);
            errors = errors + 1;
        end

        // ---- Test 5: second full frame overwrite + readback ----
        $display("[T5] overwrite slot0 and re-read");
        write_run(2'd0, 19'd0, NPIX, 16'h8000);
        wait_idle;
        wtr_base <= 32'h1000_0000;
        @(posedge clk);
        wtr_start <= 1;
        @(posedge clk);
        wtr_start <= 0;
        cycles0 = 0;
        while (!wtr_done && cycles0 < 100000) begin
            @(posedge clk);
            cycles0 = cycles0 + 1;
        end
        for (i = 0; i < NPIX; i = i + 1) begin
            rd_addr <= i[18:0];
            @(posedge clk);
            @(posedge clk);
            if (rd_data !== (16'h8000 + i[15:0])) begin
                $display("FAIL T5: fb[%0d]=%h exp %h", i, rd_data, 16'h8000+i[15:0]);
                errors = errors + 1;
                if (errors > 30) $finish;
            end
        end

        if (errors == 0)
            $display("=== tb_ddr_roundtrip PASS ===");
        else
            $display("=== tb_ddr_roundtrip FAIL errors=%0d ===", errors);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
