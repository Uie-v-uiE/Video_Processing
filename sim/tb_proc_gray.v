`timescale 1ns/1ps
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
