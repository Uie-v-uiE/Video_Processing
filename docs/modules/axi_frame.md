# AXI 帧通路与帧缓冲

## axi_frame_writer
AXI4 只读 master，按行 burst 把 DDR 帧灌入 `frame_buffer`。

| 参数 | 值 |
|------|-----|
| 数据宽 | 64 bit（4 像素/拍） |
| arsize | 3'b011 (8B) |
| arburst | INCR |
| 每行 beat | 640/4 = 160 |
| arlen | 159 |
| 基址 | BASE_ADDR=0x10000000 |

状态机：`IDLE → AR → R → NEXT(row++) → DONE`

### 端口
```
enable, frame_start
fb_wr_en, fb_wr_addr[18:0], fb_wr_data[15:0]
m_axi_araddr/arlen/arsize/arburst/arvalid/arready
m_axi_rdata/rlast/rvalid/rready
```

## frame_buffer
真双口 BRAM：写口 axi_clk，读口 clk_pix，随机读地址 `sy*W+sx`。

深度 640*360=230400，宽 16，约 2.95 Mb BRAM。

## PS 侧写入
- 地址 `0x10000000`  
- 格式 RGB565 小端、行优先  
- `Xil_DCacheFlushRange` 后 PL 才能看到  

## Vivado 2025.2 注意
- `processing_system7:5.5` 仍可用  
- HP0 64-bit；PL master 需接 `S_AXI_HP0`  
- ARID 使用 6-bit（S_AXI_HP0）  
