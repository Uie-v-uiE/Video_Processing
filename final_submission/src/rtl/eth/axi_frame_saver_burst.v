`timescale 1ns/1ps
// AXI3 DDR writer v5: deep FIFO + consecutive-address bursts.
// Issues on: flush, address gap, burst full, or quiet-idle drain.
module axi_frame_saver_burst #(
    parameter BASE_ADDR = 32'h1000_0000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire [31:0] base_addr,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,
    input  wire [15:0] wr_data,
    input  wire        flush,
    output wire        fifo_full,
    output wire        idle,
    output reg         busy,
    output reg  [31:0] m_axi_awaddr,
    output reg  [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,
    output reg  [63:0] m_axi_wdata,
    output wire [7:0]  m_axi_wstrb,
    output reg         m_axi_wlast,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready
);
    assign m_axi_awsize  = 3'b011;
    assign m_axi_awburst = 2'b01;
    assign m_axi_wstrb   = 8'hFF;

    localparam FW = 9;
    reg [31:0] q_addr [0:(1<<FW)-1];
    reg [63:0] q_data [0:(1<<FW)-1];
    reg [FW:0] wptr, rptr;
    assign fifo_full = (wptr[FW] != rptr[FW]) && (wptr[FW-1:0] == rptr[FW-1:0]);
    wire fifo_empty = (wptr == rptr);

    reg [18:0] cur_widx;
    reg [63:0] cur_data;
    reg        cur_dirty;
    reg [31:0] pack_base;
    reg        flush_d;
    reg [7:0]  quiet_cnt;
    reg        drain_req;

    localparam [1:0] S_COLLECT=0, S_AW=1, S_W=2;
    reg [1:0]  st;
    reg [63:0] b_data [0:15];
    reg [31:0] b_addr0;
    reg [7:0]  b_cnt;
    reg [7:0]  b_left;
    reg [7:0]  b_idx;
    reg [3:0]  b_outstanding;

    assign idle = enable && !cur_dirty && fifo_empty && (st == S_COLLECT)
                  && (b_cnt == 0) && (b_outstanding == 0)
                  && !m_axi_awvalid && !m_axi_wvalid && !drain_req;

    wire [18:0] in_widx = wr_addr[18:2];
    wire        idx_chg = cur_dirty && (in_widx != cur_widx);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pack_base <= BASE_ADDR;
        else if (!cur_dirty) pack_base <= base_addr;
    end

    task automatic push_word;
        input [18:0] widx;
        input [63:0] data;
        input [31:0] base;
        begin
            if (!fifo_full) begin
                q_addr[wptr[FW-1:0]] <= base + {10'd0, widx, 3'b000};
                q_data[wptr[FW-1:0]] <= data;
                wptr <= wptr + 1'b1;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= 0; cur_widx <= 0; cur_data <= 0; cur_dirty <= 0;
        end else if (enable) begin
            if (wr_en) begin
                if (idx_chg || !cur_dirty) begin
                    if (idx_chg)
                        push_word(cur_widx, cur_data, pack_base);
                    cur_widx <= in_widx;
                    case (wr_addr[1:0])
                        2'd0: cur_data <= {48'd0, wr_data};
                        2'd1: cur_data <= {32'd0, wr_data, 16'd0};
                        2'd2: cur_data <= {16'd0, wr_data, 32'd0};
                        default: cur_data <= {wr_data, 48'd0};
                    endcase
                    cur_dirty <= 1'b1;
                end else begin
                    case (wr_addr[1:0])
                        2'd0: cur_data[15:0]  <= wr_data;
                        2'd1: cur_data[31:16] <= wr_data;
                        2'd2: cur_data[47:32] <= wr_data;
                        default: cur_data[63:48] <= wr_data;
                    endcase
                end
            end else if (flush && cur_dirty) begin
                push_word(cur_widx, cur_data, pack_base);
                cur_dirty <= 1'b0;
            end
        end
    end

    wire [31:0] fifo_a = q_addr[rptr[FW-1:0]];
    wire [63:0] fifo_d = q_data[rptr[FW-1:0]];
    wire [31:0] expect_a = b_addr0 + {21'd0, b_cnt, 3'b000};
    wire can_add = (b_cnt != 0) && (fifo_a == expect_a) && (b_cnt < 8'd16);
    wire gap = !fifo_empty && (b_cnt != 0) && !can_add;
    wire quiet_drain = drain_req && !fifo_empty && (b_cnt != 0) && !can_add;
    // issue burst when full, gap, or drain requested and collector has data
    wire issue_now = (st == S_COLLECT) && (b_cnt != 0) &&
                     ((b_cnt == 8'd16) || gap || (drain_req && fifo_empty) || (drain_req && !can_add));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rptr <= 0; busy <= 0; st <= S_COLLECT;
            b_addr0 <= 0; b_cnt <= 0; b_left <= 0; b_idx <= 0;
            b_outstanding <= 0; flush_d <= 0; quiet_cnt <= 0; drain_req <= 0;
            m_axi_awvalid <= 0; m_axi_awaddr <= 0; m_axi_awlen <= 0;
            m_axi_wvalid <= 0; m_axi_wdata <= 0; m_axi_wlast <= 0;
            m_axi_bready <= 0;
        end else begin
            flush_d <= flush;
            if (flush && !flush_d) drain_req <= 1'b1;
            if (wr_en || !fifo_empty || (st != S_COLLECT)) quiet_cnt <= 8'd0;
            else if (quiet_cnt != 8'hFF) quiet_cnt <= quiet_cnt + 8'd1;
            // auto-drain if quiet after packing
            if (quiet_cnt > 8'd16 && b_cnt != 0) drain_req <= 1'b1;

            busy <= (st != S_COLLECT) || !fifo_empty || (b_cnt != 0)
                    || (b_outstanding != 0) || m_axi_awvalid || m_axi_wvalid || cur_dirty || drain_req;

            if (m_axi_bvalid && m_axi_bready) begin
                b_outstanding <= b_outstanding - 1'b1;
                m_axi_bready  <= (b_outstanding > 4'd1);
            end

            case (st)
                S_COLLECT: begin
                    if (!fifo_empty && !(b_cnt == 8'd16) && !(gap && drain_req) && !((b_cnt!=0) && !can_add && drain_req)) begin
                        if (b_cnt == 0) begin
                            b_addr0 <= fifo_a;
                            b_data[0] <= fifo_d;
                            b_cnt <= 8'd1;
                            rptr  <= rptr + 1'b1;
                        end else if (can_add) begin
                            b_data[b_cnt[3:0]] <= fifo_d;
                            b_cnt <= b_cnt + 8'd1;
                            rptr  <= rptr + 1'b1;
                        end
                    end
                    if (issue_now) begin
                        st <= S_AW;
                        m_axi_awvalid <= 1'b1;
                        m_axi_awaddr  <= b_addr0;
                        m_axi_awlen   <= b_cnt - 8'd1;
                        b_left        <= b_cnt;
                        b_idx         <= 8'd0;
                        b_outstanding <= b_outstanding + 1'b1;
                        m_axi_bready  <= 1'b1;
                        b_cnt         <= 8'd0;
                        // keep drain_req if more FIFO data remains after gap
                        if (fifo_empty) drain_req <= 1'b0;
                    end
                end
                S_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b1;
                        m_axi_wdata   <= b_data[0];
                        m_axi_wlast   <= (b_left == 8'd1);
                        b_idx         <= 8'd1;
                        st            <= S_W;
                    end
                end
                S_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        if (b_idx < b_left) begin
                            m_axi_wdata <= b_data[b_idx[3:0]];
                            m_axi_wlast <= (b_idx == b_left - 8'd1);
                            b_idx <= b_idx + 8'd1;
                        end else begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_wlast  <= 1'b0;
                            st <= S_COLLECT;
                        end
                    end
                end
                default: st <= S_COLLECT;
            endcase
        end
    end
endmodule
