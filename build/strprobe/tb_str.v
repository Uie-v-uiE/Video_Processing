`timescale 1ns/1ps
module tb_str;
    reg [8*96-1:0] held;
    reg cond;
    task line_t(input [8*96-1:0] tag, input ok);
        begin $display("F2 task-arg  %0s ok=%0d", tag, ok); end
    endtask
    initial begin
        cond = 1;
        held = "F3 reg-held 甲乙 ASCII 丙丁 256";
        $display("F1 direct   甲乙 ASCII 丙丁 256");
        line_t("F2 task-arg 甲乙 ASCII 丙丁 256", 1);
        $display("%0s", held);
        $display("F4 ternary  %0s", cond ? "是" : "否");
        line_t("F5 longlonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglong 截断测试 tail", 1);
        $display("F6 ascii-only via task arg test");
        line_t("F7 ascii only 256", 0);
        $finish;
    end
endmodule
