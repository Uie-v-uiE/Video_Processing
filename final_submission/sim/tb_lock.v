`timescale 1ns/1ps
// 功能：被测模块 `frame_commit_lock`；覆盖点：copy_base 在 start_copy 那一拍锁存、拷贝途中不随
//        新 commit_base 改变、copy_done 之后取最后一次 pending 的 base。
// 激励与检查：axi_clk #5=10 ns、pix_clk #10=20 ns；rst_n 低 20 个 axi 拍后释放；像素每行 40 拍
//        （de 高 16 拍）、共 10 行；near_active=(x>=28)&&(y<8)，blank_safe=~(de|de_pipe[15]|
//        near_active)；copy_busy 恒 0。第一段 commit_base=32'h1000_0000、commit_req 高 5 拍，
//        最多等 200000 个 axi 拍到 start_cnt>=1，再等 3 拍读 locked_seen（start_copy 之后一拍
//        锁存的 copy_base）；第二段改 commit_base=32'h1008_0000、commit_req 高 3 拍、再等 5 拍；
//        第三段 copy_done_r 拉 1 拍、等 20 拍后把 start_cnt 清零，再最多等 200000 拍取第二次 start。
//        判定条件：第一段 locked_seen===32'h1000_0000；第二段不许出现
//        (copy_base===32'h1008_0000 && start_cnt==1)；第三段 locked_seen===32'h1008_0000。
// 预期结果：通过时打印 INFO first start base=10000000、PASS copy_base locked (<base>)、
//        INFO second start base=10080000、PASS latest pending after done，末行 PASS tb_lock。
//        失败时打 FAIL no first start（首启超时直接 $finish）、FAIL copy_base changed mid-copy、
//        FAIL second base <值>；第一段 base 不符只累 errors、无独立打印，表现为末行
//        FAIL tb_lock errors=<n>。
module tb_lock;
    reg axi_clk=0, pix_clk=0, rst_n=0;
    always #5 axi_clk = ~axi_clk;
    always #10 pix_clk = ~pix_clk;
    wire rst_pix_n = rst_n;

    parameter PIPE=15;
    reg de=0, vs=0;
    reg [11:0] x=0, y=0;
    integer xcnt=0, ycnt=0;
    always @(posedge pix_clk) begin
        if (!rst_n) begin de<=0; vs<=0; xcnt<=0; ycnt<=0; x<=0; y<=0; end
        else begin
            de <= (xcnt < 16);
            vs <= (xcnt==0 && ycnt==0);
            x <= xcnt[11:0]; y <= ycnt[11:0];
            if (xcnt==39) begin
                xcnt<=0;
                if (ycnt==9) ycnt<=0;
                else ycnt<=ycnt+1;
            end else xcnt<=xcnt+1;
        end
    end

    reg [PIPE:0] de_pipe;
    always @(posedge pix_clk or negedge rst_pix_n) begin
        if (!rst_pix_n) de_pipe <= 0;
        else de_pipe <= {de_pipe[PIPE-1:0], de};
    end
    wire near_active = (x >= 12'd28) && (y < 12'd8);
    wire blank_safe = ~(de | de_pipe[PIPE] | near_active);

    reg commit_req=0;
    reg [31:0] commit_base=32'h10000000;
    wire start_copy, ready, allow, abort;
    wire copy_busy = 1'b0;
    wire [31:0] copy_base;
    reg copy_done_r=0;

    frame_commit_lock u_cm (
        .axi_clk(axi_clk), .axi_rst_n(rst_n),
        .commit_req(commit_req), .commit_base(commit_base),
        .pix_clk(pix_clk), .pix_rst_n(rst_n),
        .de(de), .vsync(vs), .blank_safe(blank_safe),
        .copy_busy(copy_busy), .copy_done(copy_done_r),
        .start_copy(start_copy), .copy_base(copy_base),
        .frame_ready_pix(ready), .allow_copy_axi(allow),
        .copy_abort(abort)
    );

    integer errors=0, start_cnt=0, guard=0;
    reg [31:0] locked_seen=0;
    reg start_d=0;
    always @(posedge axi_clk) begin
        start_d <= start_copy;
        if (start_copy) start_cnt = start_cnt + 1;
        if (start_d) locked_seen <= copy_base;
    end

    initial begin
        rst_n=0; repeat(20) @(posedge axi_clk); rst_n=1;
        commit_base=32'h10000000; commit_req=1;
        repeat (5) @(posedge axi_clk); commit_req=0;
        guard=0;
        while (start_cnt<1 && guard<200000) begin @(posedge axi_clk); guard=guard+1; end
        if (start_cnt<1) begin $display("FAIL no first start"); $finish; end
        repeat (3) @(posedge axi_clk);
        $display("INFO first start base=%h", locked_seen);
        if (locked_seen !== 32'h10000000) errors=errors+1;

        commit_base=32'h10080000; commit_req=1;
        repeat (3) @(posedge axi_clk); commit_req=0;
        repeat (5) @(posedge axi_clk);
        if (copy_base === 32'h10080000 && start_cnt==1) begin
            $display("FAIL copy_base changed mid-copy");
            errors=errors+1;
        end else $display("PASS copy_base locked (%h)", copy_base);

        @(posedge axi_clk) copy_done_r<=1;
        @(posedge axi_clk) copy_done_r<=0;
        repeat (20) @(posedge axi_clk);
        start_cnt=0; start_d=0; guard=0;
        while (start_cnt<1 && guard<200000) begin @(posedge axi_clk); guard=guard+1; end
        repeat (3) @(posedge axi_clk);
        $display("INFO second start base=%h", locked_seen);
        if (locked_seen !== 32'h10080000) begin
            $display("FAIL second base %h", locked_seen);
            errors=errors+1;
        end else $display("PASS latest pending after done");

        if (errors==0) $display("PASS tb_lock");
        else $display("FAIL tb_lock errors=%0d", errors);
        $finish;
    end
endmodule
