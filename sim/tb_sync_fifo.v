`timescale 1ns/1ps
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
