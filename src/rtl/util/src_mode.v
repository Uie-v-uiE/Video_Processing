`timescale 1ns/1ps
// src_mode —— 长按事件（sys_clk 域的翻转位）→ 片源模式（本域的四态格雷码寄存器）。本模块在像素钟 clk_pix：
//   模式的消费者（"看哪一路"）在这一域。单独成模块是因为这段以前写在 pl_video_top 里 ⇒ 没有任何台架，
//   而它是"能不能手动锁住某一路片源"的唯一入口（#28 第一次上板跑交接判据就红了）。
// ⚠ 根因一句话：**同步链的复位值必须与源头复位后的值一致，否则"上电"本身就是一次边沿**。旧写法 lsync 复位成
//   3'b111 而 key_long.tog 复位是 0 ⇒ 链里灌进的第一个 0 让 lsync[1]^lsync[2] 为真一拍，一次都没按的板子白白
//   走一步 AUTO→锁 ETH；而锁 ETH 在 src_arb 里是 force_eth=1 ⇒ owner_eth 永远为 1、"停流交回"永不发生。
module src_mode (
    input  wire       clk,        // 像素钟 clk_pix：模式的消费者（看哪一路）在这一域
    input  wire       rst_n,
    input  wire       ltog,       // 来自 sys_clk 域的长按翻转位（`key_long` 的 tog）
    input  wire       eth_now,    // 此刻屏幕上是不是 ETH（AUTO 下 = owner_eth），只用来挑下一态
    // ---- V8-2：让**串口命令**也能定住片源模式（以前环只有按键一个入口 ⇒ 停在"锁 ETH"而当下没有流时，
    // 屏幕冻在最后一帧，要再长按三次才出来；`arb_handover_test.mjs` 也没法保证起点）。
    // 跨法：`ov_tog` 走与 `ltog` 同一种 3 级链 + "边沿才采"的规矩 —— 码值在翻转**之前**就写好并稳定（PS 那边
    // 是两条独立 GPIO 写，顺序由 main.c 保证）⇒ 边沿到链尾时码值至少稳定 3 个像素周期，采到的必是完整值。
    // **不许**把 2 位码各自打 3 拍再拼（#52/#59 两次都是那形状）。
    input  wire [1:0] ov_code,    // axi 域准静态：00 自动 / 01 锁 ETH / 11 锁 SD / 10 锁 TEST（词与屏上同源）
    input  wire       ov_tog,     // axi 域翻转位：翻一次 = "上面那个码是新写的，收下"
    output wire [1:0] mode        // 生效模式（覆盖期间 = 命令给的码；否则 = 按键环）
);
    // 模式用**格雷码**排（00→01→11→10→00），档名与屏上那三个词同源：AUTO / ETH / SD / TEST（编号一个没动：
    // M_SD=3、M_TEST=2；旧文档写"锁 PS / 锁图卡"的地方 = 现在的 SD / TEST 档）。下一状态**按位**写
    // `{mode[0], ~mode[1]}`：`ms0 <= mode` 那对同步器要靠"每一位只依赖一个源触发器"才安全，写成 if/(mode==…)
    // 的比较式会被综合认成 FSM 并重编为 one-hot，格雷码的意义就在实现层被抹掉（实测见 ISSUES #49）。
    // ISSUES #55 第二条：**离开 AUTO 时不许走成一格"看不出变化"的模式**（老环 AUTO→锁ETH→锁SD，而 AUTO 下屏幕
    // 本来就是 ETH ⇒ 第一格是空动作，用户念的"切到 SD 总要按第二次"）。现在按 eth_now 挑目标，两个去向都只翻 1 位。
    localparam [1:0] M_AUTO = 2'd0, M_ETH = 2'd1, M_SD = 2'd3, M_TEST = 2'd2;

    (* ASYNC_REG = "TRUE" *) reg [2:0] lsync;
    (* ASYNC_REG = "TRUE" *) reg [2:0] osync;
    // 码也必须走一条**与翻转位等长**的延迟线，然后在"沿到链尾"那一刻取延迟线尾部那一份。
    // 为什么不能直接采 ov_code：PS 是两笔相邻的 32 位写（先码后沿），两笔只差几十 ns，
    // 而沿要被 3 级链认下来才是采样时刻 —— 中间这段时间里 `ov_code` 早就是新值了，
    // 看着没事，实则是"采到了沿之后才写的码"，一旦两笔写之间被中断插进来就变味。
    // 延迟线对齐之后，取到的必然是**沿出发那一刻**已经站住的码，两笔写隔多久都无所谓。
    reg [1:0] ovc0, ovc1, ovc2;
    reg        prev;              // 链尾已经认过的稳定值
    reg        oprev;
    reg [2:0]  settle;            // 复位后的"灌满期"计数
    reg [1:0]  ring;              // 按键环自己的状态
    reg        ov_en;             // 1 = 命令覆盖中（长按一次就交还给环）
    reg [1:0]  ov_act;            // 覆盖期间生效的码
    // 生效模式**必须是一个触发器**，不能是 `ov_en ? ov_act : ring` 这个组合式：
    // 下游 `pl_video_top` 拿 `mode` 去喂 axi 域的 3 级同步链（ms0/ms1/ms2），
    // 组合式等于"同步器前面挂一级 LUT" ⇒ `report_cdc` 立刻把 `clkout0_1→clk_fpga_0`
    // 整对提成 Critical（build #40 实测 27 端点 / 2 unsafe，与 #34 那次同一组数字），
    // 门禁第 6 项因此判红。多这一个 FF 换回"配对集合不新增"，语义只差一拍（模式是 ms 级慢变量）。
    reg [1:0]  mode_q;
    assign mode = mode_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lsync  <= 3'b000;
            osync  <= 3'b000;
            {ovc2,ovc1,ovc0} <= {M_AUTO,M_AUTO,M_AUTO};
            prev   <= 1'b0;
            oprev  <= 1'b0;
            settle <= 3'd0;
            ring   <= M_AUTO;
            ov_en  <= 1'b0;
            ov_act <= M_AUTO;
        end else begin
            lsync <= {lsync[1:0], ltog};
            osync <= {osync[1:0], ov_tog};
            {ovc2,ovc1,ovc0} <= {ovc1,ovc0,ov_code};
            if (settle != 3'd7) begin
                settle <= settle + 3'd1;
                prev   <= lsync[2];        // 灌满期里让 prev 跟住链尾，别把历史当事件
                oprev  <= osync[2];        // 同理：复位前那次命令写不该在复位后白送一次覆盖
            end else begin
                // 命令优先：覆盖生效期间，长按**只做一件事 = 把控制权交还给按键环**
                // （同一次按压既交还又走一步，会让人猜不透"这次按到底动了没有"）
                // ⚠ `osync[2]` 必须是实打实的 0/1 才算边沿：台架里没接这个输入的顶层例化
                //   （tb_v6 / tb_v81 / tb_v89 那几份）会让它浮空成 X，而 `X !== 0` 恒真 ⇒
                //   每拍都"收到一条命令"，模式变成 X，整条片源通路在台架里瞎掉。
                //   硅片上没有 X，这条守卫不花一个 LUT，却决定"忘了接线"是可见还是不可见。
                if ((osync[2] === 1'b1 || osync[2] === 1'b0) && osync[2] !== oprev) begin
                    oprev  <= osync[2];
                    ov_act <= ovc2;        // ← 沿出发那一刻的码，不是"现在的码"
                    // 码 = AUTO 时不留覆盖，而是**把环也清回 AUTO**：
                    // 否则 `src auto` 之后一按长按，会交还出一个"上次长按留下的锁"，
                    // 现象就是"我明明回了自动，怎么又钉住了"。
                    if (ovc2 == M_AUTO) begin
                        ov_en <= 1'b0;
                        ring  <= M_AUTO;
                    end else ov_en <= 1'b1;
                end else if (lsync[2] !== prev) begin
                    prev <= lsync[2];
                    if (ov_en) ov_en <= 1'b0;
                    else ring <= (ring == M_AUTO) ? (eth_now ? M_SD : M_ETH)
                                                  : {ring[0], ~ring[1]};
                end
            end
        end
    end

    // 生效模式的**唯一驱动**：寄存一拍再出去（为什么必须是触发器而不是组合 mux，见上面 mode_q 的注释）。
    // 单独一个 always 块是有意的 —— 两个块都赋 mode_q 就是多驱动 net，
    // 综合会把它接成常量而仿真看不出来（#61 那一课）。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mode_q <= M_AUTO;
        else        mode_q <= ov_en ? ov_act : ring;
    end
endmodule

