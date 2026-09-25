`timescale 1ns/1ps
// Angle control: KEY1 +1°, KEY2 -1°, wrap 0..359.
//
// V9-3（用户 2026-09-25：「增加一个 Auto 旋转模式，让它自己在那转」+「我们人可以控制的是
// 旋转的速度或角度」）：加三个口 —— `frame_tgl`（每个显示帧翻一次，像素域产生）、
// `auto_en`、`speed[2:0]`（= 每帧走几个度，0 表示钉住）。
//
// ⚠ **为什么步进必须挂在帧边界上**：`angle` 是 zoom_mapper 里两张三角表的**索引**，
//   而 mapper 是逐像素组合地吃它的。帧中间换角度 = 这一帧上半与下半用两个不同的角 ⇒
//   画面在换的那一行错开一下。以前只有按键会改角度（人手一次几毫秒、且没人拿它做逐帧动作），
//   所以这件事从来没暴露过；今天它每帧都要换，就必须钉在消隐里。
// ⚠ **为什么 `frame_tgl` 是翻转位而不是脉冲**：#36 那一课 —— 1 拍的脉冲跨时钟域会被整个吃掉。
//   顶层为它单起一个翻转触发器（不共用 `sof_tgl`/`z_hb_tog`），因为发射触发器扇出到两组
//   目的域同步器会被 cdc.rpt 判 CDC-11 Critical（同一个文件里为这件事红过两次：#65、r54 构建 #34）。
//   本模块吃的是 sys_clk（50 MHz 输入时钟），脉冲来的是 clk_pix（MMCM 的另一路）⇒ 真跨域，
//   同步器放在**这里**（谁拥有时基谁负责同步），顶层不许再自己采一遍。
module angle_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       key_inc,
    input  wire       key_dec,
    input  wire       frame_tgl,      // 每显示帧翻一次（clk_pix 域产生）
    input  wire       auto_en,
    input  wire [2:0] speed,          // 度/帧；0 = 自动开着但不走
    output reg  [8:0] angle,
    output wire       rotate_active
);
    assign rotate_active = (angle != 9'd0);

    (* ASYNC_REG = "TRUE" *) reg [2:0] fs_s;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) fs_s <= 3'b0;
        else        fs_s <= {fs_s[1:0], frame_tgl};
    end
    wire fs_edge = fs_s[1] ^ fs_s[2];          // 每次帧首恰好一拍（sys_clk 域）

    // 一帧最多走 7°：360 = 7·51 + 3，所以取模要用"减 360"而不是"到 359 就回 0"，
    // 否则每圈会在回绕处丢几度（转速快的时候肉眼看得出那一顿）。
    wire [9:0] up        = {1'b0, angle} + {7'd0, speed};
    wire [8:0] wrap_up   = (up >= 10'd360) ? (up - 10'd360) : up[8:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            angle <= 9'd0;
        else if (key_inc)
            angle <= (angle == 9'd359) ? 9'd0 : (angle + 9'd1);
        else if (key_dec)
            angle <= (angle == 9'd0) ? 9'd359 : (angle - 9'd1);
        else if (auto_en && fs_edge && (speed != 3'd0))
            angle <= wrap_up;
    end
endmodule
