# r112 采纳清单（链子在飞时写好，回来直接照着走）

链子：`bash build/r112_chain.sh`（08:18:56 起飞），分步件 `build/r112_build_console.txt`、
`build/r112_lane_after.txt`、`build/r112_tb98_console.txt`、`build/r112_gates.txt`。
两把刀与各自的凭据见 `report/log/ISSUES.md` #250；上电那一度的判定实验见 `board/ACCEPTANCE.md` 的 E6 格。

## 0. 先确认链子活着（别拿 `ps -W` 判，#244）
```
tasklist //FI "IMAGENAME eq vivado.exe" | grep -ac vivado.exe
tasklist //FI "IMAGENAME eq xsim.exe"   | grep -ac xsim.exe
tail -3 build/r112_chain_console.txt
```

## 1. 抓手判读（**先读这个再谈采纳**）
对照基线 = `build/evidence/r110_setup_paths_baseline.rpt`（08:18 钉的，md5 97403628c630）。
判据三条，都要在报告里读得出：
- **同族自己动**：`ip_head_reg[4][18] → check_buffer_reg[17]/D` 这一条的 slack 与 `CARRY4` 数
  （r110：0.713 ns / 10 级 / 6×CARRY4 / route 61.3 %）。位宽 32→20 应当把进位链从 8 个 CARRY4 的容量压到 5 个。
- **归属有没有换族**：r110 的候补是 `rxdata_bus[0].u_iddr_rxd → crc_data_reg[7]/D`（1.062 ns，2 级）
  与同族 `[30]/[31]`（1.071 ns，13 级）。若最差换成别的族，**归属整句重写**，
  并把绝对差按规矩 35 念成"这一族自己动了多少"，不写成"同一条锥变快了"。
- **hold 有没有跟着动**：`build/hold_paths.rpt` 与 `build/timing_summary.rpt` 的 WHS；
  r110 是 0.042 ns 落在 `u_crc_rx/crc_data_reg[17]/C → [25]/D`。

写一条判读件（照 `build/r110_verdict.sh` 的形状，比较两份 baseline，打印 fo 直方图 + 同族两次的 slack/级数）：
`build/r112_verdict.sh`。**没有这份件就不许写首页数字**（规矩：每条结论点名它的件）。

## 2. 资源净账要归到模块（r110 的 −243 就是栽在这一步）
- 预期方向：`icmp_tx` 少 12 个 FF（`check_buffer` 32→20）；`key_debounce` 两只实例各加
  21 位计数 + 1 个 `armed` ⇒ **+44 FF**。净账可能是 **FF 增加**。
- **本轮就补上这一步**（链子里没跑，构建完手动跑一次，只读）：
  `"$V/vivado.bat" -mode batch -source build/tcl/probe_util_hier.tcl`
  —— 它开 `impl_1/system_top_routed.dcp` 跑 `report_utilization -hierarchical -hierarchical_depth 3`，
  并把 `u_reasm / u_icmp / u_osd / u_lm / u_crc_rx` 几行念出来（r110 缺的正是这份件，才只能拿 OOC 说 −66）。
  落 `build/util_hier_probe.rpt`，与 `build/evidence/r110_attrib.txt`（OOC 两腿）一起构成归属。
- 归不到的部分**不写进首页**（#246/#250 同一课）。

## 3. 台架与门禁
- 车道：`build/r112_lane_after.txt` 期望 **30/30** 全绿（`tb_v111_key_boot` 15 条、`tb_v112_tx_bytes` 全等指纹已在
  `build/evidence/r112_tx_bytes_{base,cut}.txt`）。
- 顶层台架：`RESULT tb_v98_top_seam FAIL nfail=1`，FAIL 只许是声明过的 `C5c`；C12 四句按整句读（#239 撞名教训）。
- 门禁：**先 /tmp 再 cp 到 `build/r112_gates.txt`，再跑一遍直到逐字节一致**（#242 第 1 条）。
  项数仍是 24 ⇒ 首页"门禁 24 项 …"那四处（中英各两处）要与盘上那份一致。

## 4. 数字改口（机械 + 手写两遍）
1. `node build/rotate_from_metric.mjs --apply`（机械那一半；它会跳过认不出的形状）
2. `node src/host/metric_recheck.mjs` 列红单，逐条配手写规则，形状照
   `build/r110_rotate_docs.mjs`（每条**断言恰好命中一次**，任一拒 ⇒ 整批不写盘）。
   已知的坑（r110 撞过的）：
   - `27.00 %` 这类"百分数夹在括号里"会被机械改口写成 `26.54.00 %` ⇒ 手写规则里要带括号整段替换；
   - `clkout0_1` 的**余量百分数**（r110 是 18.995 %）机械认不出；
   - `metrics.csv` 里 `14362（27.00 %）` 这种"数+百分数"一格也要整段替换；
   - 身份句（板上这一版/bit）、门禁读数句、代价句、hold 落点半句 = 手写；
   - 若 `report/MODULES.md` 的「例化者」因行位移红：`bash build/reanchor_modules.sh`（它按 D5b 红单自己定位，#250 之后 `key_debounce.v`/`icmp_tx.v` 的行号一定漂）。
3. 收尾三把尺子全绿才算：`metric_recheck` 红 0、`doc_currency` rc=0、`line_cite_check` 硬错 0。

## 5. 采纳一笔 + 上板
- 提交含：`src/rtl/util/key_debounce.v`、`src/rtl/eth/icmp_tx.v`、`sim/tb_v111_key_boot.v`、
  `sim/tb_v112_tx_bytes.v`（+ `sim/tb_v112_ip_csum.v` 要不要留？留，但**不进车道**，#250 记了为什么）、
  `build/system.bit`/`.xsa`、r112 全套报告、文档、`build/evidence/*`。
- 三步链刷板（不设 `VP_BIT`，`build/system.bit` 就是本轮）→ `bash build/board_verify.sh --geom --battery --round=r112`
  （要 `VP_XSDB`，别猜路径）→ 把刷板时刻与新 bit md5 回填首页（`build/r110_fill_flash.mjs` 的形状）→ 第二笔。
- **E6 那一格请队员判**：冷上电 + 不碰键，屏上 `ROT:` 应读 0（r112 之前读 1 属预期）。

## 6. 收尾
试冻结（预期仍被规矩拒，红项 C5c 是声明过的）→ `bash build/make_submission.sh` →
**数盘上** `/d/Xilinx/Prj/pro/final_submission` 的文件数对 MANIFEST（#50：别读导出器的 stdout）→ 推送。

## 不做的事
- 不在链子跑动时碰 `src/rtl`/`sim`（第 15/15b 项会把报告与树对比，会红）；
- 不把两个键的上电行为写成"已彻底查清成因"——#249 的口径是**机理已证、成因未定**，
  能钉死的只有"门吞掉那次事件"（A/A6 腿）与"固件默认不转"（`build/evidence/r111_angle_readback.txt`）。
