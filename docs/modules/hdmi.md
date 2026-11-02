# HDMI / TMDS

## 组成
| 文件 | 作用 |
|------|------|
| `video_timing_720p.v` | 1280×720 时序（75 MHz） |
| `split_display.v` | 左右窗合成 + 分隔线 |
| `tmds_encoder.v` | DVI 8b/10b |
| `tmds_serializer.v` | OSERDESE2 10:1 + OBUFDS |
| `rgb2dvi.v` | 三通道 + 时钟通道 |

## 管脚（板卡）
| 信号 | 封装 |
|------|------|
| tmds_clk_p/n | W16 / Y16 |
| tmds_data_p/n[0] | AA17 / AB17 |
| tmds_data_p/n[1] | U17 / V17 |
| tmds_data_p/n[2] | U15 / U16 |

## split_display
- x∈[0,639] 左：原始（旋转后）  
- x∈[640,1279] 右：效果结果  
- x=639/640 蓝色分隔线  
- oob → 黑  

## 时序参数
H: 1280 + 110 + 40 + 220 = 1650  
V: 720 + 5 + 5 + 20 = 750  
刷新 ≈ 75e6 / (1650*750) ≈ 60.6 Hz  

## OSERDES 说明
Master D1–D8=din[7:0]，Slave D3/D4=din[8:9]，Slave SHIFTOUT→Master SHIFTIN。  
时钟通道固定 `10'b1111100000`。  
