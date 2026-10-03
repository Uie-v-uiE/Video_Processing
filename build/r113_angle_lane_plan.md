# r113 计划：把 `angle` 变成机读量（**不新增跨域**，走 lane23 的保留位）

问题（ISSUES #247、任务 #185）：今天板上的角度**没有机器读数**——
`pl_video_top.v:1046-1049` 的 `status` 口里那 9 位 `angle` 在 `system_top.v` 里只声明+连接、**没有读者**
⇒ 综合按 "unused … removed" 删掉。后果：`board/ACCEPTANCE.md` 的 E6 那一格只能靠眼睛，
"上电是不是 0 度"这种问题无法自动判。

## 为什么不做新 lane、也不新建一条跨域
- lane 号 20/21/22 虽然空（`system_top.v:234` 越界回 `DEAD_BEEF`），但走新 lane 要新起一组
  `snap_cross` + 一个新发射触发器 ⇒ 新增一对 CDC，`cdc.rpt` 会多出配对、门禁第 6 项要重开基线（#65/#11 那一族的教训）。
- **lane23 已经有现成的准静态快照**：`zoom_snap`(`#175`) 把像素域 19 位缩放状态 + `rot_forced` 打过 axi 域，
  `dbg_zoom` 的位图是 `{bit31=活, [30:20]=0 留扩展, bit19=zoom_fit|rot_forced, [18:0]=状态}`
  （唯一出处 `pl_video_top.v:679-688` 的注释）。**[30:20] 这 11 位是空的**，而 `angle` 只要 9 位。

⇒ 方案：把 `angle[8:0]` 挂进 `zoom_snap` 的总线尾部（20→29 位），从 `dbg_zoom` 的 bit28:20 出来。
零新跨域、零新 lane、`cdc.rpt` 配对集合不变。

## 要动的四处（顺序 = 先尺子后改动）
1. **尺子先红**（规矩：新判据要先在未改的树上拿红）：`sim/tb_v100_fit_rot.v` 或新建
   `sim/tb_v113_zoom_snap_angle.v`，判据两条成对：
   - N1 `bus[28:20] == angle`（快照与源头同拍相等，帧边界之内不许读到半新半旧）
   - N2 反配对：**同一时刻** `bus[19]`（`rot_forced`）与低 19 位仍各自正确
     —— 证明加宽没有把原有 20 位挪位或错位（这条是防"新加一位把老位的读者全弄坏"）
2. `src/rtl/process/zoom/zoom_snap.v`（实测路径；`bus` 现在是 `output reg [19:0]` 在第 22 行，
   `rot_forced` 是第 21 行的输入）：端口 `bus` 宽度 20→29，新增 `input [8:0] angle`，
   `bus = {angle, rot_forced, ...}` 按上面的位序；`tb_v95`（钉 `zoom_snap` 两条不变量的老台架）跟着改期望。
3. `src/rtl/top/pl_video_top.v`：`u_zsnap` 加 `.angle(angle)`；`dbg_zoom` 改成
   `{~z_pix_gone, 2'd0, z_bus_axi[28:20], split_ctl[18] | z_bus_axi[19], z_bus_axi[18:0]}`，
   **并改文件头那段位图注释**（那是唯一出处，改口必须同步，否则 D5/#122 那一族会指错位）。
4. 读者两侧：`src/host/health_read.mjs` 的 `decodeZoom` 加 `angle`（位 28:20）与 `S4` 独热走查的归属表
   （现在 [19..30] 是"保留位"，改完 28:20 有主 ⇒ 那条"译码器不许被保留位动"的判据要按新位图重写，
   并配一条反例：把 angle 位塞给老解码器不许改变任何现有字段）。门禁反例集合同步。

## 收益（为什么值得占一轮）
- E6 从"眼睛判"升级成机器判据：`board_verify` 可以加一步"冷上电（或刚 `program_pl` 之后）读 lane23 ⇒ angle==0"。
  这条正是"上电那一度"唯一能被自动化的部分（#249 的成因之争也靠它：不碰键的上电若能机读，就能重复测）。
- `angle` 与屏上 `ROT:` 那格从此同源可核（与 `Latency:`/`Zoom:` 那两格的"屏上与回读同源"是同一手法，PLAN 步 5）。

## 风险与不做的事
- `snap_cross` 的 `bus_q` 在帧首之外可能读到上一轮的值（这是它的设计语义，#52/#59 已钉）⇒
  机读角**只能用于"准静态判据"**（上电后静置、`rot auto 0` 冻住之后），不许拿去判"每帧角度对不对"。
- 不动 `status` 口（保持原样、仍无读者）：那一位宽口若接回去要重排 GPIO 位序，
  老工具全错位（#66 的"位序不许动"）。
- 不把 `angle` 塞进 lane30（那是仲裁状态，位序有老读者，见 `system_top.v:229` 与 :602 的注释）。
