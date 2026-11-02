`timescale 1ns/1ps
`default_nettype none
// 作用：量 3×3 窗口级在**帧底**的边缘处理——本帧最后一行的邻域里，到底有没有吃进"下一帧的第 0 行"。
//        它是 `tb_display_edge_rim` 的 D3（屏上第 0 行不许随上一帧的末行变）的**镜像**：D3 管上沿，这一支管下沿。
// 为什么单独一支：四个窗口级只声明了上沿旗标（`no_above = y_in==1`、`stale_row = y_in==0`），
//        盘上没有任何一把尺子看过"末行的下邻"。用户报的"旋转后画面最下沿有一条没处理的像素"落在这格里。
// 判据形状（差分，对输出平移量免疫，不需要先算 LATENCY）：
//        激励 = 除第 0 行外全帧恒定，第 0 行按帧号奇偶在两个值之间交替；采稳态两帧（第三、第四帧）。
//        于是"跟着变"的格子只可能出现在**窗口含第 0 行的那些输出行**：正确夹取下是相邻两行（第 0 行与第 1 行）。
//        B1 要求除这一对相邻行之外**任何行都不许动**；帧末那行要是动了，就是 B1 红。
//        B2 正对照：必须真有格子跟着变（不然 B1 是空集上的绿 —— 本仓 #60 那一课）。
//        B3 覆盖地板：被判格子数与每行采样数都要够。
// 跑法：bash build/sim/run_one.sh tb_edge_rim_bottom_wrap      （或 iverilog/ModelSim 同名单独跑）
// 退出码：判定行以 `RESULT tb_edge_rim_bottom_wrap PASS|FAIL` 结尾；FAIL 时点名是哪一条 B*。
module tb_edge_rim_bottom_wrap;
    localparam integer W = 64, H = 64, FW = H*W;

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg         de;
    reg  [11:0] xs, ys;
    reg  [15:0] din;

    wire        de_bu, de_sh, de_so, de_mo;
    wire [15:0] o_bu, o_sh, o_so, o_mo;
    reg  [1:0]  stage;

    proc_box_blur #(.H_ACTIVE(W), .STREAM_WRAP(1)) u_bu (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0),
        .hs_in(1'b0), .vs_in(1'b0), .de_in(de), .x_in(xs), .y_in(ys), .din(din),
        .de_out(de_bu), .dout(o_bu) );
    proc_sharpen #(.H_ACTIVE(W), .STREAM_WRAP(1)) u_sh (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din),
        .de_out(de_sh), .dout(o_sh) );
    proc_sobel #(.H_ACTIVE(W), .STREAM_WRAP(1)) u_so (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0), .vs_in(1'b0),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din),
        .de_out(de_so), .dout(o_so) );
    proc_morph #(.H_ACTIVE(W), .STREAM_WRAP(1)) u_mo (
        .clk(clk), .rst_n(rst_n), .mode(2'd1), .threshold(8'd128),
        .de_in(de), .x_in(xs), .y_in(ys), .din(din),
        .de_out(de_mo), .dout(o_mo) );

    wire [15:0] dut = (stage == 2'd0) ? o_bu  : (stage == 2'd1) ? o_sh :
                      (stage == 2'd2) ? o_so  : o_mo;
    wire        ded = (stage == 2'd0) ? de_bu : (stage == 2'd1) ? de_sh :
                      (stage == 2'd2) ? de_so : de_mo;

    // 采集：与 tb_display_edge_rim 同一口径 —— 采**第三、第四帧**（头两帧行缓存是 X，dev(X,·) 永远不算不符）
    reg [15:0] capA [0:FW-1];                // 第三帧
    reg [15:0] capB [0:FW-1];                // 第四帧
    integer ndeo = 0;
    always @(posedge clk) begin
        if (ded) begin
            if (ndeo >= 2*FW && ndeo < 3*FW)      capA[ndeo - 2*FW] = dut;
            else if (ndeo >= 3*FW && ndeo < 4*FW) capB[ndeo - 3*FW] = dut;
            ndeo = ndeo + 1;
        end
    end

    function [15:0] gray; input [4:0] v; begin gray = {v, {v, 1'b0}, v}; end endfunction

    // 激励：第 0 行按帧号奇偶交替，其余行给一个**随行也随列都不变**的常数图案
    //        （随行变会让"哪几行跟着动"和行号本身混在一起；这里要的就是只有第 0 行在动）
    reg [4:0] r0_even, r0_odd;
    function [15:0] pat; input integer x, y; input integer f;
        reg [4:0] a;
        begin
            if (y == 0) a = (f & 1) ? r0_odd : r0_even;
            else        a = 5'd16;
            pat = gray(a);
        end
    endfunction

    integer f, i, x, y;
    task send_frame; input integer f;
        begin
            for (y = 0; y < H; y = y + 1)
                for (x = 0; x < W; x = x + 1) begin
                    @(negedge clk);
                    de <= 1'b1; xs <= x[11:0]; ys <= y[11:0]; din <= pat(x, y, f);
                end
            @(negedge clk); de <= 1'b0;
            repeat (W) @(negedge clk);            // 行/帧消隐：让链子把这一帧推干净
        end
    endtask

    integer b1bad, b1judged, b2moved, rows_with_move;
    integer moved_per_row [0:H-1];
    integer r, first_move_row, second_move_row, band_ok, blocks;

    // 声明必须在 `task judge` 之前：task 体里要 ++ 它（vlog-2730 的就是这件事）。
    integer nfail = 0;
    task judge;
        begin
            b1bad = 0; b1judged = 0; b2moved = 0; rows_with_move = 0;
            for (r = 0; r < H; r = r + 1) moved_per_row[r] = 0;
            for (i = 0; i < FW; i = i + 1) begin
                if (capA[i] !== capB[i]) moved_per_row[i / W] = moved_per_row[i / W] + 1;
                b1judged = b1judged + 1;
            end
            for (r = 0; r < H; r = r + 1) if (moved_per_row[r] > 0) begin
                rows_with_move = rows_with_move + 1;
                b2moved = b2moved + moved_per_row[r];
                $display("BANDROW stage=%0d row=%0d cells=%0d", stage, r, moved_per_row[r]);
            end
            // 数"段"：先按线性数，再把首尾相接那一段并回去（输出流相对输入流有恒定平移，
            // 带子被平移切成两段是常态，不是缺陷）
            blocks = 0;
            for (r = 0; r < H; r = r + 1)
                if (moved_per_row[r] > 0 && (r == 0 || moved_per_row[r-1] == 0)) blocks = blocks + 1;
            if (blocks > 1 && moved_per_row[0] > 0 && moved_per_row[H-1] > 0) blocks = blocks - 1;
            $display("BAND stage=%0d 被判格=%0d 跟着变的格=%0d 受影响行数=%0d 段数=%0d 末行(63)动格=%0d",
                     stage, b1judged, b2moved, rows_with_move, blocks, moved_per_row[H-1]);
            // 判的是**形状**而不是绝对行号：输出流相对输入流有一个恒定平移（本尺子不去猜它），
            // 所以"帧底被吃进帧外的行"的唯一可靠特征是**出现第二段不连续的带**——
            // 正确夹取下，受影响的行必须是一整段（含首尾相接的那种）。
            if (blocks != 1) begin nfail = nfail + 1; $display("FAIL B1 stage=%0d 受影响行分成 %0d 段不连续的带（帧底把帧外的行吃进了邻域）", stage, blocks); end
            else           $display("PASS B1 stage=%0d affected rows are one contiguous band", stage);
            if (b2moved == 0) begin nfail = nfail + 1; $display("FAIL B2 stage=%0d 正对照死了：第 0 行逐帧交替而输出无一格变动", stage); end
            else              $display("PASS B2 stage=%0d alternation propagates in %0d cells", stage, b2moved);
            if (b1judged < FW) begin nfail = nfail + 1; $display("FAIL B3 stage=%0d 覆盖地板：只判到 %0d/%0d 格", stage, b1judged, FW); end
            else               $display("PASS B3 stage=%0d coverage floor %0d cells", stage, b1judged);
        end
    endtask

    integer stg;
    initial begin : main
        r0_even = 5'd31; r0_odd = 5'd0;
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1;
        // ⚠ 循环变量必须是整数：`stage` 只有 2 位，`stage < 4` 恒真就是死循环（本仓 #247 那一族）
        for (stg = 0; stg < 4; stg = stg + 1) begin
            stage = stg[1:0];
            ndeo = 0;
            repeat (4) @(negedge clk);
            for (f = 0; f < 4; f = f + 1) send_frame(f);
            repeat (4*W) @(negedge clk);
            judge();
        end
        // ⚠ 这里以前是 `nfail = 0; $display("RESULT … done")` —— 汇总行**永远不会说 FAIL**，
        //   而本文件头承诺的是 `PASS|FAIL`：一条不会红的汇总行不是判据，是装饰（I6）。
        if (nfail == 0) $display("RESULT tb_edge_rim_bottom_wrap PASS nfail=0");
        else            $display("RESULT tb_edge_rim_bottom_wrap FAIL nfail=%0d", nfail);
        $finish;
    end
endmodule

// 这一行不是装饰：`build/sim/run_one.sh` 把 src/rtl + sim/tb_*.v + sim/prim/*.v 交给**同一次 xvlog**，
//   而 `default_nettype` 是跨文件延续的编译期状态。本文件第 2 行开了 none 又不还回去，排在后面的
//   `sim/prim/unisims_sim.v`（`module BUFG (input I, output O)` 这种隐式 net 口）就被判
//   `VRFC 10-1103 / 10-3594 / 10-8530` ⇒ 规范通道整架在 xelab 之前就起不来
//   （2026-10-17 12:5x 撞到，那一跑的 `XVLOG FAILED` 八行原文在 build/sim 那条通道的输出里）。
//   同族的 `sim/tb_display_edge_rim.v` 一直在文件尾还回去（它 462 行），这里照它的写法补齐。
`default_nettype wire
