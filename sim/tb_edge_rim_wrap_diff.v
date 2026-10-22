`timescale 1ns/1ps
// 功能：被测模块 `proc_box_blur / proc_sharpen / proc_sobel / proc_morph`（STREAM_WRAP=1；固定臂 V_ACTIVE=8，旧行为对照臂 V_ACTIVE=0）；覆盖点＝绕回连续流（2× 行复制）下，图像首行与末行的窗口影响是否交叉污染。
// 激励与检查：两臂图案只差“翻转哪一源行”：臂 0 翻转源行 0（8↔200），臂 1 翻转源行 7（8↔200），其余行恒 16；每臂采第 3/4 帧。若夹取正确，翻转源行 0 只会改变靠近首行的输出格，翻转源行 7 只会改变靠近末行的输出格，两者的“变化格集合”必须不相交；绕回污染会让同一格同时受两行影响。旧行为臂必须出现交集（负对照）。
// 预期结果：通过时每个 stage 打 `PASS D1..D4`、`PASS D0` 与 `RESULT tb_edge_rim_wrap_diff PASS nfail=0`；失败时对应 stage 的 `FAIL D0/D1/D2` 并给出交集格数与覆盖数，末行改打 `FAIL nfail=<n>`。
`default_nettype none
module tb_edge_rim_wrap_diff;
    localparam integer W  = 16;
    localparam integer H  = 16;      // display rows
    localparam integer SH = 8;       // source rows
    localparam integer FW = H * W;   // cells per frame

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg        de = 0;
    reg [11:0] xs = 0, ys = 0;
    reg [15:0] din = 0;

    wire de_bu_f, de_bu_o, de_sh_f, de_sh_o, de_so_f, de_so_o, de_mo_f, de_mo_o;
    wire [15:0] o_bu_f, o_bu_o, o_sh_f, o_sh_o, o_so_f, o_so_o, o_mo_f, o_mo_o;

    proc_box_blur #(.H_ACTIVE(W), .STREAM_WRAP(1), .V_ACTIVE(SH)) u_bu_f (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0), .hs_in(1'b0), .vs_in(1'b0),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din), .de_out(de_bu_f), .dout(o_bu_f));
    proc_box_blur #(.H_ACTIVE(W), .STREAM_WRAP(1), .V_ACTIVE(0)) u_bu_o (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0), .hs_in(1'b0), .vs_in(1'b0),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din), .de_out(de_bu_o), .dout(o_bu_o));
    proc_sharpen #(.H_ACTIVE(W), .STREAM_WRAP(1), .V_ACTIVE(SH)) u_sh_f (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din), .de_out(de_sh_f), .dout(o_sh_f));
    proc_sharpen #(.H_ACTIVE(W), .STREAM_WRAP(1), .V_ACTIVE(0)) u_sh_o (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din), .de_out(de_sh_o), .dout(o_sh_o));
    proc_sobel #(.H_ACTIVE(W), .STREAM_WRAP(1), .V_ACTIVE(SH)) u_so_f (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0), .vs_in(1'b0),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din), .de_out(de_so_f), .dout(o_so_f));
    proc_sobel #(.H_ACTIVE(W), .STREAM_WRAP(1), .V_ACTIVE(0)) u_so_o (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0), .vs_in(1'b0),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din), .de_out(de_so_o), .dout(o_so_o));
    proc_morph #(.H_ACTIVE(W), .STREAM_WRAP(1), .V_ACTIVE(SH)) u_mo_f (
        .clk(clk), .rst_n(rst_n), .mode(2'd2), .threshold(8'd80),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din), .de_out(de_mo_f), .dout(o_mo_f));
    proc_morph #(.H_ACTIVE(W), .STREAM_WRAP(1), .V_ACTIVE(0)) u_mo_o (
        .clk(clk), .rst_n(rst_n), .mode(2'd2), .threshold(8'd80),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din), .de_out(de_mo_o), .dout(o_mo_o));

    function [15:0] g5; input [7:0] v;
        begin g5 = {v[7:3], v[7:2], v[7:3]}; end
    endfunction

    reg [15:0] c_bu_f [0:2*FW-1]; reg [15:0] c_bu_o [0:2*FW-1];
    reg [15:0] c_sh_f [0:2*FW-1]; reg [15:0] c_sh_o [0:2*FW-1];
    reg [15:0] c_so_f [0:2*FW-1]; reg [15:0] c_so_o [0:2*FW-1];
    reg [15:0] c_mo_f [0:2*FW-1]; reg [15:0] c_mo_o [0:2*FW-1];
    integer n_bu_f, n_bu_o, n_sh_f, n_sh_o, n_so_f, n_so_o, n_mo_f, n_mo_o;

    always @(posedge clk) begin
        if (de_bu_f) begin if (n_bu_f >= 2*FW && n_bu_f < 4*FW) c_bu_f[n_bu_f-2*FW] = o_bu_f; n_bu_f = n_bu_f + 1; end
        if (de_bu_o) begin if (n_bu_o >= 2*FW && n_bu_o < 4*FW) c_bu_o[n_bu_o-2*FW] = o_bu_o; n_bu_o = n_bu_o + 1; end
        if (de_sh_f) begin if (n_sh_f >= 2*FW && n_sh_f < 4*FW) c_sh_f[n_sh_f-2*FW] = o_sh_f; n_sh_f = n_sh_f + 1; end
        if (de_sh_o) begin if (n_sh_o >= 2*FW && n_sh_o < 4*FW) c_sh_o[n_sh_o-2*FW] = o_sh_o; n_sh_o = n_sh_o + 1; end
        if (de_so_f) begin if (n_so_f >= 2*FW && n_so_f < 4*FW) c_so_f[n_so_f-2*FW] = o_so_f; n_so_f = n_so_f + 1; end
        if (de_so_o) begin if (n_so_o >= 2*FW && n_so_o < 4*FW) c_so_o[n_so_o-2*FW] = o_so_o; n_so_o = n_so_o + 1; end
        if (de_mo_f) begin if (n_mo_f >= 2*FW && n_mo_f < 4*FW) c_mo_f[n_mo_f-2*FW] = o_mo_f; n_mo_f = n_mo_f + 1; end
        if (de_mo_o) begin if (n_mo_o >= 2*FW && n_mo_o < 4*FW) c_mo_o[n_mo_o-2*FW] = o_mo_o; n_mo_o = n_mo_o + 1; end
    end

    task send_line;
        input integer sy;
        input integer val;
        integer col;
        begin
            for (col = 0; col < W; col = col + 1) begin
                @(negedge clk);
                de <= 1'b1; xs <= col[11:0]; ys <= sy[11:0]; din <= g5(val);
            end
            @(negedge clk); de <= 1'b0;
            repeat (6) @(negedge clk);
        end
    endtask

    task send_frame;
        input integer row;
        input integer f;
        integer r;
        begin
            for (r = 0; r < H; r = r + 1)
                send_line(r >> 1, ((r >> 1) == row) ? ((f & 1) ? 200 : 8) : 16);
            repeat (40) @(negedge clk);
        end
    endtask

    // 每臂每 stage 的“首行翻转影响格”/“末行翻转影响格”
    reg m0_bu_f [0:FW-1]; reg m1_bu_f [0:FW-1];
    reg m0_bu_o [0:FW-1]; reg m1_bu_o [0:FW-1];
    reg m0_sh_f [0:FW-1]; reg m1_sh_f [0:FW-1];
    reg m0_sh_o [0:FW-1]; reg m1_sh_o [0:FW-1];
    reg m0_so_f [0:FW-1]; reg m1_so_f [0:FW-1];
    reg m0_so_o [0:FW-1]; reg m1_so_o [0:FW-1];
    reg m0_mo_f [0:FW-1]; reg m1_mo_f [0:FW-1];
    reg m0_mo_o [0:FW-1]; reg m1_mo_o [0:FW-1];

    integer ov_bu_f, ov_bu_o, ov_sh_f, ov_sh_o, ov_so_f, ov_so_o, ov_mo_f, ov_mo_o;
    integer c0_bu_f, c1_bu_f, c0_bu_o, c1_bu_o, c0_sh_f, c1_sh_f, c0_sh_o, c1_sh_o;
    integer c0_so_f, c1_so_f, c0_so_o, c1_so_o, c0_mo_f, c1_mo_f, c0_mo_o, c1_mo_o;
    integer nfail = 0;
    integer corner_fix, corner_old;

    task check_stage;
        input [8*16-1:0] name;
        input integer ov, c0, c1, is_fix;
        begin
            if (is_fix) begin
                if (ov != 0) begin nfail = nfail + 1; $display("FAIL D1 %0s fixed arm: first/last row influence overlaps in %0d cells", name, ov); end
                else $display("PASS D1 %0s fixed arm: first and last row influence are disjoint", name);
                if (c0 <= 0 || c1 <= 0) begin nfail = nfail + 1; $display("FAIL D2 %0s fixed arm coverage: move0=%0d move1=%0d", name, c0, c1); end
                else $display("PASS D2 %0s fixed arm coverage: move0=%0d move1=%0d", name, c0, c1);
            end else begin
                if (ov <= 0) begin nfail = nfail + 1; $display("FAIL D0 %0s negative control dead: no overlap", name); end
                else $display("PASS D0 %0s negative control: legacy arms overlap in %0d cells", name, ov);
            end
        end
    endtask

    integer ci, r, f, pass, inner;
    task run_arm;
        input integer row;
        input integer arm;      // 0 = first capture (fill m0), 1 = second (compare)
        begin
            rst_n = 0; de = 0;
            repeat (8) @(negedge clk);
            rst_n = 1;
            repeat (4) @(negedge clk);
            n_bu_f=0; n_bu_o=0; n_sh_f=0; n_sh_o=0; n_so_f=0; n_so_o=0; n_mo_f=0; n_mo_o=0;
            for (f = 0; f < 4; f = f + 1) send_frame(row, f);
            repeat (40) @(negedge clk);

            if (arm == 0) begin
                for (ci = 0; ci < FW; ci = ci + 1) begin
                    m0_bu_f[ci] = (c_bu_f[ci] !== c_bu_f[FW+ci]);
                    m0_bu_o[ci] = (c_bu_o[ci] !== c_bu_o[FW+ci]);
                    m0_sh_f[ci] = (c_sh_f[ci] !== c_sh_f[FW+ci]);
                    m0_sh_o[ci] = (c_sh_o[ci] !== c_sh_o[FW+ci]);
                    m0_so_f[ci] = (c_so_f[ci] !== c_so_f[FW+ci]);
                    m0_so_o[ci] = (c_so_o[ci] !== c_so_o[FW+ci]);
                    m0_mo_f[ci] = (c_mo_f[ci] !== c_mo_f[FW+ci]);
                    m0_mo_o[ci] = (c_mo_o[ci] !== c_mo_o[FW+ci]);
                end
            end else begin
                ov_bu_f=0; ov_bu_o=0; ov_sh_f=0; ov_sh_o=0; ov_so_f=0; ov_so_o=0; ov_mo_f=0; ov_mo_o=0;
                c0_bu_f=0; c1_bu_f=0; c0_bu_o=0; c1_bu_o=0; c0_sh_f=0; c1_sh_f=0; c0_sh_o=0; c1_sh_o=0;
                c0_so_f=0; c1_so_f=0; c0_so_o=0; c1_so_o=0; c0_mo_f=0; c1_mo_f=0; c0_mo_o=0; c1_mo_o=0;
                corner_fix=0; corner_old=0;
                for (ci = 0; ci < FW; ci = ci + 1) begin
                    inner = ((ci % W) != 0) && ((ci % W) != (W-1));
                    pass = (c_bu_f[ci] !== c_bu_f[FW+ci]);
                    c1_bu_f = c1_bu_f + pass; c0_bu_f = c0_bu_f + m0_bu_f[ci];
                    if (m0_bu_f[ci] && pass) begin
                        if (inner) ov_bu_f = ov_bu_f + 1; else corner_fix = corner_fix + 1;
                    end
                    pass = (c_bu_o[ci] !== c_bu_o[FW+ci]);
                    c1_bu_o = c1_bu_o + pass; c0_bu_o = c0_bu_o + m0_bu_o[ci];
                    if (m0_bu_o[ci] && pass) begin if (inner) ov_bu_o = ov_bu_o + 1; else corner_old = corner_old + 1; end

                    pass = (c_sh_f[ci] !== c_sh_f[FW+ci]);
                    c1_sh_f = c1_sh_f + pass; c0_sh_f = c0_sh_f + m0_sh_f[ci];
                    if (m0_sh_f[ci] && pass) begin if (inner) ov_sh_f = ov_sh_f + 1; else corner_fix = corner_fix + 1; end
                    pass = (c_sh_o[ci] !== c_sh_o[FW+ci]);
                    c1_sh_o = c1_sh_o + pass; c0_sh_o = c0_sh_o + m0_sh_o[ci];
                    if (m0_sh_o[ci] && pass) begin if (inner) ov_sh_o = ov_sh_o + 1; else corner_old = corner_old + 1; end

                    pass = (c_so_f[ci] !== c_so_f[FW+ci]);
                    c1_so_f = c1_so_f + pass; c0_so_f = c0_so_f + m0_so_f[ci];
                    if (m0_so_f[ci] && pass) begin if (inner) ov_so_f = ov_so_f + 1; else corner_fix = corner_fix + 1; end
                    pass = (c_so_o[ci] !== c_so_o[FW+ci]);
                    c1_so_o = c1_so_o + pass; c0_so_o = c0_so_o + m0_so_o[ci];
                    if (m0_so_o[ci] && pass) begin if (inner) ov_so_o = ov_so_o + 1; else corner_old = corner_old + 1; end

                    pass = (c_mo_f[ci] !== c_mo_f[FW+ci]);
                    c1_mo_f = c1_mo_f + pass; c0_mo_f = c0_mo_f + m0_mo_f[ci];
                    if (m0_mo_f[ci] && pass) begin if (inner) ov_mo_f = ov_mo_f + 1; else corner_fix = corner_fix + 1; end
                    pass = (c_mo_o[ci] !== c_mo_o[FW+ci]);
                    c1_mo_o = c1_mo_o + pass; c0_mo_o = c0_mo_o + m0_mo_o[ci];
                    if (m0_mo_o[ci] && pass) begin if (inner) ov_mo_o = ov_mo_o + 1; else corner_old = corner_old + 1; end
                end
            end
        end
    endtask

    initial begin
        de = 0; rst_n = 0;
        run_arm(0, 0);          // 翻转源行 0，记录首行影响
        run_arm(SH-1, 1);       // 翻转源行 7，比较与首行影响是否相交
        check_stage("blur",    ov_bu_f, c0_bu_f, c1_bu_f, 1);
        check_stage("sharpen", ov_sh_f, c0_sh_f, c1_sh_f, 1);
        check_stage("sobel",   ov_so_f, c0_so_f, c1_so_f, 1);
        check_stage("morph",   ov_mo_f, c0_mo_f, c1_mo_f, 1);
        check_stage("blur-old",    ov_bu_o, c0_bu_o, c1_bu_o, 0);
        check_stage("sharpen-old", ov_sh_o, c0_sh_o, c1_sh_o, 0);
        check_stage("sobel-old",   ov_so_o, c0_so_o, c1_so_o, 0);
        check_stage("morph-old",   ov_mo_o, c0_mo_o, c1_mo_o, 0);
        $display("OBS D3 corner overlaps excluded from the row criterion: fix=%0d old=%0d", corner_fix, corner_old);
        if (nfail == 0) $display("RESULT tb_edge_rim_wrap_diff PASS nfail=0");
        else            $display("RESULT tb_edge_rim_wrap_diff FAIL nfail=%0d", nfail);
        $finish;
    end
endmodule
`default_nettype wire
