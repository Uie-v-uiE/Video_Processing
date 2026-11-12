// proc_pipeline_cfg.vh —— 效果链两个固有常数的**全工程唯一出处**。
//
// 背景：顶层 pl_video_top 原来用 Vivado 的层次引用扩展（u_pipe.LATENCY / u_pipe.OFF_LINES）
// 取 proc_pipeline 的参数值，slang/Qihe 拒收层次名常量表达式（IEEE 1800 不允许），
// 而工程纪律又要求这两个数不许出现第二份字面量 ⇒ 抽到这份头文件：
//   proc_pipeline 的参数默认值与顶层 localparam 都从这里的宏取数，谁要谁 `include。
// 改延迟/偏移 = 改效果链契约：proc_pipeline 文件头的逐拍账要同步重算，
// 且 tb_pipe_bypass（tb_v86 一族）实测 de_in→de_out 会与这里对账，漂移即红。
// include 路径的四个入口（改了一处要同步其他，见 docs/workflow 手册的参数联动表）：
//   Vivado = build/tcl/build_system_axigpio.tcl 的 include_dirs；
//   ModelSim = build/sim/run_msim.sh 的 +incdir+；
//   xsim = build/sim/run_sim.tcl 与 run_one.sh 的 xvlog -i；
//   Qihe = 工作区 scripts/run-qihe.ps1 的 -IncludeDirs。

`ifndef PROC_PIPELINE_CFG_VH
`define PROC_PIPELINE_CFG_VH

// 效果链总延迟：**固定 15 拍**（灰度1+反色1+模糊3+锐化3+Sobel3+阈值1+形态学3），
// 与哪一级开、同级选哪个算法无关。窗口级是三拍不是两拍；gamma 是组合读出不占拍。
`define PROC_PIPELINE_LATENCY   15

// 内容偏移：四个窗口级各贡献 −1 行 ⇒ 整链固定 −4 行、0 列（因果性决定，不是笔误）。
`define PROC_PIPELINE_OFF_LINES 4

`endif
