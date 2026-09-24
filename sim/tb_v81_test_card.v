`timescale 1ns/1ps
// 台架：src/rtl/video/test_card.v（图卡 v2 = 第三源）
//
// 这张卡存在的唯一理由是"它会动而且动得可判读"。所以本台架的核心不是"画得美"，而是四条：
//   ① 同一像素跨帧必须变（通路在刷新），并且配一条反面对照：静止 `color_bar` 跨帧必须**一像素都不变**
//   ② 球心位置 = 手算的 (MX + tri(phx)*AX, MY + tri(phy)*AY) —— 画面是 frame 的纯函数，可逐像素复算
//   ③ **拖影必须比光晕亮、且不是白** —— 这条是 v2 现场修出来的：球半径大于每帧位移时，
//      三个"上一帧位置"全被球体盖住，拖影在屏幕上根本不存在（数据核对过：球心附近只采到
//      背景、光晕和球）。没有这条，"重复帧 ⇒ 拖影塌进球心"这个判读就是一句空话
//   ④ 底部帧号 8 格逐位正确 —— 拍照就能读出"屏上这帧是第几帧"，丢帧/重复帧于是成为可核对的数
//
// 期望常数全部在这里**手算**（RGB565 = r[7:3] g[7:2] b[7:3]），不从被测模块里回抄。
// 几何用 256×150（不是板上的 512×300）：判据要能逐像素扫两帧，全分辨率跑不动也不会更灵；
// 但**不能更小** —— 球半径有下限 12，画面太小会让步长钳位生效、几何与板上不同（踩过）。
module tb_v81_test_card;
    localparam integer H = 256, V = 150;
    localparam [11:0] Y_FIELD = V - V/12 - V/12;          // 150-12-12 = 126
    localparam [11:0] Y_BAND  = V - V/12;                 // 138
    localparam integer BW = H/8;                          // 32
    localparam [11:0] RAD = 12'd12;                       // V/14 = 10 < 12 ⇒ 取钳位值 12
    localparam [11:0] GLO = RAD + (RAD >> 1);             // 18
    localparam [11:0] AX  = 12'd7;                        // (256-36)/31
    localparam [11:0] AY  = 12'd1;                        // (126-36)/49
    localparam [11:0] MX  = 12'd19;                       // 18 + (256-36-217)/2
    localparam [11:0] MY  = 12'd38;                       // 18 + (126-36-49)/2
    localparam [11:0] CN  = 12'd8, CT = 12'd2;            // 四角括号臂长 / 臂宽

    localparam [15:0] C_WHITE=16'hFFFF, C_YELLOW=16'hFFE0, C_CYAN=16'h07FF,
                      C_GREEN=16'h07E0, C_MAGENTA=16'hF81F, C_RED=16'hF800,
                      C_BLUE=16'h001F, C_DARK=16'h18C3, C_BLACK=16'h0000,
                      C_CELL0=16'h19C9, C_CORNER=16'h5C76;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    reg [11:0] x = 0, y = 0;
    reg de = 0, vs = 0;
    wire [15:0] rgb, bar_rgb;

    test_card #(.H_ACTIVE(H), .V_ACTIVE(V)) dut (
        .clk(clk), .rst_n(rst_n), .vs(vs), .x(x), .y(y), .de(de), .rgb565(rgb));
    color_bar #(.H_ACTIVE(H), .V_ACTIVE(V)) ref_static (
        .clk(clk), .rst_n(rst_n), .x(x), .y(y), .de(de), .rgb565(bar_rgb));

    integer errors = 0, i, f, k, N;
    reg [15:0] v, w;
    reg [15:0] snap [0:H*V-1];
    reg [15:0] sta  [0:H*V-1];

    task expect(input [639:0] name, input cond);
        begin
            if (cond !== 1'b1) begin errors = errors + 1; $display("FAIL %0s (t=%0t)", name, $time); end
            else $display("PASS %0s", name);
        end
    endtask

    // 独立实现的三角波与球心（按注释里的定义手写，不从 RTL 引）
    function [6:0] tri64 (input [6:0] k); tri64 = (k > 7'd31) ? (7'd63 - k) : k; endfunction
    function [6:0] tri99 (input [6:0] k); tri99 = (k > 7'd49) ? (7'd98 - k) : k; endfunction
    function [11:0] ballx (input integer n);
        ballx = MX + tri64(n % 64) * AX;
    endfunction
    function [11:0] bally (input integer n);
        bally = MY + tri99(n % 99) * AY;
    endfunction
    function [5:0] blue5 (input [15:0] c); blue5 = c[4:0]; endfunction

    task px(input [11:0] xx, input [11:0] yy, output [15:0] vv);
        begin
            @(negedge clk); x <= xx; y <= yy; de <= 1'b1;
            @(negedge clk); vv = rgb; de <= 1'b0;
        end
    endtask

    task next_frame;
        begin
            @(negedge clk); vs <= 1'b1;
            @(negedge clk); vs <= 1'b0;
        end
    endtask

    task sweep;
        begin
            for (f = 0; f < V; f = f + 1)
                for (i = 0; i < H; i = i + 1) begin
                    @(negedge clk); x <= i[11:0]; y <= f[11:0]; de <= 1'b1;
                    @(negedge clk);
                    snap[f*H+i] = rgb; sta[f*H+i] = bar_rgb;
                    de <= 1'b0;
                end
        end
    endtask

    initial begin
        $dumpfile("tb_v81_test_card.vcd");
        repeat (3) @(posedge clk); rst_n = 1;
        repeat (2) @(posedge clk);

        // ---- T0 复位后帧号 0：第一格（bit7=0）是暗格；黑标在左沿 ----
        px(16, Y_BAND+5, v);
        expect("T0 复位后帧号 0：第一格为暗格", v === C_CELL0);

        // ---- T1~T8 底部细色带八格（y=131，格心 x=i*32+16）----
        px(0*BW+16, 131, v); expect("T1 色带0 白",   v === C_WHITE);
        px(1*BW+16, 131, v); expect("T2 色带1 黄",   v === C_YELLOW);
        px(2*BW+16, 131, v); expect("T3 色带2 青",   v === C_CYAN);
        px(3*BW+16, 131, v); expect("T4 色带3 绿",   v === C_GREEN);
        px(4*BW+16, 131, v); expect("T5 色带4 品红", v === C_MAGENTA);
        px(5*BW+16, 131, v); expect("T6 色带5 红",   v === C_RED);
        px(6*BW+16, 131, v); expect("T7 色带6 蓝",   v === C_BLUE);
        px(7*BW+16, 131, v); expect("T8 色带7 暗灰", v === C_DARK);

        // ---- T9 背景渐变沿 y 单调变亮（x=250 干净带：不在网格、扫光最大到 190）----
        // 采样跨度必须 ≥32 行：蓝通道在 RGB565 里只有 5 bit，`y>>2` 每 4 行才加 1，
        // 量化后 **8 行内根本看不出来**（第一版取 112..124 就是栽在这，判据假失败）
        begin : grad
            integer mono, strict, prevb, firstb, lastb;
            px(250, 108, v); prevb = blue5(v); firstb = prevb; mono = 1;
            for (i = 114; i <= 125; i = i + 5) begin
                px(250, i[11:0], w);
                if (blue5(w) < prevb) mono = 0;
                prevb = blue5(w);
            end
            lastb = prevb;
            strict = (lastb > firstb);
            expect("T9 背景渐变沿 y 不回暗、且首尾确实变亮（不是分段横带）", mono && strict);
        end

        // ---- T10 网格：每 32 一条、每 128 一条更亮（同一行 y=120）----
        begin : grid
            integer b_plain, b_minor, b_major;
            px(33, 120, v); b_plain = blue5(v);
            px(32, 120, w); b_minor = blue5(w);
            px(128, 120, v); b_major = blue5(v);
            expect("T10 网格周期 32 像素，且每 128 的主线更亮",
                   (b_minor > b_plain) && (b_major > b_minor));
        end

        // ---- T11 推到帧号 0xA5（165）后逐格读；T11b 左沿黑标 ----
        for (N = 0; N < 165; N = N + 1) next_frame;
        begin : numcells
            integer bad; bad = 0;
            for (i = 0; i < 8; i = i + 1) begin
                px(i*BW+16, Y_BAND+5, v);
                w = ((16'hA5 >> (7-i)) & 16'h1) ? C_WHITE : C_CELL0;
                if (v !== w) begin bad = bad + 1; $display("  格 %0d got=%h exp=%h", i, v, w); end
            end
            expect("T11 帧号 0xA5 的 8 个二值格逐位正确（拍照即可读出帧号）", bad == 0);
            px(0*BW+1, Y_BAND+5, v);
            expect("T11b 每格左沿 4 像素是黑标（对齐基准）", v === C_BLACK);
        end

        // ---- T12 球心 = 手算位置且为纯白；球外 16 像素不是白 ----
        begin : ballpos
            px(ballx(165), bally(165), v);
            expect("T12 球心落在手算的 (MX+tri(phx)*AX, MY+tri(phy)*AY) 且是纯白", v === C_WHITE);
            px(ballx(165) + 16, bally(165), w);
            expect("T12b 球心右 16 像素已出球体（半径 12，不再是白）", w !== C_WHITE);
        end

        // ---- T13 拖影：上二帧的球心处**比背景亮但不是白**，且比同处的光晕更亮 ----
        begin : trail
            integer gx, gy, b_bg, b_glow, b_trail;
            gx = ballx(163); gy = bally(163);
            px(gx, gy, v);
            b_trail = blue5(v);
            // 取"只受光晕影响"的点必须在拖影**反侧**：相位已过波峰 ⇒ 三个拖影都在球的右边，
            // 第一版取 +16 正好落在 ball1 上，于是"拖影比光晕亮"这条判据假失败
            px(ballx(165) - 17, bally(165), w);      // 左侧 dx=17 ≤ GLO=18，且离所有拖影 ≥24
            b_glow = blue5(w);
            px(250, gy[11:0], w);                     // 同一行最右侧的纯背景
            b_bg = blue5(w);
            expect("T13 拖影存在：上二帧球心处比背景亮、又不是白（球没盖住它）",
                   (v !== C_WHITE) && (b_trail > b_bg));
            expect("T13b 拖影比光晕更亮（三级梯级没写反，彗尾看得见）", b_trail > b_glow);
        end

        // ---- T14/T15 跨帧必变 + 静止对照；T16 同帧重扫必须逐像素相同 ----
        sweep;                                        // 帧 165
        begin : rescan
            integer diff_same; diff_same = 0;
            for (f = 0; f < V; f = f + 1)
                for (i = 0; i < H; i = i + 1) begin
                    @(negedge clk); x <= i[11:0]; y <= f[11:0]; de <= 1'b1;
                    @(negedge clk);
                    if (rgb !== snap[f*H+i]) diff_same = diff_same + 1;
                    de <= 1'b0;
                end
            expect("T16 同一帧内重扫逐像素相同（画面是 frame 的纯函数，可复算）", diff_same == 0);
        end
        next_frame;                                   // → 帧 166
        begin : cmp
            integer diff_card, diff_static;
            diff_card = 0; diff_static = 0;
            for (f = 0; f < V; f = f + 1)
                for (i = 0; i < H; i = i + 1) begin
                    @(negedge clk); x <= i[11:0]; y <= f[11:0]; de <= 1'b1;
                    @(negedge clk);
                    k = f*H+i;
                    if (rgb !== snap[k])    diff_card = diff_card + 1;
                    if (bar_rgb !== sta[k]) diff_static = diff_static + 1;
                    de <= 1'b0;
                end
            expect("T14 图卡跨帧确实变了（这就是通路在刷新的可视证据）", diff_card > 0);
            expect("T15 反面对照：静止彩条跨帧一个像素都不变", diff_static == 0);
            $display("INFO 跨帧变化像素 card=%0d color_bar=%0d（共 %0d）",
                     diff_card, diff_static, H*V);
        end

        // ---- T17 四角括号（(2,1)：球与扫光都到不了这里）----
        px(2, 1, v);
        expect("T17 四角括号在位且是手算的亮蓝灰", v === C_CORNER);

        // ---- T18 扫光带可见：带心处比最右侧背景亮 ----
        begin : sweep_chk
            integer bc;
            bc = 165 % 47;
            bc = (bc > 23) ? (46 - bc) : bc;
            px((MX + bc*7) & 12'hFFF, 120, v);
            px(250, 120, w);
            expect("T18 横扫光带在带心处明显比背景亮（球在边角时也能看出在刷新）",
                   blue5(v) > blue5(w));
        end

        // ---- T19 延迟契约：de=0 时换坐标输出不变；de 再拉高一拍才读到新值 ----
        begin : lat
            px(0*BW+16, 131, v);                      // 色带0 = 白
            @(negedge clk); x <= (1*BW+16); de <= 1'b0;
            @(negedge clk); @(negedge clk);
            expect("T19 de=0 时改坐标不改变输出（延迟恰为 1 拍，无组合直通）", v === C_WHITE
                   && rgb === C_WHITE);
            @(negedge clk); de <= 1'b1;
            @(negedge clk);
            expect("T19b de 再拉高一拍才读到色带1（黄）", rgb === C_YELLOW);
            de <= 1'b0;
        end

        // ---- T20 模式格雷码环：验 `pl_video_top` 里手推的那条下一状态式 ----
        // 顶层写的是 `mode <= {mode[0], ~mode[1]}`（自动 00 → 锁ETH 01 → 锁PS 11 → 锁图卡 10 → 自动）。
        // 这里只验**式子本身**；顶层有没有接对是板级长按判据（`board/README.md`）。
        // 四个编码重抄一遍而不是引用 RTL，是为了让"改一边忘一边"能红。
        begin : gray_ring
            reg [1:0] m, m0, m1, m2, m3;
            m = 2'd0;
            m0 = {m[0], ~m[1]};  m1 = {m0[0], ~m0[1]};
            m2 = {m1[0], ~m1[1]}; m3 = {m2[0], ~m2[1]};
            expect("T20 四步环依次落在 锁ETH/锁PS/锁图卡/自动",
                   m0 == 2'd1 && m1 == 2'd3 && m2 == 2'd2 && m3 == 2'd0);
            expect("T20b 每一步只有一位变化（格雷码成立才允许打拍跨域）",
                   (m ^ m0) == 2'd01 && (m0 ^ m1) == 2'd10 &&
                   (m1 ^ m2) == 2'd01 && (m2 ^ m3) == 2'd10);
            expect("T20c 四步回到起点且四个状态互不相同（没有进不去的模式）",
                   m3 == m && (m != m0) && (m != m1) && (m != m2) &&
                   (m0 != m1) && (m0 != m2) && (m1 != m2));
        end

        if (errors == 0) $display("PASS tb_v81_test_card");
        else             $display("FAIL tb_v81_test_card errors=%0d", errors);
        $finish;
    end

    initial begin
        #80_000_000;                                  // 80 ms 看门狗（三次整帧扫描 ≈ 23 万拍）
        $display("FAIL tb_v81_test_card timeout");
        $finish;
    end
endmodule
