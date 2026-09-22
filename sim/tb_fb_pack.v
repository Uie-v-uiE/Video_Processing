`timescale 1ns/1ps
// tb_fb_pack —— 判"打包后的每个 64bit 字的内容与字地址都对"。
//
// 黄金模型故意写成**另一种形式**：按车道号下标取（img[w*4+k]），不复刻 DUT 的 case 语句。
// 两点台架卫生（都是这轮踩出来的，别再踩）：
//   · 判据前必须 settle 两拍：wr_en 是寄存器输出，某个像素触发的写要在**下一个**沿才被计分
//     always 看到；不留拍数就会把"每段最后一个字"读成 X。
//   · 标签一律 ASCII：中文在 Windows 控制台的 xsim 输出里会糊成 ?，排查时读不出来。
module tb_fb_pack;
    reg clk = 0, rst_n = 0;
    reg        px_en = 0;
    reg [18:0] px_addr = 0;
    reg [15:0] px_data = 0;
    reg        flush = 0;
    wire       wr_en;
    wire [18:0] wr_addr;
    wire [63:0] wr_data;

    fb_pack u_dut (.clk(clk), .rst_n(rst_n), .px_en(px_en), .px_addr(px_addr),
                   .px_data(px_data), .flush(flush),
                   .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data));

    always #5 clk = ~clk;

    integer errors = 0, nrec = 0, i = 0, w = 0, wbad = 0;
    reg [18:0] rec_addr [0:63];
    reg [63:0] rec_data [0:63];
    reg [15:0] img [0:255];

    always @(posedge clk) if (wr_en) begin
        if (nrec < 64) begin rec_addr[nrec] = wr_addr; rec_data[nrec] = wr_data; end
        nrec = nrec + 1;
    end

    task settle; begin @(posedge clk); @(posedge clk); end endtask

    task chk;
        input [8*46:1] named;
        input ok;
        begin
            $display("[CHK] %-46s : %s", named, ok ? "OK" : "BAD");
            if (!ok) begin
                errors = errors + 1;
                $display("[DIAG] nrec=%0d total_bad=%0d", nrec, errors);
            end
        end
    endtask

    task put;
        input [18:0] a;
        input [15:0] d;
        begin
            @(posedge clk); #1;
            px_en = 1'b1; px_addr = a; px_data = d;
            if (a < 256) img[a] = d;
            @(posedge clk); #1;
            px_en = 1'b0;
        end
    endtask

    task do_flush;
        begin
            @(posedge clk); #1; flush = 1'b1;
            @(posedge clk); #1; flush = 1'b0;
            settle;
        end
    endtask

    task clear_watch; begin nrec = 0; end endtask

    initial begin
        for (i = 0; i < 256; i = i + 1) img[i] = 16'h0000;
        for (i = 0; i < 64; i = i + 1) begin rec_addr[i] = 19'hx; rec_data[i] = 64'hx; end
        @(posedge clk); rst_n = 1; @(posedge clk);

        // ---- 连续 16 像素 ⇒ 4 个整字 ----
        clear_watch;
        for (i = 0; i < 16; i = i + 1) put(i[18:0], 16'h1000 + i[15:0]);
        settle;
        chk("c01 16 pixels -> 4 word writes", nrec == 4);
        wbad = 0;
        for (w = 0; w < 4; w = w + 1) begin
            if (rec_addr[w] !== w[18:0] ||
                rec_data[w] !== {img[w*4+3], img[w*4+2], img[w*4+1], img[w*4]}) begin
                $display("[DIAG] word %0d addr=%h data=%h exp=%h", w, rec_addr[w], rec_data[w],
                         {img[w*4+3], img[w*4+2], img[w*4+1], img[w*4]});
                wbad = wbad + 1;
            end
        end
        settle;
        chk("c02 lane order is {p3,p2,p1,p0}", wbad == 0);

        // ---- 末尾不满一格，靠 flush 逼出 ----
        clear_watch;
        for (i = 0; i < 4; i = i + 1) put(32 + i[18:0], 16'h2000 + i[15:0]);
        for (i = 0; i < 3; i = i + 1) put(36 + i[18:0], 16'h3000 + i[15:0]);
        do_flush;
        settle;
        chk("c03 4+3 pixels -> 2 word writes", nrec == 2);
        settle;
        chk("c04 tail word lanes 0..2 set, lane 3 zero",
            rec_addr[1] === 19'd9 && rec_data[1] === {16'h0000, img[38], img[37], img[36]});

        // ---- 起头不在车道 0（50..55 只跨字 12、13）----
        clear_watch;
        for (i = 0; i < 6; i = i + 1) put(50 + i[18:0], 16'h4000 + i[15:0]);
        do_flush;
        settle;
        chk("c05 unaligned start -> 2 word writes", nrec == 2);
        settle;
        chk("c06 first word holds only lanes 2,3",
            rec_addr[0] === 19'd12 && rec_data[0] === {img[51], img[50], 16'h0000, 16'h0000});
        settle;
        chk("c07 second word is full",
            rec_addr[1] === 19'd13 && rec_data[1] === {img[55], img[54], img[53], img[52]});

        // ---- 车道 3 先到：流式打包器立刻发出只含车道 3 的字 ----
        // 真实入包不会这样（同字 4 像素来自同一行连续 4 列，拼帧输出里必递增）；
        // 这条是把"不猜、不无限等"的行为钉住，而不是许一个做不到的愿。
        clear_watch;
        put(67, 16'hD003); put(66, 16'hD002); put(64, 16'hD000); put(65, 16'hD001);
        do_flush;
        settle;
        chk("c08 lane3-first emits at once, no stale lanes",
            nrec == 2 && rec_addr[0] === 19'd16 && rec_data[0] === {16'hD003, 48'h0});
        settle;
        chk("c09 other 3 lanes go out on flush",
            rec_addr[1] === 19'd16 && rec_data[1] === {16'h0000, 16'hD002, 16'hD001, 16'hD000});

        // ---- 空 flush 不产生写 ----
        clear_watch;
        do_flush; do_flush;
        settle;
        chk("c10 flush with nothing pending writes nothing", nrec == 0);

        // ---- 跨字跳变（丢包场景）：旧字必须先落盘，不能被吞 ----
        clear_watch;
        put(80, 16'hE000); put(81, 16'hE001);
        put(88, 16'hF000);
        do_flush;
        settle;
        chk("c11 word switch flushes the old partial word",
            nrec == 2 && rec_addr[0] === 19'd20 &&
            rec_data[0] === {16'h0000, 16'h0000, 16'hE001, 16'hE000});
        settle;
        chk("c12 the jumped-to word is not lost",
            rec_addr[1] === 19'd22 && rec_data[1] === {48'h0, 16'hF000});

        $display("");
        if (errors == 0) $display("RESULT tb_fb_pack PASS");
        else             $display("RESULT tb_fb_pack FAIL (%0d checks bad)", errors);
        $finish;
    end

    initial begin
        #500_000;
        $display("RESULT tb_fb_pack FAIL timeout");
        $finish;
    end
endmodule
