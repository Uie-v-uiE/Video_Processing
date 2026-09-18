# S4 · Zynq DDR 带宽与 HP 口经验

## 适用场景
PS 写帧 / PL HP 读写帧、双缓冲、分辨率选型。

## 使用方法
- 帧字节 = W×H×2（RGB565）  
- HP0 64-bit：理论 400 MB/s @ 50 MHz；AXI3 16-beat = 128 B  
- 本工程 512×300：读 60 Hz ≈ 18 MB/s，写 30 fps ≈ 9 MB/s，余量大  
- PS 写后必须 `Xil_DCacheFlushRange`，PL 才能看到新帧  
- 提分辨率优先砍 **片上 BRAM**，不是网口

## 已验证效果
- ARCHITECTURE §5 带宽表；上板双窗稳定  

## 失效条件
- HP 位宽/ID 与脚本不一致  
- 未 flush cache  
- 720p 全帧塞进 7020 BRAM（约 13.8 Mbit ≫ 4.9 Mbit）
