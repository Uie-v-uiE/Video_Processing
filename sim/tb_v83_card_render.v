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
        end
    endtask

    initial begin
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
        $display("RENDER DONE frames=%0d %0dx%0d", FRAMES, H, V);
        $finish;
    end
endmodule
