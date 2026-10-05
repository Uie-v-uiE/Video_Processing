# `data/golden/` 基准清单（manifest）

登记日：2026-10-04（本机 `date` 读数）。本轮只做**登记与核验**，没有改动本目录任何一个已入库文件的字节
（核实：`git status --porcelain data/golden` 只应列出本文件这一个未跟踪新件；实跑输出贴在 §5 末尾）。

## 1. 这份表管什么、不管什么

- **管**：`data/golden/` 目录下除本文件之外的每一个普通文件（本轮实测 13 个：11 张 PNG + 1 个 `.mem`
  + 1 份 `README.md`）。
  范围写成可判的条件而不是靠人记：`find data/golden -type f ! -name manifest.md`。
- **不管**：`data/measured/`（板端实测留档，是**实测侧**不是参考侧，口径见 `data/measured/README.md`）
  与 `data/metrics.csv`（那是首页数字的唯一来源，由 `src/host/metric_recheck.mjs` 逐行对回报告，
  本清单不重复管它，也不许把它当参考结果）。
- **本目录的真实定位**（读 `data/golden/README.md` 原文，不是推测）：
  这 13 个数据件是**人眼比对的参照物**，全仓库没有任何 `.v`/`.mjs`/`.sh` 读它们
  （该 README 给的核实命令也重跑过，输出在 §6 第 4 条）。
  所以这份 manifest 现在的作用是**把"谁在什么时候是什么形状"钉住**，
  一旦将来有脚本要拿它们当自动比对基准，摘要核验已经先在那儿等着了。

## 2. 内容摘要的口径（绑内容，不绑行尾）

**规范化定义**（两条，按顺序做，再对结果字节取 sha256）：

1. `0x0D 0x0A` → `0x0A`（只合并 CRLF 这一对；单独的 `0x0D` 不动）。
2. 每一行（以 `0x0A` 分隔）去掉行尾连续的 `0x20` 与 `0x09`。

为什么必须这样：本仓库 `core.autocrlf=true`（`git config core.autocrlf` 实读），而 `.gitattributes`
只给 `.v/.sv/.xdc/.c/.h/.sh/.tcl/.py/.mjs/.md` 钉了 `eol=lf`——**`*.csv`、`*.png`、`*.mem`、`*.out` 都不在名单里**。
所以同一份内容在不同机器 checkout 出来**字节可以不同而内容未变**；摘要若绑字节，下一次换环境就全体假红
（这正是 2026-09-30 夜里门禁第 15/15b 项红过的形状，见 `.gitattributes` 文件头与台账 #202）。

**因此每个文件登记两个摘要**（附表给原始字节那一个）：

| 键 | 算法 | 用途 |
| --- | --- | --- |
| 主摘要 | 规范化之后取 sha256 | 不可变的判据：跨行尾/跨平台仍然可比 |
| 副摘要 | 磁盘原始字节取 sha256 | 记录登记当日的字节形状；二进制容器的真实身份 |

警告：**规范化不是可逆的，对二进制容器它甚至可能把两个不同内容映成同一个字节串**。
本轮实测到它就发生作用了：12 个 PNG 里有 11 个 `主摘要 ≠ 副摘要`（PNG 流里天然含 `0x0D 0x0A` 与行尾空格形状），
只有 `README.md` 两个相同。所以对 PNG/GZ 这类容器，**判定"内容变了没有"以副摘要为准**，主摘要负责
"行尾换了也不许红"；两个方向不一致时按 §7 的分支处置，不许自己挑一个顺眼的当结论。

### 计算命令（复制即用）

```bash
node -e 'const fs=require("fs"),c=require("crypto");
const norm=(b)=>Buffer.from(b.toString("latin1").replace(/\r\n/g,"\n").split("\n")
  .map((s)=>s.replace(/[ \t]+(?=\n)/,"")).join("\n"),"latin1");
for(const f of process.argv.slice(1)){const b=fs.readFileSync(f),n=norm(b);
  console.log([f,String(b.length),
    c.createHash("sha256").update(n).digest("hex"),
    c.createHash("sha256").update(b).digest("hex"),
    c.createHash("sha256").update(n).digest("hex")===c.createHash("sha256").update(b).digest("hex")?"same":"diff"].join(" | "));}' \
  $(find data/golden -type f ! -name manifest.md | sort)
```

用 `latin1` 往返是**刻意的**：一个字节 ↔ 一个码位，替换与还原都是逐字节的，不存在 UTF-8 解不出来的分支，
所以同一条命令对文本和二进制都成立。（`sha256sum` 也能算，但它吃的是磁盘字节，管不了 §2 的规范化，
所以本清单以这条 node 命令为准；`sha256sum data/golden/*` 只能复算副摘要。）

## 3. 主表（P17 点名的六列）

「日期」这一列填的是**本行登记的核对日**（都是 2026-10-04，由本轮实跑算出），
文件的产生日/入库 commit 写在「产生程序与版本或来源」格里——两个日期不许混用。

| 文件名 | 内容摘要（规范化后 sha256） | 产生程序与版本或来源 | 精度口径 | 日期 | 来源类别 |
| --- | --- | --- | --- | --- | --- |
| data/golden/README.md | `4bfcd0e4bd9545bc2fd7946cb6a6a1487a4897fdc425269d21fbcd85b13fe5ff` | 本队手写说明卡；首次入库 `8e03330`（2026-09-28），最后改动 `884c896`（2026-10-01），`git log --format=%h -1 -- <文件>` 可复算 | 文本，无量化口径 | 2026-10-04 | 自产文档（不进任何比对表） |
| data/golden/src.png | `73c82e13801ff5d0d6a266a5e0575d231cf5167e52fdadc8abb21e94976bf036` | 早期 host 侧预览工具的输出，**该工具不在树里**（`data/golden/README.md` 欠账 1 原文）；最早可观察到的存在 = 首次入库 `fc314bb`（2026-09-18）。⇒ 含糊项，见 §8 | 实测 IHDR：8 bit/通道 RGB、colortype=2（无 alpha、无调色板）、640×360。渲染侧定点位数【未核实】 | 2026-10-04 | 合成（软件渲染，非拍摄；产生程序缺失 ⇒ 不可一键复现） |
| data/golden/rot_000.png | `73c82e13801ff5d0d6a266a5e0575d231cf5167e52fdadc8abb21e94976bf036` | 同上（`fc314bb` 入库）。警告：主/副摘要与 `src.png` **逐字相同**：0° 档就是源图本体，两个文件是同一份字节（实测：`cmp data/golden/src.png data/golden/rot_000.png` 无输出） | 同 `src.png` | 2026-10-04 | 合成（同 `src.png`；与 src.png 是重复件） |
| data/golden/rot_030.png | `97bf6fcae5a3a55a38cc5e6b225a2df2430c4132357b4c52d409a7b7d71af5ff` | 同 `src.png`（`fc314bb`）⇒ 含糊项 | 8 bit/通道 RGB，640×360；旋转插值的算术口径【未核实】 | 2026-10-04 | 合成（软件渲染） |
| data/golden/rot_045.png | `b8fe4fc553fac44167cb001c2824c48f4362ae4c52807af30bf2967e953ac850` | 同上 ⇒ 含糊项 | 同上 | 2026-10-04 | 合成（软件渲染） |
| data/golden/rot_090.png | `36a4c648eef277fa9ad056855b8942d7f54a1987160d8a7f70c36123aaefa7f9` | 同上 ⇒ 含糊项 | 同上 | 2026-10-04 | 合成（软件渲染） |
| data/golden/rot_180.png | `a986777adde1c4b78d058051893337d8260033626e508f405f9875b351dc7379` | 同上 ⇒ 含糊项 | 同上 | 2026-10-04 | 合成（软件渲染） |
| data/golden/rot_270.png | `5db133be7767bebcfdac90aba457ac61941f92ed1f62c7b204f96ef82f39ba43` | 同上 ⇒ 含糊项 | 同上 | 2026-10-04 | 合成（软件渲染） |
| data/golden/proc_00111.png | `7d5b4479718539df2094892953fbacec6bf8ac71bf1545f8e1213e995bbef101` | 同上 ⇒ 含糊项。警告：文件名里那五位数字是**旧效果位口径**，现行 `pipe` 控制字是九位（`data/golden/README.md` 原文警告），不许按字面读成当前 `stage_sel` | 8 bit/通道 RGB，640×360；各位对应哪种算术【未核实】 | 2026-10-04 | 合成（软件渲染） |
| data/golden/proc_10000.png | `283215d0f6ed2b59f98c719078d23c6ea3f9afd5246fb1d149eea3bbf2f1d746` | 同上 ⇒ 含糊项（五位数字口径同上一行） | 同上 | 2026-10-04 | 合成（软件渲染） |
| data/golden/proc_all.png | `dd57c368c4e35626d8431d8e527fc4a4a1c118c94d4e78e3215550963f298cf8` | 同上 ⇒ 含糊项 | 同上 | 2026-10-04 | 合成（软件渲染） |
| data/golden/dual_preview.png | `585b81d9ed5a9854199908095370e952373005af621c3adf39db916c9f1a9b39` | 同上 ⇒ 含糊项。`data/golden/README.md` 明写它"与 `split_display` 的显示方式同类，但不是同一套算术产出" | 8 bit/通道 RGB，**1280×360**（实测 IHDR，左右并排各 640×360） | 2026-10-04 | 合成（软件渲染） |
| data/golden/frame_640x360.mem | `380ae5ba120317c8b48853bbc1be79997507bef6e01224fe0619fb4f489a473e` | 产生程序不在树里 ⇒ 含糊项；最早可观察到的存在 = `fc314bb`（2026-09-18）。内容由本轮实测确定（见 §9 第 3 条）：12 个不同 RGB565 色值构成的图卡 | 16 位 RGB565 定点（R5G6B5）；一行一个字的 4 位十六进制**小写**，取值 `0000`–`ffff`，无量化损失；行主序 640 列 × 360 行 = 230400 行，行尾 CRLF，共 230400×6 = 1,382,400 字节（与实测长度一致） | 2026-10-04 | 合成（12 色图卡，非拍摄画面；判定依据是取值集合，见 §9） | **【2026-10-05 修订】这一支已从目录里去掉，不随包。**

## 4. 附表：字节形状与含糊标记（按文件名basename索引，不与主表重复计数）

「主=副?」为 `diff` 表示该文件的字节里含 CRLF 或行尾空格形状——对 PNG 与 `.mem` 这是**预期**，不是异常。

| basename | 字节数 | 副摘要（原始字节 sha256） | 主=副? | 产生程序可指认? |
| --- | --- | --- | --- | --- |
| README.md | 2499 | `4bfcd0e4bd9545bc2fd7946cb6a6a1487a4897fdc425269d21fbcd85b13fe5ff` | same | 是（git commit 可查） |
| src.png | 5252 | `b9ca33fe360dc14e1e4ebec1ba4cfc1a05a0ad3a5580cdb1739dbb0ccc3eb26f` | diff | 否 ⇒ §8 |
| rot_000.png | 5252 | `b9ca33fe360dc14e1e4ebec1ba4cfc1a05a0ad3a5580cdb1739dbb0ccc3eb26f` | diff | 否 ⇒ §8 |
| rot_030.png | 7279 | `f9a3f4a06006098a923d25ffc4253a658124dcdff28290fcc7e82040aa9e2849` | diff | 否 ⇒ §8 |
| rot_045.png | 7862 | `5f9dd7d160c662eacbfdd48d39e827ff7bf02e5ab27072d2ca4a233897ef3572` | diff | 否 ⇒ §8 |
| rot_090.png | 3302 | `2f6550f06aacd084675590adcfa817d463b7b03281f39ea7e9cb81fafd22c4b5` | diff | 否 ⇒ §8 |
| rot_180.png | 4851 | `e2e6c80211627a5af47f4db49f108df85b068125a72e1856cf9339fafae85645` | diff | 否 ⇒ §8 |
| rot_270.png | 3277 | `c7715a9981c969cd818630b590aa3db0b4f30c342d7bad3d0c378668e116a010` | diff | 否 ⇒ §8 |
| proc_00111.png | 8916 | `7c1ab88c948167fcdb81ad7dfbc2668113fdc8431a1aca3516f132bfee15cbe1` | diff | 否 ⇒ §8 |
| proc_10000.png | 3523 | `86ed490e0aeb2632ef1282e5f904d1abc20efc3fc1c54af2cead4354b4ac18ba` | diff | 否 ⇒ §8 |
| proc_all.png | 4613 | `c6e4062f9e07f803131a548882297b6946f88036bd0379177e766780f57424ea` | diff | 否 ⇒ §8 |
| dual_preview.png | 10721 | `7bd6bf832ecf2397ff517df12f566c514f61f6c9d5f1efa17c41882e2c901b1c` | diff | 否 ⇒ §8 |
| frame_640x360.mem | 1382400 | `b4fafe39246aa51dae2aeea1a9e102dffc62f7d53d6e217661407e08c67068ab` | diff | 否 ⇒ §8 | ⇒ 现已去掉，不随包。

## 5. 双向差集核对（两个方向都要 0，由命令算出）

```bash
D=$(find data/golden -type f ! -name manifest.md | sort)
M=$(awk '/^\|[ ]*data\/golden\//{split($0,a,"|"); gsub(/^[ \t]+|[ \t]+$/,"",a[2]); print a[2]}' data/golden/manifest.md | sort -u)
echo "磁盘 N=$(printf '%s\n' "$D" | wc -l)  表里 N=$(printf '%s\n' "$M" | wc -l)"
echo "只在磁盘（表里缺行）："; comm -23 <(printf '%s\n' "$D") <(printf '%s\n' "$M")
echo "只在表里（磁盘找不到）："; comm -13 <(printf '%s\n' "$D") <(printf '%s\n' "$M")
```

2026-10-04 实跑输出（原样）：

```
磁盘 N=14  表里 N=14
只在磁盘（表里缺行）：
只在表里（磁盘找不到）：
```

两个方向的差集都是 0 行（`comm` 后面是空的），计数都是 14。
再钉一遍"没有已入库文件被动过"：

```bash
git status --porcelain data/golden
```

```
?? data/golden/manifest.md
```

只多出本文件这一个未跟踪新件；本目录 14 个已入库文件一条 `M` 都没有。

## 6. 摘要核验（P17 判据 3：抽样重算）

判据要求"随机抽 5 个"。本轮**14 个全部重算了**（总数只有 14，全算比抽样更强也更便宜，没有抽样空间），
用 §2 那条命令，输出与主表逐字一致：`不一致 0 条`。

抽样版本（要复现"抽 5"这个动作就贴这条；它读的是本文件，所以必须先有 §3 的表）：

```bash
awk '/^\|[ ]*data\/golden\//{split($0,a,"|");gsub(/^[ \t]+|[ \t]+$/,"",a[2]);gsub(/`/,"",a[3]);print a[2]" "a[3]}' \
  data/golden/manifest.md | head -5 | while read -r f h; do
    got=$(node -e 'const fs=require("fs"),c=require("crypto");const b=fs.readFileSync(process.argv[1]);
      const n=Buffer.from(b.toString("latin1").replace(/\r\n/g,"\n").split("\n")
        .map((s)=>s.replace(/[ \t]+(?=\n)/,"")).join("\n"),"latin1");
      console.log(c.createHash("sha256").update(n).digest("hex"))' "$f")
    [ "$got" = "$h" ] && echo "OK   $f" || echo "FAIL $f 表=$h 算=$got"
  done
```

```
OK   data/golden/README.md
OK   data/golden/src.png
OK   data/golden/rot_000.png
OK   data/golden/rot_030.png
OK   data/golden/rot_045.png
```

4. 目录里没有"表外基准件"这件事的另一半证明（没有任何脚本在读它们）——
   `data/golden/README.md` 给的核实命令，本轮原样重跑：

```bash
grep -rn "data/golden\|frame_640x360" --include='*.v' --include='*.mjs' --include='*.sh' . | grep -v '^./data/'
```

命中 `build/make_submission.sh:93` 的 `KEEP_ALWAYS_RE`（`^data/golden/`，随包名单，不是读取者）
与本轮新写的 `data/generated/gen_inputs.mjs` 注释两处。
⇒ 结论按实测口径写：**没有任何仿真或板级台架读 `data/golden/` 的字节**；唯一的读者是打包脚本，
它只按路径前缀决定留不留，不解析内容。

## 7. 不可变纪律（可执行版，不是口号）

1. 本表里的 14 个文件**不许原地改**。要改就另起目录 `data/golden/v2/`（或 `<名>-r<NN>.png` 新文件），
   在表里**新增一行**并在新行的"来源"格写清"取代哪一行、为什么"，旧行保留。
2. 需要改基准时先写"基准修订说明"（原基准错在哪、新基准依据），等队伍批准；
   批准前比对脚本继续用旧行（P17 铁律 4）。本轮没有任何修订动作。
3. 比对脚本读到**主摘要不符** ⇒ 报 `FAIL` 并拒绝继续用该基准；读到**只有副摘要不符** ⇒
   说明字节形状变了而内容未变（行尾/平台差异），按 `NOT_MEASURED` 处置并停下让人看，
   不许"内容没变就继续"——副摘要变了意味着 checkout 条件变了，这本身要解释。
   两种情况都不许静默通过。
4. 本仓库现在**没有**自动化比对脚本消费 `data/golden/`（§6 第 4 条实测），所以第 3 条眼下是
   给未来的读者预备的；把它接起来需要先定权威产生方式 ⇒ `report/questions-for-team.md` Q-P17-2。
5. 判据不许为了让比对通过而改参考值；参考值与判据都要留下改前红/改后绿的对照。

## 8. 含糊项统计（P17 判据 2 单独点名）

"产生程序与版本"这一格里**指不到仓库内脚本、也指不到外部出处**的行数：

| 含糊项 | 条数 |
| --- | --- |
| 产生程序不在树里（PNG 12 个中的 12 个 + `.mem` 1 个 = 13 个数据件） | 13 |
| 能指到仓库内件或 commit 的行 | 1（`README.md`：`8e03330` 加、`884c896` 改） |

这 13 行全部**保留在表里**而不是删掉：删掉它们就等于"13 个基准没有任何来源记录"，
比带着含糊标记更糟。它们的实际地位是"历史参照图"（`data/golden/README.md` 欠账 1 给的二选一之一，
本轮没有替队伍做另一个选项）。**在补出可复现的渲染脚本之前，"与黄金参考逐像素一致"这类说法在本仓库不成立。**

## 9. 本轮实测新查出来的三条事实（都附复算命令）

1. **`rot_000.png` 与 `src.png` 是同一份字节**：5252 字节、主副摘要都相同。
   复算：`cmp data/golden/src.png data/golden/rot_000.png; echo $?` ⇒ 无输出、`0`。
   ⇒ 0° 档不是"另一次渲染结果"而是源图本体，两个文件里必有一个是冗余的（处置要队伍定，见 Q-P17-4）。
2. **PNG 的规范化摘要 ≠ 原始摘要**（12 个全是），证明 §2 那句"规范化对二进制不是一一对应"不是假设。
3. **那支 640x360 裸帧向量（已去掉，不随包）的整帧只有 12 个不同取值**，最多的一种 `10a5` 占 97870/230400（42.5 %），
   其余 11 种各约 14355–14761；每行含 9 种取值。⇒ 它是**色块图卡**（合成），不是拍摄画面。
   复算：
   ```bash
   node -e 'const fs=require("fs");const b=fs.readFileSync("<那一支已去掉的 .mem 的本地留档>","latin1").split("\r\n").slice(0,-1);
   const m=new Map();for(const x of b)m.set(x,(m.get(x)||0)+1);
   console.log("行数",b.length,"唯一值",m.size);[...m].sort((a,c)=>c[1]-a[1]).forEach(([v,n])=>console.log(v,n));'
   ```
   与 `data/golden/README.md` 说的"没有任何脚本或台架读它"一致（§6 第 4 条），
   所以这条内容描述只是把它的形状钉住，不产生任何"它被用过"的说法。

## 10. 2026-10-05 修订：`data/golden/` 的现量与口径

本文件 §3 的表、§4 的附表、§5 与 §6 的记录都是 **2026-10-04 那一分钟的现量原样**，不改写它们（改记录等于伪造记录）。
本轮（目录精简）动了一件事，记在这里：

| 项 | 2026-10-04 记录 | 现在 |
|---|---|---|
| 目录里的件数 | 14（11 张 PNG + `.mem` + `README.md` + `manifest.md`） | **13**：`.mem` 那一行去掉，其余一字未动 |
| `frame_640x360.mem` | 在册，`§9` 第 3 条钉着它的取值集合 | **已真删，不随包**。删的依据是 `data/golden/README.md` 自己给的第二条出路（"接到发流脚本上当测试数据，或者从提交包里去掉"），本轮走后者：它的尺寸 640x360 与本设计的源尺寸 512x300 不符，且全仓没有任何 `.v`/`.mjs`/`.sh` 读它 |
| 输入向量的唯一出处 | 分散在 `.mem` 与 `data/inputs/` | 收敛到 `data/inputs/` 8 份，由 `data/generated/gen_inputs.mjs --write` 一键重生 |

复算现在的现量：

```bash
find data/golden -maxdepth 1 -type f | wc -l
ls data/golden/*.png | wc -l
grep -c '^| data/golden/' data/golden/manifest.md
```

§9 第 1、2 条（`rot_000.png` 与 `src.png` 同字节、PNG 规范化摘要不等于原始摘要）**仍然成立**，
这两条讲的是留在册上的 11 张图，与本轮的删除无关。
