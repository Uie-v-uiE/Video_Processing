`timescale 1ns/1ps
// zoom_mapper + zoom_ctrl：原本=最大，向缩小循环
module tb_zoom_mapper;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg        enable = 1;
    reg        frame_start = 0;
    wire [9:0] inv_scale;
    wire       zoom_active, dir;

    zoom_ctrl #(.INV_LO(10'd256), .INV_HI(10'd512), .STEP(10'd8)) u_ctrl (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .frame_start(frame_start),
        .inv_scale(inv_scale), .zoom_active(zoom_active), .dir(dir)
    );

    reg  [11:0] x_in = 0, y_in = 0;
    reg  [9:0]  inv_force = 10'd256;
    reg         rot_en = 1'b0;
    reg  [8:0]  angle = 9'd0;
    wire [11:0] xo, yo;
    wire        oobo;
    wire [7:0]  fx, fy;

    zoom_mapper #(.IMAGE_W(512), .IMAGE_H(300)) u_map (
        .clk(clk), .rst_n(rst_n),
        .inv_scale(inv_force), .angle(angle), .rotate_en(rot_en),
        .x_in(x_in), .y_in(y_in),
        .x_out(xo), .y_out(yo), .oob(oobo),
        .frac_x(fx), .frac_y(fy)
    );

    integer errors = 0;
    integer i;

    task stepN;
        input integer n;
        integer j;
        begin
            for (j = 0; j < n; j = j + 1) @(posedge clk);
        end
    endtask

    task expect_xy;
        input [11:0] ex, ey;
        input        exp_oob;
        input [255:0] tag;
        begin
            if (oobo !== exp_oob || (!exp_oob && (xo !== ex || yo !== ey))) begin
                $display("FAIL %0s got (%0d,%0d) oob=%b expect (%0d,%0d) oob=%b",
                         tag, xo, yo, oobo, ex, ey, exp_oob);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // inv=256 identity (original size)
        inv_force = 10'd256; rot_en = 0; angle = 0;
        x_in = 0; y_in = 0; stepN(4); expect_xy(12'd0, 12'd0, 1'b0, "id(0,0)");
        x_in = 100; y_in = 50; stepN(4); expect_xy(12'd100, 12'd50, 1'b0, "id(100,50)");

        // inv=512 → 0.5x zoom-out
        // sx = 256 + (x-256)*512/256 = 256 + (x-256)*2
        // center stays; edges OOB
        inv_force = 10'd512;
        x_in = 256; y_in = 150; stepN(4); expect_xy(12'd256, 12'd150, 1'b0, "0.5x center");
        x_in = 0; y_in = 0; stepN(4); expect_xy(12'd0, 12'd0, 1'b1, "0.5x(0,0) OOB");
        // sx=256+(128-256)*2=0 → in range; sy=150+(75-150)*2=0
        x_in = 128; y_in = 75; stepN(4); expect_xy(12'd0, 12'd0, 1'b0, "0.5x(128,75)");
        // sx=256+(384-256)*2=512 → OOB (>=512)
        x_in = 384; y_in = 225; stepN(4); expect_xy(12'd0, 12'd0, 1'b1, "0.5x(384,225) OOB");

        // rotate 0 + inv 256 identity
        inv_force = 10'd256; rot_en = 1; angle = 0;
        x_in = 200; y_in = 100; stepN(4); expect_xy(12'd200, 12'd100, 1'b0, "rot0 id");

        // zoom_ctrl: start 256, STEP=8 toward 512
        if (inv_scale !== 10'd256) begin
            $display("FAIL ctrl reset inv=%0d", inv_scale);
            errors = errors + 1;
        end
        // (512-256)/8=32 frames to hit INV_HI
        for (i = 0; i < 20; i = i + 1) begin
            frame_start = 1; @(posedge clk); frame_start = 0; @(posedge clk);
        end
        // 256+20*8=416
        if (inv_scale !== 10'd416) begin
            $display("FAIL ctrl after 20 frames inv=%0d expect 416", inv_scale);
            errors = errors + 1;
        end
        for (i = 0; i < 40; i = i + 1) begin
            frame_start = 1; @(posedge clk); frame_start = 0; @(posedge clk);
        end
        // hit 512 then bounce down; expect still in [256,512]
        if (inv_scale < 10'd256 || inv_scale > 10'd512) begin
            $display("FAIL ctrl range inv=%0d", inv_scale);
            errors = errors + 1;
        end
        enable = 0;
        frame_start = 1; @(posedge clk); frame_start = 0; @(posedge clk);
        if (inv_scale !== 10'd256 || zoom_active !== 1'b0) begin
            $display("FAIL ctrl disable inv=%0d act=%b", inv_scale, zoom_active);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS tb_zoom_mapper");
        else             $display("FAIL tb_zoom_mapper errors=%0d", errors);
        $finish;
    end
endmodule
