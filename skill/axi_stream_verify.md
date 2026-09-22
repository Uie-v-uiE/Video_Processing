# S3 · AXI / AXI4-Stream 视频通路的自证方法

## 适用场景
- 没有厂商 AXI VIP、只有手写 RTL 的工程：HP 口读写 DDR、AXI-Stream 风格视频流水、
  多级 sideband（`de/x/y/left`）对齐、64bit beat 拆像素。
- 症状长这样：画面被切成 4 幅 / 窄条、右窗花屏、分隔线毛刺、master「不排空」。
- 不适用：需要协议合规性签核（本仓库没有总线功能模型，只做行为判据）。

## 使用方法
1. **单元 TB 固定时钟**：`sim/tb_proc_gray.v`（100 MHz、只驱动 `de_in/din`、检查 `de_out/dout`）、
   `sim/tb_timing.v`（`video_timing` 的 `x/y/hs/vs/de/fs/fd`）。跑法：
   `SIM_TB=tb_proc_gray vivado -mode batch -nojournal -log sim/xsim.log -source sim/run_sim.tcl`。
2. **backpressure 必须真拉低 ready**，不能只跑理想时序。带反压的台架清单（grep `ready` 得到）：
   `tb_v5_gated` / `tb_v5_copy` / `tb_v57_rdw_copy` / `tb_v58_full_done` / `tb_v6_vblank_copy` /
   `tb_v6_ingress_integrity` / `tb_v6_pingpong` / `tb_v6_tail_bank`。
   plusargs 走 `SIM_ARGS="+FULL +MISALIGN"`（`tb_v6_ingress_integrity.v:241,243`）。
3. **拆包规则**：64bit beat = 4×RGB565 ⇒ 锁存整拍再拆 4 拍（`src/rtl/axi/axi_frame_writer_gated.v:39`
   `PIX_PER_BEAT = 4`），禁止「每个 rvalid 只写 1 像素」——那是 `report/ISSUES.md` §7「HDMI 窄条 / 4 幅画面」的成因。
4. **地址运算一律 32 位、并且单位要说清**：行地址左移溢出见 §8；`frame_reasm` 的
   `wr_addr <= off[18:1]` 是 **16bit 字索引**，注释直接写明「Must NOT use `off[16:1]`（16-bit …）」
   （`src/rtl/eth/frame_reasm.v:101,148`）。TB 按字节地址激励会让每帧字数翻倍、整体错位。
5. **sideband 与数据同延迟**：0° 也要走 3 拍旁路链（§9）；`rd_addr = {sy[8:0],9'b0}+sx` 要**打一拍**
   再进 BRAM，sideband 同步加长（§20）。
6. **诊断图案用细线/棋盘/文字，不要只用大色块**：恒定图案结构上看不见逐帧丢字
   （§34、`report/AI_COLLABORATION.md` §2.1）。现成图案：
   `node src/host/video_sender.mjs --test bars|move|edge|grad|frameid`。
7. **先看从机再看主机**：`report/ISSUES.md` §35 的规则——看到 master「不排空」，先验 TB 从机的
   B 通道（是否只有 1 个 B 寄存器、是否用组合 ready 握手、是否用上一拍的 AW 地址配 W 数据）。
8. **握手类模块单独成 TB 并把时钟做成非整数比**：`src/rtl/util/ps_publish.v` 的台架用
   7 ns / 20 ns 两个时钟 + 每次发布加 0–5.9 ns 伪随机相位（`sim/tb_ps_publish.v:5,9-10,119-127`）。

## 已验证效果
- 台架规模与判据纪律：全量回归 **34/34**（`sim/results/regression_v77_r13.txt` 末行
  `SIM DONE pass=34 fail=0`）。`sim/run_sim.tcl` 现在把「一个 PASS/FAIL 都没打印」的
  `NO_ASSERT` 与 FAIL **同等对待**（`report/OVERNIGHT_LOG.md` R13 第 3 条）⇒ 绿色才是绿色的。
- 帧缓存地址映射改造被逐像素钉住：`sim/tb_fb_roundtrip.v`（`W=512,H=300`，`:19-21`）实测
  写入 38400 字 + 2 次越界写，流水回读 153672 次 + 块边界/帧尾定点 16 次 ⇒
  **比对 153688 次、错 0 次**，同时钉住「读延迟仍是 1 拍」这条 v6.4 契约
  （`report/OVERNIGHT_LOG.md` R04）。
- 显示拷贝窗口在生产几何（512×300 / 1344×625 / 100 MHz）下的四档从机速率实测
  38441 / 54894 / 64036 / 1708873 拍，全部「不写有效行、不重复、不越界」
  （`report/V6_ROOT_CAUSE.md` §3 + `RESULT tb_v6_vblank_copy PASS`）。
- 跨域握手 60 次相位扫描 **60/60 通过**，判据是三次计数相等 `rises = falls = consumes = 60`
  （`sim/tb_ps_publish.v:126-127`；`report/OVERNIGHT_LOG.md` R13）。
- 反例判据（「没接上时必须非 0 / 必须恒 0」两个方向）在 `tb_link_monitor` 里是 26 条断言，
  并且新增了一条**用生产参数例化的守门台架**——因为它抓出过「TB 为了跑得动把 `CLK_HZ` 改成
  1000，恰好掩盖了 1 ms 分频器位宽缺陷」（`report/CHANGELOG_V7.md` V7.6 §三个 bug 之 2）。

## 失效条件
1. **小几何台架不能支撑带宽/缓冲类结论**：`sim/tb_timing.v:11-13` 用的是
   `H_ACTIVE=16, V_ACTIVE=8`；`sim/tb_v6_pingpong.v:14` 用 `IMG_H=60`（注释自己写明
   「仿真时长可控，缓冲压力比例不变」）。它们的 `firstmiss=512` 之类结论只可用作**机理形状**，
   绝对数值要回生产几何台架复测（旧 handoff 文档同样强调过这点）。
2. 仿真未模拟 backpressure（`ready` 从不拉低）时，本节所有结论作废。
3. 跨时钟未过 `dc_fifo`（Gray 指针 + 双级同步）的接口不要用本清单判「没问题」：
   `build/cdc.rpt` 至今有 **4 行 Critical**（`Asynch Clock Groups` 类，即被时钟组豁免的跨域），
   门禁口径是「无新增」而不是「零」（`report/OVERNIGHT_LOG.md` §1.4、§5）。
4. AXI3 burst > 16 拍非法：本设计读侧已经贴上限（`BEATS=16`），写侧 `axi_frame_saver64`
   是 `AWLEN=0` 单拍 + `OST=8` 在途。换到 AXI4 从机时 `AWLEN` 语义与 `WSTRB` 要求都要重对。
5. **工具链约束会让「看起来对」的 TB 编不过或测错对象**：本流程 `xvlog` 对 `.v` **不开**
   SystemVerilog（`int` / `++` / `$urandom_range` 全不认），`edge`、`cover` 是保留字不能当
   端口/信号名（`VRFC 10-8549`），激励必须在沿后 `#1` 给否则与 DUT 抢读，数组写块必须排在
   其依赖的 `wire` 声明之后（`report/OVERNIGHT_LOG.md` R05/R13）。
   重写模块前若 TB 用**层次名**引用了内部信号，必须 `grep` 确认，否则 TB 会静默测错对象（R06）。
6. `report/ISSUES.md` 的编号在不同版本间漂过：旧笔记里的 #10/#11/#15 在本仓库分别对应
   §8 行地址溢出、§9/§20 对齐、§34 图案造假 ⇒ 引用前 `grep "^### " report/ISSUES.md` 核对。
