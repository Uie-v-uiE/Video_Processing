# `report/figures/` 图例与核对口径（P18a）

本目录只有两份图，都是**纯文本正本**（不是从别处导出的第二次抄写）：

| 文件 | 层次 | 内容 |
|---|---|---|
| `fig-01-system-level.txt` | 系统级 | 芯片内 5 只实例 + PS 固件 + 片外边界，24 条边 |
| `fig-02-module-level.txt` | 模块级 | `u_eth` 的 14 只实例与 `u_pl` 的 32 只实例，逐条边带信号名与出处行 |

## 1. 为什么是纯文本、不是 `.mmd`/`.dot`/图片

- 本机没有渲染器：`which mmdc`、`which dot` 都返回"no mmdc / no dot"（2026-10-04 实测，2026-10-05 复跑仍未命中）。
  ⇒ **导出的 PNG/SVG 没有产出**，登记在 未决项集中表 的第 267 项（状态 `NOT_MEASURED`），不用"应当能渲染"糊过去。
- 文本正本的三条好处在这里可判：能被 `grep`/`diff` 直接检查（第 4 节的两条命令就是门禁式核对）、
  每行一个节点或一条边（改动可逐行 review）、不引入"图与文各自漂"的第二份真值。
- 迁移到别的题目：只有"节点名与出处行"这一列要换；图例（第 2、3 节）与核对命令是通用的。

## 2. 节点（框）的口径

| 记法 | 含义 | 硬要求 |
|---|---|---|
| `+------+` 实线框 | 本仓库 RTL 里**真实存在的实例** | 框名 = 实例名（`u_xxx`）；能在 `src/rtl/` grep 到 |
| `.-=-=-=-.` 虚线框 | **片外**东西（PHY、面板、DDR 颗粒、PC 上位机、板载晶振/按键） | 框名 = `system_top` 的顶层端口名，或 `src/host/`、`src/ps/` 下真实存在的文件名 |
| `(FW)` 标记 | 跑在 PS7 上的固件源文件 | 框名是源文件名；图中它只表示"源码里有这个东西"，不表示"板上的行为已实测"。黑名单 `src/ps/**`（时序专章 第 19 行）给的半数"本机无 `arm-none-eabi-gcc`"**不成立**：编译器在位、`node 仓库里的 ps_app.mjs（工具，不随包）` 编译链接成功（凭据 `board/output/1005_ps_app_rebuild.txt`，重建件与在板那颗的 md5/section 差异记在该件里），只是那颗与在板的 `d0b07f84a068…` 不是同一颗、未上板复验 ⇒ "不许用板级口吻汇报"这条照旧成立 |
| `INT` / `EXT` | 节点表里的 kind 列：片内 / 片外 | — |

三条不许：
- 不许画"理想架构"：现役综合树里没被例化的模块（13 个，清单口径见 `仓库里的 orphan_rtl.sh（工具，不随包）` 的说明段与
  模块清单 第 1 节）**不进框图**，只在 `fig-01-system-level.txt` 末尾"未画进图的东西"一节里点名列出。
- 不许用模块名当框名：一个模块可能有多只实例（`key_debounce` 有 `u_k1`/`u_k2`，`snap_cross` 全工程五只），
  只有实例名能对到线上。
- 不许把未实现的功能写进图或承担"设计原理"那一格的 架构章（装配位 `20-principle.md` 未写）。两张图的 grep 未命中数 = 0（第 4 节，2026-10-04 与 2026-10-05 两次实跑同为 0）。

## 3. 边（连线）的图例

边表每一行的最后一列是**型**，取值四个，ASCII 骨架里用不同箭头：

| 型 | 箭头（骨架里） | 含义 | 位宽写法 |
|---|---|---|---|
| `D` | `==>` | **数据流**：像素/包字节/AXI 载荷这类随事务走的数 | `name[位宽-1:0]`，例如 `cdc_data[35:0]` |
| `C` | `-->` | **控制/命令流**：使能、阈值、模式码、**翻转位**（toggle） | 单 bit 不写位宽；总线写 `split_ctl[18:0]` |
| `K` | `~~>` | **时钟或复位**：`fclk0`、`eth_gmii_clk`、`eth_rst_n` | 不带位宽 |
| `X` / `◆` | 标在边的型列里 | **跨时钟域点**：这条边两侧不是同一个时钟，必须写明靠哪一种形态过 | 与上同 |

- 方向约定：**箭头指数据/命令的去处**，不指物理走线方向；双向的（如 AXI 的 `aw/w/b`）合并成一条 `D` 边，
  并在信号名里把三通道都列出来。
- 每一个 `◆` 都必须能在边表的"出处"里找到那只跨域器件（`dc_fifo`、`snap_cross`、`effect_ctrl`、
  `ps_publish`、`zoom_snap`、`frame_commit_lock` 的 abort 翻转位等）。
  跨域点的**全表**（哪两侧、什么形态、约束在哪一行）在本地学习文档《时钟与复位》那一章（这一层不随包），
  本目录不复制那张表（复制两份一定会漂）。
- 时钟树的形状不在图里用"点线"细画：本设计只有 5 个域（`sys_clk`/`clk_pix`/`clk_pix5x`/`axi_clk`/`eth_rxc`），
  在节点表的"域"列直接标；域的定义在 架构章 第 2 节那张表。

## 4. 核对命令（两条，逐张图各一条，2026-10-04 实跑、2026-10-05 复跑）

**核对 1：框名必须能在 `src/` grep 到**（实例名，逐只数命中行数）

```bash
cd "$(git rev-parse --show-toplevel)"   # 仓库根，不写死本机路径
for n in u_rgmii u_rx_mac u_rx_par u_reasm u_cdc u_saver u_commit u_lm u_ctrl u_udp_tx \
         u_crc_tx u_arp u_icmp u_icmp_fifo; do
    printf "%-14s hits=%s\n" "$n" "$(grep -rn --include=*.v -w "$n" src/rtl | wc -l)"
done
for n in u_clk u_k1 u_k2 u_k1l u_mode u_ang u_eff u_t u_zfit u_zctrl u_zmap u_arb u_cmt \
         u_row u_pub u_life u_lat u_zsnap u_zoom_axi u_aw u_bilin u_bar u_raw u_pipe \
         u_split_x u_split_ctrl u_seam_src u_split u_fpsr u_lat_x u_osd u_dvi; do
    printf "%-14s hits=%s\n" "$n" "$(grep -rn --include=*.v -w "$n" src/rtl | wc -l)"
done
```

实跑结果（2026-10-04；2026-10-05 复跑同值）：46 只实例**全部命中 ≥1 行**，`MISS_TOTAL=0 / 46`。
命中数最小的那几只（`u_crc_tx`、`u_arp`、`u_icmp`、`u_zfit` 等 = 1 行）都是"只在例化处出现一次"的合法形状。

系统级图的 14 个节点用同一条命令（`-F` 匹配，扫 `src/` 全树数命中文件数）：

```bash
for n in u_bd u_idelay_clkgen u_eth u_lm_axi u_pl main.c sd_play.c video_sender.py \
         health_read.mjs eth_rxc DDR_dq tmds_clk_p key1_n sys_clk; do
    printf "%-18s hits=%s\n" "$n" "$(grep -rl --include=* -F "$n" src/ | wc -l)"
done
```

实跑结果（2026-10-04；2026-10-05 复跑同值）：14/14 命中 ≥1 个文件（`DDR_dq` = 1，因为它只出现在 `src/rtl/top/system_top.v` 的端口与连线里）。

**核对 2：出处行必须真的写着那条边说的东西**（行号锚点，门禁第 20 项的口径）

```bash
node src/host/line_cite_check.mjs          # 交付文档里的 `文件:行` 引用
node src/host/doc_enc_check.mjs            # 手写文档的编码（本目录的 .txt 不在扫描扩展名里）
```

跑法与期望输出见 `report/70-reproduce.md`；本目录两份 `.txt` 不含 `.md` 扩展名，
所以它们里面的引用**不被**第 20 项自动核对 ⇒ 尚未写的那一章（第 20 章·设计原理）与
声明与凭据对照（这两份是 `.md`）里重复引用时会被扫到，因此每条锚点都逐条实读回原行。
诚实的口径：**`.txt` 图正本里的行号是逐条 `sed -n 'Np'` 读出来的，但没有机器门禁长期盯着它们**，
这一条只记在本节，未登记进 问队伍清单（2026-10-05 读该文件，里面没有这一条）；D5 的扩展名表只有 `.v`/`.c`/`.h`/`.mjs`/`.sh`/`.tcl`/`.ps1`，不含 `.txt`（`src/host/line_cite_check.mjs` 第 40 行）。

## 5. 复现一份可读的图（不给"应当可以"的承诺）

| 想要的产物 | 本机能不能出 | 依据 |
|---|---|---|
| 直接读（终端/编辑器） | 能 | 两份正本就是 ASCII，无需工具 |
| Mermaid/Graphviz 渲染成 PNG/SVG | **不能**（`NOT_MEASURED`） | 本机无 `mmdc`、无 `dot`（`which` 实测无输出，2026-10-05 复跑同结论） |
| 由 `src/rtl` 自动重画这张图 | 不能，且没做 | 仓里没有"从 RTL 生成图"的脚本（2026-10-05 在 `build/`、`src/` 下按 `fig`/`draw`/`render` 找，零命中）；写图与读图都靠人 + 第 4 节的 grep 核对 |
