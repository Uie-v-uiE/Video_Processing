`timescale 1ns/1ps
// 级 0：Gamma 查找表 —— 256 项 8-bit 表，由 PS 通过第二个控制字的通道 2 逐项写入。
//
// 为什么是一张表而不是一个幂函数：`out = in^(1/γ)` 在 PL 里做幂要么堆 DSP、要么做
// 对数/指数近似（十几级流水），而**表本来就是这道题的标准答案** —— 屏厂给的 gamma 曲线
// 也不是解析式。代价只有 3×256×8 位的 LUTRAM。
//
// 为什么放在**整条链的最前面**（而不是最后）：
//   1. 左窗是原图、右窗是处理图，这是本设计一贯的"半屏对比"语义 —— gamma 挂在第 0 级，
//      `gamma 1.8` 一开就是左右明暗直接对比；挂在最后会被后面的二值化/形态学吃掉，
//      看着像"设了没反应"（proc_morph 文件头记过同类教训）。
//   2. 它**不加拍数**：分布式 RAM 是非同步读出 ⇒ `proc_pipeline.LATENCY` 不动。
//      这条重要 —— #54 那笔"延迟常数与真实拍数对不上"的账就是被"顺手加一级"加出来的。
//
// 三个通道共用同一张表 ⇒ 复制三份 RAM（每份 1 写 1 读）。"一份三读"要额外的读口，
// 复制三份则三份内容永远由同一个写口保证一致。
//
// 写入协议（spec §6b 的 D4 方案②）：PS 先写 `idx`+`data`（`wr` 不动），下一次写把 `wr` 翻转
// ⇒ PL 在本域看到 `wr` 的边沿时才写这一项。这样"地址"与"数据"不必同时对齐
// （与 `ps_publish` 的发布翻转同一套路子 —— ISSUES #36 那笔账的正面用法）。
module gamma_lut (
    input  wire        clk,                 // 像素域：读写都在这里（控制位由 effect_ctrl 同步过来）
    input  wire        rst_n,
    input  wire        en,                  // 0 = 旁路，逐位等于输入（台架第 1 条判据）
    input  wire        wr,                  // **翻转位**，不是脉冲（脉冲跨不到本域）
    input  wire [7:0]  idx,
    input  wire [7:0]  data,
    input  wire [15:0] din,                 // RGB565
    output wire [15:0] dout
);
    // 与 proc_binary / proc_morph 各写一遍同一套 5→8 / 6→8 扩展：不共用是故意的，
    // 三处公式必须能被独立核对，谁改了另一处会在"灰度图与 gamma 图对不上"时暴露。
    wire [4:0] r5 = din[15:11];
    wire [5:0] g6 = din[10:5];
    wire [4:0] b5 = din[4:0];
    wire [7:0] r8 = {r5, r5[4:2]};
    wire [7:0] g8 = {g6, g6[5:4]};
    wire [7:0] b8 = {b5, b5[4:2]};

    (* ram_style = "distributed" *) reg [7:0] tr [0:255];
    (* ram_style = "distributed" *) reg [7:0] tg [0:255];
    (* ram_style = "distributed" *) reg [7:0] tb [0:255];

    // 只在"这一拍的值与上一拍不同"时写一项。复位把 prev 与 wr 一起置 0 ——
    // 否则上电本身会被当成一次写事件（ISSUES #52 的根就是这个）。
    // prev 走复位而不是 `reg prev = 1'b0;`：后者是 SystemVerilog 写法，本工程按 Verilog-2001 编。
    reg prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) prev <= 1'b0;
        else        prev <= wr;
    end
    wire do_wr = rst_n && (wr !== prev);

    always @(posedge clk) begin
        if (do_wr) begin
            tr[idx] <= data;
            tg[idx] <= data;
            tb[idx] <= data;
        end
    end

    // 名字别用 `packed` —— 那是 SystemVerilog 关键字，xvlog 会把它当声明读
    // （r45 的 `edge` 是同一类坑，20 秒的 xvlog 就能抓出来）。
    wire [15:0] y16 = {tr[r8][7:3], tg[g8][7:2], tb[b8][7:3]};
    assign dout = en ? y16 : din;
endmodule
