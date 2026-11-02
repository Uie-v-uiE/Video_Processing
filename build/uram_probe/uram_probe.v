
// 1 �? 1 读：UltraRAM �?一能自然吃下的形状（简单双口）
(* ram_style = "ultramark" *) module ram_1w1r #(
    parameter DEPTH = 76800
)(
    input  wire        clk,
    input  wire        we,
    input  wire [16:0] waddr,
    input  wire [31:0] din,
    input  wire [16:0] raddr,
    output reg  [31:0] dout
);
    reg [31:0] mem [0:DEPTH-1];
    always @(posedge clk) begin
        if (we) mem[waddr] <= din;
        dout <= mem[raddr];
    end
endmodule

// 同样的属性，�?**读口翻�?**（真实帧缓存要同时喂�?/右窗�? 4 �?字节道）
(* ram_style = "ultramark" *) module ram_1w4r #(
    parameter DEPTH = 76800
)(
    input  wire        clk,
    input  wire        we,
    input  wire [16:0] waddr,
    input  wire [31:0] din,
    input  wire [16:0] r0, input  wire [16:0] r1, input  wire [16:0] r2, input  wire [16:0] r3,
    output reg  [31:0] d0, output reg  [31:0] d1, output reg  [31:0] d2, output reg  [31:0] d3
);
    reg [31:0] mem [0:DEPTH-1];
    always @(posedge clk) begin
        if (we) mem[waddr] <= din;
        d0 <= mem[r0]; d1 <= mem[r1]; d2 <= mem[r2]; d3 <= mem[r3];
    end
endmodule

// 对照组：完全不加属性，看工具自己怎么�?
module ram_plain #(
    parameter DEPTH = 76800
)(
    input  wire        clk,
    input  wire        we,
    input  wire [16:0] waddr,
    input  wire [31:0] din,
    input  wire [16:0] raddr,
    output reg  [31:0] dout
);
    reg [31:0] mem [0:DEPTH-1];
    always @(posedge clk) begin
        if (we) mem[waddr] <= din;
        dout <= mem[raddr];
    end
endmodule

