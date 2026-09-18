`timescale 1ns/1ps
// CRC32 functional checks (not a named-vector test — algorithm is Ethernet reflected).
module tb_crc32;
    reg clk=0, rst_n=0;
    always #4 clk=~clk;
    reg [7:0] data=0;
    reg crc_en=0, crc_clr=0;
    wire [31:0] crc_data, crc_next;
    integer i, errors=0;
    reg [31:0] v1, v2;

    crc32_d8 uut (.clk(clk), .rst_n(rst_n), .data(data), .crc_en(crc_en),
                  .crc_clr(crc_clr), .crc_data(crc_data), .crc_next(crc_next));

    task feed(input [7:0] b);
        begin
            @(posedge clk);
            data<=b; crc_en<=1;
            @(posedge clk);
            crc_en<=0;
            #1;
        end
    endtask

    initial begin
        repeat(3) @(posedge clk);
        rst_n=1;
        @(posedge clk); #1;
        if (crc_data !== 32'hFFFF_FFFF) begin
            $display("FAIL init %h", crc_data); errors=errors+1;
        end else $display("PASS init");

        feed(8'h00);
        v1 = crc_data;
        feed(8'hFF);
        v2 = crc_data;
        if (v1 === v2) begin
            $display("FAIL crc did not change"); errors=errors+1;
        end else $display("PASS crc updates");

        @(posedge clk); crc_clr<=1;
        @(posedge clk); crc_clr<=0; #1;
        if (crc_data !== 32'hFFFF_FFFF) begin
            $display("FAIL clr %h", crc_data); errors=errors+1;
        end else $display("PASS clr");

        // Determinism: same sequence twice → same result
        feed(8'h55); feed(8'hAA); feed(8'h01);
        v1 = crc_data;
        @(posedge clk); crc_clr<=1;
        @(posedge clk); crc_clr<=0;
        feed(8'h55); feed(8'hAA); feed(8'h01);
        v2 = crc_data;
        if (v1 !== v2) begin
            $display("FAIL determinism %h vs %h", v1, v2); errors=errors+1;
        end else $display("PASS determinism");

        if (errors==0) $display("PASS tb_crc32 ALL");
        else $display("FAIL tb_crc32 errors=%0d", errors);
        $finish;
    end
endmodule
