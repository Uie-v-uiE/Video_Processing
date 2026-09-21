`timescale 1ns/1ps
// Out-of-context inference probe: which coding shape makes Vivado map a
// 512x64 packer FIFO onto distributed RAM instead of 32k FDRE?
// Each variant is byte-for-byte the same FIFO shape as axi_frame_saver64's
// q_data array; only the read/write structure differs.

// V1: async read via continuous assign, write from a task under `if(!full)`
//     (== what is in the RTL today)
module fifo_v1 #(parameter FW = 9)(
    input wire clk, input wire rst_n, input wire enable,
    input wire wr_en, input wire [63:0] wr_data, input wire flush,
    output wire full, output reg [63:0] rd_q, output reg rd_v);
    (* ram_style = "distributed" *) reg [63:0] mem [0:(1<<FW)-1];
    reg [FW:0] wptr, rptr;
    assign full = (wptr[FW]!=rptr[FW]) && (wptr[FW-1:0]==rptr[FW-1:0]);
    wire [FW-1:0] ridx = rptr[FW-1:0];
    wire [63:0] rd_async = mem[ridx];
    task automatic push; input [63:0] d;
        begin if (!full) begin mem[wptr[FW-1:0]] <= d; wptr <= wptr + 1'b1; end end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin wptr <= 0; end
        else if (enable) begin
            if (wr_en) push(wr_data);
            else if (flush) push(wr_data);
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rptr <= 0; rd_q <= 0; rd_v <= 0; end
        else begin
            rd_v <= (rptr != wptr);
            if (rptr != wptr) begin rd_q <= rd_async; rptr <= rptr + 1'b1; end
        end
    end
endmodule

// V2: same, but the write is a plain `if (we) mem[..] <= ..` with no task and
//     no `if(!full)` guard around it (full is folded into `we` outside).
module fifo_v2 #(parameter FW = 9)(
    input wire clk, input wire rst_n, input wire we, input wire [63:0] wr_data,
    output wire full, output reg [63:0] rd_q, output reg rd_v);
    (* ram_style = "distributed" *) reg [63:0] mem [0:(1<<FW)-1];
    reg [FW:0] wptr, rptr;
    assign full = (wptr[FW]!=rptr[FW]) && (wptr[FW-1:0]==rptr[FW-1:0]);
    wire [FW-1:0] ridx = rptr[FW-1:0];
    wire [63:0] rd_async = mem[ridx];
    wire do_wr = we && !full;
    always @(posedge clk) begin
        if (do_wr) mem[wptr[FW-1:0]] <= wr_data;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin wptr <= 0; end
        else if (do_wr) wptr <= wptr + 1'b1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rptr <= 0; rd_q <= 0; rd_v <= 0; end
        else begin
            rd_v <= (rptr != wptr);
            if (rptr != wptr) begin rd_q <= rd_async; rptr <= rptr + 1'b1; end
        end
    end
endmodule

// V3: V2 shape but no ram_style attribute at all (let the tool decide).
module fifo_v3 #(parameter FW = 9)(
    input wire clk, input wire rst_n, input wire we, input wire [63:0] wr_data,
    output wire full, output reg [63:0] rd_q, output reg rd_v);
    reg [63:0] mem [0:(1<<FW)-1];
    reg [FW:0] wptr, rptr;
    assign full = (wptr[FW]!=rptr[FW]) && (wptr[FW-1:0]==rptr[FW-1:0]);
    wire [FW-1:0] ridx = rptr[FW-1:0];
    wire [63:0] rd_async = mem[ridx];
    wire do_wr = we && !full;
    always @(posedge clk) begin
        if (do_wr) mem[wptr[FW-1:0]] <= wr_data;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin wptr <= 0; end
        else if (do_wr) wptr <= wptr + 1'b1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rptr <= 0; rd_q <= 0; rd_v <= 0; end
        else begin
            rd_v <= (rptr != wptr);
            if (rptr != wptr) begin rd_q <= rd_async; rptr <= rptr + 1'b1; end
        end
    end
endmodule

// V4: V2 shape, split the 64-bit word into 8 x 8-bit arrays (some tools cap
//     the LUTRAM width per array).
module fifo_v4 #(parameter FW = 9)(
    input wire clk, input wire rst_n, input wire we, input wire [63:0] wr_data,
    output wire full, output reg [63:0] rd_q, output reg rd_v);
    integer b;
    reg [7:0] mem [0:(1<<FW)-1][0:7];
    reg [FW:0] wptr, rptr;
    assign full = (wptr[FW]!=rptr[FW]) && (wptr[FW-1:0]==rptr[FW-1:0]);
    wire [FW-1:0] ridx = rptr[FW-1:0];
    wire do_wr = we && !full;
    always @(posedge clk) begin
        if (do_wr)
            for (b=0; b<8; b=b+1) mem[wptr[FW-1:0]][b] <= wr_data[b*8 +: 8];
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin wptr <= 0; end
        else if (do_wr) wptr <= wptr + 1'b1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rptr <= 0; rd_q <= 0; rd_v <= 0; end
        else begin
            rd_v <= (rptr != wptr);
            if (rptr != wptr) begin
                for (b=0; b<8; b=b+1) rd_q[b*8 +: 8] <= mem[ridx][b];
                rptr <= rptr + 1'b1;
            end
        end
    end
endmodule

// V5: V2 shape with (* ram_style = "distributed" *) on a *separate* declaration
//     line, and read address = low bits of a pointer that never resets.
module fifo_v5 #(parameter FW = 9)(
    input wire clk, input wire rst_n, input wire we, input wire [63:0] wr_data,
    output wire full, output reg [63:0] rd_q, output reg rd_v);
    /* synthesis ram_style = "distributed" */
    reg [63:0] mem [0:(1<<FW)-1];
    reg [FW:0] wptr, rptr;
    assign full = (wptr[FW]!=rptr[FW]) && (wptr[FW-1:0]==rptr[FW-1:0]);
    wire [FW-1:0] ridx = rptr[FW-1:0];
    wire [63:0] rd_async = mem[ridx];
    wire do_wr = we && !full;
    always @(posedge clk) begin
        if (do_wr) mem[wptr[FW-1:0]] <= wr_data;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin wptr <= 0; end
        else if (do_wr) wptr <= wptr + 1'b1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rptr <= 0; rd_q <= 0; rd_v <= 0; end
        else begin
            rd_v <= (rptr != wptr);
            if (rptr != wptr) begin rd_q <= rd_async; rptr <= rptr + 1'b1; end
        end
    end
endmodule

module ramtest_top #(parameter FW = 9)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we,
    input  wire [63:0] d,
    input  wire        flush,
    output wire [63:0] o_sum,
    output wire        f_sum);
    wire        f1,f2,f3,f4,f5, v1,v2,v3,v4,v5;
    reg  [63:0] q1,q2,q3,q4,q5;
    reg [63:0] s1,s2,s3,s4,s5;

    fifo_v1 #(.FW(FW)) u1 (.clk(clk),.rst_n(rst_n),.enable(1'b1),.wr_en(we),
        .wr_data(d),.flush(flush),.full(f1),.rd_q(q1),.rd_v(v1));
    fifo_v2 #(.FW(FW)) u2 (.clk(clk),.rst_n(rst_n),.we(we),.wr_data(d),
        .full(f2),.rd_q(q2),.rd_v(v2));
    fifo_v3 #(.FW(FW)) u3 (.clk(clk),.rst_n(rst_n),.we(we),.wr_data(d),
        .full(f3),.rd_q(q3),.rd_v(v3));
    fifo_v4 #(.FW(FW)) u4 (.clk(clk),.rst_n(rst_n),.we(we),.wr_data(d),
        .full(f4),.rd_q(q4),.rd_v(v4));
    fifo_v5 #(.FW(FW)) u5 (.clk(clk),.rst_n(rst_n),.we(we),.wr_data(d),
        .full(f5),.rd_q(q5),.rd_v(v5));

    // consume the outputs so nothing is optimised away
    always @(posedge clk) begin
        if (v1) s1 <= q1;
        if (v2) s2 <= q2;
        if (v3) s3 <= q3;
        if (v4) s4 <= q4;
        if (v5) s5 <= q5;
    end
    assign o_sum = s1 + s2 + s3 + s4 + s5;
    assign f_sum = f1 ^ f2 ^ f3 ^ f4 ^ f5;
endmodule
