`timescale 1ns/1ps
// tb_v83_card_render —— 不是判据，是**取景器**：把 test_card 的像素逐点倒到文件里，
// 再用脚本转成 PNG。为什么要它：图卡好不好看，以前只能等一次完整构建 + 上板看屏幕，
// 一轮 40 分钟；而"丑"这件事根本不值得花一轮构建去发现。
//
// 采样契约（与顶层 PROC_LAT 无关，这里只测 test_card 本身）：
// 输入在 negedge 驱动 ⇒ 下一个 posedge 打进输出寄存器 ⇒ **再下一个 negedge** 读到的
// 就是刚驱动那个像素的值。所以循环体是"先读上一像素，再驱动本像素"，帧末多走一拍冲刷。
//
// 输出：<运行目录>/card_dump.txt，每行 `frame x y r g b`（8 bit 每通道，按 RGB565 标准还原）。
module tb_v83_card_render;
    localparam H = 512, V = 300, FRAMES = 6;

    reg clk = 0, rst_n = 0, vs = 0, de = 0;
    reg [11:0] xs = 0, ys = 0;
    wire [15:0] out;
    integer fd, f, yy, xx, px, py, have;
    // 取景器也要表态：runner 的规矩是"没有 PASS/FAIL 就判失败"，所以这里做四条真断言
    // （它不是判据台架，但它骗人的话，"我看着好看"这个结论就建立在一张坏图上）
    integer written[0:FRAMES-1];      // 每帧写出的像素数
    integer nx, white_cnt[0:FRAMES-1];// X 态计数 / 每帧纯白像素数（球心）
    integer diff_prev, last_white;    // 跨帧变化像素数（≥1 帧之后才有意义）
    reg [15:0] prev_img [0:H*V-1];
    integer idx, bad, gi;

    test_card #(.H_ACTIVE(H), .V_ACTIVE(V)) dut (
        .clk(clk), .rst_n(rst_n), .vs(vs), .x(xs), .y(ys), .de(de), .rgb565(out));

    always #5 clk = ~clk;                     // 100 MHz 仿真时钟

    // 565 → 888：高位照搬，低位用**自身低位**复制补齐（R5→R8 补 3 位、G6 补 2、B5 补 3）。
    // 原来写成 {out[15:11], out[15:14], out[15:13]} 是 9 位赋给 8 位 ⇒ 截掉 MSB，
    // 球心的 0xC8 变成 0x3E，看图会以为颜色全错（先看图才发现的，省了一轮构建）。
    task put(input integer fr, input integer y, input integer x);
        reg [7:0] r8, g8, b8;
        begin
            r8 = {out[15:11], out[13:11]};
            g8 = {out[10:5],  out[6:5]};
            b8 = {out[4:0],   out[2:0]};
            $fwrite(fd, "%0d %0d %0d %0d %0d %0d\n", fr, x, y, r8, g8, b8);
            written[fr] = written[fr] + 1;
            if (^out === 1'bx) nx = nx + 1;                 // 有 X 态就说明图卡算不出来
            if (out === 16'hFFFF) white_cnt[fr] = white_cnt[fr] + 1;
            if (fr > 0) begin
                idx = y * H + x;
                if (prev_img[idx] !== out) diff_prev = diff_prev + 1;
                prev_img[idx] = out;                        // 同序扫描 ⇒ 存的正是上一帧
            end
        end
    endtask

    initial begin
        // 计数器必须先清零：Verilog 的 integer 数组初值是 x，`x+1` 还是 x，判据会静默失效
        for (gi = 0; gi < FRAMES; gi = gi + 1) begin
            written[gi] = 0; white_cnt[gi] = 0;
        end
        nx = 0; diff_prev = 0; bad = 0;
        fd = $fopen("card_dump.txt");
        if (fd == 0) begin $display("OPEN_FAIL card_dump.txt"); $finish; end
        repeat (4) @(negedge clk);
        rst_n = 1;
        for (f = 0; f < FRAMES; f = f + 1) begin
            @(negedge clk); vs = 1;                     // 场边界：dut 里 frame/相位加一
            @(negedge clk); vs = 0;
            have = 0; px = 0; py = 0;
            for (yy = 0; yy < V; yy = yy + 1) begin
                for (xx = 0; xx < H; xx = xx + 1) begin
                    if (have) put(f, py, px);           // 先读上一像素
                    @(negedge clk);
                    xs = xx[11:0]; ys = yy[11:0]; de = 1;
                    px = xx; py = yy; have = 1;
                end
            end
            @(negedge clk);                             // 冲刷最后一像素
            if (have) put(f, py, px);
            @(negedge clk); de = 0;
        end
        $fclose(fd);
        // ---- 取景器自己的四条断言（不表态的台架按失败算，这是 sim/run_sim.tcl 的规矩）----
        for (gi = 0; gi < FRAMES; gi = gi + 1)
            if (written[gi] != H*V) begin
                $display("FAIL 帧 %0d 只写了 %0d 像素（应 %0d）", gi, written[gi], H*V);
                bad = bad + 1;
            end
        if (nx != 0) begin $display("FAIL 输出含 X 态 %0d 处", nx); bad = bad + 1; end
        for (gi = 0; gi < FRAMES; gi = gi + 1)
            if (white_cnt[gi] == 0) begin
                $display("FAIL 帧 %0d 没有纯白像素 ⇒ 球没画出来，这张预览不可信", gi);
                bad = bad + 1;
            end
        if (diff_prev == 0) begin
            $display("FAIL 跨帧一个像素都没变 ⇒ 拍到的是静止图，用它判'好看'无效");
            bad = bad + 1;
        end
        $display("INFO 每帧像素=%0d 白点=%0d/%0d/%0d 跨帧变化=%0d X态=%0d",
                 written[0], white_cnt[0], white_cnt[1], white_cnt[2], diff_prev, nx);
        if (bad == 0) $display("PASS tb_v83_card_render");
        else          $display("FAIL tb_v83_card_render errors=%0d", bad);
        $finish;
    end
endmodule
