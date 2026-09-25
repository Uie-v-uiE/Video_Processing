`timescale 1ns/1ps
// xtest —— 20 行的隔离实验：那份大台架里 `ddr[0]` 低 40 位是 X，到底是
//   ① 函数在拼接里被调 4 次的问题，还是 ② 别的东西（数组维度 / integer 参数 / 时间 0 的竞争）。
//   跑法：cd sim/xtest && xvlog ../xtest.v && xelab xtest -snapshot x1 && xsim x1 -runall
module xtest;
    localparam integer SRC_H = 300, WPL = 128, FRAME_WORDS = SRC_H * WPL;

    function [15:0] pv_i;  input integer  r; input integer  c; begin pv_i  = {r[7:0], c[7:0]}; end endfunction
    function [15:0] pv_sv; input [31:0] r; input [31:0] c; begin pv_sv = {r[7:0], c[7:0]}; end endfunction

    reg [63:0] a_i  [0:FRAME_WORDS-1];
    reg [63:0] a_sv [0:FRAME_WORDS-1];
    reg [63:0] a_tmp[0:FRAME_WORDS-1];
    integer ii, jj, t3, t2, t1, t0;
    initial begin
        for (ii = 0; ii < SRC_H; ii = ii + 1)
            for (jj = 0; jj < WPL; jj = jj + 1) begin
                a_i[ii*WPL+jj]  = {pv_i(ii, jj*4+3),  pv_i(ii, jj*4+2),
                                   pv_i(ii, jj*4+1),  pv_i(ii, jj*4)};
                a_sv[ii*WPL+jj] = {pv_sv(ii, jj*4+3), pv_sv(ii, jj*4+2),
                                   pv_sv(ii, jj*4+1), pv_sv(ii, jj*4)};
                t3 = pv_sv(ii, jj*4+3); t2 = pv_sv(ii, jj*4+2);
                t1 = pv_sv(ii, jj*4+1); t0 = pv_sv(ii, jj*4);
                a_tmp[ii*WPL+jj] = {t3[15:0], t2[15:0], t1[15:0], t0[15:0]};
            end
        $display("integer  args  word0=%h word1=%h", a_i[0], a_i[1]);
        $display("bitvec   args  word0=%h word1=%h", a_sv[0], a_sv[1]);
        $display("temp vars     word0=%h word1=%h", a_tmp[0], a_tmp[1]);
        $display("expected      word0=0003000200010000 word1=0007000600050004");
        $display("direct pv(0,0)=%h pv(0,3)=%h pv(1,7)=%h", pv_sv(0,0), pv_sv(0,3), pv_sv(1,7));
        $finish;
    end
endmodule
