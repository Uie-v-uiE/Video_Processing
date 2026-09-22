`timescale 1ns/1ps
// axi_frame_writer_gated v5.11
// v5 policy: BRAM writes ONLY when allow (all blanking after pipeline drain).
// Speed: direct BRAM write from AXI R when allow && skid empty (copy finishes
// inside one display frame → no motion ghosting).
// done only after every 64-bit word was written.
module axi_frame_writer_gated #(
    parameter IMG_W = 512,
    parameter IMG_H = 300,
    parameter BASE_ADDR = 32'h1000_0000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        start,
    input  wire [31:0] base_addr,
    input  wire        allow_wr,
    input  wire        abort,
    output reg         busy,
    output reg         done,
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
    output wire        m_axi_rready,
    output reg  [31:0] copy_cycles
);
    assign m_axi_arsize  = 3'b011;
    assign m_axi_arburst = 2'b01;

    localparam integer PIX_PER_BEAT = 4;
    localparam integer BEATS        = 16;
    localparam integer TOTAL_PIX    = IMG_W * IMG_H;
    localparam integer TOTAL_WORDS  = (TOTAL_PIX + PIX_PER_BEAT - 1) / PIX_PER_BEAT;
    localparam integer TOTAL_BURSTS = (TOTAL_WORDS + BEATS - 1) / BEATS;
    // 4 x 16-beat bursts in flight ≈ 64 beats, enough outstanding to cover
    // HP0/DDR read latency and hold ~1 beat/cycle through the 25-line window.
    localparam [2:0]   MAX_OUT      = 3'd4;
    localparam SK = 6;

    // skid 缓冲：与 R02 同一类问题——原先写和指针同在带异步复位的控制块里，
    // 综合报 Synth 8-4767「Block RAM or DRAM implementation is not possible」，
    // 64×83bit 全掉进触发器（约占整机剩余寄存器的一半）。改用已验证的分布式 RAM 写法。
    (* ram_style = "distributed" *) reg [18:0] sk_addr [0:(1<<SK)-1];
    (* ram_style = "distributed" *) reg [63:0] sk_data [0:(1<<SK)-1];
    reg [SK:0] sk_w, sk_r;
    wire [SK:0] sk_level = sk_w - sk_r;
    wire sk_empty = (sk_w == sk_r);
    wire sk_full  = (sk_level >= ((1<<SK)-1));

    // 异步读口（分布式 RAM 只有异步读）；同一地址被读写时读出旧值，
    // 与原来「数组在非阻塞块里读」的语义一致。
    wire [SK-1:0] sk_rid     = sk_r[SK-1:0];
    wire [18:0]   sk_addr_q  = sk_addr[sk_rid];
    wire [63:0]   sk_data_q  = sk_data[sk_rid];

    reg active;
    reg [31:0] base_r, burst_idx, r_pix, cyc, wr_words;
    reg [2:0]  outstanding;

    assign m_axi_rready = active && !sk_full;

    wire can_issue = active && allow_wr && !m_axi_arvalid && !abort
                     && (outstanding < MAX_OUT)
                     && (burst_idx < TOTAL_BURSTS)
                     && (sk_level <= ((1<<SK)-1-BEATS));

    wire r_hit     = m_axi_rvalid && m_axi_rready;
    wire do_direct = r_hit && allow_wr && sk_empty;
    wire do_skid   = r_hit && !do_direct;
    wire sk_drain  = active && allow_wr && !sk_empty && !do_direct;

    // 两个写入点（sk_drain 内与 do_skid 分支）的条件本来就完全相同（A&&do_skid | 
    // !A&&do_skid = do_skid），合并成一个写脉冲，并让这个数组写独占一个不带复位的
    // always 块 —— 这是 R02 探针实测出的唯一能被推断成 RAM 的形状。
    always @(posedge clk) begin
        if (do_skid) begin
            sk_addr[sk_w[SK-1:0]] <= r_pix[18:0];
            sk_data[sk_w[SK-1:0]] <= m_axi_rdata;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy<=0; done<=0; active<=0;
            fb_wr_en<=0; fb_wr_addr<=0; fb_wr_data<=0;
            m_axi_arvalid<=0; m_axi_araddr<=0; m_axi_arlen<=8'd15;
            base_r<=BASE_ADDR; burst_idx<=0; r_pix<=0; cyc<=0;
            outstanding<=0; sk_w<=0; sk_r<=0; copy_cycles<=0; wr_words<=0;
        end else begin
            fb_wr_en <= 0;
            done <= 0;
            if (active) cyc <= cyc + 1;
            if (fb_wr_en) wr_words <= wr_words + 1;

            if (!active) begin
                busy<=0; m_axi_arvalid<=0; outstanding<=0;
                if (enable && start) begin
                    active<=1; busy<=1;
                    base_r<=base_addr; burst_idx<=0; r_pix<=0; cyc<=0;
                    sk_w<=0; sk_r<=0; wr_words<=0;
                    if (allow_wr && TOTAL_BURSTS>0) begin
                        m_axi_araddr<=base_addr;
                        m_axi_arlen<=BEATS[7:0]-8'd1;
                        m_axi_arvalid<=1;
                        outstanding<=1;
                        burst_idx<=1;
                    end
                end
            end else if (abort) begin
                active<=0; busy<=0; done<=0;
                m_axi_arvalid<=0; outstanding<=0;
                sk_w<=0; sk_r<=0; r_pix<=0; wr_words<=0;
            end else begin
                if (can_issue) begin
                    m_axi_araddr  <= base_r + burst_idx * (BEATS * 8);
                    m_axi_arlen   <= BEATS[7:0]-8'd1;
                    m_axi_arvalid <= 1;
                    burst_idx     <= burst_idx + 1;
                    outstanding   <= outstanding + 1;
                end
                if (m_axi_arvalid && m_axi_arready) m_axi_arvalid <= 0;

                if (sk_drain) begin
                    fb_wr_en   <= 1;
                    fb_wr_addr <= sk_addr_q[18:2];
                    fb_wr_data <= sk_data_q;
                    sk_r <= sk_r + 1;
                    if (do_skid) begin
                        sk_w  <= sk_w + 1;
                        r_pix <= r_pix + PIX_PER_BEAT;
                        if (m_axi_rlast && outstanding!=0)
                            outstanding <= outstanding - 1;
                    end
                end else if (do_direct) begin
                    fb_wr_en   <= 1;
                    fb_wr_addr <= r_pix[18:2];
                    fb_wr_data <= m_axi_rdata;
                    r_pix <= r_pix + PIX_PER_BEAT;
                    if (m_axi_rlast && outstanding!=0)
                        outstanding <= outstanding - 1;
                end else if (do_skid) begin
                    sk_w  <= sk_w + 1;
                    r_pix <= r_pix + PIX_PER_BEAT;
                    if (m_axi_rlast && outstanding!=0)
                        outstanding <= outstanding - 1;
                end

                if ((wr_words >= TOTAL_WORDS) && sk_empty && !m_axi_arvalid
                    && outstanding==0 && !sk_drain && !fb_wr_en) begin
                    active<=0; busy<=0; done<=1;
                    copy_cycles<=cyc;
                end
            end
        end
    end
endmodule
