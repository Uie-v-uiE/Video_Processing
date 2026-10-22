# Vitis 平台

`vitis-comp.json` 描述两个 domain：

| Domain | 处理器 | 用途 |
|---|---|---|
| `zynq_fsbl` | `ps7_cortexa9_0` | QSPI 启动的 FSBL |
| `standalone_ps7_cortexa9_0` | `ps7_cortexa9_0` | 裸机应用与 BSP |

硬件指向 `board/project/system.xsa`；`resources/` 下是三个 QEMU 参数文件。

## 重建

```bash
<Vitis>/bin/vitis-server.bat --port 8879 &
sleep 10
VP_VITIS_WS=<工作目录> <Vitis>/bin/vitis.bat \
  -s board/scripts/rebuild_vitis.py 8879
```

期望结果：`Platform Build Finished successfully.`、`GENERATE_RC 0`，并生成 `zynq_fsbl/build/fsbl.elf`。

Vitis 2025.2.1 的 `create_app_component` 在当前平台返回 `StatusCode.INTERNAL`，应用组件建不出来。PS 应用不依赖 IDE：

```bash
PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe \
PS_BSP=<平台 BSP 目录> \
PS_OUT=board/project/ps_app.elf \
python build/build_ps_app.py
```

平台重建成功后，`rebuild_vitis.py` 会在 workspace 里留下平台与 FSBL；BSP 路径由脚本打印。`vitis_platform/` 只保存平台描述与 QEMU 参数，不保存 16 MB 级 BSP 和构建中间产物。
