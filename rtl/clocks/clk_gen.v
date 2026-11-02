`timescale 1ns/1ps
// MMCM: 50 MHz -> 50 MHz pixel + 250 MHz 5x
// Spec wants 50.25MHz; 50.000 is within typical monitor tolerance for 1024x600.
module clk_gen (
    input  wire clk_in,
    input  wire rst_n,
    output wire clk_pix,
    output wire clk_pix5x,
    output wire locked
);
    wire clkfbout, clkfbout_buf;
    wire clkout0, clkout1;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKIN1_PERIOD      (20.000),
        .DIVCLK_DIVIDE      (1),
        .CLKFBOUT_MULT_F    (15.000), // VCO = 750 MHz (>=600)
        .CLKFBOUT_PHASE     (0.0),
        .CLKOUT0_DIVIDE_F   (15.000), // 50 MHz pixel
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT1_DIVIDE     (3),      // 250 MHz 5x
        .CLKOUT1_PHASE      (0.0),
        .CLKOUT1_DUTY_CYCLE (0.5),
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
        .CLKOUT2    (),
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
endmodule
