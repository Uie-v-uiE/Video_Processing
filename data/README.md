# data/ —— 输入向量、参考结果、实测留档与那张指标表

这一层放的是**数据**，不是代码也不是报告正文。四个子目录各有唯一职责，
`metrics.csv` 是全仓唯一的数字表：别的文档要用数，就引用它的行号，不再另立第二份表。

## 1. 四个子目录与它们的责任

下表的文件数是 2026-10-04 用 `find`/`md5sum` 现算的读数（那一列的口径见第 3 节）：

| 子目录 | 文件数 | 放什么 | 谁读它 |
| --- | --- | --- | --- |
| `inputs/` | 8 | 仿真台架（testbench，跑在仿真器里的核对电路，下称台架）与上位机用的**输入向量**（正常帧、全零、随机、截断 299 行、超长 1.5 帧、0 字节、1 像素边界 udp 包） | 由 `data/generated/gen_inputs.mjs` 生成；台架与主机脚本按文件名点用 |
| `golden/` | 14 | **软件侧算出来的参考结果**（旋转 0/30/45/90/180/270、效果链各步 `proc_*.png`、源图 `src.png`、`frame_640x360.mem`） | 人工比对屏上照片；清单在 `data/golden/manifest.md` 与 `data/golden/README.md` |
| `measured/` | 20 | **板子与工具回读的原始留档**（`board_measure_*.txt`、`board_measure_r08.md`、`ddr_dump_20260921_15fps.out.gz`、仲裁 `arb_*`、`lane30_watch.out`、`interp_gain_attribution.txt`） | 报告里的实测数字指回这里；`build/make_submission.sh` 按点名决定是否随包 |
| `generated/` | 1 | 生成上面那些向量的**脚本本身**（不是数据；放这里是因为它和 `inputs/` 同源同版本） | `node data/generated/gen_inputs.mjs` |

## 2. 取舍规则（照着做就能判"这份东西该不该放进 data/"）

1. **能被脚本重算出来的才放这里**。二进制文件只放"重跑一条命令就能得到同样字节"的那些；
   重算不出来的东西（手工截图、屏幕照片）放 `report/figures/`，不放这里。
2. **参考结果要能被重算并且写清容差**。`golden/` 每张图都必须能由脚本重算，
   重算方式与容差写在 `data/golden/manifest.md`；容差口径还没定下来的地方一律标 `【队伍未确认】`，
   不许用"看着差不多"当作黄金结果，也不许因为眼看对得上就把标记去掉。
3. **原始留档与判读结论成对出现**。板子与工具吐出来的原始件放 `measured/`，
   对它的判读写在 `report/` 或 `board/`，两边都要能指到对方。
   判这条的工具是 `node src/host/metric_recheck.mjs`，它专门抓"表里有数、件里没有"这一类。
4. **一张表**。所有指标只进 `data/metrics.csv`（29 行含表头）。
   文档里要引用某个数，写"第 N 行"或者把数抄进叙述句并注明来源行号；
   新建第二份表会让两处数字各自漂移，这是这条规则存在的理由。
5. **每个数都要指得到盘上的一份件**。表里"证据文件"那一列必须是一个真实存在的路径。
   交付前的一致性检查会逐行判这一条：`node build/checks/check_repo_consistency.mjs` 的 C2 行
   就是判"指标数字指得到证据"的，红了说明某个数没有件。

## 3. 这一层怎么自查（四条命令，都能重跑）

```bash
find data/inputs data/golden data/measured data/generated -maxdepth 1 -type f | wc -l
md5sum data/metrics.csv
node src/host/metric_recheck.mjs
node build/checks/check_repo_consistency.mjs
```

- 第一条数出来的总数与上面那张表对不上时，先分清是"工作目录里多了不入库的件"还是"表写错了"：
  文件数那一列记的是**作者工作目录里 `find` 现算的数**。`measured/` 这一格在工作目录里是 20，
  在只含入库文件的检出里数到 15——差额 5 支是不入库的原始抓取件
  （`ddr_dump.out` 与 `health_cur.out`、`health_p0.out`、`health_p1.out`、`health_clr.out` 四支，
   `.gitignore` 第 58、59、68 行把这类名字排除在版本库外）。
  拿到包的人按 15 支核对是对的，不是缺件。
- 第二条打印的是当前这份表的指纹。表内容一改，这串值就变：正文与指标表里出现的
  `md5=7273b71f26ca` 是 `build/evidence/r120_window_check.txt` 第 3 行
  `HEAD data/metrics.csv 7273b71f26ca` 那条记录的原文，用来认"当时随包的是哪一版表"，
  不是当前内容的校验值。要比当前版本，跑第二条命令自己取。
  另注意行尾：换行样式不同的两份同样内容的表会给出不同 md5，跨机器比对要先统一行尾再算。

## 4. 还没做到的两件事

1. `inputs/` 的 8 个向量目前只被生成脚本与个别仿真台架点名，**没有一个统一入口一次跑完八个**。
   这条缺口登记在 `report/90-open-items.md`；补它需要跑一次把八个向量一起跑完的全量仿真，
   到目前为止还没有跑过这样一次。
2. `golden/` 与屏上照片的比对仍是**人工眼看**（`board/signoff.md` 的相应行由人签），
   没有自动的像素级判定。要把它自动化，第一步是先定容差（见第 2 节规则 2），
   容差没定就写脚本，得到的只会是一批说不清为什么不通过的判定。
