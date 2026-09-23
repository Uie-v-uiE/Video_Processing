# S15 · 位流/报告"成套"与门禁新鲜度：门禁全绿也可能读的是上一版

类别：**校验脚本 + 踩坑清单**（对应指南 §3.3.5.2 里"检查资源与时序、验证工程可复现性的脚本"）

## 适用场景

任何"构建产物 + 报告 + 固件"要一起交付、并且要能回答"这个数是哪一次构建出来的"的 FPGA 工程。
本仓库的实现是 `build/gates.sh`（一条命令读七项门禁并比阈值）+ 每套产物的 `MANIFEST`。

**不适用**：只跑一次、不留历史、也不需要复现的探索性实验。

## 触发这条的真实事故（两次，同一天）

1. 构建**还在跑**的时候念门禁：脚本读的是磁盘上现成的 `*.rpt`，于是念到的是**上一版**的数字，
   七项全绿、与上一版一字不差。差一步就把上一版当成交付。
   （现场：`WNS 0.572 / LUT 7454 / 端点 23682` 那组数出现两次，第二次构建其实还没写报告。）
2. 回归日志按"第 32 轮"命名，而**中午那一轮已经用过这个名字** ⇒ 直接覆盖了一份历史证据。
   能恢复只是因为仓库恰好把日志入库了，**不是流程保证的**。

## 两条规矩（照抄可用）

### 规矩一：门禁脚本必须自报"这套产物是不是同一批"

一次构建里 bit 先写、报告后写，只差几十秒 ⇒ 判据是"相差超过 10 分钟就当它不是一套"：

```bash
bit="$D/system.bit"
age=$(( $(stat -c %Y "$T") - $(stat -c %Y "$bit") )); [ "$age" -lt 0 ] && age=$(( -age ))
echo "新鲜度：system.bit $(stat -c %y "$bit" | cut -c1-19) / timing $(stat -c %y "$T" | cut -c1-19)"
[ "$age" -le 600 ] || echo "        WARN 两者相差 $((age/60)) 分钟 ⇒ 可能不是同一套产物"
```

**检查器自己也要有判据**（本仓库一贯要求）：拿一套已知成套的产物跑 ⇒ 不响；
把 bit 的 mtime 改到 2 小时前再跑 ⇒ 必响。两次都过才算这条告警是活的：

```bash
mkdir -p /tmp/gate_test && cp <成套目录>/* /tmp/gate_test/
touch -d "2 hours ago" /tmp/gate_test/system.bit
bash build/gates.sh /tmp/gate_test | grep WARN      # 必须有一行
```
注意：`cp` 会把复制件的 mtime 统一成"现在"，所以**冻结目录永远测不出偏差** ——
这条判据只对正在写的那个工作目录（`build/`）有意义，别拿冻结件当"通过"的证据。

### 规矩二：交付单元是"一套"，不是"一个 bit"

`bit / xsa / elf / 综合与实现报告` 必须**一起**复制、一起校验，因为它们各自会被下一次构建覆盖：

```bash
mkdir -p build/frozen_rNN_<主题>
cp build/system.bit build/system.xsa build/ps_app.elf build/{cdc,clock_util,methodology,power,\
   route_status,timing_summary,utilization}.rpt build/frozen_rNN_<主题>/
(cd build/frozen_rNN_<主题> && md5sum system.bit system.xsa ps_app.elf *.rpt > MANIFEST_BODY.txt \
   && md5sum -c MANIFEST_BODY.txt)          # 必须 10 个 OK
```
`MANIFEST.txt`（人读的那份）里必须写四件事，缺一条就是给未来的自己埋雷：
1. **这版改了什么**（源码级，一两句）；
2. **门禁数字 + 复核命令**（`bash build/gates.sh build/frozen_rNN_...`）；
3. **板级验到哪一条、哪几条没验**（没验的写"没验"，不要靠沉默）；
4. **刻意没收的文件和原因**（例：某份报告是上一天的旧件，收进来只会让人拿它当本次依据）。

还有一条同源的坑：**elf 与 bit 不同步**。改固件不会改 bit，但冻结目录里那份 elf 会停在
"冻结那一刻"，而板上跑的是后来重建的 elf ⇒ 事后按 MANIFEST 回查会查错版本。
做法：每次改完固件重新成套冻结，或者在 MANIFEST 里写一句"本目录 elf 已被 X 号提交取代"。

## 已验证效果

- 新鲜度告警：成套目录不响、bit 改旧 2 小时必响（上面那两条命令即判据）。
- 回退链可用：`build/frozen_r13 → r17 → r18 → r19 → r21 → r22 → r23 → r24 → r25`，
  每一套都能独立 `md5sum -c` 通过；板级出问题时是**按套**回退而不是"猜上一个 bit"。
- `#24` 那一套被明确标成"反例，不要拿去演示"（门禁全绿但板上判据红）——
  这正是成套 + MANIFEST 的价值：**能留下一个说得出为什么错的失败版本**。

## 失效条件

- 只用 mtime 判断不可靠：复制、同步盘、checkout 都会改 mtime ⇒ 所以 mtime 只当"新鲜度提醒"，
  **身份认定永远用 md5**（`MANIFEST_BODY.txt`）。
- 构建脚本如果不写 `system.bit`（例如只跑到 `write_checkpoint`），偏差检测会误报"没成套"——
  那是真信号（产物确实不完整），不要为了消警去改阈值。
- 阈值 10 分钟是按本工程的构建时长（综合 ~4 min、实现 ~8 min）取的；换工程要重新看这个间隔。
