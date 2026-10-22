`timescale 1ns/1ps
// 功能：被测模块 `zoom_snap`（实例 u_dut）与下游 `snap_cross`（实例 u_x，.W(20)、.DST_HZ(100_000_000)、
//        .HB_TO_MS(200)）；覆盖点＝总线没换值时一个沿都不发、20 位各自的拼接顺序、每次真实变化恰好一个沿、
//        沿相对帧首的滞后拍数、目的域只出现源域发布过的值、末态跟随最新一帧、自动呼吸不改变以上、
//        心跳在翻时 hb_gone 放开、rot_forced 单独换值走同一套帧首协议。
// 激励与检查：双钟——clk_axi 由 #5 翻转（10 ns），clk_pix 由 #20 翻转（40 ns 一个像素周期），帧周期
//        FRAME_CY 故意压成 24 个像素周期，设计滞后 LAG_NS=8*PIX_NS=320 ns；rst_n 在一个像素沿后 #1
//        置 1，前后各 repeat(4) @(posedge clk_axi)。publish(m,s,c,a,d,v) 在帧首摆好六位、发一拍
//        frame_start，把整条 {rf,m,s,c,a,d,v} 记进白名单 seen_vals 并翻一次 hb_tog，凑满一帧；
//        settle 等 30 个 axi 拍（3 级同步加余量）。序列：Z1 连发 20 帧同值（全 0）；Z2 六步逐字段点亮
//        （zman=1 ⇒ zsel=3'd5 ⇒ zcode=3'd7 ⇒ zactive=1 ⇒ zdir=1 ⇒ zinv=10'h2AB）；Z3 走完 8 档
//        zinv=256+97*i；Z7 跑 40 帧呼吸（每帧换值，zcode=i%8、zdir=i%2）；Z9 六位与基准帧一模一样、
//        只翻 rf。判定：Z0 bus===20'd0 且 tog_cnt==0 且 bus_q===20'd0；Z1 tog_cnt==0 且 bus_q 为全 0；
//        Z2a..Z2f bus_q === 对应拼接 {zman,zsel,zcode,zactive,zdir,inv}；Z3 沿数增量 ==8；
//        Z4 lag_min==lag_max==LAG_NS（两端都卡，只卡下限会让"根本没发沿"顶着初值假绿）；Z5 torn==0；
//        Z6 bus_q===seen_vals[n_seen-1]；Z7 沿数增量 ==40 且 Z7b/Z7c 同判；Z8 hb_gone===1'b0；
//        Z9a bus===(v8|20'h80000)、Z9b 沿数增量 ==1、Z9c torn==0、Z9d bus[19]===1'b0 且沿数增量 ==2。
// 预期结果：通过时每条 expect 打 "PASS <判据名>"，中间一行 "  stats: edges=<n> published=<n>
//        lag=320..320 ns (want 320)"，末行 PASS tb_zoom_snap；失败时对应判据打
//        "FAIL <判据名> (t=<时刻>)"，撕烈由探测器打前 3 条 "  DBG tear: bus_q=<bin> never published
//        (t=<时刻>)" 并累加 torn，沿发在两拍或多发会让 Z3/Z7 的增量翻倍、同拍发沿会让 Z4 的 lag 区间
//        不含 320，末行变 FAIL tb_zoom_snap errors=<n>，#2_000_000 看门狗到期打
//        FAIL tb_zoom_snap timeout (still running at <t>)。
// 台架：src/rtl/process/zoom/zoom_snap.v + 下游 snap_cross（V8-8 最后一跳 / 任务 #45）
// 测的是**机制**，不是缩放算得对不对（那由 tb_v94 逐档对表）。跑：bash sim/run_one.sh tb_zoom_snap
// Z1 总线没换值 ⇒ 一个沿都不发（对照：每帧都发沿的写法会多算）；Z2 19 位各就各位（对照：拼接顺序写反 ⇒ 字段错位立刻红）
// Z3 每次真实变化恰好一个沿（对照：沿发在两拍 ⇒ 计数翻倍）；Z5 目的域见过的每个值都必须是源域发过的（撕烈 = 冒出第三个值）
// Z4 沿必须晚于帧首**正好 8 个像素周期**（对照：同拍发沿这条红，而"末态检查"抓不到）；Z6 末态停在最后发出的那一档（抓"永久落后一档"）；Z7 自动呼吸不改变以上任何一条
// ⚠ 帧周期故意压成 24 拍（硬件 420 000）：机制预算全按像素周期计、与帧长无关，压缩等于逼出帧间重叠；真机余量大四个数量级，这里过了硬件就过了。判据标签只写 ASCII（见 ISSUES #68 附记）
module tb_zoom_snap;
    reg clk_axi = 1'b0, clk_pix = 1'b0, rst_n = 1'b0;
    always #5  clk_axi = ~clk_axi;        // 100 MHz：与 axi_clk 同名同频
    always #20 clk_pix = ~clk_pix;        //  25 MHz ：取整数周期，Z4 的"8 拍 = 320 ns"才量得准

    // ---- 源域激励（等价于 zoom_ctrl 在帧首交出来的那五个量）----
    reg        frame_start = 1'b0;
    reg        zman = 1'b0;
    reg  [2:0] zsel = 3'd0;
    reg  [2:0] zcode = 3'd0;
    reg        zactive = 1'b0;
    reg        zdir = 1'b0;
    reg  [9:0] zinv = 10'd0;
    reg        rf   = 1'b0;               // #175：旋转钳旗 = 总线的第 20 位（bit19）。默认 0

    wire [19:0] bus;
    wire        bus_tog;
    zoom_snap u_dut (
        .pix_clk(clk_pix), .pix_rst_n(rst_n), .frame_start(frame_start),
        .zman(zman), .zsel(zsel), .zoom_code(zcode), .zoom_active(zactive),
        .zoom_dir(zdir), .inv_scale(zinv),
        .rot_forced(rf), .bus(bus), .bus_tog(bus_tog));

    // 下游：与硬件同一对参数（W=20 / DST_HZ=100 MHz / HB_TO_MS=200）—— #175 起总线多一位
    wire [19:0] bus_q;
    wire        hb_gone, hb_slow;
    reg         hb_tog = 1'b0;
    snap_cross #(.W(20), .DST_HZ(100_000_000), .HB_TO_MS(200)) u_x (
        .dst_clk(clk_axi), .dst_rst_n(rst_n),
        .bus(bus), .bus_tog(bus_tog), .hb_tog(hb_tog),
        .bus_q(bus_q), .hb_gone(hb_gone), .hb_slow(hb_slow));

    localparam integer PIX_NS   = 40;         // 25 MHz
    localparam integer LAG_NS   = 8 * PIX_NS; // 设计规定：捕获后 8 拍才发沿
    localparam integer FRAME_CY = 24;         // 见文件头的"帧周期压缩"

    integer errors = 0, i, f, k;
    integer e8 = 0;                     // Z8：进这一段时的沿数
    reg [19:0] v8 = 20'd0;             // Z8：基准帧的整条总线
    integer tog_cnt = 0;                      // 源域发了几个沿
    time    fs_t = 0, tg_t = 0;               // 最近一次采样沿 / 最近一次发沿
    integer lag_min = 1 << 30, lag_max = 0;   // Z4 要的是"正好 8 拍"，两端都卡
    reg [19:0] seen_vals [0:159];             // 源域**真的发出去过**的值（Z5 的白名单）
    integer    n_seen = 0;
    integer    torn = 0;

    task expect(input [639:0] name, input cond);
        begin
            if (cond !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL %0s (t=%0t)", name, $time);
            end else $display("PASS %0s", name);
        end
    endtask

    // 数沿 + 记时：跟的是源域那根线本身，不经过任何同步
    always @(bus_tog) if (rst_n) begin
        tog_cnt = tog_cnt + 1;
        tg_t    = $time;
        if (tg_t - fs_t < lag_min) lag_min = (tg_t - fs_t);
        if (tg_t - fs_t > lag_max) lag_max = (tg_t - fs_t);
    end

    // 一帧的激励：摆好这一帧要用的值 → 下一个像素沿让 DUT 同时采到脉冲与新值。
    // #1 是必需的：不加就是在采样沿上做阻塞赋值，与 DUT 的采样同拍竞态（读回来的会是半新半旧）。
    task publish(input m, input [2:0] s, input [2:0] c, input a, input d, input [9:0] v);
        begin
            @(posedge clk_pix); #1;
            zman = m; zsel = s; zcode = c; zactive = a; zdir = d; zinv = v;
            frame_start = 1'b1;
            @(posedge clk_pix);                       // ← DUT 在这一拍采到脉冲
            fs_t = $time;
            #1; frame_start = 1'b0;
            // #175：白名单记的是"源域真的发出去过的整条总线"⇒ 新位也要进，顺序与 DUT 的 in_bus 一致
            seen_vals[n_seen] = {rf, m, s, c, a, d, v}; n_seen = n_seen + 1;
            hb_tog = ~hb_tog;                         // 硬件里 = sof_tgl，每帧翻一次
            repeat (FRAME_CY - 2) @(posedge clk_pix); // 凑满一帧
        end
    endtask

    task settle; begin repeat (30) @(posedge clk_axi); end endtask   // 3 级同步 + 采样 + 余量

    function is_published; input [19:0] v;
        begin
            is_published = 1'b0;
            for (k = 0; k < n_seen; k = k + 1) if (seen_vals[k] === v) is_published = 1'b1;
        end
    endfunction

    // 撕烈探测器：逐 axi 拍盯 bus_q（复位值 0 也算"发过"，所以白名单先塞一个 0）
    always @(posedge clk_axi)
        if (rst_n && !is_published(bus_q)) begin
            torn = torn + 1;
            if (torn < 4) $display("  DBG tear: bus_q=%b never published (t=%0t)", bus_q, $time);
        end

    initial begin
        seen_vals[0] = 20'd0; n_seen = 1;             // 复位态
        repeat (4) @(posedge clk_axi);
        @(posedge clk_pix); #1; rst_n = 1'b1;
        repeat (4) @(posedge clk_axi);
        expect("Z0 reset: bus=0, no edge, bus_q=0", bus === 20'd0 && tog_cnt == 0 && bus_q === 20'd0);

        // ---- Z1 全零值连发 20 帧：一个沿都不许有 ----
        for (f = 0; f < 20; f = f + 1) publish(1'b0, 3'd0, 3'd0, 1'b0, 1'b0, 10'd0);
        settle;
        expect("Z1 20 identical frames produce zero edges", tog_cnt == 0 && bus_q === 19'd0);

        // ---- Z2 逐字段点亮：19 位各就各位 ----
        publish(1'b1, 3'd0, 3'd0, 1'b0, 1'b0, 10'd0);   settle;
        expect("Z2a zman -> bit18 only", bus_q === {1'b1, 18'd0});
        publish(1'b1, 3'd5, 3'd0, 1'b0, 1'b0, 10'd0);   settle;
        expect("Z2b zsel=5 -> bits[17:15]", bus_q === {1'b1, 3'd5, 15'd0});
        publish(1'b1, 3'd5, 3'd7, 1'b0, 1'b0, 10'd0);   settle;
        expect("Z2c zoom_code=7 -> bits[14:12]", bus_q === {1'b1, 3'd5, 3'd7, 12'd0});
        publish(1'b1, 3'd5, 3'd7, 1'b1, 1'b0, 10'd0);   settle;
        expect("Z2d zoom_active -> bit11", bus_q === {1'b1, 3'd5, 3'd7, 1'b1, 11'd0});
        publish(1'b1, 3'd5, 3'd7, 1'b1, 1'b1, 10'd0);   settle;
        expect("Z2e zoom_dir -> bit10", bus_q === {1'b1, 3'd5, 3'd7, 1'b1, 1'b1, 10'd0});
        publish(1'b1, 3'd5, 3'd7, 1'b1, 1'b1, 10'h2AB); settle;
        expect("Z2f inv_scale -> bits[9:0]", bus_q === {1'b1, 3'd5, 3'd7, 1'b1, 1'b1, 10'h2AB});

        // ---- Z3 八档走完：每档恰好一个沿 ----
        begin : z3
            integer before;
            before = tog_cnt;
            for (i = 0; i < 8; i = i + 1) begin
                publish(1'b1, i[2:0], i[2:0], 1'b0, 1'b0, (10'd256 + i[9:0] * 10'd97));
                settle;
            end
            expect("Z3 8 real changes produce exactly 8 edges", tog_cnt - before == 8);
        end

        // ---- Z4 沿与帧首的关系：正好 8 个像素周期，不多不少 ----
        // 上限同样要紧：只卡下限的话，"根本没发过沿"会顶着 lag_min=初值 假绿。
        expect("Z4 edge lags frame_start by exactly 8 pix clocks",
               lag_min == LAG_NS && lag_max == LAG_NS);

        // ---- Z5 全程没有撕烈 ----
        expect("Z5 no unpublished value ever reached the destination", torn == 0);

        // ---- Z6 末态停在最后发出去的那一档 ----
        expect("Z6 bus_q equals the last published value", bus_q === seen_vals[n_seen-1]);

        // ---- Z7 自动呼吸：每帧都换值 ⇒ 每帧一个沿，末态依旧准确 ----
        begin : z7
            integer before7;
            before7 = tog_cnt;
            for (i = 0; i < 40; i = i + 1) begin
                publish(1'b0, 3'd4, (i % 8), 1'b1, (i % 2), (10'd256 + i[9:0]));
                @(posedge clk_axi);
            end
            settle;
            expect("Z7 40 breathing frames -> 40 edges", tog_cnt - before7 == 40);
            expect("Z7b bus_q tracked the newest frame", bus_q === seen_vals[n_seen-1]);
            expect("Z7c still no torn value", torn == 0);
        end

        // ---- Z8 心跳在翻 ⇒ hb_gone 必须已经放开（lane23 的 alive 位就取这里的反面）----
        // 超时那一侧（200 ms 不翻就报 gone）是 snap_cross 自己台架的活，这里不重测它的常数。
        expect("Z8 heartbeat ticking -> hb_gone released", hb_gone === 1'b0);

        $display("  stats: edges=%0d published=%0d lag=%0d..%0d ns (want %0d)",
                 tog_cnt, n_seen, lag_min, lag_max, LAG_NS);
        // ---------- Z8（#175）：六位输入一字不动、只翻旋转钳旗 ----------
        // 复位到这里 rf 一直是 0 ⇒ 前面所有判据看到的都是 bit19=0。这一条要钉的是：
        //   ① 新位仍守"帧首整拍换 + 一次变化恰好一个沿"；② 撕烈探测器不许因此误报（白名单已含新位）。
        //   少了这条，"新位绕过帧首直接挂在组合逻辑上"那种写法能一路绿灯。
        publish(1'b0, 3'd0, 3'd0, 1'b0, 1'b0, 10'd0);   settle;   // 基准帧：整条总线回到全 0
        e8 = tog_cnt; v8 = bus;
        rf = 1'b1;
        publish(1'b0, 3'd0, 3'd0, 1'b0, 1'b0, 10'd0);   settle;   // 六位与基准一模一样，只有 rf 变了
        expect("Z9a only bit19 moved (frame-boundary capture)", bus === (v8 | 20'h80000));
        expect("Z9b a lone rot_forced change = exactly one edge", (tog_cnt - e8) == 1);
        expect("Z9c the tearing detector stayed quiet across it", torn == 0);
        rf = 1'b0;
        publish(1'b0, 3'd0, 3'd0, 1'b0, 1'b0, 10'd0);   settle;   // 撤掉：可逆，且又一个沿
        expect("Z9d clearing rot_forced is reversible, one more edge",
               (bus[19] === 1'b0) && ((tog_cnt - e8) == 2) && (torn == 0));

        if (errors == 0) $display("PASS tb_zoom_snap");
        else             $display("FAIL tb_zoom_snap errors=%0d", errors);
        $finish;
    end

    initial begin : watchdog
        #2_000_000;
        $display("FAIL tb_zoom_snap timeout (still running at %0t)", $time);
        $finish;
    end
endmodule
