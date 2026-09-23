`timescale 1ns/1ps
// 台架：src/rtl/video/test_card.v（会动的测试图卡 = 第三源占位）
//
// 这张卡存在的唯一理由是"它会动"——静止彩条分不清"通路在刷新"和"卡在最后一帧"。
// 所以本台架的核心判据不是"画对了"，而是**同一像素跨帧会变**，并且配了一条反面对照：
// 把 `color_bar` 一起例化进来，同样两帧之间它必须**一个像素都不变**。
// 没有这条对照，"输出变了"可能只是激励没对齐或仿真器抖动。
//
// 期望常数全部在这里**手算**（RGB565 = r[7:3] g[7:2] b[7:3]），不从被测模块里回抄 ——
// 这是本仓库对"检查器自己也要有独立来源"的一贯要求。
//
// 几何用 64×48（不是板上的 512×300）：判据要能逐像素扫，全分辨率一帧 15 万拍、要扫两帧，
// 跑不动也不会更容易发现问题。分区是按 H/V 取比例的，小几何测的就是同一套逻辑。
module tb_v81_test_card;
    localparam integer H = 64, V = 48;
    localparam [11:0] Y_BAR  = (V*4)/5;                 // 38
    localparam [11:0] Y_GRAY = Y_BAR + V/16;            // 41
    localparam [11:0] Y_COMB = Y_GRAY + V/32;           // 42
    localparam [11:0] Y_NUM  = Y_COMB + V/25;           // 43
    localparam integer BW = H/8;                        // 8
    localparam [11:0] YB0 = V/6, YB1 = YB0 + V/10;      // 块所在行 8..11
    localparam integer BLKW = (H/16 > 4) ? H/16 : 4;    // 4

    localparam [15:0] C_WHITE=16'hFFFF, C_YELLOW=16'hFFE0, C_CYAN=16'h07FF,
                      C_GREEN=16'h07E0, C_MAGENTA=16'hF81F, C_RED=16'hF800,
                      C_BLUE=16'h001F, C_DARK=16'h1082, C_BLACK=16'h0000,
                      C_CELL0=16'h2104;                 // 帧号格"0"的暗蓝灰 (0x20,0x20,0x20)

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg [11:0] x = 0, y = 0;
    reg de = 0, vs = 0;
    wire [15:0] rgb, bar_rgb;

    test_card #(.H_ACTIVE(H), .V_ACTIVE(V)) dut (
        .clk(clk), .rst_n(rst_n), .vs(vs), .x(x), .y(y), .de(de), .rgb565(rgb));
    color_bar #(.H_ACTIVE(H), .V_ACTIVE(V)) ref_static (      // 反面对照：静止图案
        .clk(clk), .rst_n(rst_n), .x(x), .y(y), .de(de), .rgb565(bar_rgb));

    integer errors = 0, i, f, k;
    reg [15:0] v, w;
    reg [15:0] snap [0:H*V-1];
    reg [15:0] sta  [0:H*V-1];

    task expect(input [639:0] name, input cond);
        begin
            if (!cond) begin errors = errors + 1; $display("FAIL %0s (t=%0t)", name, $time); end
            else $display("PASS %0s", name);
        end
    endtask

    // 采一个像素：de 拉高一拍 ⇒ 输出在**下一拍**有效（这就是与 color_bar 一致的 1 拍契约）
    task px; input [11:0] xx, yy; output [15:0] vv;
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

    // 整帧扫一遍，两张卡各存一份
    task sweep;
        begin
            for (f = 0; f < V; f = f + 1) begin
                for (i = 0; i < H; i = i + 1) begin
                    @(negedge clk); x <= i[11:0]; y <= f[11:0]; de <= 1'b1;
                    @(negedge clk);
                    snap[f*H+i] = rgb; sta[f*H+i] = bar_rgb;
                    de <= 1'b0;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("tb_v81_test_card.vcd");
        repeat (3) @(posedge clk); rst_n = 1;
        repeat (2) @(posedge clk);

        // ---- T0 复位后帧号 = 0：第一格（bit7=0）应是暗格；格心取样（左沿 4 像素是黑标）----
        px(4, Y_NUM+2, v);
        expect("T0 复位后帧号 0：第一格为暗", v === C_CELL0);

        // ---- T1~T8 彩条八色（第 20 行，避开块与灰阶）----
        px(0,      20, v); expect("T1 条0 白",   v === C_WHITE);
        px(BW,     20, v); expect("T2 条1 黄",   v === C_YELLOW);
        px(2*BW,   20, v); expect("T3 条2 青",   v === C_CYAN);
        px(3*BW,   20, v); expect("T4 条3 绿",   v === C_GREEN);
        px(4*BW,   20, v); expect("T5 条4 品红", v === C_MAGENTA);
        px(5*BW,   20, v); expect("T6 条5 红",   v === C_RED);
        px(6*BW,   20, v); expect("T7 条6 蓝",   v === C_BLUE);
        px(7*BW,   20, v); expect("T8 条7 暗灰", v === C_DARK);

        // ---- T9 灰阶行 8 档单调递增（通道线性参照接没接对）----
        begin : gray_row
            reg [4:0] prev;  integer mono, first;
            prev = 5'd0; mono = 1; first = 1;
            for (i = 0; i < 8; i = i + 1) begin
                px(i*BW+4, Y_BAR+1, v);
                if (!first && v[15:11] <= prev) mono = 0;
                prev = v[15:11]; first = 0;
            end
            expect("T9 灰阶 8 档单调递增", mono);
        end

        // ---- T10 梳齿行：相邻像素一白一黑（2 像素周期）----
        px(0, Y_GRAY, v); px(1, Y_GRAY, w);
        expect("T10 梳齿 2 像素周期（偶=白，奇=黑）", v === C_WHITE && w === C_BLACK);

        // ---- T11 帧号行：推到 0xA5（165）后逐格读 ----
        for (f = 0; f < 165; f = f + 1) next_frame;
        begin : numcells
            integer bad; bad = 0;
            for (i = 0; i < 8; i = i + 1) begin
                px(i*BW+4, Y_NUM+2, v);
                w = ((16'hA5 >> (7-i)) & 16'h1) ? C_WHITE : C_CELL0;
                if (v !== w) begin bad = bad + 1; $display("  格 %0d got=%h exp=%h", i, v, w); end
            end
            expect("T11 帧号 0xA5 的 8 个二值格逐位正确（拍照即可读出帧号）", bad == 0);
            px(0, Y_NUM+2, v);
            expect("T11b 每格左沿 4 像素是黑标（对齐基准）", v === C_BLACK);
        end

        // ---- T12 移动块位置 = (frame mod 8)*8 ----
        begin : blkpos
            integer ok; ok = 1;
            px((165 % 8)*8 + 1, YB0+1, v);        if (v !== C_YELLOW) ok = 0;
            px((165 % 8)*8 + BLKW + 1, YB0+1, w); if (w === C_YELLOW) ok = 0;
            expect("T12 黄块落在 (frame mod 8)*8，块外不是黄色", ok);
        end

        // ---- T13/T14 核心：跨帧图卡必须变、静止彩条必须完全不变 ----
        sweep;                                    // 帧 165
        next_frame;                               // → 帧 166
        begin : cmp
            integer diff_card, diff_static;
            diff_card = 0; diff_static = 0;
            for (f = 0; f < V; f = f + 1) begin
                for (i = 0; i < H; i = i + 1) begin
                    @(negedge clk); x <= i[11:0]; y <= f[11:0]; de <= 1'b1;
                    @(negedge clk);
                    k = f*H+i;
                    if (rgb !== snap[k])     diff_card = diff_card + 1;
                    if (bar_rgb !== sta[k])  diff_static = diff_static + 1;
                    de <= 1'b0;
                end
            end
            expect("T13 图卡跨帧确实变了（这就是通路在刷新的可视证据）", diff_card > 0);
            expect("T14 反面对照：静止彩条跨帧一个像素都不变", diff_static == 0);
            $display("INFO 跨帧变化像素数 card=%0d color_bar=%0d（共 %0d）",
                     diff_card, diff_static, H*V);
        end

        // ---- T15 延迟契约：de=0 时换了坐标输出也必须**不**变（排除组合直通）----
        begin : lat
            px(0, 20, v);                         // v = 条0 白
            @(negedge clk); x <= BW[11:0]; de <= 1'b0;
            @(negedge clk); @(negedge clk);
            expect("T15 de=0 时改坐标不改变输出（延迟恰为 1 拍，无直通）", rgb === C_WHITE);
            @(negedge clk); de <= 1'b1;
            @(negedge clk);
            expect("T15b de 再拉高一拍才读到条1（黄）", rgb === C_YELLOW);
            de <= 1'b0;
        end

        if (errors == 0) $display("PASS tb_v81_test_card");
        else             $display("FAIL tb_v81_test_card errors=%0d", errors);
        $finish;
    end

    initial begin
        #3_000_000;                               // 3 ms 看门狗（两帧扫描 ≈ 6 千拍）
        $display("FAIL tb_v81_test_card timeout");
        $finish;
    end
endmodule
