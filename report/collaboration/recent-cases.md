# 最近修正索引

| 修正 | 错误断言 | 现在的落点 |
|---|---|---|
| 帧提交条件 | 字节数够就能提交 | `corrections.md` C1；`sim/results/regression.txt` 的 `rows` |
| A9 混帧 | 静默超过 4 ms 仍可继续拼 | `corrections.md` C2；`sim/tb_udp_reasm.v` |
| `p_good` 清零 | 按包清零只影响当前包 | `corrections.md` C3；`board/measured/link_gap.txt` |
| 故障自检 | 用瞬时帧率判干净/故障 | `corrections.md` C4；`board/measured/link_selftest.txt` |
| 处理窗漏图 | 灰度下彩色像素只是抖动 | `corrections.md` C5；`board/measured/pane_integrity.txt` |
| 竖缝几何 | 两条显示链各自缩放能对齐 | `corrections.md` C6；`sim/results/c31_edge_rim.log` |
| 台架假绿 | PASS 就代表覆盖到了 | `corrections.md` C7；`report/verification.md` |
| bootgen 假成功 | 返回 0 且打印成功就是新镜像 | `corrections.md` C8；`board/flash/boot_manifest.txt` |
| `link` 不可达 | 函数存在就能从串口调用 | `corrections.md` C9；`board/measured/link_gap.txt` |
| 复现路径漂移 | 换目录后旧相对路径仍可用 | `corrections.md` C10；`build/ps/build_ps_app.py` |
| 工程能打开 | 缺文件为 0 就能综合 | `corrections.md` C11；`board/vivado/README.md` |
| 文档旧数字 | 旧稿的 99/102、100 MHz、57–62 °C 可继续用 | `corrections.md` C12；`build/reports/`、`board/measured/` |

详细实验与结论见 `corrections.md`；板上和仿真的原始读数见 `sim/results/` 与 `board/measured/`。
