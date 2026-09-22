`timescale 1ns/1ps
// Frame Buffer Manager: multi-slot FREE/RECEIVING/READY/DISPLAYING/INVALID
// Runs in axi_clk. Eth side tags pixels with slot id and reports frame end.
module frame_buffer_manager #(
    parameter NUM_SLOTS = 3,
    parameter IMG_PIXELS = 153600,
    parameter [25:0] COMMIT_TIMEOUT = 26'd8_000_000  // ~80 ms @ 100 MHz
)(
    input  wire        clk,
    input  wire        rst_n,

    // From eth (already CDC'd into axi_clk)
    input  wire        frame_end,       // 1-cycle pulse
    input  wire [1:0]  end_slot,
    input  wire [19:0] end_accepted,    // pixels accepted into CDC FIFO
    input  wire        end_bad,         // drop or oob in this frame

    // Saver status
    input  wire [19:0] wr_count0,
    input  wire [19:0] wr_count1,
    input  wire [19:0] wr_count2,
    input  wire        sav_idle,

    // Display blanking (clk_pix frame_done, CDC'd)
    input  wire        vsync_axi,

    // Copy engine
    input  wire        copy_busy,
    input  wire        copy_done,       // 1-cycle when DMA finished
    output reg         copy_start,
    output reg  [31:0] copy_base,

    // Status
    output reg  [31:0] stat_commits,
    output reg  [31:0] stat_invalid,
    output reg  [1:0]  latest_ready,
    output reg         has_ready,
    output reg  [31:0] stat_drop_frames
);
    localparam [31:0] SLOT_BASE   = 32'h1000_0000;
    localparam [31:0] SLOT_STRIDE = 32'h0010_0000;

    localparam [2:0] ST_FREE  = 3'd0;
    localparam [2:0] ST_RX    = 3'd1;
    localparam [2:0] ST_RDY   = 3'd2;
    localparam [2:0] ST_DISP  = 3'd3;
    localparam [2:0] ST_INV   = 3'd4;

    reg [2:0]  st [0:2];
    reg [7:0]  gen [0:2];
    reg [7:0]  disp_gen;
    reg [1:0]  disp_slot;

    reg        commit_wait;
    reg [1:0]  pend_slot;
    reg [19:0] pend_pix;
    reg        pend_bad;
    reg [25:0] wait_tmr;

    wire [19:0] wr_of_slot [0:2];
    assign wr_of_slot[0] = wr_count0;
    assign wr_of_slot[1] = wr_count1;
    assign wr_of_slot[2] = wr_count2;

    function [19:0] wr_cnt;
        input [1:0] s;
        begin
            case (s)
                2'd0: wr_cnt = wr_count0;
                2'd1: wr_cnt = wr_count1;
                default: wr_cnt = wr_count2;
            endcase
        end
    endfunction

    function [31:0] slot_addr;
        input [1:0] s;
        begin
            slot_addr = SLOT_BASE + (s * SLOT_STRIDE);
        end
    endfunction

    integer i;
    reg [1:0] pick;
    reg       pick_v;
    reg [7:0] pick_gen;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 3; i = i + 1) begin
                st[i]  <= ST_FREE;
                gen[i] <= 8'd0;
            end
            commit_wait   <= 1'b0;
            pend_slot     <= 2'd0;
            pend_pix      <= 20'd0;
            pend_bad      <= 1'b0;
            wait_tmr      <= 26'd0;
            copy_start    <= 1'b0;
            copy_base     <= SLOT_BASE;
            disp_slot     <= 2'd0;
            disp_gen      <= 8'd0;
            stat_commits  <= 32'd0;
            stat_invalid  <= 32'd0;
            stat_drop_frames <= 32'd0;
            latest_ready  <= 2'd0;
            has_ready     <= 1'b0;
        end else begin
            copy_start <= 1'b0;

            // Mark RX slots on frame_end (eth already advanced its RR pointer)
            if (frame_end && end_slot < 2'd3) begin
                commit_wait <= 1'b1;
                pend_slot   <= end_slot;
                pend_pix    <= end_accepted;
                pend_bad    <= end_bad;
                wait_tmr    <= COMMIT_TIMEOUT;
                st[end_slot]<= ST_RX;
                gen[end_slot] <= gen[end_slot] + 8'd1;
            end

            // Commit evaluation
            if (commit_wait) begin
                if (wait_tmr != 0) wait_tmr <= wait_tmr - 1'b1;

                if (sav_idle && !pend_bad && (pend_pix >= IMG_PIXELS) &&
                    (wr_cnt(pend_slot) >= IMG_PIXELS)) begin
                    st[pend_slot] <= ST_RDY;
                    commit_wait   <= 1'b0;
                    stat_commits  <= stat_commits + 32'd1;
                    if (has_ready == 1'b0 ||
                        ($signed({1'b0, gen[pend_slot]}) - $signed({1'b0, disp_gen})) > 0) begin
                        latest_ready <= pend_slot;
                        has_ready    <= 1'b1;
                    end
                end else if (wait_tmr == 26'd0) begin
                    st[pend_slot] <= ST_FREE;
                    commit_wait   <= 1'b0;
                    stat_invalid  <= stat_invalid + 32'd1;
                    if (pend_bad) stat_drop_frames <= stat_drop_frames + 32'd1;
                end else if (pend_bad) begin
                    // fail fast on bad frames
                    st[pend_slot] <= ST_FREE;
                    commit_wait   <= 1'b0;
                    stat_invalid  <= stat_invalid + 32'd1;
                    stat_drop_frames <= stat_drop_frames + 32'd1;
                end
            end

            // VSYNC atomic handoff: pick newest READY, not currently copying
            if (vsync_axi && !copy_busy && !copy_start) begin
                pick_v  = 1'b0;
                pick    = 2'd0;
                pick_gen= 8'd0;
                for (i = 0; i < 3; i = i + 1) begin
                    if (st[i] == ST_RDY) begin
                        if (!pick_v || ((gen[i] - disp_gen) & 8'h7F) > ((pick_gen - disp_gen) & 8'h7F)) begin
                            pick_v = 1'b1;
                            pick = i[1:0];
                            pick_gen = gen[i];
                        end
                    end
                end
                if (pick_v) begin
                    st[pick]      <= ST_DISP;
                    disp_slot     <= pick;
                    disp_gen      <= pick_gen;
                    copy_base     <= slot_addr(pick);
                    copy_start    <= 1'b1;
                    has_ready     <= 1'b0;
                    latest_ready  <= pick;
                end
            end

            // Copy finished → FREE
            if (copy_done && disp_slot < 2'd3) begin
                if (st[disp_slot] == ST_DISP)
                    st[disp_slot] <= ST_FREE;
            end
        end
    end
endmodule
