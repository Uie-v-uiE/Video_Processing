# data/ — 输入向量、参考结果、实测留档与那张指标表

这一层放的是**数据**，不是代码也不是报告正文。四个子目录各有唯一职责，
`metrics.csv` 是全仓唯一的数字表。文件数与哈希为 2026-10-04 本轮现算（`find`/`md5sum`）：

| 子目录 | 文件数 | 放什么 | 谁读它 |
| --- | --- | --- | --- |
| `inputs/` | 8 | 台架与上位机用的**输入向量**（正常帧、全零、随机、截断 299 行、超长 1.5 帧、0 字节、1 像素边界 udp 包） | 由 `data/generated/gen_inputs.mjs` 生成；台架/主机脚本按文件名点用 |
| `golden/` | 14 | **软件侧算出来的参考结果**（旋转 0/30/45/90/180/270、效果链各步 `proc_*.png`、源图 `src.png`、`frame_640x360.mem`） | 人工比对屏上照片；清单在 `golden/manifest.md` 与 `golden/README.md` |
| `measured/` | 20 | **板子/工具回读的原始留档**（`board_measure_*.txt`、`ddr_dump*.out(.gz)`、仲裁 `arb_*`、健康计数 `health_clr.out`） | 报告里的实测数字指回这里；`build/make_submission.sh` 按点名决定是否随包 |
| `generated/` | 1 | 生成上面那些向量的**脚本本身**（不是数据；放这里是因为它和 `inputs/` 同源同版本） | `node data/generated/gen_inputs.mjs` |

## 规矩（与仓库其它层一致）

1. **参考结果不许"看着差不多"就当黄金**：`golden/` 的每一张图都必须能由脚本重算，
   重算方式与容差写在 `golden/manifest.md`；容差口径未经队伍确认的地方一律标 `【队伍未确认】`。
2. **实测件与判读件成对**：`measured/` 里放原始输出，判读结论写在 `report/` 或 `board/`，
   两边都要能指到对方（`node src/host/metric_recheck.mjs` 会抓"表里有数、件里没有"的那一类）。
3. `metrics.csv`（29 行含表头，`md5=7273b71f26ca`）是**唯一**那张指标表。
   别的文档只引用它的行号或把数抄成叙述文字，不再另立第二份表。
   每一行的"证据文件"列必须指到盘上真实存在的件——终审 C2 就是判这个的
   （`node scripts/check_repo_consistency.mjs` 的 C2 行）。
4. 二进制只放**能被脚本重算出来**的那些；手工截图放 `report/figures/`，不放这里。

## 这一轮没做的事（不装作做了）

- `inputs/` 的 8 个向量目前只被生成脚本与个别台架点名；**没有一个统一入口一次跑完八个**，
  这条缺口记在 `report/90-open-items.md`，补它需要一轮仿真（本轮被禁止跑仿真）。
- `golden/` 与屏上照片的比对仍是**人工眼看**（`board/signoff.md` 的相应行由人签），
  没有自动像素级判据；若有队伍想把它自动化，先要定容差（见规矩 1）。
