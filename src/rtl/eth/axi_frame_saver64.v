`timescale 1ns/1ps
// AXI3 DDR writer v6.3 — AWLEN=0 + **写通道流水化**（不再逐字等 B 响应）。
//
// v6.2 之前每个 64bit 字都要走完 S_AW→S_W→S_B（等 B 回来才敢发下一个），
// 在途深度恒等于 1 ⇒ HP0 的写延迟（~40 拍，被显示拷贝抢端口时上百拍）直接
// 变成吞吐上限：100MHz/40 ≈ 2.5M 字/s ≈ 20 MB/s。上位机限到 15 MB/s 看似够，
// 但每次提交/换页时拷贝占住端口，平均速率就掉到 8~10 MB/s，于是**每包固定从
// 第 48 字节开始丢字**（板上 32bit 粒度回读实测：包首丢字率 1%，包尾 52~70%，
// 且 u32 内两个 16bit 经常不同帧 ⇒ 丢在 CDC 写侧门控，逐 16bit 空洞 = 拖影）。
// 加深缓冲（v6.2 把 CDC 做到 8192）治不了，因为瓶颈是**平均排空速率**不是深度。
//
// 现在：AW/W 同时挂出、各自握手，发完立刻取下一个字（≤2 拍/字 = 400 MB/s），
// B 响应只在 outst 计数里回收，永不阻塞数据通路。
module axi_frame_saver64 #(
    parameter BASE_ADDR = 32'h1000_0000,
    parameter FW = 9   // 512-entry packer FIFO。不可加深：q_addr/q_data 被综合成
                       // **触发器**（512×96bit ≈ 4.9 万 FDRE），FW=11 直接 DRC UTLZ-1。
                       // 深缓冲在 eth_udp_video_top 里 BRAM 实现的 CDC（8192 条）。
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire [31:0] base_addr,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,
    input  wire [15:0] wr_data,
    input  wire        flush,
    output wire        fifo_full,
    output wire        idle,
    output reg         busy,
    output wire [31:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    output wire [63:0] m_axi_wdata,
    output wire [7:0]  m_axi_wstrb,
    output wire        m_axi_wlast,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready
);
    assign m_axi_awlen   = 8'd0;
    assign m_axi_awsize  = 3'b011;
    assign m_axi_awburst = 2'b01;
    assign m_axi_wstrb   = 8'hFF;
    assign m_axi_wlast   = 1'b1;

    reg [31:0] q_addr [0:(1<<FW)-1];
    reg [63:0] q_data [0:(1<<FW)-1];
    reg [FW:0] wptr, rptr;
    assign fifo_full = (wptr[FW] != rptr[FW]) && (wptr[FW-1:0] == rptr[FW-1:0]);
    wire fifo_empty = (wptr == rptr);

    reg [18:0] cur_widx;
    reg [63:0] cur_data;
    reg        cur_dirty;

    // ---- v6.3 写通道流水化：AW/W 并行挂出，B 只回收计数 ----
    localparam [3:0] OST = 4'd8;          // 在途 beat 上限（够盖住 HP0 写延迟）
    reg        aw_wait, w_wait;           // 本 beat 的 AW / W 尚未被接收
    reg [3:0]  outst;                     // 已发出、B 未回的 beat 数
    reg [31:0] a_r;
    reg [63:0] d_r;
    wire       beat   = aw_wait || w_wait;
    wire       b_ok   = m_axi_bvalid && m_axi_bready;
    wire       have   = (rptr != wptr) && !beat && (outst < OST);

    assign m_axi_awvalid = aw_wait;
    assign m_axi_wvalid  = w_wait;
    assign m_axi_awaddr  = a_r;
    assign m_axi_wdata   = d_r;

    assign idle = enable && !cur_dirty && fifo_empty && !beat && (outst == 4'd0);

    wire [18:0] in_widx = wr_addr[18:2];
    wire        idx_chg = cur_dirty && (in_widx != cur_widx);

    reg [31:0] pack_base;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pack_base <= BASE_ADDR;
        else if (!cur_dirty) pack_base <= base_addr;
    end

    task automatic push_word;
        input [18:0] widx;
        input [63:0] data;
        input [31:0] base;
        begin
            if (!fifo_full) begin
                q_addr[wptr[FW-1:0]] <= base + {10'd0, widx, 3'b000};
                q_data[wptr[FW-1:0]] <= data;
                wptr <= wptr + 1'b1;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= 0; cur_widx <= 0; cur_data <= 0; cur_dirty <= 0;
        end else if (enable) begin
            if (wr_en) begin
                if (idx_chg || !cur_dirty) begin
                    if (idx_chg)
                        push_word(cur_widx, cur_data, pack_base);
                    cur_widx  <= in_widx;
                    case (wr_addr[1:0])
                        2'd0: cur_data <= {48'd0, wr_data};
                        2'd1: cur_data <= {32'd0, wr_data, 16'd0};
                        2'd2: cur_data <= {16'd0, wr_data, 32'd0};
                        default: cur_data <= {wr_data, 48'd0};
                    endcase
                    cur_dirty <= 1'b1;
                end else begin
                    case (wr_addr[1:0])
                        2'd0: cur_data[15:0]  <= wr_data;
                        2'd1: cur_data[31:16] <= wr_data;
                        2'd2: cur_data[47:32] <= wr_data;
                        default: cur_data[63:48] <= wr_data;
                    endcase
                end
            end else if (flush && cur_dirty) begin
                push_word(cur_widx, cur_data, pack_base);
                cur_dirty <= 1'b0;
            end
        end
    end

    // 每拍最多装载一个 beat；装载条件是「上一个 beat 的 AW 和 W 都已被接收」。
    // 握手成功的接收方若拉低 ready，valid 保持不动，直到各自被接收为止。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rptr <= 0; outst <= 0; busy <= 0;
            aw_wait <= 0; w_wait <= 0; a_r <= 0; d_r <= 0;
            m_axi_bready <= 0;
        end else begin
            m_axi_bready <= 1'b1;                 // B 通道永不反压，只回收计数
            if (have && !b_ok)      outst <= outst + 4'd1;
            // 只减不回绕：万一上游偶尔多回一个 B，回绕成 15 会让 have 永远不成立
            // （整条入包链就此卡死 = 板上「冻结」类症状），宁可少计也不要锁死。
            else if (!have && b_ok) outst <= (outst == 4'd0) ? 4'd0 : outst - 4'd1;

            if (have) begin
                a_r     <= q_addr[rptr[FW-1:0]];
                d_r     <= q_data[rptr[FW-1:0]];
                rptr    <= rptr + 1'b1;
                aw_wait <= 1'b1;
                w_wait  <= 1'b1;
            end else begin
                if (aw_wait && m_axi_awready) aw_wait <= 1'b0;
                if (w_wait  && m_axi_wready)  w_wait  <= 1'b0;
            end
            busy <= !fifo_empty || beat || (outst != 4'd0);
        end
    end
endmodule
