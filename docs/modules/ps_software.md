# PS 软件与上位机

## PS bare-metal（`sw/ps/main.c`）
### 功能
1. 初始化 EMIO GPIO，上电 `src_sel=0`（彩条）  
2. lwIP 静态 IP `192.168.1.10/24`  
3. UDP 端口 5001 收 RGB565 写 `0x10000000`  
4. 收满一帧后 Flush cache 并 `src_sel=1`  
5. UART0 115200 解析命令  

### 串口命令
| 命令 | 含义 |
|------|------|
| `00111` | 5 位效果使能（左=bit0） |
| `SRC0` | 彩条 |
| `SRC1` | DDR 帧 |
| `TH80` | 阈值 80 |

### GPIO 映射
```
GPIO_O[4:0]   effect_en
GPIO_O[15:8]  threshold
GPIO_O[16]    src_sel
GPIO_I[31:0]  status 回读
```

### Vitis
1. Vivado `create_project.tcl system` + `build_bitstream.tcl system` → `output/system.xsa`  
2. New Platform from XSA  
3. BSP：`lwip`, `xuartps`, `xgpio`  
4. New App，加入 `sw/ps/main.c`  
5. 链接脚本确保 DDR 有空间；帧区 0x10000000 应用侧可用  

## 上位机

### video_sender.py
- 默认 `192.168.1.10:5001`  
- `--image path` 或无图时用渐变+动条  
- `--fps 30`  
- RGB888→RGB565，1400B 分片  

### serial_ctrl.py
- `--port COMx --baud 115200`  
- 交互输入效果串  

### 依赖
```
numpy, Pillow, pyserial
# 可选: opencv-python 用于 --video
```

## 网络
- PC 与板卡同网段，例如 PC `192.168.1.100/24`  
- 关闭防火墙对 UDP 的拦截  
- 板卡 eth0（PS）插网线  
