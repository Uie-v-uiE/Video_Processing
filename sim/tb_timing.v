`timescale 1ns/1ps
module tb_timing;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk; // 100MHz for fast sim

    wire [11:0] x, y;
    wire hs, vs, de, fs, fd;

    video_timing #(
        .H_ACTIVE(16), .V_ACTIVE(8),
        .H_FP(2), .H_SYNC(4), .H_BP(2),
        .V_FP(1), .V_SYNC(2), .V_BP(1)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .x(x), .y(y), .hs(hs), .vs(vs), .de(de),
        .frame_start(fs), .frame_done(fd)
    );

    integer de_cnt = 0;
    integer errors = 0;
    integer frames = 0;
    reg count_en = 0;

    always @(posedge clk) begin
        if (count_en && de) de_cnt = de_cnt + 1;
        if (count_en && fd) frames = frames + 1;
    end

    // H_TOTAL=24, V_TOTAL=12, frame=288 cycles
    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;
        // wait until first frame_done then count next full frame
        @(posedge clk);
        while (!fd) @(posedge clk);
        @(posedge clk);
        de_cnt = 0;
        frames = 0;
        count_en = 1;
        while (frames < 1) @(posedge clk);
        count_en = 0;
        if (de_cnt < 127 || de_cnt > 128) begin
            $display("FAIL de_cnt=%0d expected ~128", de_cnt);
            errors = errors + 1;
        end
        if (errors == 0)
            $display("PASS tb_timing");
        else
            $display("FAIL tb_timing");
        $finish;
    end
endmodule
