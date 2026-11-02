# S3 · AXI 流水线模块验证方法

## 适用场景
AXI4/AXI4-Stream 视频模块、HP 口读写、多级 sideband 对齐。

## 使用方法
1. **单元 TB**：固定时钟，驱动 valid/ready/data，检查 last/resp  
2. **sideband 对齐**：de/x/y/left 与数据同延迟；错位症状为右窗花屏/分隔线毛刺  
3. **拆包**：64-bit beat = 4×RGB565，锁存整拍再拆 4 拍，禁止每 rvalid 只写 1 像素  
4. **地址位宽**：行地址一律 32 位运算（见 ISSUES#11）  
5. **诊断图案**：细线/棋盘/文字，不要只用大色块（ISSUES#15）

## 已验证效果
- ISSUES#10/#11/#15 修复后 FILL 与视频一致  
- `sim/tb_timing.v`、`tb_proc_gray.v`  

## 失效条件
- 仿真未模拟 backpressure（ready 拉低）  
- 跨时钟未加 CDC FIFO  
- AXI3 burst &gt; 16
