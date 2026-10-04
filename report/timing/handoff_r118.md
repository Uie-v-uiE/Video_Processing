# r118 早间交接：已经落定的、还差的、以及一条命令就能接上的下一步

## 一、已经 verified（都有件）

* **板上跑的是 r118**：`build/evidence/r118_board/board_now.txt` — 2026-10-04 04:49:50 三步 JTAG 链刷入，
  `bit_cycle rc=0`、`board_verify --geom --battery --round=r118` **rc=0**；位流身份 `cd04907e1369`
  （`build/evidence/r118_bit/` 存了 bit 与 xsa）。
* **r118 只带一刀**：`IDELAY_VALUE` 26→31（r116 在已布线 DCP 上扫满 0…31 量出来的收口眼心，眼心余量 +0.315 ns，
  件 `build/evidence/r115_window/probe3_console.txt`）。
* **B1 严格名册判据 = GREEN**：`build/evidence/r118_strict_b1.txt` — 8 对（4 域 × setup/hold）**逐格与 r114 逐位相同**
  （`eth_rxc` 0.739 / 0.052、`clk_fpga_0` 1.850 / 0.053、`clkout0_1` 3.630 / 0.059、`sys_clk` 14.876 / 0.222）。
  ⇒ 这一刀在片内是**可证明中性**的；它的收益只在片外到达窗，不写成 WNS 收益（规矩 35）。
* **r117 官方名册的实测判负**：`build/r117_verdict_declined.txt` — C9 复制那根 239 引脚广播网机制成立
  （239→1 引脚、10 颗 replica）且 `clk_fpga_0` 1.850→2.104，但 `clkout0_1` / `sys_clk` / `eth_rxc` setup 与
  `eth_rxc` hold 四格一起跌 ⇒ 预登记的严格判据不过，按 H7 回滚；钩子与数都留在树里。
* **RGMII 输入窗退回候选件**：`src/constraints/r116_rgmii_input_window.xdc`，默认不加载，
  `VP_R116_IO_WINDOW=1` 复现；绑窗时 4 条发布硬门红的原因与证明留在 `report/timing_global.md` 第 6/9 节。
* 全局逐域"到极限"的判定与代价面：`report/timing_global.md` 第 6、7、9 节；`report/timing/round_r117.md`、
  `report/timing/round_r118.md`。工具账 `report/log/issues.md` #325–#330。

## 二、还差的（三项，都不是设计问题，是我这边的管道）

1. **首页/英文首页/`data/metrics.csv` 的逐时钟数字还没换成 r118 那一版**。现在这两行末尾各挂了一句
   "同步状态声明"（README.md:56、readme.en.md:70），明写板上是 r118、本行数仍属 r116 的件 —— 这是**准确的红**：
   `metric_recheck` / `doc_currency` 会照实判红（已推的提交 `b5a774b`）。
2. **改口之后的最终门禁两跑**（B4 的最后一条）与**提交包重导**没跑完。
3. 一个未落地的小修：`build/r118_rotate.py` 的"尺子输出文件"用了 `/tmp/kx/...`，
   而 **MSYS 的 /tmp ≠ Python 的 /tmp**（#330 第 3 条）⇒ 它把"读不到自己的尺子文件"报成"尺子没过"。
   修法就一行：把那两个 `> /tmp/kx/...` 改成仓库内目录（`build/evidence/r118_board/`）。

## 三、一条命令接上（顺序不能换）

```bash
cd "$(git rev-parse --show-toplevel)"   # 仓库根，不写死本机路径
# 1) 把 rotate 里两处 shell 输出目录从 /tmp/kx 换成 build/evidence/r118_board，然后：
VP_CLAIM=24,23,1 python build/r118_rotate.py      # 改口 + 三道尺子，过了才落 build/r117_docrotated.marker
bash build/gates.sh > /tmp/kx/g1.txt 2>&1; bash build/gates.sh > /tmp/kx/g2.txt 2>&1
cmp -s /tmp/kx/g1.txt /tmp/kx/g2.txt && cp -f /tmp/kx/g1.txt build/r118_gates_final.txt
grep -c " PASS$\| FAIL$" build/r118_gates_final.txt   # 期望 23 绿 / 1 红（唯一红 = 声明过的 C5c）
bash build/make_submission.sh                          # 重导提交包；按盘上文件数核，不读它的 stdout
python build/r118_commit.py && git push origin main    # 提交 + 推送（信息从件里读，不手抄）
```

如果第 1 步的尺子还报"解析到 5/10 行"，那是 `README.md` 被写坏的形状信号（#329/#330 同一个 bug 家族），
先 `git checkout -- README.md readme.en.md data/metrics.csv` 回到 `b5a774b`，再只走 `r118_rotate.py` 这一支改口。

## 四、只有你能做的两条（机器判不了）

* **E6 眼睛判**：冷上电读键值那条，要在 r118 上重判（`board/acceptance.md` 第 93/98 行已经写成"待队员在 r118 上重判"）。
* **演示默认位**与那 6 个输出端口（`led[0..1]`、`tmds_*`）的债：要么给一份可引用的 DVI/HDMI 接收窗数，
  要么你批准"不检查"（那是放宽，要进松动台账）。本机与在线都查过，没有可引用的一页
  （凭据 `build/evidence/r117/dvi_guide_scan.txt`）。


## 五、05:04 的实况：最终门禁跑到了，但撞在我自己造的"自指死锁"上（不是设计红）

`build/r118_tail3.sh` 跑完两跑门禁：**`metric_recheck 红=0`**（说明 r118 首页改口的数是对的、也解析满 10/10 行），
但门禁仍判"有红项"，于是按脚本的硬停把首页三件套 `git checkout` 回去了（现在盘上 = 提交 `0b10e7e` 的状态：
板侧已写明 r118，首页数字仍标着"属 r116 那一次的件"）。

原因是一条**自指**：`doc_currency` 的 D1c 层拿"盘上最新的 `rNN_gates.txt`"当基准去核对首页那句
"门禁 24 项 23 绿 / 1 红"，而首页引用的那一份在这一刻还是**改口之前**的 21 绿 / 3 红（其中 2 条正是文档时效本身）；
只有先把这一跑定稿成 `build/r118_gates.txt`、让 D1c 有个能吻合的基准，红数才会真的回到 1。
⇒ 修法（下次照做，别改判据）：**两跑之后再定版跑第三跑** ——
`bash build/gates.sh > /tmp/kx/fC.txt 2>&1; cp -f /tmp/kx/fC.txt build/r118_gates.txt` 之后再跑一次核对：
第二次的红项应当只剩声明过的 `C5c`（`grep -c ' FAIL$'` == 1），这时才提交首页、重导包、推送。
顺序必须是"先落一份能吻合的门禁件，再要求首页与它吻合"，否则这条判据永远把自己判红。


## 六、06:07 的确切终态（工作树已改口、未提交；差一个正则的粗体容忍）

* 首页三件套在**工作树里已经是 r118 的官方读数**（`metric_recheck 红=0`、解析 10/10 行；
  `doc_currency` 自己打印 **CURRENCY: 干净**）。**没有提交**，因为发布门禁的第 18 项仍判红 ——
  而它红的原因不是数字不对，是 D1b 那层的**射程地板**：`抓到 0 句板态身份句（地板 2）`。
  D1b 在 `NOW_MARK` 之后用 `ADJ_RNN` 取"紧邻的轮号"，而首页写的是
  `板上现在跑的是 **r118**`（粗体星号夹在标记与轮号之间）⇒ 取不到编号 ⇒ 那句身份句不计入。
  同一条句式的英文行 `the board now runs **r118**` 一样取不到。
* 所以现在的选择只有两个，我选了第一个并停下来：
  ① 不放宽判据、不提交未核过的首页（当前状态）；
  ② 下一步一行改尺子：让 `ADJ_RNN` 允许 `\*{0,2}` 前缀（或在首页身份句里去掉那对粗体），
     然后 `VP_CLAIM=24,23,1 python build/r118_rotate.py` → 定版 cp → 两跑核对，
     期望 **23 绿 / 1 红**（唯一红 = 声明过的 `C5c`），再 `bash build/make_submission.sh`
     与 `python build/r118_commit.py && git push`。
* 别把这条当成"门禁松一下就能过"：改的是**正则对 Markdown 粗体的容忍度**，改完 D1b 仍然会抓到 2 句并逐句核对轮号；
  #325 那一族的教训正是"形状变了 = 尺子断"，所以这里要修的是形状识别，而不是把地板 2 调小。

## 七、06:17 收口完成

身份句去掉粗体后 D1b 抓到 2 句、D1c 抓到 2 句且与门禁件吻合：
`doc_currency` = **CURRENCY: 干净**，`build/gates.sh` 定版两跑 = **23 绿 / 1 红**（唯一红 = 声明过的 `C5c`）且逐字节一致
（件 `build/r118_gates.txt`、`build/r118_gates_final.txt`），首页/英文首页/`metrics.csv` 已是 r118 的官方读数，提交包重导。
账记 `report/log/issues.md` #331。


## 八、07:5x–08:1x 的终态（E6 已由人眼判过；顺带把"位流从来没进过 git"这件事补上）

* **E6 判了**：队员 2026-10-04 07:5x，冷上电（断电 ≥10 s）+ 只跑三步 JTAG 链 + 全程不碰 KEY1/KEY2，屏第二行 `ROT:` 读 **0**（原话「0度」）。
  件 `build/evidence/r118_eyes/`（`state.txt` 汇总三步 rc 与身份行、`step1_boot.txt` 的 `DDR_ECHO 5A5AA5A5`、`step2_program_pl.txt` 的 `PROGRAMMED …`、`step3_app.txt` 的 `DOW: ok`、`uart_stat.txt` 的 `[STAT] … osd=1`）。
  对照那一半（按住 KEY1 到链跑完应读 1）**仍未做**，登记为"未判"，需要再断一次电。
* **板上一步的坑**：07:39 那一次 `ps_jtag_boot.tcl` 死在 `targets -set 1`（`tid2ctx`）——冷上电后 hw_server 还没重新枚举链路。等它枚举成 `1=APU / 2=ARM#0 / 3=ARM#1 / 4=xc7z020`，**脚本一字未改就过了**（只读探针 `build/tcl/probe_target_select.tcl`，五种选择写法全 rc=0）。下次遇到"冷上电后第一步就 REFUSE"，先重连一次看枚举表。
* **一处身份债补上了（ISSUES #332）**：`git show HEAD:build/system.bit | md5sum` 量出来 HEAD 里那块还是 **r116 的 `bb2fb707aebc`** —— r118 那两支提交只带了文档，bit / xsa / `build/*.rpt` / `build/report/` / `build/tb_v98_report.txt` 全悬在工作区。
  根因三条都写在 #332 里（路径清单写了不存在的 `report/acceptance.md` ⇒ `git add` 原子失败只暂存 4 条 ⇒ 打印子进程输出时又踩 cp936 解码崩溃）。
  **本节之后的规矩**：提交完必须**读回 HEAD** 验位流身份，不许只读工作区。
* **另一处工具账（ISSUES #333）**：我为追加 #332 留的那份 `ISSUES_before332.md` 备份被 D5 当成交付文档扫，连带把 D1c 也拖红（23/1 → 21/3）。备份证明成"纯前缀"之后删掉；纪律是**快照不要落成仓库里的 `.md`**。
* **门禁的实际形状（件 `build/evidence/r118_board/`）**：`g1b` 22 绿/2 红（基准件是旧的）→ 删备份 → `g1c` 22 绿/2 红（D1c 仍读着旧基准）→ 定版 → **`g2c`/`g3c` 23 绿/1 红且逐字节一致**（唯一红 = 声明过的 `C5c`，`build/tb_v98_report.txt` 里那条 `FAIL C5c …` + `RESULT tb_v98_top_seam FAIL nfail=1`），`doc_currency` 打印 **CURRENCY: 干净**。
* **交付侧**：首页三件套已是 r118 的官方读数，并且**这次位流与实现报告一起进 git**（身份由 `git show HEAD:build/system.bit | md5sum` 读回验证，件 `build/evidence/r118_eyes/head_bit_md5.txt`）；提交包按 #332 的规矩在提交之后重导。
