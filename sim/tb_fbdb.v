`timescale 1ns/1ps
// frame_buffer_db: write back, swap at vsync, read front
module tb_fbdb;
    reg wr_clk=0, rd_clk=0, rst_n=0;
    always #5 wr_clk=~wr_clk;
    always #7 rd_clk=~rd_clk; // different rate

    reg wr_en=0, wr_done=0;
    reg [18:0] wr_addr=0;
    reg [15:0] wr_data=0;
    reg rd_vsync=0;
    reg [18:0] rd_addr=0;
    wire [15:0] rd_data;

    frame_buffer_db #(.W(8), .H(4)) uut (
        .wr_clk(wr_clk), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .wr_frame_done(wr_done),
        .rd_clk(rd_clk), .rd_vsync(rd_vsync),
        .rd_addr(rd_addr), .rd_data(rd_data)
    );

    integer i, errors=0;
    reg [15:0] got;

    task write_frame(input [15:0] base);
        integer p;
        begin
            for (p=0;p<32;p=p+1) begin
                @(posedge wr_clk);
                wr_en<=1; wr_addr<=p[18:0]; wr_data<=base+p[15:0];
            end
            @(posedge wr_clk);
            wr_en<=0;
            @(posedge wr_clk);
            wr_done<=1;
            @(posedge wr_clk);
            wr_done<=0;
        end
    endtask

    task read_pix(input [18:0] a, output [15:0] d);
        begin
            @(posedge rd_clk);
            rd_addr<=a;
            @(posedge rd_clk);
            @(posedge rd_clk); // 1-cycle BRAM + 1
            d = rd_data;
        end
    endtask

    task pulse_vsync;
        begin
            @(posedge rd_clk);
            rd_vsync<=1;
            repeat(3) @(posedge rd_clk);
            rd_vsync<=0;
            repeat(3) @(posedge rd_clk);
        end
    endtask

    initial begin
        repeat(5) @(posedge wr_clk);
        rst_n=1;
        repeat(5) @(posedge wr_clk);

        // Frame 1 to back (buf0, wr_sel=0)
        write_frame(16'h1100);
        // No vsync yet — display still empty (reads buf1)
        read_pix(19'd0, got);
        // may be X/0
        pulse_vsync;
        read_pix(19'd0, got);
        if (got !== 16'h1100) begin
            $display("FAIL after frame1+vysnc got=%h exp 1100", got);
            errors=errors+1;
        end else $display("PASS frame1 visible");
        read_pix(19'd5, got);
        if (got !== 16'h1105) begin
            $display("FAIL pix5 got=%h exp 1105", got);
            errors=errors+1;
        end

        // Frame 2 to other bank while display still shows frame1
        write_frame(16'h2200);
        // During write, front should still be frame1
        read_pix(19'd0, got);
        if (got !== 16'h1100) begin
            $display("FAIL mid-write2 got=%h exp 1100 (ghost!)", got);
            errors=errors+1;
        end else $display("PASS no ghost during write2");

        pulse_vsync;
        read_pix(19'd0, got);
        if (got !== 16'h2200) begin
            $display("FAIL after frame2 got=%h exp 2200", got);
            errors=errors+1;
        end else $display("PASS frame2 visible");

        if (errors==0) $display("PASS tb_fbdb ALL");
        else $display("FAIL tb_fbdb errors=%0d", errors);
        $finish;
    end
endmodule
