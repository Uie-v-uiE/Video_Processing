`timescale 1ns/1ps
// MMCM: 50 MHz -> 50 MHz pixel + 250 MHz 5x + 200 MHz IDELAY ref
// VCO = 50 * 20 = 1000 MHz
module clk_gen (
    input  wire clk_in,
    input  wire rst_n,
    output wire clk_pix,
    output wire clk_pix5x,
    output wire clk_200m,
    output wire locked
);
    wire clkfbout, clkfbout_buf;
    wire clkout0, clkout1, clkout2;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKIN1_PERIOD      (20.000),
        .DIVCLK_DIVIDE      (1),
        .CLKFBOUT_MULT_F    (20.000), // VCO = 1000 MHz
        .CLKFBOUT_PHASE     (0.0),
        .CLKOUT0_DIVIDE_F   (20.000), // 50 MHz pixel
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT1_DIVIDE     (4),      // 250 MHz 5x
        .CLKOUT1_PHASE      (0.0),
        .CLKOUT1_DUTY_CYCLE (0.5),
        .CLKOUT2_DIVIDE     (5),      // 200 MHz IDELAY ref
        .CLKOUT2_PHASE      (0.0),
        .CLKOUT2_DUTY_CYCLE (0.5),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKIN1     (clk_in),
        .CLKFBIN    (clkfbout_buf),
        .CLKFBOUT   (clkfbout),
        .CLKFBOUTB  (),
        .CLKOUT0    (clkout0),
        .CLKOUT0B   (),
        .CLKOUT1    (clkout1),
        .CLKOUT1B   (),
        .CLKOUT2    (clkout2),
        .CLKOUT2B   (),
        .CLKOUT3    (),
        .CLKOUT3B   (),
        .CLKOUT4    (),
        .CLKOUT5    (),
        .CLKOUT6    (),
        .PWRDWN     (1'b0),
        .RST        (~rst_n),
        .LOCKED     (locked)
    );

    BUFG u_bufg_fb  (.I(clkfbout), .O(clkfbout_buf));
    BUFG u_bufg_pix (.I(clkout0),  .O(clk_pix));
    BUFG u_bufg_5x  (.I(clkout1),  .O(clk_pix5x));
    BUFG u_bufg_200 (.I(clkout2),  .O(clk_200m));
endmodule
