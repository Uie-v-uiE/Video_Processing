`timescale 1ns/1ps
// AXI3 HP0 frame fetcher: 64-bit data, max 16 beats/burst.
// Each beat = 4x RGB565; unpack over 4 cycles into frame_buffer.
module axi_frame_writer #(
    parameter IMG_W     = 512,
    parameter IMG_H     = 300,
    parameter BASE_ADDR = 32'h1000_0000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        frame_start,
    output reg         frame_busy,
    output reg         frame_done,
    output reg         fb_wr_en,
    output reg  [18:0] fb_wr_addr,
    output reg  [15:0] fb_wr_data,
    output reg  [31:0] m_axi_araddr,
    output reg  [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [63:0] m_axi_rdata,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready
);
    assign m_axi_arsize  = 3'b011; // 8 bytes / beat
    assign m_axi_arburst = 2'b01;  // INCR

    localparam integer BEATS      = 16;
    localparam integer PIX_PER_B  = 4;
    localparam integer PIX_BURST  = BEATS * PIX_PER_B; // 64
    localparam integer BURSTS_ROW = IMG_W / PIX_BURST; // 8
    localparam integer ROW_BYTES  = IMG_W * 2;         // 1024
    localparam integer BURST_BYTES = BEATS * 8;        // 128

    localparam [2:0] S_IDLE   = 3'd0;
    localparam [2:0] S_AR     = 3'd1;
    localparam [2:0] S_LOAD   = 3'd2;
    localparam [2:0] S_UNPACK = 3'd3;
    localparam [2:0] S_NEXT   = 3'd4;
    localparam [2:0] S_DONE   = 3'd5;

    reg [2:0]  state;
    reg [31:0] row;
    reg [31:0] burst_idx;
    reg [1:0]  up;
    reg [31:0] xw;
    reg [63:0] rhold;
    reg        rlast_hold;

    // 32-bit safe: row*IMG_W + xw
    wire [31:0] wr_pix_addr = row * IMG_W + xw;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            frame_busy <= 1'b0;
            frame_done <= 1'b0;
            fb_wr_en <= 1'b0;
            fb_wr_addr <= 19'd0;
            fb_wr_data <= 16'd0;
            m_axi_arvalid <= 1'b0;
            m_axi_araddr <= BASE_ADDR;
            m_axi_arlen  <= 8'd15;
            m_axi_rready <= 1'b0;
            row <= 32'd0;
            burst_idx <= 32'd0;
            up <= 2'd0;
            xw <= 32'd0;
            rhold <= 64'd0;
            rlast_hold <= 1'b0;
        end else begin
            fb_wr_en <= 1'b0;
            frame_done <= 1'b0;

            case (state)
                S_IDLE: begin
                    frame_busy <= 1'b0;
                    m_axi_rready <= 1'b0;
                    if (enable && frame_start) begin
                        row <= 32'd0;
                        burst_idx <= 32'd0;
                        xw <= 32'd0;
                        frame_busy <= 1'b1;
                        m_axi_araddr <= BASE_ADDR;
                        m_axi_arlen  <= 8'd15;
                        m_axi_arvalid<= 1'b1;
                        state <= S_AR;
                    end
                end

                S_AR: begin
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state <= S_LOAD;
                    end
                end

                S_LOAD: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        rhold <= m_axi_rdata;
                        rlast_hold <= m_axi_rlast;
                        m_axi_rready <= 1'b0;
                        up <= 2'd0;
                        state <= S_UNPACK;
                    end
                end

                S_UNPACK: begin
                    fb_wr_en   <= 1'b1;
                    fb_wr_addr <= wr_pix_addr[18:0];
                    // LE 64-bit: bytes0-1 = [15:0] = first pixel
                    case (up)
                        2'd0: fb_wr_data <= rhold[15:0];
                        2'd1: fb_wr_data <= rhold[31:16];
                        2'd2: fb_wr_data <= rhold[47:32];
                        default: fb_wr_data <= rhold[63:48];
                    endcase
                    xw <= xw + 32'd1;
                    up <= up + 2'd1;
                    if (up == 2'd3)
                        state <= S_NEXT;
                end

                S_NEXT: begin
                    if (rlast_hold) begin
                        if (burst_idx == BURSTS_ROW - 1) begin
                            burst_idx <= 32'd0;
                            if (row == IMG_H - 1) begin
                                state <= S_DONE;
                            end else begin
                                row <= row + 32'd1;
                                xw <= 32'd0;
                                // 32-bit row stride, no 12-bit shift overflow
                                m_axi_araddr <= BASE_ADDR + (row + 32'd1) * ROW_BYTES;
                                m_axi_arlen  <= 8'd15;
                                m_axi_arvalid<= 1'b1;
                                state <= S_AR;
                            end
                        end else begin
                            burst_idx <= burst_idx + 32'd1;
                            m_axi_araddr <= m_axi_araddr + BURST_BYTES;
                            m_axi_arlen  <= 8'd15;
                            m_axi_arvalid<= 1'b1;
                            state <= S_AR;
                        end
                    end else begin
                        m_axi_rready <= 1'b1;
                        state <= S_LOAD;
                    end
                end

                S_DONE: begin
                    frame_done <= 1'b1;
                    frame_busy <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
