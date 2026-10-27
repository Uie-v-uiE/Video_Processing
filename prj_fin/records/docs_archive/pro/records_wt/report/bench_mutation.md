# 台架怎么被跑起来，以及"改前必须红"怎么做

写法与判据为什么要能红：`skills/pitfalls/ruler-fake-greens/SKILL.md`；
台架清单本身（文件名 → 被测模块 → 功能 → 预期结果）由 `node build/gen_sim_readme.mjs --apply`
从每支 `sim/tb_*.v` 的三段头注释生成，落在 `sim/README.md`，那一页只有表格与运行命令。

## "改前必须红"的两个入口（都不许动工作树）

一条判据说自己抓住了某个缺陷，唯一的凭据是**把那个缺陷装回去，它必须变红**。本仓有两个入口：

- `bash build/sim/mut_control.sh <tb名> <判据名>`：机械装回**已修好的那一刀**（#103 的 C10f 就是这么补上凭据的）。
  它把整个 `src/rtl` 复制到 `/tmp` 下的副本里，用固定的几条 `sed` 还原改前的延迟线写法，
  **diff 必须恰好是那几行**否则直接退出；然后只编译"变异体 + 目标台架"，断言指定的那条判据变红。
  因为它不动 `src/rtl`，所以在跑的构建与台架报告的 `rtl_md5` 都不会被作废——这是它存在的理由。
- 判据**自己**的反例：台架/检查器自带的 `--self` 或 `*_gate_ce.sh`
  （`bash build/rim_gate_ce.sh`、`bash build/tb98_gate_ce.sh`、`node src/host/ps_hb_check.mjs --self`、
  `node src/host/doc_enc_check.mjs --self`）。要求是"每条故意坏掉的输入**只**红在它对应那一格"，
  并且**必须有一条正对照是绿的**——不然一个"永远红"的判据会被误当成有牙。

执行过的记录在 `report/log/issues.md`：#103（C10f 红→绿一对）、#124（E1/E2 的 drop 两条红在 134/32、201/48，
ep 两条仍绿）、#93（C9 族）、#102（边缘条带四条圈）。

## 跑法

两个入口，都是**通配符收全部** `sim/tb_*.v`：

- `build/sim/run_sim.tcl` —— L1 全量批跑；
- `build/sim/run_one.sh <tb名>` —— 单跑一个。它在**编译之前**给顶层 / 台架 / RTL 盖三枚 md5，
  并且如果发现已经有 xsim 活着就直接退出（两个 xsim 会往同一个 `run.log` 里写）。

所以"某个台架忘了接进流水线"这件事不存在；反过来，**放一个坏台架在目录里，每次批跑都会被它拖住**。
门禁里另有两项是**钉 md5** 的（按台架名在 `build/gates.sh` 里搜得到）：
`tb_v98_top_seam`（唯一例化整个视频顶层的那把尺子）与 `tb_edge_rim`（边缘条带）。
改了任何 RTL，这两份报告必须重出，否则门禁会判"报告来自另一份代码"。

## 去留口径（清点结论，文件已在树里）

**保留，即使看着多余：**

- `tb_v5_saver` 等测"当前没有被任何顶层例化的老 RTL"的台架——它们是 DDR 写包器改动的**复验工具**，
  不是摆设（`axi_frame_saver_burst.v` 等文件也留在树里等这个用途）。
- 纯软件模型那一组（`tb_bilin_lerp`、`tb_crc32`、`tb_uart_decode_bits`、`tb_v50_rowmath`、
  `tb_v571_allow_lead`、`tb_sync_fifo`、`tb_tap_sched`）：判据便宜、能锁算法行为，留着。

**必须修的（是注释在骗人，不是台架有问题）：** `build/sim/run_sim.tcl` 开头声称
`axi_frame_saver.v` / `axi_frame_writer.v` "各自都有台架"——按现名搜只有带后缀的变体有。
这类"文档/注释对不上树"的条目统一记在 `report/log/issues.md` 的注释精简那一类里处理。
