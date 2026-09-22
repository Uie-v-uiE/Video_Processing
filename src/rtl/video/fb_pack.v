`timescale 1ns/1ps
// 16bit 像素流 → 64bit（4 像素）字，并处理"帧/包末尾没凑满一格"的落盘。
//
// 为什么单独成模块：这是 KU5P 顶层里**唯一新写的**数据通路逻辑
// （Zynq 侧同样的活由 dc_fifo + 打包器做，那些已经有台架），
// 而它的错法很隐蔽：末尾 1~3 个像素不落盘 ⇒ 每行尾部黑一块；
// 落盘地址算错 ⇒ 整帧错位。所以它必须能被单独喂流、单独判对错。
//
// 约定：输入是"像素号 + 像素值"的写请求（与 `frame_reasm` 的输出同形），
// 输出是"字地址 + 64bit 字"的写请求（与 `frame_buffer_w64` 的写口同形）。
// 像素号允许**非连续**（拼帧本来就是乱序到达的），所以不能靠"数满 4 个"来判断，
// 必须按 `px_addr[1:0]` 落在哪个车道上决定 —— 这是本模块真正的难点，也是台架要盯的点。
module fb_pack (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               px_en,      // 一个 16bit 像素写请求
    input  wire [18:0]        px_addr,    // 像素号
    input  wire [15:0]        px_data,
    input  wire               flush,      // 一包/一帧边界：把没凑满的字写出去
    output reg                wr_en,
    output reg  [18:0]        wr_addr,    // 字地址 = 像素号 >> 2
    output reg  [63:0]        wr_data
);
    reg [63:0] lane_q;
    reg [1:0]  lane_fill;                 // 当前字里已经存了几条车道（0=空）
    reg [18:0] cur_word;

    // 换字时旧内容必须先作废：台架抓到过这个 bug —— 若一个字的**第一个**到的像素就是车道 3
    // （像素号乱序到达，或刚好从车道 3 起头），整字路径会把 lane_q 里**上一个字**残留的
    // 低 48 bit 一起写出去。base 就是"本拍真正应该继承的 lanes"。
    wire [63:0] base = (px_addr[18:2] != cur_word || lane_fill == 2'd0) ? 64'd0 : lane_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_en <= 1'b0; wr_addr <= 0; wr_data <= 64'd0;
            lane_q <= 64'd0; lane_fill <= 2'd0; cur_word <= 0;
        end else begin
            wr_en <= 1'b0;
            if (px_en) begin
                if (px_addr[18:2] != cur_word || lane_fill == 2'd0) begin
                    // 换字了：旧字若非空，先按"跳道写入"处理会丢数据 ——
                    // 这里选择**先把旧字原样落盘**（缺的车道保持上一次的值由调用方保证无意义），
                    // 再把 lane 清零重新填。真实拼帧里跨字只发生在正常 +1 递增时，
                    // 非递增的跳变只可能来自丢包，那种字本来就不完整。
                    if (lane_fill != 2'd0) begin
                        wr_en   <= 1'b1;
                        wr_addr <= cur_word;
                        wr_data <= lane_q;
                    end
                    lane_q   <= 64'd0;
                    cur_word <= px_addr[18:2];
                    lane_fill <= 2'd0;
                end
                case (px_addr[1:0])
                    2'd0:    begin lane_q[15:0]  <= px_data; lane_fill <= 2'd1; end
                    2'd1:    begin lane_q[31:16] <= px_data; lane_fill <= 2'd2; end
                    2'd2:    begin lane_q[47:32] <= px_data; lane_fill <= 2'd3; end
                    default: begin
                        wr_en    <= 1'b1;
                        wr_addr  <= px_addr[18:2];
                        wr_data  <= {px_data, base[47:0]};     // 用 base，不用 lane_q：见上面注释
                        lane_q   <= 64'd0;
                        lane_fill <= 2'd0;
                    end
                endcase
            end else if (flush && lane_fill != 2'd0) begin
                wr_en   <= 1'b1;
                wr_addr <= cur_word;
                wr_data <= lane_q;
                lane_fill <= 2'd0;
            end
        end
    end
endmodule
