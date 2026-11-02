`timescale 1ns/1ps
// tb_gmii_rx_cdc — 恢复时钟 → clk_eth 的 GMII 字节搬运。
// 覆盖点：
//  A 两帧（8B 前导 + 64B 帧 + 8B 前导 + 300B 帧）逐字节穿过 CDC，不丢不重；
//  B 两个钟有相位差且读钟略快（+1000 ppm）时仍不丢字节（帧内不会假空）；
//  C 帧间低电平被搬过去（out_dv 在两帧之间出现 0）。
// 判据：scoreboard 在 out_dv 上逐个弹出输入队列；结束时队列空、且两帧各看到一次 dv 下降。
module tb_gmii_rx_cdc;
    reg rx_clk = 0, clk = 0, rx_rst_n = 0, rst_n = 0;
    // 读钟比写钟快 1000 ppm，相位错开 2.7 ns
    always #4.000 rx_clk = ~rx_clk;
    initial begin #2.7; forever #3.996 clk = ~clk; end

    reg rx_dv = 0;
    reg [7:0] rx_d = 0;
    wire out_dv;
    wire [7:0] out_d;

    gmii_rx_cdc u (
        .rx_clk(rx_clk), .rx_rst_n(rx_rst_n), .rx_dv(rx_dv), .rx_d(rx_d),
        .clk(clk), .rst_n(rst_n), .out_dv(out_dv), .out_d(out_d)
    );

    // 输入队列（帧字节顺序）
    reg [7:0] q [0:4095];
    integer wq = 0, rq = 0;
    integer errors = 0;
    integer falls = 0;
    integer burst = 0;
    integer bursts [0:7];
    reg out_dv_d = 0;

    always @(posedge clk) begin
        if (rst_n) begin
            out_dv_d <= out_dv;
            if (out_dv_d && !out_dv) begin
                falls = falls + 1;
                if (falls < 8) bursts[falls] = burst;
                $display("NOTE out_dv fall at %0t after %0d bytes", $time, burst);
                burst = 0;
            end
            if (out_dv) begin
                burst = burst + 1;
                if (rq >= wq) begin
                    $display("FAIL output byte %02x with empty queue", out_d);
                    errors = errors + 1;
                end else if (q[rq] !== out_d) begin
                    $display("FAIL byte %0d: got %02x exp %02x", rq, out_d, q[rq]);
                    errors = errors + 1;
                end
                rq = rq + 1;
            end
        end
    end

    task send_frame;
        input integer nbytes;
        integer i;
        begin
            // 前导 7×55 + D5
            for (i = 0; i < 8; i = i + 1) begin
                @(negedge rx_clk); rx_dv = 1; rx_d = (i == 7) ? 8'hD5 : 8'h55; q[wq] = rx_d; wq = wq + 1;
            end
            for (i = 0; i < nbytes; i = i + 1) begin
                @(negedge rx_clk); rx_dv = 1; rx_d = (i * 37 + 11) & 8'hFF; q[wq] = rx_d; wq = wq + 1;
            end
            @(negedge rx_clk); rx_dv = 0; rx_d = 8'h00;
            repeat (12) @(negedge rx_clk);
        end
    endtask

    initial begin
        repeat (10) @(posedge rx_clk);
        rx_rst_n = 1; rst_n = 1;
        repeat (10) @(posedge rx_clk);
        send_frame(64);
        send_frame(300);
        // 等读侧排空
        repeat (200) @(posedge clk);
        if (wq != rq) begin
            $display("FAIL lost bytes: wrote %0d read %0d", wq, rq);
            errors = errors + 1;
        end
        // 两帧应恰好是两个连续 burst：72 与 308 字节；中间任何提前的 dv 下降都会在这里红。
        if (falls != 2 || bursts[1] != 72 || bursts[2] != 308) begin
            $display("FAIL frame gaps wrong falls=%0d bursts=%0d,%0d,%0d", falls,
                     bursts[1], bursts[2], bursts[3]);
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS tb_gmii_rx_cdc bytes=%0d falls=%0d", rq, falls);
        else             $display("FAIL tb_gmii_rx_cdc errors=%0d", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL tb_gmii_rx_cdc timeout wq=%0d rq=%0d", wq, rq);
        $finish;
    end
endmodule
