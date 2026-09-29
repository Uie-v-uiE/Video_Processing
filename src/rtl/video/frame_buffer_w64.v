`timescale 1ns/1ps
// Display frame buffer: 64-bit write port (4 RGB565), 16-bit random read. 写 wr_clk / 读 rd_clk 两个域。
// Read latency = 1 clock (BRAM 输出寄存器 + 块内 lane mux)，与 v6.4 一致。
// ⚠ 必须按 2 的幂拆块，不能直接声明一个 38400 深的数组：BRAM 推断会把非 2 的幂的深度**向上填充到
//   2^16** ⇒ 512x300 的帧缓存实测吃掉 128 个 RAMB36（整个 xc7z020 只有 140 个，98.93% 全卡在这）。
// 拆法走过两代（三个数都在同一台 Vivado 上一次跑出来，凭据 `build/evidence/r90_fb_split_probe.txt`，
// 源与跑法在 `build/fb_split_probe/`）：
//   两块 32768 + 8192 ⇒ 覆盖 40960 字，白填 2560 字 = 5 个 tile ⇒ 实测 **80**（v6.5 到 r88 一直如此）
//   三块 32768 + 4096 + 2048 ⇒ 覆盖 38912 字，白填 512 字 ⇒ 实测 **75**（本文件用的这一版）
//   四块 32768 + 4096 + 1024 + 512 ⇒ 正好 38400，一块不填 ⇒ 实测 **74**
//   取三块不取四块：只多省 1 个 tile，却要多一级 64 位读选择 —— 换不到就该收手。
// 数据量本身要 67 个 tile（512×300×16 bit ÷ 36864），所以剩下的 8 个是"每块都得向上取整到 512 字"的代价。
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
    output wire [15:0] rd_data,
    output wire [63:0] rd_data64  // 同一个物理读口的原始字（不占第二个端口，只是少一层 mux）
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

    localparam WORDS = (W * H + 3) / 4;                  // 38400 个 64bit 字
    // 贪心拆：每次取"不超过剩余额的最大 2 的幂"，最后一块向上取整。
    // 38400 → 32768（余 5632）→ 4096（余 1536）→ 2048，合计 38912。
    localparam D0    = (1 << (bitsof(WORDS) - 1));       // 32768 = 2^15
    localparam REM1  = WORDS - D0;                       //  5632
    localparam D1    = (REM1 == 0) ? 1 : (1 << (bitsof(REM1) - 1));   //  4096 = 2^12
    localparam REM2  = REM1 - D1;                        //  1536
    localparam D2    = (REM2 == 0) ? 1 : (1 << bitsof(REM2 - 1));     //  2048 = 2^11

    (* ram_style = "block" *) reg [63:0] a0 [0:D0-1];
    (* ram_style = "block" *) reg [63:0] a1 [0:D1-1];
    (* ram_style = "block" *) reg [63:0] a2 [0:D2-1];

    wire [18:0] widx  = wr_addr;
    wire        w_s1  = (widx >= D0[18:0]);
    wire        w_s2  = (widx >= (D0[18:0] + D1[18:0]));

    always @(posedge wr_clk) begin
        if (wr_en && widx < WORDS[18:0]) begin
            if (!w_s1)               a0[widx] <= wr_data;
            else if (!w_s2)          a1[widx - D0[18:0]] <= wr_data;
            else                     a2[widx - D0[18:0] - D1[18:0]] <= wr_data;
        end
    end

    // 三块每拍都被读一次，真正的选择由 sel 完成——这样读延迟仍是 1 拍，
    // 且越界一侧的地址用掩码夹住，不会产生 X。
    wire [18:0] ridx  = rd_addr[18:2];
    wire        r_s1  = (ridx >= D0[18:0]);
    wire        r_s2  = (ridx >= (D0[18:0] + D1[18:0]));

    reg [63:0] q0, q1, q2;
    reg        sel1, sel2;
    reg [1:0]  sel_lane;
    reg        blank;

    always @(posedge rd_clk) begin
        q0 <= a0[ridx & (D0-1)];
        q1 <= a1[(ridx - D0[18:0]) & (D1-1)];
        q2 <= a2[(ridx - D0[18:0] - D1[18:0]) & (D2-1)];
        sel1   <= r_s1;
        sel2   <= r_s2;
        sel_lane <= rd_addr[1:0];
        blank    <= (rd_addr >= (W*H));             // 越界仍回黑，保持 v6.4 行为
    end

    wire [63:0] rd_q = sel2 ? q2 : (sel1 ? q1 : q0);
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
    assign rd_data64 = rd_q;
endmodule
