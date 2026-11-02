`timescale 1ns/1ps
// shown_rate —— OSD 的 `FPS:` 格：数**写进屏的新帧**，不是数扫过屏的显示场（ISSUES #128）。
//
// 为什么要有这个模块：顶层原来数的是显示场的 `vs` 沿（`pl_video_top.v` 里 `vs_tick`/`vs_sys` 那一段），
// 窗口又是 `sys_clk` 的 1.000 s，而面板是 1344×625@50 MHz ⇒ 59.52 Hz ⇒ 屏上那一格**恒在 59/60 附近**，
// 片源是 30 fps、15 fps 还是根本没有片源都看不出来。`report/MODULES.md` 早就把这条口径写明了，
// 所以这是"已知的口径缺陷要改掉"，不是新抓到的隐藏 bug。
//
// "一帧新内容上屏"在三个片源上各有各的凭据，这里只共用顶层已经有的那几根线，不新造判据：
//   ETH   —— `eth_new` 是 `frame_ready && eth_link_pix` 的一拍脉冲（帧缓存里刚提交好一帧）。
//            它落在哪一拍不重要，重要的是**下一次 `frame_start` 才真的被扫到** ⇒ 内部存一个 `eth_pend`，
//            在 `frame_start` 用掉。原来顶层缺这一位（所以"帧到了"与"帧上屏"混成一根线）。
//   PS/SD —— `pub_consume && pub_pend` 已经存在于顶层（它就是翻 `fs_tog` 的那个条件）⇒ 直接拿来用。
//   图卡   —— 内容每个显示帧都是新的，所以 `frame_start` 本身。
//
// ⚠ `frame_start` 与 `eth_new` 同拍时按"仍然欠着一帧"算：新内容是在这一场开始之后才进缓存的，
//   这一场扫的是上一场的内容。把优先级写反会让读数在 ETH 满速时偏高（台架 S2 就是钉这件事的）。
//
// 窗口常数不改口径只挪域：默认 `WIN_LAST = 49_999_999` 与顶层原来那枚一个字相同
//   （50 MHz ⇒ 正好 1.000 s）；搬进 `clk_pix` 之后 `fps_q` 与 OSD 同域，
//   顶层那组"sys_clk 里寄存、像素域直读"的准静态位就此少一对。台架把窗口缩到几千拍才能逐秒判定。
module shown_rate #(
    parameter integer WIN_LAST = 49_999_999       // 计数到这一拍结束一个窗口（50 MHz ⇒ 1.000 s）
)(
    input  wire       clk,                        // clk_pix
    input  wire       rst_n,
    input  wire       frame_start,                // 一个显示场开始扫
    input  wire       owner_eth_pix,              // 当前片源是 ETH
    input  wire       fb_vis,                     // 1 = 屏上内容是帧缓存里的片源（ETH 或 PS）
    input  wire       eth_new,                    // 帧缓存里刚提交好一帧（一拍脉冲）
    input  wire       pub_consume,                // 这一场取走了 PS 发布的内容
    input  wire       pub_pend,                   // PS 已发布还没被取走
    output reg  [7:0] fps_q                       // 上一个完整窗口里的新帧数
);
    localparam [25:0] WIN = WIN_LAST[25:0];

    reg        eth_pend;
    reg [25:0] win_cnt;
    reg [31:0] acc;

    // 一行一个谓词，是为了 `sim/mut_control.sh` 的反例能一行 sed 掉它（拆成多行就会一次改两件事）。
    wire new_shown = frame_start && (owner_eth_pix ? eth_pend : (fb_vis ? (pub_consume && pub_pend) : 1'b1));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eth_pend <= 1'b0;
            win_cnt  <= 0;
            acc      <= 0;
            fps_q    <= 0;
        end else begin
            if (eth_new)                         eth_pend <= 1'b1;
            else if (frame_start && owner_eth_pix) eth_pend <= 1'b0;

            if (win_cnt == WIN) begin
                win_cnt <= 0;
                fps_q   <= acc[7:0];
                acc     <= 0;
            end else begin
                win_cnt <= win_cnt + 1'b1;
                if (new_shown) acc <= acc + 1'b1;
            end
        end
    end
endmodule
