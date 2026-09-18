`timescale 1ns/1ps
// Minimal GMII RX MAC: strip preamble/SFD, output frame payload+FCS bytes.
// good_frame pulses when DV falls after a valid SFD-started frame (>=64B).
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
    output reg        m_good,   // end of frame, no ER, len>=64
    output reg        m_bad
);
    localparam [1:0] S_WAIT = 2'd0;
    localparam [1:0] S_PRE  = 2'd1;
    localparam [1:0] S_DATA = 2'd2;

    reg [1:0]  state;
    reg [15:0] cnt;
    reg        saw_sfd;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_WAIT;
            cnt <= 16'd0;
            saw_sfd <= 1'b0;
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
                    if (!gmii_rx_er && cnt >= 16'd64) begin
                        m_good <= 1'b1;
                    end else begin
                        m_bad <= 1'b1;
                    end
                end
                state <= S_WAIT;
                cnt <= 16'd0;
                saw_sfd <= 1'b0;
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
                        if (gmii_rx_er) m_bad <= 1'b1;
                    end
                    default: state <= S_WAIT;
                endcase
            end
        end
    end
endmodule
