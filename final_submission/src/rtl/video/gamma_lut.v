`timescale 1ns/1ps
// 级 0：Gamma 查找表 —— 256 项 8-bit 表，PS 通过第二个控制字的通道 2 逐项写入。时钟域：像素域，读写都在
//   这里（控制位由 effect_ctrl 同步）。三通道共用一张表 ⇒ 复制三份 RAM 各 1W1R："一份三读"要额外读口，
//   复制三份则内容永远由同一个写口保证一致。用表不用幂函数：PL 里做 `in^(1/γ)` 要堆 DSP 或做对数/指数近似。
// 写入协议（spec §6b 的 D4 方案②）：先写 `idx`+`data`、下一次写把 `wr` **翻转**（不是脉冲，脉冲跨不到本域）
//   ⇒ PL 看边沿才写一项，地址与数据不必同时对齐（#36 那笔账的正面用法）。挂在**第 0 级**是左窗原图/右窗
//   处理图的一贯半屏对比语义；它**不加拍数**（分布式 RAM 非同步读出）⇒ LATENCY 常数不动（#54 那一类账）。
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
