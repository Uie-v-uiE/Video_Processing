# v6 上板验证单（结果由板测填写）

产物：`build_v6/system.bit`、`build_v6/system.xsa`（同目录含
`timing_summary.rpt` / `utilization.rpt` / `rebuild.log`）。

## 1. 下载 bit

用 Vivado Hardware Manager（`Auto Connect` → 右键 `xc7z020` →
`Program Device` → 选 `build_v6/system.bit`）。

> `build_tcl/program_board.tcl` 里写死的是 `$root/build/video_pipeline.bit`，
> 若要复用它，请把 `build_v6/system.bit` 复制成那个路径。

## 2. Vitis

**必须**用本次的 `build_v6/system.xsa` 重建/更新 Platform 后再 Run ELF
（bit 下载会复位 PS，每次下 bit 都要重新 Run ELF）。

## 3. 上位机

```bat
cd host
python video_sender.py --ip 192.168.1.10 --src 192.168.1.100 --fps 15 --anim
```
默认已开启 15 MB/s 帧内限速（v6 新增）。对照组：
`--no-pace` 复现旧的整帧倾泻。

## 4. 板级复验（已自动完成的部分）

| 项目 | 方法 | 结果 |
|------|------|------|
| bit 下载 | `build_tcl/program_v6.tcl`（JTAG，xc7z020_1） | OK |
| PS/DDR 可用 | `mwr/mrd 0x1000_0000` 回环 | OK（FCLK 100MHz 已起） |
| PL 网络活着 | `ping 192.168.1.10` | 1 ms，0% 丢包（PL 侧 ARP/ICMP） |
| 选视频源 | `build_tcl/set_src.tcl` 写 `0x41200000=0x00010000` | 回读 `00010000` |
| 入包完整性（修复前） | `ddr_verify` 回读两 bank | 只有 23~37% 的 32bit 字完整，坏字掩码几乎全是 `1010/0101`，且 0.2/2/8/15 MB/s 四档空洞数几乎不变 |
| **入包完整性（修复后）** | 同上 | **bank0 76800/76800 = 100%，lane 153600/153600，空洞游程 0**<br>*（注：这是 `wordid` 恒定图案的结论，事后证明它看不出逐帧丢字，见 §7.1；以 v6.3 一行为准）* |
| 速率余量 | 30fps 限速 30MB/s / 30fps 不限速 / 60fps 不限速(18.4MB/s) | 全部 100%（同上，测量方法有盲区） |
| 时序/资源 | `build_v6/timing_summary.rpt`、`utilization.rpt` | WNS **+0.373 ns**、WHS +0.070 ns，全部满足；BRAM 130/140（92.9%） |

### 4.1 v6.3（2026-09-21 00:10 出的 bit）板级复验 —— 用 `frameid` 逐字反解帧号

流程：`ps_jtag_boot → program_v6 → set_src → node host/measure_v63.mjs --fps N --count M`
（**必须发完再回读**：回读要几秒，边推边读会让每个地址段读到不同时刻的帧，
统计全部作废 —— 这一点我第一次就踩了，跨度 130..152 就是这么来的）。

| 推流 | 最新帧在自己 bank 的 16bit 命中率 | 包内分带丢字率 | u32 内两 16bit 不同帧 |
|------|--------------------------------|--------------|---------------------|
| 15 fps / 80 帧（A9 停） | bank0 #78 **100.0%**，bank1 #79 **100.0%** | 六个带全 **0.0%** | 0/76800 |
| 30 fps / 200 帧（**A9 在跑**） | bank0 #199 **100.0%**，bank1 #198 **100.0%** | 全 **0.0%** | 0/76800 |
| 60 fps / 300 帧（18.4 MB/s） | 两 bank 各 **100.0%** | 全 **0.0%** | 0/76800 |
| 15 fps / 200 帧（**A9 在跑**，交付工况） | bank0 #199 **100.0%**，bank1 #198 **100.0%** | 全 **0.0%** | 0/76800 |
| （修复前 v6.2 同一指标） | 42~52% | 0–48 B 6.7%，48 B 之后 54~64% | 14296/76800 = 18.6% |

### 4.2 黑点排查：分包长度 1396 vs 1392（同板同 bit 同会话 A/B）

用回读定位到「规律黑点」不是本版 RTL 造成的，而是上位机分包长度：

| 分包 | 最新帧命中率 | 每帧空洞（16bit 字） | 空洞内容 |
|---|---|---|---|
| 1396 B（本机多份历史 `video_sender.py` 的取值） | 99.9% | **222（111 处 × 2）** | 0x0000 ⇒ 纯黑点 |
| 1392 B（本仓库默认） | **100.0%** | 0 ~ 2（#4.1 的已知残留） | — |

机理与复现：`report/ISSUES.md` #29、`src/host/HOST_GUIDE.md` §6.1。

**帧号跨度 = 相邻两帧**（78/79、198/199）⇒ 每个 bank 里干干净净只有一帧，
乒乓切换本身没有把两帧混在一起。本次 bit：WNS **+0.675 ns**、WHS +0.053 ns、
WPWS +0.264 ns，111287 个端点 0 违例（`build_v6/timing_summary.rpt`）；
Slice Registers 52687（49.52%）、BRAM 138.5/140（98.93%，与 v6.2 同）。

已知残留（不影响显示，记录以免明天被当成新问题）：偶发地，某个 bank 的
**最后一个 64bit 字的高半个 u32**（地址 +0x4aff8，帧的最后 4 字节 = 2 个像素）读到 0；
四档复测的 8 次「bank 末帧」读数里出现 4 次，15/30/60 fps 都会 ⇒ **不是速率专属**。
每帧最多影响 2 个像素，且下一帧同一地址会被覆盖 ⇒ 自愈；≥696（整包）的游程段数 = 0。
`tb_v6_ingress_integrity +FULL`（221 包、最后一包 960 B）里 38400 个字
**全对**（`lanes_bad=0/153600`，最后一字四路 lane 都是 0x95ff）⇒ 不是
reasm/CDC/打包器的确定性逻辑问题。最合理的解释：**帧最后 2 个 16bit 偶发没被打包器推出**
（最后一拍 `wr_en` 与 `flush` 的竞争；帧中间看不见是因为下一帧同地址覆盖，
只有停流后最后两帧能被读到）。要坐实：把 TB 的 `send_byte` 分别改成
「`p_eof` 与最后一个字节同拍」和「晚一拍」两种时序各跑一次 `+FULL`，看哪种复现这个签名。

板子当前状态（2026-09-21 00:2x）：已按 `ps_jtag_boot → program_v6 → set_src`
恢复成「PS 在跑 + v6.3 bit 在 PL + SRC1 视频」，屏上留的是 `move` 图案的最后一帧
（四象限 + 红块）。要看动图直接重新推流即可。

仍需要人眼确认的只有 §5 的显示效果。

## 5. 观察项

| # | 检查 | 期望 | 实测 |
|---|------|------|------|
| 1 | SRC0 彩条 | 干净、无横纹 | 待肉眼 |
| 2 | SRC1 静止图 | 无黑横纹 | 数据面已确认：16bit 粒度丢字 = 0（§4.1），肉眼待确认 |
| 3 | SRC1 动画 | 无拖影、无固定黑缝 | 数据面已确认：30/60 fps 下每帧 100% 落位 ⇒ 不可能再有「上一帧残留拼进来」的拖影；肉眼待确认 |
| 4 | OSD `eth`/帧计数 | 随推流递增 | 待肉眼（JTAG 回读时 A9 被停，OSD 看不到） |
| 5 | OSD `net_bad` | 限速下接近 0；`--no-pace` 下明显 >0 | 待肉眼 |
| 6 | 停流后冻结帧 | **干净**（v6 关键判据：有空洞就不 commit） | 数据面已确认：停流后回读，两个 bank 各是一整帧 100%（#78/#79、#198/#199）；肉眼待确认 |
| 7 | 拔网线 30s 再插 | 自动恢复推流，不需重下 bit | 待肉眼 |
| 8 | `--fps 30 --no-pace` | 允许 net_bad 上升，但不允许卡死/花屏不可恢复 | 未测（`--no-pace` 已知会把 CDC 灌满丢包，属于设计上的限速前提） |

判读：
* 若 6 仍脏 → 覆盖门限没起作用，回看 `stat_frames`/`stat_bad` 比例。
* 若画面完全不更新且 `stat_frames` 在涨 → 拷贝带宽不足（V-blank 预算
  需要 ≥0.571 拍/周期 ≈ 457 MB/s），看 `timing_summary.rpt` 与 HP0 占用。
* 若有固定位置的黑缝 → `disp_quiet` 窗口与光栅未对齐，需要加大 `VB_X_GUARD`。

## 6. 本轮改了什么（单变量清单）

1. `frame_reasm.v`：commit 需要 `rows_hit==IMG_H` **且** 帧内字节数累计到
   `FRAME_BYTES`；修 `p_valid&&p_eof` 同拍的 off-by-one；`stat_bad` 每帧只加一次。
2. `pl_video_top.v`：拷贝窗口由「全部消隐」收紧为「仅 V-blank + 64 像素尾部保护」。
3. `frame_commit_lock.v`：拷贝在 `allow` 上升沿即启动（不再等 vsync 边沿，多出 36% 预算）。
4. `axi_frame_writer_gated.v`：`MAX_OUT` 2→4（64 拍在途）。
5. `host/video_sender.py`：新增 `Pacer` 帧内限速，默认 15 MB/s；分包长度
   1396 → **1392（必须是 8 的倍数，见 `docs/ANALYSIS_v6.md` §7.1）**。
6. `rtl_fix/eth_udp_video_top.v`（v6.1，板级回读定位）：入包 CDC 读侧从
   「每 3 拍 1 条」改成「每拍 1 条」，并让 flush 不再顶掉数据写 —— 这是
   黑横纹的真正主因，与上位机速率无关。
7. 新增工具：`host/video_sender.mjs`（无需 python 的同协议推流 + `--test wordid`
   自描述图案）、`host/ddr_verify.mjs`、`host/ddr_holemap.mjs`（JTAG 回读 DDR 逐
   16bit lane 找空洞）、`build_tcl/rebuild_v6.tcl`、`build_tcl/program_v6.tcl`。
8. `build_tcl/rebuild_v6.tcl`：把工程里失效的 `ghosting_fix_v5/rtl/*.v` 换成
   本工作区 `rtl_fix/*.v`（该目录在本机不存在；此改动会写回 `ADD/Video_Pipeline-main`
   的 `.xpr`）。
9. **v6.3** `rtl_fix/axi_frame_saver64.v`：写通道不再逐字等 B 响应（AW/W 同拍挂出、
   各保持到被接收，`OST=8` 在途，`m_axi_bready` 恒 1，`outst` 只回收计数且不回绕）。
   入包写吞吐上限由「往返延迟决定 ≈20 MB/s」变成「总线握手决定 ≈400 MB/s」。
   定位依据与仿真表见 `docs/ANALYSIS_v6.md` §7.5；判据工具 `host/ddr_stale.mjs`。

仿真（全量回归 16/16 PASS，`sim_work/reg3.log`）：
`tb_v6_cover_gate` / `tb_v6_vblank_copy` / `tb_v6_ingress_integrity` 新增并通过，
`tb_v50_rows_prod` 按 v6 契约更新期望。详见 `docs/ANALYSIS_v6.md`。

## 7. 不看屏幕的复验方法（JTAG 回读 DDR）

```bat
:: 1) PS 起来（正常应改用 Vitis Run ELF；这里用 JTAG 兜底）
"D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat" build_tcl\ps_jtag_boot.tcl
:: 2) 配 PL（必须在 PS 起来之后，GPIO 写值又要在这之后）
"D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat" -mode batch -nojournal ^
    -source build_tcl\program_v6.tcl
"D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat" build_tcl\set_src.tcl
:: 3) 发自描述图案：每个 16bit 像素 = 字号 + 帧号 ⇒ 能看出「这个字来自第几帧」
node host\video_sender.mjs --fps 15 --count 40 --test frameid --pace-mpbps 15
:: 4) 把两个 bank 读回来逐字反解帧号，给出「包内字节偏移 → 丢字率」签名
node host\ddr_verify.mjs --frameid
node host\ddr_stale.mjs
```

判据（v6.3 起看这个，别再看 `words exact`）：`ddr_stale.mjs` 的分带丢字率应当
**每一带都接近 0%**，最新帧命中 100%。历史签名是「0–48 B 约 6%、48 B 之后约 60%」
⇒ 那是排空速率跟不上（打包器逐字等 B）；若变成「≥696 个 16bit 的整包长带」
⇒ 那是某个窗口把端口完全占死或前端整包丢失。
`half(1010/0101)`/`u32 内两个 16bit 不同帧` 比例高 ⇒ 仍在按 16bit 粒度丢。
