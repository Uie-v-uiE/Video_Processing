`timescale 1ns/1ps
// Measure axi_frame_writer DMA time with realistic HP0-like read latency.
module tb_dma_latency;
    localparam IMG_W = 512;
    localparam IMG_H = 300;
    localparam TOTAL_WORDS = IMG_W * IMG_H / 4;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    wire [31:0] araddr;
    wire [7:0]  arlen;
    wire        arvalid, arready;
    wire        rvalid, rready, rlast;
    wire [63:0] rdata;
    wire        fb_we, busy, done;
    wire [16:0] fb_wa;
    wire [63:0] fb_wd;
    reg         start = 0;

    axi_frame_writer #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_dut (
        .clk(clk), .rst_n(rst_n), .enable(1'b1), .frame_start(start),
        .base_addr(32'h1000_0000),
        .frame_busy(busy), .frame_done(done),
        .fb_wr_en(fb_we), .fb_wr_waddr(fb_wa), .fb_wr_wdata(fb_wd),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(),
        .m_axi_arburst(), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid),
        .m_axi_rready(rready)
    );

    // ------------------------------------------------------------------
    // AXI read slave: accept AR always; first beat after LAT cycles;
    // then 1 beat/cycle. After rlast, GAP cycles before next burst.
    // ------------------------------------------------------------------
    localparam integer LAT = 24;
    localparam integer GAP = 8;

    // AR queue (depth 16)
    reg [31:0] q_addr [0:15];
    reg [7:0]  q_len  [0:15];
    reg [4:0]  q_wp = 0, q_rp = 0;
    assign arready = arvalid; // always accept

    reg        rvalid_r = 0, rlast_r = 0;
    reg [63:0] rdata_r = 0;
    assign rvalid = rvalid_r;
    assign rdata  = rdata_r;
    assign rlast  = rlast_r;

    reg [31:0] b_addr;
    reg [7:0]  b_left;
    integer    lat_cnt = 0;
    integer    n_words = 0;
    reg        running = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_wp <= 0; q_rp <= 0;
            rvalid_r <= 0; rlast_r <= 0;
            running <= 0; lat_cnt <= 0; n_words <= 0;
        end else begin
            if (arvalid && arready) begin
                q_addr[q_wp[3:0]] <= araddr;
                q_len[q_wp[3:0]]  <= arlen;
                q_wp <= q_wp + 1'b1;
            end

            // complete a presented beat
            if (rvalid_r && rready) begin
                rvalid_r <= 1'b0;
                if (rlast_r) begin
                    rlast_r  <= 1'b0;
                    running  <= 1'b0;
                    q_rp     <= q_rp + 1'b1;
                    // next AR already accepted → short turnaround
                    lat_cnt  <= ((q_wp - q_rp) > 1) ? 2 : GAP;
                end
            end

            if (!running) begin
                if (lat_cnt > 0)
                    lat_cnt <= lat_cnt - 1;
                else if (q_wp != q_rp && !(rvalid_r && !rready)) begin
                    running  <= 1'b1;
                    b_addr   <= q_addr[q_rp[3:0]];
                    b_left   <= q_len[q_rp[3:0]];
                    // If next AR already queued, short gap (HP0 pipeline), else full LAT
                    lat_cnt  <= ((q_wp - q_rp) > 1) ? 2 : (LAT - 1);
                end
            end else if (!(rvalid_r && rready && rlast_r) && (!rvalid_r || rready)) begin
                if (lat_cnt > 0)
                    lat_cnt <= lat_cnt - 1;
                else begin
                    rvalid_r <= 1'b1;
                    rdata_r  <= {32'hA5A5_0000, b_addr};
                    rlast_r  <= (b_left == 8'd0);
                    n_words  <= n_words + 1;
                    b_addr   <= b_addr + 32'd8;
                    if (b_left != 8'd0)
                        b_left <= b_left - 8'd1;
                end
            end
        end
    end

    integer cycles;
    initial begin
        $display("=== tb_dma_latency TOTAL_WORDS=%0d LAT=%0d GAP=%0d ===",
                 TOTAL_WORDS, LAT, GAP);
        repeat (5) @(posedge clk);
        rst_n <= 1;
        repeat (5) @(posedge clk);

        cycles = 0;
        @(posedge clk) start <= 1;
        @(posedge clk) start <= 0;

        while (!done && cycles < 500000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (!done) begin
            $display("FAIL timeout cycles=%0d words=%0d", cycles, n_words);
        end else begin
            $display("DMA cycles=%0d  %.2f ms  words=%0d", cycles, cycles/100000.0, n_words);
            $display("budget early+vblank ~= 774 us = 77400 cycles");
            if (cycles <= 77400)
                $display("RESULT: FITS");
            else
                $display("RESULT: OVERRUN %.2f ms into active  (this is the stutter)",
                         (cycles - 77400) / 100000.0);
        end
        $finish;
    end

    initial begin
        #50_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
