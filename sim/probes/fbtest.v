`timescale 1ns/1ps
// Out-of-context probe: 同样的 512x300 RGB565 帧缓存，哪种写法 RAMB36 用得少？
// 现状 u_fb = 128 RAMB36，而 512*300*16bit = 2.4576Mb 的理论下限只有 67 个 tile。

// V0: 与 frame_buffer_w64 完全一致（数组深度 = 38400，地址总线 19bit/17bit）
module fb_v0 #(parameter W = 512, parameter H = 300)(
    input  wire        wr_clk, input  wire wr_en,
    input  wire [18:0] wr_addr, input wire [63:0] wr_data,
    input  wire        rd_clk, input  wire [18:0] rd_addr,
    output reg  [15:0] rd_data);
    localparam WORDS = (W * H + 3) / 4;
    (* ram_style = "block" *) reg [63:0] mem [0:WORDS-1];
    always @(posedge wr_clk)
        if (wr_en && wr_addr < WORDS) mem[wr_addr] <= wr_data;
    reg [63:0] rd_q; reg [1:0] rd_sel;
    always @(posedge rd_clk) begin
        if (rd_addr < (W*H)) begin rd_q <= mem[rd_addr[18:2]]; rd_sel <= rd_addr[1:0]; end
        else begin rd_q <= 64'd0; rd_sel <= 2'd0; end
    end
    always @(*) rd_data = (rd_sel==2'd0) ? rd_q[15:0]  : (rd_sel==2'd1) ? rd_q[31:16] :
                          (rd_sel==2'd2) ? rd_q[47:32] : rd_q[63:48];
endmodule

// V1: 深度取 2 的幂（65536）——用来判别「是不是地址位宽决定了填充量」
module fb_v1 #(parameter W = 512, parameter H = 300)(
    input  wire        wr_clk, input  wire wr_en,
    input  wire [18:0] wr_addr, input wire [63:0] wr_data,
    input  wire        rd_clk, input  wire [18:0] rd_addr,
    output reg  [15:0] rd_data);
    localparam WORDS = (W * H + 3) / 4;
    (* ram_style = "block" *) reg [63:0] mem [0:65535];
    always @(posedge wr_clk)
        if (wr_en && wr_addr < WORDS) mem[wr_addr] <= wr_data;
    reg [63:0] rd_q; reg [1:0] rd_sel;
    always @(posedge rd_clk) begin
        if (rd_addr < (W*H)) begin rd_q <= mem[{1'b0,rd_addr[17:2]}]; rd_sel <= rd_addr[1:0]; end
        else begin rd_q <= 64'd0; rd_sel <= 2'd0; end
    end
    always @(*) rd_data = (rd_sel==2'd0) ? rd_q[15:0]  : (rd_sel==2'd1) ? rd_q[31:16] :
                          (rd_sel==2'd2) ? rd_q[47:32] : rd_q[63:48];
endmodule

// V2: 深度向上取到 1024 的整数倍（38912），看综合器是否肯按 38 列铺
module fb_v2 #(parameter W = 512, parameter H = 300)(
    input  wire        wr_clk, input  wire wr_en,
    input  wire [18:0] wr_addr, input wire [63:0] wr_data,
    input  wire        rd_clk, input  wire [18:0] rd_addr,
    output reg  [15:0] rd_data);
    localparam WORDS  = (W * H + 3) / 4;          // 38400
    localparam AWORDS = ((WORDS + 1023) / 1024) * 1024;   // 38912
    (* ram_style = "block" *) reg [63:0] mem [0:AWORDS-1];
    always @(posedge wr_clk)
        if (wr_en && wr_addr < WORDS) mem[wr_addr] <= wr_data;
    reg [63:0] rd_q; reg [1:0] rd_sel;
    always @(posedge rd_clk) begin
        if (rd_addr < (W*H)) begin rd_q <= mem[rd_addr[18:2]]; rd_sel <= rd_addr[1:0]; end
        else begin rd_q <= 64'd0; rd_sel <= 2'd0; end
    end
    always @(*) rd_data = (rd_sel==2'd0) ? rd_q[15:0]  : (rd_sel==2'd1) ? rd_q[31:16] :
                          (rd_sel==2'd2) ? rd_q[47:32] : rd_q[63:48];
endmodule

// V3: 4 个 16bit 宽 bank 交织（bank = 像素低 2 位），读侧 4 路并读 + mux
module fb_v3 #(parameter W = 512, parameter H = 300)(
    input  wire        wr_clk, input  wire wr_en,
    input  wire [18:0] wr_addr, input wire [63:0] wr_data,
    input  wire        rd_clk, input  wire [18:0] rd_addr,
    output reg  [15:0] rd_data);
    localparam WORDS = (W * H + 3) / 4;           // 38400 个 64bit 字
    localparam BDEPTH = WORDS;                     // 每个 bank 38400 个 16bit 像素
    (* ram_style = "block" *) reg [15:0] b0 [0:BDEPTH-1];
    (* ram_style = "block" *) reg [15:0] b1 [0:BDEPTH-1];
    (* ram_style = "block" *) reg [15:0] b2 [0:BDEPTH-1];
    (* ram_style = "block" *) reg [15:0] b3 [0:BDEPTH-1];
    always @(posedge wr_clk) if (wr_en) begin
        b0[wr_addr] <= wr_data[15:0];
        b1[wr_addr] <= wr_data[31:16];
        b2[wr_addr] <= wr_data[47:32];
        b3[wr_addr] <= wr_data[63:48];
    end
    reg [15:0] q0,q1,q2,q3; reg [1:0] sel;
    always @(posedge rd_clk) begin
        if (rd_addr < (W*H)) begin
            q0 <= b0[rd_addr[18:2]]; q1 <= b1[rd_addr[18:2]];
            q2 <= b2[rd_addr[18:2]]; q3 <= b3[rd_addr[18:2]];
            sel <= rd_addr[1:0];
        end else begin q0<=0; q1<=0; q2<=0; q3<=0; sel<=0; end
    end
    always @(*) rd_data = (sel==2'd0) ? q0 : (sel==2'd1) ? q1 : (sel==2'd2) ? q2 : q3;
endmodule

// V4: 只保留 32bit 宽的写入口做对照（判断「位宽」是不是主因）
module fb_v4 #(parameter W = 512, parameter H = 300)(
    input  wire        wr_clk, input  wire wr_en,
    input  wire [18:0] wr_addr, input wire [31:0] wr_data,
    input  wire        rd_clk, input  wire [18:0] rd_addr,
    output reg  [15:0] rd_data);
    localparam WORDS = (W * H + 3) / 4;
    (* ram_style = "block" *) reg [31:0] mem [0:WORDS-1];
    always @(posedge wr_clk) if (wr_en) mem[wr_addr] <= wr_data;
    reg [31:0] rd_q; reg rd_sel;
    always @(posedge rd_clk) begin
        rd_q <= mem[rd_addr[18:1]]; rd_sel <= rd_addr[0];
    end
    always @(*) rd_data = rd_sel ? rd_q[31:16] : rd_q[15:0];
endmodule

module fbtest_top (
    input wire wr_clk, input wire rd_clk, input wire wr_en,
    input wire [18:0] wr_addr, input wire [63:0] wr_data,
    input wire [18:0] rd_addr,
    output wire [15:0] o0, o1, o2, o3, o4);
    fb_v0 u0(.wr_clk(wr_clk),.wr_en(wr_en),.wr_addr(wr_addr),.wr_data(wr_data),
             .rd_clk(rd_clk),.rd_addr(rd_addr),.rd_data(o0));
    fb_v1 u1(.wr_clk(wr_clk),.wr_en(wr_en),.wr_addr(wr_addr),.wr_data(wr_data),
             .rd_clk(rd_clk),.rd_addr(rd_addr),.rd_data(o1));
    fb_v2 u2(.wr_clk(wr_clk),.wr_en(wr_en),.wr_addr(wr_addr),.wr_data(wr_data),
             .rd_clk(rd_clk),.rd_addr(rd_addr),.rd_data(o2));
    fb_v3 u3(.wr_clk(wr_clk),.wr_en(wr_en),.wr_addr(wr_addr),.wr_data(wr_data),
             .rd_clk(rd_clk),.rd_addr(rd_addr),.rd_data(o3));
    fb_v4 u4(.wr_clk(wr_clk),.wr_en(wr_en),.wr_addr(wr_addr),.wr_data(wr_data[31:0]),
             .rd_clk(rd_clk),.rd_addr(rd_addr),.rd_data(o4));
endmodule

// V5: 2 个 2 的幂块（32768 + 8192 覆盖 38400 个字），消掉深度填充
module fb_v5 #(parameter W = 512, parameter H = 300)(
    input  wire        wr_clk, input  wire wr_en,
    input  wire [18:0] wr_addr, input wire [63:0] wr_data,
    input  wire        rd_clk, input  wire [18:0] rd_addr,
    output reg  [15:0] rd_data);
    localparam WORDS = (W * H + 3) / 4;         // 38400
    localparam D_LO  = 32768;                   // 2^15
    localparam D_HI  = 8192;                    // ceil_pow2(38400-32768=5632)
    (* ram_style = "block" *) reg [63:0] lo [0:D_LO-1];
    (* ram_style = "block" *) reg [63:0] hi [0:D_HI-1];
    wire wr_hi = (wr_addr >= D_LO);
    always @(posedge wr_clk) if (wr_en && wr_addr < WORDS) begin
        if (wr_hi) hi[wr_addr-D_LO] <= wr_data; else lo[wr_addr] <= wr_data;
    end
    wire [18:0] ridx = rd_addr[18:2];
    reg hi_hit;
    always @(posedge rd_clk) hi_hit <= (ridx >= D_LO);
    reg [63:0] ql, qh; reg [1:0] sel;
    always @(posedge rd_clk) begin
        ql <= lo[ridx];                    // 两块的地址都在各自范围内
        qh <= hi[ridx - D_LO];
        sel <= rd_addr[1:0];
    end
    reg [63:0] rd_q;
    always @(posedge rd_clk) rd_q = hi_hit ? qh : ql;
    always @(*) rd_data = (sel==2'd0) ? rd_q[15:0]  : (sel==2'd1) ? rd_q[31:16] :
                          (sel==2'd2) ? rd_q[47:32] : rd_q[63:48];
endmodule
