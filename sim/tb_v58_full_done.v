`timescale 1ns/1ps
// v5.8: writer must not pulse done unless all BRAM words written
module tb_v58_full_done;
    reg axi_clk=0, rst_n=0;
    always #5 axi_clk=~axi_clk;

    parameter IMG_W=32, IMG_H=8;
    parameter TOTAL_WORDS=(IMG_W*IMG_H)/4;

    reg start=0, allow=0, abort=0;
    reg [31:0] base=32'h10000000;
    wire busy, done, wr_en;
    wire [18:0] wr_addr; wire [63:0] wr_data;
    wire arvalid, rready; wire [31:0] araddr; wire [7:0] arlen;
    reg arready=0, rvalid=0, rlast=0;
    reg [63:0] rdata=0;
    integer beats=0, delay=0;
    integer drop_last=0; // if 1, model lost beats

    always @(posedge axi_clk) begin
        if (!rst_n) begin beats<=0; rvalid<=0; arready<=1; end
        else if (arvalid && arready) begin
            beats<=arlen+1; delay<=2; arready<=0; rvalid<=0;
        end else if (beats>0) begin
            if (delay>0) delay<=delay-1;
            else if (!rvalid) begin
                // optionally drop data beats (never assert rvalid for last burst)
                if (drop_last && araddr[7:0]==8'h80) begin
                    beats<=0; arready<=1; // silent drop
                end else begin
                    rvalid<=1; rdata<=64'h1111*beats; rlast<=(beats==1);
                end
            end else if (rvalid&&rready) begin
                rvalid<=0; beats<=beats-1;
                if (beats==1) begin beats<=0; arready<=1; end
            end
        end else arready<=1;
    end

    axi_frame_writer_gated #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_wr (
        .clk(axi_clk), .rst_n(rst_n), .enable(1'b1),
        .start(start), .base_addr(base), .allow_wr(allow), .abort(abort),
        .busy(busy), .done(done),
        .fb_wr_en(wr_en), .fb_wr_addr(wr_addr), .fb_wr_data(wr_data),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(), .m_axi_arburst(),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .copy_cycles()
    );

    integer errors=0, wr_cnt=0, guard=0;
    always @(posedge axi_clk) if (wr_en) wr_cnt=wr_cnt+1;

    // Case 1: clean copy → done
    initial begin
        rst_n=0; repeat(20) @(posedge axi_clk); rst_n=1;
        allow=1; start=1; @(posedge axi_clk); start=0;
        guard=0;
        while (done!==1 && guard<50000) begin @(posedge axi_clk); guard=guard+1; end
        if (done!==1 || wr_cnt < TOTAL_WORDS) begin
            $display("FAIL clean copy done=%b wr=%0d/%0d", done, wr_cnt, TOTAL_WORDS);
            errors=errors+1;
        end else $display("PASS clean full copy done wr=%0d", wr_cnt);

        // Case 2: abort mid-copy → no done
        allow=0; wr_cnt=0;
        @(posedge axi_clk) start<=1; @(posedge axi_clk) start<=0;
        repeat (30) @(posedge axi_clk);
        allow=1;
        repeat (40) @(posedge axi_clk);
        abort=1; @(posedge axi_clk); abort=0;
        repeat (20) @(posedge axi_clk);
        if (done) begin
            $display("FAIL done after abort");
            errors=errors+1;
        end else $display("PASS no done after abort (wr=%0d)", wr_cnt);

        if (errors==0) $display("PASS tb_v58_full_done");
        else $display("FAIL tb_v58_full_done errors=%0d", errors);
        $finish;
    end
endmodule
