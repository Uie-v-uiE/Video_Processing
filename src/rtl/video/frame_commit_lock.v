`timescale 1ns/1ps
// frame_commit_lock v5.9 — RESTORE first-good v5 policy
// allow = ALL blanking after de_d4→de_d[11] only (output pipeline).
// NO near_de, NO V-blank-only, NO mute.
module frame_commit_lock #(
    parameter IMG_H   = 300,
    parameter DISP_H  = 600,
    parameter WD_CYC  = 32'd2_000_000
)(
    input  wire        axi_clk,
    input  wire        axi_rst_n,
    input  wire        commit_req,
    input  wire [31:0] commit_base,
    input  wire        pix_clk,
    input  wire        pix_rst_n,
    input  wire        de,
    input  wire        vsync,
    input  wire        blank_safe,
    input  wire        copy_busy,
    input  wire        copy_done,
    output reg         start_copy,
    output reg  [31:0] copy_base,
    output reg         frame_ready_pix,
    output wire        allow_copy_axi,
    output reg         copy_abort,
    output reg         abort_tgl        // v7.9：copy_abort 每发生一次就翻转一位（给像素域用）
);
    reg pending;
    reg [31:0] pending_base;
    reg copy_active;
    reg [31:0] wd_cnt;

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            pending <= 0; pending_base <= 32'h1000_0000;
        end else if (commit_req) begin
            pending <= 1'b1; pending_base <= commit_base;
        end else if (start_copy) begin
            pending <= 1'b0;
        end
    end

    reg vs_d0, vs_d1;
    reg bs_d0, bs_d1, bs_d2;
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            {vs_d1,vs_d0} <= 2'b0;
            {bs_d2,bs_d1,bs_d0} <= 3'b0;
        end else begin
            vs_d0 <= vsync; vs_d1 <= vs_d0;
            bs_d0 <= blank_safe; bs_d1 <= bs_d0; bs_d2 <= bs_d1;
        end
    end
    wire vs_rise = vs_d0 & ~vs_d1;
    wire blank_pix = bs_d2;

    reg blank_tog;
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) blank_tog <= 1'b0;
        else if (vs_rise) blank_tog <= ~blank_tog;
    end
    (* ASYNC_REG = "TRUE" *) reg b0,b1,b2;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) {b2,b1,b0} <= 3'b0;
        else {b2,b1,b0} <= {b1,b0,blank_tog};
    end
    wire vsync_req = b1 ^ b2;

    (* ASYNC_REG = "TRUE" *) reg d0,d1,d2;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) {d2,d1,d0} <= 3'b0;
        else {d2,d1,d0} <= {d1,d0,blank_pix};
    end
    assign allow_copy_axi = d1 & d2;

    // v6: start the copy at the OPENING of the allow window, not at the vsync
    // edge. With 1024x600 (V_FP=3, V_SYNC=6) vsync only rises 9 blank lines
    // into a 25-line window, which throws away a third of the copy budget.
    reg al_d;
    wire allow_rise = allow_copy_axi & ~al_d;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) al_d <= 1'b0;
        else al_d <= allow_copy_axi;
    end

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin wd_cnt <= 0; copy_abort <= 0; end
        else begin
            copy_abort <= 0;
            if (!copy_active || copy_done) wd_cnt <= 0;
            else begin
                wd_cnt <= wd_cnt + 1;
                if (wd_cnt >= WD_CYC) begin copy_abort <= 1; wd_cnt <= 0; end
            end
        end
    end

    // v7.9：`copy_abort` 是 axi_clk 上**只有 1 拍（10 ns）**的脉冲，而消费者
    // `pl_video_top` 的 `eth_has_frame` 在 50 MHz 像素域 —— 两路时钟同源同相
    // （MMCM 出来的 100 MHz 与 50 MHz），于是脉冲的翻转沿**正好压在**像素域的采样沿上：
    // 收不收得到取决于建立/保持窗口里的亚稳，`report_cdc` 一直把它记成 unsafe。
    // 电平型 3 级同步在这里只会更糟（更容易整串漏掉）；正确形式是翻转式脉冲同步器，
    // 与本文件里像素域→axi 域那一侧的 `blank_tog` 完全对称（同一个文件已有模板）。
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) abort_tgl <= 1'b0;
        else if (copy_abort) abort_tgl <= ~abort_tgl;
    end

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            start_copy <= 0; copy_base <= 32'h10000000; copy_active <= 0;
        end else begin
            start_copy <= 0;
            if (copy_done || copy_abort) copy_active <= 0;
            if ((allow_rise || vsync_req) && pending && !copy_active && !copy_busy
                && !copy_done && !start_copy && !copy_abort) begin
                start_copy <= 1;
                copy_base <= pending_base;
                copy_active <= 1;
            end
        end
    end

    reg ready_tog;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) ready_tog <= 0;
        else if (copy_done) ready_tog <= ~ready_tog;
    end
    (* ASYNC_REG = "TRUE" *) reg r0,r1,r2;
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin {r2,r1,r0} <= 0; frame_ready_pix <= 0; end
        else begin
            {r2,r1,r0} <= {r1,r0,ready_tog};
            if (r1 ^ r2) frame_ready_pix <= 1;
        end
    end
endmodule
