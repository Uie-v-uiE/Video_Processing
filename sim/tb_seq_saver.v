`timescale 1ns/1ps
// Minimal saver TB: back-to-back pixels, simple AXI slave
module tb_seq_saver;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    wire [31:0] awaddr;
    wire [7:0]  awlen;
    wire [2:0]  awsize;
    wire [1:0]  awburst;
    wire        awvalid, awready;
    wire [63:0] wdata;
    wire [7:0]  wstrb;
    wire        wlast, wvalid, wready;
    wire        bvalid, bready;

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
        .idle(sav_idle), .busy(),
        .drop_cnt(sav_drop),
        .wr_count0(wc0), .wr_count1(wc1), .wr_count2(wc2),
        .cnt_clear_en(1'b0), .cnt_clear_slot(2'd0),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    // Simple always-ready AXI slave with INCR support
    reg [63:0] mem [0:8191];
    assign awready = awvalid;
    assign wready  = wvalid;
    reg bvalid_r = 0;
    assign bvalid = bvalid_r;
    integer beat_off = 0;
    integer wi;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bvalid_r <= 0;
            beat_off <= 0;
        end else begin
            if (awvalid && awready) beat_off <= 0;
            if (wvalid && wready) begin
                // single-beat (awlen=0): no offset; multi-beat: increment
                if (awlen == 0)
                    wi = (awaddr - 32'h10000000) >> 3;
                else
                    wi = ((awaddr - 32'h10000000) >> 3) + beat_off;
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
                if (awlen != 0) beat_off <= beat_off + 1;
                bvalid_r <= 1;
            end else begin
                bvalid_r <= 0;
            end
        end
    end

    integer errors=0;
    integer i;
    integer n_writes = 0;

    always @(posedge clk) if (wvalid && wready) begin
        n_writes = n_writes + 1;
        $display("AXI W t=%0t aw=%h data=%h strb=%h", $time, awaddr, wdata, wstrb);
    end

    initial begin
        $display("=== tb_seq_saver start ===");
        for (i=0;i<8192;i=i+1) mem[i]=64'h0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // Feed 64 pixels back-to-back (one per cycle)
        for (i=0;i<64;i=i+1) begin
            sav_en   <= 1'b1;
            sav_slot <= 2'd0;
            sav_a    <= i[18:0];
            sav_d    <= 16'h1000 + i[15:0];
            @(posedge clk);
        end
        sav_en <= 1'b0;
        @(posedge clk);

        // wait for drain
        for (i=0;i<2000;i=i+1) @(posedge clk);

        $display("wc0=%0d wc1=%0d wc2=%0d drop=%0d idle=%b writes=%0d",
                 wc0, wc1, wc2, sav_drop, sav_idle, n_writes);

        if (wc0 !== 64) begin
            $display("FAIL: wc0=%0d expected 64", wc0);
            errors = errors + 1;
        end

        // Check pixels 0..31 at least (mem words 0..7)
        for (i=0;i<8;i=i+1) begin
            if (mem[i][15:0] !== (16'h1000 + i*4 + 0)) begin
                $display("FAIL: pix %0d got=%h exp=%h", i*4, mem[i][15:0], 16'h1000+i*4);
                errors = errors + 1;
            end
            if (mem[i][31:16] !== (16'h1000 + i*4 + 1)) begin
                $display("FAIL: pix %0d got=%h exp=%h", i*4+1, mem[i][31:16], 16'h1000+i*4+1);
                errors = errors + 1;
            end
            if (mem[i][47:32] !== (16'h1000 + i*4 + 2)) begin
                $display("FAIL: pix %0d got=%h exp=%h", i*4+2, mem[i][47:32], 16'h1000+i*4+2);
                errors = errors + 1;
            end
            if (mem[i][63:48] !== (16'h1000 + i*4 + 3)) begin
                $display("FAIL: pix %0d got=%h exp=%h", i*4+3, mem[i][63:48], 16'h1000+i*4+3);
                errors = errors + 1;
            end
        end

        if (errors==0) $display("=== tb_seq_saver PASS ===");
        else           $display("=== tb_seq_saver FAIL errors=%0d ===", errors);
        $finish;
    end

    initial begin
        #50_000;
        $display("TIMEOUT wc0=%0d idle=%b writes=%0d", wc0, sav_idle, n_writes);
        $finish;
    end
endmodule
