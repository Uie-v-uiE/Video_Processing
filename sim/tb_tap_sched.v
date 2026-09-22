`timescale 1ns/1ps
// tb_tap_sched —— 判"每个请求拿到的 4 个抽头与 fx/fy 都对，且输出节拍=输入节拍"。
//
// 独立性怎么保证（这条最重要）：期望值**不走** DUT 的字地址/车道路径，
// 而是直接用像素函数 pix(n) 算 `pix(sy*W+sx)`、`pix(...+1)`、`pix(...+W)`、`pix(...+W+1)`；
// 存储模型 mem[] 只用来喂 DUT 的读口。两边算法不同 ⇒ 有一方错就会露出来。
//
// 台架卫生（都是今晚踩过的，写在这儿免得再踩）：
//   · 驱动与检查都在 negedge：寄存型输出（vld、rd_word_addr）在 posedge 之后一整拍稳定，
//     在 posedge 同一时间步里读会与被测逻辑抢读。
//   · 判据实参在**调用点**求值，所以计数类判据前要先留 settling。
//   · 标签用 ASCII：中文在 xsim 的控制台输出里会糊成 ?。
module tb_tap_sched;
    localparam IW = 512;
    localparam SL = 5;

    reg clk = 0, rst_n = 0;
    always #2 clk = ~clk;                 // 4 ns 快时钟（对应 20 ns 像素周期 = 5 槽）

    reg         req;
    reg  [11:0] sx, sy;
    reg  [7:0]  fx, fy;
    wire        fetching, rd_en, vld;
    wire [18:0] rd_word_addr;
    reg  [63:0] rd_word;
    wire [15:0] p00, p10, p01, p11;
    wire [7:0]  ofx, ofy;

    tap_sched #(.IMG_W(IW), .SLOTS(SL)) u_dut (
        .clk(clk), .rst_n(rst_n), .req(req), .sx(sx), .sy(sy), .fx(fx), .fy(fy),
        .fetching(fetching), .rd_en(rd_en), .rd_word_addr(rd_word_addr), .rd_word(rd_word),
        .p00(p00), .p10(p10), .p01(p01), .p11(p11), .ofx(ofx), .ofy(ofy), .vld(vld));

    // ---------------- 存储模型 ----------------
    function [15:0] pix;
        input [24:0] n;                   // 与 mem 一致：只用低位，避免位宽歧义
        begin
            pix = n[15:0] ^ {n[11:0], 4'h0} ^ (n[15:0] * 16'h0403) ^ 16'h5A5A;
        end
    endfunction

    function [63:0] word_of;
        input [18:0] w;
        begin
            word_of = {pix(w*4 + 3), pix(w*4 + 2), pix(w*4 + 1), pix(w*4 + 0)};
        end
    endfunction

    // 读口：延迟 1 拍（真 BRAM 的行为）
    reg [18:0] a_d;
    reg        e_d;
    always @(posedge clk) begin
        a_d <= rd_word_addr;
        e_d <= rd_en;
        if (rd_en) rd_word <= word_of(rd_word_addr);
    end

    // ---------------- 期望队列 ----------------
    reg [63:0] e_taps [0:63];              // {p11,p01,p10,p00}
    reg [15:0] e_frs  [0:63];              // {fx,fy}
    integer   e_head = 0, e_tail = 0;

    integer errors = 0, nreq = 0, nchk = 0, i = 0, k = 0;
    reg [11:0] q_sx [0:63];
    reg [11:0] q_sy [0:63];
    reg [7:0]  q_fx [0:63];
    reg [7:0]  q_fy [0:63];

    // 覆盖 lane=0..3、跨行、边界附近
    task fill_queue;
        begin
            // 60 个请求：sx 依次取 4 种车道，sy 递增，靠近行首/行尾各来一次
            for (k = 0; k < 60; k = k + 1) begin
                q_sx[k] = 4*(k % 40) + (k % 4);
                q_sy[k] = (k % 50);
                q_fx[k] = 8'h11 * (k[7:0] % 8);
                q_fy[k] = 8'h22 * (k[7:0] % 4);
            end
            q_sx[57] = 0;   q_sy[57] = 100;            // lane 0，行首
            q_sx[58] = 508; q_sy[58] = 101;            // lane 0，接近行尾（509..511 越界由 sy 决定）
            q_sx[59] = 511; q_sy[59] = 102;            // lane 3 ⇒ 必须读下一个字
            nreq = 60;
        end
    endtask

    // 入队一个期望
    task expect_for;
        input [11:0] x;
        input [11:0] y;
        input [7:0]  fxx;
        input [7:0]  fyy;
        reg [24:0] n;
        begin
            n = y * IW + x;
            e_taps[e_tail] = {pix(n + IW + 1), pix(n + IW), pix(n + 1), pix(n)};
            e_frs [e_tail] = {fxx, fyy};
            e_tail = e_tail + 1;
        end
    endtask

    // 请求驱动：只在 fetching 的中点给出，下一个 posedge 被采样
    always @(negedge clk) begin
        if (!rst_n) begin
            req <= 1'b0; sx <= 0; sy <= 0; fx <= 0; fy <= 0;
        end else if (fetching && i < nreq) begin
            req <= 1'b1; sx <= q_sx[i]; sy <= q_sy[i]; fx <= q_fx[i]; fy <= q_fy[i];
            expect_for(q_sx[i], q_sy[i], q_fx[i], q_fy[i]);
            i = i + 1;
        end else begin
            req <= 1'b0;
        end
    end

    // 结果检查：vld 在 posedge 后一整拍稳定，故在 negedge 读
    always @(negedge clk) begin
        if (rst_n && vld) begin
            if (e_head >= e_tail) begin
                $display("[DIAG] vld with empty expectation queue (nchk=%0d)", nchk);
                errors = errors + 1;
            end else begin
                if ({p11, p01, p10, p00} !== e_taps[e_head]) begin
                    $display("[DIAG] taps mismatch #%0d: got %h_%h_%h_%h exp %h",
                             nchk, p11, p01, p10, p00, e_taps[e_head]);
                    errors = errors + 1;
                end
                if ({ofx, ofy} !== e_frs[e_head]) begin
                    $display("[DIAG] frac mismatch #%0d: got %h%h exp %h",
                             nchk, ofx, ofy, e_frs[e_head]);
                    errors = errors + 1;
                end
                e_head = e_head + 1;
            end
            nchk = nchk + 1;
        end
    end

    task chk;
        input [8*46:1] named;
        input ok;
        begin
            $display("[CHK] %-46s : %s", named, ok ? "OK" : "BAD");
            if (!ok) errors = errors + 1;
        end
    endtask

    initial begin
        fill_queue;
        repeat (4) @(posedge clk);
        rst_n = 1;
        // 每个请求占一个像素周期 = 5 个快时钟周期；留足余量让 60 个全部走完
        repeat (60 * SL + 12) @(posedge clk);
        #1;
        chk("all 60 requests produced 60 tap groups", nchk == nreq);
        chk("expectation queue drained", e_head == e_tail);
        chk("no extra vld pulses", nchk == nreq && errors == 0);
        $display("[INFO] requests=%0d checked=%0d errors=%0d", nreq, nchk, errors);
        if (errors == 0) $display("RESULT tb_tap_sched PASS");
        else             $display("RESULT tb_tap_sched FAIL (%0d bad)", errors);
        $finish;
    end

    initial begin
        #200_000;
        $display("RESULT tb_tap_sched FAIL timeout");
        $finish;
    end
endmodule
