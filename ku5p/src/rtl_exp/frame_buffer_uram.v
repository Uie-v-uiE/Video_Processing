`timescale 1ns/1ps
// 实验件（不进主线）：与 `src/rtl/video/frame_buffer_w64.v` 端口同形的 **UltraRAM** 版帧缓存。
//
// 为什么要有这个文件：`ku5p/README.md` §9 第 3 条写着"换 UltraRAM 值得量一次"，但那是个**算出来的**
// 结论（2,621,440 bit ÷ 294,912 bit = 8.89 ⇒ 下界 9 块），而"算出来"在我们这里从来不算证据
// （§5 那条 BRAM 算错 10 倍的复盘就是这么来的）。所以做一个开关能切过去的实验版，
// 把 tile 数与功耗**量出来**再写口径。
//
// 与 BRAM 版的三处刻意一致，否则比不了：
//   1) 同样按 2 的幂拆两块（32768 + 8192 个 64bit 字）—— 不然深度会被向上补到 2^16；
//   2) 同样**无写使能**（整字写）、同样 1 拍读延迟（输出寄存器）；
//      注意 URAM 不支持 byte-write-enable，所以这条不是偷懒而是必须；
//   3) 读写同域（KU5P 入口本来就是单时钟域）。
// 只有 `ram_style` 从 "block" 改成 UltraRAM 强制值。
//
// **2026-09-23 06:1x 实测结果（这个实验现在是"未收口"，不是"成功"）**：
//   1) 开关是有效的 —— `KU5P_FB=uram` 时综合确实例化了本模块（日志里能看到 synthesizing module）；
//   2) 但 Vivado 2025.2.1 拒绝了两种拼法：
//        WARNING [Synth 8-11376] The 'ram_style' set on 'lo' is ignored because
//        'ultramark' / 'ultraram' is an not a valid value. The default value 'auto' will be used.
//   3) 于是样式退回 `auto` 后**仍然全部落在 BRAM**：`Block RAM Tile = 72`、`URAM = 0`
//      ⇒ 至少量到一条有用事实：这份"40960 字 × 64 bit、1 写 1 读、输出带寄存器"的形状，
//      工具**不会自己**选 UltraRAM，必须给出正确的强制 token 或直接用 `URAM1240` 原语。
//   下一步（明天之后，两选一）：查 UG901 "Forcing RAM Inference" 那节的属性取值表拿到正确 token；
//   或者直接例化 `uram_ing12400`（Unisim，端口要对：64bit 需要两片级联还是单片 72bit 宽，看数据手册）。
//   §9 第 3 条那句"9 块 UltraRAM"因此仍然是**算出来的**，不是量出来的。
//
// 用法（不改动主线构建）：
//   KU5P_FB=uram vivado -mode batch -source ku5p/build/tcl/ku5p_build.tcl
// 关掉时这份文件根本不被 add_files，网表与冻结的 r23 那一版同形。
module frame_buffer_uram #(
    parameter W = 512,
    parameter H = 300
)(
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,   // 64-bit 字号 = pixel[18:2]
    input  wire [63:0] wr_data,

    input  wire        rd_clk,
    input  wire [18:0] rd_addr,   // 像素号
    output wire [15:0] rd_data
);
    function integer bitsof;
        input integer n;
        integer v;
        begin
            v = n; bitsof = 0;
            while (v > 0) begin bitsof = bitsof + 1; v = v >> 1; end
        end
    endfunction

    localparam WORDS = (W * H + 3) / 4;                        // 38400
    localparam D_LO  = (1 << (bitsof(WORDS) - 1));             // 32768
    localparam REM   = WORDS - D_LO;                           // 5632
    localparam D_HI  = (REM == 0) ? 1 : (1 << bitsof(REM));    // 8192

    (* ram_style = "ultramark" *) reg [63:0] lo [0:D_LO-1];
    (* ram_style = "ultramark" *) reg [63:0] hi [0:D_HI-1];

    wire [18:0] widx  = wr_addr;
    wire        wr_hi = (widx >= D_LO[19:0]);

    always @(posedge wr_clk) begin
        if (wr_en && widx < WORDS[19:0]) begin
            if (wr_hi) hi[(widx - D_LO[19:0]) & (D_HI-1)] <= wr_data;
            else       lo[widx]                           <= wr_data;
        end
    end

    wire [18:0] ridx  = rd_addr[18:2];
    wire        rd_hi = (ridx >= D_LO[19:0]);
    wire [18:0] r_off = ridx - D_LO[19:0];

    reg [63:0] q_lo, q_hi;
    always @(posedge rd_clk) begin
        q_lo <= lo[ridx & (D_LO-1)];
        q_hi <= hi[r_off & (D_HI-1)];
    end
    assign rd_data = rd_hi ? q_hi[(ridx[1:0]*16) +: 16]
                           : q_lo [(ridx[1:0]*16) +: 16];
endmodule
