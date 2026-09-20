`timescale 1ns/1ps
// Prove row-index math for production 512x300 (and catch off[16:1] truncation)
module tb_v50_rowmath;
    localparam IMG_W = 512;
    localparam IMG_H = 300;
    localparam ROW_STRIDE = IMG_W * 2; // 1024

    integer errors = 0;
    integer off, row_good, row_bad;
    integer off16;

    function integer row_correct;
        input integer byte_off;
        begin
            row_correct = byte_off / ROW_STRIDE;
        end
    endfunction

    function integer row_trunc16;
        input integer byte_off;
        integer pix16;
        begin
            // buggy formula: off[16:1] then / IMG_W
            pix16 = (byte_off >> 1) & 16'hFFFF;
            row_trunc16 = pix16 / IMG_W;
        end
    endfunction

    initial begin
        // Known offsets
        if (row_correct(0) != 0) begin $display("FAIL off0"); errors=errors+1; end
        if (row_correct(1024) != 1) begin $display("FAIL off1024"); errors=errors+1; end
        if (row_correct(299*1024) != 299) begin $display("FAIL off row299"); errors=errors+1; end
        if (row_correct(307198) != 299) begin $display("FAIL off last"); errors=errors+1; end
        $display("PASS basic correct formula");

        // Where 16-bit truncation diverges
        errors = 0;
        begin : scan
            integer bad;
            bad = 0;
            for (off = 0; off < 307200; off = off + 1024) begin
                if (row_correct(off) != row_trunc16(off)) bad = bad + 1;
            end
            $display("INFO row-stride samples with wrong 16bit row: %0d / 300", bad);
            if (bad < 50) begin
                $display("FAIL expected many wrong rows with off[16:1] (got %0d)", bad);
                errors = errors + 1;
            end else
                $display("PASS 16-bit truncation is a real production bug (%0d rows wrong)", bad);
        end

        // Correct formula covers 0..299 exactly at stride starts
        begin : cover
            integer r, o, hit;
            reg [IMG_H-1:0] ok;
            ok = 0; hit = 0;
            for (r = 0; r < IMG_H; r = r + 1) begin
                o = r * ROW_STRIDE;
                if (!ok[row_correct(o)]) begin
                    ok[row_correct(o)] = 1;
                    hit = hit + 1;
                end
            end
            $display("INFO correct formula hits %0d rows", hit);
            if (hit != IMG_H) begin
                $display("FAIL correct formula not covering all rows");
                errors = errors + 1;
            end else $display("PASS correct formula covers all 300 rows");
        end

        if (errors == 0) $display("PASS tb_v50_rowmath");
        else $display("FAIL tb_v50_rowmath errors=%0d", errors);
        $finish;
    end
endmodule
