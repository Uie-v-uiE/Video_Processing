`timescale 1ns/1ps
// DDR ping-pong: bank tag + commit after frame_done drain delay
module tb_pingpong;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    reg wr_bank_eth=0, done_bank=0, frame_done=0;
    reg [18:0] fb_addr=0;
    reg [15:0] fb_data=0;
    reg fb_en=0;

    wire [35:0] fifo_dout;
    wire fifo_empty, fifo_full;
    reg fifo_rd=0, fifo_rd_d=0;
    reg sav_en=0;
    reg [18:0] sav_a=0;
    reg [15:0] sav_d=0;
    reg sav_bank=0;

    dc_fifo #(.DATA_W(36), .ADDR_W(8)) u_cdc (
        .wr_clk(clk), .wr_rst_n(rst_n),
        .wr_en(fb_en && !fifo_full),
        .wr_data({wr_bank_eth, fb_addr, fb_data}),
        .wr_full(fifo_full),
        .rd_clk(clk), .rd_rst_n(rst_n),
        .rd_en(fifo_rd), .rd_data(fifo_dout), .rd_empty(fifo_empty)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_rd<=0; fifo_rd_d<=0; sav_en<=0; sav_a<=0; sav_d<=0; sav_bank<=0;
        end else begin
            fifo_rd   <= !fifo_empty && !fifo_rd_d;
            fifo_rd_d <= fifo_rd;
            sav_en    <= fifo_rd_d;
            if (fifo_rd_d) begin
                sav_bank <= fifo_dout[35];
                sav_a    <= fifo_dout[34:16];
                sav_d    <= fifo_dout[15:0];
            end
        end
    end

    always @(posedge clk) begin
        if (frame_done) begin
            done_bank   <= wr_bank_eth;
            wr_bank_eth <= ~wr_bank_eth;
        end
    end

    // commit logic (same as RTL, shorter wait)
    reg fd0,fd1,fd2;
    reg db0,db1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) {fd2,fd1,fd0}<=0;
        else {fd2,fd1,fd0} <= {fd1,fd0,frame_done}; // same clock: edge on frame_done
    end
    // use frame_done directly as pulse (same clock in TB)
    reg [11:0] drain_cnt=0;
    reg drain_run=0, rd_bank=0, commit_tog=0;
    integer commits=0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drain_cnt<=0; drain_run<=0; rd_bank<=0; commit_tog<=0;
        end else begin
            if (frame_done) begin
                drain_run<=1; drain_cnt<=12'd64; // short wait in TB
            end else if (drain_run) begin
                if (drain_cnt==0) begin
                    drain_run<=0;
                    rd_bank<=done_bank;
                    commit_tog<=~commit_tog;
                    commits<=commits+1;
                end else drain_cnt<=drain_cnt-1;
            end
        end
    end

    integer n0=0, n1=0, errors=0, i;
    always @(posedge clk) if (sav_en) begin
        if (!sav_bank) n0=n0+1; else n1=n1+1;
    end

    task send_frame(input [15:0] base_data);
        integer p;
        begin
            for (p=0;p<32;p=p+1) begin
                @(posedge clk);
                fb_en<=1; fb_addr<=p[18:0]; fb_data<=base_data+p[15:0];
            end
            @(posedge clk);
            fb_en<=0;
            @(posedge clk);
            frame_done<=1;
            @(posedge clk);
            frame_done<=0;
            repeat(80) @(posedge clk); // wait drain+commit
        end
    endtask

    initial begin
        repeat(4) @(posedge clk);
        rst_n=1;
        repeat(2) @(posedge clk);

        send_frame(16'h1000);
        if (commits<1) begin $display("FAIL no commit1"); errors=errors+1; end
        else $display("PASS commit1 rd_bank=%0d n0=%0d n1=%0d", rd_bank, n0, n1);
        if (rd_bank!==0) begin $display("FAIL rd_bank exp 0 got %0d", rd_bank); errors=errors+1; end
        if (n0<32) begin $display("FAIL n0=%0d", n0); errors=errors+1; end

        send_frame(16'h2000);
        if (commits<2) begin $display("FAIL no commit2"); errors=errors+1; end
        else $display("PASS commit2 rd_bank=%0d n0=%0d n1=%0d", rd_bank, n0, n1);
        if (rd_bank!==1) begin $display("FAIL rd_bank exp 1 got %0d", rd_bank); errors=errors+1; end
        if (n1<32) begin $display("FAIL n1=%0d", n1); errors=errors+1; end

        send_frame(16'h3000);
        if (commits<3) begin $display("FAIL no commit3"); errors=errors+1; end
        else $display("PASS commit3 rd_bank=%0d", rd_bank);
        if (rd_bank!==0) begin $display("FAIL rd_bank exp 0 got %0d", rd_bank); errors=errors+1; end

        if (errors==0) $display("PASS tb_pingpong ALL");
        else $display("FAIL tb_pingpong errors=%0d", errors);
        $finish;
    end
endmodule
