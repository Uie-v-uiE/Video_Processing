`timescale 1ns/1ps
// start arrives when allow=0 — copy must still complete on later blanking
module tb_v57_first_ar;
    reg axi_clk=0, pix_clk=0, rst_n=0;
    always #5 axi_clk=~axi_clk;
    always #10 pix_clk=~pix_clk;
    wire rst_pix_n=rst_n;

    parameter IMG_W=32, IMG_H=8;
    parameter TOTAL_WORDS=(IMG_W*IMG_H)/4;

    reg de=1, vs=0, blank_safe=0; // start during ACTIVE
    integer i;

    reg commit_req=0;
    reg [31:0] commit_base=32'h10000000;
    wire start_copy, done, busy, ready, allow, abort;
    wire [31:0] copy_base;
    wire wr_en; wire [18:0] wr_addr; wire [63:0] wr_data;
    wire arvalid, rready; wire [31:0] araddr; wire [7:0] arlen;
    reg arready=0, rvalid=0, rlast=0;
    reg [63:0] rdata=0;
    integer beats=0, delay=0;

    always @(posedge axi_clk) begin
        if (!rst_n) begin beats<=0; rvalid<=0; arready<=1; end
        else if (arvalid && arready) begin beats<=arlen+1; delay<=2; arready<=0; rvalid<=0; end
        else if (beats>0) begin
            if (delay>0) delay<=delay-1;
            else if (!rvalid) begin rvalid<=1; rdata<=64'hC0DE+beats; rlast<=(beats==1); end
            else if (rvalid&&rready) begin
                rvalid<=0; beats<=beats-1;
                if (beats==1) begin beats<=0; arready<=1; end
            end
        end else arready<=1;
    end

    frame_commit_lock u_cm (
        .axi_clk(axi_clk), .axi_rst_n(rst_n),
        .commit_req(commit_req), .commit_base(commit_base),
        .pix_clk(pix_clk), .pix_rst_n(rst_n),
        .de(de), .vsync(vs), .blank_safe(blank_safe),
        .copy_busy(busy), .copy_done(done),
        .start_copy(start_copy), .copy_base(copy_base),
        .frame_ready_pix(ready), .allow_copy_axi(allow), .copy_abort(abort)
    );

    axi_frame_writer_gated #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_wr (
        .clk(axi_clk), .rst_n(rst_n), .enable(1'b1),
        .start(start_copy), .base_addr(copy_base), .allow_wr(allow), .abort(abort),
        .busy(busy), .done(done),
        .fb_wr_en(wr_en), .fb_wr_addr(wr_addr), .fb_wr_data(wr_data),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(), .m_axi_arburst(),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .copy_cycles()
    );

    integer errors=0, wr_cnt=0, guard=0;
    always @(posedge axi_clk) if (wr_en) wr_cnt=wr_cnt+1;

    initial begin
        rst_n=0; repeat(20) @(posedge axi_clk); rst_n=1;
        // vsync pulse while de=1 (start during active)
        de=1; blank_safe=0;
        repeat (5) @(posedge pix_clk);
        vs=1; @(posedge pix_clk); vs=0;
        commit_req=1; repeat (4) @(posedge axi_clk); commit_req=0;
        // wait a bit — writer should be active but not write
        repeat (50) @(posedge axi_clk);
        if (wr_cnt != 0) begin
            $display("FAIL wrote during active wr=%0d", wr_cnt);
            errors=errors+1;
        end else $display("PASS no write while de=1");
        // open blanking
        de=0; blank_safe=1;
        guard=0;
        while (done!==1 && guard<100000) begin @(posedge axi_clk); guard=guard+1; end
        if (done!==1) begin
            $display("FAIL copy never finished after blanking opened wr=%0d busy=%b", wr_cnt, busy);
            errors=errors+1;
        end else $display("PASS copy completed after allow rose wr=%0d/%0d", wr_cnt, TOTAL_WORDS);
        if (wr_cnt < TOTAL_WORDS) begin
            $display("FAIL incomplete"); errors=errors+1;
        end
        if (errors==0) $display("PASS tb_v57_first_ar");
        else $display("FAIL tb_v57_first_ar errors=%0d", errors);
        $finish;
    end
endmodule
