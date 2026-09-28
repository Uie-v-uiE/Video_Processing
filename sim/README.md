# 台架（`sim/`）清单与去留

这里不是教程（怎么写台架、判据为什么要能红：见本地学习文档第 60 章，或本仓库
`skill/` 的"判据盲区/自己把台架判红"两条）。这一页只回答两个问题：**这些 `tb_*.v` 是怎么被跑起来的**，
以及**哪一个在看着什么**。

## 跑法

两个入口，都是**通配符收全部** `sim/tb_*.v`：

- `sim/run_sim.tcl` —— L1 全量批跑；
- `sim/run_one.sh <tb名>` —— 单跑一个。它在**编译之前**给顶层 / 台架 / RTL 盖三枚 md5，
  并且如果发现已经有 xsim 活着就直接退出（两个 xsim 会往同一个 `run.log` 里写）。

所以"某个台架忘了接进流水线"这件事不存在；反过来，**放一个坏台架在目录里，每次批跑都会被它拖住**。
门禁里另有两项是**钉 md5** 的（按台架名在 `build/gates.sh` 里搜得到）：
`tb_v98_top_seam`（唯一例化整个视频顶层的那把尺子）与 `tb_edge_rim`（边缘条带）。
改了任何 RTL，这两份报告必须重出，否则门禁会判"报告来自另一份代码"。

## 按"看着什么"分类

| 组 | 台架 | 盯的东西 |
|---|---|---|
| 顶层/几何/显示 | `tb_v98_top_seam` | 缝在第几列、每行画面是否连续一段、每一格带回自己的源行/列号（C4–C9），两条抽头的第 0 列（C8a/C8b） |
| 边缘条带 | `tb_edge_rim` | 窗口级效果链在行首/行尾/帧头/帧尾的错位（#97 那一族的专用尺子） |
| 抽头相位 | `tb_v100_raw_delay`、`tb_v92_seam_bleed` | 行延迟环逐格语义（T7 行首那一格 / T7k 行内其余格） |
| 缩放 | `tb_v96_zoom_scan`、`tb_v94_zoom_sel`、`tb_v95_zoom_snap`、`tb_zoom_mapper`、`tb_v100_fit_rot` | 八档码→倍率、快照一致性、定点拟合 |
| 旋转 | `tb_rotate_window`、`tb_v101_fb_bilin` | 旋转限制在窗口内、双线性读口 |
| 效果链 | `tb_proc_gray`、`tb_v84_morph`、`tb_v85_sharpen`、`tb_v86_pipe_sel`、`tb_v88_gamma` | 单级算术与控制字/旁路 |
| 收链/DDR | `tb_v795_rx_chain`、`tb_v795_rx_fcs`、`tb_udp_parser`、`tb_v6_*`、`tb_v5_*`、`tb_eth_video` | 拼帧、覆盖门限、乒乓 bank、写包 |
| 片源与仲裁 | `tb_v796_src_arb`、`tb_v102_src_life`、`tb_v82_src_mode`、`tb_v81_test_card`、`tb_v87_key_long` | 谁拥有屏幕、心跳、图卡"活着"的证据 |
| OSD/显示杂项 | `tb_osd_lines`、`tb_v794_osd_glyph`、`tb_v93_split_ctrl`、`tb_timing` | 屏上那一格的字形与位置、时序发生器等 |
| 纯软件模型 | `tb_bilin_lerp`、`tb_crc32`、`tb_fb_pack`、`tb_uart_decode_bits`、`tb_v50_rowmath`、`tb_v571_allow_lead`、`tb_sync_fifo`、`tb_tap_sched` | 用 Verilog 写的算法/协议模型，没有对应 RTL 顶层 |

## 去留判断（本轮清点，未动文件）

**保留，即使看着多余：**

- `tb_v5_saver` 等测"当前没有被任何顶层例化的老 RTL"的台架 —— 它们是 DDR 写包器改动的**复验工具**，
  不是摆设（`axi_frame_saver_burst.v` 等文件也留在树里等这个用途）。
- 上面标"纯软件模型"的那些：判据便宜、能锁算法行为，留着。

**退役候选（要先确认没有文档按名字引用它们，再一次性删，删完必须重跑门禁）：**

- `tb_v50_rows`（外部引用只出现在冻结下来的控制台留档里）、`tb_udp_reasm`、`tb_v83_card_render`
  （后两条分别只被一个 skill 条目和 `board/README.md` + 一个 host 工具点名）。

**必须修的（是注释在骗人，不是台架有问题）：** `sim/run_sim.tcl` 开头声称
`axi_frame_saver.v` / `axi_frame_writer.v` "各自都有台架"——按现名搜只有带后缀的变体有。
这类"文档/注释对不上树"的条目统一记在 `docs/log/ISSUES.md` 的注释精简那一类里处理。
