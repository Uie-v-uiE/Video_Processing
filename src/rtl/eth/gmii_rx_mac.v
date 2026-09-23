`timescale 1ns/1ps
// Minimal GMII RX MAC: strip preamble/SFD, output frame payload+FCS bytes.
// good_frame pulses when DV falls after a valid SFD-started frame (>=64B).
//
// V7.9.5（ISSUES #38 第 1 步）：**自己算 FCS-32**。原来 `m_good` 只判"长度 ≥64 且没有 ER"，
// 而两个板的 RGMII 收侧**根本没有 ER 这根线**（RX_CTL 在 rgmii_rx.v 里只当 gmii_rx_dv 用，
// RGMII 本身也只有 4 数据 + 1 控制，没有 GMII 的 RX_ER 通道）—— 所以"没有 ER"恒真，
// 收侧实际上**没有任何错误源**，这才是顶层 `p_good` 被硬接 1 的真实原因。
// ⇒ 唯一的错误源得自己造：把整帧（DA..FCS[3]）喂给发送侧同一个 `crc32_d8`，
//   一帧算完留下的**残值**是常数（内容无关），拿它当判据。
//   残值常数与"这个常数确实是内容无关的"两件事都由 `sim/tb_v795_rx_fcs.v` 量出来并钉住：
//   台架里的帧是用**独立实现**（标准反射算法 0xEDB88320，出处见那个文件头）算的 FCS，
//   如果本模块的约定不是标准以太网，两种不同内容的帧就会得到两个不同的残值 ⇒ 台架立刻红。
module gmii_rx_mac (
    input  wire       clk,      // 125 MHz GMII clock (from rgmii_rx domain)
    input  wire       rst_n,
    input  wire [7:0] gmii_rxd,
    input  wire       gmii_rx_dv,
    input  wire       gmii_rx_er,
    output reg  [7:0] m_data,
    output reg        m_valid,
    output reg        m_sof,    // first payload byte (DA[0])
    output reg        m_eof,    // last byte (FCS[3])
    output reg        m_good,   // end of frame, no ER, len>=64, FCS 残值正确
    output reg        m_bad
);
    // 整帧（含 4 字节 FCS）过完 crc32_d8 之后的残值。由台架实测得到，不要凭记忆改。
    localparam [31:0] FCS_RESIDUE = 32'h42_23_AD_77;
    // ↑ 实测值，不是推算值：`sim/tb_v795_rx_fcs.v` 用两套独立实现造帧再量出来的
    //   （第一版我凭印象写了一个数，被那条 T5 判据当场拦下）。

    localparam [1:0] S_WAIT = 2'd0;
    localparam [1:0] S_PRE  = 2'd1;
    localparam [1:0] S_DATA = 2'd2;

    reg [1:0]  state;
    reg [15:0] cnt;
    reg        saw_sfd;
    reg        er_seen;                       // 一帧内是否出现过 ER（RGMII 上恒 0，留着兼容 GMII）

    // ---- FCS-32：与发送侧同一个模块、同一套约定 ----
    wire        in_data = (state == S_DATA) && gmii_rx_dv;
    wire [31:0] crc_q;
    crc32_d8 u_crc_rx (
        .clk     (clk),
        .rst_n   (rst_n),
        .data    (gmii_rxd),
        .crc_en  (in_data),                  // 每个数据字节（含 FCS 那 4 个）都累加
        .crc_clr ((state == S_PRE) && gmii_rx_dv && (gmii_rxd == 8'hD5)),
                                             // 只在 SFD 那一拍清，早于第一个数据字节 ——
                                             // 若在第一个数据字节当拍清，crc_clr 优先级会**吞掉第 0 字节**
        .crc_data(crc_q),
        .crc_next()                          // 本模块不用下一拍值（发送侧才用它输出 FCS）
    );
    wire fcs_ok = (crc_q == FCS_RESIDUE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_WAIT;
            cnt <= 16'd0;
            saw_sfd <= 1'b0;
            er_seen <= 1'b0;
            m_data <= 8'd0;
            m_valid <= 1'b0;
            m_sof <= 1'b0;
            m_eof <= 1'b0;
            m_good <= 1'b0;
            m_bad <= 1'b0;
        end else begin
            m_valid <= 1'b0;
            m_sof   <= 1'b0;
            m_eof   <= 1'b0;
            m_good  <= 1'b0;
            m_bad   <= 1'b0;

            if (!gmii_rx_dv) begin
                if (state == S_DATA) begin
                    // 帧尾判定：长度、ER、FCS 三个条件都要过才算好帧
                    if (!er_seen && !gmii_rx_er && (cnt >= 16'd64) && fcs_ok) begin
                        m_good <= 1'b1;
                    end else begin
                        m_bad <= 1'b1;
                    end
                end
                state <= S_WAIT;
                cnt <= 16'd0;
                saw_sfd <= 1'b0;
                er_seen <= 1'b0;
            end else begin
                case (state)
                    S_WAIT: begin
                        if (gmii_rxd == 8'h55) begin
                            state <= S_PRE;
                            cnt <= 16'd1;
                        end
                    end
                    S_PRE: begin
                        if (gmii_rxd == 8'hD5) begin
                            state <= S_DATA;
                            cnt <= 16'd0;
                            saw_sfd <= 1'b1;
                        end else if (gmii_rxd == 8'h55) begin
                            cnt <= cnt + 16'd1;
                        end else begin
                            state <= S_WAIT;
                            cnt <= 16'd0;
                        end
                    end
                    S_DATA: begin
                        m_data  <= gmii_rxd;
                        m_valid <= 1'b1;
                        if (cnt == 16'd0) m_sof <= 1'b1;
                        cnt <= cnt + 16'd1;
                        if (gmii_rx_er) er_seen <= 1'b1;
                    end
                    default: state <= S_WAIT;
                endcase
            end
        end
    end
endmodule
