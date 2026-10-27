---
name: pynq-video-frame-pipeline
description: 用于用 PYNQ 的帧通路（AXI VDMA / HDMI 包装层）跑图像时；也用于出现"画面停在上一帧""首帧坏或尾帧坏""读帧一直不返回""按行宽算的字节数与硬件对不上""换分辨率后要么报错要么错位"这类症状的时候。换题目、换板卡仍可用。
compatibility: PYNQ 3.x/4.0 与 2.5.1 的 `pynq.lib.video`（两侧接口名已核到源码）；旧栈里 `pynq.video`/`Display`/`InValueError`/`OutValueError` 本包**未能核到**，不要当事实引用。未上板实跑
metadata:
  kind: 踩坑清单
  topic: PYNQ
---

# 帧通路：所有权、停摆与字节数这三件事

帧通路上的坏点几乎都落在这三处，而三处的判据完全不同——把它们混成"视频不显示"就会一路瞎试。

## 适用场景

- 画面停住、上一帧残影、首帧或尾帧坏、读帧调用一直不返回。
- 换分辨率/色深后错位，或算出来的行字节数与硬件配置不一致。
- 要给一条新的采集→处理→显示通路定最小可判活形状。

## 使用方法

**先查**：本版本 `pynq.lib.video` 的模块清单与类文档（`AxiVDMA`、`S2MMChannel`、`MM2SChannel`、
`VideoMode`、`PixelFormat` 在 2.5.1 与 4.0 都已核到存在）；IP 侧的行数/字长配置（hwh 里的 `C_S_AXIS_S2MM_TDATA_WIDTH`
这类参数名已核到，具体值以本工程为准）；一致性与缓存维护的方向（见 `pynq-dma-buffer-coherency`）。
一手资料优先级＝源码与 IP 配置 ＞ 官方 FAQ ＞ 教程 ＞ 记忆。
**先跟用户确认**：能不能改帧缓冲个数（吃内存）、能不能降一路刷新、是否允许为了判活加一个会动的计数器。

1. **字节数按定义算，不要抄教程里的魔数**：
   `bytes_per_pixel = ((bits_per_pixel - 1) // 8) + 1`，`stride = width × bytes_per_pixel`（除非显式给了 stride）——
   这是 `VideoMode` 源码里的算法。24-bit 走 3 字节，所以行字节数天然是 4 的倍数才对齐得整齐；
   非 4 倍数的 stride 在很多配置里直接报错。**换分辨率后错位**先查这一条。
2. **分清三条"停"的路**：通路没启动、通路被 park（停摆）、启动了但没等到帧。
   `AxiVDMA` 暴露 `parked`，读它就能把"卡住"与"没数据"分开；
   通道未启动时报的是 "DMA channel not started" / "Video mode not set, channel not started"，
   这两种错误文本与"等待超时"是三件不同的事，判据要分开打印。
3. **帧所有权是硬规则**：写侧 `newframe()` 拿到的是**还没提交**的缓冲，填完要 `writeframe`/`setframe` 才交出去；
   读侧 `readframe()` 拿到的帧在你用完后要归还（框架内部按 `framecount` 个缓冲轮转）。
   一边写一边被另一边读，看到的就慢一帧或两个半帧拼一帧。`cacheable_frames` 决定这些帧是否可缓存 ⇒
   **它改变了维护要求**，把它当配置项而不是默认值。
4. **完成/到达判定用硬件计数**：`irqframecount` 决定多久发一次中断，读回的帧计数为 0 或读不到 ⇒ `NOT_MEASURED`，
   不许按"应该已经到了"放行。
5. **末帧缺结束标记 ⇒ 读帧永不返回**：这是官方 FAQ 明确记录的一类形状（症状是**卡住**，不是数据错）。
   收尾要显式：写完最后一帧后按通路的结束语义停，而不是让 Python 端一直等。
6. **异常名要现探测再用**：旧栈教程里的 `InValueError`/`OutValueError` 在本包核到的 2.4/2.5.1/4.0 源码里**找不到**；
   新栈能看到的是 `LineStrideError` 一类的显式校验与若干 `RuntimeError`/`ValueError` 文本。
   `except` 之前先 `import` 探一次；探不到就别捕，并让那条判据判 `NOT_MEASURED`。

## 失效条件

- **把"读帧返回了"当"画面正确"**：返回只证明有帧到达，位段/格式/字节序仍可能全错 ⇒ 需要内容比对（见 `golden-frame-compare`）。
- **`parked` 没读就说"通路活着"**：一个静止源本就每帧同值，跨刷写同值不是冻死；读它喂给谁的代码再判
  （同 `board-liveness-readback` 的"先问这个字段凭什么会动"）。
- **改 `framecount` 不改归属**：缓冲数与谁在用哪一格绑定，改一边就出现"自己写自己读"。
- **色深与格式混用**：`PixelFormat(in_color, out_color)` 只管颜色映射，不改字节数 ⇒
  指望它修 stride 问题会把问题挪到别处。
- **照旧栈视频 API 写新栈**：`Display`/`pynq.video` 未能核到，写出来的代码在 import 阶段就失败，
  而失败信息很容易被误读成"板子不支持"。
- **通用 Zynq-7000 板卡没有现成镜像**：官方支持表里 Zynq-7000 只有 PYNQ-Z1/Z2（且有版本区间）；
  非列表板卡要自建 BSP/设备树，本条不覆盖那一段。

## 已验证效果

未量过，属建议：本条的接口名与算法逐条核到 `pynq.lib.video` 的 2.5.1 与 4.0 源码，**未在本队板卡实跑 PYNQ**。
可复跑的形式（有对应硬件才允许跑）：给一个已知图案的源，跑三种分辨率（行字节 4 的倍数、非倍数、极小），
每种各判四件事——`stride` 算得对不对、读回帧的内容是否等图案、`parked` 是否为假、
末帧是否能在有界时间内返回——共 `判 12 项`；
再加 1 项变异对照：把结束标记抽掉，"末帧返回"这一格必须变红；若仍绿，说明这条判据看不见那个缺陷。

## 来源

长自一类反复出现的观察：显示通路"没画面"被当成一个症状查，实际分属"没启动/停摆/没到达/内容错"四层，
其中"末帧缺结束标记导致永不返回"与"stride 与字节数不一致"两类最常被误归因。
接口出处：`pynq/lib/video/{common,dma,hierarchies}` 的 2.5.1 与 master 源码、官方 FAQ "End of Frame"。
配套：`pynq-dma-buffer-coherency`、`board-liveness-readback`、`width-and-overflow-audit`。
