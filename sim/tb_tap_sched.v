`timescale 1ns/1ps
// tb_tap_sched —— 判"每个请求拿到的 4 个抽头 + fx/fy 都对、左窗字也对、输出节拍=输入节拍"。
//
// 独立性怎么保证（这条最重要）：期望值**不走** DUT 的字地址/车道路径，
// 而是直接用像素函数 pix(n) 算 `pix(sy*W+sx)`、`pix(...+1)`、`pix(...+W)`、`pix(...+W+1)`；
// 存储模型只用来喂 DUT 的读口。两边算法不同 ⇒ 有一方错就会露出来。
// 左窗那一路另算一条独立判据：aux_q/aux_lane 必须等于 pix(aux_word*4 + aux_word[1:0])。
//
// 台架卫生（都是今晚踩过的，写在这儿免得再踩）：
//   · 驱动与检查都在 negedge：寄存型输出在 posedge 之后一整拍稳定。
//   · 判据实参在**调用点**求值，所以计数类判据前要先留 settling。
//   · 标签用 ASCII：中文在 xsim 的控制台输出里会糊成 ?。
//   · 存储模型每拍都跟随地址（真 BRAM 就是这个行为，frame_buffer_w64 无条件寄存 q_lo），
//     所以不需要 rd_en —— 少一个"TB 自己造的控制信号"就少一处自证。
module tb_tap_sched;
    localparam IW = 512;
    localparam SL = 5;

    reg clk = 0, rst_n = 0;
    always #2 clk = ~clk;                 // 4 ns 快时钟（对应 20 ns 像素周期 = 5 槽）

    reg         req;
    reg  [16:0] word;
    reg  [1:0]  lane;
    reg  [7:0]  fx, fy;
    reg  [16:0] aux_word;
    reg  [1:0]  aux_lane;
    wire [63:0] aux_q;
    wire [1:0]  aux_lane_q;
    wire [16:0] rd_word_addr;
    reg  [63:0] rd_word;
    wire [15:0] p00, p10, p01, p11;
    wire [7:0]  ofx, ofy;
    wire        vld;

    tap_sched #(.IMG_W(IW), .SLOTS(SL)) u_dut (
        .clk(clk), .rst_n(rst_n), .req(req),
        .word(word), .lane(lane), .fx(fx), .fy(fy),
        .aux_word(aux_word), .aux_lane(aux_lane),
        .aux_q(aux_q), .aux_lane_q(aux_lane_q),
        .rd_word_addr(rd_word_addr), .rd_word(rd_word),
        .p00(p00), .p10(p10), .p01(p01), .p11(p11), .ofx(ofx), .ofy(ofy), .vld(vld));

    // ---------------- 存储模型 ----------------
    function [15:0] pix;
        input [24:0] n;
        begin
            pix = n[15:0] ^ {n[11:0], 4'h0} ^ (n[15:0] * 16'h0403) ^ 16'h5A5A;
        end
    endfunction

    function [63:0] word_of;
        input [16:0] w;
        begin
            word_of = {pix(w*4 + 3), pix(w*4 + 2), pix(w*4 + 1), pix(w*4 + 0)};
        end
    endfunction

    function [15:0] pick;
        input [63:0] w;
        input [1:0]  l;
        begin
            case (l)
                2'd0:    pick = w[15:0];
                2'd1:    pick = w[31:16];
                2'd2:    pick = w[47:32];
                default: pick = w[63:48];
            endcase
        end
    endfunction

    always @(posedge clk) rd_word <= word_of(rd_word_addr);

    // ---------------- 请求序列：覆盖 lane=0..3、跨行、行首/行尾 ----------------
    integer   nreq = 60, i = 0, k = 0;
    reg [11:0] q_sx [0:63];
    reg [11:0] q_sy [0:63];
    reg [7:0]  q_fx [0:63];
    reg [7:0]  q_fy [0:63];
    reg [16:0] q_aux [0:63];

    task fill_queue;
        begin
            for (k = 0; k < 60; k = k + 1) begin
                q_sx[k]  = 4*(k % 40) + (k % 4);
                q_sy[k]  = (k % 50);
                q_fx[k]  = 8'h11 * (k[7:0] % 8);
                q_fy[k]  = 8'h22 * (k[7:0] % 4);
                q_aux[k] = (k * 37) % (IW*300/4);
            end
            q_sx[57] = 0;   q_sy[57] = 100;            // lane 0，行首
            q_sx[58] = 508; q_sy[58] = 101;            // 接近行尾
            q_sx[59] = 511; q_sy[59] = 102;            // lane 3 ⇒ 必须读下一个字
        end
    endtask

    // ---------------- 期望队列（右窗抽头） ----------------
    reg [63:0] e_taps [0:63];              // {p11,p01,p10,p00}
    reg [15:0] e_frs  [0:63];              // {fx,fy}
    integer   e_head = 0, e_tail = 0;

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

    // 每像素周期换一次请求（= 顶层里 clk_pix 域寄存器一个周期一个值）
    wire in_s0 = (u_dut.slot == 3'd0);
    always @(negedge clk) begin
        if (!rst_n) begin
            req <= 1'b0; word <= 0; lane <= 0; fx <= 0; fy <= 0; aux_word <= 0;
        end else if (in_s0) begin
            req <= (i < nreq);                      // 发完就停：否则尾部会多出没有期望的 vld
            if (i < nreq) begin
                word <= {(q_sy[i]*IW + q_sx[i]) >> 2};
                lane <= {(q_sy[i]*IW + q_sx[i]) & 2'h3};
                fx   <= q_fx[i];
                fy   <= q_fy[i];
                expect_for(q_sx[i], q_sy[i], q_fx[i], q_fy[i]);
                i = i + 1;
            end else begin
                word <= 17'd0; lane <= 2'd0; fx <= 8'd0; fy <= 8'd0;
            end
            aux_word <= (i < nreq + 1) ? q_aux[i > 0 ? i-1 : 0] : 17'd0;
            aux_lane <= i[1:0] ^ 2'd1;              // 与字号无关的独立车道图案：错了就会露出来
        end
    end

    integer errors = 0, nchk = 0, naux = 0, nauxbad = 0;

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

    // 左窗字：aux_q 在 s1 沿装好，s2 内整拍稳定 ⇒ 在 s2 的 negedge 判。
    // 期望值直接从 aux_word 自己算（不走 DUT 的路径），所以这条判据不依赖任何队列对齐；
    // 头两个周期流水还没灌满（aux_q 仍是复位值），用 cyc 跳过。
    wire in_s2 = (u_dut.slot == 3'd2);
    integer cyc = 0;
    always @(negedge clk) begin
        if (!rst_n) cyc = 0;
        else if (u_dut.slot == 3'd4) cyc = cyc + 1;
    end
    always @(negedge clk) begin
        if (rst_n && in_s2 && cyc >= 2) begin
            naux = naux + 1;
            if (pick(aux_q, aux_lane_q) !== pix(aux_word*4 + {15'd0, aux_lane})) begin
                if (nauxbad < 5)
                    $display("[DIAG] aux mismatch #%0d: word=%0d lane=%0d got %h exp %h",
                             naux, aux_word, aux_lane, pick(aux_q, aux_lane_q),
                             pix(aux_word*4 + {15'd0, aux_lane}));
                nauxbad = nauxbad + 1;
            end
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
        aux_word = 17'd0;
        aux_lane = 2'd0;
        #1;
        repeat (4) @(posedge clk);
        rst_n = 1;
        // 前 2 个周期是流水灌满（aux_q 里还没有对应本请求的字），从第 3 个周期起才开始判
        repeat (60 * SL + 12) @(posedge clk);
        #1;
        chk("all 60 requests produced 60 tap groups", nchk == nreq);
        chk("expectation queue drained", e_head == e_tail);
        chk("no extra vld pulses", nchk == nreq);
        chk("left-pane word checked every period", naux > 55);
        chk("left-pane word all correct", nauxbad == 0);
        $display("[INFO] requests=%0d checked=%0d aux=%0d auxbad=%0d errors=%0d",
                 nreq, nchk, naux, nauxbad, errors);
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
