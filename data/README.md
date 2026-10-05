# data/ —— 输入向量、参考结果、实测留档与那张指标表

这一层只放**数据**：喂给脚本的输入向量、软件侧算出来的参考结果、板子与工具吐出来的原始读数，
以及全仓唯一的数字表 `metrics.csv`。别的文档要用数就引用它的行号，不再另立第二份表。
构建脚本、尺子、报告正文都不在这里（分别在 `build/`、`src/host/`、`report/`）。

## 1. 四个子目录与它们的责任

下表件数是 2026-10-05 目录精简之后 `find` 现算的，复算命令在第 3 节：

| 子目录 | 文件数 | 放什么 | 谁读它 |
| --- | --- | --- | --- |
| `inputs/` | 8 | **输入向量**（正常帧、全零、随机、截断 299 行、超长 1.5 帧、0 字节、1 像素边界 udp 包） | 由 `data/generated/gen_inputs.mjs` 一条命令重生；实测读者是 `src/host/one_click_test.mjs` 与 `.py`（读 `wordid_512x300.rgb565`），其余 7 份是边界向量，还没有统一入口一次跑完（缺口在第 4 节） |
| `golden/` | 13 | **软件侧算出来的参考结果**：11 张 PNG（旋转 0/30/45/90/180/270、效果链 `proc_*.png`、源图 `src.png`、并排预览 `dual_preview.png`）+ `README.md` + `manifest.md` | **没有任何 `.v`/`.mjs`/`.sh` 读它**，定位是人眼比对的参照物；能不能当参考、容差怎么定，判据写在 `data/golden/README.md` 与 `data/golden/manifest.md` |
| `measured/` | 5 | **板子与工具回读的原始留档**（15fps 那一次的完整输出、仲裁交接的红用例样本、增益归属读数、两份逐轮判读） | 报告里的实测数字指回这里；逐行的证据路径以 `data/metrics.csv` 的"证据文件"列为准（实测：那一列指的是 `build/` 与 `board/` 的件，不指 `data/`，所以这一格是**原始留档**而不是指标表的证据层） |
| `generated/` | 1 | `inputs/` 那 8 份向量的**生成脚本本身**。它不是数据，放这里是因为它与 `inputs/` 同源同版本，删掉它 `inputs/` 就不可重生 | `node data/generated/gen_inputs.mjs --write` |

本轮从这一层清出去的东西（都属"既不是测试数据也不是参考结果"）：`golden/` 那份 640x360 的裸帧
`.mem`（尺寸与本设计 512x300 不符、0 个读者，`golden/README.md` 自己就把它登记成孤儿向量）；
`measured/` 里那份每次跑都会往上追加的运行台账、一份含乱码的串口残片、一份 0 字节的回读、
两个没有任何读者的 `lane30_watch` 现场件（工具本体在 `src/host/lane30_watch.mjs`）、
一份 460 KB 的 DDR bank 原始抓取（那是构建凭据不是输入数据，同类抓取由 `.gitignore` 挡在库外），
以及两份没有一处指路的判读残篇。判据与逐条理由见第 5 节。

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

- 第一条数出来的总数与上面那张表对不上时，先分清是"工作目录里多了不入库的件"还是"表写错了"。
  本轮之后 `find data -type f | wc -l` = 29，`git ls-files data | wc -l` 也数到同一批
  （`.gitignore` 挡的那几支原始抓取件（`ddr_dump.out` 与四支 `health_*.out`）已经从工作目录里删掉，
  不再产生差额）。核对用这两条：`find data -type f | wc -l`、`git ls-files data | wc -l`。
- 第二条打印的是当前这份表的指纹。表内容一改，这串值就变：正文与指标表里出现的
  `md5=7273b71f26ca` 是 `build/evidence/r120_window_check.txt` 第 3 行
  `HEAD data/metrics.csv 7273b71f26ca` 那条记录的原文，用来认"当时随包的是哪一版表"，
  不是当前内容的校验值。要比当前版本，跑第二条命令自己取。
  另注意行尾：换行样式不同的两份同样内容的表会给出不同 md5，跨机器比对要先统一行尾再算。

## 4. 还没做到的两件事

1. `inputs/` 的 8 个向量目前只被生成脚本与个别仿真台架点名，**没有一个统一入口一次跑完八个**。
   这条缺口登记在 `report/90-open-items.md`；补它需要跑一次把八个向量一起跑完的全量仿真，
   到目前为止还没有跑过这样一次。
2. `golden/` 与屏上照片的比对仍是**人工眼看**（签字记在板级验收那一层，见 `board/README.md`），
   没有自动的像素级判定。要把它自动化，第一步是先定容差（见第 2 节规则 2），
   容差没定就写脚本，得到的只会是一批说不清为什么不通过的判定。

## 5. 本轮删除清单（每支都给"为什么不算测试数据也不算参考结果"）

| 件 | 判据 |
|---|---|
| `golden/frame_640x360.mem` | 尺寸 640x360 与设计 512x300 不符；全仓 0 个读者；`golden/README.md` 第二条出路本来就叫"从提交包里去掉" |
| `measured/arb_handover_last.json` | 运行台账：`src/host/arb_handover_test.mjs` 每跑一次往上追加一条，它不是某一次测量的结果而是历史累加；原始判据在 `build/evidence/` |
| `measured/arb_uart.txt` | 串口残片，含乱码，0 处指路 |
| `measured/arb_gpio0.out` | 0 字节 |
| `measured/arb_r32_run1.txt` | 一次跑的现场，0 处指路；同一次跑的判读已在 `build/frozen_r32_sdfix/` |
| `measured/sender_during_sd.txt` | 0 处指路 |
| `measured/lane30_watch.out`、`measured/lane30_watch.tcl` | 一次打点的现场与它的驱动脚本；工具本体是 `src/host/lane30_watch.mjs`，脚本不该住在这一层 |
| `measured/ddr_dump_20260921_15fps.out.gz` | 460 KB 的 bank 原始抓取，只有 `src/host/ddr_stale.mjs` 能读；它与 `.gitignore` 挡住 `ddr_dump.out` 是同一条口径（原始抓取属凭据，不属数据层）。判读表本身留在 `measured/README.md` |
| `measured/board_measure_r06_r07.md`、`measured/board_measure_r09.md` | 判读文档不是数据，且全仓 0 处指路（同一批读数在 `report/measurements.md` 里已有）；`board_measure_r08.md` **留着**，因为交付文档按名字引它当凭据 |
