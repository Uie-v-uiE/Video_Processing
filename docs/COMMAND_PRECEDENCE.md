# 命令优先级与覆盖关系

## 0. 这份文件回答什么

固件里有一条默认的假设：**串口回声说的就是屏上正在做的事**。这份文件列出这条假设不成立的全部位置 ——
即那些"命令确实被收到、确实写了寄存器、但对画面的贡献是零"的场合，并给出每一处的判定条件与凭据。

读法上有三条规矩：

- 结论只以代码为出处，格式是 `文件:行号`。RTL 与固件两头都要指：固件那一头决定"写了哪个位"，
  RTL 那一头决定"这个位此刻有没有被选中"。只有固件那一头的结论不算结论。
- "静默"与"有回显"分开写。本仓已有的规矩是**不许收了却什么都不做**（`src/ps/main.c:590-593` 的 token 上限
  注释、`src/ps/main.c:1149` 的拒绝分支都按这条写），所以凡是"被盖住且回声没说明"的那几条都在最后一节列成待改清单。
  本轮只登记，不动代码。
- 本文不替代 `docs/COMMANDS.md`（命令口径表）。本文只管"命令同时有效时谁赢"。两份文档对不上的地方在
  第 13 节点名，以代码为准。

一个贯穿全文的区分：`stat` 打出来的每一个字段都是 **PS 侧的影子**（`src/ps/main.c:1334-1342`），
它证明"固件请求了这个值"，证明不了"像素域正在用这个值"。请求侧与执行侧的对账见第 11 节。

正文里的出处用短文件名（在本仓 `src/` 下每个名字都只有一份），完整路径是：

| 短名 | 完整路径 | 短名 | 完整路径 |
|---|---|---|---|
| `main.c` | `src/ps/main.c` | `pl_video_top.v` | `src/rtl/top/pl_video_top.v` |
| `system_top.v` | `src/rtl/top/system_top.v` | `src_mode.v` | `src/rtl/util/src_mode.v` |
| `src_arb.v` | `src/rtl/util/src_arb.v` | `src_life.v` | `src/rtl/util/src_life.v` |
| `zoom_ctrl.v` | `src/rtl/process/zoom/zoom_ctrl.v` | `zoom_fit.v` | `src/rtl/process/zoom/zoom_fit.v` |
| `zoom_mapper.v` | `src/rtl/process/zoom/zoom_mapper.v` | `angle_ctrl.v` | `src/rtl/process/rotate/angle_ctrl.v` |
| `split_ctrl.v` | `src/rtl/video/split_ctrl.v` | `split_display.v` | `src/rtl/video/split_display.v` |
| `osd_overlay.v` | `src/rtl/video/osd_overlay.v` | `fb_bilin.v` | `src/rtl/process/bilin/fb_bilin.v` |
| `proc_pipeline.v` | `src/rtl/process/proc_pipeline.v` | `proc_binary.v` | `src/rtl/process/proc_binary.v` |
| `proc_morph.v` | `src/rtl/process/proc_morph.v` | `health_read.mjs` | `src/host/health_read.mjs` |

行号一律按换行符计（`awk 'NR==n'` / `sed -n 'Np'` 的口径），并且取自**工作区当前文本**。
`src/rtl/` 下 `proc_pipeline.v`、`src_mode.v`、`osd_overlay.v` 等几份带着未提交的注释整理（行数比提交版本少），
所以拿提交版本去对行号会整体偏移；改动落库之后这一批行号要重新走一遍。

---

## 1. 总表：命令 → 写哪个位 → 谁盖谁

控制字只有两只，所有命令都写进这两只（`src/ps/main.c:188-206`）：
`gpio_o`（`0x41200000`）与 `gpio_cfg1`（`0x41220000`，RTL 里的 `CFG_DATA0`）。
物理位到逻辑位的拼接在 `src/rtl/top/system_top.v:248-276`。

| 命令 | PS 影子 → 物理位 | 执行侧的读者 | 谁盖它 | 被盖住时有没有说明 |
|---|---|---|---|---|
| `zoom <倍率>` | `cur_zsel`/`cur_zman` → `cfg1[28:26]`/`[29]`（`main.c:942`、`203-204`） | `zoom_ctrl.v:89-93` | `zoom fit 1`、`zoom off` | **没有**（§2） |
| `zoom auto` | `cur_zman=0`（`main.c:917`） | 同上 | `zoom fit 1`、`zoom off` | **没有**（§2） |
| `zoom on/off` | `cur_zoom` → `gpio_o[17]`（`main.c:498`、`195`） | `zoom_ctrl.v:85-88` | `zoom fit 1` | **没有**（§2） |
| `zoom fit 1/0` | `ZOOM_FIT_BIT` → `cfg1[31]`（`main.c:929`） | `zoom_ctrl.v:58`、`80` | 无人盖它（缩放链的最高优先级） | 它盖别人时会说明（`main.c:931-933`） |
| `rot auto 1` | `ROT_AUTO_BIT` → `cfg1[9]`（`main.c:1016`） | `angle_ctrl.v:43` | 无人盖 | 顺带改 `speed`、`zoom_fit`，**两处都说明**（`main.c:1019-1030`） |
| `rot speed <0..7>` | `ROT_SPEED_MASK` → `cfg1[12:10]`（`main.c:1002`） | `angle_ctrl.v:43` | `rot auto 0` | **没有**（§3） |
| `rot <绝对角度>` | 不存在 | — | — | 明确拒绝（`main.c:1042`） |
| `src 0/1/2` | `cur_mode_ovr` → `gpio_o[24:23]`＋`[22]`（`main.c:489-492`） | `src_mode.v:73-82`→`pl_video_top.v:545` | 长按 KEY1 一次交还；`have_src` 能否决 | 说明了钉住与交还（`main.c:493`） |
| `src auto` | 同上，码=AUTO | `src_mode.v:79-81`（连按键环一起清） | — | 是 |
| `src 3` | 不存在 | — | — | 明确拒绝（`main.c:708-710`） |
| `SRC0/SRC1`（`src_sel`） | `cur_src` → `gpio_o[16]`（`main.c:478`、`194`） | 显示侧 `pl_video_top.v:545`；搬运机 `pl_video_top.v:641` | **显示侧：任何非 AUTO 的 mode 都让它失效**；搬运机那一路的闸门是 `owner_eth` 而不是 mode | **没有**（§4、§5） |
| `play` / `fill` / `frame N` | 只写 `cur_src`＋发布位（`main.c:1303`、`683-684`、`1228`） | 搬运机 `pl_video_top.v:509`、`641` | `src 0`/`src 1` 钉住期间 | **没有**（§5） |
| `split <pct>` / `split px <n>` | 清 `SPLIT_AUTO_BIT`、写 `pos_px`（`main.c:1130`、`1140`） | `split_ctrl.v:92` | 无人盖（它自己盖 `auto`） | 说明"manual"（`main.c:1131`、`1143`） |
| `split auto` | `SPLIT_AUTO_BIT` → `cfg1[23]`（`main.c:1068`） | `split_ctrl.v:92`、`100` | **它盖 `pos_px`** | 半说明（§6） |
| `split follow 1` / `split video` | `SPLIT_FOLLOW_BIT` → `cfg1[24]`（`main.c:1090`、`1114`） | `split_ctrl.v:33` | 与 `auto` 同时开时新的 `pos` 不动屏 | 说明了"auto 仍开着"（`main.c:1119`） |
| `split swap 1` | `SPLIT_SWAP_BIT` → `cfg1[25]`（`main.c:1090`） | `split_ctrl.v:103`→`split_display.v:48` | — | 说明了"只换内容，不换缝位"（`main.c:1095`） |
| `split marker 0` | `SPLIT_MARKOFF_BIT` → `cfg1[30]`（反着写，`main.c:1087-1088`） | `pl_video_top.v:839`→`split_display.v:53-65` | 标记线盖过缝两侧的内容 | 是（那格说明是蓝线） |
| `split range` / `split speed` | 不存在 | 端点/速度是构建参数（`pl_video_top.v:16-18`、`834`） | — | 明确拒绝（`main.c:1150-1152`） |
| `pipe <九位>` | `cur_sel` → `cfg1[8:0]`（`main.c:435`、`202`） | `proc_pipeline.v:49-58` | 缝位决定"看得见几成" | 见 §7 |
| `pipe` 的 `[6]`（bin_pol） | 同上 | `proc_pipeline.v:131` | **`[5]=0` 时无人读它** | **没有**（§8） |
| `pipe` 的 `[7]`＋`[8]` 同开 | 同上 | `proc_pipeline.v:56-58`、`proc_morph.v:24` | **两者互相抵消** | **没有**（§8） |
| `th <0..255>` | `cur_thr` → `gpio_o[15:8]`（`main.c:472`、`194`） | `proc_binary.v:22`、`proc_morph.v:34` | `[5]`/`[7]`/`[8]` 全 0 时没有读者 | **没有**（§8） |
| `gamma <γ>` | `cur_gamma` ＋ `CFG_DATA1` 表窗口 | `proc_pipeline.v:92-96`（级 0） | 只在"处理图"那一侧可见 | **没有**（§7） |
| `bilin on/off` | `cur_bilin` → `gpio_o[19]`（`main.c:537`、`196`） | `pl_video_top.v:251-262`→`fb_bilin.v:51-54` | 旋转态、整数倍率、画面末行末列 | 说了两个条件（§9） |
| `osd on/off` | 不写任何位 | — | — | 明说"语法已收、硬件未接"（`main.c:1204-1206`） |
| 裸五位串 / `pipe 00111` | 不写任何位（`main.c:461-467`） | — | — | 回一句等价的九位 |

---

## 2. 缩放：四个来源，一条有先后的链

命令表看起来是三个来源（呼吸 / 手动档 / 按角度拟合），但执行侧实际是**四个输入、一条 if-else 链**。
第四个是 `zoom on|off`（`gpio_o[17]`，`main.c:498`），它在链里排在手动档之前。

`src/rtl/process/zoom/zoom_ctrl.v:80-94` 的分支顺序就是优先级顺序：

1. `fit_en`（`zoom_ctrl.v:80`）：整条 `inv_scale` 链被旁路，这一支**不写** `inv_scale`；
   喂给 mapper 的是 `inv_used = fit_en ? inv_fit : inv_scale`（`zoom_ctrl.v:58`）。
2. `!enable`（即 `zoom off`，`zoom_ctrl.v:85-88`）：`inv_scale <= INV_LO`，`INV_LO` 就是 256 = 1.00x
   （实例化时钉在 `pl_video_top.v:281`）。
3. `manual && frame_start`（`zoom_ctrl.v:89-93`）：`inv_scale <= tbl(zsel)`，八档表在 `zoom_ctrl.v:34-50`。
4. `frame_start`（`zoom_ctrl.v:94`）：呼吸，在 `[INV_LO..INV_HI]` 里每帧走一步。

于是判定条件写成一句话就是：

- **`zoom fit=1` 时，`zoom 1.5` 会被接受但不生效** —— `cur_zsel=6`、`cur_zman=1` 都真写进了
  `cfg1[28:26]`/`[29]`（`main.c:942` 与 `main.c:203-204`），同步链也把它们送到了像素域
  （`pl_video_top.v:202`），但 `inv_used` 走的是 `inv_fit` 那一支（`zoom_ctrl.v:58`）。
  它不是丢了：`zoom fit 0` 之后的下一个帧首，手动档就接管（`zoom_ctrl.v:89`）。
- **`zoom off` 时，`zoom <倍率>` 与 `zoom auto` 都不生效**，屏上恒为 1.00x（`zoom_ctrl.v:85-88`）。
  上电默认 `cur_zoom=1`（`main.c:167`），所以这条平时撞不到；一旦谁为了演示按过 `zoom off`，
  后面所有 `zoom` 数值命令都只改影子。
- **`zoom off` 关不掉拟合**：`fit_en` 排在 `!enable` 之前（`zoom_ctrl.v:80` vs `:85`），
  所以 `zoom off` ＋ `zoom fit 1` 的屏上是"跟着角度缩放的画面"，而不是"不缩放"。
- **三条命令的合成结果只有一个读数**：`inv_used`（`pl_video_top.v:275` 就把它命名为
  "本文件里此刻真的在用哪个倍率的唯一读数"）。屏上 `Zoom:` 那一格的档位号也是从 `inv_used` 分区来的
  （`zoom_ctrl.v:52-53`、`60-67`），不是从影子来的。

回声的问题在于它把"请求成功"说成"生效"：

- `zoom 1.5` 的固定回声是"[ZOOM] 1.5 → 最近档 1.50x（八档…；回自动用 zoom auto）"（`main.c:944-947`）。
  fit 开着时这句的两个半句都不成立：1.50x 此刻不在用，`zoom auto` 也不会让画面动起来。
- `ctrl_apply` 那行 `zoom_step=%d %s (%s)`（`main.c:216-217`）在 fit 开着时会印成 `1.50x (手动)`。
  这一行的原意（`main.c:214-215` 的注释）是"切回手动就会用哪一档"，但它印出来的字面就是"手动"，
  而 fit 那一支被省略了 —— 这是本文件里唯一一处**回声主动说谎**（另外几处只是不说）。
- `zoom fit 0` 的收尾半句是"关掉之后回到手动档/呼吸自动档"，取自 `cur_zman`（`main.c:931-933`）。
  如果同时 `zoom off`，实际回到的是 1.00x（`zoom_ctrl.v:85`），既不是手动档也不是呼吸。

---

## 3. 旋转：`rot auto` 与缩放拟合是绑定的，`rot speed` 不是自足的

`rot` 只有三个入口：`rot auto [0|1]`、`rot speed <0..7>`、`rot show`（`main.c:989-1044`）。
**没有 `rot <角度>`**，注释里写明了为什么不做一个 9 位角度写窗口（`main.c:985-987`），
拒绝消息也会把这句话说出来（`main.c:1042-1043`）。角度只有 KEY1/KEY2 的 ±1° 这一个来源
（`src/rtl/process/rotate/angle_ctrl.v:39-42`）。

耦合与优先级有四处：

- `rot auto 1` 顺带做两件事：`speed` 为 0 时提到 2（`main.c:1017-1022`），
  `zoom_fit` 没开时把它开起来（`main.c:1024-1030`）。两件事**都在回声里明说**，
  并且给出避开的方法（"不想这样就先 `zoom fit 0` 再 `rot auto 1`"）。这是全文件里做得最标准的一处。
- `rot auto 0` 只清 `ROT_AUTO_BIT`，**不动缩放那一路**（`main.c:1036-1037`），这一点也明说了。
  也就是说 `rot auto 1` 不是可逆的：开的时候绑上了 fit，关的时候 fit 留着。
- `rot speed <n>` 在 `rot auto 0` 时不产生任何画面差别：`angle_ctrl` 的步进条件是
  `auto_en && fs_edge && (speed != 0)`（`angle_ctrl.v:43`）。回声只印
  "[ROT] speed=n 度/帧"（`main.c:1004`），不说 auto 现在是关的。
- 在 `angle_ctrl` 内部，按键的 ±1° 排在自动步进之前（`angle_ctrl.v:39-44` 是同一串 if-else 的前两支），
  所以按住键的那一帧，帧首步进被按键顶掉。这是设计意图，不需要回显。

`rot show` 印的是 `auto`、`speed`、以及 fit 位（`main.c:990-993`），三个都取自 PS 影子 `cur_split`；
它**不含角度**，而固件里也没有角度的串口读口（`stat` 的字段表见 `main.c:1334-1342`，
几何控制字 `geom=` 也不含角度）。要看真实角度只能读屏上 `Rot:` 那一格
（`src/rtl/video/osd_overlay.v:284-286`）。

---

## 4. 片源：四层判据，命令只是其中一层

"屏上是哪一路"不是一条命令决定的，是四层串联的结果。从上往下：

**第一层：模式（`mode`）** —— 来源有两个，互相能盖。

- 命令侧：`src 0/1/2` → `cur_mode_ovr` → `gpio_o[24:23]` 加一次 `[22]` 翻转
  （`main.c:489-492`，两笔写的先后顺序的理由写在 `main.c:482-486`）。
- 按键侧：长按 KEY1 一次 → `ltog` → 模式环走一格（`pl_video_top.v:144-146`、`src_mode.v:83-87`）。
- 谁赢：覆盖期间长按**只交还控制权，不多走一步**（`src_mode.v:85` 的 `if (ov_en) ov_en <= 0`），
  所以命令赢在第一笔，按键赢在"一次就能解除"。生效模式是一个触发器
  `mode_q <= ov_en ? ov_act : ring`（`src_mode.v:98`）。
- `src auto` 比"取消覆盖"更彻底：它把按键环也清回 AUTO（`src_mode.v:79-81`），
  针对的正是"回了自动、再一按又钉住"。

命令的字面编号与 PL 的编码不是同一张表，这一点必须按代码念：
`src 0` = TEST、`src 1` = ETH、`src 2` = SD（`main.c:694-707`），
而模式编码是 AUTO=0 / ETH=1 / TEST=2 / SD=3（`main.c:59-62`）。
所以 `src 3` 不是"第四路"，它落在拒绝分支上（`main.c:708-710`）。回声印的词与屏上印的词同源
（`src/rtl/video/osd_overlay.v:244-246`）。

**第二层：搬运机归谁（`owner_eth`）** —— 模式只是"谁想要总线"，不是"什么时候换手"。

- 模式到仲裁输入的适配在 `pl_video_top.v:167`：ETH→强制 ETH、SD→强制 PS、
  **TEST 与 AUTO 都映射成 AUTO**，理由是"图卡只是显示什么，不是谁在搬"（`pl_video_top.v:166`）。
  后果：`src 0` 期间如果网线活着，ETH 引擎照样占着 AXI 读口和帧缓存写口，只是屏上看不到它。
- 判据本身在 `src/rtl/util/src_arb.v`：`force_eth`/`force_ps`（`:44-45`）直接压过
  `eth_live & eth_tb_ok` 那个自动判据（`:51`），但换手仍然只在两个引擎都空闲时发生（`:69-72`），
  往 PS 让位还要等 20 ms 静默（`pl_video_top.v:376`）。

**第三层：帧缓存可见性（`fb_vis`）** —— `pl_video_top.v:545`：

```
fb_vis = (mode_card ? 1'b0 : (mode_eth | mode_ps) ? 1'b1 : src_use) && have_src;
```

这一行就是 `src_sel`（`gpio_o[16]`，也就是老写法 `SRC0`/`SRC1` 写的位，`main.c:478`）
**唯一的读者**：只有 AUTO 模式才轮到它说话。模式一旦钉住，`src_sel` 在显示侧就没有票了
（它在搬运机那边还剩一个作用，见 `pl_video_top.v:641`）。

**第四层：还有没有片源（`have_src`）** —— 活判据，能否决前三层（`src/rtl/util/src_life.v:56-57`）。
PS 这一路看的是 500 ms 内有没有过发布（`src_life.v:41-47`），而固件在停播/定点这些状态下
每 100 ms 替它报一次心跳（`main.c:239-248`）。心跳停了才会把画面交回仲裁（`main.c:252-257`）。

屏上 `SRC:` 那一格画的是第三层与第二层的合成结果，不是模式：
`src_eff = {fb_vis, owner_eth_pix}`（`pl_video_top.v:959`）→ 11 印 `ETH`、10 印 `SD`、其余印 `TEST`
（`osd_overlay.v:244-246`），模式非 AUTO 时只在名字后加一个 `*`（`osd_overlay.v:248`）。

`stat` 里与片源有关的是两个字段，**都是 PS 影子**：`src=` 是 `cur_src`（bit16 那个位），
`mode=` 是 `cur_mode_ovr`（`main.c:1334-1341`）。它们合起来仍然回答不了"此刻屏上是谁" ——
因为 `owner_eth` 与 `have_src` 不在 `stat` 里。真值走 lane30（`pl_video_top.v:553`，
译码在 `src/host/health_read.mjs:70-78`）。

---

## 5. 被钉住的模式下 `play` / `fill` / `frame N` 都不换画面

这是最容易被当成"命令坏了"的一组。三条命令都只写 `cur_src` 与发布位，**都不动模式**：

| 命令 | 写了什么 | 没写什么 |
|---|---|---|
| `src 2` | `cur_src=1` ＋ 踢回放 ＋ **钉模式到 SD**（`main.c:704-706`） | — |
| `play` | `cur_src=1` ＋ `sd_play(1)`（`main.c:1303-1304`） | 模式 |
| `frame N` | `sd_show()` ＋ `cur_src=1`（`main.c:1227-1228`） | 模式 |
| `fill` | 写 DDR ＋ `cur_src=1` ＋ 发布一次（`main.c:683-684`） | 模式 |

于是先 `src 1`（钉 ETH）或先 `src 0`（钉 TEST）再敲这三条，屏上一个像素都不动：

- 钉 ETH 时仲裁把总线交给 ETH（`pl_video_top.v:167`→`src_arb.v:51`），而 PS 的发布只有在
  仲裁没把屏交给 ETH 时才被消费：`pub_consume = frame_start && src_use && !owner_eth_pix`
  （`pl_video_top.v:509`）；PS 那一台搬运机也直接被禁用（`pl_video_top.v:641`）。
  屏上是冻结的最后一帧，外加 "ETH IS NO SIGNAL" 那一格（判据 `pl_video_top.v:465`）。
- 钉 TEST 时 `fb_vis` 被强制成 0（`pl_video_top.v:545`），DDR 里那张画和发布都真发生了，
  只是显示侧不看它。

回声方面：`play` 那句是 "[SD] playing (stop / play 0 结束; ETH 有流时会自动让位)"（`main.c:1307`）。
它只覆盖了 AUTO 模式下的交接，既没说"模式现在是钉住的"，也没覆盖钉 TEST 的情形。
`fill` 完全没有自己的回声（只有 `ctrl_apply` 的 `[CTRL]` 行，`main.c:211`）。

---

## 6. 分割线：`auto` 盖住 `pos_px`，`follow` 换的是坐标空间

`split` 家族写的是同一只几何字的相邻位（`main.c:117-135`）。三种"谁盖谁"：

**（a）`split auto` 盖住缝位数值。** 执行侧的选择器是
`raw_sel = auto_en ? swp : pos_px`（`split_ctrl.v:92`），
输出再夹进当前端点（`split_ctrl.v:100`）。所以 auto 开着的时候 `pos_px` 那位还留着，
但**不是此刻的缝**。反过来 `split <pct>` 与 `split px <n>` 会顺手把 auto 清掉
（`main.c:1130`、`main.c:1140`），回声带 "(manual)"（`main.c:1131`、`main.c:1143`），
所以顺序不同结果不同：`split 30` → `split auto` 里那个 30 只当成扫描的起点
（`split_ctrl.v:74` 在手工模式下把 `swp` 跟住 `pos_px`，为的就是打开 auto 那一瞬间不跳位）；
`split auto` → `split 30` 则扫描被关掉。

**（b）`follow` 盖的是"这个数字是什么单位"。** PL 里
`wire [16:0] W = follow ? SRC_W17 : DISP_W17;`（`split_ctrl.v:33`），
固件这一侧镜像同一个判据（`main.c:1054`：`w = follow ? SPLIT_SRC_W : SPLIT_DISP_W`）。
于是同一个 `split 60` 有两种物理位置：显示列空间是第 614 列，画面列空间是第 307 列。
`split show` 会念出当前空间（`main.c:1059`），屏上 `Split:` 那一格念的是百分比而不是列
（`osd_overlay.v:296-298`）。

不匹配的那一支由夹住来兜：`split px <n>` 的上限取**当前空间**的宽（`main.c:1124`），
超出就拒绝并说明是哪个空间；PL 侧还有一道 `raw_sel > W ? W` 的夹
（`split_ctrl.v:96`）。固件注释里写的正是这个改动的动机：不换算的话 `split 60` 在 follow 下算出 614，
被 PL 夹到画面右端，而屏上那格还印 60%（`main.c:1050-1053`）。

**（c）字段宽度盖住"100%"。** `pos_px` 只有 10 位（`cfg1[22:13]`），屏幕宽 1024，
所以 1024 这个值装不下，`1024<<13` 会串进 `auto` 那一位（`main.c:119-130` 把两种历史症状都写了）。
现在的处置是写口之前夹到 1023 并把"夹过"这件事交给调用方印
（`split_pos_clamp`，`main.c:159-163`；三处写口分别带 `main.c:1120`、`1133`、`1146` 的尾巴），
回声里的百分比由**存进去的值**反算（`main.c:1141-1146`），所以 100% 会念成 99%。

**（d）`marker` 与 `swap` 是内容级的事。** 标记线位在 `cfg1[30]`，语义反着写
（1 = 关，`main.c:1087-1088`；执行侧 `split_marker_on = ~gp[13]`，`pl_video_top.v:839`），
而它在混色级排在内容之前：`if (sep && de)` 直接画蓝（`split_display.v:53-65`）。
`swap` 只翻 `raw_on_left`（`split_ctrl.v:103`），不改缝位（回声明说，`main.c:1095`）。
follow 打开时"哪一格算缝的左侧"改由源头那一拍判定（`seam_src`，`pl_video_top.v:849-853`，
`split_display.v:44`、`48`），这条写口的注释说清了它是 V9-1 才真的换判据空间的
（`main.c:1093`）。

---

## 7. 分割线位置决定整条效果链可见不可见

缝两侧的像素来自同一份源坐标、两个抽头：`orig_pix`（链子之前）与 `proc_pix`（链子之后），
选择器是 `sel = oob ? 黑 : (take_orig ? orig : proc)`（`split_display.v:49`）。
gamma 是链子的第 0 级（`proc_pipeline.v:92-96`，`en=0` 时逐位旁路），
`th`/`pipe` 都在它后面（`proc_pipeline.v:131`、`137`）。

于是这三条推论都是位级的事实，而不是观感：

- `split 100`（存成 1023，§6c）时几乎整屏都是原图抽头 ⇒ `pipe`、`th`、`gamma` 全都"看不出在动"。
  固件注释里把这一条当作要防的症状写过（`main.c:121-126`：要"整屏处理图"结果得到"整屏原图"）。
- `split 0` 时整屏都是处理图，缝两侧的对照就没了。要对照就得把缝放在中间，
  或者用 `split swap` 换边而不是挪缝（`main.c:1095`）。
- "处理只作用于半屏"是这个设计的定义而不是缺陷（`docs/COMMANDS.md` 第 6 节第 1 条就是这么写的），
  但**没有一条回声会提醒它**。当屏上是整屏原图的时候，`stat` 里的 `sel=` 与 `gm=` 仍然显示
  "效果开着、γ 开着"（`main.c:1340-1341`），因为它们读的是影子。

---

## 8. 九位效果字内部：修饰位与被抵消的一对

九位是"一位一级"，但级与级之间有三条不成对的规则，代码都在 RTL 一侧：

- **`[6]`（bin_pol）是 `[5]`（binary）的修饰位，不是独立的一级。**
  它唯一的读者是 `proc_binary` 的 `.pol(bin_pol)`（`proc_pipeline.v:131`），
  而同一个例化的 `bypass(~w_bin)` 在 `[5]=0` 时把这一级整个旁路掉 ——
  于是 `pipe 010000000` 这一位写进去了，没有任何像素会因它改变。
  模块文件头自己写了这条约束（`proc_pipeline.v:6`，"只在 `[5]=1` 有意义"）。
- **`[7]` 与 `[8]` 同时为 1 时两个都不做。** `w_erode = sel[7] & ~sel[8]`、
  `w_dilate = sel[8] & ~sel[7]`（`proc_pipeline.v:56-57`），合成 `morph_mode=0`；
  而 `proc_morph` 把 `mode==0` 与 `mode==3` 都当旁路
  （`proc_morph.v:24`，理由写在 `proc_morph.v:22-23`：开/闭运算要两遍 3×3 窗口）。
  这不是"后写的盖住先写的"，是**两位互相抵消**。
  与之对照：`[2]`/`[3]`（模糊/锐化）是串联的两个窗口级，同开就都做（`proc_pipeline.v:109-118`），
  所以互斥只有级 5 这一处。
- **`th` 只有两个读者。** `proc_binary` 的亮度比较（`proc_binary.v:22`，极性由 `pol` 翻，`:23`）
  与 `proc_morph` 自己那一次二值化（`proc_morph.v:34`）。
  所以当 `[5]`、`[7]`、`[8]` 全为 0 时，`th` 的任何取值都不改变画面；
  而 `[7]` 或 `[8]` 单独开着时 `th` 仍然有效（形态学自带一次亮度判决）。

回声的问题：`print_sel_names` 把每一位的名字按 `cur_sel` 的置位列出来（`main.c:568-578`），
它列的是"置了哪些位"，不是"哪些位此刻在做功"。于是 `pipe 110000000` 会得到
"[PIPE] sel=160 生效: erode dilate"，而画面上腐蚀与膨胀都没发生。
同一件事屏上反而更诚实：`Pipe:` 那五格是"每级选了第几个算法"的成对编码，
阈值格只可能 0/1/2（`osd_overlay.v:134`）、形态学格在两位同开时给 0（`osd_overlay.v:138`）。
**串口说"生效: erode dilate"、屏上第五格是 `0` —— 这就是请求侧与执行侧不一致时该读哪一个的判据。**

---

## 9. `bilin` 的三种空转

`bilin on|off` 是真接到硬件的：`gpio_o[19]`（`main.c:537`、`196`）→ 3 级同步成 `bilin_en_pix`
（`pl_video_top.v:251-262`）→ `fb_bilin` 的 `bilin_en`（`pl_video_top.v:677-683`）。
它不改变画面的几何，只改变取样的插值方式，所以有三种情况下 on 与 off 逐位相同：

- 旋转态：mapper 的旋转那一支把小数钉成 0（`zoom_mapper.v:75-76`）。
- 整数倍率（1.00x 等）：逆映射本来就没有小数步长。
- 采样落在源画面最后一列/最后一行：`(!bilin_en || sx >= IMG_W-1) ? 8'd0 : fx`
  （`fb_bilin.v:51-54`），边界格本来就折回最近邻。

`bilin show` 把前两条讲出来了，而且给了一条可复现的对照序列
（`main.c:960-966`：`src 0` → `zoom 1.5` → `bilin off/on`），第三条没有提。
另需记一笔：`main.c:1207-1214` 那段注释断言"缺的是 PL 侧没人读 `gpio_o[19]`"（`main.c:1211-1212`），
这与今天的连线不符（`system_top.v:270` 已经把这一位接进 `pl_video_top`，
`pl_video_top.v:251-262` 同步、`fb_bilin` 在读）。同一段注释里那句"上面 801 行 `ci_pre(tk[0], "BILIN")`"
指的位置也不对了 —— 那条前缀匹配今天在 `main.c:957`。而它下面那条 `not_wired("bilin", …)`
（`main.c:1222`）按注释自己的说法就永远不会执行。

---

## 10. 语法收了、但不写任何位的写法

这几条不是"被别的命令盖住"，而是本来就没有出口。放在一起是因为它们在串口上的表现相同：
一句解释、零状态改动。**它们都已经有明确回声**，列在这里是为了和第 11-12 节那几条"沉默的"区分开。

| 写法 | 现在的行为 | 出处 |
|---|---|---|
| 裸五位串（`00111`）、`pipe 00111` | 一个位都不写，回一句等价的九位 | `main.c:457-468`、`871` |
| `pipe` 给 6/7/8 位 | 拒，不做补零解释 | `main.c:541-558`、`876-881` |
| `src 3` | 拒，并念出 0/1/2 的词表 | `main.c:708-710` |
| `rot 37` / `rot angle …` | 拒，并说明角度只走按键 | `main.c:1042-1043` |
| `split range …` / `split speed …` | 拒，并说明端点与速度是构建参数 | `main.c:1150-1152`；参数在 `pl_video_top.v:16-18`、`834` |
| `osd on/off` | "语法已收，硬件未接"，并说明两条接法各要付什么 | `main.c:1204-1206` |
| `zoom show` | **不存在**：落到 `ZOOM` 的通用拒绝消息 | `main.c:951-954`（对照 `split show` 在 `main.c:1056`） |
| `gamma auto` 参数越界 | 拒，并把收到的四个数原样念出来 | `main.c:308-313` |
| `temp th` 参数不是十进制 | 退回 85 并说明 | `main.c:820-824` |
| 一行超长 / 半行搁置 | 报一条并丢掉，不静默截断 | `main.c:1427-1434`、`1384-1392` |

（`osd on/off` 从这张"会拒的"表里删掉了 —— r83 起它真的写位，位置在 §2 那一行；
 顺带一句：`main.c:1204-1206` 那个 `not_wired("osd", …)` 桩已经跟着删了，别再按老行号去找它。）

---

## 11. 怎么确认此刻真的在用哪一路

原则：**先读执行侧，再读影子。** 影子的字段清单在 `main.c:1334-1342`（`stat` 那一行的字段顺序被
串口电池按前缀解析，所以只能往后加，`main.c:1325-1333`）。

| 想知道的事 | 读哪里 | 出处 |
|---|---|---|
| 此刻倍率是多少 | 屏上 `Zoom:` 那五位档位（由 `inv_used` 分区得到） | `zoom_ctrl.v:52-67`、`osd_overlay.v:141-155` |
| 此刻倍率是哪一路给的 | 屏上后缀：`(Fit)` = 角度定的，`(Auto)` = 呼吸在跑，**无后缀** = 手动档**或** `zoom off`（合成式要求 `zoom_run`） | `osd_overlay.v:291-292`；三个旗标的合成 `pl_video_top.v:955-956` |
| 同上，但不看屏 | lane23 的 `zoom_fit`（bit19）与 `[9:0]`（`inv_used`） | `pl_video_top.v:627-633`；译码 `src/host/health_read.mjs:91-96` |
| 请求侧写了什么 | `stat` 的 `zsel=`/`zman=`、`zoom=`；`rot show` 的 `zoom=fit/now` | `main.c:1334-1338`、`990-993` |
| 屏上此刻是哪一路 | 屏上 `SRC:` 的名字（`{fb_vis, owner_eth}`），尾部 `*` 才表示"被钉住" | `pl_video_top.v:959`、`osd_overlay.v:244-248` |
| 为什么归这一路 | lane30：`owner_eth`/`eth_live`/`eth_tb_ok`/`why_ps` | `pl_video_top.v:553`、`src_arb.v:35-39`、`62`；译码 `health_read.mjs:70-78` |
| 模式请求 | `stat` 的 `mode=`（AUTO/ETH/TEST/SD 的**编码**，不是词） | `main.c:1341`、编码表 `main.c:59-62` |
| 此刻生效的是哪几级效果 | `pipe show` 念名字；屏上 `Pipe:` 念成对编码 | `main.c:568-578`、`osd_overlay.v:129-138` |
| `th` 此刻有没有读者 | `pipe show` 里有没有 binary / erode / dilate | 读者只有 `proc_binary.v:22`、`proc_morph.v:34` |
| 缝在哪个坐标空间 | `split show` 的"画面列/显示列"与 `pos=<n>/<W>` | `main.c:1056-1064`；空间的唯一判据 `split_ctrl.v:33` |
| 缝是不是在被自动扫 | `split show` 的 `auto/manual`；屏上 `Split:` 后面的 `(Auto)` | `main.c:1061`、`osd_overlay.v:299` |
| 几何控制字整字（含 fit 位） | `stat` 的 `geom=%08x`（PS 影子），bit31 = zoom_fit | `main.c:1334-1342`、`main.c:152` |
| 此刻的角度 | **只有屏上 `Rot:` 那一格**；固件没有角度读口 | `osd_overlay.v:284-286`；对照 `main.c:990-993`、`1334-1342` |
| 温度/延时的屏上格 | `temp` 那一行末尾同时给 `degC`/`osd`/`gpio` 三种写法 | `main.c:855-857` |

把上面这些串成一次自查的最小序列（每条都能独立判红绿，都不需要眼睛看屏幕的只有 lane23/lane30 那两个）：

```
stat                     影子：zsel zman mode geom
rot show                 请求侧的 fit 位
split show               请求侧的坐标空间与 auto
pipe show                请求侧的九位
node src/host/health_read.mjs    执行侧：lane23（倍率与 fit）、lane30（谁占着屏）
```

---

## 12. 建议改代码的地方（本轮不改）

改法统一遵循同一条已在本仓成文的规矩：**状态改了就要说出来**
（先例是 `main.c:1019-1030` 的 `rot auto 1` 与 `main.c:1119` 的 `split screen`：
既说出顺带改了什么，也说出怎么避开）。下面每一条都只加回声，不改任何位的写法，
因此不影响 elf/bit 的配套关系，也不新增跨域。

| # | 命令 | 现在的行为 | 建议回显 |
|---|---|---|---|
| 1 | `zoom <倍率>` 而 fit=1 | 写 `zsel/zman`，报"最近档 1.50x；回自动用 zoom auto"，画面不动 | 追加一句"fit 开着 ⇒ `inv_used` 由角度定，本档要到 `zoom fit 0` 才接管（现在这样写就行：`zoom fit 0`）" |
| 2 | `ctrl_apply` 的 `zoom_step=… (手动)` | fit 开着时仍印"手动" | 三个状态都印：`手动` / `呼吸` / `拟合中，本档暂不生效`（判据取 `cur_split & ZOOM_FIT_BIT`，`main.c:929` 已经在维护这个影子） |
| 3 | `zoom <倍率>` 或 `zoom auto` 而 `zoom off` | 写了位，屏上恒 1.00x（`zoom_ctrl.v:85-88`） | "呼吸开关是关的（`zoom off`）⇒ 这一档暂时不会生效，要么 `zoom on`，要么 `zoom fit 1` 交给角度" |
| 4 | `zoom fit 0` 的"回到手动档/呼吸自动档" | `cur_zoom=0` 时实际回到 1.00x，那句是错的 | 三个分支：`手动档` / `呼吸` / `1.00x（因为 zoom off）` |
| 5 | `rot speed <n>` 而 `rot auto 0` | 只报"speed=n 度/帧" | "（`rot auto` 现在是关的 ⇒ 这个转速要 `rot auto 1` 才看得见）" |
| 6 | `play` / `fill` / `frame N` 而模式被钉住 | 写了 DDR 与发布，画面不动，回声不提模式 | 读 `cur_mode_ovr`（`main.c:178`）：非 AUTO 时补一句"屏此刻钉在 %s ⇒ 这一路不会上屏，先 `src auto` 或 `src 2`" |
| 7 | `pipe` 含 `[6]` 而 `[5]=0` | `print_sel_names` 把 `bin_pol` 列为"生效" | "bin_pol 是 binary 的修饰位，`[5]=0` 时无人读它（`proc_pipeline.v:131`）⇒ 要它就用 `001100000` 这种 `[5][6]` 同开的写法" |
| 8 | `pipe` 含 `[7]`＋`[8]` | 列出 `erode dilate`，画面上两个都没做 | "腐蚀与膨胀同开＝明确旁路（开/闭要两遍窗口，`proc_morph.v:22-24`）⇒ 屏上 `Pipe:` 第五格会是 0，以那一格为准" |
| 9 | `th <n>` 而 binary/erode/dilate 全 0 | 只报 `[CTRL] thr=n` | "（这一位只被 binary 与 morph 读；现在这两位都没开 ⇒ `th` 不会改变画面，开一个：`pipe 000001000`）" |
| 10 | 任何让屏上几乎全是原图的缝位（`split ≥ 99%`） | 效果链照旧回显"开着" | 在 `split` 的回声尾部加一句"处理图只剩一列 ⇒ 想看清 `pipe`/`gamma` 把缝放回中间（`split 50`）"；判据就是 `split_display.v:49` 那一次选择 |
| 11 | `bilin show` 的条件句 | 只讲旋转态与整数倍率 | 补第三条：源画面最后一列/最后一行按构造退化成最近邻（`fb_bilin.v:51-54`） |
| 12 | 没有 `zoom show` | `zoom show` 落到通用拒绝（`main.c:951-954`） | 要么补一条与 `split show` 同形的回显（念 fit/zman/zsel/`zoom_en` 四个来源与合成结果），要么在拒绝消息里明说"缩放的状态读 `stat` 的 zsel/zman ＋ `rot show` 的 `zoom=` 半句" |
| 13 | `main.c:1207-1214` 与 `main.c:1222` | 注释断言"PL 没人读 `gpio_o[19]`"，与 `system_top.v:270`、`pl_video_top.v:251-262` 矛盾；`main.c:1222` 那条 `not_wired("bilin", …)` 走不到 | 改注释并删掉走不到的那一行；这属于文档性腐烂，不改变行为，但会把下一个查 bilin 的人引到 PL 侧去 |

---

## 13. 与 `docs/COMMANDS.md` 的差异

按"以代码为准"的规矩登记，本轮不改那份文件。

1. **`docs/COMMANDS.md:135`**："`zoom fit 1 / 0` 缩放跟着旋转角度定（屏上 Zoom 格标 (Fit)）；
   `zoom 1.5` 那套八档手动仍然有效"。
   后半句与代码不符：fit=1 期间 `zman/zsel` 只被**保存**，不生效，
   `inv_used` 走 `inv_fit` 那一支（`zoom_ctrl.v:58`、`80`）。
   准确说法是"仍然保留，`zoom fit 0` 之后的下一个帧首接管"（`zoom_ctrl.v:89`）。
2. **`docs/COMMANDS.md:112`**：`zoom on / zoom off 右窗缩放开关`。
   这一行没说明它同时是手动档与呼吸的**闸门**（`zoom_ctrl.v:85-88` 排在 `:89` 之前），
   也漏了"它盖不住拟合"（`:80` 排在 `:85` 之前）。不算正面冲突，但按 §2 补全才不会被念成
   "关了 zoom 画面就不会缩放了"——开了 fit 时它照样缩。
3. **`docs/COMMANDS.md:219`**："`zman=1` 才生效（0 = 自动呼吸）"。
   这只在 fit=0 且 `zoom_en=1` 时成立；fit 位（`:221` 行同一张表）优先级更高，
   而表格按位平铺，读起来像四个位互不相干。
4. **`docs/COMMANDS.md:131`**："`gamma 1.8` … 只作用于**右窗**"与第 6 节第 1 条"pipe 生效在右窗"
   （`docs/COMMANDS.md:231`）。缝位可调之后"右窗"已经不是执行侧的说法：
   混色级的判据是 `take_orig`（`split_display.v:48-49`），由缝位、`swap`、follow 三个位共同决定，
   `split 100` 时整屏都是原图抽头。这两句在缝固定在中点的场合仍然成立，作为口径描述不完整。

其余部分（`rot auto 1` 的两件顺带事、缝位 10 位夹到 1023、`src` 三个词、位预算表）
与今天代码逐条对得上，本文没有异议。
