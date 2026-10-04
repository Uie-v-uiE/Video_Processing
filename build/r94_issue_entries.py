#!/usr/bin/env python3
# 用途：把 r94 这一轮的四件事追加进账本（只追加，不改历史条目）
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
# build/r94_issue_entries.py —— 把 r94 这一轮的四件事追加进账本（只追加，不改历史条目）。
# 规矩：断言结果一定比原来长；写完立刻用 grep 自证条目在盘上（"grep before claiming"）。
import io, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, 'docs', 'log', 'issues.md'.replace('/', os.sep))
t = io.open(P, encoding='utf-8', newline='').read()
NL = '\r\n' if '\r\n' in t else '\n'
before = len(t)

TXT = """
## #158（2026-09-30 12:3x，r94）生产例化没把 `FRAME_BYTES` 传给 `frame_reasm` —— 现值靠 512×300 **偶然**相等

- **怎么发现的**：这一轮派了一只只读巡检子任务扫"显示通路 + 收包链"里没人查过的接缝，四条候选里这是第一条。
- **机理**：`src/rtl/eth/eth_udp_video_top.v` 里唯一的生产例化写的是
  `frame_reasm #(.IMG_W(IMG_W), .IMG_H(IMG_H))` —— `FRAME_BYTES` 用的是 `frame_reasm.v` 的参数默认值 307200。
  而"整帧收完"的唯一判据就是这个字节门（`cov == FRAME_BYTES`）。今天 `IMG_W=512`、`IMG_H=300` ⇒
  `512*300*2 = 307200` 与默认值**恰好相等**，所以没有任何屏上现象；一旦有人改分辨率（学习文档里就教过改
  `VIDEO_W/VIDEO_H`），字节门要么提前成立（提交半幅黑帧）要么永不成立（不出 `frame_done`）。
- **这一刀**：把 `FRAME_BYTES(IMG_W*IMG_H*2)` 显式传进去。**今天的展开值仍是 307200 ⇒ 综合参数逐字节不变**，
  所以它是一刀"免费的防呆"，不是行为修改；正因如此它**不需要**新的判据，需要的是"改了参数就必然对"这个不变式。
- **同族还欠一条（本轮不修，只记）**：`frame_reasm.v` 用 `row_idx[8:0]`（9 位）索引 `row_ok[IMG_H-1:0]`。
  `IMG_H ≤ 512` 时无事；`IMG_H > 512` 时行位图按 512 折叠 ⇒ `rows_hit` 再也凑不齐，帧永远不完整。
  这条**不是**运行时现象，机会计数探针数不到它，正确的尺子是构建期参数检查（写进任务 **#102** 的同一批"工具欠账"）。
- **凭据**：`build/r94_build_console.txt`（这一轮的构建，`rtl_md5=526321488fed` 之后的树）。

## #159 / #160 / #161（2026-09-30，r94 巡检的另外三条候选：**只记录，本轮不修**）

按本项目的规矩，这三条都缺"能数出机会"的探针，所以既不升格为缺陷也不注销。逐条给**验证配方**，
将来谁动它先跑配方、先拿到非零计数，再谈改代码。

- **#159 `eth_udp_video_top.v` 的 `cdc_d1_v` 比 `cdc_d1` 早一拍（存疑）**：`dc_fifo` 的 `rd_data` 已经是一级寄存，
  所以数据在 `fifo_rd` 之后**两拍**才有效，而 valid 侧只打了一拍 ⇒ 每段 CDC 突发的第一拍吐的是陈旧字、
  最后一拍（正好是那包的 flush 标记）不被 pass。今天靠"字自带地址 + `idx_chg` 兜底 + `force_flush`"没有屏上现象。
  配方：在 `tb_v6_ingress_integrity` 里把 `cdc_d1_v` 改成两级延迟，看判据动不动得起来 —— 注意那份胶水在
  `tb_v6_pingpong.v` / `tb_v6_ingress_integrity.v` 是**手抄副本**，所以台架结构上看不见顶层那份的真实形状。
- **#160 `src_mode.v` 的覆盖路径可能一次翻两位，破坏格雷码契约**：`mode_q <= ov_en ? ov_act : ring`，
  `ov_act` 是 PS 直接写的 2 位码（锁 ETH `01` → `src test` `10`；锁 SD `11` → `src auto` `00` 都是两位同翻），
  而顶层是逐位 3FF 同步 ⇒ `ms2` 能读到 `00/11` 这种中间码，`arb_sel` 错一拍。被 `src_arb` 的 20 ms 滞回吃掉
  ⇒ 只污染 `why_ps` / lane30 的读数。配方：串口电池里做"锁 ETH → 立刻切 `src test`"并连读 lane30 若干次，
  数出现非法码的次数；零就注销，非零再改（改法是覆盖路径也走格雷编码，而不是把两位拆开打拍）。
- **#161 整链异步复位是"两个异步源的与门"（低）**：`system_top.v` 的 `.rst_n(eth_rst_n & mmcm_locked)` 与
  `pl_video_top.v` 的 `sys_rst_n & locked`，没有同步/去毛刺 ⇒ 两源近同时翻转时给 `frame_reasm`/`dc_fifo`
  一次窄复位毛刺。配方：`report_cdc -details` 里认 `RS` 类端点，看这份毛刺有没有被记进 `cdc.rpt`；
  在加 `set_false_path` 之前先看，别看反了。

## #162（2026-09-30 12:2x–12:4x，r94 几何两刀：#104 的旋转支小数位 + #93 的旋转态倍率钳制）

**这一节的"改前红"各是哪一份文件**：#104 是 `build/r94_zoomfrac_console.txt`（298 行 FAIL），
#93 是 `build/r94_rotfit_mutation.txt`（关掉钳制的变异对照：恰好 T8b/T8c/T8e 三条红，三条共享同一个根因，
按规矩列**连带红**而不削弱判据）。改后绿：`build/r94_zoomfrac_after.txt`、`build/r94_rotfit_after.txt`
（六条 T8 全绿 + 原有 T1~T7 无回归）。两把尺子的 provenance 里 `rtl_md5=526321488fed`。

### 第一刀 #104：旋转支把小数钉成 0，`bilin on` 是空头支票

`zoom_mapper.v` 的旋转支算完 `xr_m * inv`（Q16）之后只取 `>>> 16` 的整数部分，`frac_x/frac_y` 在旋转态被硬写成 0
⇒ OSD 那一格说"双线性开"，取样其实是最近邻。修法不是"把小数接上"这么轻：
**纵向那一次 `Y_disp = C − Y_math` 的翻转必须连着 floor 一起改** ——
`Y_math = yr_pix + f/256`（`>>>` 是朝 −∞ 取整，`f ∈ [0,256)`），所以
`Y_disp = (C − yr_pix − 1) + (256 − f)/256`（`f = 0` 时就是 `C − yr_pix`、小数 0）。
只把小数接给插值、不减那一格，会在旋转态整体错一行 —— 画面上就是沿角度方向的一条剪切。
这条"floor 与 frac 必须自洽"的要求在缩放支早就写着（`>>> 8` 是朝 −∞ 取整，低 8 位正好是 [0,1) 的小数），
旋转支是它的镜像版本，取的是 `[15:8]` 且小数要 `256 − f`。
判据 `sim/tb_zoom_frac.v` 的期望值是从 DUT 同一张 Q8 三角表里取值、在实数域独立推出来的，
不是"照着 RTL 抄一遍"；它自己带了两条防身：H0 自检"表真的换成新角度了吗"（同步读出的 ROM 不等人，
第一版就是栽在这里把 60 个像素全报成 floor_y 错），H5 数"旋转态到底有几个像素带非零小数"。

### 第二刀 #93：旋转态把生效倍率钳进 fit —— **落点从顶层改到 zoom_ctrl，这是本节的重点**

我先在 `pl_video_top.v` 写了一版顶层钳制（`inv_eff` 同时喂 mapper / lane23 / status），写完发现它违反了
`zoom_ctrl.v` 文件头自己立的规矩："倍率的唯一出处在本模块，顶层再 mux 一次就会出现『屏上那一格与真正在用的
inv 不是一回事』" —— 顶层钳喂得到 mapper、lane23、`status`，**喂不到 `zoom_code`**（OSD 的 ZOOM 那一格是
`zoom_ctrl` 里寄存出来的）。所以那版回退了（补丁留在 `build/r94_top_mux_superceded.patch`，作为"我走过的那条错路"的凭据），
改成给 `zoom_ctrl` 新增输入 `rotate_en` / 输出 `rot_forced`，钳制在 `inv_used` 那一个出口里做，
顶层只做一件事：把 `rot_forced` 并进 OSD 的 `(Fit)` 标记。于是 mapper、lane23、`status`、屏上档号四处**同一个数**。

代价（写进口径，不美化）：

1. 旋转态**不再提供放大**。手动 1.33x/1.5x/2.0x 三档在旋转时被拉回 fit 那一档；用户选的档号不丢
   （`inv_scale` 保持原值），关掉旋转立刻回去 —— 这就是 T8e/T8f 两条的形状。
2. `zoom_fit` 因为 ±0.5 LSB 的表余量，0° 给的是 259 而不是 256 ⇒ **角度正好 0° 且旋转使能开着时也在钳**，
   画面差 1.2 %（约 6 个源列，肉眼不可分辨）。
3. `zoom fit 0` **解不开**这一钳：钳的是"旋转在不在生效"，不是 fit 开关（讲稿里那句"不想要就 `zoom fit 0`"已改）。

台架的形状也记一条教训：`tb_v94_zoom_sel` 的 `chk()` 名字参数只有 **100 字节**，中文标签按 UTF-8 是 3 字节/字 ⇒
超长的会被从**左边**截掉，于是 `T8e` 整条在日志里 grep 不到 —— 我第一版就是看到"只有 5 条 T8"才发现的。
新写的六条一律 ASCII（任务 **#55**"台架判据标签改 ASCII"从今天起不再是可选整理）。
"""

for ln in TXT.strip('\n').split('\n'):
    t += ln + NL
assert len(t) > before, "追加后反而变短了：中止，不写盘"
io.open(P, 'w', encoding='utf-8', newline='').write(t)
print("issues.md %d -> %d 字符" % (before, len(t)))
