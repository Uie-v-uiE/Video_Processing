`timescale 1ns/1ps
// 无极缩放控制：原本尺寸(1.0x)为最大，向缩小方向循环再回到 1.0x。
// inv_scale Q8: 256=1.0x（最大），512=0.5x（最小，画面更小、四周黑边）。
// inv 越大 → 逆映射采样越“散”→ 显示画面越小。
module zoom_ctrl #(
    parameter [9:0] INV_LO = 10'd256,  // 1.0x 原始 = 最大
    parameter [9:0] INV_HI = 10'd512,  // 0.5x 最小
    parameter [9:0] STEP   = 10'd2
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire [2:0]  zsel,            // V8-8：手动档号（见下面八档表）
    input  wire        manual,          // V8-8：1=停在手动档（呼吸被打断），0=自动呼吸
    // V9-2：第三种缩放来源 —— 由**角度**定出来的"刚好装得下"那一档（见 zoom_fit.v）。
    //   为什么 mux 在本模块而不是在顶层：这里已经是"倍率的唯一出处"（八档表、呼吸、
    //   zoom_code 的分区比较都在本文件）；顶层再 mux 一次就会出现"屏上那一格与真正在用的
    //   inv 不是一回事"—— 那正是 lane23 两条判据要拦的那类错（#52/#59/#66 同一族）。
    // #93：旋转态的"装得下"上界。为什么它是**输入**而不是顶层的第二次 mux：见下面 fit_en
      //   那一段的同一个理由 —— 倍率的唯一出处只能有一个，否则 `zoom_code`（OSD 那一格）报的是
      //   用户按下的档、mapper 画的是另一档（#52/#59/#66 那一族）。
      input  wire        rotate_en,       // 1=旋转真的在生效（顶层把 `rotate_active` 原样递进来）
      input  wire        fit_en,
    input  wire [9:0]  inv_fit,         // 拟合值（Q8，与 inv_scale 同一个约定）
    input  wire        frame_start,
    output reg  [9:0]  inv_scale,
    output wire [9:0]  inv_used,        // ← 顶层 / OSD / lane23 一律读这一个
    output reg         zoom_active,
    output reg  [2:0]  zoom_code,     // V8-5：OSD 的"最近一档"编号（见下面的表）
    output reg         dir,           // 0: 向缩小走(inv增) 1: 回到1.0x(inv减)
    output wire        rot_forced     // #93：1=这一帧生效的倍率是被旋转钳出来的，不是用户那一档
                                      //   ⇒ 顶层把它并进 OSD 的 `(Fit)` 标记，屏上才讲真话
);
    // ---- V8-8：八档"用户能点出来的倍率"表（Q8 倒数尺度，纯常数，不做除法，#58）----
    // 档号与下面 OSD 那张表**同一个约定**：0=0.25 1=0.33 2=0.50 3=0.75 4=1.00 5=1.33 6=1.50 7=2.00。
    // 为什么两张表能互相对上：`zoom_code` 是拿 inv 与**相邻两档的中点**比大小得到的 ⇒ 表值代回自己那一档必然
    //   落在自己的区间里 —— 这条不是巧合，是台架判据（tb_zoom_sel 逐档验 `code(TBL[i]) == i`，改哪边都会红）。
    // 呼吸仍然只在 [INV_LO, INV_HI]（默认 1.0x…0.5x）里走；手动档允许到 2.0x/0.25x：`zoom_mapper` 是**逆**映射，
    //   inv 变小只是采样窗收进画面内部（不越界），inv 变大则四周填黑 —— 两种都不需要动 mapper。
    function [9:0] tbl;
        input [2:0] i;
        begin
            case (i)
                3'd0: tbl = 10'd1023;   // 0.25x —— **不是 1024**：inv_scale 只有 10 bit（Q8 的天花板
                                        // 就是 1023 ⇒ 1024 会回绕成 0，画面上变成"无限大"而不是 0.25x）。
                                        // 1023 对应 0.2502x，与档名差 0.02 %，台架按 10 bit 的边界钉住。
                3'd1: tbl = 10'd776;    // 0.33x
                3'd2: tbl = 10'd512;    // 0.50x
                3'd3: tbl = 10'd341;    // 0.75x
                3'd4: tbl = 10'd256;    // 1.00x
                3'd5: tbl = 10'd192;    // 1.33x
                3'd6: tbl = 10'd171;    // 1.50x
                default: tbl = 10'd128; // 2.00x
            endcase
        end
    endfunction
    // ---- OSD 用的 8 档倍率表（#58 合规做法：查表，不除）----
    // ⚠ 比较的对象是 `inv_used`（真正喂给 mapper 的那一个），不是 `inv_scale`：开拟合时后者还停在呼吸/手动的
    //   位置，拿它分区就会"屏上写 1.00x、画面上是 0.52x"。
    // inv_scale 是 Q8 倒数尺度：scale = 256/inv ⇒ 想显示 "0.75x" 就得算 25600/inv，那是一条运行时非 2 幂除法
    //   —— 在快域里就是 #58 那个 −5.014 ns 的组合除法器。所以这里只把 inv 与**相邻两档的中点**比大小（8 档
    //   ⇒ 7 个常数比较，优先级链），结果寄存一拍再给 OSD ⇒ OSD 的 `chars[]` 那一片只多一个 3 bit 的 case 译码。
    reg [2:0] code_nxt;
    wire [9:0] inv_raw = fit_en ? inv_fit : inv_scale;
    // #93：旋转时不许放大到画外 —— 生效倍率取"用户那一档"与"这个角度刚好装得下那一档"里
    //   **画面较小**的那一个（inv 越大画面越小 ⇒ 取较大的 inv）。
    //   代价（写进口径，不藏着）：① 旋转态因此**不提供放大**，1.33x/1.5x/2.0x 三档在旋转时被拉回 fit；
    //   ② **0° 不在钳之内**：顶层递进来的 `rotate_en` 就是 `angle_ctrl.v:18` 的 `rotate_active = (angle != 0)`，
    //     所以角度正好 0° 时这一支整个不参与（`inv_used == inv_raw`）。这里原先写的是"0° 因为 ±0.5 LSB
    //     的表余量给 259 ⇒ 也在钳"——那是把 `zoom_fit` 的**输出**当成了生效条件，实测口径见 #162，
    //     注释一直留到本轮（r97）才改。两条口径都由 tb_zoom_sel 的 T8 钉住（T8a 是"不旋转时一个字都不改"的负对照）。
    wire       rot_clamp = rotate_en && (inv_raw < inv_fit);
    assign inv_used   = rot_clamp ? inv_fit : inv_raw;
    assign rot_forced = rot_clamp;
    always @(*) begin
        if      (inv_used >= 10'd900) code_nxt = 3'd0;
        else if (inv_used >= 10'd644) code_nxt = 3'd1;
        else if (inv_used >= 10'd427) code_nxt = 3'd2;
        else if (inv_used >= 10'd299) code_nxt = 3'd3;
        else if (inv_used >= 10'd224) code_nxt = 3'd4;
        else if (inv_used >= 10'd182) code_nxt = 3'd5;
        else if (inv_used >= 10'd150) code_nxt = 3'd6;
        else                     code_nxt = 3'd7;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inv_scale   <= INV_LO;
            dir         <= 1'b0;
            zoom_active <= 1'b0;
            zoom_code   <= 3'd4;                 // 1.00x：与 INV_LO=256 一致
        end else begin
            // 档位号只跟着**上一拍**的 inv_scale ⇒ 这一段不进 OSD 那条组合链（V7.9.4 的教训）。
            // 与 inv_scale 同一个块驱动：多驱动 net 会让综合扔掉逻辑那一侧，见 ISSUES #61。
            zoom_code   <= code_nxt;
            if (fit_en) begin
                // V9-2 拟合：整条 inv_scale 链**旁路**（这里不写 inv_scale ⇒ 关掉拟合时，
                // 呼吸/手动从它原来的位置接着走，不会跳档）。但 `zoom_active` 要照
                // `inv_used` 报 —— 不然会出现"lane23 说没在缩放、屏上画面缩了一半"。
                zoom_active <= (inv_used != INV_LO);
            end else if (!enable) begin
                inv_scale   <= INV_LO;
                dir         <= 1'b0;
                zoom_active <= 1'b0;
            end else if (manual && frame_start) begin
                // 手动档：**与呼吸同一个节拍，只在帧首换** ⇒ 一帧之内不会半屏新一档半屏旧一档。
                // `dir` 故意不动：从手动切回自动时，从当前 inv 继续朝原方向走（不跳档）。
                inv_scale   <= tbl(zsel);
                // #176：这一位比较的也必须是一真在用的那一个（`inv_used`），不是用户那一档 ——
                // 旋转钳生效时"档号 = 1.00x"而画面缩到 0.75x，lane23 的 bit11 就在那里说过谎。
                zoom_active <= (inv_used != INV_LO);
            end else if (frame_start) begin
                // 手动档可以把画面停在呼吸带**之外**（2.0x 在下方、0.25x 在上方）。
                // 切回自动时不许瞬移：原来 `!dir` 那一支在 inv 已经大于 INV_HI 时会写成
                // `inv <= INV_HI`，于是 1023 → 512 一帧跳掉半幅 —— 用户看到的就是"画面弹一下"。
                // 现在改成**朝带回里走**（每帧一步），进带之后原有逻辑接管，方向交给 dir。
                if (inv_scale > INV_HI) begin
                    inv_scale <= inv_scale - STEP;
                    dir       <= 1'b1;
                end else if (!dir) begin
                    // inv 上升 → 画面缩小
                    if (inv_scale + STEP >= INV_HI) begin
                        inv_scale <= INV_HI;
                        dir       <= 1'b1;
                    end else begin
                        inv_scale <= inv_scale + STEP;
                    end
                end else begin
                    // inv 下降 → 回到原始大小
                    if (inv_scale <= INV_LO + STEP) begin
                        inv_scale <= INV_LO;
                        dir       <= 1'b0;
                    end else begin
                        inv_scale <= inv_scale - STEP;
                    end
                end
                zoom_active <= 1'b1;
            end else begin
                // #176：稳态这一支也一样 ⇒ "有没有在缩放"只看**真正喂给 mapper 的那一个**（`inv_used`）。
                zoom_active <= (inv_used != INV_LO);
            end
        end
    end
endmodule
