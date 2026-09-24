module presence_top(input clk); wire w; reg r; always @(posedge clk) r <= ~r; endmodule
