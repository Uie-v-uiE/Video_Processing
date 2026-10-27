# PLTG 增强方案评估结果（自动生成）

## 1. 五策略对照（静止停车族：真值固定 2.5 m 内/框外 3 m）

| case | policy | false_fee_rate | miss_violation_rate | hold_rate | auto_decision_rate | first_commit_s | cost_per_100_epochs |
|---|---|---|---|---|---|---|---|
| clean_in | P0_naive | 0.0 | 0.0 | 0.0 | 1.0 | 0.0 | 0.0 |
| clean_in | P1_gated | 0.0 | 0.0 | 0.0 | 1.0 | 0.0 | 0.0 |
| clean_in | P2_single_epoch_PL | 0.0 | 0.0 | 0.9008 | 0.0992 | 6.0 | 2.82 |
| clean_in | P3_PLTG | 0.0 | 0.0 | 0.0331 | 0.9669 | 3.0 | 0.1 |
| clean_in | P4_PLTG_aux | 0.0 | 0.0 | 0.0248 | 0.9752 | 3.0 | 0.08 |
| clean_out | P0_naive | 0.0 | 0.0 | 0.0 | 1.0 | 0.0 | 0.0 |
| clean_out | P1_gated | 0.0 | 0.0 | 0.0 | 1.0 | 0.0 | 0.0 |
| clean_out | P2_single_epoch_PL | 0.0 | 0.0 | 0.9752 | 0.0248 | 6.0 | 3.05 |
| clean_out | P3_PLTG | 0.0 | 0.0 | 0.0331 | 0.9669 | 3.0 | 0.1 |
| clean_out | P4_PLTG_aux | 0.0 | 0.0 | 0.0248 | 0.9752 | 3.0 | 0.08 |
| urban_mp_in | P0_naive | 0.0 | 0.0 | 0.0 | 1.0 | 0.0 | 0.0 |
| urban_mp_in | P1_gated | 0.0 | 0.0 | 0.1653 | 0.8347 | 0.0 | 0.52 |
| urban_mp_in | P2_single_epoch_PL | 0.0 | 0.0 | 0.9752 | 0.0248 | 8.0 | 3.05 |
| urban_mp_in | P3_PLTG | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| urban_mp_in | P4_PLTG_aux | 0.0 | 0.0 | 0.0248 | 0.9752 | 3.0 | 0.08 |
| urban_mp_out | P0_naive | 0.0 | 0.0992 | 0.0 | 1.0 | 0.0 | 1.86 |
| urban_mp_out | P1_gated | 0.0 | 0.0909 | 0.1653 | 0.8347 | 0.0 | 2.22 |
| urban_mp_out | P2_single_epoch_PL | 0.0 | 0.0 | 0.9752 | 0.0248 | 8.0 | 3.05 |
| urban_mp_out | P3_PLTG | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| urban_mp_out | P4_PLTG_aux | 0.0 | 0.0 | 0.0248 | 0.9752 | 3.0 | 0.08 |
| mp_spoof_in | P0_naive | 0.5372 | 0.0 | 0.0 | 1.0 | 0.0 | 16.79 |
| mp_spoof_in | P1_gated | 0.0083 | 0.0 | 0.6364 | 0.3636 | 0.0 | 2.25 |
| mp_spoof_in | P2_single_epoch_PL | 0.0 | 0.0 | 0.9917 | 0.0083 | 22.0 | 3.1 |
| mp_spoof_in | P3_PLTG | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| mp_spoof_in | P4_PLTG_aux | 0.0 | 0.0 | 0.0248 | 0.9752 | 3.0 | 0.08 |
| mp_spoof_out | P0_naive | 0.0 | 0.0 | 0.0 | 1.0 | 0.0 | 0.0 |
| mp_spoof_out | P1_gated | 0.0 | 0.0 | 0.6364 | 0.3636 | 0.0 | 1.99 |
| mp_spoof_out | P2_single_epoch_PL | 0.0 | 0.0 | 0.9669 | 0.0331 | 11.0 | 3.02 |
| mp_spoof_out | P3_PLTG | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| mp_spoof_out | P4_PLTG_aux | 0.0 | 0.0 | 0.0248 | 0.9752 | 3.0 | 0.08 |
| denial_in | P0_naive | 0.7107 | 0.0 | 0.0 | 1.0 | 0.0 | 22.21 |
| denial_in | P1_gated | 0.0 | 0.0 | 0.7107 | 0.2893 | 0.0 | 2.22 |
| denial_in | P2_single_epoch_PL | 0.0 | 0.0 | 0.9587 | 0.0413 | 6.0 | 3.0 |
| denial_in | P3_PLTG | 0.0 | 0.0 | 0.7355 | 0.2645 | 3.0 | 2.3 |
| denial_in | P4_PLTG_aux | 0.0 | 0.0 | 0.0331 | 0.9669 | 3.0 | 0.1 |
| denial_out | P0_naive | 0.0 | 0.0 | 0.0 | 1.0 | 0.0 | 0.0 |
| denial_out | P1_gated | 0.0 | 0.0 | 0.7107 | 0.2893 | 0.0 | 2.22 |
| denial_out | P2_single_epoch_PL | 0.0 | 0.0 | 0.9835 | 0.0165 | 6.0 | 3.07 |
| denial_out | P3_PLTG | 0.0 | 0.0 | 0.7355 | 0.2645 | 3.0 | 2.3 |
| denial_out | P4_PLTG_aux | 0.0 | 0.0 | 0.0331 | 0.9669 | 3.0 | 0.1 |
| heavy_mp_in | P0_naive | 0.0826 | 0.0 | 0.0 | 1.0 | 0.0 | 2.58 |
| heavy_mp_in | P1_gated | 0.0083 | 0.0 | 0.686 | 0.314 | 0.0 | 2.4 |
| heavy_mp_in | P2_single_epoch_PL | 0.0 | 0.0 | 0.9669 | 0.0331 | 8.0 | 3.02 |
| heavy_mp_in | P3_PLTG | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| heavy_mp_in | P4_PLTG_aux | 0.0 | 0.0 | 0.0248 | 0.9752 | 3.0 | 0.08 |
| heavy_mp_out | P0_naive | 0.0 | 0.2645 | 0.0 | 1.0 | 0.0 | 4.96 |
| heavy_mp_out | P1_gated | 0.0 | 0.0992 | 0.686 | 0.314 | 0.0 | 4.0 |
| heavy_mp_out | P2_single_epoch_PL | 0.0 | 0.0 | 0.9587 | 0.0413 | 8.0 | 3.0 |
| heavy_mp_out | P3_PLTG | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| heavy_mp_out | P4_PLTG_aux | 0.0 | 0.0 | 0.0248 | 0.9752 | 3.0 | 0.08 |

## 2. 组件消融（P3 各部件去掉后的变化）

| case | policy | false_fee_rate | miss_violation_rate | hold_rate | auto_decision_rate | first_commit_s | cost_per_100_epochs |
|---|---|---|---|---|---|---|---|
| clean_in | P3_full | 0.0 | 0.0 | 0.0331 | 0.9669 | 3.0 | 0.1 |
| clean_in | P3_无χ²完好性门 | 0.0 | 0.0 | 0.0248 | 0.9752 | 3.0 | 0.08 |
| clean_in | P3_无零速门 | 0.0 | 0.0 | 0.0331 | 0.9669 | 3.0 | 0.1 |
| clean_in | P3_短窗win6 | 0.0 | 0.0 | 0.0413 | 0.9587 | 3.0 | 0.13 |
| clean_in | P3_长窗win40 | 0.0 | 0.0 | 0.0248 | 0.9752 | 3.0 | 0.08 |
| clean_in | P3_宽松HPL_max8m | 0.0 | 0.0 | 0.0331 | 0.9669 | 3.0 | 0.1 |
| clean_in | P3_严格HPL_max2m | 0.0 | 0.0 | 0.0496 | 0.9504 | 5.0 | 0.15 |
| clean_out | P3_full | 0.0 | 0.0 | 0.0331 | 0.9669 | 3.0 | 0.1 |
| clean_out | P3_无χ²完好性门 | 0.0 | 0.0 | 0.0248 | 0.9752 | 3.0 | 0.08 |
| clean_out | P3_无零速门 | 0.0 | 0.0 | 0.0331 | 0.9669 | 3.0 | 0.1 |
| clean_out | P3_短窗win6 | 0.0 | 0.0 | 0.0413 | 0.9587 | 3.0 | 0.13 |
| clean_out | P3_长窗win40 | 0.0 | 0.0 | 0.0248 | 0.9752 | 3.0 | 0.08 |
| clean_out | P3_宽松HPL_max8m | 0.0 | 0.0 | 0.0331 | 0.9669 | 3.0 | 0.1 |
| clean_out | P3_严格HPL_max2m | 0.0 | 0.0 | 0.0496 | 0.9504 | 5.0 | 0.15 |
| urban_mp_in | P3_full | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| urban_mp_in | P3_无χ²完好性门 | 0.0 | 0.0 | 0.8099 | 0.1901 | 56.0 | 2.53 |
| urban_mp_in | P3_无零速门 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| urban_mp_in | P3_短窗win6 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| urban_mp_in | P3_长窗win40 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| urban_mp_in | P3_宽松HPL_max8m | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| urban_mp_in | P3_严格HPL_max2m | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| urban_mp_out | P3_full | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| urban_mp_out | P3_无χ²完好性门 | 0.0 | 0.0 | 0.9008 | 0.0992 | 76.0 | 2.82 |
| urban_mp_out | P3_无零速门 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| urban_mp_out | P3_短窗win6 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| urban_mp_out | P3_长窗win40 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| urban_mp_out | P3_宽松HPL_max8m | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| urban_mp_out | P3_严格HPL_max2m | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| mp_spoof_in | P3_full | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| mp_spoof_in | P3_无χ²完好性门 | 0.0 | 0.0 | 0.8595 | 0.1405 | 8.0 | 2.69 |
| mp_spoof_in | P3_无零速门 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| mp_spoof_in | P3_短窗win6 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| mp_spoof_in | P3_长窗win40 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| mp_spoof_in | P3_宽松HPL_max8m | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| mp_spoof_in | P3_严格HPL_max2m | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| mp_spoof_out | P3_full | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| mp_spoof_out | P3_无χ²完好性门 | 0.0 | 0.0 | 0.9256 | 0.0744 | 16.0 | 2.89 |
| mp_spoof_out | P3_无零速门 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| mp_spoof_out | P3_短窗win6 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| mp_spoof_out | P3_长窗win40 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| mp_spoof_out | P3_宽松HPL_max8m | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| mp_spoof_out | P3_严格HPL_max2m | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| denial_in | P3_full | 0.0 | 0.0 | 0.7355 | 0.2645 | 3.0 | 2.3 |
| denial_in | P3_无χ²完好性门 | 0.0 | 0.0 | 0.7355 | 0.2645 | 3.0 | 2.3 |
| denial_in | P3_无零速门 | 0.0 | 0.0 | 0.7355 | 0.2645 | 3.0 | 2.3 |
| denial_in | P3_短窗win6 | 0.0 | 0.0 | 0.7355 | 0.2645 | 3.0 | 2.3 |
| denial_in | P3_长窗win40 | 0.0 | 0.0 | 0.7355 | 0.2645 | 3.0 | 2.3 |
| denial_in | P3_宽松HPL_max8m | 0.0 | 0.0 | 0.7355 | 0.2645 | 3.0 | 2.3 |
| denial_in | P3_严格HPL_max2m | 0.0 | 0.0 | 0.7521 | 0.2479 | 5.0 | 2.35 |
| denial_out | P3_full | 0.0 | 0.0 | 0.7355 | 0.2645 | 3.0 | 2.3 |
| denial_out | P3_无χ²完好性门 | 0.0 | 0.0 | 0.7355 | 0.2645 | 3.0 | 2.3 |
| denial_out | P3_无零速门 | 0.0 | 0.0 | 0.7355 | 0.2645 | 3.0 | 2.3 |
| denial_out | P3_短窗win6 | 0.0 | 0.0 | 0.7355 | 0.2645 | 3.0 | 2.3 |
| denial_out | P3_长窗win40 | 0.0 | 0.0 | 0.7355 | 0.2645 | 3.0 | 2.3 |
| denial_out | P3_宽松HPL_max8m | 0.0 | 0.0 | 0.7355 | 0.2645 | 3.0 | 2.3 |
| denial_out | P3_严格HPL_max2m | 0.0 | 0.0 | 0.7521 | 0.2479 | 5.0 | 2.35 |
| heavy_mp_in | P3_full | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| heavy_mp_in | P3_无χ²完好性门 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| heavy_mp_in | P3_无零速门 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| heavy_mp_in | P3_短窗win6 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| heavy_mp_in | P3_长窗win40 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| heavy_mp_in | P3_宽松HPL_max8m | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| heavy_mp_in | P3_严格HPL_max2m | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| heavy_mp_out | P3_full | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| heavy_mp_out | P3_无χ²完好性门 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| heavy_mp_out | P3_无零速门 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| heavy_mp_out | P3_短窗win6 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| heavy_mp_out | P3_长窗win40 | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| heavy_mp_out | P3_宽松HPL_max8m | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |
| heavy_mp_out | P3_严格HPL_max2m | 0.0 | 0.0 | 1.0 | 0.0 |  | 3.12 |

## 3. 多径强度扫描（in/out 两位置 × 0→20 m）

| case | multipath_amp_m | policy | false_fee_rate | hold_rate | auto_decision_rate | first_commit_s |
|---|---|---|---|---|---|---|
| park_in_mp0 | 0.0 | P1_gated | 0.0 | 0.0 | 1.0 | 0.0 |
| park_in_mp0 | 0.0 | P3_PLTG | 0.0 | 0.0331 | 0.9669 | 3.0 |
| park_in_mp0 | 0.0 | P4_PLTG_aux | 0.0 | 0.0248 | 0.9752 | 3.0 |
| park_in_mp4 | 4.0 | P1_gated | 0.0 | 0.0 | 1.0 | 0.0 |
| park_in_mp4 | 4.0 | P3_PLTG | 0.0 | 0.9587 | 0.0413 | 3.0 |
| park_in_mp4 | 4.0 | P4_PLTG_aux | 0.0 | 0.0248 | 0.9752 | 3.0 |
| park_in_mp8 | 8.0 | P1_gated | 0.0 | 0.0 | 1.0 | 0.0 |
| park_in_mp8 | 8.0 | P3_PLTG | 0.0 | 1.0 | 0.0 |  |
| park_in_mp8 | 8.0 | P4_PLTG_aux | 0.0 | 0.0248 | 0.9752 | 3.0 |
| park_in_mp12 | 12.0 | P1_gated | 0.0 | 0.1653 | 0.8347 | 0.0 |
| park_in_mp12 | 12.0 | P3_PLTG | 0.0 | 1.0 | 0.0 |  |
| park_in_mp12 | 12.0 | P4_PLTG_aux | 0.0 | 0.0248 | 0.9752 | 3.0 |
| park_in_mp16 | 16.0 | P1_gated | 0.0 | 0.5372 | 0.4628 | 0.0 |
| park_in_mp16 | 16.0 | P3_PLTG | 0.0 | 1.0 | 0.0 |  |
| park_in_mp16 | 16.0 | P4_PLTG_aux | 0.0 | 0.0248 | 0.9752 | 3.0 |
| park_in_mp20 | 20.0 | P1_gated | 0.0083 | 0.686 | 0.314 | 0.0 |
| park_in_mp20 | 20.0 | P3_PLTG | 0.0 | 1.0 | 0.0 |  |
| park_in_mp20 | 20.0 | P4_PLTG_aux | 0.0 | 0.0248 | 0.9752 | 3.0 |
| park_out_mp0 | 0.0 | P1_gated | 0.0 | 0.0 | 1.0 | 0.0 |
| park_out_mp0 | 0.0 | P3_PLTG | 0.0 | 0.0331 | 0.9669 | 3.0 |
| park_out_mp0 | 0.0 | P4_PLTG_aux | 0.0 | 0.0248 | 0.9752 | 3.0 |
| park_out_mp4 | 4.0 | P1_gated | 0.0 | 0.0 | 1.0 | 0.0 |
| park_out_mp4 | 4.0 | P3_PLTG | 0.0 | 0.9752 | 0.0248 | 5.0 |
| park_out_mp4 | 4.0 | P4_PLTG_aux | 0.0 | 0.0248 | 0.9752 | 3.0 |
| park_out_mp8 | 8.0 | P1_gated | 0.0 | 0.0 | 1.0 | 0.0 |
| park_out_mp8 | 8.0 | P3_PLTG | 0.0 | 1.0 | 0.0 |  |
| park_out_mp8 | 8.0 | P4_PLTG_aux | 0.0 | 0.0248 | 0.9752 | 3.0 |
| park_out_mp12 | 12.0 | P1_gated | 0.0 | 0.1653 | 0.8347 | 0.0 |
| park_out_mp12 | 12.0 | P3_PLTG | 0.0 | 1.0 | 0.0 |  |
| park_out_mp12 | 12.0 | P4_PLTG_aux | 0.0 | 0.0248 | 0.9752 | 3.0 |
| park_out_mp16 | 16.0 | P1_gated | 0.0 | 0.5372 | 0.4628 | 0.0 |
| park_out_mp16 | 16.0 | P3_PLTG | 0.0 | 1.0 | 0.0 |  |
| park_out_mp16 | 16.0 | P4_PLTG_aux | 0.0 | 0.0248 | 0.9752 | 3.0 |
| park_out_mp20 | 20.0 | P1_gated | 0.0 | 0.686 | 0.314 | 0.0 |
| park_out_mp20 | 20.0 | P3_PLTG | 0.0 | 1.0 | 0.0 |  |
| park_out_mp20 | 20.0 | P4_PLTG_aux | 0.0 | 0.0248 | 0.9752 | 3.0 |

## 4. 定位层面对照（窗口聚合位置误差与保护级）

| case | multipath_amp_m | win_pos_err_gnss_m | hpl_gnss_m | win_pos_err_aux_m | hpl_aux_m | gnss_gate_pass |
|---|---|---|---|---|---|---|
| park_in_mp0 | 0.0 | 0.36 | 1.09 | 0.09 | 0.2 | True |
| park_in_mp4 | 4.0 | 0.69 | 1.62 | 0.09 | 0.32 | False |
| park_in_mp8 | 8.0 | 1.62 | 2.71 | 0.09 | 0.32 | False |
| park_in_mp12 | 12.0 | 2.56 | 3.9 | 0.09 | 0.32 | False |
| park_in_mp16 | 16.0 | 3.49 | 5.13 | 0.09 | 0.32 | False |
| park_in_mp20 | 20.0 | 4.45 | 6.37 | 0.09 | 0.32 | False |
| park_out_mp0 | 0.0 | 0.36 | 1.09 | 0.12 | 0.2 | True |
| park_out_mp4 | 4.0 | 0.69 | 1.62 | 0.13 | 0.32 | False |
| park_out_mp8 | 8.0 | 1.62 | 2.71 | 0.13 | 0.32 | False |
| park_out_mp12 | 12.0 | 2.56 | 3.9 | 0.13 | 0.32 | False |
| park_out_mp16 | 16.0 | 3.49 | 5.13 | 0.13 | 0.32 | False |
| park_out_mp20 | 20.0 | 4.45 | 6.37 | 0.13 | 0.32 | False |

## 5. 汇总均值（全部静止场景）

| policy | mean_false_fee | mean_hold | mean_auto | mean_cost |
|---|---|---|---|---|
| P0_naive | 0.1331 | 0.0 | 1.0 | 4.84 |
| P1_gated | 0.0017 | 0.4397 | 0.5603 | 1.78 |
| P2_single_epoch_PL | 0.0 | 0.9653 | 0.0347 | 3.02 |
| P3_PLTG | 0.0 | 0.7537 | 0.2463 | 2.35 |
| P4_PLTG_aux | 0.0 | 0.0265 | 0.9735 | 0.08 |

- 关键结论（自动从结果表取值）：
  - urban_mp_in：旧逻辑误扣 0% → P3 误扣 0%、HOLD 100%；P4 误扣 0%、自动判决率 98%、首次定案 3 s
  - mp_spoof_in：旧逻辑误扣 54% → P3 误扣 0%、HOLD 100%；P4 误扣 0%、自动判决率 98%、首次定案 3 s
  - heavy_mp_in：旧逻辑误扣 8% → P3 误扣 0%、HOLD 100%；P4 误扣 0%、自动判决率 98%、首次定案 3 s
  - denial_in：旧逻辑误扣 71% → P3 误扣 0%、HOLD 74%；P4 误扣 0%、自动判决率 97%、首次定案 3 s
  - urban_mp_out（真实违停）：P3 漏判 0%、HOLD 100%；P4 漏判 0%、首次扣费 3 s
  - heavy_mp_out（真实违停）：P3 漏判 0%、HOLD 100%；P4 漏判 0%、首次扣费 3 s
