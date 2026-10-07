`timescale 1ns/1ps
// 功能：被测模块 `rotate_mapper`（例化 `dut`，.IMAGE_W(64) / .IMAGE_H(36)）；覆盖点：0° 恒等
// 映射在左上角/中心/右下角三点的逐位相等，与 90° 时中心不被判越界、输出不出现 X 态。
// 激励与检查：#5 翻转时钟（周期 10 ns）；rst_n 上电为 0，repeat(3) @(posedge clk) 后放成 1
// 再等 1 拍；check_id 任务每次把 angle=0、配上 (x_in,y_in)，然后 repeat(5) @(posedge clk)
// 等流水稳定（注释记的是 3 级流水、5 拍后采样），三点依次为 (0,0)、(32,18)、(63,35)；
// 90° 两笔不走 task：angle=9'd90 配 (32,18) 后 repeat(3) @(posedge clk)，再换 (0,0) 等 3 拍。
// 判定条件：angle=0 时 oob 必须为 0 且 x_out !== x_in、y_out !== y_in 都不成立（逐位等）；
// 90° 中心那笔只判 oob 为 0；90° 角点那笔不判 oob 取值，只判 ^x_out 与 ^y_out 都不是 1'bx。
// 预期结果：通过时每笔恒等检查各打一条 `PASS id (%0d,%0d)`，errors==0 收尾打
// `PASS tb_rotate_mapper`；失败时对应判据红在 `FAIL id (%0d,%0d)->(%0d,%0d) oob=%b`、
// `FAIL 90 center oob`、`FAIL X on outputs`，收尾打 `FAIL tb_rotate_mapper errors=%0d`。
// Verify rotate_mapper identity at 0° and 90° center/edge cases
module tb_rotate_mapper;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg [8:0] angle = 0;
    reg [11:0] x_in = 0, y_in = 0;
    wire [11:0] x_out, y_out;
    wire oob;

    rotate_mapper #(.IMAGE_W(64), .IMAGE_H(36)) dut (
        .clk(clk), .rst_n(rst_n), .angle(angle), .enable(1'b1),
        .x_in(x_in), .y_in(y_in),
        .x_out(x_out), .y_out(y_out), .oob(oob)
    );

    integer errors = 0;

    task check_id;
        input [11:0] x, y;
        begin
            angle = 0; x_in = x; y_in = y;
            // rotate_mapper is 3-stage pipeline; sample after 5 clocks
            repeat (5) @(posedge clk);
            if (oob || x_out !== x || y_out !== y) begin
                $display("FAIL id (%0d,%0d)->(%0d,%0d) oob=%b", x, y, x_out, y_out, oob);
                errors = errors + 1;
            end else
                $display("PASS id (%0d,%0d)", x, y);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        check_id(0, 0);
        check_id(32, 18); // center-ish
        check_id(63, 35);

        // 90°: center maps to center
        angle = 9'd90;
        x_in = 12'd32; y_in = 12'd18;
        repeat (3) @(posedge clk);
        if (oob) begin
            $display("FAIL 90 center oob");
            errors = errors + 1;
        end

        // far corner 90° should often be oob for 64x36
        angle = 9'd90;
        x_in = 12'd0; y_in = 12'd0;
        repeat (3) @(posedge clk);
        // may or may not be oob — just ensure no X
        if (^x_out === 1'bx || ^y_out === 1'bx) begin
            $display("FAIL X on outputs");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS tb_rotate_mapper");
        else
            $display("FAIL tb_rotate_mapper errors=%0d", errors);
        $finish;
    end
endmodule
