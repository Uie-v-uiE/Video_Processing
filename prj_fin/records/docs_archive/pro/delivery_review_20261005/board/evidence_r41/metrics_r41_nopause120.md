# 指标采集 r41_nopause120（2026-09-23T17:37:33.251Z）

命令：`node src/host/metrics.mjs --fps 120 --seconds 8 --no-pace --tag r41_nopause120`
bit：见同目录 `MANIFEST.txt` 或 `build/gates.sh` 当时的报告；板子为 Zynq7020。

| 项 | 值 |
|---|---|
| 发送帧数 / 用时 | 960 / 10.29 s |
| 交付载荷字节增量 | 294912000 → 折合 960.00 帧 |
| 收到包数增量 | 212160 |
| **drop_words 增量** | **0**（CDC 灌满次数 +0） |
| 验收门作废帧 frames_bad 增量 | 0（坏包 0，缺行峰值 205） |
| 帧间隔 min/avg/max (ms) | 2 / 8.57 / 24（959 段） |
| 由间隔算的 fps | 116.709 |
| 由墙钟算的 fps | 93.285 |
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
    "frames_bad": 1261,
    "pkt_err": 0,
    "stall_ms": 28118,
    "rows_miss_max": 205,
    "gap_last": 0,
    "gap_min": 0,
    "gap_max": 0,
    "gap_sum": 0,
    "cdc_episodes": 0,
    "flags": 2,
    "pkts": 860136,
    "bytes": 1195627536,
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
    "frames_bad": 1261,
    "pkt_err": 0,
    "stall_ms": 4901,
    "rows_miss_max": 205,
    "gap_last": 8,
    "gap_min": 2,
    "gap_max": 24,
    "gap_sum": 8217,
    "cdc_episodes": 0,
    "flags": 18,
    "pkts": 1072296,
    "bytes": 1490539536,
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
    "frames_bad": 0,
    "pkt_err": 0,
    "cdc_episodes": 0,
    "rows_miss_max": 205,
    "pkts_delta": 212160,
    "bytes_delta": 294912000,
    "frames_sent": 960,
    "frames_recv": 960,
    "frames_ok": 960,
    "gap_min_ms": 2,
    "gap_max_ms": 24,
    "gap_sum_ms": 8217,
    "gap_segments": 959,
    "avg_gap_ms": 8.56830031282586,
    "fps_from_gap": 116.70926128757455,
    "fps_wall": 93.28539500534447,
    "hb_slow_a": 0,
    "hb_gone_a": 0,
    "stream_live_a": "0",
    "verdict_no_word_lost": true
  }
}
```