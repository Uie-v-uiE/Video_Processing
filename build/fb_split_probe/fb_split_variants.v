// 帧缓存拆分的两个候选（照抄 src/rtl/video/frame_buffer_w64.v 的读写结构，只改阵列划分）：
//   现在：32768 + 8192（2 的幂）⇒ 覆盖 40960 个字，而需要 38400 ⇒ 白填 2560 个 = 5 个 tile（实测 80）
//   fb3 ：32768 + 4096 + 2048 = 38912 ⇒ 预测 76 tile（白填 512）
//   fb4 ：32768 + 4096 + 1024 + 512 = 38400 ⇒ 预测 75 tile（不填）
// 64 位宽的阵列每 512 字占 1 个 RAMB36 ⇒ tile 数 = 覆盖字数 / 512，这条用实测 80 反推成立。
// 读侧保持"每块每拍都读一次 + 掩码夹住越界地址"，与原件一致，否则推断条件不可比。
`timescale 1ns/1ps

module fb_w64_3 #(
    parameter W = 512,
    parameter H = 300
)(
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,
    input  wire [63:0] wr_data,
    input  wire        rd_clk,
    input  wire [18:0] rd_addr,
    output wire [15:0] rd_data,
    output wire [63:0] rd_data64
);
    localparam WORDS = (W * H + 3) / 4;      // 38400
    localparam D0 = 32768, D1 = 4096, D2 = 2048;

    (* ram_style = "block" *) reg [63:0] a0 [0:D0-1];
    (* ram_style = "block" *) reg [63:0] a1 [0:D1-1];
    (* ram_style = "block" *) reg [63:0] a2 [0:D2-1];

    wire [18:0] widx = wr_addr;
    wire s1 = (widx >= D0), s2 = (widx >= (D0 + D1));
    always @(posedge wr_clk) begin
        if (wr_en && widx < WORDS) begin
            if (!s1)      a0[widx]        <= wr_data;
            else if (!s2) a1[widx - D0]   <= wr_data;
            else          a2[widx - D0 - D1] <= wr_data;
        end
    end

    wire [18:0] ridx = rd_addr[18:2];
    wire r1 = (ridx >= D0), r2 = (ridx >= (D0 + D1));
    reg [63:0] q0, q1, q2;
    reg        sel1, sel2;
    reg [1:0]  sel_lane;
    reg        blank;
    always @(posedge rd_clk) begin
        q0 <= a0[ridx & (D0-1)];
        q1 <= a1[(ridx - D0) & (D1-1)];
        q2 <= a2[(ridx - D0 - D1) & (D2-1)];
        sel1 <= r1; sel2 <= r2;
        sel_lane <= rd_addr[1:0];
        blank    <= (rd_addr >= (W*H));
    end
    wire [63:0] rd_q = sel2 ? q2 : (sel1 ? q1 : q0);
    reg [15:0] lane;
    always @(*) begin
        case (sel_lane)
            2'd0: lane = rd_q[15:0];
            2'd1: lane = rd_q[31:16];
            2'd2: lane = rd_q[47:32];
            default: lane = rd_q[63:48];
        endcase
    end
    assign rd_data = blank ? 16'd0 : lane;
    assign rd_data64 = rd_q;
endmodule

module fb_w64_4 #(
    parameter W = 512,
    parameter H = 300
)(
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,
    input  wire [63:0] wr_data,
    input  wire        rd_clk,
    input  wire [18:0] rd_addr,
    output wire [15:0] rd_data,
    output wire [63:0] rd_data64
);
    localparam WORDS = (W * H + 3) / 4;
    localparam D0 = 32768, D1 = 4096, D2 = 1024, D3 = 512;

    (* ram_style = "block" *) reg [63:0] a0 [0:D0-1];
    (* ram_style = "block" *) reg [63:0] a1 [0:D1-1];
    (* ram_style = "block" *) reg [63:0] a2 [0:D2-1];
    (* ram_style = "block" *) reg [63:0] a3 [0:D3-1];

    wire [18:0] widx = wr_addr;
    wire s1 = (widx >= D0), s2 = (widx >= (D0+D1)), s3 = (widx >= (D0+D1+D2));
    always @(posedge wr_clk) begin
        if (wr_en && widx < WORDS) begin
            if (!s1)                  a0[widx] <= wr_data;
            else if (!s2)             a1[widx - D0] <= wr_data;
            else if (!s3)             a2[widx - D0 - D1] <= wr_data;
            else                      a3[widx - D0 - D1 - D2] <= wr_data;
        end
    end

    wire [18:0] ridx = rd_addr[18:2];
    wire r1 = (ridx >= D0), r2 = (ridx >= (D0+D1)), r3 = (ridx >= (D0+D1+D2));
    reg [63:0] q0, q1, q2, q3;
    reg        sel1, sel2, sel3;
    reg [1:0]  sel_lane;
    reg        blank;
    always @(posedge rd_clk) begin
        q0 <= a0[ridx & (D0-1)];
        q1 <= a1[(ridx - D0) & (D1-1)];
        q2 <= a2[(ridx - D0 - D1) & (D2-1)];
        q3 <= a3[(ridx - D0 - D1 - D2) & (D3-1)];
        sel1 <= r1; sel2 <= r2; sel3 <= r3;
        sel_lane <= rd_addr[1:0];
        blank    <= (rd_addr >= (W*H));
    end
    wire [63:0] rd_q = sel3 ? q3 : (sel2 ? q2 : (sel1 ? q1 : q0));
    reg [15:0] lane;
    always @(*) begin
        case (sel_lane)
            2'd0: lane = rd_q[15:0];
            2'd1: lane = rd_q[31:16];
            2'd2: lane = rd_q[47:32];
            default: lane = rd_q[63:48];
        endcase
    end
    assign rd_data = blank ? 16'd0 : lane;
    assign rd_data64 = rd_q;
endmodule
