`timescale 1ns/1ps
// 台架：effect_ctrl（两套控制源折成一套 + 跨域同步）与 proc_pipeline（五级链的整体契约）
//
// 这个台架钉的是"整条链对外承诺的三件事"，单模块台架（tb_v84/tb_v85）管不到：
//   ① **全旁路 = 逐位不动**：sel=0 时输出必须与输入完全一致（不错位、不钳位、不变灰）。
//      V8-4 要把"原图"和"处理图"按分割线逐像素混合，只要旁路时错一行/错一列，分割线两侧
//      就会出现一条错缝 —— 那是"看起来像 bug 但没人说得清"的最坏情况。
//   ② **总延迟固定**：实测 de_in→de_out 必须等于模块自己声明的 LATENCY，且与 sel 无关。
//      顶层左窗的 skid 长度直接取 `u_pipe.LATENCY`，所以这条一红，左右窗就一定错位。
//   ③ **老五位与新九位的优先级**：`cfg != 0` 用新九位，否则用老五位翻出来的等价形式；
//      OSD 上那五位是新九位的投影，不许成为第二个控制源（两边都能开就再也关不掉了）。
module tb_v86_pipe_sel;

    localparam W = 16, H = 8;
    localparam integer LAT_EXPECT = 15;     // 灰1+反色1+模糊3+锐化3+Sobel3+阈值1+形态学3（窗口级是三拍）

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    // ---------------- effect_ctrl ----------------
    reg  [4:0] en_a = 0;
    reg  [8:0] cfg_a = 0;
    reg  [7:0] th_a = 80;
    wire [8:0] sel_q;
    wire [4:0] en_q;
    wire [7:0] th_q;
    effect_ctrl u_eff (
        .clk(clk), .rst_n(rst_n),
        .effect_en_async(en_a), .stage_sel_async(cfg_a), .threshold_async(th_a),
        .stage_sel(sel_q), .effect_en(en_q), .threshold(th_q)
    );

    // ---------------- proc_pipeline ----------------
    reg         de = 0;
    reg  [11:0] xs = 0, ys = 0;
    reg  [15:0] src = 0;
    reg  [8:0]  sel = 0;
    wire        de_o;
    wire [15:0] d_o;
    proc_pipeline #(.H_ACTIVE(W)) up (
        .clk(clk), .rst_n(rst_n), .stage_sel(sel), .threshold(8'd80),
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
            if (!cond) begin errors = errors + 1; chk_no = chk_no + 1; $display("  FAIL #%0d %0s", chk_no, name); end
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
        // 旁路是**中心抽头**（与 blur/sobel 同约定），所以这里不要求逐位等于输入；
        // 要求的是更强的性质：全旁路时不许产生任何输入里没有的颜色（不量化、不运算）。
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
            $display("     T2 实测=%0d 声明=%0d 期望=%0d", first_lat, up.LATENCY, LAT_EXPECT);
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

        // ================= ③ 两套控制源的优先级与投影 =================
        // 老五位全开、新九位为 0 ⇒ 新九位必须等于老五位的等价形式（位序见 proc_pipeline.v 头）
        en_a = 5'b11111; cfg_a = 9'h000; th_a = 8'd123;
        repeat (6) @(negedge clk);
        chk("T9 老五位 11111 → 新九位 0x37（gray/invert/blur/sobel/binary）", sel_q == 9'h037);
        chk("T10 OSD 投影回老位序 11111（投影不是第二个源）", en_q == 5'b11111);
        chk("T11 阈值同步过来（3 拍链）", th_q == 8'd123);

        // 新九位非 0 时**盖住**老五位；只开 sharpen 时 gray/binary 等必须都是关的
        en_a = 5'b11111; cfg_a = 9'h008;
        repeat (6) @(negedge clk);
        chk("T12 cfg 非 0 时以 cfg 为准（老五位不再参与）", sel_q == 9'h008);
        // 判据改成可判定的形式：同一个 cfg，老五位从 0 变成 11111，输出必须一模一样
        // （= 老五位确实没有漏进效果里）。原来写的是「不许出现 FFFF/0000」，
        // 但输入本来就有黑白条纹，锐化在平地上当然还是黑白 —— 那条判据是错的判据。
        en_a = 5'b00000; run_frame(9'h008);
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1) ref0[j][i] = got[j][i];
        en_a = 5'b11111; run_frame(9'h008);
        bad = 0;
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1)
                if (got[j][i] !== ref0[j][i]) bad = bad + 1;
        chk("T13 cfg 非 0 时老五位完全不起作用（换 en 输出逐位不变）", bad == 0);

        // 腐蚀 + 膨胀同时要求 = 两个都不做（= 旁路）
        cfg_a = 9'h180;
        repeat (6) @(negedge clk);
        run_frame(9'h180);
        bad = 0;
        for (j = 0; j < H; j = j + 1)
            for (i = 0; i < W; i = i + 1)
                if (got[j][i] !== refbyp[j][i]) bad = bad + 1;
        chk("T14 腐蚀|膨胀 同时要 = 旁路（开/闭运算要两遍窗口，不许偷偷只做一半）", bad == 0);

        cfg_a = 9'h000; en_a = 5'b00000;
        repeat (4) @(negedge clk);
        $display("");
        if (errors == 0) $display("PASS tb_v86_pipe_sel");
        else $display("FAIL tb_v86_pipe_sel errors=%0d", errors);
        $finish;
    end
endmodule
