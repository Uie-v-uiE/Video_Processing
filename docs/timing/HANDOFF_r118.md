# r118 早间交接：已经落定的、还差的、以及一条命令就能接上的下一步

## 一、已经 verified（都有件）

* **板上跑的是 r118**：`build/evidence/r118_board/BOARD_NOW.txt` — 2026-10-04 04:49:50 三步 JTAG 链刷入，
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
  `VP_R116_IO_WINDOW=1` 复现；绑窗时 4 条发布硬门红的原因与证明留在 `report/TIMING_GLOBAL.md` 第 6/9 节。
* 全局逐域"到极限"的判定与代价面：`report/TIMING_GLOBAL.md` 第 6、7、9 节；`docs/timing/ROUND_r117.md`、
  `docs/timing/ROUND_r118.md`。工具账 `report/log/ISSUES.md` #325–#330。

## 二、还差的（三项，都不是设计问题，是我这边的管道）

1. **首页/英文首页/`data/metrics.csv` 的逐时钟数字还没换成 r118 那一版**。现在这两行末尾各挂了一句
   "同步状态声明"（README.md:56、README.en.md:70），明写板上是 r118、本行数仍属 r116 的件 —— 这是**准确的红**：
   `metric_recheck` / `doc_currency` 会照实判红（已推的提交 `b5a774b`）。
2. **改口之后的最终门禁两跑**（B4 的最后一条）与**提交包重导**没跑完。
3. 一个未落地的小修：`build/r118_rotate.py` 的"尺子输出文件"用了 `/tmp/kx/...`，
   而 **MSYS 的 /tmp ≠ Python 的 /tmp**（#330 第 3 条）⇒ 它把"读不到自己的尺子文件"报成"尺子没过"。
   修法就一行：把那两个 `> /tmp/kx/...` 改成仓库内目录（`build/evidence/r118_board/`）。

## 三、一条命令接上（顺序不能换）

```bash
cd /d/Xilinx/Prj/pro/Video_Processing
# 1) 把 rotate 里两处 shell 输出目录从 /tmp/kx 换成 build/evidence/r118_board，然后：
VP_CLAIM=24,23,1 python build/r118_rotate.py      # 改口 + 三道尺子，过了才落 build/r117_docrotated.marker
bash build/gates.sh > /tmp/kx/g1.txt 2>&1; bash build/gates.sh > /tmp/kx/g2.txt 2>&1
cmp -s /tmp/kx/g1.txt /tmp/kx/g2.txt && cp -f /tmp/kx/g1.txt build/r118_gates_final.txt
grep -c " PASS$\| FAIL$" build/r118_gates_final.txt   # 期望 23 绿 / 1 红（唯一红 = 声明过的 C5c）
bash build/make_submission.sh                          # 重导提交包；按盘上文件数核，不读它的 stdout
python build/r118_commit.py && git push origin main    # 提交 + 推送（信息从件里读，不手抄）
```

如果第 1 步的尺子还报"解析到 5/10 行"，那是 `README.md` 被写坏的形状信号（#329/#330 同一个 bug 家族），
先 `git checkout -- README.md README.en.md data/metrics.csv` 回到 `b5a774b`，再只走 `r118_rotate.py` 这一支改口。

## 四、只有你能做的两条（机器判不了）

* **E6 眼睛判**：冷上电读键值那条，要在 r118 上重判（`board/ACCEPTANCE.md` 第 93/98 行已经写成"待队员在 r118 上重判"）。
* **演示默认位**与那 6 个输出端口（`led[0..1]`、`tmds_*`）的债：要么给一份可引用的 DVI/HDMI 接收窗数，
  要么你批准"不检查"（那是放宽，要进松动台账）。本机与在线都查过，没有可引用的一页
  （凭据 `build/evidence/r117/dvi_guide_scan.txt`）。
