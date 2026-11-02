`timescale 1ns/1ps
// AXI saver → memory model → writer round-trip test
module tb_saver_writer;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    // AXI wires
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

    // Saver
    reg        svr_en=0, svr_wr=0;
    reg [18:0] svr_a=0;
    reg [15:0] svr_d=0;
    wire       svr_busy;
    axi_frame_saver u_saver (
        .clk(clk), .rst_n(rst_n), .enable(svr_en),
        .base_addr(32'h10000000),
        .wr_en(svr_wr), .wr_addr(svr_a), .wr_data(svr_d), .busy(svr_busy),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    // Writer
    reg        wtr_en=0, wtr_start=0;
    wire       wtr_busy, wtr_done;
    wire       fb_we;
    wire [18:0] fb_a;
    wire [15:0] fb_d;
    axi_frame_writer #(.IMG_W(64), .IMG_H(2)) u_writer (
        .clk(clk), .rst_n(rst_n), .enable(wtr_en), .frame_start(wtr_start),
        .base_addr(32'h10000000),
        .frame_busy(wtr_busy), .frame_done(wtr_done),
        .fb_wr_en(fb_we), .fb_wr_addr(fb_a), .fb_wr_data(fb_d),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid),
        .m_axi_rready(rready)
    );

    // Simple AXI3 memory slave (word-addressed 64-bit)
    reg [63:0] mem [0:4095];
    assign awready = awvalid;
    assign wready  = wvalid;
    reg bvalid_r=0;
    assign bvalid = bvalid_r;
    integer wi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) bvalid_r <= 0;
        else begin
            if (wvalid && wready) begin
                wi = (awaddr[13:0]) >> 3;
                $display("MEMWR aw=%h idx=%0d data=%h strb=%h", awaddr, wi, wdata, wstrb);
                if (wstrb[0]) mem[wi][7:0]   = wdata[7:0];
                if (wstrb[1]) mem[wi][15:8]  = wdata[15:8];
                if (wstrb[2]) mem[wi][23:16] = wdata[23:16];
                if (wstrb[3]) mem[wi][31:24] = wdata[31:24];
                if (wstrb[4]) mem[wi][39:32] = wdata[39:32];
                if (wstrb[5]) mem[wi][47:40] = wdata[47:40];
                if (wstrb[6]) mem[wi][55:48] = wdata[55:48];
                if (wstrb[7]) mem[wi][63:56] = wdata[63:56];
                bvalid_r <= 1;
            end else bvalid_r <= 0;
        end
    end

    // Read channel: 16-beat burst
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
                    rlast_r <= (beats+1 == arlen);
                end
            end
        end
    end

    // Capture BRAM writes
    reg [15:0] got [0:255];
    integer nwr=0;
    integer n_ar=0, n_beat=0;
    always @(posedge clk) if (fb_we) begin
        got[fb_a] <= fb_d;
        nwr = nwr + 1;
        if (nwr <= 8 || (nwr % 32)==0)
            $display("WR %0d addr=%0d data=%h", nwr, fb_a, fb_d);
    end
    always @(posedge clk) begin
        if (arvalid && arready) begin
            n_ar = n_ar + 1;
            $display("AR#%0d addr=%h len=%0d", n_ar, araddr, arlen);
        end
        if (rvalid && rready) n_beat = n_beat + 1;
    end

    integer i, errors=0;
    reg [15:0] expect_d;

    initial begin
        for (i=0;i<4096;i=i+1) mem[i]=0;
        repeat(4) @(posedge clk);
        rst_n=1;
        repeat(2) @(posedge clk);

        // Write 128 pixels slowly so saver AXI can keep up
        svr_en = 1;
        for (i=0;i<128;i=i+1) begin
            @(posedge clk);
            svr_wr <= 1;
            svr_a  <= i[18:0];
            svr_d  <= 16'hA000 + i[15:0];
            @(posedge clk);
            svr_wr <= 0;
            repeat (8) @(posedge clk);
        end
        for (i=0;i<30000 && svr_busy;i=i+1) @(posedge clk);
        if (svr_busy) begin $display("FAIL saver busy timeout"); $finish; end
        repeat(10) @(posedge clk);

        wtr_en = 1;
        @(posedge clk);
        wtr_start <= 1;
        @(posedge clk);
        wtr_start <= 0;
        for (i=0;i<50000 && !wtr_done;i=i+1) @(posedge clk);
        if (!wtr_done) begin $display("FAIL writer timeout"); $finish; end
        repeat(5) @(posedge clk);

        for (i=0;i<128;i=i+1) begin
            expect_d = 16'hA000 + i[15:0];
            if (got[i] !== expect_d) begin
                $display("FAIL pix[%0d]=%h exp %h", i, got[i], expect_d);
                errors = errors + 1;
            end
        end
        if (nwr < 128) begin
            $display("FAIL nwr=%0d", nwr);
            errors = errors + 1;
        end
        if (errors==0) $display("PASS tb_saver_writer ALL");
        else $display("FAIL tb_saver_writer errors=%0d", errors);
        $finish;
    end
endmodule
