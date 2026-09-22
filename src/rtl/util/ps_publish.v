`timescale 1ns/1ps
// PS→PL "这一帧 DDR 写完了"的发布脉冲跨域 + 挂起。
//
// 为什么单独成模块：这段逻辑本身是一个异步握手（翻转位来自 axi_clk 域，消费在 clk_pix 域），
// 塞在 pl_video_top 里就只能靠"上板看有没有撕裂"来验；单独拿出来才能用台架把
// 相位扫一遍、把"一次发布 = 一次消费"钉死。
//
// 语义是**电平**而不是计数：连着发两次、PL 只消费一次 ⇒ 第二次被合并。
// 这是有意的：PS 每帧之间至少隔一个帧周期（本项目里 SD 读一帧 30~60 ms >> 16.8 ms），
// 真要合并也只是"少刷一帧"，不会撕裂；换成计数器就要多一套溢出/复位约定，收益为零。
module ps_publish (
    input  wire clk,        // 消费侧时钟（clk_pix）
    input  wire rst_n,
    input  wire tog,        // 来自其它时钟域的翻转位
    input  wire consume,    // 本拍愿意接收一次
    output reg  pend,       // 有未消费的发布请求
    output wire new_tog     // 本拍检测到新翻转（Verilog 里 edge 是保留字，不能当端口名）
);
    // 3 级：前两级打异步，第三级专门给"异拍出沿"用，保证 new_tog 两拍内稳定可被 consume 采样
    (* ASYNC_REG = "TRUE" *) reg m0, m1, m2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) {m2, m1, m0} <= 3'b0;
        else        {m2, m1, m0} <= {m1, m0, tog};
    end

    assign new_tog = m1 ^ m2;

    always @(posedge clk or negedge rst_n) begin
        // 顺序有意：new_tog 优先于 consume ⇒ "这拍刚到又这拍消费"时请求不会被吃掉
        if (!rst_n)          pend <= 1'b0;
        else if (new_tog)    pend <= 1'b1;
        else if (consume)    pend <= 1'b0;
    end
endmodule
