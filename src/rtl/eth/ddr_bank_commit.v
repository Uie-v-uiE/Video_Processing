`timescale 1ns/1ps
// DDR 乒乓 bank 的「提交 / 换页」glue。
//
// 原来这段状态机写在 eth_udp_video_top 里，仿真只能靠 TB **抄一份**（tb_v6_pingpong
// 就是这么做的）——抄的那份永远不会因为真代码改错而变红，所以抽成本模块，
// 让 TB 直接例化上板的实现。
//
// 职责：frame_done（gmii 域）→ 3 级同步 + 边沿检测（axi 域）→ 请求换页 →
//       等打包器排空且**本帧数据已完整交付**→ 提交 completed_base + 翻转 bank。
//
// TAIL_GUARD=1 修的是 v6.4 遗留的「帧尾 4 字节偶发丢失」：旧判据只看打包器空
// （saver_idle 对 8192 深的 CDC 和它后面的读流水完全不可见），于是打包器一旦排空
// 就翻 bank，而本帧最后几个 16bit 还排在 CDC 里 —— 它们随后被写进**下一帧**的
// bank，刚提交的那块内存的帧尾 4 字节就停在旧值/0 上（板上 HDMI 右下角少 2 像素）。
// TAIL_GUARD=0 保留 v6.4 行为，仅供 A/B 对照复现。
module ddr_bank_commit #(
    parameter [31:0] BANK0      = 32'h1000_0000,
    parameter [31:0] BANK1      = 32'h1008_0000,
    parameter        TAIL_GUARD = 1'b1
)(
    input  wire        gmii_clk,        // frame_done 所在时钟域（RGMII 125 MHz）
    input  wire        axi_clk,         // 提交/换页所在域（HP0 100 MHz）
    input  wire        rst_n,
    input  wire        axi_rst_n,

    input  wire        frame_done,      // gmii_clk 域单拍脉冲（frame_reasm）

    input  wire        saver_idle,      // 打包器 + 在途 AXI 全部排空
    output wire [31:0] sav_base,        // 打包器当前写入的 bank
    output wire        pack_flush,      // = CDC 取到的 flush 标记 | 兜底 force_flush

    // CDC 交付状态：判「本帧的数据是否已经全部到达打包器」
    input  wire        cdc_empty,
    input  wire        cdc_rd,          // 读使能已发出、数据还没出来
    input  wire        cdc_d1_v,        // 读流水第 2 级有效
    input  wire        sav_en,          // 读流水第 3 级：正在写字
    input  wire        sav_flush,       // 读流水第 3 级：正在推 flush

    output reg  [31:0] completed_base,  // 交给显示侧的、已完整落位的 bank
    output reg         commit_pulse,
    output reg         switch_req,
    output reg         force_flush
);
    // ---- frame_done 跨域 ----
    reg frame_done_tog = 1'b0;
    always @(posedge gmii_clk or negedge rst_n) begin
        if (!rst_n) frame_done_tog <= 1'b0;
        else if (frame_done) frame_done_tog <= ~frame_done_tog;
    end
    (* ASYNC_REG = "TRUE" *) reg fd0, fd1, fd2;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) {fd2, fd1, fd0} <= 3'b0;
        else {fd2, fd1, fd0} <= {fd1, fd0, frame_done_tog};
    end
    wire fd_axi = fd1 ^ fd2;

    // 本帧的数据是否已经全部穿过 CDC：队空 + 读地址已发 + 两级读流水都空。
    wire tail_drained = cdc_empty && !cdc_rd && !cdc_d1_v && !sav_en && !sav_flush;
    wire commit_ok    = TAIL_GUARD ? (saver_idle && tail_drained) : saver_idle;

    reg bank = 1'b0;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            bank           <= 1'b0;
            completed_base <= BANK0;
            commit_pulse   <= 1'b0;
            switch_req     <= 1'b0;
            force_flush    <= 1'b0;
        end else begin
            commit_pulse <= 1'b0;
            if (fd_axi) begin
                switch_req  <= 1'b1;
                force_flush <= 1'b1;
            end
            if (switch_req && commit_ok) begin
                completed_base <= sav_base;
                bank           <= ~bank;
                commit_pulse   <= 1'b1;
                switch_req     <= 1'b0;
                force_flush    <= 1'b0;
            end
            if (saver_idle && !switch_req)
                force_flush <= 1'b0;
        end
    end

    assign sav_base   = bank ? BANK1 : BANK0;
    assign pack_flush = sav_flush | (force_flush && (TAIL_GUARD ? tail_drained : 1'b1));
endmodule
