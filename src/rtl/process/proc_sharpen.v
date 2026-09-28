`timescale 1ns/1ps
// 级 2 的第二个算法：3×3 锐化，卷积核 [0,-1,0 ; -1,5,-1 ; 0,-1,0]（四邻是上/下/左/右）。与 proc_box_blur
// 是**同一级的两个选项**、不是串联：先模糊再锐化几乎等于什么都没做，所以控制字里这两个占同一个字段。
// 三个通道分开算，**先比较再相减**：Verilog 的无符号减法会回绕，直接 `a-b` 然后判负是错的（表现是"暗边变成
// 一圈亮边"）。5×中心 与 四邻之和 都是无符号，比完大小再夹到 [0, 满量程]。延迟与 blur 一致（固定 2 拍，与
// bypass 无关）；整条链的延迟只有 `proc_pipeline.LATENCY` 一个出处。
module proc_sharpen #(
    parameter H_ACTIVE = 512
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bypass,
    input  wire        de_in,
    input  wire [11:0] x_in,
    input  wire [11:0] y_in,
    input  wire [15:0] din,
    output reg         de_out,
    output reg  [15:0] dout
);
    (* ram_style = "distributed" *) reg [15:0] lb0 [0:H_ACTIVE-1];
    (* ram_style = "distributed" *) reg [15:0] lb1 [0:H_ACTIVE-1];

    reg [15:0] q00, q01, q02, q10, q11, q12, q20, q21, q22;   // 窗口原始抽头（下面按边界复制成 p**）
    reg        de_d1, de_d2;

    always @(posedge clk) begin
        if (de_in) begin
            lb0[x_in] <= lb1[x_in];
            lb1[x_in] <= din;
        end
    end
    // #92 第四笔（与 proc_box_blur.v 同名注释一条）：行尾多跳一拍，末列的中心才进得了输出。
    // 只在"刚吃掉本行末列"那一跳多走 —— 拿 `de_d1 && !de_in` 当行尾会在**每个 de 断点**多跳一次
    // （`tb_rotate_window` 一拍一像素地推 ⇒ 模糊整个坏掉，2026-09-26 红给我看过）。
    reg [11:0] run;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)      run <= 12'd0;
        else if (de_in)  run <= run + 12'd1;
        else            run <= 12'd0;   // de 一断就清：那一拍非阻塞更新的旧值仍看得见，就是本行的宽度（详见 proc_box_blur.v 那五段）
    wire owed     = (run == H_ACTIVE[11:0]);
    wire line_end = owed && de_d1 && !de_in;
    wire shift_w  = de_in || line_end;
    wire [11:0] x_rd = (x_in >= H_ACTIVE[11:0]) ? (H_ACTIVE[11:0] - 12'd1) : x_in;
    wire [15:0] up2 = lb0[x_rd];           // 上上行
    wire [15:0] up1 = lb1[x_rd];           // 上一行

    // ---------------------------------------------------------------- #97：四条圈的旗标（推导与凭据在 proc_box_blur.v 的 #97 段）
    // `tb_edge_rim` 量出来的三条事实，四个窗口级共用同一套旗标（"逐字同形"是 S4/tb_v92 能差分验证的前提）：
    // ① 拍 k 武装的旗标落在槽位 k+1；② 行尾补跳那一拍落在**下一行第 0 槽**（旧代码在这里塞 1 ⇒ 第 0 列被旁路
    // 成原图 = 用户念的"左边一条带"）；③ 中心行 = 输入行 − 1 ⇒ 每帧第一个输出槽吃的是上一帧的末行（"上边缘那条带"）。
    reg [11:0] y_row_d;                    // this display line's y_in, latched at line end
    always @(posedge clk or negedge rst_n)
        if (!rst_n) y_row_d <= 12'h0FFF;
        else if (line_end) y_row_d <= y_in;
    wire row_first = (y_in != y_row_d);    // x2 raster: only the FIRST display row of a
                                           // source row can be missing the row above
    reg [2:0] no_left_r, no_right_r, no_above_r, stale_row_r;
    // ⚠ 复位只写在这**一个**块里（两个驱动源 = Synth 8-6859，bit 里恒 0 而仿真看不出来，#61）。
    always @(posedge clk or negedge rst_n)
    if (!rst_n) begin
        no_left_r <= 3'b0; no_right_r <= 3'b0; no_above_r <= 3'b0; stale_row_r <= 3'b0;
    end else if (shift_w) begin
        no_left_r  [0] <= ~de_in;                                     // 补跳那一拍 = 下一行第 0 槽
        no_right_r [0] <= de_in && (x_in == H_ACTIVE[11:0] - 12'd1);   // #103：坐标抽头对齐到 de 之后，武装位从 -2 改回 -1；拍 k 武装仍落槽位 k+1（正本见 proc_box_blur.v 的 #97 段）
        no_above_r [0] <= de_in && (y_in == 12'd1) && row_first;                    // 中心行 0，上面缺
        stale_row_r[0] <= de_in && (y_in == 12'd0);                    // 中心行 −1：整行都是旧的
        no_left_r  [1] <= no_left_r  [0];  no_left_r  [2] <= no_left_r  [1];
        no_right_r [1] <= no_right_r [0];  no_right_r [2] <= no_right_r [1];
        no_above_r [1] <= no_above_r [0];  no_above_r [2] <= no_above_r [1];
        stale_row_r[1] <= stale_row_r[0];  stale_row_r[2] <= stale_row_r[1];
    end
    wire no_left = no_left_r[2], no_right = no_right_r[2];
    wire no_above = no_above_r[2], stale_row = stale_row_r[2];
    // 缺的邻居复制中心 ⇒ 最外圈不再"直出原图"，那条断层就是用户报的带。
    // 抽头约定不变：`p00..p22` 仍是**移位之前**以 p11 为中心的 3×3，只是边缘那几格被复制过。
    wire [15:0] h00 = no_left ? q01 : q00;   wire [15:0] h02 = no_right ? q01 : q02;
    wire [15:0] h10 = no_left ? q11 : q10;   wire [15:0] h12 = no_right ? q11 : q12;
    wire [15:0] h20 = no_left ? q21 : q20;   wire [15:0] h22 = no_right ? q21 : q22;
    wire [15:0] h01 = q01, h11 = q11, h21 = q21;
    wire [15:0] p00 = stale_row ? h20 : (no_above ? h10 : h00);
    wire [15:0] p01 = stale_row ? h21 : (no_above ? h11 : h01);
    wire [15:0] p02 = stale_row ? h22 : (no_above ? h12 : h02);
    wire [15:0] p10 = stale_row ? h20 : h10;
    wire [15:0] p11 = stale_row ? h21 : h11;
    wire [15:0] p12 = stale_row ? h22 : h12;
    wire [15:0] p20 = h20, p21 = h21, p22 = h22;

    // R/B 5 bit，G 6 bit；中心 ×4 + 中心 = ×5，四邻直接相加（≤ 4×满量程）
    // 抽头约定与 proc_box_blur 一模一样：**移位之前**的 p00..p22 就是以 p11 为中心的 3×3，
    // 组合逻辑算完、下一拍寄存输出，所以四邻取 p01(上)/p21(下)/p10(左)/p12(右)。
    // 顺手用 up2/up1（还没移位进来的新值）会把整幅图错一行 —— 这是 blur 台架早就钉过的方向。
    wire [8:0] r_c = {p11[15:11], 2'b00} + {4'b0000, p11[15:11]};
    wire [8:0] r_n = {4'b0000, p01[15:11]} + {4'b0000, p21[15:11]}
                   + {4'b0000, p10[15:11]} + {4'b0000, p12[15:11]};
    wire [9:0] g_c = {p11[10:5], 2'b00} + {4'b0000, p11[10:5]};
    wire [9:0] g_n = {4'b0000, p01[10:5]} + {4'b0000, p21[10:5]}
                   + {4'b0000, p10[10:5]} + {4'b0000, p12[10:5]};
    wire [8:0] b_c = {p11[4:0], 2'b00} + {4'b0000, p11[4:0]};
    wire [8:0] b_n = {4'b0000, p01[4:0]} + {4'b0000, p21[4:0]}
                   + {4'b0000, p10[4:0]} + {4'b0000, p12[4:0]};

    wire [8:0] r_d = (r_c > r_n) ? (r_c - r_n) : 9'd0;
    wire [9:0] g_d = (g_c > g_n) ? (g_c - g_n) : 10'd0;
    wire [8:0] b_d = (b_c > b_n) ? (b_c - b_n) : 9'd0;
    wire [4:0] r_o = (r_d > 9'd31)  ? 5'd31 : r_d[4:0];
    wire [5:0] g_o = (g_d > 10'd63) ? 6'd63 : g_d[5:0];
    wire [4:0] b_o = (b_d > 9'd31)  ? 5'd31 : b_d[4:0];
    wire [15:0] sharp = {r_o, g_o, b_o};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q00<=0; q01<=0; q02<=0; q10<=0; q11<=0; q12<=0; q20<=0; q21<=0; q22<=0;
            de_d1<=0; de_d2<=0; de_out<=0; dout<=0;
        end else begin
            // 行缓存那两路与当前行那一路**都**跟 `shift_w` 走（含行尾多跳的一拍）：
            // 只让上面两行跳的话，末列那一格的"下面一行"还停在倒数第二列 ⇒ 窗口整体错一列
            //（#97：`tb_edge_rim` R4 实测 `got` 既不是 clamp 也不是原始平均，四个候选全不是）。
            // 消隐期没有新像素 ⇒ 当前行重复末列，与 `x_rd` 钉末列同一手法。
            if (shift_w) begin
                q00<=q01; q01<=q02; q02<=up2;
                q10<=q11; q11<=q12; q12<=up1;
                q20<=q21; q21<=q22; q22<=de_in ? din : q22;
            end
            de_d1 <= de_in;
            de_d2 <= de_d1;
            de_out <= de_d2;
            // 旁路取窗口中心抽头 p11（陈旧行已被换成当前行）—— 与 proc_box_blur 同一约定。
            dout   <= bypass ? p11 : sharp;
        end
    end
endmodule
