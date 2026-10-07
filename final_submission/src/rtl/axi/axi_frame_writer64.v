`timescale 1ns/1ps
// AXI3 HP read: DDR frame -> 64-bit BRAM writes, with overlapped bursts
// to finish a full frame inside vertical blanking when possible.
module axi_frame_writer64 #(
    parameter IMG_W = 512,
    parameter IMG_H = 300,
    parameter BASE_ADDR = 32'h1000_0000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        frame_start,
    input  wire [31:0] base_addr,
    output reg         frame_busy,
    output reg         frame_done,

    output reg         fb_wr_en,
    output reg  [18:0] fb_wr_addr,
    output reg  [63:0] fb_wr_data,

    output reg  [31:0] m_axi_araddr,
    output reg  [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [63:0] m_axi_rdata,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready,
    output reg  [31:0] copy_cycles  // debug: cycles spent in last copy
);
    assign m_axi_arsize  = 3'b011;
    assign m_axi_arburst = 2'b01;

    localparam integer BEATS      = 16;
    localparam integer PIX_PER_B  = 4;
    localparam integer PIX_BURST  = BEATS * PIX_PER_B; // 64
    localparam integer BURSTS_ROW = (IMG_W / PIX_BURST) > 0 ? (IMG_W / PIX_BURST) : 1;
    localparam integer ROW_BYTES  = IMG_W * 2;
    localparam integer BURST_BYTES= BEATS * 8;

    reg [31:0] row, burst_idx, waddr_pix, base_r, cyc;
    reg        active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_busy <= 0; frame_done <= 0; active <= 0;
            fb_wr_en <= 0; fb_wr_addr <= 0; fb_wr_data <= 0;
            m_axi_arvalid <= 0; m_axi_araddr <= 0; m_axi_arlen <= 8'd15;
            m_axi_rready <= 0;
            row <= 0; burst_idx <= 0; waddr_pix <= 0; base_r <= BASE_ADDR;
            copy_cycles <= 0; cyc <= 0;
        end else begin
            fb_wr_en <= 1'b0;
            frame_done <= 1'b0;

            if (active) cyc <= cyc + 1;

            if (!active) begin
                frame_busy <= 0;
                m_axi_rready <= 0;
                if (enable && frame_start) begin
                    active <= 1;
                    frame_busy <= 1;
                    base_r <= base_addr;
                    row <= 0;
                    burst_idx <= 0;
                    waddr_pix <= 0;
                    cyc <= 0;
                    m_axi_araddr <= base_addr;
                    m_axi_arlen  <= 8'd15;
                    m_axi_arvalid<= 1;
                    m_axi_rready <= 0;
                end
            end else begin
                // AR handshake
                if (m_axi_arvalid && m_axi_arready) begin
                    m_axi_arvalid <= 0;
                    m_axi_rready  <= 1;
                end
                // data
                if (m_axi_rvalid && m_axi_rready) begin
                    fb_wr_en   <= 1'b1;
                    fb_wr_addr <= waddr_pix[18:2];
                    fb_wr_data <= m_axi_rdata;
                    waddr_pix  <= waddr_pix + 32'd4;
                    if (m_axi_rlast) begin
                        m_axi_rready <= 0;
                        // next burst immediately (overlap)
                        if (burst_idx == BURSTS_ROW - 1) begin
                            if (row == IMG_H - 1) begin
                                active <= 0;
                                frame_done <= 1;
                                copy_cycles <= cyc;
                            end else begin
                                row <= row + 1;
                                burst_idx <= 0;
                                waddr_pix <= (row + 1) * IMG_W;
                                m_axi_araddr <= base_r + (row + 1) * ROW_BYTES;
                                m_axi_arlen <= 8'd15;
                                m_axi_arvalid <= 1;
                            end
                        end else begin
                            burst_idx <= burst_idx + 1;
                            m_axi_araddr <= m_axi_araddr + BURST_BYTES;
                            m_axi_arlen <= 8'd15;
                            m_axi_arvalid <= 1;
                        end
                    end
                end
            end
        end
    end
endmodule
