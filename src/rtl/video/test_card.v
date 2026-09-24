`timescale 1ns/1ps
// test_card —— 第三源的"会动的画面"（v2）。
//
// 为什么换掉 v1：v1 有 80 % 面积是八色彩条，屏幕上就是一张检测卡。判读点是对的，
// 但拿来做演示画面不好看也不直观（用户 2026-09-24 原话："彩条图是在动的，但是感觉有点丑"）。
//
// v2 保留 v1 全部判读能力，只换表现。四样判读点，每样都对应一个真实问题：
//   ① 游动的亮球 + 三段拖影   —— "在不在动"一眼可见；**拖影塌进球心 = 重复帧**（相位寄存器
//      只在场边界搬，所以重复帧时球与拖影重合，这个现象本身就是判据）
//   ② 每 32 像素一条的细网格   —— 缩放/旋转/以后双线性插值的几何参照（每 128 一条主线可数格）
//   ③ 一条横扫的亮带           —— 球跑到边角时也能一眼看出"通路在刷新"，不是卡在最后一帧
//   ④ 底部细色带 + 帧号二值格  —— 通道有没有串色；不依赖字库，拍照就能读出"屏上这帧是第几帧"
//
// 三条不能为了好看牺牲的约束：
// · 时序契约与 `color_bar` **逐位一致**：输入 (x,y,de)，输出在 `de` 有效时打一拍。
//   顶层 PROC_LAT 与延迟抽头（bar_l_d4 / bar_r_d2）按 1 拍配好，改成 2 拍会整体错一行，
//   而那种错在屏幕上只是"偏了一点"，最难查。
// · 不出现除法和非常数乘法：路径用三角波，圆角方用"切比雪夫 + 曼哈顿"混合判据。
//   `相位 × 常数` 里的常数是 parameter，综合期折成移位/相加。像素域挂一条真乘法链会把
//   WNS 拖下水 —— 全设计最紧的路本来就是 OSD 算术（report/PERF_REPORT.md §4）。
// · 位置是 frame 的**纯函数** ⇒ 台架能逐像素复算，不用存历史。
//
// 写法注意：ANSI 端口表的模块里函数也必须用新式端口表（`function ... (input ...)`），
// 且 `wire` 不能声明在 always 块内 —— 这两条 vlog 会直接报语法错（v2 第一版踩过）。
module test_card #(
    parameter H_ACTIVE = 512,
    parameter V_ACTIVE = 300
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vs,          // 场同步：每个上升沿算一帧
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        de,
    output reg  [15:0] rgb565
);
    // ---------------------------------------------------------------- 帧号
    reg [15:0] frame;
    reg        vs_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin frame <= 16'd0; vs_d <= 1'b0; end
        else begin
            vs_d <= vs;
            if (vs && !vs_d) frame <= frame + 16'd1;
        end
    end

    // ---------------------------------------------------------------- 分区（按 V_ACTIVE 等比，改分辨率不用改代码）
    localparam [11:0] Y_FIELD = V_ACTIVE - (V_ACTIVE / 12) - (V_ACTIVE / 12);   // 主画面
    localparam [11:0] Y_BAND  = V_ACTIVE - (V_ACTIVE / 12);                      // 细色带下沿
    localparam [11:0] BW      = H_ACTIVE / 8;                                    // 格宽 64 @512
    // 球半径必须**小于每帧位移的量级**：V/10 配 11 px/帧时，三个"上一帧位置"全被球体自己盖住，
    // 渲染出来拖影完全看不见 —— 于是"重复帧 ⇒ 拖影塌进球心"这条判读也就没了（数据核对过：
    // 球心附近只有背景、光晕和球，一个拖影像素都采不到）。
    localparam [11:0] RAD     = (V_ACTIVE / 14 > 12) ? V_ACTIVE / 14 : 12'd12;
    localparam [11:0] GLO     = RAD + (RAD >> 1);                                // 光晕外沿
    // 步长与居中偏移。三条约束一起算，缺一不可：
    //   · 球要**完整**留在主画面里（第一版 AX 用 (H-2*GLO+30)/31 会把球推过右边界，半个球被切掉）
    //   · 底部要留一条**干净带**：台架要在"没有球、没有光晕、没有扫光"的位置量背景渐变，
    //     否则它测到的是球而不是背景，判据就成了碰运气
    //   · 小几何（台架用 256×150）下这些减法会变负 —— 12 bit 无符号会回绕成巨大步长，
    //     所以钳位一律写成"先比较再取"的形式，`> 0` 那种写法挡不住回绕
    localparam [11:0] AX = (H_ACTIVE > 2*GLO + 32) ? (H_ACTIVE - 2*GLO) / 31 : 12'd1;
    localparam [11:0] AY = (Y_FIELD  > 2*GLO + 49) ? (Y_FIELD  - 2*GLO) / 49 : 12'd1;
    localparam [11:0] MX = GLO + ((H_ACTIVE - 2*GLO - 31*AX) / 2);
    localparam [11:0] MY = GLO + ((Y_FIELD  - 2*GLO - 49*AY) / 2);

    // 横向 8 等分：格号 ci 与格内偏移都用常数阈值，不做除法
    wire [11:0] t1 = BW, t2 = 2*BW, t3 = 3*BW, t4 = 4*BW,
                t5 = 5*BW, t6 = 6*BW, t7 = 7*BW;
    wire [2:0] ci = (x < t1) ? 3'd0 : (x < t2) ? 3'd1 : (x < t3) ? 3'd2 : (x < t4) ? 3'd3 :
                    (x < t5) ? 3'd4 : (x < t6) ? 3'd5 : (x < t7) ? 3'd6 : 3'd7;
    reg  [11:0] cstart;
    always @(*) case (ci)
        3'd0: cstart = 12'd0;    3'd1: cstart = t1;   3'd2: cstart = t2;   3'd3: cstart = t3;
        3'd4: cstart = t4;       3'd5: cstart = t5;   3'd6: cstart = t6;   default: cstart = t7;
    endcase
    wire [11:0] xin = x - cstart;

    // ---------------------------------------------------------------- 相位与波形
    // 三个计数器周期互质（64 / 99 / 47）⇒ 合成轨迹要几千帧才重复一次，肉眼看不出循环。
    // 为什么不用 `frame` 的位段直接当相位：位段每 2/8 帧才变一次，纵向就"跳格"，
    // 观感是抖而不是动（v2 第一版写成 frame[7:3]，渲染出来才发现）。
    reg [6:0] phx, phy, phs;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin phx <= 7'd0; phy <= 7'd0; phs <= 7'd0; end
        else if (vs && !vs_d) begin
            phx <= (phx == 7'd63) ? 7'd0 : phx + 7'd1;
            phy <= (phy == 7'd98) ? 7'd0 : phy + 7'd1;
            phs <= (phs == 7'd46) ? 7'd0 : phs + 7'd1;
        end
    end

    function [5:0] tri64 (input [6:0] k);          // 0..63 → 0..31..0
        tri64 = (k > 7'd31) ? (7'd63 - k) : {1'b0, k[5:0]};
    endfunction
    function [5:0] tri99 (input [6:0] k);          // 0..98 → 0..49..0
        tri99 = (k > 7'd49) ? (7'd98 - k) : k;
    endfunction
    function [5:0] tri47 (input [6:0] k);          // 0..46 → 0..23..0（横扫光带用）
        tri47 = (k > 7'd23) ? (7'd46 - k) : k;
    endfunction
    function [11:0] adiff (input [11:0] a, input [11:0] b);
        adiff = (a >= b) ? (a - b) : (b - a);
    endfunction
    // 圆角方（方框裁四角）：只用加法、移位与比较
    function disc (input [11:0] px, input [11:0] py,
                   input [11:0] ccx, input [11:0] ccy, input [11:0] rr);
        reg [11:0] dx, dy;
        begin
            dx = adiff(px, ccx); dy = adiff(py, ccy);
            disc = (dx <= rr) && (dy <= rr) && ((dx + dy) <= (rr + (rr >> 1)));
        end
    endfunction

    // 球心：居中偏移 + 相位 × 常数步长（MX/MY/AX/AY 在上面与"干净带"一起算好了）
    wire [11:0] cx0 = MX + tri64(phx) * AX, cy0 = MY + tri99(phy) * AY;

    // 拖影 = 前三帧的球心，用寄存器搬（回退相位会在周期边界给出"未来"的位置）。
    // 存下来的才是真历史 ⇒ 重复帧时拖影会塌进球心，这本身就是一条能看的判据。
    reg [11:0] cx1, cy1, cx2, cy2, cx3, cy3;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cx1 <= 12'd0; cy1 <= 12'd0; cx2 <= 12'd0; cy2 <= 12'd0; cx3 <= 12'd0; cy3 <= 12'd0;
        end else if (vs && !vs_d) begin
            cx1 <= cx0; cy1 <= cy0;
            cx2 <= cx1; cy2 <= cy1;
            cx3 <= cx2; cy3 <= cy2;
        end
    end

    wire ball0 = disc(x, y, cx0, cy0, RAD);
    wire glow1 = disc(x, y, cx0, cy0, RAD + (RAD >> 2));      // 内圈：离球越远越暗，做成两级
    wire glow0 = disc(x, y, cx0, cy0, GLO);                   // 外圈：只比背景亮一点
    wire ball1 = disc(x, y, cx1, cy1, RAD - (RAD >> 3));
    wire ball2 = disc(x, y, cx2, cy2, RAD - (RAD >> 2));
    wire ball3 = disc(x, y, cx3, cy3, RAD - (RAD >> 1));

    // 四角括号：让画面读起来是"一个被测量的窗口"，同时给旋转/缩放一个几何基准
    localparam [11:0] CN = H_ACTIVE / 32, CT = V_ACTIVE / 75;         // 臂长 16 / 臂宽 4 @512×300
    wire corner = (y < Y_FIELD) &&
        ( ((x < CN) || (x >= H_ACTIVE - CN)) &&
          ((y < CT) || (y >= Y_FIELD - CT)) );

    // ③ 横扫光带：三级台阶（中心亮、两侧半亮），不是硬边条 —— 硬边看起来像坏线而不是光
    localparam [11:0] SW = (H_ACTIVE / 24 > 6) ? H_ACTIVE / 24 : 12'd6;
    wire [11:0] band_c = MX + tri47(phs) * AX;
    wire [11:0] band_d = adiff(x, band_c);
    wire sweep_core = (band_d <= (SW >> 2));
    wire sweep_soft = (band_d <= SW) && !sweep_core;

    // ---------------------------------------------------------------- ② 网格
    wire grid       = (x[4:0] == 5'd0) || (y[4:0] == 5'd0);
    wire grid_major = (x[6:0] == 7'd0) || (y[6:0] == 7'd0);

    // ---------------------------------------------------------------- ④ 帧号格用的中间量
    wire bitv = frame[7 - ci];
    wire lead = xin < 12'd4;

    // ---------------------------------------------------------------- 上色
    reg [7:0] r, g, b;
    always @(*) begin
        if (y < Y_FIELD) begin
            // 深蓝渐变底（随 y 变亮，兼作"绿色通道线性"参照），不再是几乎全黑
            // 深蓝渐变底。用 y>>2 / y>>3 这种**单调**位移，不用 y[7:6] 那种分段位：
            // 后者每 64 行回绕一次，渲染出来是一层一层横带（不是渐变），而且台架里
            // "沿 y 变亮"这条判据会在回绕处假失败。
            // 蓝通道跨度拉到 0x20..0xB6（原来 0x40..0x5F 只有 4 个量化级：
            // 人眼看不出渐变，台架也量不出单调 —— 好看与可测在这里是同一件事）
            r = 8'h08 + {5'b0, y[9:5]} + {6'b0, x[9:7]};
            g = 8'h14 + {3'b0, y[9:4]};
            b = 8'h20 + {1'b0, y[9:1]};
            if (grid) begin
                r = r + 8'h06; g = g + 8'h0A; b = b + 8'h10;
                if (grid_major) begin r = r + 8'h0A; g = g + 8'h14; b = b + 8'h20; end
            end
            if (sweep_soft)  begin r = r + 8'h0C; g = g + 8'h12; b = b + 8'h18; end
            if (sweep_core)  begin r = r + 8'h18; g = g + 8'h24; b = b + 8'h30; end
            if (corner)      begin r = 8'h5A; g = 8'h8E; b = 8'hB4; end
            // 光晕与拖影一律**在背景上加亮**，不给绝对色：
            // 上一版给的是绝对色，蓝通道 0x5C 比背景的 0x60 还暗 ⇒ 光晕看着是一圈深色方框，
            // 球像被套了个盒子（渲染出来才发现，改一轮构建就白费 40 分钟）
            // 光晕/拖影/球心一律给**绝对色**，不做叠加：上一版五层相加（bg+光晕两级+拖影三级）
            // 会把 8 bit 加溢出回绕 —— 台架 T13 实测到"拖影比背景还暗"，屏幕上就是黑洞。
            // 绝对阶梯同时保证每一级都比球活动区内背景的最坏值（r≤0x14 g≤0x2F b≤0x5A）更亮。
            if (glow0) begin r = 8'h1C; g = 8'h40; b = 8'h6C; end
            if (glow1) begin r = 8'h2A; g = 8'h58; b = 8'h88; end
            if (ball3) begin r = 8'h46; g = 8'h80; b = 8'hB0; end
            if (ball2) begin r = 8'h6E; g = 8'hAA; b = 8'hD2; end
            if (ball1) begin r = 8'hA8; g = 8'hD8; b = 8'hEE; end
            if (ball0) begin r = 8'hFF; g = 8'hFF; b = 8'hFF; end   // 球心纯白，最亮的一个点
        end else if (y < Y_BAND) begin
            // ③ 细色带：八色各占一格（v1 的整片彩条在这里只留一条）
            case (ci)
                3'd0:    begin r=8'hFF; g=8'hFF; b=8'hFF; end
                3'd1:    begin r=8'hFF; g=8'hFF; b=8'h00; end
                3'd2:    begin r=8'h00; g=8'hFF; b=8'hFF; end
                3'd3:    begin r=8'h00; g=8'hFF; b=8'h00; end
                3'd4:    begin r=8'hFF; g=8'h00; b=8'hFF; end
                3'd5:    begin r=8'hFF; g=8'h00; b=8'h00; end
                3'd6:    begin r=8'h00; g=8'h00; b=8'hFF; end
                default: begin r=8'h18; g=8'h18; b=8'h18; end
            endcase
        end else begin
            // 帧号低 8 位：左起第 0 格 = bit7，每格左沿 4 像素黑标当对齐基准；
            // "0" 格给暗青而不是纯黑，让这一排读起来是一个设计元素而不是一条黑缝
            r = lead ? 8'h00 : (bitv ? 8'hFF : 8'h1E);
            g = lead ? 8'h00 : (bitv ? 8'hFF : 8'h3A);
            b = lead ? 8'h00 : (bitv ? 8'hFF : 8'h48);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)   rgb565 <= 16'h0000;
        else if (de)  rgb565 <= {r[7:3], g[7:2], b[7:3]};
    end
endmodule
