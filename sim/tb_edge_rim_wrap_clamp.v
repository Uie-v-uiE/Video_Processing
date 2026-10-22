`timescale 1ns/1ps
// 功能：被测模块 `proc_box_blur`（STREAM_WRAP=1；固定臂 V_ACTIVE=8，旧行为对照臂 V_ACTIVE=0）；覆盖点＝绕回连续流（2× 行复制）下图像上/下边界的 3×3 窗口夹取，以及行尾补跳那一格的边界决定。
// 激励与检查：首源行=8、末源行=31、其余=16，4 帧后采两帧；固定臂不许出现同时混入 8 与 31 的均值（15/18/23），且必须真的保留首行 8 与末行 31；旧行为对照臂必须出现混边（证明尺子能红）。
// 预期结果：通过时打印 `PASS A1..A5` 与 `RESULT tb_edge_rim_wrap_clamp PASS nfail=0`；失败时对应 A1/A2/A3/A4/A5 打 `FAIL` 并给出坏格数或覆盖数，末行改打 `FAIL nfail=<n>`。
// Regression: image-boundary clamp for the wrapped continuous stream.
//
// Top level feeds proc_pipeline a wrapped 2x-vertical stream:
//   ..., 6,6,7,7,0,0,1,1,...
// A 3x3 window centred on source row 0 must not take row V_ACTIVE-1 as its
// "above" tap, and a window centred on row V_ACTIVE-1 must not take row 0 as
// its "below" tap. Before V_ACTIVE was added the top row blended the previous
// frame's tail (observed 21/26 instead of 16/8 at the boundary).
//
// Two blur instances get the same stimulus:
//   u_fix : STREAM_WRAP=1, V_ACTIVE=SH  -> row-label clamp (must be clean)
//   u_old : STREAM_WRAP=1, V_ACTIVE=0   -> legacy flags (negative control,
//                                          must show the mixed values)
// Pattern: first source row = 8, last = 31, all others = 16. With clamp the
// only legal averages are 8, 10, 13, 16, 21, 26, 31. A window mixing 8 and 31
// produces 15, 18 or 23 -> impossible.
`default_nettype none
module tb_edge_rim_wrap_clamp;
    localparam integer W = 16;
    localparam integer H = 16;     // display rows
    localparam integer SH = 8;     // source rows

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg de = 0;
    reg [11:0] xs = 0, ys = 0;
    reg [15:0] din = 0;

    wire de_fix, de_old;
    wire [15:0] o_fix, o_old;

    proc_box_blur #(.H_ACTIVE(W), .STREAM_WRAP(1), .V_ACTIVE(SH)) u_fix (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0),
        .hs_in(1'b0), .vs_in(1'b0),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din),
        .de_out(de_fix), .dout(o_fix)
    );
    proc_box_blur #(.H_ACTIVE(W), .STREAM_WRAP(1), .V_ACTIVE(0)) u_old (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0),
        .hs_in(1'b0), .vs_in(1'b0),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din),
        .de_out(de_old), .dout(o_old)
    );

    function [15:0] g5; input [4:0] v; begin g5 = {v, {v,1'b0}, v}; end endfunction

    integer frame, row, col;
    integer n_fix, n_old, nc_fix, nc_old;
    reg [15:0] cap_fix [0:2*H*W-1];
    reg [15:0] cap_old [0:2*H*W-1];

    task send_line;
        input integer sy;
        begin
            for (col = 0; col < W; col = col + 1) begin
                @(negedge clk);
                de <= 1'b1; xs <= col[11:0]; ys <= sy[11:0];
                din <= g5(sy == 0 ? 5'd8 : (sy == (SH-1) ? 5'd31 : 5'd16));
            end
            @(negedge clk); de <= 1'b0;
            repeat (6) @(negedge clk);
        end
    endtask

    always @(posedge clk) begin
        if (de_fix) begin
            if (n_fix >= 2*H*W && n_fix < 4*H*W) begin cap_fix[n_fix - 2*H*W] = o_fix; nc_fix = nc_fix + 1; end
            n_fix = n_fix + 1;
        end
        if (de_old) begin
            if (n_old >= 2*H*W && n_old < 4*H*W) begin cap_old[n_old - 2*H*W] = o_old; nc_old = nc_old + 1; end
            n_old = n_old + 1;
        end
    end

    integer i, v, bad_fix, bad_old, low_fix, high_fix;
    integer nfail = 0;
    initial begin
        n_fix = 0; n_old = 0; nc_fix = 0; nc_old = 0;
        repeat (4) @(negedge clk); rst_n = 1; repeat (4) @(negedge clk);
        for (frame = 0; frame < 4; frame = frame + 1) begin
            for (row = 0; row < H; row = row + 1) send_line(row >> 1);
            repeat (40) @(negedge clk);
        end

        bad_fix = 0; bad_old = 0; low_fix = 0; high_fix = 0;
        for (i = 0; i < 2*H*W; i = i + 1) begin
            v = cap_fix[i][15:11];
            if (v == 15 || v == 18 || v == 23) begin
                bad_fix = bad_fix + 1;
                if (bad_fix <= 6)
                    $display("FAIL FIX mixed edge at cell %0d: gray=%0d", i, v);
            end
            if (v == 8)  low_fix  = low_fix + 1;
            if (v == 31) high_fix = high_fix + 1;

            v = cap_old[i][15:11];
            if (v == 15 || v == 18 || v == 23) bad_old = bad_old + 1;
        end

        if (bad_fix != 0) begin nfail = nfail + 1; $display("FAIL A1 fixed arm still mixes the opposite edge (%0d cells)", bad_fix); end
        else $display("PASS A1 fixed arm: no mixed 8/31 window");
        if (low_fix < W) begin nfail = nfail + 1; $display("FAIL A2 fixed arm has no clamped first row (gray8 cells=%0d, want >=%0d)", low_fix, W); end
        else $display("PASS A2 fixed arm keeps the first row (gray8 cells=%0d)", low_fix);
        if (high_fix < W) begin nfail = nfail + 1; $display("FAIL A3 fixed arm has no clamped last row (gray31 cells=%0d, want >=%0d)", high_fix, W); end
        else $display("PASS A3 fixed arm keeps the last row (gray31 cells=%0d)", high_fix);
        if (bad_old == 0) begin nfail = nfail + 1; $display("FAIL A4 negative control dead: legacy arm shows no mixed edge"); end
        else $display("PASS A4 negative control: legacy arm mixes the opposite edge (%0d cells)", bad_old);
        if (nc_fix != 2*H*W || nc_old != 2*H*W) begin nfail = nfail + 1; $display("FAIL A5 coverage: captured fix=%0d old=%0d (want %0d)", nc_fix, nc_old, 2*H*W); end
        else $display("PASS A5 coverage: %0d cells per arm", nc_fix);

        if (nfail == 0) $display("RESULT tb_edge_rim_wrap_clamp PASS nfail=0");
        else            $display("RESULT tb_edge_rim_wrap_clamp FAIL nfail=%0d", nfail);
        $finish;
    end
endmodule
`default_nettype wire
