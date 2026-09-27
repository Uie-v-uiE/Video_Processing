`timescale 1ns/1ps
// tb_v102_src_life —— `src_life` 的逐条判据（ISSUES #94）。
// 为什么单独一份台架：#94 的症状是"屏幕永久冻在最后一帧"，而"永久"只有在**时间轴上喂出
// "应用不再发帧了"**才看得见；顶层那份台架（tb_v98）一次要跑 75 分钟，用它调一个 30 帧的
// 看门狗等于拿卡车送信。几何/链路仍然归 tb_v98，这里只管"此刻还有没有片源"。
// 判据一律 ASCII（#55：cp936 控制台会把 CJK 打乱码，判据名乱码等于没有判据）。
module tb_v102_src_life;
    localparam integer CLK_HZ = 50_000_000;
    localparam integer TO_MS  = 500;
    // ⚠ 期望值**故意写成字面量、不共用模块里的式子**：共用了就会共用同一个 bug。
    //   第一版两边都写 `(TO_MS*CLK_HZ/1000)/840_000+1`，而 500*50_000_000 = 2.5e10 在
    //   Verilog 的 32 位 integer 里回绕 ⇒ 一起算出"1 帧"，S9 会绿得像验证过，
    //   上板就是"每次呼吸都误判 PS 掉线"。手算：500 ms @50 MHz = 25e6 拍；
    //   一帧 1344*625 = 840_000 拍；25e6/840000 = 29.76 ⇒ 第 30 个帧节拍必须判超时。
    localparam integer TO_FRAMES = 30;
    // 固件 keepalive 的约定间隔（ms）——S12 用它证明"按约定发就不会被误判"。
    localparam integer KEEPALIVE_MS = 100;
    localparam integer KEEPALIVE_FRAMES = (KEEPALIVE_MS * (CLK_HZ/1000)) / 840_000;   // ≈ 5.95 ⇒ 6

    reg clk = 0, rst_n = 0, frame_start = 0;
    reg ps_pub = 0, eth_owner = 0, mode_eth = 0, mode_ps = 0;
    wire ps_src_now, have_src, ps_no_pub;

    always #10 clk = ~clk;                          // 50 MHz

    src_life #(.CLK_HZ(CLK_HZ), .HB_TIMEOUT_MS(TO_MS)) dut (
        .clk(clk), .rst_n(rst_n), .frame_start(frame_start), .ps_pub(ps_pub),
        .eth_owner(eth_owner), .mode_eth(mode_eth), .mode_ps(mode_ps),
        .ps_src_now(ps_src_now), .have_src(have_src), .ps_no_pub(ps_no_pub)
    );

    integer errors = 0, i, frames_seen, low_seen;


    task settle; begin @(posedge clk); #3; end endtask
    task line(input [8*64-1:0] name, input cond);
        begin
            // 注意：`cond` 是**调用那一刻**就求好值的输入实参 —— 在 task 里面延时**毫无用处**。
            //   所以采样点的对齐必须放在**调用之前**（`settle;` 就是干这个的）。
            //   为什么必须有它：激励是阻塞赋值、DUT 的输入端口与输出 `assign` 各自是一级事件，
            //   同一时间步里读到的是"上一拍的端口值"—— S7 就是这么先红后"两次跑出不同结论"的
            //   （同一份快照两次结果差 1 ns ⇒ 采样点落在沿上）。老规矩"激励在 #1 之后才改"
            //   的另一半是"**判之前也过一次沿**"。
            if (cond !== 1'b1) begin errors = errors + 1; $display("FAIL %0s (t=%0t)", name, $time); end
            else $display("PASS %0s", name);
        end
    endtask

    // 一个"显示帧"：帧首脉冲 + 几拍间隔（这里只喂看门狗的节拍，不模拟整帧）
    task one_frame; begin @(posedge clk); #1; frame_start = 1; @(posedge clk); #1; frame_start = 0;
                          repeat (3) @(posedge clk); end endtask
    task frames(input integer n); integer k; begin for (k=0;k<n;k=k+1) one_frame; end endtask
    task publish; begin @(posedge clk); #1; ps_pub = 1; @(posedge clk); #1; ps_pub = 0; end endtask
    // 模式/归属也要在沿后改：直接在初始块里写 `mode_ps = 1'b1;` 然后立刻判，判的是
    //   **还没传播进 DUT 端口的那一份**（端口的值本身是一级连续赋值）—— S7 就是这样红了两次，
    //   而 DUT 一直是对的（同一拍上用 `dut.mode_ps` 与 TB 的 `mode_ps` 能看出差一个 delta）。
    task set_modes(input m_e, input m_p, input eo);
        begin @(posedge clk); #1; mode_eth = m_e; mode_ps = m_p; eth_owner = eo; end
    endtask

    initial begin
        repeat (4) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);

        // ---- S1 复位：谁都没发过帧 ⇒ 屏上该是图卡，且"没有发布"这件事是**已知状态**不是 X ----
        settle; line("S1 reset means no source", have_src === 1'b0 && ps_src_now === 1'b0 && ps_no_pub === 1'b1);

        // ---- S2 PS 在发帧 ⇒ 该画帧缓存 ----
        publish; one_frame;
        settle; line("S2 publishing => show fb", ps_src_now === 1'b1 && have_src === 1'b1 && ps_no_pub === 1'b0);

        // ---- S3 发帧停了（应用挂住）⇒ 超时后必须判"没片源" ----
        frames(TO_FRAMES + 2);
        settle; line("S3 publish silence trips watchdog", ps_no_pub === 1'b1 && ps_src_now === 1'b0 && have_src === 1'b0);

        // ---- S9 超时是量出来的：从最后一个沿数到 lost 拉高，正好 TO_FRAMES 个帧节拍 ----
        @(posedge clk); #1; rst_n = 0; repeat (2) @(posedge clk); rst_n = 1;
        publish;                                  // 计时从这个沿起算
        frames_seen = 0;
        while (ps_no_pub !== 1'b1 && frames_seen < 400) begin one_frame; frames_seen = frames_seen + 1; end
        $display("INFO S9 frames=%0d expected=%0d (TO_MS=%0d)", frames_seen, TO_FRAMES, TO_MS);
        settle; line("S9 timeout equals the named constant",
             frames_seen >= TO_FRAMES - 1 && frames_seen <= TO_FRAMES + 1);

        // ---- S10 反例：超时之后重新开始发帧，判据必须自己退回去（不许"红过一次就永远红"）----
        publish; one_frame;
        settle; line("S10 a new publish clears it", ps_no_pub === 1'b0 && ps_src_now === 1'b1 && have_src === 1'b1);

        // ---- S12 按固件约定（每 KEEPALIVE_MS 发一次）永远不会被误判成掉线 ----
        //   这条就是"`frame N` / `stop` 故意停帧不许被看门狗误伤"的硬件侧保证：
        //   应用只要按约定的节拍重发同一帧，超时就必须一直不成立。
        low_seen = 0;
        for (i = 0; i < 40; i = i + 1) begin
            frames(KEEPALIVE_FRAMES); publish;
            if (ps_no_pub === 1'b1) low_seen = low_seen + 1;
        end
        settle; line("S12 keepalive cadence never trips", low_seen == 0 && ps_src_now === 1'b1);

        // ---- S5 拔卡后停止发帧 → 落到图卡；卡插回、重新发帧 → 画面必须回来 ----
        frames(TO_FRAMES + 2);
        settle; line("S5a stopped publishing falls back", have_src === 1'b0);
        publish; one_frame;
        settle; line("S5b resuming publishing recovers", have_src === 1'b1 && ps_no_pub === 1'b0);

        // ---- S6 锁网络（`src 1`）的语义：PS 不再发帧也不能被看门狗抢走 ----
        set_modes(1'b1, 1'b0, 1'b0); frames(TO_FRAMES + 2);
        settle; line("S6 pinned ETH keeps its last frame", have_src === 1'b1);

        // ---- S7 锁 SD 而 PS 没货：这条路真的没东西可看了 ⇒ 落图卡（不拿"锁"当遮羞布）----
        set_modes(1'b0, 1'b1, 1'b0);
        settle; line("S7 pinned SD with no publishes => test card", have_src === 1'b0);
        set_modes(1'b0, 1'b0, 1'b0); publish; one_frame;

        // ---- S8 自动模式：ETH 活着归 ETH；交还的那一拍起看 PS，不留粘滞 ----
        set_modes(1'b0, 1'b0, 1'b1); frames(1);
        settle; line("S8a auto with live ETH shows fb", have_src === 1'b1);
        set_modes(1'b0, 1'b0, 1'b0); frames(TO_FRAMES + 2);
        settle; line("S8b after handover with no PS publishes => test card", have_src === 1'b0);
        set_modes(1'b0, 1'b0, 1'b0); publish; one_frame;
        settle; line("S8c PS picked it up after the cable", have_src === 1'b1);

        // ---- S11 三个输出任何一拍都不许是 X/Z（判据不许在空集上成立）----
        settle; line("S11 no X on the outputs",
             (ps_src_now ^ ps_src_now) === 1'b0 && (have_src ^ have_src) === 1'b0
             && (ps_no_pub ^ ps_no_pub) === 1'b0);
        if (errors == 0) $display("RESULT tb_v102_src_life PASS");
        else             $display("RESULT tb_v102_src_life FAIL nfail=%0d", errors);
        $finish;
    end
endmodule
