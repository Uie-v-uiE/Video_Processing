`timescale 1ns/1ps
// Window filter + rotation combo: ensure blur is not forced-off when angle!=0.
// Checks that proc_pipeline applies blur when enabled regardless of rotate_active.
module tb_rotate_window;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg [4:0] en = 5'b00100; // blur only
    reg rot = 0;
    reg de = 0;
    reg [11:0] x = 0, y = 0;
    reg [15:0] din = 0;
    wire de_o;
    wire [15:0] dout;

    // Use a tiny H_ACTIVE
    // V8-2 起 proc_pipeline 吃的是**九位算法字**（每一位一个算法）。台架仍然用"老五位"表达
    // 意图（这条测试问的是"转不转都该模糊"，与位序无关），映射在这里做一遍 ——
    // 故意不引用 effect_ctrl 里的那张表：两处独立写同一个映射，改一边忘了另一边就会红。
    //   sel: [0]gray [1]invert [2]blur [3]sharp [4]sobel [5]binary [6]pol [7]erode [8]dilate
    //   老:       en[0]  en[4]   en[2]          en[3]   en[1]
    wire [8:0] sel = {3'b000, en[1], en[3], 1'b0, en[2], en[4], en[0]};

    proc_pipeline #(.H_ACTIVE(8)) uut (
        .clk(clk), .rst_n(rst_n),
        .stage_sel(sel), .threshold(8'd80),
        .rotate_active(rot),
        .hs_in(1'b0), .vs_in(1'b0),
        .de_in(de), .x_in(x), .y_in(y), .din(din),
        .de_out(de_o), .dout(dout)
    );

    integer errors = 0;
    integer i, row;
    reg [15:0] first_out;
    reg got;

    task push_pix(input [15:0] v, input [11:0] xx, input [11:0] yy);
        begin
            @(posedge clk);
            de <= 1; din <= v; x <= xx; y <= yy;
            @(posedge clk);
            de <= 0;
        end
    endtask

    initial begin
        $dumpfile("tb_rotate_window.vcd");
        $dumpvars(0, tb_rotate_window);
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;

        // angle!=0 path (rotate_active=1) but blur enabled
        rot = 1;
        en  = 5'b00100;

        // fill 3 lines of constant 0xF800 (red) — box blur of constant should stay ~same
        for (row = 0; row < 3; row = row + 1) begin
            for (i = 0; i < 8; i = i + 1)
                push_pix(16'hF800, i[11:0], row[11:0]);
        end
        // collect some outputs after pipeline latency
        got = 0;
        for (i = 0; i < 16; i = i + 1) begin
            @(posedge clk);
            if (de_o) begin
                if (!got) begin first_out = dout; got = 1; end
            end
        end

        // With blur active on constant red, center average stays near red (not identity bypass of raw-only).
        // Constant field: average = F800. If blur were bypassed by rotate, also F800.
        // So this check alone is weak — instead compare against binary+blur chain.
        // Stronger: enable blur on a step pattern and ensure dout differs from din path.

        // Step image: left half 0, right half F800
        for (row = 0; row < 3; row = row + 1) begin
            for (i = 0; i < 8; i = i + 1) begin
                if (i < 4) push_pix(16'h0000, i[11:0], row[11:0]);
                else       push_pix(16'hF800, i[11:0], row[11:0]);
            end
        end
        got = 0;
        first_out = 16'h0;
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk);
            if (de_o) begin
                if (dout !== 16'h0000 && dout !== 16'hF800) begin
                    got = 1; // intermediate blend => blur applied
                end
            end
        end

        if (!got) begin
            $display("FAIL no intermediate blur value under rotate_active=1");
            errors = errors + 1;
        end else $display("PASS blur active with rotate_active=1");

        // Also verify rotate_active=0 still blurs
        rot = 0;
        got = 0;
        for (row = 0; row < 3; row = row + 1)
            for (i = 0; i < 8; i = i + 1)
                push_pix(i<4 ? 16'h0 : 16'hF800, i[11:0], row[11:0]);
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk);
            if (de_o && dout !== 16'h0000 && dout !== 16'hF800) got = 1;
        end
        if (!got) begin
            $display("FAIL blur inactive at angle0");
            errors = errors + 1;
        end else $display("PASS blur active with rotate_active=0");

        if (errors == 0) $display("PASS tb_rotate_window ALL");
        else $display("FAIL tb_rotate_window errors=%0d", errors);
        $finish;
    end
endmodule
