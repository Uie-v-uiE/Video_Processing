`timescale 1ns/1ps
// Display frame buffer: 64-bit write port (4 RGB565), 16-bit random read.
// Read latency = 1 clock (BRAM reg + in-beat mux).
module frame_buffer_w64 #(
    parameter W = 512,
    parameter H = 300
)(
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,   // 64-bit word index = pixel[18:2]
    input  wire [63:0] wr_data,   // {p3,p2,p1,p0}

    input  wire        rd_clk,
    input  wire [18:0] rd_addr,
    output reg  [15:0] rd_data
);
    localparam WORDS = (W * H + 3) / 4;
    (* ram_style = "block" *) reg [63:0] mem [0:WORDS-1];

    wire [18:0] widx = wr_addr;
    always @(posedge wr_clk) begin
        if (wr_en && widx < WORDS)
            mem[widx] <= wr_data;
    end

    reg [63:0] rd_q;
    reg [1:0]  rd_sel;
    always @(posedge rd_clk) begin
        if (rd_addr < (W*H)) begin
            rd_q   <= mem[rd_addr[18:2]];
            rd_sel <= rd_addr[1:0];
        end else begin
            rd_q   <= 64'd0;
            rd_sel <= 2'd0;
        end
    end
    always @(*) begin
        case (rd_sel)
            2'd0: rd_data = rd_q[15:0];
            2'd1: rd_data = rd_q[31:16];
            2'd2: rd_data = rd_q[47:32];
            default: rd_data = rd_q[63:48];
        endcase
    end
endmodule
