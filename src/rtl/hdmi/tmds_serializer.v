`timescale 1ns/1ps
// 10:1 OSERDESE2 cascade (UG471): DATA_WIDTH=10 requires DATA_RATE_OQ=DDR
// Master D1-D8 + Slave D3/D4, Slave SHIFTOUT -> Master SHIFTIN
module tmds_serializer (
    input  wire clk_pix,
    input  wire clk_pix5x,
    input  wire rst_n,
    input  wire [9:0] din,
    output wire data_p,
    output wire data_n
);
    wire shift1, shift2;
    wire serq;

    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .SERDES_MODE    ("MASTER"),
        .TRISTATE_WIDTH (1),
        .TBYTE_CTL      ("FALSE"),
        .TBYTE_SRC      ("FALSE")
    ) u_master (
        .OFB        (),
        .OQ         (serq),
        .SHIFTOUT1  (),
        .SHIFTOUT2  (),
        .TBYTEOUT   (),
        .TFB        (),
        .TQ         (),
        .CLK        (clk_pix5x),
        .CLKDIV     (clk_pix),
        .D1         (din[0]),
        .D2         (din[1]),
        .D3         (din[2]),
        .D4         (din[3]),
        .D5         (din[4]),
        .D6         (din[5]),
        .D7         (din[6]),
        .D8         (din[7]),
        .OCE        (1'b1),
        .RST        (~rst_n),
        .SHIFTIN1   (shift1),
        .SHIFTIN2   (shift2),
        .T1         (1'b0),
        .T2         (1'b0),
        .T3         (1'b0),
        .T4         (1'b0),
        .TBYTEIN    (1'b0),
        .TCE        (1'b0)
    );

    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .SERDES_MODE    ("SLAVE"),
        .TRISTATE_WIDTH (1),
        .TBYTE_CTL      ("FALSE"),
        .TBYTE_SRC      ("FALSE")
    ) u_slave (
        .OFB        (),
        .OQ         (),
        .SHIFTOUT1  (shift1),
        .SHIFTOUT2  (shift2),
        .TBYTEOUT   (),
        .TFB        (),
        .TQ         (),
        .CLK        (clk_pix5x),
        .CLKDIV     (clk_pix),
        .D1         (1'b0),
        .D2         (1'b0),
        .D3         (din[8]),
        .D4         (din[9]),
        .D5         (1'b0),
        .D6         (1'b0),
        .D7         (1'b0),
        .D8         (1'b0),
        .OCE        (1'b1),
        .RST        (~rst_n),
        .SHIFTIN1   (1'b0),
        .SHIFTIN2   (1'b0),
        .T1         (1'b0),
        .T2         (1'b0),
        .T3         (1'b0),
        .T4         (1'b0),
        .TBYTEIN    (1'b0),
        .TCE        (1'b0)
    );

    OBUFDS u_obuf (.I(serq), .O(data_p), .OB(data_n));
endmodule
