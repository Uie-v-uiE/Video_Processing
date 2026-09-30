#!/usr/bin/env python3
# build/r94_known_issues.py —— 把 KNOWN_ISSUES.md 第一节里"这版没修"的三条改成"已修 + 代价 + 凭据"，
# 并把 r94 只读巡检的四条候选挂到同一节末尾。按**标题行**切片，不做多行字符串匹配（CRLF 会静默失配）。
import io, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, 'docs', 'KNOWN_ISSUES.md')
raw = io.open(P, encoding='utf-8', newline='').read()
NL = '\r\n' if '\r\n' in raw else '\n'
lines = raw.split(NL)


def find(prefix):
    for i, ln in enumerate(lines):
        if ln.startswith(prefix):
            return i
    raise SystemExit('找不到标题：%s（中止，不写盘）' % prefix)


S2, S5, SEC2 = find('### 2. '), find('### 5. '), find('## 二、')
assert S2 < S5 < SEC2, (S2, S5, SEC2)

BLOCK = """### 2. 旋转支上的双线性小数位（`#104`）—— **本轮（r94）已修**

- **改前的现象**：角度非 0 时 OSD 的 `bilin` 那一格显示"双线性开"，但旋转支取样的小数部分被丢掉，
  等效最近邻 ⇒ 屏幕上那一格名不副实。
- **改法**：`zoom_mapper.v` 旋转支把 `>>> 16` 之后的 `[15:8]` 接成小数。**纵向那一次
  `Y_disp = H/2 − Y_math` 的翻转必须连着 floor 一起改**（小数≠0 时 floor 多减一格、小数取 `256 − f`），
  只接小数不减那一格会在旋转态整体错一行 —— 画面上是沿角度方向的一条剪切。台账与判据形状见 `#162`。
- **复现（两半都在盘上）**：改前的红 `build/r94_zoomfrac_console.txt`（298 行 FAIL）；改后的绿
  `build/r94_zoomfrac_final.txt`（独立逐像素判据 128 次比较 0 失配；旋转态 99/99 个像素带非零小数）。
  重跑：`bash sim/run_one.sh tb_zoom_frac`。
- **当时为什么没修 / 现在动了什么**：位宽改动会进时序关键锥。这一轮确实动了它，所以时序那一侧的读数
  **只在 `build/` 的 `timing_summary` 里说**（见第二节第 1 条与 `docs/OPTIMIZATION_LOG.md` 的 r94 段），
  本文不写"余量变好/变差了多少 ns"。眼睛判据（`rot 30` 前后边缘锯齿）**还没复验**，不进"已验证"那一栏。

### 3. 大角度旋转的角点出屏（`#93`）—— **本轮（r94）已修，代价写在下面**

- **改前的现象**：旋转角度大时画面对角线超出窗口 ⇒ 角点出屏，出现沿对角方向的宽彩条与左缘细线。
  原来这一条按"待定的产品决定"记录（语义是"旋转围绕视口中心、超出丢弃"）。
- **改法**：旋转真的在生效时，**实际生效的倍率被钳到 `zoom_fit` 那一档之内**（inv 越大画面越小 ⇒ 取较大的 inv）。
  钳制落在 `zoom_ctrl.v` 的 `inv_used` 那**一个**出口里（新增输入 `rotate_en`、输出 `rot_forced`），
  顶层只把 `rot_forced` 并进 OSD 的 `(Fit)` 标记 —— 于是 mapper、lane23、`status`、屏上档号四处说同一个数。
  为什么不在顶层再 mux 一次：`zoom_ctrl.v` 文件头自己立着这条规矩；我先在顶层写过一版，回退了，
  补丁留在 `build/r94_top_mux_superceded.patch` 当"走过的那条错路"的凭据。
- **代价（不美化，三条都量过）**：① 旋转态**不提供放大**，手动 1.33x/1.5x/2.0x 三档被拉回 fit，
  但用户那一档**不丢**（`inv_scale` 保持原值），关掉旋转立刻回去；② 角度正好 0° 且旋转开着时也在钳
  （`zoom_fit` 的 ±0.5 LSB 表余量给 0° 的是 259 而不是 256 ⇒ 画面差 1.2 %、约 6 个源列）；
  ③ `zoom fit 0` **解不开**这一钳 —— 钳的是"旋转在不在生效"，不是 fit 开关（讲稿那句已改）。
- **复现**：`bash sim/run_one.sh tb_v94_zoom_sel` 看 T8a~T8f；把钳制关掉做变异对照时**恰好** T8b/T8c/T8e 红
  （`build/r94_rotfit_mutation.txt`），恢复后六条全绿（`build/r94_rotfit_after.txt`）。
  屏上"整幅到底在不在框内"由眼睛判，**这一条还没走眼睛复验**（配方：`rot auto` 起转到 45°/60°，看角点）。

### 4. `pl_demo_top` 里同一个实例被关联了两次 `stage_sel`（`#127` 第 1 条）—— **已修（提交 `e634dad`）**

- 重复的 `.stage_sel(...)` 已删（留 `9'd0`，与这个 PL-only 老演示"六级全旁路"的口径一致）。
- **真正要修的那半也落了**：`build/check_ports.py` 现在带 `--dup`，"同一实例重复关联同一输入"是门禁第 14 项的
  **硬项**，它自己的能红对照在 `build/ports_dup_ce.txt` —— 今天 20 项门禁查不出这条，才是原来的病。
- 影响范围不变：这个顶层不在交付构建的顶层链上（交付走 `build_system_axigpio.tcl` → `system_top`）。

### 5. 两处"网口/AXI 输入不可信"的钳制缺失（`#127` 第 4、5 条，CANDIDATE）—— 本轮**没**动，仍是 CANDIDATE

- `src/rtl/eth/frame_reasm.v`：写地址由上位机字头里的 32 位偏移直接拼出，**从未被钳制**
  （偏移越界只护住了行位图）。仿真与硬件行为一致（不是 `#103` 那一族），但一个畸形片头能把数据写进帧中间。
- `src/rtl/axi/axi_frame_writer_gated.v`：`r_pix` 每拍加一无上限，超过约 `2^19` 像素后按位回卷。
- **现状诚实说法**：这两条**没有屏上现象**，也**还没有能数出机会的探针**，所以既不升格为缺陷也不注销。
  本项目的规矩是"先加机会计数探针，有非零再谈改"，否则"没现象"和"被门住了"两种说法不可区分。

### 6. r94 只读巡检新增的四条（`#158` 已修防呆；`#159`/`#160`/`#161` 只记录，各带验证配方）

- **`#158` 已修**：生产例化 `eth_udp_video_top.v` 没把 `FRAME_BYTES` 传给 `frame_reasm`，用的是参数默认 307200 ——
  它只在 `512×300` 时与 `IMG_W*IMG_H*2` 偶然相等。改分辨率后字节门会提前成立（提交半幅黑帧）或永不成立
  （不出 `frame_done`）。现在显式传 `IMG_W*IMG_H*2`：**今天的展开值逐字节不变** ⇒ 这一刀是防呆，不是行为修改。
  **同族还欠一条**：`frame_reasm.v` 用 9 位 `row_idx` 索引 `row_ok[IMG_H-1:0]`，`IMG_H > 512` 时行位图按 512 折叠。
  这条不是运行时现象、机会计数探针数不到，正确的尺子是构建期参数检查 —— 记在工具欠账那一堆，不记成"缺陷已修"。
- **`#159`/`#160`/`#161`（只记录）**：CDC 胶水里 `cdc_d1_v` 比数据早一拍；`src_mode` 的覆盖路径可能一次翻两位、
  破坏格雷码契约（被 20 ms 滞回吃掉 ⇒ 只污染 `why_ps`/lane30 读数）；整链异步复位是"两个异步源的与门"。
  三条都**没有能数出机会的探针**，`docs/log/ISSUES.md` 里逐条写了验证配方：先跑配方拿到非零计数，再谈改代码。
"""

out = lines[:S2] + BLOCK.split('\n') + lines[SEC2:]
new = NL.join(out)
assert len(new) > len(raw), '重写后变短了：中止（当年踩过这个坑，见 #155）'
io.open(P, 'w', encoding='utf-8', newline='').write(new)
print('KNOWN_ISSUES.md %d -> %d 行' % (len(lines), len(out)))
