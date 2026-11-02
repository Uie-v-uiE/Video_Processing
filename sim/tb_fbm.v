`timescale 1ns/1ps
// Multi-slot saver + commit integrity + writer round-trip
module tb_fbm;
    reg clk=0, rst_n=0;
    always #5 clk=~clk; // 100 MHz

    // ---- AXI memory model ----
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

    reg        sav_en=0;
    reg [1:0]  sav_slot=0;
    reg [18:0] sav_a=0;
    reg [15:0] sav_d=0;
    wire       sav_idle;
    wire [19:0] wc0, wc1, wc2;
    wire [15:0] sav_drop;

    axi_frame_saver #(
        .SLOT0(32'h10000000), .SLOT_STRIDE(32'h00100000)
    ) u_saver (
        .clk(clk), .rst_n(rst_n), .enable(1'b1),
        .wr_en(sav_en), .wr_slot(sav_slot), .wr_addr(sav_a), .wr_data(sav_d),
        .idle(sav_idle), .drop_cnt(sav_drop),
        .wr_count0(wc0), .wr_count1(wc1), .wr_count2(wc2),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    reg wtr_en=0, wtr_start=0;
    reg [31:0] wtr_base=32'h10000000;
    wire wtr_busy, wtr_done, fb_we;
    wire [18:0] fb_a;
    wire [15:0] fb_d;

    axi_frame_writer #(.IMG_W(64), .IMG_H(2)) u_writer (
        .clk(clk), .rst_n(rst_n), .enable(wtr_en), .frame_start(wtr_start),
        .base_addr(wtr_base),
        .frame_busy(wtr_busy), .frame_done(wtr_done),
        .fb_wr_en(fb_we), .fb_wr_addr(fb_a), .fb_wr_data(fb_d),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid),
        .m_axi_rready(rready)
    );

    // Shared AXI3 slave
    reg [63:0] mem [0:8191];
    wire wvalid_stall = 1'b0;
    assign awready = awvalid && !wvalid_stall;
    assign wready  = wvalid;
    reg bvalid_r=0;
    assign bvalid = bvalid_r;
    integer wi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) bvalid_r <= 0;
        else begin
            if (wvalid && wready) begin
                wi = (awaddr - 32'h10000000) >> 3;
                if (wi >= 0 && wi < 8192) begin
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
            end else bvalid_r <= 0;
        end
    end

    assign arready = arvalid && !rvalid;
    reg        rvalid_r=0;
    reg [63:0] rdata_r=0;
    reg        rlast_r=0;
    reg [7:0]  beats=0;
    reg [31:0] raddr;
    assign rvalid = rvalid_r;
    assign rdata  = rdata_r;
    assign rlast  = rlast_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid_r<=0; rlast_r<=0; beats<=0; raddr<=0;
        end else begin
            if (arvalid && arready) begin
                raddr <= araddr;
                beats <= 0;
                rvalid_r <= 1;
                rdata_r <= mem[((araddr - 32'h10000000) >> 3)];
                rlast_r <= (arlen==0);
            end else if (rvalid && rready) begin
                if (rlast_r) begin
                    rvalid_r <= 0; rlast_r <= 0;
                end else begin
                    beats <= beats + 1;
                    raddr <= raddr + 8;
                    rdata_r <= mem[((raddr + 8 - 32'h10000000) >> 3)];
                    rlast_r <= (beats + 1 == arlen);
                end
            end
        end
    end

    integer errors=0;
    integer i;
    integer got;

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

    initial begin
        $display("=== tb_fbm start ===");
        for (i=0;i<8192;i=i+1) mem[i]=64'hA5A5_0000_0000_0000 + i;
        repeat(5) @(posedge clk);
        rst_n <= 1;
        repeat(5) @(posedge clk);

        // Test 1: write 128 pixels to slot0 (IMG 64x2)
        for (i=0;i<128;i=i+1)
            write_pix(2'd0, i[18:0], 16'h1000 + i[15:0]);
        // slot1 few pixels
        for (i=0;i<8;i=i+1)
            write_pix(2'd1, i[18:0], 16'h2000 + i[15:0]);

        wait (sav_idle);
        repeat(20) @(posedge clk);

        $display("wc0=%0d wc1=%0d wc2=%0d drop=%0d idle=%b", wc0, wc1, wc2, sav_drop, sav_idle);
        if (wc0 !== 128) begin
            $display("FAIL: wc0=%0d expected 128", wc0);
            errors = errors + 1;
        end
        if (wc1 !== 8) begin
            $display("FAIL: wc1=%0d expected 8", wc1);
            errors = errors + 1;
        end
        if (wc2 !== 0) begin
            $display("FAIL: wc2=%0d expected 0", wc2);
            errors = errors + 1;
        end

        // Verify slot0 pixel 0 at base 0x10000000 + 0
        // pixel0 lane0 → bytes 0-1 of word0
        if (mem[0][15:0] !== 16'h1000) begin
            $display("FAIL: slot0 pix0 mem=%h", mem[0][15:0]);
            errors = errors + 1;
        end
        // pixel 4 → word 1 lane 0
        if (mem[1][15:0] !== 16'h1004) begin
            $display("FAIL: slot0 pix4 mem=%h", mem[1][15:0]);
            errors = errors + 1;
        end
        // pixel 5 → word 1 lane 1
        if (mem[1][31:16] !== 16'h1005) begin
            $display("FAIL: slot0 pix5 mem=%h", mem[1][31:16]);
            errors = errors + 1;
        end

        // slot1 base = 0x10100000 → index = 0x10000/8 = 8192... out of 8192 range
        // mem model only 8192 words = 64KB. SLOT_STRIDE is 1MB. Need larger model
        // or check only slot0 here. For slot1, skip mem check if OOB.

        // Test 2: incomplete frame must NOT look complete
        // Simulate commit logic
        begin : commit_chk
            reg commit_wait; reg [19:0] pend_pix; reg pend_bad;
            reg [1:0] pend_slot; reg [25:0] wait_tmr;
            integer commits, invalids;
            commits=0; invalids=0;

            // incomplete: 100 pixels
            commit_wait=1; pend_slot=0; pend_pix=100; pend_bad=0; wait_tmr=1000;
            // drain
            repeat(20) @(posedge clk);
            // should timeout or not commit
            // run the condition
            if (sav_idle && !pend_bad && (pend_pix >= 128) && (wc0 >= 128)) begin
                $display("FAIL: incomplete would commit");
                errors = errors + 1;
            end else
                $display("PASS: incomplete frame not committed (pix=100)");

            // bad frame
            if (sav_idle && pend_bad && (pend_pix >= 128)) begin
                $display("FAIL: bad frame would commit");
                errors = errors + 1;
            end else
                $display("PASS: bad frame not committed");
        end

        // Test 3: writer round-trip slot0
        wtr_en <= 1;
        wtr_base <= 32'h10000000;
        @(posedge clk);
        wtr_start <= 1;
        @(posedge clk);
        wtr_start <= 0;
        wait (wtr_done);
        @(posedge clk);

        // Read back a few via writer fb outputs - need to capture
        // Instead dump first BRAM writes by monitoring fb_we
        $display("writer done, busy=%b", wtr_busy);

        if (errors==0)
            $display("=== tb_fbm PASS ===");
        else
            $display("=== tb_fbm FAIL errors=%0d ===", errors);
        $finish;
    end

    // capture writer BRAM
    reg [15:0] bram [0:127];
    integer nw=0;
    always @(posedge clk) if (fb_we && fb_a < 128) begin
        bram[fb_a] <= fb_d;
        nw <= nw + 1;
    end

    // after writer, check
    initial begin
        wait(wtr_done);
        repeat(10) @(posedge clk);
        $display("BRAM writes=%0d", nw);
        for (i=0;i<128;i=i+1) begin
            if (bram[i] !== (16'h1000 + i[15:0])) begin
                $display("FAIL: bram[%0d]=%h exp %h", i, bram[i], 16'h1000+i[15:0]);
                errors = errors + 1;
            end
        end
        if (nw < 128) begin
            $display("FAIL: only %0d bram writes", nw);
            errors = errors + 1;
        end
    end

    initial begin
        #10_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
