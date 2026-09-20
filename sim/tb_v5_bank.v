`timescale 1ns/1ps
// v5.4: after frame_done, new pixels must go to the OTHER bank immediately
module tb_v5_bank;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    localparam BANK0=32'h10000000, BANK1=32'h10080000;

    reg wr_en=0, flush=0, fd_axi=0;
    reg [18:0] wr_addr=0;
    reg [15:0] wr_data=0;
    wire fifo_full, idle, busy;
    wire [31:0] awaddr; wire [7:0] awlen; wire [2:0] awsize; wire [1:0] awburst;
    wire awvalid; reg awready=1;
    wire [63:0] wdata; wire [7:0] wstrb; wire wlast, wvalid; reg wready=1;
    reg bvalid=0; wire bready;

    // DUT bank FSM (mirror of eth_udp_video_top)
    reg bank=0;
    reg [31:0] completed_base=BANK0;
    reg commit_pulse=0, commit_pending=0, force_flush=0;
    wire [31:0] sav_base = bank ? BANK1 : BANK0;
    wire [31:0] commit_base_o = completed_base;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bank<=0; completed_base<=BANK0; commit_pulse<=0; commit_pending<=0; force_flush<=0;
        end else begin
            commit_pulse <= 0;
            if (fd_axi) begin
                completed_base <= sav_base;
                bank <= ~bank;
                force_flush <= 1;
                commit_pending <= 1;
            end
            if (commit_pending && idle) begin
                commit_pulse <= 1;
                commit_pending <= 0;
                force_flush <= 0;
            end
            if (idle && !commit_pending) force_flush <= 0;
        end
    end

    axi_frame_saver64 #(.BASE_ADDR(BANK0)) u_s (
        .clk(clk), .rst_n(rst_n), .enable(1'b1), .base_addr(sav_base),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .flush(flush | force_flush),
        .fifo_full(fifo_full), .idle(idle), .busy(busy),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize), .m_axi_awburst(awburst),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast), .m_axi_wvalid(wvalid),
        .m_axi_wready(wready),
        .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    integer bdelay=0;
    always @(posedge clk) begin
        if (wvalid && wready && wlast) bdelay<=2;
        else if (bdelay>0) begin
            bdelay<=bdelay-1;
            if (bdelay==1) bvalid<=1;
        end else if (bvalid && bready) bvalid<=0;
    end

    integer errors=0, i, bad_bank0_after=0, aw_to_new_before_switch=0;
    reg [31:0] expect_completed;
    integer g;

    initial begin
        rst_n=0; repeat(20) @(posedge clk); rst_n=1;

        // write frame A pixels (bank0)
        for (i=0;i<16;i=i+1) begin
            @(posedge clk); wr_en<=1; wr_addr<=i; wr_data<=16'hA000+i;
        end
        @(posedge clk) wr_en<=0;
        // frame_done — must latch bank0 as completed and flip to bank1 same cycle
        @(posedge clk) fd_axi<=1;
        @(posedge clk) fd_axi<=0;
        expect_completed = BANK0;
        repeat (2) @(posedge clk);
        if (completed_base !== BANK0) begin
            $display("FAIL completed_base=%h expected %h", completed_base, BANK0);
            errors=errors+1;
        end else $display("PASS completed_base locked to bank0");
        if (sav_base !== BANK1) begin
            $display("FAIL sav_base=%h expected bank1 immediately after fd", sav_base);
            errors=errors+1;
        end else $display("PASS write bank flipped to bank1 on frame_done");

        // next frame pixels must target bank1
        for (i=0;i<16;i=i+1) begin
            @(posedge clk); wr_en<=1; wr_addr<=i; wr_data<=16'hB000+i;
        end
        @(posedge clk) wr_en<=0;
        @(posedge clk) flush<=1;
        @(posedge clk) flush<=0;

        g=0;
        while (idle!==1 && g<20000) begin @(posedge clk); g=g+1; end
        if (idle!==1) begin
            $display("FAIL not idle");
            errors=errors+1;
        end else $display("PASS idle after drain");

        if (sav_base !== BANK1) begin
            $display("FAIL sav_base drifted %h", sav_base);
            errors=errors+1;
        end

        if (errors==0) $display("PASS tb_v5_bank");
        else $display("FAIL tb_v5_bank errors=%0d", errors);
        $finish;
    end
endmodule
