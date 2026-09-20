`timescale 1ns/1ps
// Directed: blank_safe low long enough ⇒ allow must be low when de pulses
module tb_v571_allow_lead;
    reg axi_clk=0, pix_clk=0, rst_n=0;
    always #5 axi_clk=~axi_clk;
    always #10 pix_clk=~pix_clk;

    reg blank_safe=1, de=0;
    reg bs0,bs1,bs2,d0,d1,d2;
    always @(posedge pix_clk) begin
        if (!rst_n) {bs2,bs1,bs0}<=0;
        else {bs2,bs1,bs0}<={bs1,bs0,blank_safe};
    end
    always @(posedge axi_clk) begin
        if (!rst_n) {d2,d1,d0}<=0;
        else {d2,d1,d0}<={d1,d0,bs2};
    end
    wire allow = d1 & d2;

    integer errors=0, i;
    integer bad=0;
    initial begin
        rst_n=0; repeat(20) @(posedge axi_clk); rst_n=1;
        // open blanking
        blank_safe=1; de=0;
        repeat (20) @(posedge pix_clk);
        repeat (20) @(posedge axi_clk);
        if (!allow) begin
            $display("FAIL allow should be 1 when blank_safe held high");
            errors=errors+1;
        end else $display("PASS allow high in stable blanking");

        // production-like lead: blank_safe=0 for 20 pix (64-pix lead analogue)
        blank_safe=0;
        repeat (20) @(posedge pix_clk);
        repeat (10) @(posedge axi_clk);
        // de rises now
        de=1;
        repeat (4) @(posedge pix_clk);
        if (allow) begin
            $display("FAIL allow still high after 20pix lead + de=1");
            errors=errors+1;
        end else $display("PASS allow low before/at de after lead");

        // too-short lead (3 pix) — documents why production needs ~64 pix
        de=0; blank_safe=1;
        repeat (30) @(posedge pix_clk);
        repeat (20) @(posedge axi_clk);
        blank_safe=0;
        repeat (3) @(posedge pix_clk);
        de=1;
        repeat (2) @(posedge pix_clk);
        if (allow) $display("INFO short lead still allow=1 (expected; why 64pix margin)");
        else $display("INFO short lead already allow=0");

        if (errors==0) $display("PASS tb_v571_allow_lead");
        else $display("FAIL tb_v571_allow_lead errors=%0d", errors);
        $finish;
    end
endmodule
