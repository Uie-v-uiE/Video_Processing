`timescale 1ns/1ps
// zoom_snap —— 把"像素域这一帧真正在用的缩放状态"打包成一条**准静态总线**并配上合法的跨域沿。
//
// 为什么需要它（V8-8 的最后一跳，任务 #45）：GPIO 回读 zsel/zman 只能证明"PS 写了那一位"，
// 证明不了 13 级同步链把它送到了像素域、更证明不了据此算出的 inv_scale 是对的。
// 这一口把因果链末端（收到的档号 + 算出的量）交给 snap_cross 搬到 axi 域 ⇒ lane23 可机器判定。
//
// 两条不变量（台架 tb_v95 逐条对着它们判，见 sim/tb_v95_zoom_snap.v）：
//   ① `bus` 只在帧首整拍换，换完至少保持一帧（≈16.7 ms）⇒ 满足 snap_cross 的"准静态总线"前提；
//   ② `bus_tog` 每**一次真实变化**恰好翻一次，且翻在总线已经稳定之后
//      （晚 8 个像素周期 ≈318 ns）——早一拍都不行：那样发的是"上一帧的值"，
//      目的域会永久落后一档，末态检查（写了 5 档就必须读到 5 档）会红。
// 不变化时不发沿：呼吸档每帧都在动，那属于 zoom_active=1 的正常路径，见 ② 的计数判据。
module zoom_snap (
    input  wire        pix_clk,
    input  wire        pix_rst_n,
    input  wire        frame_start,   // 像素域单拍脉冲：一帧开始
    input  wire        zman,          // 手动旗标（同步链的末端，不是 GPIO 原值）
    input  wire [2:0]  zsel,          // 收到的档号
    input  wire [2:0]  zoom_code,     // OSD 画的"最近一档"
    input  wire        zoom_active,   // 这一帧是否在缩放
    input  wire        zoom_dir,      // 呼吸方向（自动档才有意义）
    input  wire [9:0]  inv_scale,     // 真正喂给 zoom_mapper 的 Q8 倒数
    output reg  [18:0] bus,
    output reg         bus_tog
);
    // 位序 = lane23 的位序（去掉 axi 侧的 alive 位）：{zman, zsel, zoom_code, active, dir, inv}
    wire [18:0] in_bus = {zman, zsel, zoom_code, zoom_active, zoom_dir, inv_scale};

    reg       pend;       // 这一帧换了值，等着发沿
    reg [7:0] dly;        // 帧首脉冲往里走，第 8 拍 = 总线必定稳定的时刻

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            bus <= 19'd0; bus_tog <= 1'b0; pend <= 1'b0; dly <= 8'd0;
        end else begin
            dly <= {dly[6:0], frame_start};
            if (frame_start) begin
                pend    <= (in_bus != bus);     // 与总线同一拍记账：没换值就一个沿都不发
                bus     <= in_bus;
            end
            if (dly[7] && pend) begin
                bus_tog <= ~bus_tog;            // 捕获后第 8 拍才发沿：Z4 卡的就是这一拍
                pend    <= 1'b0;
            end
        end
    end
endmodule
