`timescale 1ns/1ps
// v6 proof TB — PRODUCTION geometry (512x300 source, 1024x600 @50MHz pix,
// 100MHz AXI). Question: does the whole frame land in the display BRAM inside
// ONE V-blank window, so no visible row can ever mix two DDR frames?
//
//   window = 25 blank lines x 1344 px = 33600 pix cycles = 67200 axi cycles
//   frame  = 38400 words of 64 bit (4 RGB565 each)
//
// The slave models HP0 as a sustained bandwidth (rate_num beats / 10 cycles;
// 10 = the 800 MB/s peak of a 64-bit @100MHz port) plus a cold-start latency.
module tb_v6_vblank_copy;
    localparam integer IMG_W  = 512;
    localparam integer IMG_H  = 300;
    localparam integer WORDS  = (IMG_W * IMG_H) / 4;   // 38400
    localparam integer LAT    = 40;
    localparam integer WD     = 32'd2_000_000;          // production watchdog (20 ms)

    reg pix_clk = 0, axi_clk = 0, rst_n = 0;
    always #10 pix_clk = ~pix_clk;
    always #5  axi_clk  = ~axi_clk;

    wire [11:0] x, y;
    wire hs, vs, de, frame_start, frame_done_v;
    video_timing_1024x600 u_t (
        .clk(pix_clk), .rst_n(rst_n),
        .x(x), .y(y), .hs(hs), .vs(vs), .de(de),
        .frame_start(frame_start), .frame_done(frame_done_v)
    );

    // replica of the v6 window in pl_video_top
    wire blank_window = (y >= 12'd600) && ((y < 12'd624) || (x <= 12'd1279));

    reg commit_req = 0;
    wire start_copy, copy_done, copy_busy, allow, copy_abort, frame_ready;
    wire [31:0] copy_base;
    frame_commit_lock #(.IMG_H(IMG_H), .DISP_H(600), .WD_CYC(WD)) u_cm (
        .axi_clk(axi_clk), .axi_rst_n(rst_n),
        .commit_req(commit_req), .commit_base(32'h1000_0000),
        .pix_clk(pix_clk), .pix_rst_n(rst_n),
        .de(de), .vsync(vs), .blank_safe(blank_window),
        .copy_busy(copy_busy), .copy_done(copy_done),
        .start_copy(start_copy), .copy_base(copy_base),
        .frame_ready_pix(frame_ready), .allow_copy_axi(allow),
        .copy_abort(copy_abort)
    );

    wire wr_en; wire [18:0] wr_addr; wire [63:0] wr_data;
    wire [31:0] araddr; wire [7:0] arlen;
    wire [2:0] arsize; wire [1:0] arburst;
    wire arvalid, rready;
    reg arready = 1, rvalid = 0, rlast = 0;
    reg [63:0] rdata = 0;
    wire [31:0] copy_cycles;

    axi_frame_writer_gated #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_wr (
        .clk(axi_clk), .rst_n(rst_n),
        .enable(1'b1), .start(start_copy), .base_addr(copy_base),
        .allow_wr(allow), .abort(copy_abort),
        .busy(copy_busy), .done(copy_done),
        .fb_wr_en(wr_en), .fb_wr_addr(wr_addr), .fb_wr_data(wr_data),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid),
        .m_axi_rready(rready), .copy_cycles(copy_cycles)
    );

    // ---- bandwidth-limited read slave -----------------------------------
    integer rate_num, credits, pending, rem_burst, gap, idle_seen;
    always @(posedge axi_clk) begin
        if (!rst_n) begin
            arready <= 1; rvalid <= 0; rlast <= 0; rdata <= 0;
            credits = 0; pending = 0; rem_burst = 0; gap = 0; idle_seen = 1;
            rate_num = 10;
        end else begin
            if (arvalid && arready) begin
                pending = pending + arlen + 1;
                if (idle_seen) begin gap = LAT; idle_seen = 0; end
            end
            arready <= 1;
            if (gap > 0) gap = gap - 1;
            credits = credits + rate_num;
            if (credits > 40) credits = 40;
            if (credits >= 10 && pending > 0 && gap == 0 && (!rvalid || rready)) begin
                credits = credits - 10;
                if (rem_burst == 0) rem_burst = 16;
                pending   = pending - 1;
                rem_burst = rem_burst - 1;
                rvalid    <= 1;
                rdata     <= {32'h1234_5678, pending[31:0]};
                rlast     <= (rem_burst == 0);
                if (pending == 0) begin idle_seen = 1; rem_burst = 0; end
            end else if (rvalid && rready) rvalid <= 0;
        end
    end

    // ---- checks ----------------------------------------------------------
    reg [WORDS-1:0] seen;
    integer errors, w_ok, w_dup, w_oob, w_viol;
    reg window_open;
    reg [11:0] de_d;

    always @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin de_d <= 0; window_open <= 0; end
        else begin
            de_d        <= {de_d[10:0], de};
            window_open <= blank_window;
            // a write is only legal while the beam is blank: y>=600 covers the
            // whole V-blank window plus the CDC residue the 64-px guard allows
            if (wr_en && (de || de_d[11] || (y < 12'd600))) w_viol = w_viol + 1;
        end
    end

    always @(posedge axi_clk) begin
        if (rst_n && wr_en) begin
            if (wr_addr >= WORDS)       w_oob = w_oob + 1;
            else if (seen[wr_addr[15:0]]) w_dup = w_dup + 1;
            else begin seen[wr_addr[15:0]] = 1'b1; w_ok = w_ok + 1; end
        end
    end

    // 38400 words must fit the 67200-cycle window → needs >=0.571 beat/cycle.
    // run_phase(rate, must_finish_in_one_window)
    task run_phase;
        input integer r;
        input integer in_one;
        integer g;
        integer did1;
        begin
            rate_num = r;
            w_ok = 0; w_dup = 0; w_oob = 0; w_viol = 0;
            seen = 0;
            @(posedge axi_clk); commit_req <= 1;
            @(posedge axi_clk); commit_req <= 0;
            @(posedge start_copy);
            // copy must finish before allow falls (window closes)
            while (allow && !copy_done && !copy_abort) @(posedge axi_clk);
            did1 = copy_done;
            if (!did1 && !in_one) begin
                // below the 0.571 beat/cycle floor the swap legitimately spills
                // into the next blank; it must still finish and never write an
                // active line. One display frame = 1.68 M axi cycles.
                g = 0;
                while (!copy_done && (g < 3_000_000)) begin
                    @(posedge axi_clk); g = g + 1;
                end
            end
            if (copy_done && (did1 == in_one))
                $display("PASS rate=%0d/10 swap %s done=%0d cycles=%0d words=%0d",
                         r, in_one ? "inside one V-blank" : "after spilling",
                         did1, copy_cycles, w_ok);
            else if (!copy_done) begin
                $display("FAIL rate=%0d/10 no swap (abort=%0d words=%0d/%0d viol=%0d)",
                         r, copy_abort, w_ok, WORDS, w_viol);
                errors = errors + 1;
            end else begin
                $display("FAIL rate=%0d/10 swapped in_one=%0d but required=%0d",
                         r, did1, in_one);
                errors = errors + 1;
            end
            if (w_ok != WORDS || w_dup != 0 || w_oob != 0) begin
                $display("FAIL rate=%0d/10 coverage words=%0d/%0d dup=%0d oob=%0d",
                         r, w_ok, WORDS, w_dup, w_oob);
                errors = errors + 1;
            end
            if (w_viol != 0) begin
                $display("FAIL rate=%0d/10 writes overlapped active display (%0d)", r, w_viol);
                errors = errors + 1;
            end
            if (did1)
                $display("rate=%0d/10 swapped inside the first V-blank (window budget met)", r);
            else
                $display("rate=%0d/10 spilled to a later V-blank (below the 0.571 beat/cycle floor)", r);
            // wait for the abort/idle path to settle, then for the window to close
            while (copy_busy) @(posedge axi_clk);
            while (allow) @(posedge axi_clk);
            repeat (3000) @(posedge axi_clk);
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 0; repeat (50) @(posedge axi_clk); rst_n = 1;
        repeat (2000) @(posedge pix_clk);
        run_phase(10, 1);   // 800 MB/s: HP0 peak
        run_phase(7,  1);   // 560 MB/s
        run_phase(6,  1);   // 480 MB/s, just above the 0.571 beat/cycle floor
        run_phase(4,  0);   // 320 MB/s, below the floor: must degrade cleanly
        if (errors == 0) $display("PASS tb_v6_vblank_copy");
        else $display("FAIL tb_v6_vblank_copy errors=%0d", errors);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("FAIL tb_v6_vblank_copy timeout");
        $finish;
    end
endmodule
