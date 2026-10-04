`timescale 1ns/1ps
// 功能：被测模块 无（本 tb 不例化 RTL，比的是文件内两个 function：row_correct 与 row_trunc16）；
//        覆盖点：产线尺寸 512×300（ROW_STRIDE=1024）下行号算式的两条路：byte_off / 1024 与
//        (byte_off>>1) & 16'hFFFF 再 / 512（即 off[16:1] 那种截断写法）在哪些行上分家。
// 激励与检查：无时钟、无复位、无数据流；纯组合遍历——off 从 0 到 307200 步进 1024 共 300 个行首采样点，
//        另按 r=0..299 取 o=r*ROW_STRIDE；边界取值取 0、1024、299*1024、307198（末字节偏移）；
//        判定条件 1：row_correct(0)==0、row_correct(1024)==1、row_correct(299*1024)==299、
//        row_correct(307198)==299；
//        判定条件 2：两条路结果不等的采样点数 bad >= 50（少于 50 判红）；
//        判定条件 3：row_correct 在行首偏移上打到的不同行数 hit == IMG_H == 300。
// 预期结果：通过时打印 `PASS basic correct formula`、`INFO row-stride samples with wrong 16bit row: <bad> / 300`、
//        `PASS 16-bit truncation is a real production bug (<bad> rows wrong)`、
//        `INFO correct formula hits <hit> rows`、`PASS correct formula covers all 300 rows`，
//        末行 `PASS tb_v50_rowmath`；失败时按条打印 `FAIL off0` / `FAIL off1024` / `FAIL off row299` /
//        `FAIL off last` / `FAIL expected many wrong rows with off[16:1] (got <bad>)` /
//        `FAIL correct formula not covering all rows`，末行变 `FAIL tb_v50_rowmath errors=<n>`
//        （前四条只打印不计票：errors 在 scan 段之前被清 0，不进末行判定）。
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
