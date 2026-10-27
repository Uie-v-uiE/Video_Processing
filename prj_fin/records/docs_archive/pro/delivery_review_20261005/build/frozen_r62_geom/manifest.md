# r62 冻结件（V9 几何自动化：缝进画面 + 缩放跟角度 + 转速给人管）— 2026-09-25 23:25 构建 #49

一句话：**分割线的分类从"显示列"搬到"图像列"**（`seam_src.v`，于是蓝线跟着旋转/缩放一起走、
端点天然是画面的两端），**倍率新增第三种来源"按角度定"**（`zoom_fit.v`，360 个角度全程不缺角），
**自动旋转挂在帧首翻转位上**（`angle_ctrl`），无 ETH 时 OSD 第 5 行印 `ETH is no signal`。
细节、算式、以及哪几处错了三次，全在 `report/issues.md` **#75**。

## 三件套（与下面每一条数字同一次构建 #49）
| 件 | md5 |
|---|---|
| `system.bit` | 见 `MANIFEST_BODY.txt`（10 个文件一起 `md5sum -c` 必须全 OK） |
| `system.xsa` | 同上 |
| `ps_app.elf` | 同上（本轮 PS 侧改了：`rot`/`zoom fit`/`split screen|video`/`gamma auto`、`T_MAX` 8、`[STAT] geom=`） |

警告：表里的 `ps_app.elf` 是 **00:39 重编的那一份**（PS-only，位流没动）。两次重编的账：
23:42 给 `split show` 的文案加单位（`pos=307/1024（显示列） = 29%`）；
00:39 修 **#77**：`split 100` / `split px 1024` / `split screen` 三条写口把缝位夹到 10 位上限 1023 并明说，
回显的百分比改由**存进去的值**反算（与屏上 Split 格同一个式子）。
`system.bit` / `system.xsa` 仍是 23:25 构建 #49 的那一份；板上现在跑的就是表里这三件（`md5sum -c` 13 个文件全 OK）。
`battery_r62.txt` 也换成修完之后的那一轮：**97 条全 PASS**（92.0 s，初末 `geom=00400000` 相同）。

## 门禁 14 项 `GATES: ALL PASS`（`gates_r62.txt`；复核 `bash build/gates.sh build/frozen_r62_geom`）
WNS **+0.792**（r59b-1 +0.575、r60 曾 **−0.482** 判红）、WHS **+0.001**、失败 setup/hold 端点 0/0、
**BRAM 96 tile / 68.57 %**（与 r59b-1 逐位相同 ⇒ V9 一块 BRAM 都没多要）、
**LUT 12958 / 24.36 %**、Dynamic **2.201 W**、methodology CRIT 0、布线错误 0、
CDC Critical 3 行且**配对集合不新增**、端口宽度警告 0、多驱动 0、顶层接线 violations 0。
警告：**WHS +0.001 是本项目最薄的一次**（r51 +0.017、r59b +0.053）：门禁是绿的，
但这一档不能当好消息记账 —— 深度时序那一遍（任务 #46）的第一个目标就是它。

## 本轮已经有的凭据
- `xsim_v100_fit_rot.log`：`V100 PASS`，checks=373 errors=0 —— 360 个角度的"装得下/不白缩"、
  0° 回 1.0x、自动旋转的帧沿计数/取模/`speed=0` 钉住、`inv_used` 与 `zoom_code` 同源。
  跑法在 `sim/tb_v100_fit_rot.v` 文件头（快照名要独占，理由写在 #75）。
- RTL 全树 `xvlog` 0 error；PS 固件 `node build/ps_app.mjs` rc=0（`build/ps_app_v9f.log`）。

## 还没闭合的（不要拿这一版去演示，直到这四条有人看过）
`board/README.md` 第 **24~27** 行：① 蓝线跟着画面转、端点停在画面边上；② 自动旋转全程不缺角、
`Zoom:` 标 `(Fit)` 且数字跟着角度走；③ 钉住 ETH 停流时屏上出 `ETH is no signal`；
④ `gamma auto` 来回渐明、`gamma manual` 立刻停。
机器侧两条已经补齐：`battery_r62.txt` = 91 条串口电池 **91/91 PASS**（86.9 s，跑完 `geom=00400000` 与进来时逐位相同）；
`geom_check_r62.txt`（在 `build/`）= G1~G4 **ok=8 fail=0**。
