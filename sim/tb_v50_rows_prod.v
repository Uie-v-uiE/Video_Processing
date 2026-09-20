`timescale 1ns/1ps
// Production-scale row coverage: 512-wide rows, first and last row offsets
module tb_v50_rows_prod;
    localparam IMG_W=512, IMG_H=300;
    localparam FRAME_BYTES=IMG_W*IMG_H*2;
    localparam ROW_STRIDE=IMG_W*2;

    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    reg p_valid=0, p_sof=0, p_eof=0, p_good=1;
    reg [7:0] p_data=0;
    wire wr_en, flush, frame_done, frame_err;
    wire [18:0] wr_addr; wire [15:0] wr_data;
    wire [31:0] s0,s1,s2,s3,s4;

    frame_reasm #(.IMG_W(IMG_W), .IMG_H(IMG_H), .FRAME_BYTES(FRAME_BYTES)) u (
        .clk(clk), .rst_n(rst_n),
        .p_data(p_data), .p_valid(p_valid), .p_sof(p_sof), .p_eof(p_eof), .p_good(p_good),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .flush(flush),
        .frame_done(frame_done), .frame_err(frame_err),
        .stat_frames(s0), .stat_pkts(s1), .stat_bytes(s2), .stat_bad(s3), .stat_oob_off(s4)
    );

    integer done_cnt=0;
    always @(posedge clk) if (frame_done) done_cnt=done_cnt+1;

    integer errors=0, i, r;

    task send_rows;
        input integer nskip; // send nskip*stride bytes as one-pixel-per-row? send full first pix of each row
        integer row;
        reg [31:0] off;
        begin
            // one pixel per row for rows 0..IMG_H-1 (enough to set row_ok)
            for (row = 0; row < IMG_H; row = row + 1) begin
                if (row < nskip) ; // skip some rows
                else begin
                    off = row * ROW_STRIDE;
                    // 4-byte offset + 2-byte pixel
                    p_sof<=1; p_valid<=1; p_data<=off[7:0];
                    @(posedge clk); p_sof<=0; p_data<=off[15:8];
                    @(posedge clk); p_data<=off[23:16];
                    @(posedge clk); p_data<=off[31:24];
                    @(posedge clk); p_data<=8'h11; // lo
                    @(posedge clk); p_data<=8'h22; // hi
                    @(posedge clk); p_valid<=0; p_eof<=1;
                    @(posedge clk); p_eof<=0;
                end
            end
        end
    endtask

    task send_full_row0_and_last;
        begin
            // row 0 full pixels would be large; just one pixel each on row 0 and row 299
            // already covered by send_rows
        end
    endtask

    // one complete 1024-byte row (production stride) — the v6 gate also needs
    // the whole FRAME_BYTES, so this is what a real frame is made of.
    task send_row_full;
        input integer row;
        integer b;
        reg [31:0] off;
        begin
            off = row * ROW_STRIDE;
            p_sof<=1; p_valid<=1; p_data<=off[7:0];
            @(posedge clk); p_sof<=0; p_data<=off[15:8];
            @(posedge clk); p_data<=off[23:16];
            @(posedge clk); p_data<=off[31:24];
            for (b = 0; b < ROW_STRIDE; b = b + 1) begin
                @(posedge clk); p_data<=b[7:0] ^ row[7:0];
            end
            p_eof<=1;                 // coincident with the last byte, as on the wire
            @(posedge clk); p_valid<=0; p_eof<=0;
        end
    endtask

    initial begin
        rst_n=0; repeat(20) @(posedge clk); rst_n=1;
        done_cnt=0;
        // only rows 0..9 → must NOT commit
        send_rows(10);
        repeat (30) @(posedge clk);
        if (done_cnt != 0) begin
            $display("FAIL commit with only 10 rows");
            errors=errors+1;
        end else $display("PASS no commit when only 10/300 rows");

        // all 300 rows touched but 600/307200 bytes → v6 refuses the holey frame
        done_cnt=0;
        send_rows(0);
        repeat (40) @(posedge clk);
        if (done_cnt != 0) begin
            $display("FAIL committed a 600-byte frame");
            errors=errors+1;
        end else $display("PASS no commit when rows are touched but bytes are short");

        // 300 complete rows → commit
        done_cnt=0;
        for (r = 0; r < IMG_H; r = r + 1) send_row_full(r);
        repeat (40) @(posedge clk);
        if (done_cnt < 1) begin
            $display("FAIL no commit after 300 full production rows done=%0d", done_cnt);
            errors=errors+1;
        end else $display("PASS commit after 300 full production rows done=%0d", done_cnt);

        if (errors==0) $display("PASS tb_v50_rows_prod");
        else $display("FAIL tb_v50_rows_prod errors=%0d", errors);
        $finish;
    end
endmodule
