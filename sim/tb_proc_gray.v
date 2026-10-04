`timescale 1ns/1ps
// 功能：被测模块 `proc_gray`（例化 `dut`，bypass 钉死 1'b0）；覆盖点：RGB565 灰度化在纯红
// 与纯白两个极端像素上的输出亮度方向，以及 de 是否跟着输入走。
// 激励与检查：#5 翻转时钟（周期 10 ns）；rst_n 上电为 0，repeat(4) @(posedge clk) 后放成 1，
// 再等 1 拍；每幅图用 de_in 举一拍灌一个像素（先 RED=16'hF800，后 WHITE=16'hFFFF），接着
// de_in 落 0、再等 1 拍采样 de_out/dout。判定条件：红像素之后 de_out 必须为 1；红的灰度
// 取高 5 位比较，dout[15:11] > 5'd20 判为"太亮"；白的 dout[15:11] < 5'd20 判为"太暗"
// —— 阈值 5'd20 是这两条实际在比的数。
// 预期结果：通过时三条判据都不红，errors==0 打印 `PASS tb_proc_gray`；失败时对应判据打
// `FAIL: de_out not set` / `FAIL: red gray too bright %h` / `FAIL: white gray too dark %h`，
// 收尾打 `FAIL tb_proc_gray errors=%0d`。
module tb_proc_gray;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg de_in = 0;
    reg [15:0] din = 0;
    wire de_out;
    wire [15:0] dout;

    proc_gray dut (
        .clk(clk), .rst_n(rst_n), .bypass(1'b0),
        .de_in(de_in), .din(din), .de_out(de_out), .dout(dout)
    );

    // pure red RGB565
    localparam [15:0] RED = 16'hF800;
    localparam [15:0] WHITE = 16'hFFFF;

    integer errors = 0;
    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        de_in <= 1; din <= RED;
        @(posedge clk);
        de_in <= 0;
        @(posedge clk);
        if (!de_out) begin
            $display("FAIL: de_out not set");
            errors = errors + 1;
        end
        // gray of red is dark; gray of white is bright
        if (dout[15:11] > 5'd20) begin
            $display("FAIL: red gray too bright %h", dout);
            errors = errors + 1;
        end

        @(posedge clk);
        de_in <= 1; din <= WHITE;
        @(posedge clk);
        de_in <= 0;
        @(posedge clk);
        if (dout[15:11] < 5'd20) begin
            $display("FAIL: white gray too dark %h", dout);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS tb_proc_gray");
        else
            $display("FAIL tb_proc_gray errors=%0d", errors);
        $finish;
    end
endmodule
