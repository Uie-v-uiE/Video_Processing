`timescale 1ns/1ps
// AXI3 write master: one RGB565 pixel per beat (2-byte strobe) into DDR.
// Simple and correct; 512x300@30fps ≈ 4.6 Mpix/s — well under HP0 capacity.
module axi_frame_saver #(
    parameter BASE_ADDR = 32'h1000_0000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,
    input  wire [15:0] wr_data,
    output reg         busy,

    output reg  [31:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,
    output reg  [63:0] m_axi_wdata,
    output wire [7:0]  m_axi_wstrb,
    output wire        m_axi_wlast,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready
);
    assign m_axi_awlen   = 8'd0;   // 1 beat
    assign m_axi_awsize  = 3'b001; // 2 bytes
    assign m_axi_awburst = 2'b01;
    assign m_axi_wstrb   = 8'h03;  // lane 0
    assign m_axi_wlast   = 1'b1;

    localparam FW = 7;
    localparam FD = 128;
    reg [15:0] dmem [0:FD-1];
    reg [18:0] amem [0:FD-1];
    reg [FW:0] wptr, rptr;
    wire empty = (wptr == rptr);
    wire full  = (wptr[FW] != rptr[FW]) && (wptr[FW-1:0] == rptr[FW-1:0]);

    always @(posedge clk) begin
        if (wr_en && enable && !full) begin
            dmem[wptr[FW-1:0]] <= wr_data;
            amem[wptr[FW-1:0]] <= wr_addr;
            wptr <= wptr + 1'b1;
        end
    end

    localparam [1:0] S_AW=0, S_W=1, S_B=2;
    reg [1:0] st;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_AW;
            rptr <= 0;
            wptr <= 0;
            busy <= 1'b0;
            m_axi_awvalid <= 1'b0;
            m_axi_awaddr  <= BASE_ADDR;
            m_axi_wvalid  <= 1'b0;
            m_axi_wdata   <= 64'd0;
            m_axi_bready  <= 1'b0;
        end else begin
            busy <= !empty;
            case (st)
                S_AW: begin
                    if (!empty) begin
                        m_axi_awvalid <= 1'b1;
                        m_axi_awaddr  <= BASE_ADDR + {12'd0, amem[rptr[FW-1:0]], 1'b0};
                        m_axi_wdata   <= {48'd0, dmem[rptr[FW-1:0]]};
                        st <= S_W;
                    end
                end
                S_W: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b1;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_bready <= 1'b1;
                        rptr <= rptr + 1'b1;
                        st <= S_B;
                    end
                end
                S_B: begin
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
                        st <= S_AW;
                    end
                end
                default: st <= S_AW;
            endcase
        end
    end
endmodule
