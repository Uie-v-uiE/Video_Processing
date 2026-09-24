`timescale 1ns/1ps
// 片源仲裁：DDR→帧缓存 这一台搬运机，到底归 ETH 引擎还是归 PS(SD/FILL) 引擎。
//
// 为什么要单独成模块：这件事的正确答案**不是**"哪边有数据"，而是"哪边活着 + 现在能不能安全换手"。
// 老写法是 `eth_mode = 3FF(|s_pkts)`，两个问题叠在一起：
//   ① |s_pkts 是"自配置以来收到过任何一个包"——PC 的 ARP 就够触发，且**拔网线也不会回 0**，
//      于是 PS 片源被永久锁死（ISSUES #47 修的是它在显示端的表现，这里修的是它的根）；
//   ② 就算换成"最近有包"，两个引擎共用同一个 AXI 读口 + 同一个 BRAM 写口，选择位在
//      一次拷贝**中途**翻转会留下半开的读突发：老代码里唯一的"互锁"就是那一个选择位本身。
// 所以这里把两件事分开：
//   · "活着"由 link_monitor 用 stall_ms 判（eth_rxc 域，本来就是它的活）；
//   · 但这个"活着"必须**先确认量它的时钟还算准**才可以用：板级实测（2026-09-23）断链时
//     RTL8211 不停 RXC 而是把它拉到 ≈2.5 MHz，stall_ms 于是以约 1/48 的速度爬，
//     `stall_ms < 200` 会连着骗人十几秒 ⇒ 仲裁死占 ETH、SD 接不回画面。
//     这一条判据就落在本模块（原来在 system_top 里是一个裸与门，没有任何台架能验到它）。
//   · "换手"只在两个引擎都空闲时发生，且往 PS 方向带一段静默等待（滞回），
//     免得帧间隔刚好卡在阈值上时来回抢总线。
module src_arb #(
    // eth 静默多少拍才把总线让给 PS。AXI 域 100 MHz ⇒ 2_000_000 = 20 ms。
    // 注意这是**第二级**滞回：第一级是 stall_ms > LIVE_MS（默认 200 ms）。
    parameter integer T_OFF_CYC = 2_000_000
)(
    input  wire clk,          // axi_clk：两个引擎都在这个域
    input  wire rst_n,
    input  wire eth_live,     // 已在本域同步好的电平（慢变量，ms 级）
    input  wire eth_tb_ok,    // 量 eth_live 的那个源时基仍然准（0=被拉慢或停掉 ⇒ 不信 eth_live）
    input  wire [1:0] sel,    // 00=AUTO 01=锁ETH 10=锁PS 11=按 AUTO 处理（图卡模式不改仲裁）
    input  wire row_busy,     // ETH 引擎（axi_frame_writer_gated）正在拷贝
    input  wire fill_busy,    // PS 引擎（axi_frame_writer64）正在拷贝
    output reg  owner_eth,    // 1 = AXI 读口与帧缓存写口归 ETH 引擎
    // V8-7：PS 拿着屏幕**为什么**拿着 —— 三个输入在**判决同一个时钟沿**上的快照。
    // 为什么只要"寄存"、不许在这里再算一遍：屏上/上位机看到的"原因"必须与主人是同一份输入产生的，
    // 否则就是 #55 那一类"两个地方各说一套"（那次是 CARD/PS 标签反了）。
    // 位序固定为 `{force_ps, ~eth_live, ~eth_tb_ok}`：
    //   [2]=1 被人用 `src 1` 钉住了（不是故障）；[1]=1 时基准但**没有流**（网线/上位机停了）；
    //   [0]=1 时基本身不可信（断链时 RXC 被拉到 ≈2.5 MHz ⇒ `eth_live` 那个读数不能用）。
    // 只在 `owner_eth=0` 时有意义（ETH 拿着屏幕时这三个位是"如果现在放手会是因为…"）。
    output reg  [2:0] why_ps
);
    // 手动锁**只改"谁想要总线"，不改"什么时候能换手"**：换手仍然只在两个引擎都空闲时发生。
    // 直接在输出上加一个 mux 是最容易想到的写法，也是错的 —— 那会在一次拷贝中途把选择位翻掉，
    // 留下半开的 AXI 读突发（这正是本模块要消灭的那个老毛病）。
    wire force_eth = (sel == 2'd01);
    wire force_ps  = (sel == 2'd10);

    reg [31:0] quiet;
    wire       both_idle = ~row_busy & ~fill_busy;
    // 时基不准时一律当作"没有流"：宁可让 PS 接管（它至少能立刻出画面），
    // 也不要在一个无法证实的电平上锁死显示端。
    wire       eth_wanted = force_eth ? 1'b1 : force_ps ? 1'b0 : (eth_live & eth_tb_ok);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            owner_eth <= 1'b0;      // 配置完成时两边都没东西，先给 PS
            quiet     <= 32'd0;
            // 复位值取"没有流 + 时基还没验"（011），不取 000：
            // 000 的意思是"一切正常、是被人钉住的"，那是刚上电时最不该撒的谎。
            why_ps    <= 3'b011;
        end else begin
            // 每拍寄存**同一组输入**的当前值（只有触发器，没有新判决）⇒ 与 owner_eth 出自同一份事实
            why_ps <= {force_ps, ~eth_live, ~eth_tb_ok};
            // 计数器只服务"往 PS 让位"这一个方向；ETH 一活就清零（回抢不等）
            if (!eth_wanted) begin
                if (quiet != 32'hFFFF_FFFF) quiet <= quiet + 32'd1;
            end else quiet <= 32'd0;

            // 唯一的赋值点：只有两边都空闲才换主人 ⇒ 不会切断任何一次拷贝
            if (both_idle) begin
                if (eth_wanted)             owner_eth <= 1'b1;
                else if (quiet >= T_OFF_CYC) owner_eth <= 1'b0;
            end
        end
    end
endmodule
