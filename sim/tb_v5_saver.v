`timescale 1ns/1ps
// v5 saver TB: write 64 sequential pixels, flush, require all 16 words + idle
module tb_v5_saver;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    reg wr_en=0, flush=0;
    reg [18:0] wr_addr=0;
    reg [15:0] wr_data=0;
    reg [31:0] base_addr=32'h10000000;
    wire fifo_full, idle, busy;
    wire [31:0] awaddr; wire [7:0] awlen; wire [2:0] awsize; wire [1:0] awburst;
    wire awvalid; reg awready=1;
    wire [63:0] wdata; wire [7:0] wstrb; wire wlast, wvalid; reg wready=1;
    reg bvalid=0; wire bready;

    axi_frame_saver_burst u_s (
        .clk(clk), .rst_n(rst_n), .enable(1'b1), .base_addr(base_addr),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .flush(flush),
        .fifo_full(fifo_full), .idle(idle), .busy(busy),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize), .m_axi_awburst(awburst),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast), .m_axi_wvalid(wvalid),
        .m_axi_wready(wready),
        .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    integer aw_cnt=0, w_cnt=0, b_cnt=0, max_awlen=0;
    always @(posedge clk) begin
        if (awvalid && awready) begin
            aw_cnt=aw_cnt+1;
            if (awlen>max_awlen) max_awlen=awlen;
        end
        if (wvalid && wready) w_cnt=w_cnt+1;
        if (bvalid && bready) b_cnt=b_cnt+1;
    end

    integer bdelay=0;
    always @(posedge clk) begin
        if (wvalid && wready && wlast) bdelay<=3;
        else if (bdelay>0) begin
            bdelay<=bdelay-1;
            if (bdelay==1) bvalid<=1;
        end else if (bvalid && bready) bvalid<=0;
    end

    integer errors=0, i, g;
    initial begin
        rst_n=0; repeat(20) @(posedge clk); rst_n=1;
        for (i=0; i<64; i=i+1) begin
            @(posedge clk);
            wr_en<=1; wr_addr<=i; wr_data<=16'h1000+i[15:0];
        end
        @(posedge clk) wr_en<=0;
        // two-cycle flush to cover packer push visibility
        @(posedge clk) flush<=1;
        @(posedge clk) flush<=1;
        @(posedge clk) flush<=0;

        g=0;
        while (idle!==1'b1 && g<50000) begin @(posedge clk); g=g+1; end
        $display("INFO aw_cnt=%0d w_cnt=%0d b_cnt=%0d max_awlen=%0d idle=%b g=%0d",
                 aw_cnt, w_cnt, b_cnt, max_awlen, idle, g);
        if (w_cnt < 16) begin
            $display("FAIL w_cnt=%0d expected>=16", w_cnt);
            errors=errors+1;
        end else $display("PASS all words written");
        if (idle!==1'b1) begin
            $display("FAIL not idle");
            errors=errors+1;
        end else $display("PASS idle");
        if (errors==0) $display("PASS tb_v5_saver");
        else $display("FAIL tb_v5_saver errors=%0d", errors);
        $finish;
    end
endmodule
