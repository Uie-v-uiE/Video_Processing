`timescale 1ns/1ps
// Display frame buffer: 64-bit write port (4 RGB565), 16-bit random read.
// Read latency = 1 clock (BRAM 输出寄存器 + 块内 lane mux)，与 v6.4 一致。
//
// 为什么要按 2 的幂拆成两块，而不是直接声明一个 38400 深的数组：
// BRAM 推断会把非 2 的幂的深度**向上填充到 2^16**，于是 512x300 的帧缓存
// 实测吃掉 128 个 RAMB36（整个 xc7z020 只有 140 个，BRAM 98.93% 全卡在这），
// 而数据量本身只需要 67 个 tile。拆成 32768 + 8192 两块以后实测 80 个，
// 省下的 48 个 tile 足够放插值行缓存。对照实验见 tmp_ramtest/fbtest.v
// （v0 单阵列 = 128，v5 分块 = 80），不是猜的。
module frame_buffer_w64 #(
    parameter W = 512,
    parameter H = 300
)(
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,   // 64-bit word index = pixel[18:2]
    input  wire [63:0] wr_data,   // {p3,p2,p1,p0}

    input  wire        rd_clk,
    input  wire [18:0] rd_addr,   // 像素号
    output wire [15:0] rd_data
);
    // 不超过 n 的最大 2 的幂的位宽
    function integer bitsof;
        input integer n;
        integer v;
        begin
            v = n; bitsof = 0;
            while (v > 0) begin bitsof = bitsof + 1; v = v >> 1; end
        end
    endfunction

    localparam WORDS = (W * H + 3) / 4;             // 38400 个 64bit 字
    localparam D_LO  = (1 << (bitsof(WORDS) - 1));  // 32768 = 2^15
    localparam REM   = WORDS - D_LO;                // 5632
    localparam D_HI  = (REM == 0) ? 1 : (1 << bitsof(REM));   // 8192

    (* ram_style = "block" *) reg [63:0] lo [0:D_LO-1];
    (* ram_style = "block" *) reg [63:0] hi [0:D_HI-1];

    wire [18:0] widx   = wr_addr;
    wire        wr_hi  = (widx >= D_LO[19:0]);
    wire [18:0] w_off  = widx - D_LO[19:0];

    always @(posedge wr_clk) begin
        if (wr_en && widx < WORDS[19:0]) begin
            if (wr_hi) hi[w_off & (D_HI-1)] <= wr_data;
            else       lo[widx]             <= wr_data;
        end
    end

    // 两个块每拍都被读一次，真正的选择由 sel_hi 完成——这样读延迟仍是 1 拍，
    // 且越界一侧的地址用掩码夹住，不会产生 X。
    wire [18:0] ridx   = rd_addr[18:2];
    wire        rd_hi  = (ridx >= D_LO[19:0]);
    wire [18:0] r_off  = ridx - D_LO[19:0];

    reg [63:0] q_lo, q_hi;
    reg        sel_hi;
    reg [1:0]  sel_lane;
    reg        blank;

    always @(posedge rd_clk) begin
        q_lo     <= lo[ridx & (D_LO-1)];
        q_hi     <= hi[r_off & (D_HI-1)];
        sel_hi   <= rd_hi;
        sel_lane <= rd_addr[1:0];
        blank    <= (rd_addr >= (W*H));             // 越界仍回黑，保持 v6.4 行为
    end

    wire [63:0] rd_q = sel_hi ? q_hi : q_lo;
    reg [15:0]  lane;
    always @(*) begin
        case (sel_lane)
            2'd0: lane = rd_q[15:0];
            2'd1: lane = rd_q[31:16];
            2'd2: lane = rd_q[47:32];
            default: lane = rd_q[63:48];
        endcase
    end
    assign rd_data = blank ? 16'd0 : lane;
endmodule
