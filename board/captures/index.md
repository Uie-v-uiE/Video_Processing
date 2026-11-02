# `board/captures/` · 抓图 / 波形 / 导出件索引件（不复制大文件）

登记口径同 `board/logs/index.md`：真实路径 + 日期 + 构建指纹 + 摘要 + 旁边是哪张采集条件卡。
**这一类里最容易犯的错是"文件存在 = 采集成功"** ⇒ 本表把"容器存在"和"容器里有内容"分成两列。

## 1. 参考侧抓图（软件渲染，属"软件算出"，不是板级输出）

| # | 真实路径 | 日期（登记日 / 首次入库） | 字节 | 规范化 sha256 前 8 | 摘要相符? | 内容摘要（manifest 精度口径列） | 条件卡 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| K01 | `data/golden/src.png` | 2026-10-04 / `fc314bb`（2026-09-18） | 5252 | `73c82e13` | OK | 8 bit/通道 RGB、colortype=2、640×360 | 卡 D1 |
| K02 | `data/golden/rot_000.png` | 同上 | 5252 | `73c82e13` | OK | **与 K01 逐字节相同**（0° 档就是源图本体，`cmp` 无输出） | 卡 D1 |
| K03 | `data/golden/rot_030.png` | 同上 | 7279 | `97bf6fca` | OK | 同上；旋转插值算术 `【未核实】` | 卡 D1 |
| K04 | `data/golden/rot_045.png` | 同上 | 7862 | `b8fe4fc5` | OK | 同上 | 卡 D1 |
| K05 | `data/golden/rot_090.png` | 同上 | 3302 | `36a4c648` | OK | 同上 | 卡 D1 |
| K06 | `data/golden/rot_180.png` | 同上 | 4851 | `a986777a` | OK | 同上 | 卡 D1 |
| K07 | `data/golden/rot_270.png` | 同上 | 3277 | `5db133be` | OK | 同上 | 卡 D1 |
| K08 | `data/golden/proc_00111.png` | 同上 | 8916 | `7d5b4479` | OK | 警告：文件名那五位是**旧效果位口径**，现行 `pipe` 控制字是九位 ⇒ 不许按字面读成当前 `stage_sel` | 卡 D1 |
| K09 | `data/golden/proc_10000.png` | 同上 | 3523 | `283215d0` | OK | 同上一行 | 卡 D1 |
| K10 | `data/golden/proc_all.png` | 同上 | 4613 | `dd57c368` | OK | 同上 | 卡 D1 |
| K11 | `data/golden/dual_preview.png` | 同上 | 10721 | `585b81d9` | OK | 8 bit/通道 RGB，**1280×360**（左右并排各 640×360） | 卡 D1 |
| K12 | `data/golden/frame_640x360.mem` | 同上 | 1382400 | `380ae5ba` | OK | 16 bit RGB565 定点、640×360、230400 行、CRLF；整帧只有 12 个不同取值 ⇒ **色块图卡** | 卡 D1 |
| K13 | `data/golden/README.md` | 2026-10-04 / `8e03330`（改 `884c896`） | 2499 | `4bfcd0e4` | OK | 文本，无量化口径 ⇒ **不进任何比对表**（manifest §3 自己就这么写） | 卡 D1 |

复算命令（就是 `data/golden/manifest.md` §2 那条，本轮 13 行全算，结果落在
`board/compare/golden-digest-verify.txt`：**13 行 OK / 0 行 FAIL**）：

```bash
awk '/^\|[ ]*data\/golden\//{split($0,a,"|");gsub(/^[ \t]+|[ \t]+$/,"",a[2]);gsub(/`/,"",a[3]);print a[2]" "a[3]}' \
  data/golden/manifest.md | while read -r f h; do
  got=$(node -e 'const fs=require("fs"),c=require("crypto");const b=fs.readFileSync(process.argv[1]);
    const n=Buffer.from(b.toString("latin1").replace(/\r\n/g,"\n").split("\n")
      .map((s)=>s.replace(/[ \t]+(?=\n)/,"")).join("\n"),"latin1");
    console.log(c.createHash("sha256").update(n).digest("hex"))' "$f")
  [ "$got" = "$h" ] && echo "OK   $f" || echo "FAIL $f"; done
```

## 2. 上位机渲染的板级预览（不是屏摄）

| # | 真实路径 | 日期 | 字节 | 产生程序 | 条件卡 |
| --- | --- | --- | --- | --- | --- |
| K14 | `board/card_v2_preview.png` | 2026-09-25 16:00 | 5622 | `src/host/card_preview.mjs`（写 `<prefix>_f*.png` / `<prefix>_strip.png`；入库说明见 commit `30df9bf`，2026-09-24，"取景器 tb_v83/card_preview（一分钟看图，省一轮 40 分钟构建）"） | 卡 C2（同类：host 渲染，非板读） |

警告：这一件是**图卡的样子**，不是**屏上显示的样子**：`card_preview.mjs` 走的是 host 侧渲染路径，
和 PL 里 `test_card` 的算术不是同一条（所以它只能当"设计者预览"，不能当板上输出与 `data/golden/` 的中介）。

## 3. 仿真波形导出（唯一的"波形"类）

复算命令：`for f in sim_work/*.vcd; do printf "%s bytes=%s ts=%s vars=%s\n" "$f" "$(stat -c %s $f)" "$(grep -c '^#' $f)" "$(grep -c '^ *\$var' $f)"; done`

| # | 真实路径 | 日期 | 字节 | 时间戳事件 | 声明信号数 | 容器里有内容? | 条件卡 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| K15 | `sim_work/tb_eth_video.vcd` | 2026-09-27 18:52 | 96982 | 624 | 136 | 是 | 卡 C2 |
| K16 | `sim_work/tb_rotate_window.vcd` | 2026-09-27 18:53 | 158123 | 552 | 416 | 是 | 卡 C2 |
| K17 | `sim_work/tb_udp_parser.vcd` | 2026-09-27 18:53 | 20156 | 440 | 61 | 是 | 卡 C2 |
| K18 | `sim_work/tb_udp_reasm.vcd` | 2026-09-27 18:54 | 231453 | 4308 | 72 | 是 | 卡 C2 |
| K19 | `sim_work/tb_v796_src_arb.vcd` | 2026-09-27 18:55 | 178 | **0** | **0** | **否 ⇒ `NOT_MEASURED`** | 卡 C2 |
| K20 | `sim_work/tb_v80_ku5p_cmd.vcd` | 2026-09-27 18:55 | 178 | **0** | **0** | **否 ⇒ `NOT_MEASURED`** | 卡 C2 |
| K21 | `sim_work/tb_v81_test_card.vcd` | 2026-09-27 18:55 | 179 | **0** | **0** | **否 ⇒ `NOT_MEASURED`** | 卡 C2 |

所有 VCD 的 `$version` 都是 `2025.2.1`、`$timescale 1ps`（件内自报）⇒ 时间口径是仿真时间，
**不能**与板级 `[STAT]` 的 `ms` 或 `Latency=6ms` 那类读数放进同一行。

## 4. 这一类里"仓库里没有"的（缺口如实登记）

| 缺什么 | 后果 | 需要谁落地 |
| --- | --- | --- |
| 板级屏摄/截图（HDMI 采集或手机拍屏的文件 + 采集时刻） | 所有"屏上看起来对"的观察都只能标 **人眼报告（无仪器证据）**，不得进比对表（P16b 铁律 1） | 队伍的手/眼睛 + 一个存图位置 |
| 板级抓帧（把帧缓存 512×300 或 DDR 里的真实画面读成文件） | 与 `data/golden/frame_640x360.mem` / 6 张 `rot_*.png` / 3 张 `proc_*.png` 的逐元素比对**无法进行** ⇒ 全部记 `NOT_MEASURED` | P16a 的运行脚本 + 一支"读帧缓存"的尺子（`src/host/ddr_verify.mjs` 现在只读图案自校验） |
| 逻辑分析仪 / 示波器导出 | 帧率、时延、抖动三格的"时间基准来源"只能落在固件自报或上位机 OS 计时上，量程无法独立校 | 队伍的外设 |
| 与 640×360 同口径的参考件 | 参考侧是 640×360、板上处理画幅是 512×300 ⇒ 即便抓到帧也要**另起一行**（铁律 4：换口径另起一行） | P17 决定：改基准还是改口径说明 |
