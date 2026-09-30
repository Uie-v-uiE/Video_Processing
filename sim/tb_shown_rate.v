`timescale 1ns/1ps
// tb_shown_rate —— `src/rtl/util/shown_rate.v` 的逐拍尺子（ISSUES #128：OSD 的 `FPS:` 格）。
//
// 为什么单独一支小台架而不挂到整屏台架上：这一格错的方式是"读数恒在 59/60"，
// 而 tb_v98 判的是像素与坐标，它对"数的是场还是帧"**不敏感** ⇒ 挂上去会恒绿。
// 这里把窗口缩到 1000 拍，各场景拿**激励几何**算出来的期望数比。
//
// 几何是刻意选的（这三条不成立，下面所有期望值都要重推）：
//   窗口 F = WIN+1 = 1000 拍；一场 FP = 50 拍 ⇒ 每窗口恰好 20 场；
//   场网格与窗口边界**错开 1 拍**（phase=1）⇒ 没有一场落在"窗口结束那一拍"上，
//     否则每窗口莫名少一场（FP 整除 F 时边界必然撞，第一版就栽在这里）。
//   片源周期（2 场 / 4 场 = 100 / 200 拍）整除 1000 ⇒ 稳态下每窗口的计数完全确定：10、5、0、20。
//
// ⚠ 激励只有一个写入者（下面那个 always）。第一版在 initial 里直接 `eth_new = 1` 想演"同拍"那一支，
//   结果 always 里的非阻塞赋值 `eth_new <= ...` 在**同一个时间点**把它盖掉 ⇒ S6 那两条因为
//   "根本没有新帧"而绿（假绿，而且是被自己写的地板读数发现的）。同拍那一支改由 mode==5 生成。
module tb_shown_rate;

    localparam integer WIN = 999;          // 小窗口
    localparam integer F   = 1000;         // 每窗口拍数
    localparam integer FP  = 50;           // 每场拍数 ⇒ 每窗口 20 场
    localparam integer PH  = 1;            // 场起点相对窗口错开的那一拍
    localparam integer NFS = F/FP;         // 每窗口场数 = 20

    reg clk = 0, rst_n = 0;
    reg frame_start = 0, owner_eth = 0, fb_vis = 1, eth_new = 0, pub_consume = 0, pub_pend = 0;
    wire [7:0] fps_q;
    integer errors = 0;
    integer cy = 0, fi = 0, mode = 0, new_every = 0, nstop = 0;
    integer n_fs = 0, n_eth = 0, n_pub = 0, one_shot = 0;
    integer n_pulse = 0, n_count = 0;    // 真值：eth_new 实际脉冲数 / DUT 的 new_shown 实际数
    reg tb_pend = 0;

    always #10 clk = ~clk;

    shown_rate #(.WIN_LAST(WIN)) u_dut (
        .clk(clk), .rst_n(rst_n), .frame_start(frame_start), .owner_eth_pix(owner_eth),
        .fb_vis(fb_vis), .eth_new(eth_new), .pub_consume(pub_consume), .pub_pend(pub_pend),
        .fps_q(fps_q));

    // 默认参数那份只用来钉口径（S5）：不喂激励，只读它的参数。
    // ⚠ 先声明线再接端口：端口里先引用会造出隐式 net，后面再显式声明就是重定义
    //   （顶层 pl_video_top.v 里 `pub_new` 那条注释写的就是同一件事）。
    wire [7:0] fps_full_unused;
    shown_rate u_full (.clk(clk), .rst_n(rst_n), .frame_start(1'b0), .owner_eth_pix(1'b0),
                       .fb_vis(1'b0), .eth_new(1'b0), .pub_consume(1'b0), .pub_pend(1'b0),
                       .fps_q(fps_full_unused));

    // 地板用真值计数（#128 那一族：判据不许复刻 DUT 的谓词来"证明自己有牙"）
    always @(posedge clk) begin
        if (rst_n) begin
            if (eth_new)              n_pulse = n_pulse + 1;
            if (u_dut.new_shown)      n_count = n_count + 1;
        end
    end

    // ⚠ 标签宽度必须容得下**整条判据名**：`[8*80:1]` 那种写法在名字超过 80 字符时会从左端截掉，
    //   于是 "S1 eth ..." 被打成 "eth ..." —— 判定文本还在，但 `mut_control.sh` 那种按
    //   `FAIL S1` 匹配的机器判据就抓不到了（今晚实测：变异跑里 5 条全红，harness 却说"仍然不红"）。
    task chk(input [8*140:1] named, input ok);
        begin
            if (ok) $display("PASS %0s", named);
            else  begin $display("FAIL %0s", named); errors = errors + 1; end
        end
    endtask

    // 唯一的激励写入者：输入在 negedge 更新，DUT 在紧接着的 posedge 采样 ⇒ 每根线只维持一拍
    always @(negedge clk) begin
        if (!rst_n) begin
            frame_start <= 0; eth_new <= 0; pub_consume <= 0; pub_pend <= 0; tb_pend <= 0;
        end else begin
            frame_start <= ((cy % FP) == PH);
            // mode 1 = ETH 按 new_every 的节拍来帧（落在两场之间）；
            // mode 5 = 只来一帧，而且**与场起点同一拍**（S6 要钉的就是这一支）
            eth_new     <= (((mode == 1) && new_every > 0 && ((cy % FP) == (PH + 5))
                                       && ((fi % new_every) == 0))
                         || ((mode == 5) && one_shot && ((cy % FP) == PH)));
            pub_consume <= ((mode == 2) && ((cy % FP) == PH));
            pub_pend    <= tb_pend;
            if ((mode == 2) && new_every > 0 && ((cy % FP) == (PH + 5)) && ((fi % new_every) == 0))
                tb_pend <= 1;
            else if (frame_start && tb_pend)
                tb_pend <= 0;

            if ((cy % FP) == (PH + 5)) fi = (cy / FP);   // 先更新场号：放后面会让"每第几场"滞后一场
            if ((cy % FP) == PH) n_fs = n_fs + 1;
            if ((mode == 1) && ((cy % FP) == (PH + 5)) && ((fi % new_every) == 0)) n_eth = n_eth + 1;
            if ((mode == 5) && one_shot && ((cy % FP) == PH)) begin n_eth = n_eth + 1; one_shot = 0; end
            if ((mode == 2) && ((cy % FP) == (PH + 5)) && ((fi % new_every) == 0)) n_pub = n_pub + 1;
            cy = cy + 1;
        end
    end

    // 每个场景都从复位开始：`eth_pend` 只在"ETH 是当前片源且这一场取走了它"时清，
    // 所以 S1 结束后那位可能还是 1 —— 不清就会把上一个场景的欠账算进下一个场景的读数里
    // （今晚 S6 第一次读到 2 就是这个原因，不是 DUT 错）。顺带让 S7 能判复位卫生。
    task run(input integer ns, input integer m, input integer every);
        begin
            @(negedge clk); rst_n = 0;
            repeat (3) @(negedge clk);
            mode = m; new_every = every; cy = 0; fi = 0; n_fs = 0; n_eth = 0; n_pub = 0;
            n_pulse = 0; n_count = 0;
            if (m == 5) one_shot = 1;
            @(negedge clk); rst_n = 1;         // 释放后 DUT 的 win_cnt 从 0 起，窗口与场网格对齐
            nstop = ns * F;
            while (cy < nstop) @(negedge clk);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);

        // ---- S1 ETH，每 2 场一帧 ⇒ 每窗口 20/2 = 10（老写法这里会给 20）----
        owner_eth = 1; fb_vis = 1; tb_pend = 0;
        run(3, 1, 2);
        $display("INFO S1 fps_q=%0d 期望=%0d 场=%0d 发布判定=%0d 实际脉冲=%0d new_shown=%0d",
                 fps_q, NFS/2, n_fs, n_eth, n_pulse, n_count);
        chk("S1 eth source every 2 fields -> fps_q == fields_per_window/2 (10), not field count (20)",
            fps_q == NFS/2);
        // 地板判的是"发布次数 == DUT 真正认账的次数"（30 == 30）：少一条就是丢帧。
        // `n_pulse` 只印不判 —— 释放复位的缝上它会多读到一个来自上一拍的脉冲（TB 记账的边界，
        // 不是 DUT 的行为；把它写进期望值等于把尺子绑在缝上）。
        chk("S1a opportunity floor: 60 field starts, 30 publishes -> 30 counted (none dropped)",
            n_fs == 3*NFS && n_eth == 30 && n_count == 30);

        // ---- S2 PS/SD，每 4 场取走一帧 ⇒ 每窗口 20/4 = 5 ----
        owner_eth = 0; fb_vis = 1;
        run(3, 2, 4);
        $display("INFO S2 fps_q=%0d 期望=%0d 场=%0d publish=%0d", fps_q, NFS/4, n_fs, n_pub);
        chk("S2 sd source every 4 fields -> fps_q == fields_per_window/4 (5)", fps_q == NFS/4);
        chk("S2a opportunity floor: PS published on every 4th field (15 in 3 windows)",
            n_pub == 3*NFS/4);

        // ---- S3 没有新内容 ⇒ 必须是 0（"屏冻住而格子里还在数面板"那件事）----
        owner_eth = 0; fb_vis = 1;
        run(2, 3, 0);
        $display("INFO S3 fps_q=%0d 场=%0d owner=%b fb_vis=%b", fps_q, n_fs, owner_eth, fb_vis);
        chk("S3 no new content -> fps_q == 0 (the cell must not keep counting the panel)", fps_q == 0);
        chk("S3a opportunity floor: the two windows really ran 40 field starts", n_fs == 2*NFS);

        // ---- S4 图卡态：每场都新 ⇒ 期望 = 场数。反配对：防 S3 把三格一起判成 0 ----
        owner_eth = 0; fb_vis = 0;
        run(2, 4, 0);
        $display("INFO S4 fps_q=%0d 期望=%0d 场=%0d", fps_q, NFS, n_fs);
        chk("S4 card mode (every field new) -> fps_q == field count (20)", fps_q == NFS);
        chk("S4a opportunity floor: the fb_vis==0 path was exercised 40 times", n_fs == 2*NFS);

        // ---- S5 口径本身：默认窗口常数必须是 49_999_999（板载 50 MHz ⇒ 正好 1.000 s）----
        chk("S5 default WIN_LAST == 49999999 (1.000 s at the 50 MHz board clock)",
            u_full.WIN_LAST == 49999999);

        // ---- S7 复位卫生：三个状态位都必须被清（#124 那一族：事件寄存器漏进复位清单）----
        owner_eth = 1; fb_vis = 1;
        @(negedge clk); rst_n = 0;
        repeat (4) @(negedge clk);
        chk("S7 reset clears acc, eth_pend and fps_q (no stale state across a re-init)",
            u_dut.acc == 0 && u_dut.eth_pend === 1'b0 && fps_q == 0);
        $display("INFO S7 acc=%0d pend=%b fps_q=%0d", u_dut.acc, u_dut.eth_pend, fps_q);
        @(negedge clk); rst_n = 1;
        repeat (2) @(negedge clk);

        // ---- S6 唯一的一帧与场起点**同一拍**到达：这一场不计数，但它不许被丢掉 ----
        //   期望形状：整个窗口只数到 1（下一场补计）。如果优先级写反成"清除赢"，那一帧会被
        //   整帧丢掉 ⇒ 这里读到 0，S6b 就红；如果在同拍那一格就计数，S1/S2 的比例会先出错。
        owner_eth = 1; fb_vis = 1;
        run(1, 5, 0);
        $display("INFO S6 fps_q=%0d acc=%0d pend=%b eth_new 发了 %0d 次",
                 fps_q, u_dut.acc, u_dut.eth_pend, n_eth);
        chk("S6 one same-cycle ETH frame yields exactly one counted field (not zero)",
            fps_q == 1);
        chk("S6b ...and the pending flag was consumed by the next field", u_dut.eth_pend === 1'b0);
        chk("S6c opportunity floor: exactly one same-cycle eth_new pulse reached the DUT",
            n_pulse == 1);
        $display("INFO S6 new_shown 实际次数=%0d（同拍那一次不该计入它落下的那一场）", n_count);

        $display("");
        if (errors == 0) $display("RESULT tb_shown_rate PASS");
        else             $display("RESULT tb_shown_rate FAIL nfail=%0d", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL tb_shown_rate timeout");
        $display("RESULT tb_shown_rate FAIL nfail=timeout");
        $finish;
    end

endmodule
