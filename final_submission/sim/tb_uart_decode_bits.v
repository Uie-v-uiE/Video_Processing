`timescale 1ns/1ps
// 功能：被测模块 `tb_uart_decode_bits.try_cmd`（台架内的纯软件模型，没有 RTL 例化，
//        对照 src/ps/main.c 的 parse_bits）；覆盖点：串口命令里 5 个 "0"/"1" 字符到
//        使能位的位序约定——字符串最左那个字符落 en[0]，右移一位落 en[1]，依此类推。
// 激励与检查：无时钟、无复位，initial 里直调 4 组：try_cmd("00111", 5'b11100)、
//        try_cmd("10000", 5'b00001)、try_cmd("11111", 5'b11111)、try_cmd("00000", 5'b00000)；
//        判定条件：每次把 40 位字符串按 s[39-8*i -: 8] == "1"（i=0..4）置 en[i]，
//        en !== expect 即 errors+1，四组都必须逐位等于期望。
// 预期结果：通过时四组都不输出、只打印末行 PASS tb_uart_decode_bits；失败时每条错配打印
//        FAIL cmd <字符串> got <实测 5 位> exp <期望 5 位>，末行改打
//        FAIL tb_uart_decode_bits errors=<n>。
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
