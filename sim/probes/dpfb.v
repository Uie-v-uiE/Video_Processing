`timescale 1ns/1ps
// sim/probes/dpfb.v — 对照实验：**给显示帧缓存再加一个读口，RAMB36 会不会翻倍？**
//
// 为什么要探这个：想给缩放/旋转加双线性插值，每个输出像素要采
//   (sx,sy)、(sx+1,sy)、(sx,sy+1)、(sx+1,sy+1) 四个点。
// 横向两点是**免费**的 —— 现有帧缓存每拍读出的就是一个 64bit 字 = 4 个 RGB565
// 像素，现在只用掉其中 1 个 lane（`frame_buffer_w64.v:72-82`）。
// 真正缺的是**纵向那一行**：要么第二个读口，要么把两行搬进行缓存，要么把读口
// 跑在更快的时钟上分时读两次。
//
// 7 系列 RAMB36 只有 A/B 两个口。现在是「A 写 64bit + B 读 16bit」= 两个口用满
// ⇒ 第三个逻辑口理论上只能靠**复制阵列**实现，那会把 tile 数翻倍（80 → 160，
// 而全片只有 140、已用 90.5）。这组探针就是把这个"理论上"变成实测数字，
// 免得我拿架构常识当证据（R04 那次 128 vs 80 的教训：推断行为只能靠综合问）。
//
// 跑法见 sim/probes/probe4.tcl。判据：dp_v1 的 BRAM 数若等于 dp_v0 就可以走
// 双读口；若接近翻倍就必须走行缓存 / 250 MHz 分时读。

// ---------- V0：与生产版 frame_buffer_w64 同形（1 写 + 1 读，按 2 的幂拆两块）----
module dp_v0 #(parameter W = 512, parameter H = 300)(
    input  wire        wr_clk, input  wire wr_en,
    input  wire [18:0] wr_addr, input  wire [63:0] wr_data,
    input  wire        rd_clk, input  wire [18:0] rd_addr,
    output wire [15:0] rd_data
);
    localparam WORDS = (W * H + 3) / 4;          // 38400
    localparam D_LO  = 32768;                    // 2^15
    localparam D_HI  = 8192;
    (* ram_style = "block" *) reg [63:0] lo [0:D_LO-1];
    (* ram_style = "block" *) reg [63:0] hi [0:D_HI-1];
    wire        wr_hi = (wr_addr >= D_LO);
    always @(posedge wr_clk) begin
        if (wr_en && wr_addr < WORDS) begin
            if (wr_hi) hi[wr_addr - D_LO] <= wr_data;
            else       lo[wr_addr]        <= wr_data;
        end
    end
    wire [18:0] ridx = rd_addr[18:2];
    wire        r_hi = (ridx >= D_LO);
    reg [63:0] q_lo, q_hi; reg sel_hi; reg [1:0] sel_lane;
    always @(posedge rd_clk) begin
        q_lo <= lo[ridx & (D_LO-1)];  q_hi <= hi[(ridx-D_LO) & (D_HI-1)];
        sel_hi <= r_hi; sel_lane <= rd_addr[1:0];
    end
    wire [63:0] rd_q = sel_hi ? q_hi : q_lo;
    assign rd_data = (sel_lane==2'd0) ? rd_q[15:0]  : (sel_lane==2'd1) ? rd_q[31:16] :
                     (sel_lane==2'd2) ? rd_q[47:32] : rd_q[63:48];
endmodule

// ---------- V1：1 写 + 2 读（第二个读口独立地址，各自 lane mux）----------
module dp_v1 #(parameter W = 512, parameter H = 300)(
    input  wire        wr_clk, input  wire wr_en,
    input  wire [18:0] wr_addr, input  wire [63:0] wr_data,
    input  wire        rd_clk,
    input  wire [18:0] rd_addr_a, output wire [15:0] rd_data_a,
    input  wire [18:0] rd_addr_b, output wire [15:0] rd_data_b
);
    localparam WORDS = (W * H + 3) / 4;
    localparam D_LO  = 32768;
    localparam D_HI  = 8192;
    (* ram_style = "block" *) reg [63:0] lo [0:D_LO-1];
    (* ram_style = "block" *) reg [63:0] hi [0:D_HI-1];
    wire        wr_hi = (wr_addr >= D_LO);
    always @(posedge wr_clk) begin
        if (wr_en && wr_addr < WORDS) begin
            if (wr_hi) hi[wr_addr - D_LO] <= wr_data;
            else       lo[wr_addr]        <= wr_data;
        end
    end
    // --- 读口 A ---
    wire [18:0] ra = rd_addr_a[18:2];
    reg [63:0] qa_lo, qa_hi; reg [1:0] sa;
    always @(posedge rd_clk) begin
        qa_lo <= lo[ra & (D_LO-1)]; qa_hi <= hi[(ra-D_LO) & (D_HI-1)]; sa <= rd_addr_a[1:0];
    end
    wire [63:0] qa = (ra >= D_LO) ? qa_hi : qa_lo;   // 与生产版同形（用寄存的 sel 也可）
    assign rd_data_a = (sa==2'd0) ? qa[15:0]  : (sa==2'd1) ? qa[31:16] :
                       (sa==2'd2) ? qa[47:32] : qa[63:48];
    // --- 读口 B ---
    wire [18:0] rb = rd_addr_b[18:2];
    reg [63:0] qb_lo, qb_hi; reg [1:0] sb;
    always @(posedge rd_clk) begin
        qb_lo <= lo[rb & (D_LO-1)]; qb_hi <= hi[(rb-D_LO) & (D_HI-1)]; sb <= rd_addr_b[1:0];
    end
    wire [63:0] qb = (rb >= D_LO) ? qb_hi : qb_lo;
    assign rd_data_b = (sb==2'd0) ? qb[15:0]  : (sb==2'd1) ? qb[31:16] :
                       (sb==2'd2) ? qb[47:32] : qb[63:48];
endmodule

// ---------- V2：1 写 + 2 读，但第二个口只读 64bit 整字（不切 lane）----------
// 判别"读口宽度"是不是影响因素：如果 V2 和 V1 一样，说明代价来自端口数而不是位宽。
module dp_v2 #(parameter W = 512, parameter H = 300)(
    input  wire        wr_clk, input  wire wr_en,
    input  wire [18:0] wr_addr, input  wire [63:0] wr_data,
    input  wire        rd_clk,
    input  wire [18:0] rd_addr_a, output wire [63:0] rd_word_a,
    input  wire [18:0] rd_addr_b, output wire [63:0] rd_word_b
);
    localparam WORDS = (W * H + 3) / 4;
    localparam D_LO  = 32768;
    localparam D_HI  = 8192;
    (* ram_style = "block" *) reg [63:0] lo [0:D_LO-1];
    (* ram_style = "block" *) reg [63:0] hi [0:D_HI-1];
    wire        wr_hi = (wr_addr >= D_LO);
    always @(posedge wr_clk) begin
        if (wr_en && wr_addr < WORDS) begin
            if (wr_hi) hi[wr_addr - D_LO] <= wr_data;
            else       lo[wr_addr]        <= wr_data;
        end
    end
    reg [63:0] qa, qb;
    always @(posedge rd_clk) begin
        qa <= rd_addr_a[21] ? hi[rd_addr_a[18:2] & (D_HI-1)] : lo[rd_addr_a[18:2] & (D_LO-1)];
        qb <= rd_addr_b[21] ? hi[rd_addr_b[18:2] & (D_HI-1)] : lo[rd_addr_b[18:2] & (D_LO-1)];
    end
    assign rd_word_a = qa;
    assign rd_word_b = qb;
endmodule

// ---------- V3：把整帧复制两份、各给一个读口（对照组：这就是"翻倍"的坏主意）----------
module dp_v3 #(parameter W = 512, parameter H = 300)(
    input  wire        wr_clk, input  wire wr_en,
    input  wire [18:0] wr_addr, input  wire [63:0] wr_data,
    input  wire        rd_clk,
    input  wire [18:0] rd_addr_a, output wire [63:0] rd_word_a,
    input  wire [18:0] rd_addr_b, output wire [63:0] rd_word_b
);
    localparam D_LO = 32768, D_HI = 8192;
    (* ram_style = "block" *) reg [63:0] lo [0:D_LO-1];
    (* ram_style = "block" *) reg [63:0] hi [0:D_HI-1];
    (* ram_style = "block" *) reg [63:0] lo2 [0:D_LO-1];
    (* ram_style = "block" *) reg [63:0] hi2 [0:D_HI-1];
    wire wr_hi = (wr_addr >= D_LO);
    always @(posedge wr_clk)
        if (wr_en) begin
            if (wr_hi) begin hi[wr_addr-D_LO] <= wr_data; hi2[wr_addr-D_LO] <= wr_data; end
            else       begin lo[wr_addr]      <= wr_data; lo2[wr_addr]      <= wr_data; end
        end
    reg [63:0] qa, qb;
    always @(posedge rd_clk) begin
        qa <= lo[rd_addr_a[18:2] & (D_LO-1)];
        qb <= lo2[rd_addr_b[18:2] & (D_LO-1)];
    end
    assign rd_word_a = qa;
    assign rd_word_b = qb;
endmodule
