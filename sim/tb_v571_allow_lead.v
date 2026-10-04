`timescale 1ns/1ps
// 功能：被测模块 无（本 tb 不例化 RTL，在 TB 内自建 allow 同步链：blank_safe 经 pix_clk 三级移位取 bs2，
//        bs2 再经 axi_clk 三级移位得 d0/d1/d2，allow = d1 & d2）；
//        覆盖点：blank_safe 拉低之后、de 起来之前那段导前量够不够让 allow 先落 0，
//        以及导前只有 3 个像素拍时 allow 的实际电平。
// 激励与检查：两个时钟——axi_clk #5 翻转（10 ns）、pix_clk #10 翻转（20 ns）；rst_n 低 20 个 axi 拍后放开；
//        腿1 blank_safe=1、de=0 稳定 20 个 pix 拍 + 20 个 axi 拍；
//        腿2 blank_safe=0 撑 20 个 pix 拍 + 10 个 axi 拍（产线 64-pix 导前的类比），随后 de=1 再 4 个 pix 拍；
//        腿3 先 de=0、blank_safe=1 撑 30 个 pix 拍 + 20 个 axi 拍，再 blank_safe=0 只撑 3 个 pix 拍就抬 de=1
//        跑 2 个 pix 拍（这一腿只打印 INFO，不计 errors）；
//        判定条件：腿1 结束时 allow 必须为 1，腿2 de 起来之后 allow 必须为 0。
// 预期结果：通过时打印 `PASS allow high in stable blanking` 与 `PASS allow low before/at de after lead`，
//        末行 `PASS tb_v571_allow_lead`；失败时打印 `FAIL allow should be 1 when blank_safe held high` 或
//        `FAIL allow still high after 20pix lead + de=1`、errors 加一，末行变
//        `FAIL tb_v571_allow_lead errors=<n>`；腿3 两种取值都只打 `INFO short lead ...`。
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
