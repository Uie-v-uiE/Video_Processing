`timescale 1ns/1ps
// pl_video_top — ghosting-fix v5
// Display BRAM written ONLY by axi_frame_writer_gated during blanking (~de).
// commit base locked until copy completes.
module pl_video_top #(
    parameter IMG_W     = 512,
    parameter IMG_H     = 300,
    parameter PANE_W    = 512,
    parameter BASE_ADDR = 32'h1000_0000,
    // PS 片源（SD 回放 / FILL 诊断帧）专用 DDR bank，与 ETH 的乒乓双 bank 错开。
    // 仲裁只管"谁用 DDR→帧缓存这台搬运机"，**管不到谁写 DDR**（SD 的 DMA 走 PS 的 HP0、不经过 PL）
    // ⇒ 两路同时跑时重叠只能靠地址分开。这个数必须与 src/ps 的 FRAME_ADDR 一致（见 system_top）。
    parameter PS_BASE_ADDR = 32'h1010_0000,
    parameter ZOOM_DEFAULT_ON = 1,
    // #51：扫描速度与端点是"设一次就忘"的量 ⇒ 做成构建参数，不占控制位（#70 的预算账）
    parameter [3:0] SPLIT_SPEED = 4'd1,
    parameter [4:0] SPLIT_LO16  = 5'd2,
    parameter [4:0] SPLIT_HI16  = 5'd14
)(
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        axi_clk,
    input  wire        axi_rst_n,

    // V8 的九位算法选择字（新控制字 gpio_cfg[8:0]），一位一级、**唯一**的一套效果口径
    // （逐位含义见 proc_pipeline.v 文件头）。V7 那五位 `effect_en` 的兜底合流已删（见 ISSUES #66）。
    input  wire [8:0]  stage_sel,
    input  wire [7:0]  threshold,
    // 第二个控制字的**通道 2**（axi_gpio_2 的 GPIO2，偏移 +0x08）：gamma 表的
    // {en[31], wr[30], data[29:22], idx[21:14]}。位序与理由写在 gamma_lut.v / spec §6b。
    input  wire [31:0] gamma_ctl,
    input  wire        src_sel,
    input  wire        zoom_en,
    input  wire        bilin_en_axi,   // #83：gpio_o[19]（PS 的 BILIN_BIT），axi 域准静态电平
    input  wire        osd_off_axi,    // r83：gpio_o[20]（**反相**，1 = 关掉叠层），同一类准静态电平
    // V8-2：串口命令可以把片源模式**钉住**，不必只靠按键环。都是 axi 域准静态电平，跨域与
    // "命令优先还是按键优先"全在 `src_mode` 里处理，这一层只把线接过去（不许在这里自己采）。
    input  wire [1:0]  mode_ovr,        // 00 自动 / 01 锁 ETH / 11 锁 SD / 10 锁 TEST（屏上就印这三个词）
    input  wire        mode_ovr_tog,    // 翻一次 = 上面那个码是新写的
    // V8-8 手动缩放：档号 [28:26] 与手动旗标 [29]，与 `stage_sel` 来自**同一个 32 位控制字**
    // （gpio_cfg1 = PS 侧 CFG_DATA0），都是 axi 域异步电平 ⇒ 一律交给 effect_ctrl 那条 sel 链同步，
    // 这一层**不许自己采样**（见 ISSUES #24/#49）。
    input  wire [2:0]  zoom_sel_async,
    input  wire        zoom_manual_async,
    // #51：这一束控制位（V9 起改名**几何控制字**，19 位，名字留着是为了不折腾台架）：
    //   [9:0]=pos_px、[10]=auto_en、[11]=follow、[12]=swap、[13]=marker_off、[14]=rot_auto、
    //   [17:15]=rot_speed（度/帧）、[18]=zoom_fit；物理位 = CFG_DATA0[22:13]、[25:23]、[30]、[9]、
    //   [12:10]、[31]（在 system_top 里拼成一束），19 位**一起过同一条 snap_cross**。位图正本见 ISSUES #70 追加。
    // ⚠ 不并进 effect_ctrl 那条现成的 ASYNC_REG 链（#71：加宽会让 cdc.rpt 的 unsafe 端点按位长涨），
    //   也不再开第二条 snap_cross（多一对 bus/toggle 同步器 = CDC-11 Critical 的签名，#65、r54 构建 #34 各红过一次）。
    input  wire [18:0] split_ctl,
    // PS 侧"这一帧 DDR 写完了"的发布脉冲：每翻转一次 = 请求 PL 在下一个 frame_start
    // 把 DDR 搬进显示帧缓存一次。SD 回放靠它避免撕裂（见 src/ps/sd_play.c 头部协议说明）。
    input  wire        ps_publish,

    input  wire        key1_n,
    input  wire        key2_n,
    output wire [1:0]  led,
    // 仲裁状态的可观测口（axi 域电平 ⇒ 零新增跨域），system_top 把它映到健康 GPIO 的 lane30。
    // 为什么需要它：`owner_eth` 决定"此刻屏幕归谁"，以前只有眼睛看屏幕才知道 ⇒ "停流不交回"这类
    // 板级红夜里既看不见也没法记账；现在 JTAG 读一次就判红绿，而且**红的时候读得出是谁占着**。
    // 位序（与 system_top 的 lane30 一致，`assign dbg_src` 那一行是同一份）：
    //   bit0=eth_tb_ok bit1=eth_live bit2=owner_eth bit3=fill_busy(PS 搬运中) bit4=row_busy(ETH 搬运中)
    //   bit[6:5]=仲裁看到的模式(格雷码，同 src_arb 的 sel) bit7=0 bit[10:8]=why_ps=判决那一拍的 {force_ps, ~eth_live, ~eth_tb_ok}（仅 bit2=0 时才有"为什么"的意思）
    output wire [15:0] dbg_src,
    // V8-6 链路内时延的可观测口（axi 域电平，**单位是 axi 拍数不是时间**，见 frame_latency 文件头）：
    //   lane29=c1（等消隐）lane28=c2（搬运）lane27=tot（提交→上屏）lane26=max lane25={n_meas,clamped}
    // 换算成时间戳在 `src/host/health_read.mjs` 里做（一个常量：fclk0=100 MHz ⇒ 1 拍 = 10 ns）。
    output wire [6*32-1:0] dbg_lat,
    // V8-8 最后一跳（lane23）：像素域**正在用**的缩放状态，已跨到 axi 域。
    //   位图（含 V9-2 的 bit19=zoom_fit）**唯一出处在文件尾 `assign dbg_zoom` 上面那段**，这里不抄
    //   第二遍 —— 抄两遍就是 #66 那一族的病（改一处忘一处，症状是"脚本读错档"）。
    // ⚠ 与上面两口的区别：dbg_src/dbg_lat 全取自 axi 域现成电平 ⇒ 零新增跨域；这一口的 19 位
    //   **本来在像素域**，所以必须真跨一次（snap_cross + 帧首准静态总线，见文件尾）。
    output wire [31:0] dbg_zoom,
    // 抄快照的触发：system_top 在"lane 选择指到 25"时给一拍（读这一组的第一个字天然就是它）。
    // 为什么需要它：五个字之间有恒等式 tot ≥ c1+c2，而 live 寄存器每轮都在换，
    // 上位机逐 lane 读会读到不同轮 ⇒ ISSUES #59（板级 11 组读数里 4 组破坏恒等式）。
    input  wire        lat_arm,

    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_data_p,
    output wire [2:0]  tmds_data_n,

    output wire [31:0] m_axi_araddr,
    output wire [5:0]  m_axi_arid,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [63:0] m_axi_rdata,
    input  wire [5:0]  m_axi_rid,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,

    input  wire        eth_wr_clk,
    input  wire        eth_wr_en,
    input  wire [18:0] eth_wr_addr,
    input  wire [15:0] eth_wr_data,
    input  wire        eth_link,
    // "最近真的有帧"（axi_clk(fclk0) 域电平，取自健康快照 lane7.bit3 = stall_ms < 200）。
    // eth_tb_ok：量这位的**源时基**（eth_rxc）还准不准 —— 板级实测断链时 RTL8211 不停 RXC 而是把它
    // 拉到 ≈2.5 MHz ⇒ stall_ms 慢约 48 倍地爬，"活着"这一位会连着十几秒说谎。
    // 两位的相与放在 src_arb 里（那里才是判据的主人，也才台架验得到），不在本文件外面做。
    // 与 eth_link 的分工：eth_link 只喂 OSD/状态（R08~R10 依赖它的语义，不动）；**谁拥有 AXI 读口 + 帧缓存
    // 写口**由 src_arb 决定 —— eth_link 是"自配置以来收过任何一个包"（ARP 就触发、拔线不回 0），那是 PS 片源被永久锁死的根（见 ISSUES #47）。
    input  wire        eth_live,
    input  wire        eth_tb_ok,
    input  wire        eth_frame,
    input  wire [31:0] eth_ddr_base,
    input  wire        eth_commit,
    // （r55）这里不再有 eth_pkts / eth_bad / lm_bus 三个口：那两级触发器是**拿单 bit 的规矩跨 16 位
    //   总线**，而同步完的值在 V8-5 撤下屏之后没有读者。数走 link_monitor → snap_cross 的 lane1/8/9。
    //   见 ISSUES #64。

    output wire [31:0] status,
    output wire        copy_hold
);
    wire clk_pix, clk_pix5x, locked;
    wire clk_200m_unused;
    clk_gen u_clk (
        .clk_in(sys_clk), .rst_n(sys_rst_n),
        .clk_pix(clk_pix), .clk_pix5x(clk_pix5x), .clk_200m(clk_200m_unused), .locked(locked)
    );
    wire rst_pix_n = sys_rst_n & locked;

    wire p1, p2, k1_up;
    wire k1_short, k1_hold, ltog;
    key_debounce #(.CNT_MAX(1_000_000)) u_k1 (
        .clk(sys_clk), .rst_n(sys_rst_n), .key_n(key1_n), .pulse(p1), .key_stable(k1_up)
    );
    key_debounce #(.CNT_MAX(1_000_000)) u_k2 (
        .clk(sys_clk), .rst_n(sys_rst_n), .key_n(key2_n), .pulse(p2), .key_stable()
    );
    wire owner_eth_pix;          // 前面声明、下面赋值：u_mode 要拿它挑 AUTO 的下一态

    // ---- 同一个按键的两种语义：短按 = 旋转 ±1°，长按 0.6 s = 切换片源模式。
    //      长按事件用**翻转位**跨域（脉冲跨域会被吃掉，与 `ps_publish` / ISSUES #36 是同一课）。
    //      短按改到**松手时**发（ISSUES #55）：以前由 u_k1 在按下沿发 ⇒ 每次长按必先进 1°。
    //      p1 现在不再驱动旋转（留着只因为它是 u_k1 的输出端口，删它要动 key_debounce 的接口）。
    key_long #(.HOLD_CYC(30_000_000), .ARM_CYC(10_000_000)) u_k1l (   // 50 MHz ⇒ 0.6 s / 0.2 s
        .clk(sys_clk), .rst_n(sys_rst_n), .pressed(~k1_up),
        .tog(ltog), .short_pulse(k1_short), .holding(k1_hold));

    localparam [1:0] M_AUTO = 2'd0, M_ETH = 2'd1, M_SD = 2'd3, M_TEST = 2'd2;
    // 模式寄存器搬到了 `src/rtl/util/src_mode.v`，理由是"这段逻辑有没有台架"：写在这里时顶层没有
    // 台架碰得到它，于是同步链的复位值与源头不一致（`tog` 复位 0、链复位 3'b111）一直没人查 ⇒
    // 上电白送一次"长按"、模式自走到"锁 ETH"、`force_eth` 长占 ⇒ #28 板级交接判据红的根（见 ISSUES #49）。
    wire [1:0] mode;
    src_mode u_mode (
        .clk(clk_pix), .rst_n(rst_pix_n), .ltog(ltog),
        .eth_now(owner_eth_pix), .ov_code(mode_ovr), .ov_tog(mode_ovr_tog), .mode(mode)
    );
    wire mode_eth  = (mode == M_ETH);
    wire mode_ps   = (mode == M_SD);
    wire mode_card = (mode == M_TEST);

    (* ASYNC_REG = "TRUE" *) reg [1:0] ms0, ms1, ms2;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin ms0 <= M_AUTO; ms1 <= M_AUTO; ms2 <= M_AUTO; end
        else begin ms0 <= mode; ms1 <= ms0; ms2 <= ms1; end
    end
    // 图卡模式不参与仲裁（保持 AUTO）：它只是"显示什么"，不是"谁在搬"
    wire [1:0] arb_sel = (ms2 == M_ETH) ? 2'd1 : (ms2 == M_SD) ? 2'd2 : 2'd0;
    // ---- V9 的几何控制字（19 位，跨域在下面的 u_split_x，与 #51 那 14 位同一条路）----
    // 这里先声明、在下面才由 snap_cross 驱动：angle_ctrl / zoom_ctrl 排在驱动它的那一条之前，
    // 而 Verilog-2001 不许在名字声明之前先切它的位（写成隐式 net 就是"看着接上、其实常 0"）。
    wire [18:0] gp;
    wire        rot_auto    = gp[14];    // 自动旋转
    wire [2:0]  rot_speed   = gp[17:15]; // 度/帧，0 = 钉住
    wire        zoom_fit_en = gp[18];    // 缩放跟着角度自动定（见 zoom_fit.v）
    reg         rot_fs_tog;              // 每个显示帧翻一次 —— 单独一个 FF，理由见 angle_ctrl 文件头

    wire [8:0] angle;
    wire rotate_active;
    angle_ctrl u_ang (
        .clk(sys_clk), .rst_n(sys_rst_n),
        .key_inc(k1_short), .key_dec(p2),   // 短按改松手发（ISSUES #55）
        .frame_tgl(rot_fs_tog), .auto_en(rot_auto), .speed(rot_speed),
        .angle(angle), .rotate_active(rotate_active)
    );

    wire [7:0] th_sync;
    wire [8:0] sel_sync;
    wire       gm_en, gm_wr;
    wire [7:0] gm_idx, gm_data;
    wire [5:0] gm_disp;          // V8-5：只给 OSD 的 gamma×10（同一对同步器带过来的 6 位）
    wire [7:0] tmp_disp;         // V9-6：只给 OSD 的片上温度 BCD（**同一对**同步器的低字节）
    wire [2:0] zsel_pix;         // V8-8：手动档号（与 sel_sync 同源同深度）
    wire       zman_pix;         // V8-8：手动旗标
    effect_ctrl u_eff (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .stage_sel_async(stage_sel),
        .zoom_sel_async(zoom_sel_async),
        .zoom_manual_async(zoom_manual_async),
        .threshold_async(threshold),
        .gamma_async(gamma_ctl),
        .stage_sel(sel_sync),
        .zoom_sel(zsel_pix), .zoom_manual(zman_pix),
        .threshold(th_sync),
        .gamma_en(gm_en), .gamma_wr(gm_wr), .gamma_idx(gm_idx), .gamma_data(gm_data),
        .gamma_disp(gm_disp), .temp_disp(tmp_disp)
    );

    (* ASYNC_REG = "TRUE" *) reg ze0, ze1, ze2;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            ze0 <= ZOOM_DEFAULT_ON[0];
            ze1 <= ZOOM_DEFAULT_ON[0];
            ze2 <= ZOOM_DEFAULT_ON[0];
        end else begin
            ze0 <= zoom_en; ze1 <= ze0; ze2 <= ze1;
        end
    end
    wire zoom_run = ze2;

    wire [11:0] x, y;
    wire hs, vs, de, frame_start, frame_done;
    video_timing_1024x600 u_t (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .x(x), .y(y), .hs(hs), .vs(vs), .de(de),
        .frame_start(frame_start), .frame_done(frame_done)
    );

    // 自动旋转的节拍：帧首翻转位（像素域产生，angle_ctrl 里同步）。
    // ⚠ **单独一个发射触发器**，不共用现成的 sof_tgl / z_hb_tog：同一个翻转位扇出到两组目的域
    //   同步器 = CDC-11 Critical 的签名，本文件里已为这件事红过两次（#65、r54 构建 #34）。
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) rot_fs_tog <= 1'b0;
        else if (frame_start) rot_fs_tog <= ~rot_fs_tog;
    end

    wire [7:0]  pipe_off_rows;   // 效果链自己声明的"内容滞后几行"（u_pipe 的输出口）
    // ---- r59b-1（#73）：整屏一个视口 ----
    //   1024 个显示列对应 512 个源列 ⇒ 每个源列在屏上占两列；行方向 600 对应 300，还是那一次 >>1。
    //   原图抽头与处理抽头从此共用同一份源坐标，缝只是逐像素二选一 ⇒ "分割线 0~100 % 可调"与
    //   "整体旋转缩放"在数学上第一次相容（旧几何两屏各画一整幅，缝只能钉死在 512，见 #62）。
    wire        left_pane = (x < PANE_W);      // 只留给调试位；内容选择从此不看它
    wire [11:0] cx = x >> 1;                   // 视口内的源列（0..511），左右两半同一个数
    wire [11:0] cy = (y >> 1) < IMG_H ? (y >> 1) : (IMG_H - 1);
    // 右窗读坐标**提前 u_pipe.OFF_LINES 个显示行**（= 效果链的内容滞后，实测 −4 行且逐像素一致）：行缓存式
    // 3×3 滤波必然滞后一整行 ⇒ "把数据提前"不可能，只能"把地址提前"（片源在帧缓存里，地址本来就是随机的）；
    // 且提前量必须加在 **mapper 的显示行输入**上而不是输出的源行上 —— 链子的滞后发生在显示栅格上，缩放/旋转
    // 之后"源行差 4"≠"显示行差 4"。#52 在这之上又叠了双线性读口行方向的 2 行（一对的结果要在这对的第二行
    // 才算得出）：请求行 = (Y+OFF+2)>>1，而实际显示的是上一对算出的 ⇒ 源行 = 它 −1 ✓；`u_raw` 那条行环不动。
    // ⚠ BILIN_ROWS 必须**偶数**（`row0 = ~y[0]` 定成对奇偶，奇数会让一对分属两个源行 ⇒ A/B 错行）。凭据 tb_v89 T1、tb_v101 L3/L6、tb_v98 C1c/C1d/C1h；缝连续性的最终凭据是眼睛（board/README.md 第 12 行）。
    localparam integer BILIN_ROWS = 2;
    // bilin 的运行时 on/off：`gpio_o[19]`（#83）→ 这条 3 级同步 → `bilin_en_pix`。
    //   为什么走 gpio_o 而不是 cfg1：cfg1 的 32 位已满（docs/COMMANDS.md §5 的位表），那是一次新跨域。
    //   复位默认取 **1** ⇒ 上电画面与它是 localparam 常量那一版逐位相同（"加了口子但观感不变"可查）。
    (* ASYNC_REG = "TRUE" *) reg be0, be1, be2;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            be0 <= 1'b1; be1 <= 1'b1; be2 <= 1'b1;
        end else begin
            be0 <= bilin_en_axi; be1 <= be0; be2 <= be1;
        end
    end
    wire bilin_en_pix = be2;
    // OSD 总开关（r83）：`gpio_o[20]`（反相）→ 这一条**独立**的 3 级同步 → `osd_en`。
    //   为什么每一位各走一条链而不共用：#65 那一次 CDC-11 就是"把两个翻转位挂同一级扇出"打出来的；
    //   为什么复位取 **0**（= OSD 开着）：与固件默认一致 ⇒ 上电/PS 没写过时的屏上与加这个口子之前
    //   逐位相同，"开了口子但观感不变"是可查的（同 `be0..be2` 取 1 的理由，#83）。
    (* ASYNC_REG = "TRUE" *) reg oo0, oo1, oo2;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            oo0 <= 1'b0; oo1 <= 1'b0; oo2 <= 1'b0;
        end else begin
            oo0 <= osd_off_axi; oo1 <= oo0; oo2 <= oo1;
        end
    end
    wire osd_en = ~oo2;
    wire [12:0] y_right_adv = {1'b0, y} + {5'b0, pipe_off_rows} + BILIN_ROWS[12:0];
    wire [11:0] y_req_row = y_right_adv[11:0] >> 1;
    // #97 第四笔 / #98：读行提前 `OFF_LINES + BILIN_ROWS` ⇒ 本帧末尾几行的越界请求喂的是**下一帧的头
    // 几行**，钳到 `IMG_H-1` 就让屏顶画"这张图自己的末行"：列位置与段数一点都不变 ⇒ #92/#93 那十二格
    // 全都看不见（C5 就是为这一格写的尺子）。绕回后仍走一遍逆缩放 ⇒ 小于 1.00x 不多出一条顶带。
    // ⚠ **取模的对象是"请求行"，窗也必须按"写进环的那一拍"来开**（r77 踩在这里；P98 探针量的就是环写
    //   侧每拍摆的 `sy(r−2)`）：本式比旧窗早两行，帧头 0..7 才逐格等于定义 `prow>>1`。**减一次就够**：
    //   `y_req_row` 最大 302 ⇒ 不需要除法器/取模（#58）。凭据 tb_v98 的 C5c/C5b；C1h 跟着本式改 ⇒ 不能当尺子。
    wire [11:0] cy_r = (y_req_row >= IMG_H) ? (y_req_row - IMG_H) : y_req_row;

    wire [9:0] inv_scale;
    wire [9:0] inv_fit;          // V9-2：角度定出来的"刚好装得下"那一档
    wire [9:0] inv_used;         // ← 本文件里"此刻真的在用哪个倍率"的**唯一**读数
    wire       zoom_active, zoom_dir;
    wire [2:0] zoom_code;        // V8-5：OSD 的"最近一档"（八档表在 zoom_ctrl 里，不除）
    zoom_fit #(.IMAGE_W(IMG_W), .IMAGE_H(IMG_H)) u_zfit (
        .clk(clk_pix), .rst_n(rst_pix_n), .angle(angle), .inv_fit(inv_fit)
    );
    zoom_ctrl #(.INV_LO(10'd256), .INV_HI(10'd512), .STEP(10'd2)) u_zctrl (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .enable(zoom_run), .frame_start(frame_start),
        .zsel(zsel_pix), .manual(zman_pix),        // V8-8：手动档（同一对同步器带来的两个位）
        .fit_en(zoom_fit_en), .inv_fit(inv_fit),   // V9-2：第三种来源；mux 在 zoom_ctrl 里做，不在这里
        .inv_scale(inv_scale), .inv_used(inv_used),
        .zoom_active(zoom_active), .zoom_code(zoom_code),
        .dir(zoom_dir)
    );

    // 旋转/缩放从此属于**整幅画面**：只有一份源坐标，左半不再单独走一条"不旋转"的路。
    //   旧的 cx_q*/cy_q* 三拍打拍与 sx_l/sy_l 一起删掉 —— 那是"两屏各画一整幅"时代的遗产。
    //   ⚠ 这是对观感有实感的改动（#73 第 0 条）：整幅图铺满 1024，旋转时左右两半一起转。
    wire        rot_on = rotate_active;
    wire [11:0] sx, sy;
    wire        oob;
    wire [7:0]  zfrac_x, zfrac_y;
    zoom_mapper #(.IMAGE_W(IMG_W), .IMAGE_H(IMG_H)) u_zmap (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .inv_scale(inv_used), .angle(angle), .rotate_en(rot_on),
        .x_in(cx), .y_in(cy_r),     // ← 提前 OFF_LINES 个显示行，抵掉效果链的内容滞后（#54 (B)）
        .x_out(sx), .y_out(sy), .oob(oob),
        .frac_x(zfrac_x), .frac_y(zfrac_y)
    );

    // 混色级要的列坐标必须由**流水线深度**推出来，不许再抄字面量 11（ISSUES #68）。
    //   内容站在：3(`cx/cy` 打到 mapper 与左路的打拍) + 1(`rd_addr_q`) + 1(BRAM 读出) + PROC_LAT = 20 级。
    //   以前 `u_split` 拿的是 `x_d[11]` ⇒ 缝的判定比内容旧 9 列（台架 `tb_v98_top_seam` 的 C-tap 钉住）。
    localparam MIX_D = 3 + 1 + 1 + u_pipe.LATENCY;
    localparam SB = (MIX_D > 16) ? (MIX_D + 1) : 16;
    reg        de_d[0:SB-1], hs_d[0:SB-1], vs_d[0:SB-1], left_d[0:SB-1];
    reg [11:0] x_d[0:SB-1], y_d[0:SB-1], cx_d[0:SB-1], cy_d[0:SB-1];
    integer k;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            for (k = 0; k < SB; k = k + 1) begin
                de_d[k]<=0; hs_d[k]<=0; vs_d[k]<=0; left_d[k]<=1;
                x_d[k]<=0; y_d[k]<=0; cx_d[k]<=0; cy_d[k]<=0;
            end
        end else begin
            de_d[0]<=de; hs_d[0]<=hs; vs_d[0]<=vs; left_d[0]<=left_pane;
            x_d[0]<=x; y_d[0]<=y; cx_d[0]<=cx; cy_d[0]<=cy;
            for (k = 1; k < SB; k = k + 1) begin
                de_d[k]<=de_d[k-1]; hs_d[k]<=hs_d[k-1]; vs_d[k]<=vs_d[k-1];
                left_d[k]<=left_d[k-1]; x_d[k]<=x_d[k-1]; y_d[k]<=y_d[k-1];
                cx_d[k]<=cx_d[k-1]; cy_d[k]<=cy_d[k-1];
            end
        end
    end

    // --- v5.3 ETH path ---
    wire row_start, row_done, row_busy;
    wire [31:0] row_base;
    wire row_wr_en;
    wire [18:0] row_wr_addr;
    wire [63:0] row_wr_data;
    wire [31:0] row_araddr;
    wire [7:0]  row_arlen;
    wire [2:0]  row_arsize;
    wire [1:0]  row_arburst;
    wire        row_arvalid, row_rready;
    wire        allow_copy;
    wire        frame_ready;
    wire        copy_abort;
    wire        abort_tgl;          // copy_abort 的翻转位（axi 域产生，像素域同步后消费）

    // v6 ATOMIC SWAP: the whole frame is copied inside V-blank ONLY.
    //   V_TOTAL 625 - active 600 = 25 blank lines = 33.5k pix cycles = 67k axi(100M) cycles, and one
    //   frame is 38.4k 64-bit words ⇒ the copy finishes before the first active line is painted, so
    //   the display BRAM holds ONE complete frame during every visible row: no new/old seam (v5's
    //   fixed-position black line came from the copier overtaking the beam mid-frame), no R/W collision.
    localparam [11:0] DISP_V_LINES = 12'd600;   // active lines of 1024x600
    localparam [11:0] DISP_V_LAST  = 12'd624;   // V_TOTAL-1
    localparam [11:0] VB_X_GUARD   = 12'd1279;  // H_TOTAL(1344)-65：早关 64 个消隐像点 —— allow_copy_axi 过 frame_commit_lock 的 CDC 要晚这个窗口约 5 个像素拍
    wire disp_quiet = (y >= DISP_V_LINES)
                      && ((y < DISP_V_LAST) || (x <= VB_X_GUARD));

    wire fill_wr_en;
    wire [18:0] fill_wr_addr;
    wire [63:0] fill_wr_data;
    wire fill_done;
    wire [31:0] fill_araddr;
    wire [7:0]  fill_arlen;
    wire [2:0]  fill_arsize;
    wire [1:0]  fill_arburst;
    wire        fill_arvalid, fill_rready;

    reg  eth_has_frame;

    // 仲裁见 src/rtl/util/src_arb.v。两个输入都是 system_top 在 **axi_clk(fclk0) 域**里取好的 ⇒
    // 这里直接采样，不再跨域；要跨到像素域的是**仲裁结果** owner_eth（下面的 op0/1/2）。
    // 换手只在"两个引擎都空闲"时发生，往 PS 方向再多等 T_OFF（帧间隔卡在阈值上时不会来回抢总线）。
    wire fill_busy;                       // u_aw 的 frame_busy 以前是悬空的，现在是互锁输入
    wire owner_eth;
    wire [2:0] why_ps;                    // V8-7：仲裁判决那一拍看到的三个输入（见 src_arb 端口注释）
    src_arb #(.T_OFF_CYC(2_000_000)) u_arb (   // AXI 域 100 MHz ⇒ 20 ms 静默才让给 PS
        .clk(axi_clk), .rst_n(axi_rst_n), .eth_live(eth_live), .eth_tb_ok(eth_tb_ok),
        .sel(arb_sel),
        .row_busy(row_busy), .fill_busy(fill_busy), .owner_eth(owner_eth),
        .why_ps(why_ps));
    // 名字留着：下面每一处 `eth_mode ? row_* : fill_*` 都是"这一拍搬运机归谁"的意思，只是判据从
    // "收过包"换成了"仲裁过的 owner" ⇒ 这次改动不需要动那 14 处 mux。
    wire eth_mode = owner_eth;

    frame_commit_lock #(.IMG_H(IMG_H), .DISP_H(600)) u_cmt (
        .axi_clk(axi_clk), .axi_rst_n(axi_rst_n),
        .commit_req(eth_commit), .commit_base(eth_ddr_base),
        .pix_clk(clk_pix), .pix_rst_n(rst_pix_n),
        .de(de), .vsync(vs), .blank_safe(disp_quiet),
        .copy_busy(row_busy), .copy_done(row_done),
        .start_copy(row_start), .copy_base(row_base),
        .frame_ready_pix(frame_ready),
        .allow_copy_axi(allow_copy),
        .copy_abort(copy_abort), .abort_tgl(abort_tgl)
    );

    // 板载诊断：拷贝是否超出一个 V-blank 窗口（25 行 × 1344 像素 × 2 axi 拍）。
    // 超出 ⇒ 换帧跨了两个消隐期 ⇒ 屏幕上同一帧的新旧两半并存 ⇒ 运动物体被
    // 一条水平缝「切开」+ 拖影。粘滞到重新加载 bit 为止，用 led[0] 看。
    wire [31:0] row_copy_cycles;
    localparam [31:0] VBLANK_AXI_CYC = 32'd67200;
    reg copy_overrun = 1'b0;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n)      copy_overrun <= 1'b0;
        else if (row_done && (row_copy_cycles > VBLANK_AXI_CYC))
                             copy_overrun <= 1'b1;
    end

    axi_frame_writer_gated #(.IMG_W(IMG_W), .IMG_H(IMG_H), .BASE_ADDR(BASE_ADDR)) u_row (
        .clk(axi_clk), .rst_n(axi_rst_n),
        .enable(eth_mode),
        .start(eth_mode ? row_start : 1'b0),
        .base_addr(row_base),
        .allow_wr(eth_mode ? allow_copy : 1'b0),
        .abort(eth_mode ? copy_abort : 1'b0),
        .busy(row_busy), .done(row_done),
        .fb_wr_en(row_wr_en), .fb_wr_addr(row_wr_addr), .fb_wr_data(row_wr_data),
        .m_axi_araddr(row_araddr), .m_axi_arlen(row_arlen),
        .m_axi_arsize(row_arsize), .m_axi_arburst(row_arburst),
        .m_axi_arvalid(row_arvalid), .m_axi_arready(eth_mode ? m_axi_arready : 1'b0),
        .m_axi_rdata(m_axi_rdata), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(eth_mode ? m_axi_rvalid : 1'b0), .m_axi_rready(row_rready),
        .copy_cycles(row_copy_cycles)
    );

    (* ASYNC_REG = "TRUE" *) reg ss0, ss1, ss2;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) {ss2,ss1,ss0} <= 3'b0;
        else {ss2,ss1,ss0} <= {ss1, ss0, src_sel};
    end
    wire src_sel_pix = ss2;

    // U11（R22）：`eth_link` 是 eth_rxc 域的电平，原来在像素域被**裸采样** 4 处，而同一个文件里
    // `src_sel` 早就走了 3 级同步 —— 一处对一处错。现在统一成 3 级（多 60 ns，对毫秒级的"链路断"不可见）。
    // ⚠ 证据只是**行级**的：`cdc.rpt` 里 `eth_rxc→clkout0_1` 那一行端点数 84→51、被标记 16→1，而这份
    //   报告不点名信号 ⇒ 它只能证明"这一类端点变少了"，逐信号的凭据要写台架（见 R23/tb_v79_abort_toggle）。
    // ⚠ `copy_abort` **不能**照这个模板同步 —— 它是 axi_clk 上只有 1 拍（10 ns）的脉冲，电平型 3 级同步
    //   会整拍漏掉它（比裸采样更糟）⇒ 要的是翻转式脉冲同步器（`abort_tgl`，下面这条链 = 3 级 + 异拍出沿）。
    (* ASYNC_REG = "TRUE" *) reg ab0, ab1, ab2;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) {ab2,ab1,ab0} <= 3'b0;
        else            {ab2,ab1,ab0} <= {ab1, ab0, abort_tgl};
    end
    wire copy_abort_pix = ab1 ^ ab2;   // 每次 abort 恰好一拍

    (* ASYNC_REG = "TRUE" *) reg el0, el1, el2;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) {el2,el1,el0} <= 3'b0;
        else {el2,el1,el0} <= {el1, el0, eth_link};
    end
    wire eth_link_pix = el2;

    // ---- V9-4：屏上那句 "ETH is no signal" 的判据 ----
    // 冻住的最后一帧在屏上**没有任何说法**，看上去就是"板子卡死" ⇒ 把这件事印出来。
    // 判据用 `eth_live`（健康快照 lane7.bit3：200 ms 内真的见过帧）而不是 `eth_link`（那位自配置以来
    // 只置不清、拔线不回 0，正是 #47 的根）；跨域按仓库规矩 3 级同步，与上面 eth_link_pix 同构。
    (* ASYNC_REG = "TRUE" *) reg lv0, lv1, lv2;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) {lv2,lv1,lv0} <= 3'b0;
        else {lv2,lv1,lv0} <= {lv1, lv0, eth_live};
    end
    wire eth_live_pix = lv2;
    // "屏上这一路本该是 ETH _live 却没有"：钉在 ETH 模式，或仲裁此刻把屏交给 ETH。
    // AUTO 模式不判 —— 那时 src_arb 已经把屏交回 PS/图卡，屏上画的就不是冻结的 ETH 帧。
    wire no_sig = (mode_eth | owner_eth_pix) & ~eth_live_pix;

    // 像素域要的是**仲裁结果**而不是第二份判据（判据归 src_arb；这里再复制一份"活着"就会出现
    // "ETH 那一位还在说谎、SD 帧却永远不被消费"的死锁 —— 板上的 STALL 钉在 9999 正是它）。
    //   · ETH 拥有搬运机时 PS 的发布不被消费（pend 留着，等轮到 PS 那一帧再消费），否则 pend 会在
    //     没人搬运的时候被清掉；
    // owner_eth 是 ms 级的慢变量 ⇒ 3 级同步，写法与上面 eth_link_pix 同构。
    (* ASYNC_REG = "TRUE" *) reg op0, op1, op2;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) {op2,op1,op0} <= 3'b0;
        else {op2,op1,op0} <= {op1,op0,owner_eth};
    end
    assign owner_eth_pix = op2;

    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) eth_has_frame <= 1'b0;
        else if (frame_ready && eth_link_pix) eth_has_frame <= 1'b1;
        else if (copy_abort_pix) eth_has_frame <= 1'b0;
    end

    wire [15:0] fb_rd;
    wire eth_ready   = eth_link_pix & eth_has_frame;
    wire src_use     = src_sel_pix;
    assign copy_hold = 1'b0;

    // Hold last pixel only while writer may touch BRAM in blanking.
    // Active video always shows live BRAM (complete frame after copy_done).
    (* ASYNC_REG = "TRUE" *) reg ac0, ac1;
    reg [15:0] fb_pix_hold;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            {ac1,ac0} <= 2'b0;
            fb_pix_hold <= 16'h0;
        end else begin
            {ac1,ac0} <= {ac0, allow_copy};
            if (!ac1) fb_pix_hold <= fb_rd;
        end
    end
    wire [15:0] fb_out = (ac1 && !de_d[11]) ? fb_pix_hold : fb_rd;
    // 这块红"没有片源"的判据往下挪三行 —— 它要用 ps_frame_start，而那是下面才声明的线。

    // 发布握手单独成模块（内含 3 级同步），这样它能被 sim/tb_ps_publish.v 逐相位验。
    // 顺带修掉一处真错：这里原来用 `src_sel`（axi_clk 域的**未同步**电平），
    // 而同文件里 src_sel_pix/src_use 早就存在 —— 帧起始那拍采它会采到亚稳态。
    wire pub_consume = frame_start && src_use && !owner_eth_pix;
    wire pub_pend;
    wire pub_new;                      // PS 刚提交了一帧（同步后的沿）⇒ #94 心跳的唯一来源
                                       //   ⚠ 必须在例化之前声明：端口先引用会造出隐式 net，
                                       //   后面再显式声明就是重定义。
    ps_publish u_pub (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .tog(ps_publish), .consume(pub_consume), .pend(pub_pend), .new_tog(pub_new));

    reg fs_tog;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) fs_tog <= 1'b0;
        else if (pub_consume && pub_pend) fs_tog <= ~fs_tog;
    end
    (* ASYNC_REG = "TRUE" *) reg fs0, fs1, fs2;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) {fs2,fs1,fs0} <= 3'b0;
        else {fs2,fs1,fs0} <= {fs1,fs0,fs_tog};
    end
    wire ps_frame_start = fs1 ^ fs2;

    // ---- #94：片源存在性判据换成**活判据**（`src_life`），不再用两位"只置不清零"的粘滞位 ----
    //   原来这里 `have_src = eth_link_pix | ps_src_seen`，两位都只会被置 1 ⇒ AUTO 下拔掉 SD 卡，画面
    //   **永久冻在最后一帧**、插回也不恢复（`fb_vis` 恒 1，"两路都没片源就画图卡"那条根本进不去）。
    //   判据取自**已有的发布握手**（`ps_publish` 同步出来的 `new_tog`）+ 一条看门狗 ⇒ **不新增 GPIO 位、
    //   不新增异步配对**（`cdc.rpt` 若因此多出一行，就是接错了）。三条语义由 tb_v102_src_life 逐条钉。
    //   `ps_no_pub` 今天只上屏；要做成寄存器回读得走 `zoom_snap` 那条像素→axi 的正路（#85），不在这里塞一根裸线进 axi 口（#61/#65 交过的税）。
    localparam integer PS_SRC_TIMEOUT_MS = 500;
    wire ps_src_now, have_src, ps_no_pub;
    src_life #(.CLK_HZ(50_000_000), .HB_TIMEOUT_MS(PS_SRC_TIMEOUT_MS)) u_life (
        .clk(clk_pix), .rst_n(rst_pix_n), .frame_start(frame_start), .ps_pub(pub_new),
        .eth_owner(owner_eth_pix), .mode_eth(mode_eth), .mode_ps(mode_ps),
        .ps_src_now(ps_src_now), .have_src(have_src), .ps_no_pub(ps_no_pub)
    );
    // 模式决定"看哪一路"：锁 ETH / 锁 SD 强制看 fb，锁 TEST 强制看图卡，AUTO 交回给 PS 的 SRC0/SRC1
    // 命令（src_use），与 #23/#25 一致 —— 本行没改，改的只有它右边 `have_src` 由谁算。
    wire fb_vis   = (mode_card ? 1'b0 : (mode_eth | mode_ps) ? 1'b1 : src_use) && have_src;

    // ---- 仲裁状态可观测口（dbg_src）：位序见文件头端口处那段 ----
    // 为什么把仲裁看得见的所有输入都摆出来：只凭 owner_eth 回答不了"是谁占着"（时基判错？判据算错？
    //   both_idle 没成立？还是长按把模式钉在"锁 ETH"？）—— #28 第一次上板就撞上这个。
    // ⚠ 这些位全部本来就在 axi 域 ⇒ 零新增跨域（#26 那版新加一对像素域 mode 同步器是白交税：cdc.rpt
    //   从 3 端点/0 unsafe 涨到 8/4）。要看模式就取现成的 ms2。
    // ⚠ 新位只往上加：lane30 的老读者（arb_handover_test.mjs / lane30_watch.mjs）按位 0..6 解析，改低 8 位会让它们的判据静默失效。
    assign dbg_src = {5'd0, why_ps, 1'd0, ms2, row_busy, fill_busy, owner_eth, eth_live, eth_tb_ok};

    // ---- V8-6：链路内时延（commit → 该帧开始被扫描），分三段量 ----
    // 显示帧起始在像素域 ⇒ 按仓库规矩先转成**翻转位**再进 axi 域（脉冲跨域会被吃掉，#36 那一课）。
    reg sof_tgl;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) sof_tgl <= 1'b0;
        else if (frame_start) sof_tgl <= ~sof_tgl;
    end

    wire [31:0] lat_c1, lat_c2, lat_tot, lat_max;
    wire [15:0] lat_n;
    // 快照那一组（读回口给出去的就是这六个，见下面的 dbg_lat）
    wire [31:0] lq_c1, lq_c2, lq_tot, lq_max, lq_stat, lq_ms;
    wire        lat_clamp;
    // V8-5：axi 域那一口的四个声明（必须在例化之前声明，否则端口先造出隐式 net，后面再显式声明就是重定义）
    wire [15:0] lat_ms_axi;
    wire        lat_ok_axi, lat_sticky_axi, lat_tog_axi;
    // **PL 里不做除法**：r49 在这里把拍数除以 100 换 µs，除数不是 2 的幂 ⇒ 综合架出组合除法器，
    // 100 MHz 域直接 WNS −5.014 / 96 个失败端点（见 ISSUES #58）。现在只报拍数，换算在
    // src/host/health_read.mjs 的一个常量里做（1 拍 = 10 ns）。
    frame_latency u_lat (
        .axi_clk(axi_clk), .axi_rst_n(axi_rst_n),
        .commit(eth_commit), .copy_start(row_start), .copy_done(row_done),
        .disp_sof_tgl(sof_tgl), .arm(lat_arm),
        .c1_cyc(lat_c1), .c2_cyc(lat_c2), .tot_cyc(lat_tot), .max_cyc(lat_max),
        .n_meas(lat_n), .clamped(lat_clamp),
        .q_c1(lq_c1), .q_c2(lq_c2), .q_tot(lq_tot), .q_max(lq_max), .q_stat(lq_stat),
        // V8-5：axi 域换算好的 ms（逐次除法，见 frame_latency 里那段注释）
        .lat_ms(lat_ms_axi), .lat_valid(lat_ok_axi),
        .lat_sticky(lat_sticky_axi), .lat_tog(lat_tog_axi),
        .q_ms(lq_ms)
    );
    // 六个字，lane 号 = 25 + 序号（system_top 的 mux 按这个式子取）：
    //   lane29=c1（commit→start_copy，等消隐窗口）lane28=c2（start_copy→copy_done，整帧搬运）
    //   lane27=tot（c3 = tot−c1−c2，不单独占一口）lane26=max（演示念这个）lane25={n_meas,clamped} lane24=q_ms
    // ⚠ 这一行给出去的是 **q_*（快照）** 不是 live 的 lat_*：live 每轮都在换，逐 lane 各读各的会读到
    //   不同轮（#59）；live 的 lat_* 仍接在台架上（tb_v90 逐周期对账）。ms 塞进同一次武装的快照，是因为
    //   屏上 `Latency:` 画的就是它、而"屏上与回读必须同源"⇒ 只有**同一轮**的 (q_tot,q_ms) 能互验。
    assign dbg_lat = { lq_ms, lq_c1, lq_c2, lq_tot, lq_max, lq_stat };

    // ================= V8-8 最后一跳（lane23）：像素域真正在用的缩放状态 =================
    // 为什么寄存器回读不算数：GPIO 读回来的 zsel/zman 只能证明**PS 写了这一位**，证明不了 13 级 sel
    // 链把它送到了像素域、更证明不了据此算出的 inv_scale 是对的 ⇒ 这一口摆出因果链的**末端**，于是
    //   ① PS 写 zsel=i ⇒ 像素域 inv_scale == TBL[i]；② 屏上 `Zoom:` 那格与同一帧在用的 inv 同档
    //   （PLAN 步 5 的"屏上与回读同源"要求，与 lane24 对照 `Latency:` 是同一手法）。
    // 跨法：总线只在**帧首**变（准静态），发沿在捕获之后再推迟 8 个像素周期 ⇒ 目的域采到的必是完整值；规矩单独成模块 `zoom_snap.v`（tb_v95 逐周期验它的两条不变量），对照是"19 位各自打两拍 ⇒ 读到半新一半旧"（#52/#59）。
    wire [18:0] z_bus;
    wire        z_bus_tog;
    zoom_snap u_zsnap (
        .pix_clk(clk_pix), .pix_rst_n(rst_pix_n), .frame_start(frame_start),
        .zman(zman_pix), .zsel(zsel_pix), .zoom_code(zoom_code),
        .zoom_active(zoom_active), .zoom_dir(zoom_dir), .inv_scale(inv_used),
        .bus(z_bus), .bus_tog(z_bus_tog));
    wire [18:0] z_bus_axi;
    wire        z_pix_gone;
    // 心跳**单独一个触发器**，不共用现成的 sof_tgl —— 这不是洁癖：r54 第一次构建里就是共用了它，于是
    // 那一个发射触发器同时扇出到两组目的域同步器（u_lat 与 u_zoom_axi），cdc.rpt 立刻把整对
    // `clkout0_1 → clk_fpga_0` 提成 **CDC-11 Critical**、门禁第 6 项判红。一个 FF 换回"配对集合不新增
    // Critical 行"，语义一模一样（每个显示帧翻一次）。
    reg z_hb_tog;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) z_hb_tog <= 1'b0;
        else if (frame_start) z_hb_tog <= ~z_hb_tog;
    end
    // 心跳 = 每帧一次 ⇒ hb_gone 的含义是"200 ms 没等到帧起始"
    // = 像素时基停了，这时 bus_q 里的数还是上一个的，必须让脚本知道它旧。
    // SLOW_MS 这一档**不接出去**：模块里那个 5 ms 的门限是给 1 ms 心跳（eth_rxc）定的，
    // 帧心跳本来就是 16.7 ms，硬接只会常亮一位没意义的慢标志。
    snap_cross #(.W(19), .DST_HZ(100_000_000), .HB_TO_MS(200)) u_zoom_axi (
        .dst_clk(axi_clk), .dst_rst_n(axi_rst_n),
        .bus(z_bus), .bus_tog(z_bus_tog), .hb_tog(z_hb_tog),
        .bus_q(z_bus_axi), .hb_gone(z_pix_gone), .hb_slow()
    );
    // 位序（**唯一出处**，改这里要同步改 health_read.mjs 的 decodeZoom 与门禁反例）：
    //   bit31 = 像素时基活着（0 ⇒ 下面 19 位是旧的）  **bit19 = zoom_fit**（V9-2：1 ⇒ inv 由角度定、
    //   不再等于八档表里的哪一档）  bit[18]=zman [17:15]=zsel [14:12]=zoom_code [11]=zoom_active
    //   [10]=zoom_dir [9:0]=inv_used；bit[30:20]=0 留扩展（#84/#85：像素域的信号不许直接塞进这个 axi 口）
    // ⚠ bit19 必须有：判据①在拟合模式下**按构造就不成立**，没有它脚本会把一次正常拟合读成档位错乱 ——
    //   那是"尺子先错"（#68）不是设计错。它取 `split_ctl[18]`（axi 域那份请求位）而**不是**像素域副本 `zoom_fit_en` ⇒ 零新增跨域。
    assign dbg_zoom = {~z_pix_gone, 11'd0, split_ctl[18], z_bus_axi};

    assign m_axi_arid = 6'd0;

    axi_frame_writer64 #(
        .IMG_W(IMG_W), .IMG_H(IMG_H), .BASE_ADDR(PS_BASE_ADDR)
    ) u_aw (
        .clk(axi_clk), .rst_n(axi_rst_n),
        .enable(eth_mode ? 1'b0 : src_sel),
        .frame_start(eth_mode ? 1'b0 : ps_frame_start),
        .base_addr(PS_BASE_ADDR),
        .frame_busy(fill_busy), .frame_done(fill_done),
        .fb_wr_en(fill_wr_en), .fb_wr_addr(fill_wr_addr), .fb_wr_data(fill_wr_data),
        .m_axi_araddr(fill_araddr), .m_axi_arlen(fill_arlen),
        .m_axi_arsize(fill_arsize), .m_axi_arburst(fill_arburst),
        .m_axi_arvalid(fill_arvalid), .m_axi_arready(eth_mode ? 1'b0 : m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(eth_mode ? 1'b0 : m_axi_rvalid), .m_axi_rready(fill_rready),
        .copy_cycles()
    );

    assign m_axi_araddr  = eth_mode ? row_araddr  : fill_araddr;
    assign m_axi_arlen   = eth_mode ? row_arlen   : fill_arlen;
    assign m_axi_arsize  = eth_mode ? row_arsize  : fill_arsize;
    assign m_axi_arburst = eth_mode ? row_arburst : fill_arburst;
    assign m_axi_arvalid = eth_mode ? row_arvalid : fill_arvalid;
    assign m_axi_rready  = eth_mode ? row_rready  : fill_rready;

    wire        aw_wr_en   = eth_mode ? row_wr_en   : fill_wr_en;
    wire [18:0] aw_wr_addr = eth_mode ? row_wr_addr : fill_wr_addr;
    wire [63:0] aw_wr_data = eth_mode ? row_wr_data : fill_wr_data;

    // 一个读口、一条地址流、一份坐标（#73）：这里从此没有"左用哪套源坐标 / 右用哪套"的 mux。
    // ---- r63 / #52：显示侧读口换成 `fb_bilin`（双线性，每源像素用满它天然的 4 个 50 MHz 拍）----
    //   对外形状与旧的"rd_addr_q + frame_buffer_w64"逐位同深（请求 → 2 拍到数据），所以
    //   `MIX_D = 3 + 1 + 1 + LATENCY` 的两个 `1` 原样成立 ⇒ 混色级、skid、SEAM_TAPS 全不动。
    //   唯一额外的代价是**行方向晚一整对显示行**（乒乓缓冲：一对的结果在那对的第二行才算得出），
    //   由上面 `y_right_adv` 的 `BILIN_ROWS` 补偿掉 ⇒ 见那条线旁边的注释。
    wire [11:0] sx_fb = sx;
    wire [11:0] sy_fb = sy;

    // `fb_rd` / `oob_fb_d1` 沿用旧名字（上面声明），下面 fb_pix_hold / fb_out / pix_raw 那一串因此
    // 一个都不动 —— 换的只是"这两个信号由谁驱动"。
    wire        oob_fb_d1;
    fb_bilin #(
        .IMG_W(IMG_W), .IMG_H(IMG_H)
    ) u_bilin (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .wr_clk(axi_clk), .wr_en(aw_wr_en), .wr_addr(aw_wr_addr), .wr_data(aw_wr_data),
        .sx(sx_fb), .sy(sy_fb), .fx(zfrac_x), .fy(zfrac_y),
        .bilin_en(bilin_en_pix),
        // ⚠ 相位量必须与 `sx/sy` **同一级**，而"哪一级"是量出来的不是推出来的：tb_v98 自带的级数标定
        //   （`sx` vs 第 k 级显示列 >>1，样本 822555）给 k=0 全错｜k=1 412166｜**k=2 0**｜k=3 410389｜
        //   k=4/5 全错 ⇒ sx 站在第 2 级。第一版这里接的是 [3]（照 "MIX_D = 3+1+1+LATENCY" 的那个 3）
        //   ⇒ 地址与列奇偶错一拍 ⇒ "每源像素的 4 拍"跨到相邻源像素，屏上四分之一格子错列（C1c 的 Δcol）。
        //   行方向同结论：C1h 用 y_d[2] + OFF + BILIN_ROWS 判绿。
        .col0(~x_d[2][0]), .row0(~y_d[2][0]), .pair_odd(y_d[2][1]),
        // 暂存/结果缓冲的索引必须是**显示列对号**，不是源列 `sx`：旋转时 sx 沿一行会停滞/倒退，
        // 用 sx 当地址会让同一个格子被别的源行重写 ⇒ 满屏噪点（2026-09-26 用户报，见 fb_bilin 头）。
        .jd(x_d[2][9:1]),
        .req_vld(de_d[2]), .oob_in(oob),
        .pix(fb_rd), .oob_out(oob_fb_d1)
    );

    // SRC0 位置原来是静止彩条（`color_bar`），换成**会动的测试图卡**：静止图案分不清"通路在刷新"和
    //   "卡在最后一帧"，这张卡自带移动块 + 帧号二值格（见 test_card.v 文件头）。端口与 color_bar 同形、
    //   输出同样只打一拍 ⇒ PROC_LAT 与那些抽头不用动。
    //   图卡也只剩一份并且吃同一份源坐标 (sx,sy)：旧代码 u_bar_l 吃 cx/cy、u_bar_r 吃 mapper 输出，
    //   正是"两屏各画一整幅"的另一半遗产。
    wire [15:0] bar0;
    reg  [15:0] bar_d1, bar_d2;
    test_card #(.H_ACTIVE(IMG_W), .V_ACTIVE(IMG_H)) u_bar (
        .clk(clk_pix), .rst_n(rst_pix_n), .vs(vs),
        .x(sx), .y(sy), .de(de_d[2]), .rgb565(bar0)
    );
    always @(posedge clk_pix) begin
        bar_d1 <= bar0; bar_d2 <= bar_d1;
    end

    // oob_fb_d1 现在是 `u_bilin` 从结果缓冲里带出来的那一位（与像素同一次写、同一拍读 ⇒ 天生同级）。

    // 第 5 级"这一格该显示什么"：有片源取帧缓存，没片源取会动的图卡，越界给黑。
    //   旧版这里是一对 pix_left/pix_right（各按半窗把自己那一侧以外强制清零）—— 那对 mux 就是 #68 那条
    //   暗带的另一半（标签与内容不同级时被清零的一路会在缝旁留一条带）；现在只有一个流 ⇒ 那一族结构上消失。
    wire [15:0] pix_raw = oob_fb_d1 ? 16'h0000 : (fb_vis ? fb_out : bar_d2);
    wire        oob_raw = oob_fb_d1;

    // ---- r59b-2（#73）：原图抽头必须过一条**行环**，缝两侧才是同一行画面 ----
    //   单流之后地址只有一份，而它的行号带着 #54 (B) 的提前量 `cy_r = (y+OFF_LINES)>>1` —— 那个提前量是
    //   给链子准备的（链子内容天生滞后 4 行），原图抽头不需要它。补偿不是再开一个读口（第二个逻辑读口
    //   实测把 80 块 BRAM 顶到 160 块，全片才 140），而是把原图抽头整体延后 OFF_LINES 个显示行：
    //     第 r 行写进去的内容是源行 (r+OFF)>>1，第 r+OFF 行读出来 ⇒ 落在显示行 r+OFF 上，而那一行要的正是它
    //     —— 列号由环按 x 寻址，一格都不偏。LINES 的唯一合法出处是 u_pipe.OFF_LINES（链子改了这条跟着改）。
    localparam integer RAW_LINES = u_pipe.OFF_LINES;
    // #92 第三笔：**越界标签与像素打包过同一条环**。以前 `pix_raw` 过环（4 行 + 1 拍）而
    //   `oob_raw` 绕开环只走等长 skid ⇒ 到混色级时两者差 (4 行, 1 列)：画面右沿最后一列被
    //   "别的格子"的越界位按黑，上下边界的越界位来自别的行（屏上=上边缘有东西闪）。
    //   17 位仍在 RAMB36 的 18 位宽度模式里 ⇒ BRAM 一块不多要（这句要在 utilization.rpt 上核，不许停在注释）。
    wire [16:0] raw_ring;
    wire        raw_ring_v;
    raw_line_delay #(.LINES(RAW_LINES), .W(2*IMG_W), .DW(17)) u_raw (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .de(de_d[5]), .x(x_d[5]), .y(y_d[5]),
        .d_in({oob_raw, pix_raw}), .d_out(raw_ring), .de_out(raw_ring_v)
    );

    wire [15:0] pipe_dout;
    wire        pipe_de;
    // #73：链子现在的"一行"是显示列 1024（相邻两拍内容是同一个源列的复制）。
    //   代价写死在这里，不许算作免费：行缓存宽度翻倍（约 +8 块 BRAM），而且 3x3 滤波的空间尺度
    //   从"源像素"变成"显示像素"（横向覆盖 1.5 个源列）⇒ 横方向的模糊/边缘比旧版略宽。
    //   要回到源域等距就得给整条链加时钟使能（#73 订正里那条支路）。
    proc_pipeline #(.H_ACTIVE(2*IMG_W)) u_pipe (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .stage_sel(sel_sync), .threshold(th_sync),
        .gamma_en(gm_en), .gamma_wr(gm_wr), .gamma_idx(gm_idx), .gamma_data(gm_data),
        .rotate_active(rot_on),
        .hs_in(hs_d[3]), .vs_in(vs_d[3]),
        .de_in(de_d[3]),                 // 整行都进链（旧版只喂右窗那 512 个）
        .x_in(x_d[3]), .y_in(cy_d[3]),   // 链子里的"列"= 显示列，"行"= 源行（两个显示行同名，照旧）
        .din(pix_raw), .off_rows(pipe_off_rows),
        .de_out(pipe_de), .dout(pipe_dout)
    );

    // 处理链的延迟**只有一处定义**：proc_pipeline 自己的 LATENCY。
    // 以前这里是字面量 7，于是"链上加一级"必须同时记得改这里 —— 忘了不是编译错，
    // 而是左窗（原始画面）与右窗（处理后）错开 N 个像素。左窗的 skid 长度直接取 u_pipe 的值，
    // 而 tb_v86 的 T2 实测 de_in→de_out 与 LATENCY 对账 ⇒ 两处任一处漂移就有测试可红。
    localparam PROC_LAT = u_pipe.LATENCY;
    localparam LEFT_TAIL = PROC_LAT;

    // ---- #92 第一笔：两个抽头必须**同深**，否则缝上错开一整列 ----
    //   原图那一路 = `raw_line_delay`(1 拍 RAM 读出) + `orig_skid`(PROC_LAT 拍) = **PROC_LAT+1 拍**，而链子
    //   自己只有 PROC_LAT 拍 ⇒ 处理抽头比原图抽头**早一整拍** = 混色级早一整列。1.00x 时画面铺满整屏看不出
    //   来；一缩小，左边界就把"画面自己最左那一列"甩进背景带、右边界少一列 —— 用户念的"贴在边上的一条线"
    //   这一笔占一列。凭据 tb_v98：C1c 独立钉住"原图抽头与 `x_d[MIX_D]` 同级"⇒ 要动的是链子这一路；
    //   C2 在 inv=512 与 inv=1023 两档都量到"内容左右沿 = 定义左右沿 − 1"（**恒为一列、不随倍率变** ⇒ 是整拍之差，不是取整偏差）。
    reg [15:0] pipe_dout_q;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) pipe_dout_q <= 16'h0000;
        else            pipe_dout_q <= pipe_dout;
    end

    reg [15:0] orig_skid [0:LEFT_TAIL-1];
    reg        oob_skid [0:LEFT_TAIL-1];
    integer s;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            for (s = 0; s < LEFT_TAIL; s = s + 1) begin
                orig_skid[s] <= 0; oob_skid[s] <= 0;
            end
        end else begin
            orig_skid[0] <= raw_ring[15:0];   // 行环之后再做 15 拍 skid：行与列都才对得上（#73）
            oob_skid[0]  <= raw_ring[16];     // #92：标签与像素过**同一条环** ⇒ 到这一拍仍然配好对
            for (s = 1; s < LEFT_TAIL; s = s + 1) begin
                orig_skid[s] <= orig_skid[s-1];
                oob_skid[s]  <= oob_skid[s-1];
            end
        end
    end
    wire [15:0] orig_disp = orig_skid[LEFT_TAIL-1];   // 链子之前的抽头，与 pipe_dout 同一级
    wire        oob_out   = oob_skid[LEFT_TAIL-1];

    wire de_d11 = de_d[11], hs_d11 = hs_d[11], vs_d11 = vs_d[11];
    wire [11:0] x_d11 = x_d[11], y_d11 = y_d[11];

    wire [7:0] r, g, b;
    wire de_o, hs_o, vs_o;

    // ---- #51：分割线的执行者 ----
    //   控制位在 axi 域每 ~1.3 ms 整拍抄一次并翻 toggle；目的域等 3 级同步之后才采总线
    //   ⇒ 采到的永远是完整值（snap_cross 文件头那条契约）。心跳就用这个刷新沿：
    //   axi 时钟要是停了，bus_q 里的缝位还是旧的 —— 这里不接慢/停标志，因为缝位晚一帧
    //   生效的代价只是"下一格才跳"，不是数据错。
    reg  [18:0] sp_bus;
    reg         sp_tog;
    reg  [16:0] sp_ref;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            sp_bus <= 19'd0; sp_tog <= 1'b0; sp_ref <= 17'd0;
        end else if (sp_ref == 17'h1FFFF) begin
            sp_ref <= 17'd0;
            sp_bus <= split_ctl;
            sp_tog <= ~sp_tog;
        end else begin
            sp_ref <= sp_ref + 17'd1;
        end
    end
    snap_cross #(.W(19), .DST_HZ(50_000_000), .HB_TO_MS(200)) u_split_x (
        .dst_clk(clk_pix), .dst_rst_n(rst_pix_n),
        .bus(sp_bus), .bus_tog(sp_tog), .hb_tog(sp_tog),
        .bus_q(gp), .hb_gone(), .hb_slow()
    );

    wire [11:0] split_eff;
    wire        split_raw_left;
    wire [11:0] split_pct_w;
    split_ctrl #(.DISP_W(2*PANE_W), .SRC_W(IMG_W), .TICK_BITS(16)) u_split_ctrl (
        .clk(clk_pix), .rst_n(rst_pix_n), .de(de),
        .pos_px({2'd0, gp[9:0]}),
        .auto_en(gp[10]), .follow(gp[11]),
        .speed(SPLIT_SPEED), .lo16(SPLIT_LO16), .hi16(SPLIT_HI16), .swap(gp[12]),
        .split_eff(split_eff), .raw_on_left(split_raw_left), .shown_pct(split_pct_w)
    );
    // 标记线：gp[13]=1 才是"关" ⇒ 复位/PS 没写过时屏上仍有那条 2 px 蓝线，
    //   与 r59a 的观感口径一致（board/README.md 第 12 行说的就是"故意画的"）。
    wire split_marker_on = ~gp[13];

    // ---- V9-1：缝可以量在图像列里，于是那条线跟着画面一起转 ----
    //   `gp[11]`（follow）今天同时管两件事：`split_ctrl` 的扫描坐标系（端点按画面的两端量）与下面这一路
    //   的判据空间（线长在画面里）。以前它只管前者，所以"follow"名不副实。
    //   ⚠ TAPS 由流水线深度推出来，不抄字面量（#68）：内容站在 `x_d[MIX_D]` 那一拍，而 `sx` 是 mapper 的
    //   第 3 级输出 ⇒ 从 sx 到混色级要走 MIX_D+1−3 拍。差几拍在这里只是把整条线刚体平移几列，**不会**再
    //   产生暗带（暗带的根因是"标签与内容不是同一份流"，这里两者是同一份流上的同一个位）。
    localparam integer SEAM_TAPS = MIX_D + 1 - 3;
    wire seam_src_orig, seam_src_mark;
    seam_src #(.TAPS(SEAM_TAPS)) u_seam_src (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .sx(sx), .oob(oob), .seam(split_eff),
        .marker_on(split_marker_on), .raw_left(split_raw_left),
        .take_orig(seam_src_orig), .mark(seam_src_mark)
    );

    split_display u_split (
        .clk(clk_pix), .rst_n(rst_pix_n),
        // #92 第二笔：整束标签必须与**像素同一级**。r59b 修 #68 时只把"选哪一路"的 `x_sel` 提到 `MIX_D`，
        //   而 `x/y/de/hs/vs` 留在第 11 级 ⇒ 面板上的 `de` 比同一拍的像素早 9 列（MIX_D − 11）：屏上最左
        //   9 列画的是**上一行末尾那 9 格**（= 用户念的"贴在屏幕左边缘的一条线"），最右 9 列落进消隐丢掉
        //   （对着黑底看不见），而 OSD 一格都不动（它的 x/y 与 de 同源、跟着一起错）—— 三条观察同一件事。
        //   凭据 tb_v98 的 C3：面板坐标系**只用输出引脚**建立、不引用任何内部标签，改前量到"画面左右沿 =
        //   定义 +8 列"（= 本笔 +9 与上一笔 −1 之和）且带宽不变 ⇒ 整幅平移不是尺寸错；C3a 排除"消隐窗口不匹配"。
        .x(x_d[MIX_D]), .y(y_d[MIX_D]), .de(de_d[MIX_D]), .hs(hs_d[MIX_D]), .vs(vs_d[MIX_D]),
        .x_sel(x_d[MIX_D]), .marker(split_marker_on),
        .seam(split_eff), .raw_left(split_raw_left),   // 与内容同级的那一路坐标（#68）；OSD 用的 x/y 不动
        .seam_in_src(gp[11]), .src_orig(seam_src_orig), .src_mark(seam_src_mark),
        .orig_pix(orig_disp), .proc_pix(pipe_dout_q),
        .oob_l(oob_out), .oob_r(oob_out),   // 越界对两个抽头是同一件事（同一份源坐标）⇒ 一位喂两口
        .angle_idx(angle[1:0]),
        .r(r), .g(g), .b(b),
        .de_out(de_o), .hs_out(hs_o), .vs_out(vs_o)
    );

    reg vs_pix_d0, vs_pix_d1;
    always @(posedge clk_pix) begin
        vs_pix_d0 <= vs_d11; vs_pix_d1 <= vs_pix_d0;
    end
    wire vs_tick = vs_pix_d0 & ~vs_pix_d1;
    reg [31:0] fps_acc;
    reg [25:0] sec_div;
    reg [7:0]  fps_q;
    (* ASYNC_REG = "TRUE" *) reg vt0, vt1, vt2;
    always @(posedge sys_clk) {vt2,vt1,vt0} <= {vt1,vt0,vs_tick};
    wire vs_sys = vt1 & ~vt2;
    always @(posedge sys_clk or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            sec_div <= 0; fps_acc <= 0; fps_q <= 0;
        end else if (sec_div == 26'd49_999_999) begin
            sec_div <= 0; fps_q <= fps_acc[7:0]; fps_acc <= 0;
        end else begin
            sec_div <= sec_div + 1'b1;
            if (vs_sys) fps_acc <= fps_acc + 1'b1;
        end
    end

    // （r55）这里原来有一段把 16 位 `eth_pkts` 用两级触发器同步的代码：两级触发器只能跨**单 bit**，
    // 跨总线会读到"每一位各自新旧不一"的中间态，而它同步出来的东西又没有读者 ⇒ 整段删除。数没有丢：
    // pkts/bytes/bad 由 link_monitor 经 snap_cross 正确跨域，走 lane1/8/9。见 ISSUES #64。

    // v7.6 曾把 320 bit 健康快照跨进像素域给 OSD 的 DROP/STALL 两格用；V8-5 把那两格撤下屏之后这一路
    // **没有消费者**了，于是那条 snap_cross（u_lm_x）连同 lm_bus/lm_bus_tog/lm_hb 三个输入口一起删掉：
    // 留着它就是一根"没人读的线"（本项目为这类线付过两次学费：#57 的位宽、#61 的多驱动）。
    // **功能没有删**：lane0~lane9 在 axi 域由 `src/host/health_read.mjs` 机器可读（system_top 里那条
    // snap_cross 是给读回口用的，与本段无关，仍然存在）；"链路断了"在屏上有三个长相：Src 退回 CARD、
    // FPS 掉到 0、Latency 变 `--`。

    // ---- V8-5：把 axi 域算好的 ms 跨到像素域（#36/#52 那一课：翻转位 + 3 级同步 + 整拍锁存）----
    // hb_tog 与 bus_tog 是**同一件事**：**没有新测量**就等于"心跳停了" ⇒ hb_gone 亮 ⇒ OSD 画 `--`，于是
    // "ETH 停了、屏上还挂着最后一轮的 12 ms"这种过期读数不可能出现。门限取 1000 ms（一轮正常是一帧
    // 16~33 ms，留 30 倍余量），SLOW_MS=200 ⇒ 只有时基真的废了才判 slow，不会把正常的帧间抖动当成断。
    // 总线里带两位状态：lat_valid（这一轮算完了）与 ~lat_sticky（这一轮配对干净）—— 少了后一位，一次
    // "倒挂/超长"的轮次就会把一个假 ms 画上屏，那正是 #59 要防的那类谎。
    wire [17:0] lat_bus_q;
    wire        lat_gone;
    // 心跳**另起一个触发器**：语义仍然是"和发沿同一件事"（同域打一拍，对 1000 ms 的门限什么都不意味着），
    // 但 `lat_tog_axi` 不再同时扇出到 bus_tog 与 hb_tog 两组目的域同步器 —— r55 的 cdc.rpt 里这一对
    // `clk_fpga_0 → clkout0_1` 有 3 个 unsafe 端点，其中 2 个就是这里（CDC-11），与 r54 构建 #34 同一个
    // 签名、同一个修法（见上面 `z_hb_tog` 那段）。
    reg lat_hb_tog;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) lat_hb_tog <= 1'b0;
        else            lat_hb_tog <= lat_tog_axi;
    end
    snap_cross #(.W(18), .DST_HZ(50_000_000), .HB_TO_MS(1000), .SLOW_MS(200)) u_lat_x (
        .dst_clk(clk_pix), .dst_rst_n(rst_pix_n),
        .bus({lat_ok_axi, ~lat_sticky_axi, lat_ms_axi}),
        .bus_tog(lat_tog_axi), .hb_tog(lat_hb_tog),
        .bus_q(lat_bus_q), .hb_gone(lat_gone), .hb_slow()
    );
    wire        lat_ok_pix = lat_bus_q[17] & lat_bus_q[16] & ~lat_gone;
    wire [15:0] lat_ms_pix = lat_bus_q[15:0];


    // ---- Split 那一格由 split_ctrl 的 shown_pct 真驱动（缝的执行者见 ISSUES #62 / split_ctrl 文件头）----
    // 除法是 elaboration 常数（PANE_W 等是参数），综合折成一个数、不留硬件；以前这一格是个死数
    // SPLIT_PCT_FIX，死数与它的推导注释一起删掉了 —— 留着就是"两处各说一遍"，正是 #66 那一族的病。

    wire [7:0] r_osd, g_osd, b_osd;
    wire de_osd, hs_osd, vs_osd;
    // #67：OSD 第一行那格从"片源 512×300"换成**面板 1024×600**，所以递进去的是面板那一份。
    // ×2 这条关系在本文件里只有一个出处（`proc_pipeline.H_ACTIVE`、`raw_line_delay.W` 用的也是它），
    // 不是在这儿另抄一遍 1024/600 —— 谁改了窗口展开的倍数，屏上那格就跟着改。
    osd_overlay #(.OUT_W(2*IMG_W), .OUT_H(2*IMG_H)) u_osd (
        .clk(clk_pix), .rst_n(rst_pix_n),
        // #92：跟着上面那一束一起提到 `MIX_D`。它与 `de_o` 的相对关系**一格都不变**
        //   （`de_o` 是 `de_d[MIX_D]` 再打一拍，这里的 `x/y` 就是同一拍的值 ⇒ 仍是"早一拍"，
        //   与改前 `x_d11` vs `de_d11+1` 完全同形）⇒ OSD 在屏上的位置一个像素都不动，
        //   动的只有"画面 vs 面板有效窗口"那一笔（上面 C3 那条）。
        .x(x_d[MIX_D]), .y(y_d[MIX_D]), .de(de_o),
        .angle(angle), .fps(fps_q),
        .stage_sel(sel_sync),                 // 五级链实际生效的九位
        .threshold(th_sync),
        .gamma_disp(gm_disp),
        .zoom_code(zoom_code), .zoom_auto(zoom_run && !zman_pix && !zoom_fit_en),   // V8-8：手动档不许再标 (Auto)
        .zoom_fit(zoom_fit_en),                    // V9-2：倍率由角度定 ⇒ 标 (Fit)
        .split_pct(split_pct_w[7:0]), .split_auto(gp[10]),
        .lat_ms(lat_ms_pix), .lat_ok(lat_ok_pix),
        .src_eff({fb_vis, owner_eth_pix}),   // 屏幕上真的这一路：CARD / PS / ETH
        .mode(mode),
        .no_sig(no_sig),                     // V9-4：屏上印 "ETH is no signal"
        .temp_disp(tmp_disp),                // V9-6：片上温度那一格（L4 常驻）
        .bg_pix(16'h0),
        .osd_en(osd_en),                // r83：0 = 输出逐位等于背景（见 osd_overlay 端口注释）
        .r_in(r), .g_in(g), .b_in(b),
        .hs_in(hs_o), .vs_in(vs_o),
        .r(r_osd), .g(g_osd), .b(b_osd),
        .de_out(de_osd), .hs_out(hs_osd), .vs_out(vs_osd)
    );

    rgb2dvi u_dvi (
        .clk_pix(clk_pix), .clk_pix5x(clk_pix5x), .rst_n(rst_pix_n),
        .r(r_osd), .g(g_osd), .b(b_osd),
        .hs(hs_osd), .vs(vs_osd), .de(de_osd),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n)
    );

    reg [24:0] hb;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) hb <= 0; else hb <= hb + 1'b1;
    end
    // led[0]: 正常 = 1.5Hz 心跳；一旦发生过「拷贝超出一个 V-blank 窗口」= 6Hz 快闪
    assign led[0] = copy_overrun ? hb[22] : hb[24];
    // led[1]：按下的过程里亮（0.2 s 后 = '我在计时'），松开后停在 ltog 上 —— 每成功一次长按它必翻转一次。
    // 原来这里挂的是 src_use，但屏幕 OSD 已经有片源行，LED 挂一个"看得见有没有生效"的东西更有用。
    assign led[1] = k1_hold ? 1'b1 : ltog;

    // `inv_used` 而不是 `inv_scale`：这一口是给 JTAG 侧"屏上到底是什么倍率"用的，
    // 拟合模式下前者才是答案（非拟合模式下两者同一个数 ⇒ 老脚本读法不受影响）。
    assign status = {zoom_dir, zoom_active, inv_used, eth_ready, locked, rotate_active,
                     angle, 5'b0 /* 原 en_sync：随 #66 五位控制一起退役，位保留填 0（与
                                  * gpio_o[4:0] 同样处理：不重排，JTAG 侧的读法就不会错位） */,
                     src_use, 2'b00};
endmodule
