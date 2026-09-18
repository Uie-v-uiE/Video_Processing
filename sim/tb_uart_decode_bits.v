`timescale 1ns/1ps
// Pure software model of serial bit-string parsing (same as PS parse_bits)
module tb_uart_decode_bits;
    integer errors = 0;

    function integer parse_bits;
        input [8*8-1:0] s; // not used; use byte loop in initial
        begin
            parse_bits = 0;
        end
    endfunction

    // Behavioral check of mapping "00111" -> 5'b00111 with bit0=left
    reg [4:0] en;
    integer i;
    reg [8*5-1:0] cmd;

    task try_cmd;
        input [8*5-1:0] s;
        input [4:0] expect;
        begin
            en = 5'd0;
            for (i = 0; i < 5; i = i + 1) begin
                // left char is MSB of string packing in Verilog — check char i
                // s is 40 bits, char0 at [39:32]
                if (s[39-8*i -: 8] == "1")
                    en[i] = 1'b1;
            end
            if (en !== expect) begin
                $display("FAIL cmd %s got %b exp %b", s, en, expect);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        try_cmd("00111", 5'b11100); // left=bit0; 2,3,4 on => last three effects
        try_cmd("10000", 5'b00001); // only gray
        try_cmd("11111", 5'b11111);
        try_cmd("00000", 5'b00000);
        if (errors == 0)
            $display("PASS tb_uart_decode_bits");
        else
            $display("FAIL tb_uart_decode_bits errors=%0d", errors);
        $finish;
    end
endmodule
