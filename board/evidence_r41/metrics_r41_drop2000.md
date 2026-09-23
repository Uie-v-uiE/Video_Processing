# 指标采集 r41_drop2000（2026-09-23T17:34:40.281Z）

命令：`node src/host/metrics.mjs --fps 30 --seconds 20 --drop-every 2000 --tag r41_drop2000`
bit：见同目录 `MANIFEST.txt` 或 `build/gates.sh` 当时的报告；板子为 Zynq7020。

| 项 | 值 |
|---|---|
| 发送帧数 / 用时 | 600 / 22.05 s |
| 交付载荷字节增量 | 184228128 → 折合 599.70 帧 |
| 收到包数增量 | 132534 |
| **drop_words 增量** | **0**（CDC 灌满次数 +0） |
| 验收门作废帧 frames_bad 增量 | 66（坏包 0，缺行峰值 205） |
| 帧间隔 min/avg/max (ms) | 22 / 37.45 / 75（533 段） |
| 由间隔算的 fps | 26.701 |
| 由墙钟算的 fps | 27.194 |
| 时基标志（结束后） | hb_slow=0 hb_gone=0 stream_live=0 |
| 判据 | ✅ 入包链一个字都没丢 |

原始读数（JSON，可直接复核）：

```json
{
  "before": {
    "gpio0": 741376,
    "clk": 0,
    "dbg_src": 1,
    "src_state": {
      "eth_tb_ok": 1,
      "eth_live": 0,
      "owner_eth": 0,
      "fill_busy": 0,
      "row_busy": 0,
      "mode_gray": 0,
      "mode": "AUTO"
    },
    "drop_words": 0,
    "frames_bad": 598,
    "pkt_err": 0,
    "stall_ms": 21864,
    "rows_miss_max": 205,
    "gap_last": 0,
    "gap_min": 0,
    "gap_max": 0,
    "gap_sum": 0,
    "cdc_episodes": 0,
    "flags": 2,
    "pkts": 463065,
    "bytes": 643681008,
    "hb_slow": 0,
    "hb_gone": 0,
    "flags_bits": {
      "drop_seen": "0",
      "abort_seen": "1",
      "cdc_full_seen": "0",
      "stream_live": "0",
      "gap_valid": "0"
    },
    "passes": [
      [
        0,
        2
      ],
      [
        1,
        2
      ],
      [
        2,
        2
      ],
      [
        3,
        2
      ],
      [
        4,
        2
      ],
      [
        5,
        2
      ],
      [
        6,
        2
      ],
      [
        7,
        2
      ],
      [
        8,
        2
      ],
      [
        9,
        2
      ],
      [
        30,
        2
      ],
      [
        31,
        2
      ]
    ]
  },
  "after": {
    "gpio0": 741376,
    "clk": 0,
    "dbg_src": 1,
    "src_state": {
      "eth_tb_ok": 1,
      "eth_live": 0,
      "owner_eth": 0,
      "fill_busy": 0,
      "row_busy": 0,
      "mode_gray": 0,
      "mode": "AUTO"
    },
    "drop_words": 0,
    "frames_bad": 664,
    "pkt_err": 0,
    "stall_ms": 4828,
    "rows_miss_max": 205,
    "gap_last": 33,
    "gap_min": 22,
    "gap_max": 75,
    "gap_sum": 19962,
    "cdc_episodes": 0,
    "flags": 18,
    "pkts": 595599,
    "bytes": 827909136,
    "hb_slow": 0,
    "hb_gone": 0,
    "flags_bits": {
      "drop_seen": "0",
      "abort_seen": "1",
      "cdc_full_seen": "0",
      "stream_live": "0",
      "gap_valid": "1"
    },
    "passes": [
      [
        0,
        1
      ],
      [
        1,
        1
      ],
      [
        2,
        1
      ],
      [
        3,
        1
      ],
      [
        4,
        1
      ],
      [
        5,
        1
      ],
      [
        6,
        1
      ],
      [
        7,
        1
      ],
      [
        8,
        1
      ],
      [
        9,
        1
      ],
      [
        30,
        1
      ],
      [
        31,
        1
      ]
    ]
  },
  "metrics": {
    "drop_words": 0,
    "frames_bad": 66,
    "pkt_err": 0,
    "cdc_episodes": 0,
    "rows_miss_max": 205,
    "pkts_delta": 132534,
    "bytes_delta": 184228128,
    "frames_sent": 600,
    "frames_recv": 599.7009375,
    "frames_ok": 533.7009375,
    "gap_min_ms": 22,
    "gap_max_ms": 75,
    "gap_sum_ms": 19962,
    "gap_segments": 533,
    "avg_gap_ms": 37.45215759849906,
    "fps_from_gap": 26.700731389640314,
    "fps_wall": 27.19362161610665,
    "hb_slow_a": 0,
    "hb_gone_a": 0,
    "stream_live_a": "0",
    "verdict_no_word_lost": true
  }
}
```