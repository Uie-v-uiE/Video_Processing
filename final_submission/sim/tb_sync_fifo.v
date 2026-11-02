`timescale 1ns/1ps
// 功能：被测模块 `sync_fifo`（例化 `uut`，参数 .DATA_W(8) / .ADDR_W(4)）；覆盖点：8 位宽、
// 16 格深同步 FIFO 的 level/empty 旗标与"先连写后连读"两条路径上的数据一一对应。
// 激励与检查：#4 翻转时钟（周期 8 ns）；rst_n 上电为 0，repeat(3) @(posedge clk) 后放成 1；
// 复位放开一拍后读 empty，再连写 10 拍（wr_data<=i+8'hA0，即 0xA0..0xA9）、停写空等 2 拍读
// level；随后逐字节读 10 次（每次 rd_en 只举一拍，#1 后采样 rd_data），读完再空等 2 拍。
// 判定条件：复位后 !empty；写完 10 个后 level 必须 ==10（打印 exp10）；第 i 次读回必须满足
// rd_data === i[7:0]+8'hA0（!== 即计一次错）；收尾 empty 必须回到 1。
// 预期结果：通过时逐段打印 `PASS level`、`PASS empty end`，errors==0 时打印
// `PASS tb_sync_fifo ALL`；失败时对应判据红在 `FAIL not empty after rst` /
// `FAIL level=%0d exp10` / `FAIL data[%0d]=%h exp %h` / `FAIL not empty at end`，
// 收尾打印 `FAIL tb_sync_fifo errors=%0d`。
module tb_sync_fifo;
    reg clk=0, rst_n=0;
    always #4 clk=~clk;
    reg wr_en=0, rd_en=0;
    reg [7:0] wr_data=0;
    wire [7:0] rd_data;
    wire full, empty;
    wire [4:0] level;
    integer i, errors=0;

    sync_fifo #(.DATA_W(8), .ADDR_W(4)) uut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_data(wr_data), .full(full),
        .rd_en(rd_en), .rd_data(rd_data), .empty(empty), .level(level)
    );

    initial begin
        repeat(3) @(posedge clk);
        rst_n=1;
        @(posedge clk); #1;
        if (!empty) begin $display("FAIL not empty after rst"); errors=errors+1; end
        for (i=0;i<10;i=i+1) begin
            @(posedge clk);
            wr_en<=1; wr_data<=i[7:0]+8'hA0;
        end
        @(posedge clk);
        wr_en<=0;
        repeat(2) @(posedge clk);
        #1;
        if (level!=10) begin $display("FAIL level=%0d exp10", level); errors=errors+1; end
        else $display("PASS level");
        for (i=0;i<10;i=i+1) begin
            @(posedge clk);
            rd_en<=1;
            @(posedge clk);
            rd_en<=0;
            #1;
            if (rd_data !== (i[7:0]+8'hA0)) begin
                $display("FAIL data[%0d]=%h exp %h", i, rd_data, i[7:0]+8'hA0);
                errors=errors+1;
            end
        end
        repeat(2) @(posedge clk); #1;
        if (!empty) begin $display("FAIL not empty at end"); errors=errors+1; end
        else $display("PASS empty end");
        if (errors==0) $display("PASS tb_sync_fifo ALL");
        else $display("FAIL tb_sync_fifo errors=%0d", errors);
        $finish;
    end
endmodule
