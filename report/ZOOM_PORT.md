# 右屏无极缩放移植说明

## 需求

将 `Algorithm` 工程中的「无极缩放」移植到 `Video_Pipeline`（以太网视频）工程：

- **右屏**自动连续放大 ↔ 缩小循环
- **其他功能不受影响**：源选择（彩条/ETH）、五效果链、按键旋转

## 源工程 vs 目标工程

| 项 | Algorithm（源） | Video_Pipeline（目标） |
|----|-----------------|------------------------|
| 数据通路 | 流式 vsync/href + 行缓 | 帧缓 BRAM 随机读 + 逆映射 |
| 缩放接口 | `c_dst_img_width/height` + divider IP | `inv_scale` Q8 逆映射（无除法器） |
| 插值 | 最近邻 / 双线性 / 双三次 | 当前最近邻 + 连续 inv_scale（无极比例） |
| 依赖 | Efinity RAM / divider_ip | 仅工程内 sin/cos ROM |

**未原样搬运 `rgb_bicubic.v` 的原因：** 其比例计算依赖 `divider_ip` 与流式行 BRAM 推流，和本工程「屏幕坐标 → 源坐标 → 帧缓读」模型不一致；直接例化无法与现有 rotate/effects/单口 FB 读时分复用共存。

## 移植后的架构

```
左屏: cx,cy ──rotate_mapper──► FB ──► 原图显示
右屏: cx,cy ──zoom_mapper──► FB ──► proc_pipeline ──► 效果+缩放显示
              (inv_scale 自动三角波，可叠 rotate)
```

- FB 单口读：左窗时钟用旋转坐标，右窗用缩放坐标（左右扫描不重叠）
- 效果链挂在**右屏缩放后的光栅**上，目标域 3×3 滤波语义不变
- `inv_scale`: **256=1.0×（原本尺寸，最大）**，**512=0.5×（最小）**，每帧 STEP=2，缩小→回原始循环；缩小时四周 OOB 黑边

## 新增/修改文件

| 文件 | 说明 |
|------|------|
| `src/rtl/process/zoom/zoom_ctrl.v` | 帧同步三角波 inv_scale |
| `src/rtl/process/zoom/zoom_mapper.v` | 中心缩放逆映射 + 可选旋转，3 级流水 |
| `src/rtl/top/pl_video_top.v` | 双路径时分 FB、效果改挂右屏 |
| `src/rtl/video/split_display.v` | 左右独立 oob |
| `src/rtl/top/system_top.v` | `zoom_en=1` 常开 |
| `src/ps/main.c` | `ZOOM0`/`ZOOM1`（GPIO bit17 预留） |
| `sim/tb_zoom_mapper.v` | 恒等 / 2× 映射 / 控制器三角波 |

## 上板预期

1. 下载 bit 后**无需 PS** 即可看到右屏自动缩放（彩条源）
2. 推流后右屏缩放实时视频；串口 `10000` 等效果仍作用于右屏
3. KEY1/KEY2 旋转时左右屏同时旋转，右屏保持缩放循环
4. `SRC0`/`SRC1` 选源不受影响

## 后续升级（双线性）

`zoom_mapper` 已输出 `frac_x/frac_y` 亚像素。若需更平滑：

- 将 `frame_buffer` 扩为双读口或奇偶 bank，或
- 在右窗生成期用行缓预取 2×2 邻域做双线性

受 XC7Z020 BRAM（帧缓已占约 2.34 Mb / 4.9 Mb）限制，全图双缓冲双线性放不下，需行级缓存方案。
