# 算法与处理级

每小节给三件事：实现选择 / 代价 / 依据的台架或报告文件。文件里点名的是当前代码的真实模块；
台架只写它的职责（我据以陈述的是模块文件头与 `report/modules.md`、`report/architecture.md`）。

## 逐像素效果链（15 级流水线）
- 实现选择：级 0 gamma + 级 1..5 五个可选级，九位 `stage_sel` 逐位直连、不留第二条兜底口径；
  整链固定 15 拍，与哪一级开、同级选哪个算法都无关（灰度 1 + 反色 1 + 模糊 3 + 锐化 3 + Sobel 3 +
  阈值 1 + 形态学 3）。gamma 表项是分布式 RAM 组合读出、不占拍。出处 `src/rtl/process/proc_pipeline.v`
  文件头第 2–21 行（`LATENCY = 15`、`OFF_LINES = 4`）。
- 代价：窗口级是三拍不是两拍；`H_ACTIVE` 现在传的是 1024 个有效拍，同级相邻两列在源上只差半格，
  所以横向模糊/锐化/Sobel 的半径是**半个源像素**（同一文件头第 9–15 行）。链子内容滞后固定 −4 行，
  由顶层把右窗读坐标提前 `OFF_LINES` 行抵消（`proc_pipeline.v:23–27`，抵消手法记于
  `report/architecture.md` §4 的 `cy_r`）。
- 依据：`src/rtl/process/proc_pipeline.v:20` 明写"tb_v86 实测 de_in→de_out 再与声明值比"——
  台架 `sim/tb_v86_pipe_sel.v`；装配与各级映射见 `report/modules.md` process/ 表。

## 缩放 / 旋转（逆映射 + 双线性读口）
- 实现选择：屏幕 (x,y) → 源 (sx,sy) 用定点逆映射，`inv_scale` Q8（256 = 1.0×、512 = 0.5×），
  缩放与旋转同级、3 级流水，出 `sx,sy,oob,frac_x,frac_y`；旋转用 360 项 Q8 的 sin/cos ROM。
  出处 `src/rtl/process/zoom/zoom_mapper.v` 文件头第 2–10 行、`src/rtl/process/rotate/sin_rom.v`
  / `cos_rom.v`（例化行见 `report/modules.md`）。读口 `src/rtl/process/bilin/fb_bilin.v` 每个源像素
  用满它天然的 4 个 50 MHz 拍、单读口每拍一次、全程不进快域，`bilin_en = 0` 时逐位等于最近邻
  （该文件头第 2–6 行）。
- 代价：旋转一开，生效倍率被 `zoom_ctrl` 钳进"这个角度刚好装得下"那一档 → 旋转态不提供放大，
  手动 1.33×/1.5×/2.0× 被拉回 fit（档号不丢，关掉旋转立刻回去），而 0° 不钳
  （`report/architecture.md` §4 缩放表、`report/demo_script.md` §2）。双线性乒乓读口一对结果
  下一对才读得到，额外 2 显示行延迟（`BILIN_ROWS`，`report/architecture.md` §4）。
- 依据：`sim/tb_zoom_mapper.v`（1.0× 恒等、0.5× 中心与 OOB、控制器三角波，见
  `report/rotation_and_effects.md` §5）、`sim/tb_v94_zoom_sel.v` 的 T8a~T8f（那一钳的档位）、
  `sim/tb_v101_fb_bilin.v`（读口）——三者职责记于 `report/modules.md` 与 `report/architecture.md` §5。

## 形态学（3×3 腐蚀 / 膨胀）
- 实现选择：放在阈值之后，因为它的定义就是"邻域内全 1 才 1 / 有 1 就 1"，是对面具图的操作；
  结构逐条照 `proc_box_blur`——同样的两条行缓存读法、同样的三拍 de 链、同样的中心抽头旁路；
  掩码只存 1 bit/像素，两条掩码行缓存 = 512 bit × 2。出处 `src/rtl/process/proc_morph.v`
  文件头第 2–7 行、端口 `mode[1:0]` 见同文件第 13 行。
- 代价：腐蚀与膨胀**互斥**——`stage_sel[7]`、`[8]` 两位同时为 1 时两个都不做（开/闭要两遍 3×3
  窗口，这里只有一遍，明确旁路）；另加一条 16 bit 行缓存，只为旁路时能还原原色。出处
  `src/rtl/process/proc_pipeline.v:59–60` 与 `proc_morph.v:7`。
- 依据：`sim/tb_v84_morph.v`、`sim/tb_edge_rim.v`（边缘内容）——映射见 `report/modules.md`
  的 proc_morph 行与 `report/architecture.md` §5 的四个窗口级台架表。

## OSD（屏上状态叠加）
- 实现选择：像素通路的最后一级，叠 5 行状态文字（面板/FPS/片源、Pipe/Th/Gamma、Rot/Zoom、
  Split/Latency、Temp/无信号），5×7 字模 ×3 放大（`CHAR_W = 18`、`CHAR_H = 21`），输出比输入晚 2 拍、
  内容与坐标仍同一拍；`N_LINES = 5`。出处 `src/rtl/video/osd_overlay.v` 文件头第 2–19 行。
  叠层开关 `osd_en` 反相由 `gpio_o[20]` 驱动，复位即"有 OSD"（`src/ps/main.c` 第 11 行、第 53–57 行）。
- 代价：字格几何含非 2 幂的除/模（`/31`、`/18`、`%18`），组合链级数因此偏高；`FPS:` 那一格的口径
  历史上从"显示场计数"改数"写进屏的新帧"（`src/rtl/util/shown_rate.v`），改口径与上板版本要对齐
  （`report/architecture.md` §2 表末、`report/demo_script.md` §0 第 3 步的 ⚠ 注）。
- 依据：`sim/tb_osd_lines.v` 的 T13（关掉逐位等于背景）、`sim/tb_v794_osd_glyph.v`（字格）——
  凭据三处记于 `report/demo_script.md` 开头段。

## 打包（写 DDR 的 16b→64b 与 AXI 流水化）
- 实现选择：`axi_frame_saver64` 把入包的 16bit 字打包成 64bit 字、以 AWLEN=0 单拍写挂 HP0，AW/W
  通道并行挂出、各自握手、在途深度 OST=8，B 响应只在计数里回收、永不阻塞数据通路。出处
  `src/rtl/eth/axi_frame_saver64.v` 文件头第 2–4 行。
- 代价：packer FIFO 必须综合成分布式 RAM——该文件头第 10–13 行记，早先版本让它被推断成触发器
  （512×100 bit ≈ 5.1 万 FDRE）会占整机 Slice Register 的 94%、`FW = 11` 直接触发 DRC UTLZ-1。
  加深缓冲治不了真正的瓶颈（平均排空速率而非深度，同一文件头第 5–7 行，账在 ISSUES #31/#32）。
- 依据：`sim/tb_v6_pingpong.v`、`sim/tb_v5_bank.v`（乒乓与 bank）——例化与台架行见
  `report/modules.md` 的 eth/、axi/ 表。

## 本章依据的产物
- `src/rtl/process/proc_pipeline.v`
- `src/rtl/process/zoom/zoom_mapper.v`
- `src/rtl/process/bilin/fb_bilin.v`
- `src/rtl/process/proc_morph.v`
- `src/rtl/video/osd_overlay.v`
- `src/rtl/eth/axi_frame_saver64.v`
- `src/ps/main.c`
- `report/architecture.md`
- `report/modules.md`
- `report/rotation_and_effects.md`
- `report/demo_script.md`
