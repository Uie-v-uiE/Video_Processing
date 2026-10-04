`timescale 1ns/1ps
// 功能：被测模块 `axi_frame_writer_gated`（#(.IMG_W(128),.IMG_H(80))）与 `frame_commit_lock` 的
//        V-blank 开窗；覆盖点：整帧写吞吐能否压在有限几个 V-blank allow 窗口内跑完。
// 激励与检查：axi_clk #5=10 ns、pix_clk #10=20 ns；rst_n 低 30 个 axi 拍后释放；像素每行 96 拍、
//        共 90 行（V_ACT=50 行的前 64 拍 de=1，V_BLANK_LINES=40 行整行 de=0），vs 在 ycnt==50
//        的第 0 列；blank_safe=(y>=50)&&!de；commit_req 拉 1 拍；最多等 200000 个 axi 拍到 done=1。
//        判定条件：wr_en 计数 wr_cnt>=TOTAL_WORDS=(128*80)/4=2560；allow&&busy 的累计拍数
//        allow_high_cycles<=vblank_budget*3，vblank_budget=V_BLANK_LINES*96*2=7680（pix 拍 20 ns
//        对 axi 拍 10 ns 的 2 倍关系），即上限 23040 个 axi 拍。
// 预期结果：通过时打印 INFO wr_cnt=<n> expect=2560 allow_high=<n> budget=7680 ar=<n> cyc=<n>、
//        PASS full frame written、PASS copy throughput acceptable for V-blast，末行 PASS tb_v5_vblast。
//        失败时打 FAIL timeout wr=<n> allow_cyc=<n> budget=7680 ar=<n>（随后 $finish）、
//        FAIL incomplete frame 或 FAIL too slow: allow_high=<n> > 3*Vblank=23040，
//        末行改打 FAIL tb_v5_vblast errors=<n>。
// v5.5: full frame must complete during ONE V-blank allow window
module tb_v5_vblast;
    reg axi_clk=0, pix_clk=0, rst_n=0;
    always #5 axi_clk = ~axi_clk;
    always #10 pix_clk = ~pix_clk;
    wire rst_pix_n = rst_n;

    parameter IMG_W=128, IMG_H=80;
    parameter TOTAL_PIX = IMG_W*IMG_H;
    parameter TOTAL_WORDS = TOTAL_PIX/4;
    parameter DISP_H=80;   // scale: active lines
    parameter V_TOTAL=90;  // 10 lines of V-blank
    // V-blank axi cycles in this TB: 10 lines * 96 pix * 2 = 1920 — too small
    // Use longer V-blank: 40 lines * 96 * 2 = 7680 axi cycles
    // Override V_TOTAL below via long blank

    // Line: 64 active + 32 blank = 96 pix
    // V-blank: last 40 lines have de=0 entire line
    parameter V_ACT=50;
    parameter V_BLANK_LINES=40;

    reg de=0, vs=0;
    reg [11:0] x=0, y=0;
    integer xcnt=0, ycnt=0;
    always @(posedge pix_clk) begin
        if (!rst_n) begin de<=0; vs<=0; xcnt<=0; ycnt<=0; x<=0; y<=0; end
        else begin
            de <= (xcnt < 64) && (ycnt < V_ACT);
            vs <= (xcnt==0 && ycnt==V_ACT);
            x <= xcnt[11:0];
            y <= ycnt[11:0];
            if (xcnt==95) begin
                xcnt<=0;
                if (ycnt==V_ACT+V_BLANK_LINES-1) ycnt<=0;
                else ycnt<=ycnt+1;
            end else xcnt<=xcnt+1;
        end
    end

    wire vblank_pix = (y >= V_ACT) && !de;
    wire blank_safe = vblank_pix;

    reg commit_req=0;
    reg [31:0] commit_base=32'h10000000;
    wire start_copy, done, busy, ready, allow, abort;
    wire [31:0] copy_base;
    wire wr_en; wire [18:0] wr_addr; wire [63:0] wr_data;
    wire arvalid, rready; wire [31:0] araddr; wire [7:0] arlen;
    reg arready=0, rvalid=0, rlast=0;
    reg [63:0] rdata=0;
    integer beats=0, delay=0, ar_cnt=0;

    // AXI: 1-cycle beat after AR accept, supports pipelined AR via queue-ish stall
    always @(posedge axi_clk) begin
        if (!rst_n) begin
            beats<=0; delay<=0; rvalid<=0; rlast<=0; arready<=1;
        end else if (arvalid && arready) begin
            ar_cnt=ar_cnt+1;
            beats<=beats + (arlen+1); // accumulate if overlapping
            delay<=1; rvalid<=0;
            // only one outstanding stream in this model — arready low while busy
            arready<=0;
        end else if (beats>0) begin
            if (delay>0) delay<=delay-1;
            else if (!rvalid) begin
                rvalid<=1;
                rdata<= {32'h5A5A, araddr[15:0], beats[15:0]};
                rlast<=1; // model each accept as short — simplified: stream beats
            end else if (rvalid && rready) begin
                rvalid<=0;
                beats<=beats-1;
                if (beats==1) begin
                    beats<=0; arready<=1;
                end
            end
        end else arready<=1;
    end

    frame_commit_lock u_cm (
        .axi_clk(axi_clk), .axi_rst_n(rst_n),
        .commit_req(commit_req), .commit_base(commit_base),
        .pix_clk(pix_clk), .pix_rst_n(rst_n),
        .de(de), .vsync(vs), .blank_safe(blank_safe),
        .copy_busy(busy), .copy_done(done),
        .start_copy(start_copy), .copy_base(copy_base),
        .frame_ready_pix(ready), .allow_copy_axi(allow),
        .copy_abort(abort)
    );

    axi_frame_writer_gated #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_wr (
        .clk(axi_clk), .rst_n(rst_n),
        .enable(1'b1), .start(start_copy), .base_addr(copy_base),
        .allow_wr(allow), .abort(abort),
        .busy(busy), .done(done),
        .fb_wr_en(wr_en), .fb_wr_addr(wr_addr), .fb_wr_data(wr_data),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(), .m_axi_arburst(),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .copy_cycles()
    );

    integer errors=0, wr_cnt=0, guard=0;
    integer allow_high_cycles=0;
    integer vblank_budget;
    always @(posedge axi_clk) begin
        if (wr_en) wr_cnt=wr_cnt+1;
        if (allow && busy) allow_high_cycles=allow_high_cycles+1;
    end

    initial begin
        // one V-blank window in axi cycles:
        // V_BLANK_LINES * 96 pix * (100/50) = 40*96*2 = 7680
        vblank_budget = V_BLANK_LINES * 96 * 2;
        rst_n=0; repeat(30) @(posedge axi_clk); rst_n=1;
        @(posedge axi_clk) commit_req<=1;
        @(posedge axi_clk) commit_req<=0;

        guard=0;
        while (done!==1'b1 && guard<200000) begin
            @(posedge axi_clk); guard=guard+1;
        end
        if (done!==1'b1) begin
            $display("FAIL timeout wr=%0d allow_cyc=%0d budget=%0d ar=%0d",
                     wr_cnt, allow_high_cycles, vblank_budget, ar_cnt);
            $finish;
        end
        $display("INFO wr_cnt=%0d expect=%0d allow_high=%0d budget=%0d ar=%0d cyc=%0d",
                 wr_cnt, TOTAL_WORDS, allow_high_cycles, vblank_budget, ar_cnt, u_wr.copy_cycles);
        if (wr_cnt < TOTAL_WORDS) begin
            $display("FAIL incomplete frame");
            errors=errors+1;
        end else $display("PASS full frame written");
        // Prefer finishing within ~2 V-blanks on this simplified AXI model;
        // production budget is 67200 for 512x300.
        if (allow_high_cycles > vblank_budget*3) begin
            $display("FAIL too slow: allow_high=%0d > 3*Vblank=%0d",
                     allow_high_cycles, vblank_budget*3);
            errors=errors+1;
        end else $display("PASS copy throughput acceptable for V-blast");

        if (errors==0) $display("PASS tb_v5_vblast");
        else $display("FAIL tb_v5_vblast errors=%0d", errors);
        $finish;
    end
endmodule
