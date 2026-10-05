# 命令优先级与覆盖关系

## 0. 这一页回答什么

固件里有一条默认的假设：**串口回声说的就是屏上正在做的事**。这一页列出这条假设不成立的全部位置——
即那些"命令确实被收到、确实写了寄存器、但对画面的贡献是零"的场合，并给出每一处的判定条件与出处。
读法有三条规矩：

- 结论只以代码为出处，格式是 `文件:行号`。RTL 与固件两头都要指：固件那一头决定"写了哪个位"，
  RTL 那一头决定"这个位此刻有没有被选中"。只有固件那一头的结论不算结论。
- "静默"与"有回显"分开写。这个仓已有的规矩是**不许收了却什么都不做**（token 上限那段注释
  `src/ps/main.c:620-626`、split 的通用拒绝分支 `src/ps/main.c:1206-1209` 都是按这条写的），
  所以凡是"被盖住且回声没说明"的那几条，都集中在 §12 列成待改清单。§12 只登记条件与改法，代码未动。
- 这一页不替代 `report/commands.md`（命令表）。它只管"命令同时有效时谁赢"。
  两份文档需要对齐的地方在 §13 逐条点名，以代码为准。

贯穿全文的一个区分：`stat` 打出来的每一个字段都是 **PS 侧的影子**（`src/ps/main.c:1403-1411`），
它证明"固件请求了这个值"，证明不了"像素域正在用这个值"。请求侧与执行侧的对账见 §11。

正文里的出处用短文件名（在 `src/` 下每个名字都只有一份），完整路径是：

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

行号一律按换行符计（`awk 'NR==n'` / `sed -n 'Np'` 的取法），并且取自工作区当前文本。
`src/rtl/` 下几份文件近期只整理过注释，行位与提交版本可能差几行；注释再变一次，这一批行号要重新核一遍。

---

## 1. 总表：命令 → 写哪个位 → 谁盖谁

控制字只有两只，所有命令都写进这两只（`main.c:214-225`）：`gpio_o`（`0x41200000`）与
`gpio_cfg1`（`0x41220000`，RTL 里的 `CFG_DATA0`）。物理位到逻辑位的拼接在 `system_top.v:262-293`。

| 命令 | PS 影子 → 物理位 | 执行侧的读者 | 谁盖它 | 被盖住时有没有说明 |
|---|---|---|---|---|
| `zoom <倍率>` | `cur_zsel`/`cur_zman` → `cfg1[28:26]`/`[29]`（`main.c:976`、`224-225`） | `zoom_ctrl.v:105-108` | `zoom fit 1`、`zoom off` | **没有**（§2） |
| `zoom auto` | `cur_zman=0`（`main.c:951`） | 同上 | `zoom fit 1`、`zoom off` | **没有**（§2） |
| `zoom on/off` | `cur_zoom` → `gpio_o[17]`（`main.c:519`、`215`） | `zoom_ctrl.v:101-104` | `zoom fit 1` | **没有**（§2） |
| `zoom fit 1/0` | `ZOOM_FIT_BIT` → `cfg1[31]`（`main.c:963`） | `zoom_ctrl.v:96`、`72-73` | 无人盖它（缩放链的最高优先级） | 它盖别人时会说明（`main.c:965-967`） |
| `rot auto 1` | `ROT_AUTO_BIT` → `cfg1[9]`（`main.c:1073`） | `angle_ctrl.v:43` | 无人盖 | 顺带改 `speed`、`zoom_fit`，**两处都说明**（`main.c:1076-1087`） |
| `rot speed <0..7>` | `ROT_SPEED_MASK` → `cfg1[12:10]`（`main.c:1059`） | `angle_ctrl.v:43` | `rot auto 0` | **没有**（§3） |
| `rot <绝对角度>` | 不存在 | — | — | 明确拒绝（`main.c:1099`） |
| `src 0/1/2` | `cur_mode_ovr` → `gpio_o[24:23]`＋`[22]`（`main.c:510-513`） | `src_mode.v:75-82`→`pl_video_top.v:595` | 长按 KEY1 一次交还；`have_src` 能否决 | 说明了钉住与交还（`main.c:514`） |
| `src auto` | 同上，码=AUTO | `src_mode.v:82-83`（连按键环一起清） | — | 是 |
| `src 3` | 不存在 | — | — | 明确拒绝（`main.c:740-742`） |
| `SRC0/SRC1`（`src_sel`） | `cur_src` → `gpio_o[16]`（`main.c:499`、`214`） | 显示侧 `pl_video_top.v:595`；搬运机 `pl_video_top.v:696` | **显示侧：任何非 AUTO 的 mode 都让它失效**；搬运机那一路的闸门是 `owner_eth` 而不是 mode | **没有**（§4、§5） |
| `play` / `fill` / `frame N` | 只写 `cur_src`＋发布位（`main.c:1359-1360`、`715-716`、`1284`） | 搬运机 `pl_video_top.v:559`、`696` | `src 0`/`src 1` 钉住期间 | **没有**（§5） |
| `split <pct>` / `split px <n>` | 清 `SPLIT_AUTO_BIT`、写 `pos_px`（`main.c:1197`、`1187`） | `split_ctrl.v:94` | 无人盖（它自己盖 `auto`） | 说明"manual"（`main.c:1200`、`1188`） |
| `split auto` | `SPLIT_AUTO_BIT` → `cfg1[23]`（`main.c:1125`） | `split_ctrl.v:94`、`102` | **它盖 `pos_px`** | 半说明（§6） |
| `split follow 1` / `split video` | `SPLIT_FOLLOW_BIT` → `cfg1[24]`（`main.c:1145-1147`、`1171`） | `split_ctrl.v:33` | 与 `auto` 同时开时新的 `pos` 不动屏 | 说明了"auto 仍开着"（`main.c:1176`） |
| `split swap 1` | `SPLIT_SWAP_BIT` → `cfg1[25]`（`main.c:1147`） | `split_ctrl.v:105`→`split_display.v:47` | — | 说明了"只换内容，不换缝位"（`main.c:1152`） |
| `split marker 0` | `SPLIT_MARKOFF_BIT` → `cfg1[30]`（反着写，`main.c:1144-1145`） | `pl_video_top.v:894`→`split_display.v:63-65` | 标记线盖过缝两侧的内容 | 是（那格说明是蓝线） |
| `split range` / `split speed` | 不存在 | 端点/速度是构建参数（声明 `pl_video_top.v:19-21`，送进 `split_ctrl` 那一处 `:889`） | — | 明确拒绝（`main.c:1207-1209`） |
| `pipe <九位>` | `cur_sel` → `cfg1[8:0]`（`main.c:456`、`223`） | `proc_pipeline.v:56-65` | 缝位决定"看得见几成" | 见 §7 |
| `pipe` 的 `[6]`（bin_pol） | 同上 | `proc_pipeline.v:141` | **`[5]=0` 时无人读它** | **没有**（§8） |
| `pipe` 的 `[7]`＋`[8]` 同开 | 同上 | `proc_pipeline.v:59-60`、`proc_morph.v:24` | **两者互相抵消** | **没有**（§8） |
| `th <0..255>` | `cur_thr` → `gpio_o[15:8]`（`main.c:493`、`214`） | `proc_binary.v:23`、`proc_morph.v:34` | `[5]`/`[7]`/`[8]` 全 0 时没有读者 | **没有**（§8） |
| `gamma <γ>` | `cur_gamma` ＋ `CFG_DATA1` 表窗口 | `proc_pipeline.v:104`（级 0） | 只在"处理图"那一侧可见 | **没有**（§7） |
| `bilin on/off` | `cur_bilin` → `gpio_o[19]`（`main.c:558`、`216`） | `pl_video_top.v:251-262`→`fb_bilin.v:51-54` | 整数倍率、画面末行末列与越界格 | 说了两个条件（§9） |
| `osd on/off` | `cur_osd` → `gpio_o[20]`（**反相**：写 1 = 关，`main.c:567-571`、`217`） | `pl_video_top.v:265-276`→`osd_overlay.v:58`、`518` | 无人盖它（只作用于输出级那一个选择） | 是（`show` 那一句说清只影响叠字） |
| 裸五位串 / `pipe 00111` | 不写任何位（`main.c:461-467`） | — | — | 回一句等价的九位 |

---

## 2. 缩放：四个来源，一条有先后的链

命令表看起来是三个来源（呼吸 / 手动档 / 按角度拟合），但执行侧实际是**四个输入、一条 if-else 链**。
第四个是 `zoom on|off`（`gpio_o[17]`，`main.c:519`），它在链里排在手动档之前。

`zoom_ctrl.v:96-110` 的分支顺序就是优先级顺序：

1. `fit_en`（`zoom_ctrl.v:96`）：整条 `inv_scale` 链被旁路，这一支**不写** `inv_scale`；
   喂给 mapper 的是 `inv_raw = fit_en ? inv_fit : inv_scale`（`zoom_ctrl.v:64`），再经一道旋转钳
   成 `inv_used`（`zoom_ctrl.v:72-73`）。
2. `!enable`（即 `zoom off`，`zoom_ctrl.v:101-104`）：`inv_scale <= INV_LO`，`INV_LO` 就是 256 = 1.00x
   （实例化时钉在 `pl_video_top.v:325`）。
3. `manual && frame_start`（`zoom_ctrl.v:105-108`）：`inv_scale <= tbl(zsel)`，八档表在 `zoom_ctrl.v:40-53`。
4. `frame_start`（`zoom_ctrl.v:110`）：呼吸，在 `[INV_LO..INV_HI]` 里每帧走一步。

于是判定条件写成一句话就是：

- **`zoom fit=1` 时，`zoom 1.5` 会被接受但不生效** —— `cur_zsel=6`、`cur_zman=1` 都真写进了
  `cfg1[28:26]`/`[29]`（`main.c:976` 与 `main.c:224-225`），同步链也把它们送到了像素域
  （`pl_video_top.v:202`），但喂给 mapper 的是 `inv_fit` 那一支（`zoom_ctrl.v:64`）。
  它不是丢了：`zoom fit 0` 之后的下一个帧首，手动档就接管（`zoom_ctrl.v:105`）。
- **`zoom off` 时，`zoom <倍率>` 与 `zoom auto` 都不生效**，屏上恒为 1.00x（`zoom_ctrl.v:101-104`）。
  上电默认 `cur_zoom=1`（`main.c:173`），所以这条平时撞不到；一旦谁为了演示按过 `zoom off`，
  后面所有 `zoom` 数值命令都只改影子。
- **`zoom off` 关不掉拟合**：`fit_en` 排在 `!enable` 之前（`zoom_ctrl.v:96` 对 `:101`），
  所以 `zoom off` ＋ `zoom fit 1` 的屏上是"跟着角度缩放的画面"，而不是"不缩放"。
- **三条命令的合成结果只有一个读数**：`inv_used`（`pl_video_top.v:318` 就把它命名为
  "本文件里此刻真的在用哪个倍率的唯一读数"）。屏上 `Zoom:` 那一格的档位号也是从 `inv_used` 分区来的
  （`zoom_ctrl.v:76-82`、`88-95`），不是从影子来的。

回声的问题在于它把"请求成功"说成"生效"：

- `zoom 1.5` 的固定回声是"[ZOOM] 1.5 → 最近档 1.50x（八档…；回自动用 zoom auto）"（`main.c:978-981`）。
  fit 开着时这句的两个半句都不成立：1.50x 此刻不在用，`zoom auto` 也不会让画面动起来。
- `ctrl_apply` 那行 `zoom_step=%d %s (%s)`（`main.c:237-238`）在 fit 开着时会印成 `1.50x (手动)`。
  这一行的原意（`main.c:235-236` 的注释）是"切回手动就会用哪一档"，但它印出来的字面就是"手动"，
  而 fit 那一支被省略了——这是这一页里唯一一处**回声主动说反**（另外几处只是不说）。
- `zoom fit 0` 的收尾半句是"关掉之后回到手动档/呼吸自动档"，取自 `cur_zman`（`main.c:965-967`）。
  如果同时 `zoom off`，实际回到的是 1.00x（`zoom_ctrl.v:101`），既不是手动档也不是呼吸。

---

## 3. 旋转：`rot auto` 与缩放拟合是绑定的，`rot speed` 不是自足的

`rot` 只有三个入口：`rot auto [0|1]`、`rot speed <0..7>`、`rot show`（`main.c:1046-1101`）。
**没有 `rot <角度>`**，注释里写明了为什么不做一个 9 位角度写窗口（`main.c:1042-1044`），
拒绝消息也会把这句话说出来（`main.c:1099-1100`）。角度只有 KEY1/KEY2 的 ±1° 这一个来源
（`angle_ctrl.v:39-42`）。

耦合与优先级有四处：

- `rot auto 1` 顺带做两件事：`speed` 为 0 时提到 2（`main.c:1074-1079`），
  `zoom_fit` 没开时把它开起来（`main.c:1081-1087`）。两件事**都在回声里明说**，
  并且给出避开的方法（"不想这样就先 `zoom fit 0` 再 `rot auto 1`"）。这是全文件里做得最标准的一处。
- `rot auto 0` 只清 `ROT_AUTO_BIT`，**不动缩放那一路**（`main.c:1093-1094`），这一点也明说了。
  也就是说 `rot auto 1` 不是可逆的：开的时候绑上了 fit，关的时候 fit 留着。
- `rot speed <n>` 在 `rot auto 0` 时不产生任何画面差别：`angle_ctrl` 的步进条件是
  `auto_en && fs_edge && (speed != 0)`（`angle_ctrl.v:43`）。回声只印"[ROT] speed=n 度/帧"（`main.c:1061`），
  不说 auto 现在是关的。
- 在 `angle_ctrl` 内部，按键的 ±1° 排在自动步进之前（`angle_ctrl.v:39-44` 是同一串 if-else 的前两支），
  所以按住键的那一帧，帧首步进被按键顶掉。这是设计意图，不需要回显。

`rot show` 印的是 `auto`、`speed`、以及 fit 位（`main.c:1047-1050`），三个都取自 PS 影子 `cur_split`；
它**不含角度**，而固件里也没有角度的串口读口（`stat` 的字段表见 `main.c:1403-1411`，
几何控制字 `geom=` 也不含角度）。要看真实角度只能读屏上 `Rot:` 那一格（`osd_overlay.v:288-291`）。

---

## 4. 片源：四层决定条件，命令只是其中一层

"屏上是哪一路"不是一条命令决定的，是四层串联的结果。从上往下：

**第一层：模式（`mode`）** —— 来源有两个，互相能盖。

- 命令侧：`src 0/1/2` → `cur_mode_ovr` → `gpio_o[24:23]` 加一次 `[22]` 翻转
  （`main.c:510-513`，两笔写的先后顺序的理由写在 `main.c:503-507`）。
- 按键侧：长按 KEY1 一次 → `ltog` → 模式环走一格（`pl_video_top.v:148-150`、`src_mode.v:87-89`）。
- 谁赢：覆盖期间长按**只交还控制权，不多走一步**（`src_mode.v:87` 的 `if (ov_en) ov_en <= 0`），
  所以命令赢在第一笔，按键赢在"一次就能解除"。生效模式是一个触发器
  `mode_q <= ov_en ? ov_act : ring`（`src_mode.v:100`）。
- `src auto` 比"取消覆盖"更彻底：它把按键环也清回 AUTO（`src_mode.v:82-83`），
  针对的正是"回了自动、再一按又钉住"。

命令的字面编号与 PL 的编码不是同一张表，这一点必须按代码念：`src 0` = TEST、`src 1` = ETH、
`src 2` = SD（`main.c:726-739`），而模式编码是 AUTO=0 / ETH=1 / TEST=2 / SD=3（`main.c:65-68`）。
所以 `src 3` 不是"第四路"，它落在拒绝分支上（`main.c:740-742`）。回声印的词与屏上印的词同源
（`osd_overlay.v:244-252`）。

**第二层：搬运机归谁（`owner_eth`）** —— 模式只是"谁想要总线"，不是"什么时候换手"。

- 模式到仲裁输入的适配在 `pl_video_top.v:171`：ETH→强制 ETH、SD→强制 PS、
  **TEST 与 AUTO 都映射成 AUTO**，理由是"图卡只是显示什么，不是谁在搬"（`pl_video_top.v:170`）。
  后果：`src 0` 期间如果网线活着，ETH 引擎照样占着 AXI 读口和帧缓存写口，只是屏上看不到它。
- 谁占总线这件事本身在 `src_arb.v`：`force_eth`/`force_ps`（`:44-45`）直接压过
  `eth_live & eth_tb_ok` 那个自动条件（`:51`），但换手仍然只在两个引擎都空闲时发生（`:67-75`），
  往 PS 让位还要等 20 ms 静默（`src_arb.v:18-19`）。

**第三层：帧缓存可见性（`fb_vis`）** —— `pl_video_top.v:595`：

```
fb_vis = (mode_card ? 1'b0 : (mode_eth | mode_ps) ? 1'b1 : src_use) && have_src;
```

这一行就是 `src_sel`（`gpio_o[16]`，也就是老写法 `SRC0`/`SRC1` 写的位，`main.c:499`）
**唯一的读者**：只有 AUTO 模式才轮到它说话。模式一旦钉住，`src_sel` 在显示侧就没有票了
（它在搬运机那边还剩一个作用，见 `pl_video_top.v:696`）。

**第四层：还有没有片源（`have_src`）** —— 会过期的活条件，能否决前三层（`src_life.v:56-57`）。
PS 这一路看的是 500 ms 内有没有过发布（`src_life.v:41-47`），而固件在停播/定点这些状态下
每 100 ms 替它报一次心跳（`main.c:242-251`、`260-269`）。心跳停了才会把画面交回仲裁（`main.c:273-278`）。

屏上 `SRC:` 那一格画的是第三层与第二层的合成结果，不是模式：
`src_eff = {fb_vis, owner_eth_pix}`（`pl_video_top.v:1014`）→ 11 印 `ETH`、10 印 `SD`、其余印 `TEST`
（`osd_overlay.v:244-252`），模式非 AUTO 时只在名字后加一个 `*`（`osd_overlay.v:252`）。

`stat` 里与片源有关的是两个字段，**都是 PS 影子**：`src=` 是 `cur_src`（bit16 那个位），
`mode=` 是 `cur_mode_ovr`（`main.c:1403-1411`）。它们合起来仍然回答不了"此刻屏上是谁"——
因为 `owner_eth` 与 `have_src` 不在 `stat` 里。真值走 lane30（`pl_video_top.v:603`，
译码在 `health_read.mjs:71-78`）。

---

## 5. 被钉住的模式下 `play` / `fill` / `frame N` 都不换画面

这是最容易被当成"命令坏了"的一组。三条命令都只写 `cur_src` 与发布位，**都不动模式**：

| 命令 | 写了什么 | 没写什么 |
|---|---|---|
| `src 2` | `cur_src=1` ＋ 踢回放 ＋ **钉模式到 SD**（`main.c:736-738`） | — |
| `play` | `cur_src=1` ＋ `sd_play(1)`（`main.c:1359-1360`） | 模式 |
| `frame N` | `sd_show()` ＋ `cur_src=1`（`main.c:1283-1284`） | 模式 |
| `fill` | 写 DDR ＋ `cur_src=1` ＋ 发布一次（`main.c:715-716`） | 模式 |

于是先 `src 1`（钉 ETH）或先 `src 0`（钉 TEST）再敲这三条，屏上一个像素都不动：

- 钉 ETH 时仲裁把总线交给 ETH（`pl_video_top.v:171`→`src_arb.v:51`），而 PS 的发布只有在
  仲裁没把屏交给 ETH 时才被消费：`pub_consume = frame_start && src_use && !owner_eth_pix`
  （`pl_video_top.v:559`）；PS 那一台搬运机也直接被禁用（`pl_video_top.v:696`）。
  屏上是冻结的最后一帧，外加 "ETH IS NO SIGNAL" 那一格（`pl_video_top.v:510`）。
- 钉 TEST 时 `fb_vis` 被强制成 0（`pl_video_top.v:595`），DDR 里那张画和发布都真发生了，
  只是显示侧不看它。

回声方面：`play` 那句是 "[SD] playing (stop / play 0 结束; ETH 有流时会自动让位)"（`main.c:1363`）。
它只覆盖了 AUTO 模式下的交接，既没说"模式现在是钉住的"，也没覆盖钉 TEST 的情形。
`fill` 完全没有自己的回声（只有 `ctrl_apply` 的 `[CTRL]` 行，`main.c:232`）。

---

## 6. 分割线：`auto` 盖住 `pos_px`，`follow` 换的是坐标空间

`split` 家族写的是同一只几何字的相邻位（`main.c:120-141`）。四种"谁盖谁"：

**（a）`split auto` 盖住缝位数值。** 执行侧的选择器是
`raw_sel = auto_en ? swp : pos_px`（`split_ctrl.v:94`），
输出再夹进当前端点（`split_ctrl.v:102`）。所以 auto 开着的时候 `pos_px` 那位还留着，
但**不是此刻的缝**。反过来 `split <pct>` 与 `split px <n>` 会顺手把 auto 清掉
（`main.c:1197`、`main.c:1187`），回声带 "(manual)"（`main.c:1200`、`main.c:1188`），
所以顺序不同结果不同：`split 30` → `split auto` 里那个 30 只当成扫描的起点
（`split_ctrl.v:76` 在手工模式下把 `swp` 跟住 `pos_px`，为的就是打开 auto 那一瞬间不跳位）；
`split auto` → `split 30` 则扫描被关掉。

**（b）`follow` 盖的是"这个数字是什么单位"。** PL 里
`wire [16:0] W = follow ? SRC_W17 : DISP_W17;`（`split_ctrl.v:33`），
固件这一侧镜像同一个条件（`main.c:1111`：`w = follow ? SPLIT_SRC_W : SPLIT_DISP_W`）。
于是同一个 `split 60` 有两种物理位置：显示列空间是第 614 列，画面列空间是第 307 列。
`split show` 会念出当前空间（`main.c:1114`），屏上 `Split:` 那一格念的是百分比而不是列
（`osd_overlay.v:300-303`）。

不匹配的那一支由夹住来兜：`split px <n>` 的上限取**当前空间**的宽（`main.c:1181`），
超出就拒绝并说明是哪个空间；PL 侧还有一道 `raw_sel > W ? W` 的夹（`split_ctrl.v:98`）。
固件注释里写的正是这个改动的动机：不换算的话 `split 60` 在 follow 下算出 614，
被 PL 夹到画面右端，而屏上那格还印 60%（`main.c:1107-1110`）。

**（c）字段宽度盖住"100%"。** `pos_px` 只有 10 位（`cfg1[22:13]`），屏幕宽 1024，
所以 1024 这个值装不下，`1024<<13` 会串进 `auto` 那一位（`main.c:125-136` 把两种历史症状都写了）。
现在的处置是写口之前夹到 1023 并把"夹过"这件事交给调用方印（`split_pos_clamp`，`main.c:165-169`；
三处写口分别带 `main.c:1177`、`1190`、`1203` 的尾巴），回声里的百分比由**存进去的值**反算
（`main.c:1200-1203`），所以 100% 会念成 99%。

**（d）`marker` 与 `swap` 是内容级的事。** 标记线位在 `cfg1[30]`，语义反着写
（1 = 关，`main.c:1144-1145`；执行侧 `split_marker_on = ~gp[13]`，`pl_video_top.v:894`），
而它在混色级排在内容之前：`if (sep && de)` 直接画蓝（`split_display.v:63-65`）。
`swap` 只翻 `raw_on_left`（`split_ctrl.v:105`），不改缝位（回声明说，`main.c:1152`）。
follow 打开时"哪一格算缝的左侧"改由源头那一拍判定（`seam_src`，`pl_video_top.v:903-908`，
`split_display.v:44`、`47`），这条写口的注释说清了它是 V9-1 才真的换坐标空间的（`main.c:1150`）。

---

## 7. 分割线位置决定整条效果链可见不可见

缝两侧的像素来自同一份源坐标、两个抽头：`orig_pix`（链子之前）与 `proc_pix`（链子之后），
选择器是 `sel = oob ? 黑 : (take_orig ? orig : proc)`（`split_display.v:48`）。
gamma 是链子的第 0 级（`proc_pipeline.v:104`，`en=0` 时逐位旁路），
`th`/`pipe` 都在它后面（`proc_pipeline.v:141`、`147`）。

于是这三条推论都是位级的事实，而不是观感：

- `split 100`（存成 1023，§6c）时几乎整屏都是原图抽头 ⇒ `pipe`、`th`、`gamma` 全都"看不出在动"。
  固件注释里把这一条当作要防的症状写过（`main.c:128`：要"整屏处理图"结果得到"整屏原图"）。
- `split 0` 时整屏都是处理图，缝两侧的对照就没了。要对照就得把缝放在中间，
  或者用 `split swap` 换边而不是挪缝（`main.c:1152`）。
- "处理只作用于半屏"是这个设计的定义而不是缺陷（`report/commands.md` §8 第 1 条就是这么写的），
  但**没有一条回声会提醒它**。当屏上是整屏原图的时候，`stat` 里的 `sel=` 与 `gm=` 仍然显示
  "效果开着、γ 开着"（`main.c:1409-1410`），因为它们读的是影子。

---

## 8. 九位效果字内部：修饰位与被抵消的一对

九位是"一位一级"，但级与级之间有三条不成对的规则，代码都在 RTL 一侧：

- **`[6]`（bin_pol）是 `[5]`（binary）的修饰位，不是独立的一级。**
  它唯一的读者是 `proc_binary` 的 `.pol(bin_pol)`（`proc_pipeline.v:141`），
  而同一个例化的 `bypass(~w_bin)` 在 `[5]=0` 时把这一级整个旁路掉——
  于是 `pipe 010000000` 这一位写进去了，没有任何像素会因它改变。
  模块文件头自己写了这条约束（`proc_pipeline.v:6`，"只在 `[5]=1` 有意义"）。
- **`[7]` 与 `[8]` 同时为 1 时两个都不做。** `w_erode = sel[7] & ~sel[8]`、
  `w_dilate = sel[8] & ~sel[7]`（`proc_pipeline.v:59-60`），合成 `morph_mode=0`；
  而 `proc_morph` 把 `mode==0` 与 `mode==3` 都当旁路
  （`proc_morph.v:24`，理由写在 `proc_morph.v:22-23`：开/闭运算要两遍 3×3 窗口）。
  这不是"后写的盖住先写的"，是**两位互相抵消**。
  与之对照：`[2]`/`[3]`（模糊/锐化）是串联的两个窗口级，同开就都做（`proc_pipeline.v:119-125`），
  所以互斥只有级 5 这一处。
- **`th` 只有两个读者。** `proc_binary` 的亮度比较（`proc_binary.v:23`，极性由 `pol` 翻，`:24`）
  与 `proc_morph` 自己那一次二值化（`proc_morph.v:34`）。
  所以当 `[5]`、`[7]`、`[8]` 全为 0 时，`th` 的任何取值都不改变画面；
  而 `[7]` 或 `[8]` 单独开着时 `th` 仍然有效（形态学自带一次亮度判决）。

回声的问题：`print_sel_names` 把每一位的名字按 `cur_sel` 的置位列出来（`main.c:600-610`），
它列的是"置了哪些位"，不是"哪些位此刻在做功"。于是 `pipe 110000000` 会得到
"[PIPE] sel=160 生效: erode dilate"，而画面上腐蚀与膨胀都没发生。
同一件事屏上反而更诚实：`Pipe:` 那五格是"每级选了第几个算法"的成对编码，
阈值格只可能 0/1/2（`osd_overlay.v:138`）、形态学格在两位同开时给 0（`osd_overlay.v:143`）。
**串口说"生效: erode dilate"、屏上第五格是 `0`——这就是请求侧与执行侧不一致时该读哪一个的规矩。**

---

## 9. `bilin` 的空转条件

`bilin on|off` 是真接到硬件的：`gpio_o[19]`（`main.c:558`、`216`）→ 3 级同步成 `bilin_en_pix`
（`pl_video_top.v:251-262`）→ `fb_bilin` 的 `bilin_en`（`pl_video_top.v:738`）。
它不改变画面的几何，只改变取样的插值方式，所以有几种情况下 on 与 off 逐位相同：

- 整数倍率（1.00x、0.50x）：非旋转那一支的逆映射本来就没有小数步长
  （`zoom_mapper.v:92-93` 取的是 `raw_xs[7:0]`，`inv` 是 2 的幂时那八位恒 0）。
- 采样落在源画面最后一列/最后一行：`(!bilin_en || sx >= IMG_W-1) ? 8'd0 : fx`
  （`fb_bilin.v:51-54`），边界格本来就折回最近邻；越界那一支更早就被 `oob` 判成黑（`zoom_mapper.v:100-105`）。

**旋转态不再是空转**：mapper 的旋转支以前在这里把小数钉成 0（`bilin on` 在旋转态是空头支票），
那一条已经改掉了——小数现在真的接给插值，并且纵向翻号与 floor 一起改（`zoom_mapper.v:70-93`）。
固件的 `bilin show` 说的就是这件事（"看得出的条件：倍率非整数（旋转态也算）"）。

`bilin show` 把上面这些讲出来了，而且给了一条可复现的对照序列
（`main.c:990-991`：`src 0` → `zoom 1.5` → `bilin off/on`）。这个开关在源码里曾经有两处互相矛盾的
说法，现在都清了：一处注释断言"缺的是 PL 侧没人读 `gpio_o[19]`"，并把上面那次前缀匹配指到 801 行；
另一处是它下面那条 `not_wired("bilin", …)` 的"待接"提示。两处都不成立——`system_top.v:286` 已经把这一位
接进 `pl_video_top`，`pl_video_top.v:251-262` 同步、`fb_bilin` 在读——所以整段连同那条提示一起删了，
`main.c:1253-1256` 现在是把连线讲清的那四行。删它不需要先证明行为：`main.c:983` 的
`ci_pre(tk[0], "BILIN")` 是前缀匹配，`ci_eq(tk[0], "BILIN")` 的严格超集，同一个 `dispatch()`
（`main.c:890` 起）里前者优先 ⇒ 那条提示**不可能**被执行。

---

## 10. 语法收了、但不写任何位的写法

这几条不是"被别的命令盖住"，而是本来就没有出口。放在一起是因为它们在串口上的表现相同：
一句解释、零状态改动。**它们都已经有明确回声**，列在这里是为了和 §11 那几条"沉默的"区分开。

| 写法 | 现在的行为 | 出处 |
|---|---|---|
| 裸五位串（`00111`）、`pipe 00111` | 一个位都不写，回一句等价的九位 | `main.c:457-468`、`905` |
| `pipe` 给 6/7/8 位 | 拒，不做补零解释 | `main.c:576-590`、`909-914` |
| `src 3` | 拒，并念出 0/1/2 的词表 | `main.c:740-742` |
| `rot 37` / `rot angle …` | 拒，并说明角度只走按键 | `main.c:1099-1100` |
| `split range …` / `split speed …` | 拒，并说明端点与速度是构建参数 | `main.c:1207-1209`；参数在 `pl_video_top.v:19-21`（声明）与 `:889`（送进 `split_ctrl`） |
| `zoom show` | **不存在**：落到 `ZOOM` 的通用拒绝消息 | `main.c:985-988`（对照 `split show` 在 `main.c:1113`） |
| `gamma auto` 参数越界 | 拒，并把收到的四个数原样念出来 | `main.c:329-334` |
| `temp th` 参数不是十进制 | 退回 85 并说明 | `main.c:850-858` |
| 一行超长 / 半行搁置 | 报一条并丢掉，不静默截断 | `main.c:1523-1527`、`1456-1475` |

`osd on|off` 以前在这一张表里（那句"语法已收、硬件未接"的提示），现在不是了：它写的是
`gpio_o[20]` 那一位（见 §1 与 `report/commands.md` §4）。固件里那个 `not_wired("osd", …)` 桩
已经跟着删掉，删它的理由留在 `main.c:1013-1018` 的注释里——留一条永远走不到的待接分支
就是"两处各说一遍"。

---

## 11. 怎么确认此刻真的在用哪一路

原则：**先读执行侧，再读影子。** 影子的字段清单在 `main.c:1403-1411`（`stat` 那一行的字段顺序被
串口回归清单按前缀解析，所以只能往后加，`main.c:1394-1402`）。

| 想知道的事 | 读哪里 | 出处 |
|---|---|---|
| 此刻倍率是多少 | 屏上 `Zoom:` 那五位档位（由 `inv_used` 分区得到） | `zoom_ctrl.v:76-95`、`osd_overlay.v:140-158` |
| 此刻倍率是哪一路给的 | 屏上后缀：`(Fit)` = 角度定的，`(Auto)` = 呼吸在跑，**无后缀** = 手动档**或** `zoom off`（合成式要求 `zoom_run`） | `osd_overlay.v:295-296`；三个旗标的合成 `pl_video_top.v:1010-1011` |
| 同上，但不看屏 | lane23 的 `zoom_fit`（bit19，念作"请求拟合 或 被旋转钳住"）与 `[9:0]`（`inv_used`） | 位序唯一出处 `pl_video_top.v:680-687`；译码 `src/host/health_read.mjs:87-100`，**期望值只有一处实现** `:120`（`zoomJudge`，人读那一支与 `--json` 共用它） |
| 请求侧写了什么 | `stat` 的 `zsel=`/`zman=`、`zoom=`；`rot show` 的 `zoom=fit/now` | `main.c:1403-1407`、`1047-1050` |
| 屏上此刻是哪一路 | 屏上 `SRC:` 的名字（`{fb_vis, owner_eth}`），尾部 `*` 才表示"被钉住" | `pl_video_top.v:1014`、`osd_overlay.v:244-252` |
| 为什么归这一路 | lane30：`owner_eth`/`eth_live`/`eth_tb_ok`/`why_ps` | `pl_video_top.v:603`、`src_arb.v:35-39`、`73`；译码 `health_read.mjs:71-78` |
| 模式请求 | `stat` 的 `mode=`（AUTO/ETH/TEST/SD 的**编码**，不是词） | `main.c:1410`、编码表 `main.c:65-68` |
| 此刻生效的是哪几级效果 | `pipe show` 念名字；屏上 `Pipe:` 念成对编码 | `main.c:600-610`、`osd_overlay.v:133-143` |
| `th` 此刻有没有读者 | `pipe show` 里有没有 binary / erode / dilate | 读者只有 `proc_binary.v:23`、`proc_morph.v:34` |
| 缝在哪个坐标空间 | `split show` 的"画面列/显示列"与 `pos=<n>/<W>` | `main.c:1113-1122`；空间由谁定的唯一出处 `split_ctrl.v:33` |
| 缝是不是在被自动扫 | `split show` 的 `auto/manual`；屏上 `Split:` 后面的 `(Auto)` | `main.c:1118`、`osd_overlay.v:300-303` |
| 几何控制字整字（含 fit 位） | `stat` 的 `geom=%08x`（PS 影子），bit31 = zoom_fit | `main.c:1403-1411`、`main.c:158` |
| 此刻的角度 | **只有屏上 `Rot:` 那一格**；固件没有角度读口 | `osd_overlay.v:288-291`；对照 `main.c:1047-1050`、`1403-1411` |
| 温度/延时的屏上格 | `temp` 那一行末尾同时给 `degC`/`osd`/`gpio` 三种写法 | `main.c:873-891` |

把上面这些串成一次自查的最小序列（每条都能独立判过与不过；不需要眼睛看屏幕的只有 lane23/lane30 那两个）：

```
stat                     影子：zsel zman mode geom
rot show                 请求侧的 fit 位
split show               请求侧的坐标空间与 auto
pipe show                请求侧的九位
node src/host/health_read.mjs    执行侧：lane23（倍率与 fit）、lane30（谁占着屏）
```

---

## 12. 建议改代码的地方（这一页只登记，代码未动）

改法统一遵循同一条已经写进本仓的规矩：**状态改了就要说出来**
（先例是 `main.c:1076-1087` 的 `rot auto 1` 与 `main.c:1163-1177` 的 `split screen`：
既说出顺带改了什么，也说出怎么避开）。下面每一条都只加回声，不改任何位的写法，
因此不影响 elf/bit 的配套关系，也不新增跨域。

| # | 命令 | 现在的行为 | 建议回显 |
|---|---|---|---|
| 1 | `zoom <倍率>` 而 fit=1 | 写 `zsel/zman`，报"最近档 1.50x；回自动用 zoom auto"，画面不动 | 追加一句"fit 开着 ⇒ `inv_used` 由角度定，本档要到 `zoom fit 0` 才接管（现在这样写就行：`zoom fit 0`）" |
| 2 | `ctrl_apply` 的 `zoom_step=… (手动)` | fit 开着时仍印"手动" | 三个状态都印：`手动` / `呼吸` / `拟合中，本档暂不生效`（条件取 `cur_split & ZOOM_FIT_BIT`，`main.c:963` 已经在维护这个影子） |
| 3 | `zoom <倍率>` 或 `zoom auto` 而 `zoom off` | 写了位，屏上恒 1.00x（`zoom_ctrl.v:101-104`） | "呼吸开关是关的（`zoom off`）⇒ 这一档暂时不会生效，要么 `zoom on`，要么 `zoom fit 1` 交给角度" |
| 4 | `zoom fit 0` 的"回到手动档/呼吸自动档" | `cur_zoom=0` 时实际回到 1.00x，那句是错的 | 三个分支：`手动档` / `呼吸` / `1.00x（因为 zoom off）` |
| 5 | `rot speed <n>` 而 `rot auto 0` | 只报"speed=n 度/帧" | "（`rot auto` 现在是关的 ⇒ 这个转速要 `rot auto 1` 才看得见）" |
| 6 | `play` / `fill` / `frame N` 而模式被钉住 | 写了 DDR 与发布，画面不动，回声不提模式 | 读 `cur_mode_ovr`（`main.c:198`）：非 AUTO 时补一句"屏此刻钉在 %s ⇒ 这一路不会上屏，先 `src auto` 或 `src 2`" |
| 7 | `pipe` 含 `[6]` 而 `[5]=0` | `print_sel_names` 把 `bin_pol` 列为"生效" | "bin_pol 是 binary 的修饰位，`[5]=0` 时无人读它（`proc_pipeline.v:141`）⇒ 要它就用 `001100000` 这种 `[5][6]` 同开的写法" |
| 8 | `pipe` 含 `[7]`＋`[8]` | 列出 `erode dilate`，画面上两个都没做 | "腐蚀与膨胀同开＝明确旁路（开/闭要两遍窗口，`proc_morph.v:22-24`）⇒ 屏上 `Pipe:` 第五格会是 0，以那一格为准" |
| 9 | `th <n>` 而 binary/erode/dilate 全 0 | 只报 `[CTRL] thr=n` | "（这一位只被 binary 与 morph 读；现在这两位都没开 ⇒ `th` 不会改变画面，开一个：`pipe 000001000`）" |
| 10 | 任何让屏上几乎全是原图的缝位（`split ≥ 99%`） | 效果链照旧回显"开着" | 在 `split` 的回声尾部加一句"处理图只剩一列 ⇒ 想看清 `pipe`/`gamma` 把缝放回中间（`split 50`）"；依据就是 `split_display.v:48` 那一次选择 |
| 11 | `bilin show` 的条件句 | 只讲"倍率非整数"这一条 | 补第二条：源画面最后一列/最后一行与越界格按构造退化成最近邻（`fb_bilin.v:51-54`、`zoom_mapper.v:100-105`） |
| 12 | 没有 `zoom show` | `zoom show` 落到通用拒绝（`main.c:985-988`） | 要么补一条与 `split show` 同形的回显（念 fit/zman/zsel/`zoom_en` 四个来源与合成结果），要么在拒绝消息里明说"缩放的状态读 `stat` 的 zsel/zman ＋ `rot show` 的 `zoom=` 半句" |
| 13 | `main.c:1263-1270` 与 `main.c:1278` | 注释断言"PL 没人读 `gpio_o[19]`"，与 `system_top.v:286`、`pl_video_top.v:251-262` 矛盾；`main.c:1278` 那条 `not_wired("bilin", …)` 走不到 | 改注释并删掉走不到的那一行；这属于文档性腐烂，不改变行为，但会把下一个查 bilin 的人引到 PL 侧去 |

---

## 13. 与 `report/commands.md` 对齐的四处

这两份文档按同一份代码写。以下四处是最容易被念错的，命令表里已经按代码写全，
这里把判定条件记下，免得下一次改回旧说法：

1. **`zoom fit [0|1]` 那一行**。"`zoom 1.5` 那套八档手动仍然有效"这半句不准确：fit=1 期间
   `zman/zsel` 只被**保存**，不生效，喂给 mapper 的是 `inv_fit` 那一支（`zoom_ctrl.v:64`、`96`）。
   准确说法是"仍然保留，`zoom fit 0` 之后的下一个帧首接管"（`zoom_ctrl.v:105`）。
2. **`zoom on / zoom off` 那一行**。它同时是手动档与呼吸的**闸门**（`zoom_ctrl.v:101-104` 排在 `:105` 之前），
   而它盖不住拟合（`:96` 排在 `:101` 之前）。只写"右窗缩放开关"会被念成"关了 zoom 画面就不会缩放了"——
   开了 fit 时它照样缩。
3. **位预算表里 `zman` 那一行**。"`zman=1` 才生效（0 = 自动呼吸）"只在 fit=0 且 `zoom_en=1` 时成立；
   fit 位在同一只字的 `[31]`，优先级更高。表格按位平铺，读起来像四个位互不相干，所以命令表把
   缩放那一行指向了这一节的链。
4. **`gamma 1.8 … 只作用于右窗`与"pipe 生效在右窗"那两句**。缝位可调之后"右窗"已经不是执行侧的说法：
   混色级看的是 `take_orig`（`split_display.v:47-48`），由缝位、`swap`、follow 三个位共同决定，
   `split 100` 时整屏都是原图抽头。这两句在缝固定在中点的场合仍然成立，作为完整描述不够，
   命令表现在写的是"处理那一侧"并把可见性那一账指到 §7。

其余部分（`rot auto 1` 的两件顺带事、缝位 10 位夹到 1023、`src` 三个词、位预算表）与代码逐条对得上。
