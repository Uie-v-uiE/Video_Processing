# 算法与处理级

本章的数字口径以 `../data/metrics.csv` 与 `build/report/*.rpt` 为准；重复写出是为了让这一章能单独读懂。

这一章回答三件事：处理链由哪几级组成、每一级为什么这样实现、代价落在哪里。每节给同一个形状——
实现选择、代价、依据的文件。下面点名的是仓库里现在的模块；"台架"指 `sim/` 下那份用仿真激励逐拍
核对模块行为的 Verilog 文件，这里只写它管什么、不抄它的输出，读数去它点名的产物里看。

## 逐像素效果链（固定 15 拍）

- 实现选择：级 0 是 gamma，级 1..5 是五个可选级，九位 `stage_sel` 每一位直连一个算法，链上没有第二条
  兜底路径；整链固定 15 拍，与哪一级开、同级选哪个算法都无关（灰度 1 + 反色 1 + 模糊 3 + 锐化 3 +
  Sobel 3 + 阈值 1 + 形态学 3）。gamma 表项由分布式 RAM 组合读出，不占拍。出处
  `src/rtl/process/proc_pipeline.v` 文件头第 2–21 行（`LATENCY = 15`、`OFF_LINES = 4`）。
- 代价：窗口级是三拍不是两拍。`H_ACTIVE` 这一版传进去的是 1024 个有效拍，同级相邻两列在源图上只差
  半格，所以横向的模糊、锐化、Sobel 的半径是**半个源像素**（同一文件头第 9–15 行）。处理链的内容
  固定滞后 −4 行，抵消手法是顶层把右窗的读坐标提前 `OFF_LINES` 行（`proc_pipeline.v:23–27`，
  抵消的那条坐标链记于 `report/architecture.md` §4 的 `cy_r`）。
- 依据：`src/rtl/process/proc_pipeline.v:20` 写着"tb_v86 实测 de_in→de_out 再与声明值比"，也就是说这个延迟不只是
  声明值，台架会逐拍量一遍再对回去；台架是 `sim/tb_v86_pipe_sel.v`，装配与各级映射见 `report/modules.md`
  的 process/ 表。

## 缩放与旋转（逆映射加双线性读口）

- 实现选择：屏幕坐标 (x,y) 到源坐标 (sx,sy) 用定点逆映射，`inv_scale` 取 Q8 定点（256 = 1.0×、
  512 = 0.5×）；缩放与旋转同级、3 级流水，输出 `sx,sy,oob,frac_x,frac_y`；旋转用 360 项 Q8 的
  sin 与 cos 两个 ROM。出处 `src/rtl/process/zoom/zoom_mapper.v` 文件头第 2–10 行、
  `src/rtl/process/rotate/sin_rom.v` 与 `cos_rom.v`（例化行见 `report/modules.md`）。读口
  `src/rtl/process/bilin/fb_bilin.v` 每个源像素用满它天然的 4 个 50 MHz 拍、单读口每拍一次、全程留在
  像素时钟这一个域里（不借助更快的域），`bilin_en = 0` 时逐位等于最近邻（该文件头第 2–6 行）。
- 代价：旋转一开，真正生效的倍率被 `zoom_ctrl` 收进"这个角度刚好装得下"那一档 ⇒ 旋转态不提供放大，
  手动 1.33×/1.5×/2.0× 会被拉回装得下的那一档（档号不丢，关掉旋转立刻回去），而 0° 不收这一档
  （`report/architecture.md` §4 的缩放表、`report/demo_script.md` §2）。双线性那对乒乓读口，这一对的
  结果要下一对才读得到，于是多 2 显示行的延迟（`BILIN_ROWS`，`report/architecture.md` §4）。
- 依据：`sim/tb_zoom_mapper.v` 管 1.0× 恒等、0.5× 的中心与越界、控制器的三角波（见
  `report/rotation_and_effects.md` §5）；`sim/tb_v94_zoom_sel.v` 的 T8a~T8f 管旋转生效时倍率被收进哪
  一档；`sim/tb_v101_fb_bilin.v` 管读口。三支台架的职责记于 `report/modules.md` 与
  `report/architecture.md` §5。

## 形态学（3×3 腐蚀与膨胀）

- 实现选择：放在二值化之后，因为它的定义就是"邻域内全 1 才 1 / 有 1 就 1"，操作对象是面具图。结构
  逐条照 `proc_box_blur` 对齐：同样的两条行缓存读法、同样的三拍 de 链、同样的中心抽头旁路。掩码每
  个像素只存 1 bit，两条掩码行缓存 = 512 bit × 2。出处 `src/rtl/process/proc_morph.v` 文件头
  第 2–7 行，端口 `mode[1:0]` 见同文件第 13 行。
- 代价：腐蚀与膨胀**互斥**——`stage_sel[7]`、`[8]` 两位同时为 1 时两个都不做。开运算与闭运算要两遍
  3×3 窗口，这里只有一遍，所以这一格被明确旁路。另外加一条 16 bit 行缓存，只为旁路时能还原原色。
  出处 `src/rtl/process/proc_pipeline.v:59–60` 与 `proc_morph.v:7`。
- 依据：`sim/tb_v84_morph.v` 与 `sim/tb_edge_rim.v`（后者管边缘那一圈的内容）；映射见 `report/modules.md`
  的 proc_morph 行与 `report/architecture.md` §5 的四个窗口级台架表。

## OSD（屏上状态叠加）

- 实现选择：像素通路的最后一级，叠 5 行状态文字（面板/FPS/片源、Pipe/Th/Gamma、Rot/Zoom、
  Split/Latency、Temp/无信号），字模是 5×7 点阵再放大 3 倍（`CHAR_W = 18`、`CHAR_H = 21`）；输出比输入
  晚 2 拍，内容与坐标仍是同一拍；行数参数 `N_LINES = 5`。出处 `src/rtl/video/osd_overlay.v` 文件头
  第 2–19 行。叠层开关 `osd_en` 由 `gpio_o[20]` 反相驱动，复位状态是"有 OSD"（`src/ps/main.c`
  第 11 行、第 53–57 行）。
- 代价：字格几何里含不是 2 的幂的除法与取余（`/31`、`/18`、`%18`），组合链的级数因此偏高。`FPS:`
  那一格数的是"写进屏的新帧"，而它以前数的是扫过屏的显示场，两者不是一回事（计数所在的模块
  `src/rtl/util/shown_rate.v`）；换计数依据必须与上板的那一版一起念，否则屏上的数与报告里的数对不上
  （`report/architecture.md` §2 表末、`report/demo_script.md` §0 第 3 步那条注意事项）。
- 依据：`sim/tb_osd_lines.v` 的 T13 判"关掉叠层后逐位等于背景"，`sim/tb_v794_osd_glyph.v` 管字格；
  三处凭据的位置记于 `report/demo_script.md` 开头段。

## 打包（写 DDR 的 16b→64b 与 AXI 流水化）

- 实现选择：`axi_frame_saver64` 把入包的 16bit 字打包成 64bit 字，以 AWLEN=0 的单拍写挂在 HP0 上；
  写地址与写数据两条通道并行挂出、各自握手，在途深度 OST=8；写响应只用来回收计数，不阻塞数据通路。
  出处 `src/rtl/eth/axi_frame_saver64.v` 文件头第 2–4 行。
- 代价：打包器的 FIFO 必须被综合成分布式 RAM。该文件头第 10–13 行记着反面：早先版本让它被推断成
  触发器（512×100 bit ≈ 5.1 万个 FDRE），一份就要占掉整机 Slice Register 的 94%，`FW = 11` 那一档直接
  触发 DRC UTLZ-1。加深缓冲也治不了真正的瓶颈——瓶颈是平均排空速率而不是缓冲深度（同一文件头
  第 5–7 行；这两笔记在 `report/log/issues.md` 的第 31 与第 32 条）。
- 依据：`sim/tb_v6_pingpong.v` 与 `sim/tb_v5_bank.v`（乒乓与 bank 那两件事）；例化与台架行见
  `report/modules.md` 的 eth/ 与 axi/ 表。

## 这一章管到哪里

- 上面每一级的"拍数、半径、行列数"都由模块文件头声明并被台架逐拍核对过；观感（模糊够不够柔、边线
  粗细）不在仿真判据的射程里，那部分只由看屏幕的人确认，落点在 `board/acceptance.md`。
- 横向窗口半径等于半个源像素是既成事实，不是待评估的新风险；要回到"一行只喂源列数那么多拍"的喂法，
  得先把坐标抽头与行缓存写地址那一族的账重算一遍，那段说明在 `src/rtl/process/proc_pipeline.v` 文件头。
- 本章不写占用与余量。每级花掉多少 LUT、BRAM、DSP，仓库里只有合计值、没有逐实例归属，那格账在
  `build/` 下的报告原件与 `data/metrics.csv` 里读。

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
