`timescale 1ns/1ps
// v5.0-fix: frame_done only after all source rows written
module tb_v50_rows;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    reg p_valid=0, p_sof=0, p_eof=0, p_good=1;
    reg [7:0] p_data=0;
    wire wr_en, flush, frame_done, frame_err;
    wire [18:0] wr_addr; wire [15:0] wr_data;
    wire [31:0] s0,s1,s2,s3,s4;

    frame_reasm #(.IMG_W(8), .IMG_H(4), .FRAME_BYTES(64)) u (
        .clk(clk), .rst_n(rst_n),
        .p_data(p_data), .p_valid(p_valid), .p_sof(p_sof), .p_eof(p_eof), .p_good(p_good),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .flush(flush),
        .frame_done(frame_done), .frame_err(frame_err),
        .stat_frames(s0), .stat_pkts(s1), .stat_bytes(s2), .stat_bad(s3), .stat_oob_off(s4)
    );

    integer errors=0;
    integer done_cnt=0;
    always @(posedge clk) if (frame_done) done_cnt=done_cnt+1;

    task send_pix;
        input [31:0] byte_off;
        input [15:0] pix;
        begin
            // not used
        end
    endtask

    task send_packet;
        input [31:0] off0;
        input integer npix; // pixels from off0
        integer i;
        reg [31:0] off;
        begin
            off = off0;
            @(posedge clk); p_sof<=1; p_valid<=1; p_data<=off[7:0];
            @(posedge clk); p_sof<=0; p_data<=off[15:8];
            @(posedge clk); p_data<=off[23:16];
            @(posedge clk); p_data<=off[31:24];
            for (i=0;i<npix;i=i+1) begin
                @(posedge clk); p_data<=off[7:0]; // pix lo (dummy)
                @(posedge clk); p_data<=off[15:8]; // pix hi
                off = off + 2;
            end
            @(posedge clk); p_valid<=0; p_eof<=1;
            @(posedge clk); p_eof<=0;
        end
    endtask

    initial begin
        rst_n=0; repeat(20) @(posedge clk); rst_n=1;
        // Frame with only rows 0 and 1 (offsets 0-31 for 8px rows*2bytes*2rows=32)
        // IMG_W=8, row bytes=16. Partial: 2 rows only
        send_packet(32'd0, 8);  // row 0
        send_packet(32'd16, 8); // row 1
        repeat (20) @(posedge clk);
        if (done_cnt != 0) begin
            $display("FAIL frame_done on incomplete rows (%0d)", done_cnt);
            errors=errors+1;
        end else $display("PASS no commit on 2/4 rows");

        // Full frame: offsets covering 4 rows, 16 bytes each = 64
        send_packet(32'd0, 8);
        send_packet(32'd16, 8);
        send_packet(32'd32, 8);
        send_packet(32'd48, 8);
        repeat (30) @(posedge clk);
        if (done_cnt < 1) begin
            $display("FAIL no frame_done after all rows");
            errors=errors+1;
        end else $display("PASS commit after all rows done_cnt=%0d", done_cnt);

        if (errors==0) $display("PASS tb_v50_rows");
        else $display("FAIL tb_v50_rows errors=%0d", errors);
        $finish;
    end
endmodule
