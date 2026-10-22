# QSPI 启动镜像

| 文件 | 内容 |
|---|---|
| `BOOT.bin` | FSBL + 位流 + PS 应用，写入板载 QSPI |
| `boot.bif` | bootgen 的镜像描述，路径相对 BIF 文件本身 |
| `bootgen.log` | 打包日志 |

## 重新打包

```bash
VP_VIVADO_BIN=<Vitis>/bin bash board/scripts/make_boot_image.sh
```

脚本从 `vitis/fin2_plat/zynq_fsbl/fsbl.elf`、`board/project/system.bit` 和 `board/project/ps_app.elf` 取输入，生成 `BOOT.bin`。`boot.bif` 里用相对路径，换一台机器解包不会带本机盘符。

期望结果：

```text
BOOT_IMAGE .../board/flash/BOOT.bin
BOOT_BYTES ...
BOOT_MD5 ...
MAKE_BOOT_IMAGE DONE
```

## 写入 QSPI

```bash
VP_HW_URL=<host:port> vivado -mode batch -source board/tcl/flash_qspi.tcl
```

期望结果：

```text
Erase Operation successful.
Program Operation successful.
Verify Operation successful.
PROGRAM_RC 0
```

写入后断电重上，确认串口启动回显和 `ping`。QSPI 写入不可逆；写入前确认镜像与启动模式拨码。

## 注意

- `BOOT.bin` 必须包含最新的 `ps_app.elf`；重编固件后要重打镜像并重写 QSPI。
- bootgen 读不到输入时也可能返回 0；打包脚本会检查日志里的 `[ERROR]` 和成功行，并在生成前删除旧镜像。
- JTAG 下载只影响当前上电周期，断电后仍从 QSPI 启动。
