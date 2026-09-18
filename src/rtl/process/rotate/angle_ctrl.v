`timescale 1ns/1ps
// Angle control: KEY1 +1°, KEY2 -1°, wrap 0..359. Optional hold-to-accel.
module angle_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       key_inc,
    input  wire       key_dec,
    output reg  [8:0] angle,
    output wire       rotate_active
);
    assign rotate_active = (angle != 9'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            angle <= 9'd0;
        else if (key_inc)
            angle <= (angle == 9'd359) ? 9'd0 : (angle + 9'd1);
        else if (key_dec)
            angle <= (angle == 9'd0) ? 9'd359 : (angle - 9'd1);
    end
endmodule
