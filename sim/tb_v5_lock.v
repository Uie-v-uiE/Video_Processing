`timescale 1ns/1ps
module tb_v5_lock;
    reg axi_clk=0, pix_clk=0, rst_n=0;
    always #5 axi_clk = ~axi_clk;
    always #10 pix_clk = ~pix_clk;
    wire rst_pix_n = rst_n;

    parameter PIPE=15;
    reg de=0, vs=0;
    reg [11:0] x=0, y=0;
    integer xcnt=0, ycnt=0;
    always @(posedge pix_clk) begin
        if (!rst_n) begin de<=0; vs<=0; xcnt<=0; ycnt<=0; x<=0; y<=0; end
        else begin
            de <= (xcnt < 16);
            vs <= (xcnt==0 && ycnt==0);
            x <= xcnt[11:0]; y <= ycnt[11:0];
            if (xcnt==39) begin
                xcnt<=0;
                if (ycnt==9) ycnt<=0;
                else ycnt<=ycnt+1;
            end else xcnt<=xcnt+1;
        end
    end

    reg [PIPE:0] de_pipe;
    always @(posedge pix_clk or negedge rst_pix_n) begin
        if (!rst_pix_n) de_pipe <= 0;
        else de_pipe <= {de_pipe[PIPE-1:0], de};
    end
    wire near_active = (x >= 12'd28) && (y < 12'd8);
    wire blank_safe = ~(de | de_pipe[PIPE] | near_active);

    reg commit_req=0;
    reg [31:0] commit_base=32'h10000000;
    wire start_copy, ready, allow, abort;
    wire copy_busy = 1'b0;
    wire [31:0] copy_base;
    reg copy_done_r=0;

    frame_commit_lock u_cm (
        .axi_clk(axi_clk), .axi_rst_n(rst_n),
        .commit_req(commit_req), .commit_base(commit_base),
        .pix_clk(pix_clk), .pix_rst_n(rst_n),
        .de(de), .vsync(vs), .blank_safe(blank_safe),
        .copy_busy(copy_busy), .copy_done(copy_done_r),
        .start_copy(start_copy), .copy_base(copy_base),
        .frame_ready_pix(ready), .allow_copy_axi(allow),
        .copy_abort(abort)
    );

    integer errors=0, start_cnt=0, guard=0;
    reg [31:0] locked_seen=0;
    reg start_d=0;
    always @(posedge axi_clk) begin
        start_d <= start_copy;
        if (start_copy) start_cnt = start_cnt + 1;
        if (start_d) locked_seen <= copy_base;
    end

    initial begin
        rst_n=0; repeat(20) @(posedge axi_clk); rst_n=1;
        commit_base=32'h10000000; commit_req=1;
        repeat (5) @(posedge axi_clk); commit_req=0;
        guard=0;
        while (start_cnt<1 && guard<200000) begin @(posedge axi_clk); guard=guard+1; end
        if (start_cnt<1) begin $display("FAIL no first start"); $finish; end
        repeat (3) @(posedge axi_clk);
        $display("INFO first start base=%h", locked_seen);
        if (locked_seen !== 32'h10000000) errors=errors+1;

        commit_base=32'h10080000; commit_req=1;
        repeat (3) @(posedge axi_clk); commit_req=0;
        repeat (5) @(posedge axi_clk);
        if (copy_base === 32'h10080000 && start_cnt==1) begin
            $display("FAIL copy_base changed mid-copy");
            errors=errors+1;
        end else $display("PASS copy_base locked (%h)", copy_base);

        @(posedge axi_clk) copy_done_r<=1;
        @(posedge axi_clk) copy_done_r<=0;
        repeat (20) @(posedge axi_clk);
        start_cnt=0; start_d=0; guard=0;
        while (start_cnt<1 && guard<200000) begin @(posedge axi_clk); guard=guard+1; end
        repeat (3) @(posedge axi_clk);
        $display("INFO second start base=%h", locked_seen);
        if (locked_seen !== 32'h10080000) begin
            $display("FAIL second base %h", locked_seen);
            errors=errors+1;
        end else $display("PASS latest pending after done");

        if (errors==0) $display("PASS tb_v5_lock");
        else $display("FAIL tb_v5_lock errors=%0d", errors);
        $finish;
    end
endmodule
