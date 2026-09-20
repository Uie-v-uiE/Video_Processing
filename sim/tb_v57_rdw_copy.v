`timescale 1ns/1ps
// v5.7 multi-dim: (1) no BRAM write while de|de_pipe (2) copy completes (3) no lost beats
module tb_v57_rdw_copy;
    reg axi_clk=0, pix_clk=0, rst_n=0;
    always #5 axi_clk = ~axi_clk;
    always #10 pix_clk = ~pix_clk;
    wire rst_pix_n = rst_n;

    parameter IMG_W=64, IMG_H=20;
    parameter TOTAL_WORDS = (IMG_W*IMG_H)/4;
    parameter PIPE=15;

    reg de=0, vs=0;
    reg [11:0] x=0, y=0;
    integer xcnt=0, ycnt=0;
    always @(posedge pix_clk) begin
        if (!rst_n) begin de<=0; vs<=0; xcnt<=0; ycnt<=0; x<=0; y<=0; end
        else begin
            de <= (xcnt < 40); // more blanking like production ratio
            vs <= (xcnt==0 && ycnt==0);
            x <= xcnt; y <= ycnt;
            if (xcnt==79) begin
                xcnt<=0;
                if (ycnt==29) ycnt<=0; else ycnt<=ycnt+1;
            end else xcnt<=xcnt+1;
        end
    end

    reg [PIPE:0] de_pipe;
    always @(posedge pix_clk or negedge rst_pix_n) begin
        if (!rst_pix_n) de_pipe <= 0;
        else de_pipe <= {de_pipe[PIPE-1:0], de};
    end
    wire blank_safe = ~(de | de_pipe[PIPE]);

    reg commit_req=0;
    reg [31:0] commit_base=32'h10000000;
    wire start_copy, done, busy, ready, allow, abort;
    wire [31:0] copy_base;
    wire wr_en; wire [18:0] wr_addr; wire [63:0] wr_data;
    wire arvalid, rready; wire [31:0] araddr; wire [7:0] arlen;
    reg arready=0, rvalid=0, rlast=0;
    reg [63:0] rdata=0;
    integer beats=0, delay=0, ar_cnt=0, r_cnt=0;

    always @(posedge axi_clk) begin
        if (!rst_n) begin beats<=0; delay<=0; rvalid<=0; rlast<=0; arready<=1; end
        else if (arvalid && arready) begin
            ar_cnt=ar_cnt+1; beats<=arlen+1; delay<=2; rvalid<=0; arready<=0;
        end else if (beats>0) begin
            if (delay>0) delay<=delay-1;
            else if (!rvalid) begin
                rvalid<=1; rdata<={32'hAABB, araddr[15:0], beats[15:0]}; rlast<=(beats==1);
            end else if (rvalid && rready) begin
                r_cnt=r_cnt+1;
                rvalid<=0; beats<=beats-1;
                if (beats==1) begin beats<=0; rlast<=0; arready<=1; end
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
        .frame_ready_pix(ready), .allow_copy_axi(allow),
        .copy_abort(abort)
    );

    axi_frame_writer_gated #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_wr (
        .clk(axi_clk), .rst_n(rst_n),
        .enable(1'b1), .start(start_copy), .base_addr(copy_base),
        .allow_wr(allow), .abort(abort),
        .busy(busy), .done(done),
        .fb_wr_en(wr_en), .fb_wr_addr(wr_addr), .fb_wr_data(wr_data),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(), .m_axi_arburst(),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .copy_cycles()
    );

    integer errors=0, wr_cnt=0, wr_no_allow=0, guard=0;
    reg allow_d=0;
    always @(posedge axi_clk) begin
        allow_d <= allow;
        if (wr_en) begin
            wr_cnt=wr_cnt+1;
            if (!allow && !allow_d) wr_no_allow=wr_no_allow+1;
        end
    end

    initial begin
        rst_n=0; repeat(30) @(posedge axi_clk); rst_n=1;
        @(posedge axi_clk) commit_req<=1;
        @(posedge axi_clk) commit_req<=0;
        guard=0;
        while (done!==1'b1 && guard<400000) begin @(posedge axi_clk); guard=guard+1; end
        if (done!==1'b1) begin
            $display("FAIL timeout wr=%0d r=%0d ar=%0d abort=%b", wr_cnt, r_cnt, ar_cnt, abort);
            $finish;
        end
        $display("INFO wr=%0d expect=%0d r=%0d ar=%0d cyc=%0d no_allow=%0d",
                 wr_cnt, TOTAL_WORDS, r_cnt, ar_cnt, u_wr.copy_cycles, wr_no_allow);
        if (wr_cnt < TOTAL_WORDS) begin
            $display("FAIL incomplete/lost beats"); errors=errors+1;
        end else $display("PASS full frame, no lost beats");
        if (wr_no_allow != 0) begin
            $display("FAIL write outside allow"); errors=errors+1;
        end else $display("PASS writes only when allow");
        if (r_cnt != ar_cnt*16 && r_cnt < TOTAL_WORDS) begin
            $display("WARN r_cnt=%0d vs 16*ar=%0d", r_cnt, ar_cnt*16);
        end
        if (errors==0) $display("PASS tb_v57_rdw_copy");
        else $display("FAIL tb_v57_rdw_copy errors=%0d", errors);
        $finish;
    end
endmodule
