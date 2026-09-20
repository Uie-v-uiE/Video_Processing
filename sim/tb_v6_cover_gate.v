`timescale 1ns/1ps
// v6 gate TB — frame_reasm must refuse to commit a frame that lost a packet.
// The old row bitmap only asked "was every row touched once", so a dropped
// packet left a black hole that was still committed (black stripes that survive
// a stopped stream). Production geometry: 512x300 RGB565, 1396 B payload.
module tb_v6_cover_gate;
    localparam integer IMG_W = 512, IMG_H = 300, FRAME_BYTES = 307200;
    localparam integer PAY   = 1396;
    localparam integer PKTS  = (FRAME_BYTES + PAY - 1) / PAY;   // 220

    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk;              // 125 MHz GMII

    reg        p_valid = 0, p_sof = 0, p_eof = 0;
    reg  [7:0] p_data = 0;
    wire       wr_en, flush, frame_done, frame_err;
    wire [18:0] wr_addr;
    wire [15:0] wr_data;
    wire [31:0] stat_frames, stat_pkts, stat_bytes, stat_bad, stat_oob;

    frame_reasm #(.IMG_W(IMG_W), .IMG_H(IMG_H), .FRAME_BYTES(FRAME_BYTES)) u_r (
        .clk(clk), .rst_n(rst_n),
        .p_data(p_data), .p_valid(p_valid), .p_sof(p_sof), .p_eof(p_eof),
        .p_good(1'b1),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .flush(flush),
        .frame_done(frame_done), .frame_err(frame_err),
        .stat_frames(stat_frames), .stat_pkts(stat_pkts),
        .stat_bytes(stat_bytes), .stat_bad(stat_bad), .stat_oob_off(stat_oob)
    );

    integer dups = 0;
    always @(posedge clk) if (frame_done) dups = dups + 1;

    // one packet: [u32 LE offset][payload]
    task send_pkt;
        input integer off;
        input integer skip;
        integer i, n;
        begin
            if (skip) begin
                // emulate a lost packet: nothing appears on the wire
                repeat (30) @(posedge clk);
            end else begin
                n = FRAME_BYTES - off;
                if (n > PAY) n = PAY;
                @(negedge clk);
                p_valid <= 1; p_sof <= 1; p_eof <= 0;
                p_data  <= off[7:0];
                @(negedge clk); p_sof <= 0; p_data <= off[15:8];
                @(negedge clk); p_data <= off[23:16];
                @(negedge clk); p_data <= off[31:24];
                for (i = 0; i < n; i = i + 1) begin
                    @(negedge clk);
                    p_data <= (off + i) & 8'hFF;
                    p_eof  <= (i == n - 1);
                end
                @(negedge clk);
                p_valid <= 0; p_eof <= 0;
            end
        end
    endtask

    task send_frame;
        input integer drop;          // packet index to lose, -1 = complete
        integer k;
        begin
            for (k = 0; k < PKTS; k = k + 1) send_pkt(k * PAY, (k == drop));
            repeat (200) @(posedge clk);
        end
    endtask

    integer errors = 0;
    initial begin
        rst_n = 0; repeat (10) @(posedge clk); rst_n = 1;
        send_frame(-1);
        if (dups != 1) begin $display("FAIL complete frame did not commit (done=%0d)", dups); errors = errors + 1; end
        else $display("PASS complete 512x300 frame commits");
        if (stat_bad !== 0) begin $display("FAIL clean frame counted bad=%0d", stat_bad); errors = errors + 1; end
        else $display("PASS clean frame not counted as bad");

        send_frame(100);
        if (dups != 1) begin
            $display("FAIL holey frame committed anyway (done=%0d)", dups); errors = errors + 1;
        end else $display("PASS frame with a lost packet is refused");
        if (stat_bad != 1) begin $display("FAIL holey frame not counted (bad=%0d)", stat_bad); errors = errors + 1; end
        else $display("PASS holey frame counted on the wire (OSD net_bad)");

        send_frame(-1);
        if (dups != 2) begin $display("FAIL recovery frame did not commit (done=%0d)", dups); errors = errors + 1; end
        else $display("PASS next complete frame commits again");

        $display("INFO done=%0d frames=%0d pkts=%0d bytes=%0d bad=%0d oob=%0d",
                 dups, stat_frames, stat_pkts, stat_bytes, stat_bad, stat_oob);
        if (errors == 0) $display("PASS tb_v6_cover_gate");
        else $display("FAIL tb_v6_cover_gate errors=%0d", errors);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("FAIL tb_v6_cover_gate timeout");
        $finish;
    end
endmodule
