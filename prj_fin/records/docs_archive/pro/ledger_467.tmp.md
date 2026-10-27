### #467 交付树里不能有本机路径：改得与改不得的分界，和"改完要用工具自己证明一次"

- 用户口径：交付看的是链接（GitHub 那份要给评委点开），所以**仓库正文里不该有我机器的路径**。
  工具 `build/r129_path_sanitize.mjs`（`--check` / `--apply` 两态、可重跑、带地板）。
- 分界是三句话，不是"能改就改"：
  ① **改得**：两棵工程树生成件的正文（175 份 8628 条）、手写源码注释里指向本地资料库的路径、脚本用法示例
     ⇒ 换成 `<repo>` / `<tools>` / `<board-docs>`；`<Project … Path>` 按仓库既有约定写成**仓库相对落点名**。
  ② **改不得**：`build/`、`board/measured|evidence*|compare/`、`report/log/`、`data/metrics.csv` 的正文
     （188 份 3048 条）——那里记的是"当天读的是哪一台机器上的哪一份"，改掉就是改写证据（导出器把这一层写成
     "只报数不判红"是同一个道理）；`board/signoff.md` 的用户原话 1 份不动。
  ③ **不能改字节**：含 NUL 的 300 份（`.obj`/`.a`/`.dcp`…），改了不是清理是损坏 ⇒ 只报数。
- 关键一步不是替换而是**证明**：`build/r129_open_check.tcl`（只读探针）跑 Vivado 批处理，
  读回 `OPEN ok=zynq_video_sys`、`sources=196`、`constrs=2`、`missing_files=0 of 198`、`runs=14`、
  `abs_path_lines=0`、`CLOSE no-write` ⇒ 工程照打得开，而且 open/close **没有**把绝对路径写回 `.xpr`
  （提交后那份的 diff 仍是我改的一行 1/1）。改完只跑文本尺子是**不够**的：动的就是那份工程本身。
- 尺子跟着补牙，不是把红压下去：`r125_fact_hold` 为这次消失的 160 个 `path:` 记号加的是**规则式豁免**
  （三条件同时成立才放行：记号是 path、消失的那条本来就是本机根形状、同一份文件里当场数得到占位符），
  并在 RESULT 行新增"占位符豁免 N 条"（本轮 159）——逐条名单会变成万能出口，规则式 + 计数器才看得见谁被放行了。
  另有 1 条逐条豁免：`src/host/README.md` 的 `number:2025.2` 随那条从来不存在的路径一起消失（换成 `<Vitis>/bin/xsdb.bat`）。
- 反买通对照现成：改完第一次跑 fact_hold 是 **RED**（消失 160 ⇒ 豁免前它真的会红），
  加规则后 OK；再拿一条"路径不是本机根形状"或"文件里没有占位符"的写法它就还是不红才需要补——本轮没做这一步，
  记在这里当作下一次要补的对照（形状：**新增豁免必须带一个能红的反例**，见 [[feedback-ruler-teeth-empty-sets]]）。
- 顺带两处事实错修正（都是实核出来的，不是猜）：`src/host/README.md` 的 xsdb 示例写的
  `D:/Xilinx/Vitis/2025.2/bin/xsdb.bat` 这台机器上从来不存在（真实落点 `<套件根>/Vitis/bin/xsdb.bat`，版本 2025.2.1）；
  `PS_CC` 示例的 `<Vitis>/gnu/…` 与 `<tools>/gnu/…` 两种写法并存——实核**两个位置都在**（`2025.2.1/gnu/…` 与
  `2025.2.1/Vitis/gnu/…` 各有一份 arm-none-eabi-gcc），所以统一成文档其余部分用的 `<Vitis>/gnu/…`，
  并把"两处都有"这个事实写在这里，避免下一次有人把它当错改掉。
- 位流侧不需要重刷：`bash build/rtl_fingerprint.sh` 读 `top=56c269602e18 rtl=07570b1ac1b4`，
  与 `build/provenance.md:36` 记的那对逐字相同；两条 `.xdc` 的 diff 只动 `##` 注释行。
  ⚠ 但**合指纹的射程只有 `src/rtl`**，不含 `src/constraints` ⇒ "指纹没变"不能写成"约束文件没被改过"，
  这一句的区别要留在记录里（本轮靠逐行看 diff 补上，不是靠指纹）。
- 提交：交付树 `1fd04c9`（180 文件，+4542/−4397）；导出器另一处 bug 同笔修掉
  （`git archive` 少写 tree-ish ⇒ `fatal: not a valid object name: vivado_system`，见 #466 末）。
