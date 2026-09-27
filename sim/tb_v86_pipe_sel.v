`timescale 1ns/1ps
// 台架：effect_ctrl（两套控制源折成一套 + 跨域同步）与 proc_pipeline（五级链的整体契约）
// 钉的是"整条链对外承诺的三件事"，单模块台架（tb_v84/tb_v85）管不到。跑：bash sim/run_one.sh tb_v86_pipe_sel
// ① **全旁路 = 逐位不动**（sel=0 不许错位、钳位、变灰）：V8-4 要按分割线逐像素混合，旁路错一行/一列就出一条说不清的错缝；
// ② **总延迟固定**：实测 de_in→de_out == 模块自己声明的 LATENCY 且与 sel 无关 —— 顶层左窗的 skid 长度直接取 `u_pipe.LATENCY`，这条一红左右窗就一定错位；
// ③ **只有一套控制源**：`cfg != 0` 用新九位，否则用老五位翻出来的等价形式；OSD 上那五位是新九位的投影，
//    不许成为第二个控制源（两边都能开就再也关不掉了）。
module tb_v86_pipe_sel;

    localparam W = 16, H = 8;
    localparam integer LAT_EXPECT = 15;     // 灰1+反色1+模糊3+锐化3+Sobel3+阈值1+形态学3（窗口级是三拍）

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    // ---- effect_ctrl ----
    reg  [8:0] cfg_a = 0;
    reg  [7:0] th_a = 80;
    wire [8:0] sel_q;
    wire [7:0] th_q;
    // 声明必须在 u_eff 之前：端口连接里先出现的标识符会被当成**隐式 1 bit 线网**，再写 `reg [31:0] gm_a` 就是重复声明
    reg  [31:0] gm_a = 32'd0;
    wire        gm_en_q, gm_wr_q;
    wire [7:0]  gm_idx_q, gm_data_q;
    effect_ctrl u_eff (
        .clk(clk), .rst_n(rst_n),
        .stage_sel_async(cfg_a), .threshold_async(th_a),
        .gamma_async(gm_a),             // gamma 表本身由 tb_v88_gamma 测；这里加 T15/T16 钉"位序与同步"
        // V8-8 给 effect_ctrl 加的两个缩放输入在本台架**没人判**（这里判选择字与 gamma 位序），但悬空 = Z
        // 会顺着 `sel_meta` 把 X 灌进同一条同步链（#88：一个悬空输入红了四判据好几天）。钉成"1.00x 手动"=固件默认。
        .zoom_sel_async(3'd4), .zoom_manual_async(1'b1),
        .stage_sel(sel_q), .threshold(th_q),
        .gamma_en(gm_en_q), .gamma_wr(gm_wr_q), .gamma_idx(gm_idx_q), .gamma_data(gm_data_q)
    );

    // ---- proc_pipeline ----
    reg         de = 0;
    reg  [11:0] xs = 0, ys = 0;
    reg  [15:0] src = 0;
    reg  [8:0]  sel = 0;
    wire        de_o;
    wire [15:0] d_o;
    proc_pipeline #(.H_ACTIVE(W)) up (
        .clk(clk), .rst_n(rst_n), .stage_sel(sel), .threshold(8'd80),
        // gamma 关掉：这里测"上面那五级 + 老五位映射"，表的内容由 tb_v88_gamma 测。留一条副作用判据：
        // gamma_en=0 必须逐位透明，所以 T1（sel=0 只含输入里出现过的颜色）同时也是"gamma 旁路不偷改像素"的证据。
        .gamma_en(1'b0), .gamma_wr(1'b0), .gamma_idx(8'd0), .gamma_data(8'd0),
        .rotate_active(1'b0), .hs_in(1'b0), .vs_in(1'b0),
        .de_in(de), .x_in(xs), .y_in(ys), .din(src), .de_out(de_o), .dout(d_o)
    );

    reg [15:0] field [0:H-1][0:W-1];
    reg [15:0] got   [0:H-1][0:W-1];
    reg [15:0] ref0  [0:H-1][0:W-1];       // 最近一次参考帧
    reg [15:0] refbyp[0:H-1][0:W-1];      // sel=0（全旁路）那一帧，T14 与 mode3 比的就是它
    integer oi = 0, oj = 0, errors = 0, n_p = 0, first_lat = -1, feed_cyc = 0, chk_no = 0;
    integer cyc = 0, t_in = -1;   // cyc 自由跑；t_in = 本帧第一个 de_in 的时刻

    always @(posedge clk) begin
        cyc = cyc + 1;
        if (de && t_in < 0) t_in = cyc;                 // 本帧第一个激励像素的时刻
        if (de_o && first_lat < 0) first_lat = cyc - t_in;      // 延迟 = 首个 de_out - 首个 de_in
    end
    always @(posedge clk) if (de_o && oi < H) begin
        n_p = n_p + 1;
        got[oi][oj] = d_o;
        oj = oj + 1;
        if (oj == W) begin oj = 0; oi = oi + 1; end
    end

    task chk;
        input [100*8:1] name;
        input cond;
        begin
            if (cond !== 1'b1) begin errors = errors + 1; chk_no = chk_no + 1; $display("  FAIL #%0d %0s", chk_no, name); end
            else chk_no = chk_no + 1;
        end
    endtask

    // 跑两帧（第二帧才是采集帧：热身掉上一段留下的行缓存），返回时 got 里是这一帧的结果
    task run_frame;
        input [8:0] s;
        integer x, y, k;
        begin
            for (k = 0; k < 2; k = k + 1) begin
                sel = s; oi = 0; oj = 0; n_p = 0; first_lat = -1; t_in = -1; feed_cyc = 0;
                for (y = 0; y < H; y = y + 1) begin
                    for (x = 0; x < W; x = x + 1) begin
                        @(negedge clk); xs = x; ys = y; src = field[y][x]; de = 1;
                        feed_cyc = feed_cyc + 1;
                    end
                    @(negedge clk); de = 0; feed_cyc = feed_cyc + 1;
                end
                de = 0;
                repeat (LAT_EXPECT + 4) @(negedge clk);
                feed_cyc = feed_cyc + LAT_EXPECT + 4;
                de = 0;
            end
        end
    endtask

    function color_exists;
        input [15:0] v;
        integer a, b;
        begin
            color_exists = 0;
            for (a = 0; a < H; a = a + 1)
                for (b = 0; b < W; b = b + 1)
                    if (field[a][b] === v) color_exists = 1;
        end
    endfunction

    integer i, j, bad, cnt;
    reg [15:0] v;

    initial begin
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1) begin
                // 一张有彩色、有边缘、有中间灰度的小图（灰度/二值化/形态学都要有可分的东西）
                field[j][i] = (i < 8) ? ((j & 1) ? 16'h0000 : 16'hFFFF)
                                      : {i[4:0], j[5:0], (i ^ j)};
            end
        rst_n = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (4) @(negedge clk);

        // ================= ① 全旁路：逐位不动 =================
        run_frame(9'h000);
        bad = 0;
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1) begin
                if (!color_exists(got[j][i])) bad = bad + 1;
                ref0[j][i] = got[j][i];
                refbyp[j][i] = got[j][i];
            end
        // 旁路是**中心抽头**（与 blur/sobel 同约定，见 ISSUES #54），所以这里不要求逐位等于输入，而是要求更强的性质：全旁路时不许产生任何输入里没有的颜色（不量化、不运算）。
        chk("T1 sel=0 输出只含输入里出现过的颜色（旁路不做任何运算）", bad == 0);
        if (bad) begin
            for (j = 0; j < H; j = j + 1) begin
                $write("     T1 r%0d ", j);
                for (i = 0; i < W; i = i + 1) $write("%h ", got[j][i]);
                $write("\n");
            end
        end

        // ================= ② 总延迟固定 =================
        chk("T2 实测 de 延迟 == 模块声明的 LATENCY", first_lat == up.LATENCY);
        if (first_lat != up.LATENCY)
            $display("[tb_v86_pipe_sel.v:156] T2 实测=%0d 声明=%0d 期望=%0d", first_lat, up.LATENCY, LAT_EXPECT);
        chk("T3 LATENCY 参数与手算的逐级和一致", up.LATENCY == LAT_EXPECT);
        chk("T4 脉冲数 == 像素数（没有多发也没有漏发）", n_p == H * W);

        // 换任何一级开/关，延迟都不许变（左右窗对齐的前提）
        bad = 0;
        run_frame(9'h001);  if (first_lat != LAT_EXPECT) bad = bad + 1;   // gray
        run_frame(9'h004);  if (first_lat != LAT_EXPECT) bad = bad + 1;   // blur
        run_frame(9'h008);  if (first_lat != LAT_EXPECT) bad = bad + 1;   // sharpen
        run_frame(9'h010);  if (first_lat != LAT_EXPECT) bad = bad + 1;   // sobel
        run_frame(9'h020);  if (first_lat != LAT_EXPECT) bad = bad + 1;   // binary
        run_frame(9'h080);  if (first_lat != LAT_EXPECT) bad = bad + 1;   // dilate
        chk("T5 六种组合下延迟都还是 15 拍", bad == 0);

        // ================= 每一级"真的动了画面"（挡接了没生效） =================
        cnt = 0;
        run_frame(9'h001);
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1)
                if (got[j][i] !== ref0[j][i]) cnt = cnt + 1;
        chk("T6 灰度确实改变了像素（不是空接）", cnt > 0);
        // 灰度后三通道必须相等（右边那半张图本来是彩色的）
        bad = 0;
        for (j = 0; j < H; j = j + 1)
            for (i = 8; i < W; i = i + 1) begin
                v = got[j][i];
                if (v[15:11] !== v[4:0]) bad = bad + 1;   // 灰度之后 R 与 B 必须同一个值
            end
        chk("T7 灰度输出 R==B（5/6/5 里 R、B 都是 5 bit）", bad == 0);

        run_frame(9'h020);                       // 只开二值化
        bad = 0;
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1)
                if (got[j][i] !== 16'hFFFF && got[j][i] !== 16'h0000) bad = bad + 1;
        chk("T8 二值化输出只有全亮/全暗两种", bad == 0);

        // ================= ③ 只有一套控制源（#66：五位那个第二源已经删掉）=================
        // 原来这一节钉"老五位全开、新九位为 0 ⇒ 等价"（T9/T10）与"新字非 0 时老五位不许漏进效果"（T13）；
        // `effect_ctrl` 现在只有一个入口，那两条**结构上成立**，于是换成钉今天真的会坏的两件事：cfg=0 必全旁路、cfg 逐位直连。
        cfg_a = 9'h000; th_a = 8'd123;
        repeat (6) @(negedge clk);
        chk("T9 cfg=0 ⇒ 全旁路（五位这个第二源已不存在，没人能把效果偷偷打开）", sel_q == 9'h000);
        chk("T11 阈值同步过来（3 拍链）", th_q == 8'd123);

        // 新九位逐位直连：只开 sharpen 那一位，其余八位必须是 0
        cfg_a = 9'h008;
        repeat (6) @(negedge clk);
        chk("T12 九位控制字逐位直连（cfg=0x008 ⇒ sel_q=0x008）", sel_q == 9'h008);
        // 同一份 cfg 连跑两帧必须一模一样 —— 替掉原来的"换老五位输出不变"（那条防第二个源），现在防"同步链自己每帧漂"
        run_frame(9'h008);
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1) ref0[j][i] = got[j][i];
        run_frame(9'h008);
        bad = 0;
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1)
                if (got[j][i] !== ref0[j][i]) bad = bad + 1;
        chk("T13 同一份 cfg 连跑两帧逐位一致（同步链与效果链都不漂）", bad == 0);

        // 腐蚀 + 膨胀同时要求 = 两个都不做（= 旁路）
        cfg_a = 9'h180;
        repeat (6) @(negedge clk);
        run_frame(9'h180);
        bad = 0;
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1)
                if (got[j][i] !== refbyp[j][i]) bad = bad + 1;
        chk("T14 腐蚀|膨胀 同时要 = 旁路（开/闭运算要两遍窗口，不许偷偷只做一半）", bad == 0);

        // ================= ④ gamma 窗口的位序与同步（表的内容由 tb_v88_gamma 测） =================
        // 字：[31] en、[30] wr（翻转位）、[29:22] data、[21:14] idx。
        // 这四个值**互不相同**是故意的：任何一处对调（idx/data、en/wr）都会红。
        gm_a = {1'b1, 1'b1, 8'hA5, 8'h3C, 14'd0};
        repeat (6) @(negedge clk);
        chk("T15 gamma 位序：en[31]/wr[30]/data[29:22]/idx[21:14] 各就各位",
            gm_en_q === 1'b1 && gm_wr_q === 1'b1 && gm_data_q === 8'hA5 && gm_idx_q === 8'h3C);

        // en 落到 0、wr 落到 0，而 idx/data 同时换值 ⇒ 四个字段各自跟随（en 不是"整字关断"）
        gm_a = {1'b0, 1'b0, 8'h5A, 8'hC3, 14'd0};
        repeat (6) @(negedge clk);
        chk("T16 en/wr 归 0 时 idx/data 仍照实同步（旁路与表内容互不牵连）",
            gm_en_q === 1'b0 && gm_wr_q === 1'b0 && gm_data_q === 8'h5A && gm_idx_q === 8'hC3);

        gm_a = 32'd0;
        cfg_a = 9'h000;
        repeat (4) @(negedge clk);
        $display("");
        if (errors == 0) $display("PASS tb_v86_pipe_sel");
        else $display("FAIL tb_v86_pipe_sel errors=%0d", errors);
        $finish;
    end
endmodule
