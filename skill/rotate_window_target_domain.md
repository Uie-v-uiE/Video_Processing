# S2 · 旋转与窗口滤波必须做在**目标域**

## 适用场景
- 任意角逆映射旋转（0–359°）+ 3×3 邻域滤波（blur / Sobel）要**同时开**。
- 症状长这样：`angle≠0` 时一开模糊/Sobel 就花屏、出现中间混叠值；关掉旋转又正常。
- 机理（一句话）：窗滤若在**源图扫描序**上取邻域，逆映射之后「屏幕邻域 ≠ 源图邻域」⇒ 滤的是错的 3×3。
  **点运算**（gray / binary / invert）与邻域无关，任何域都兼容 ⇒ 只有窗滤类需要本次重构。

## 使用方法（目标域四步）
1. 屏幕 `(cx,cy)` 经缩放/旋转逆映射得 `(sx,sy)` 并读像素（`src/rtl/process/zoom/zoom_mapper.v`）。
2. 承认「读出来的像素流本身就是**旋转后图像的光栅序**」。
3. 在这条流上用行缓存建 3×3，列坐标用**屏幕 cx**寻址：
   `src/rtl/process/proc_box_blur.v:18-19`、`proc_sobel.v:17-18` 各 2 行缓存，
   深度 = `H_ACTIVE`，由 `src/rtl/top/pl_video_top.v:422` 的 `proc_pipeline #(.H_ACTIVE(IMG_W)) u_pipe` 传入。
4. 删掉 `bypass = ~en | rotate_active` 里对 blur/sobel 的强制旁路：现状是
   `src/rtl/process/proc_pipeline.v:26-27` `by2 = ~effect_en[2]` / `by3 = ~effect_en[3]`；
   `rotate_active` 端口还在（`:12`，注释即「retained for status」），`pl_video_top.v:425` 仍把
   `rot_on` 接进去，但在 `proc_pipeline.v` 全文里它只出现这一次 ⇒ 结构上已经不可能旁路任何一级。
5. OOB 填 0，并在效果链**之后**再强制黑边——否则 invert 会把 OOB 的 0 变成白。
   串口侧命令见 `report/ROTATION_AND_EFFECTS.md` §6（如 `00111` = 右窗模糊+Sobel+反色）。
6. 台架：`SIM_TB=tb_rotate_window vivado -mode batch -nojournal -source sim/run_sim.tcl`。

## 已验证效果
- 台架判据是「反向」的（rotate_active=1 时**必须**出现中间混叠值 ⇒ 证明 blur 真的在跑）：
  `sim/tb_rotate_window.v:89` 的失败文案是 `no intermediate blur value under rotate_active=1`，
  `:91` `PASS blur active with rotate_active=1`、`:106` `PASS blur active with rotate_active=0`；
  该 TB 在全量回归里 PASS（`sim/results/regression_v77_r13.txt`，`SIM DONE pass=34 fail=0`）。
- 结论已写进工程文档：`report/ISSUES.md` §10「旋转时窗滤花屏（旧）→ 目标域 3×3 重构后任意角可用
  blur/sobel」、§16「原 line_cache（左扫右读）废弃，效果改挂右窗缩放后光栅，左窗保持原图」、
  `report/ROTATION_AND_EFFECTS.md` §2。
- 顺带把「旋转放在哪个窗」这件事变成资源收益：V7.7/R12 将旋转限制在右窗、
  删掉左路的 `rotate_mapper` 实例 ⇒ **DSP48 13 → 9（−4）**、Slice LUT −182、Reg −24、
  时序端点 −279，WNS 反而由 +0.408 升到 **+0.540**，BRAM 64.64% 不变
  （`report/OVERNIGHT_LOG.md` §5 R12 行、§6 bit `166f4b94`；`report/CHANGELOG_V7.md` V7.7）。
- 左路改动的风险论证是「走今天已在板上逐像素正确的那条分支」：`rot_on=0`（angle=0）路径不变、
  不引入新数据通路、不动 3 级列配准深度（`report/OVERNIGHT_LOG.md` R12）。

## 失效条件
1. **行缓存深度 < 有效行宽**：`H_ACTIVE` 默认 640，本设计传的是 `IMG_W`=512 ⇒ 一旦右窗宽度大于
   传入值，3×3 的列就对不上（改分辨率要一起改）。
2. **在源域行缓存上滤波却用屏幕坐标寻址**——仍是错的，只是错得更隐蔽。重构的充分条件是
   「行缓存挂在逆映射**之后**的那条流上」。
3. 与「未旋转源图」做逐像素金标对比时，**金标也要先旋转/缩放再滤波**
   （`report/ROTATION_AND_EFFECTS.md` §5），否则会报出一堆假差异。
4. **R12 之后左窗不再旋转**：`report/ROTATION_AND_EFFECTS.md` §1 仍写着「左右窗均可旋转」，
   与当前 RTL（`src/rtl/top/pl_video_top.v:132-150`，`sx_l = cx_q3` 无旋转分支）不一致。
   需要左窗旋转时必须重新例化 `rotate_mapper` —— 它现在**没有被任何模块例化**（全树 grep 无实例），
   只在回归里作为独立数学参考被 `tb_rotate_mapper` 覆盖。
5. 「左窗不转、右窗转」「OSD 角度行仍跟随」这条**尚未上板肉眼确认**
   （`report/OVERNIGHT_LOG.md` R12 明写「待明天上板确认」）⇒ 属未验证，不要当战果引用。
6. 旋转分支的 `frac_x/frac_y` 被强制清 0（`src/rtl/process/zoom/zoom_mapper.v:73-74`
   `fx = rot_s1 ? 8'h00 : raw_xs[7:0]`）⇒ 本 skill 描述的是**最近邻**取像素下的旋转+窗滤共存；
   想在旋转态做双线性必须先补出小数位，且 `src/rtl/process/bilin_lerp.v` 目前未被例化。
