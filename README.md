# 第三版攻关过程 · 去拖影的三次未收敛尝试（存档分支）

**这个分支不是可上板的实现**，而是将「拖影（ghosting）」这个问题**从"以为是显示侧问题"查到"其实是入包链丢字"**
之前走过的三条弯路原样存档。里面的 RTL 与上位机代码**不保证能被当前的构建脚本编出来**，
只保证可读到当时的判断依据。当前可用实现见 `main`，问题与版本的完整对应见
`main:report/VERSION_LINEAGE.md`。

## 问题是什么

现象（当时记录）：人物移动后原位置留颜色残影；静止时也撕裂；**停止推流后 bank 里仍是两帧混合**；
纯色图案看不出问题（因为颜色不变）。

排除过程的关键一步：换成自描述图案（每个 16bit 像素 = 字号 + 帧号）后回读，才发现
「**每帧只有约 42~52% 的字真正属于它自己那一帧**」——即残影不是显示切换瞬间造成的，
而是**数据在写进 DDR 之前就已经在丢**。这个判据转换本身比修复更有价值
（方法见 `main:report/V6_ROOT_CAUSE.md` 与 `main:skill/frameid_loss_signature.md`）。

## 三次尝试与本分支里的对应物

| # | 尝试 | 判据 / 结果 | 留下的文件 |
|---|------|-------------|-----------|
| 1 | **BRAM 真双缓冲** `frame_buffer_db.v` | XC7Z020 放不下：BRAM/LUT 爆资源，**实现失败**，退回单缓冲。（该模块在 `main` 的 `src/rtl/video/` 里作为历史文件仍存在，只是从未例化） | `docs/DDR_DUALBUF_ANALYSIS.md`（为什么单口不够、双缓冲的代价估算） |
| 2 | **DDR 三槽位帧管理器** `frame_buffer_manager.v`：FREE / RX / READY / DISP / INVALID 五态 + 槽位轮转 | 上板表现为**更严重的花屏与卡顿**；资源上 `build/utilization.rpt` 当时是 BRAM **134/140 = 95.71%**、WNS −6.4 ns（时序未收敛） | `rtl/frame_buffer_manager.v`、`docs/DDR_MULTI_SLOT_FBM.md`、`docs/CONSULT_BRIEF.md`、`sim/tb_fbm.v`、`sim/tb_pingpong.v`、`sim/tb_ddr_roundtrip.v`、`sim/tb_fbdb.v`、`sim/tb_saver_writer.v`、`sim/tb_seq_saver.v`、`sim/tb_dma_latency.v`、`sim/run_fbm_tb.tcl`、`sim/run_saver_tb.tcl` |
| 3 | **DDR 双 bank 乒乓 + 排空后提交**（`eth_udp_video_top.v` 里 `drain_pend` / `all_drained`） | 结构已接近最终版，但**致命缺口**：`pl_video_top.v:190` `wire writer_en = el1 ? 1'b0 : src_use_axi;` 与 `:238 assign kick_copy = el1 ? 1'b0 : src_use;` ⇒ **ETH 视频路径上 DDR 读回引擎根本没启动，显示 BRAM 仍由 UDP 边收边写**。所以这一版拖影不可能消失，也正是"上板更严重"的来源 | 判据与结论记录在 `docs/CONSULT_BRIEF.md`（当时的对外咨询简报，写明「根因已定位但修复上板表现为更严重的花屏卡顿」） |

三次的共同点：**都在改"什么时候把帧交给显示"，而真正的瓶颈在"帧能不能完整写进 DDR"**。
方向纠正发生在第四版：`axi_frame_saver64` 每写一个 64bit 字都要等 AXI 写响应 B，在途深度恒为 1
⇒ 吞吐被 HP0 往返延迟钉死在约 20 MB/s（主机给 15 MB/s 只有 1.3× 余量），显示拷贝一抢端口就
低于主机速率 ⇒ **每个包从第 48 字节起按 16bit 粒度丢弃**，表现为拖影 + 黑横纹 + 撕裂。
修复是第四版 V6.3（写通道流水化，`OST=8`，B 只回收计数）；随后 V6.4 补掉 `WSTRB` 恒 `0xFF`
导致的分包长度敏感问题（1396 B 载荷实测每帧 111 处 4 字节黑洞）。板级结果：最新帧命中率 42~52% → **100.0%**。

**加深缓冲是没用的**——这条被当时逐档测量证伪（尝试过把 CDC 做到 8192 深，丢字起始位置只等于
打包器深度，机理不变）。这是本分支最想留下的教训：**先建立能区分"哪一级在丢"的判据，再动手改结构**。

## 目录

```
rtl/frame_buffer_manager.v     三槽位 DDR 帧管理器（未收敛方案，未接入当前设计）
sim/tb_*.v                     当时用于判定槽位轮转 / 乒乓 / DDR 往返 / DMA 延迟的 7 个 testbench
sim/run_fbm_tb.tcl             当时的独立运行脚本（仓库相对路径按那个时期的布局）
sim/run_saver_tb.tcl             同上
docs/DDR_DUALBUF_ANALYSIS.md   双缓冲的代价估算与"为什么 7020 放不下"
docs/DDR_MULTI_SLOT_FBM.md     三槽位方案的状态机与时序设计
docs/CONSULT_BRIEF.md          对外咨询简报：现象、已排除项、当时卡在哪
```

## 怎么读

```bash
git checkout v3-ghosting-attempts
less docs/CONSULT_BRIEF.md          # 先看问题状态
less rtl/frame_buffer_manager.v     # 三槽位方案本体
git log --oneline v2-pl-ethernet    # 上一版（拖影刚被记录为"可接受"）
git log --oneline v3-seamless-zoom  # 同期正式第三版（加了连续缩放）
```
