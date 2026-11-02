# 板上三件套

| 文件 | 内容 | 生成方式 |
|---|---|---|
| `system.bit` | PL 位流 | `vivado -mode batch -source build/tcl/build_system_axigpio.tcl` |
| `system.xsa` | 与位流同批的硬件描述 | 同上 |
| `ps_app.elf` | PS 裸机应用 | `build/ps/build_ps_app.py` |

三件套必须同批生成。换位流不换 XSA，Vitis 平台的地址映射会对不上；换 PS 源码不重编 ELF，板上仍是旧固件。

## 校验

```bash
md5sum board/project/system.bit board/project/system.xsa board/project/ps_app.elf
```

构建脚本和上板脚本都会打印 md5 前 12 位；日志里的身份行与这三个值一致，才算同一批。

## 重新生成顺序

1. 改 RTL 或约束：跑 `build/tcl/build_system_axigpio.tcl`，更新 `system.bit` 与 `system.xsa`；
2. 改 PS 源码：跑 `build/ps/build_ps_app.py`，更新 `ps_app.elf`；
3. 重打 QSPI 镜像：`board/scripts/make_boot_image.sh`；
4. JTAG 验证：`board/scripts/board_flash.sh`；
5. QSPI 固化：`board/tcl/flash_qspi.tcl`，断电重上。

## 说明

`system.bit` 与 `system.xsa` 由同一次实现导出；`ps_app.elf` 的 BSP 必须与 `system.xsa` 的 PS7 配置一致。当前 ELF 包含串口 `link`/`link clr` 命令，用于读帧间隔统计。
