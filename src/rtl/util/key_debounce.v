`timescale 1ns/1ps
// Active-low key debounce + one-cycle press pulse
module key_debounce #(
    parameter CNT_MAX = 1_000_000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire key_n,
    output reg  pulse,
    output reg  key_stable  // 1 = released, 0 = pressed
);
    reg [20:0] cnt;
    reg key_sync0, key_sync1;
    reg key_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_sync0  <= 1'b1;
            key_sync1  <= 1'b1;
            key_prev   <= 1'b1;
            key_stable <= 1'b1;
            cnt        <= 21'd0;
            pulse      <= 1'b0;
        end else begin
            key_sync0 <= key_n;
            key_sync1 <= key_sync0;
            pulse     <= 1'b0;
            if (key_sync1 != key_stable) begin
                if (cnt >= CNT_MAX[20:0]) begin
                    key_stable <= key_sync1;
                    cnt        <= 21'd0;
                end else
                    cnt <= cnt + 21'd1;
            end else
                cnt <= 21'd0;

            key_prev <= key_stable;
            // press edge: stable was released (1), now pressed (0)
            if (key_prev && !key_stable)
                pulse <= 1'b1;
        end
    end
endmodule
