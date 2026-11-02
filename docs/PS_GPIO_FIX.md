# 红线 vs 真编译

你截图是 **编辑器 clang**，不等于 Vitis Build 失败。

## 已改 API

| 错误 | 原因 | 修正 |
|------|------|------|
| `XGpioPs_GetValuePin` 不存在 | 函数名错了 | 改为 **`XGpioPs_ReadPin`** |
| `XPAR_XGPIOPS_0_DEVICE_ID` 未定义 | BSP 宏名不同 | 兼容 `XPAR_PS7_GPIO_0_DEVICE_ID` |
| `XPAR_GPIO_0_DEVICE_ID` / `xgpio.h` | 旧文件残留 | **整文件替换** `main.c`，不要混用旧代码 |

## 正确做法

1. 用当前 `sw/ps/main.c` **整体覆盖** Application 源文件  
2. 在 **Vitis** 里 **Project → Build Project**（不要只看 VS Code 下划线）  
3. Build 通过后 **Run As → Launch Hardware**  
4. 串口看：

```
[GPIO init] DIRM0=... DIRM2=...
[GPIO] want=0x00005000 ... DATA2=...
```

把 `DUMP` / `PATT` / `00111` 的完整输出发我。

## 若 Vitis 真编不过

- Platform 是否已 Build 且被 Application 引用  
- BSP include 路径应含 `\<plat\>/ps7_cortexa9_0/lib/include`  
- 不要再出现 `#include "xgpio.h"`
