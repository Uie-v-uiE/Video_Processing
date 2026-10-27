# 工作区清点记录：`D:\Xilinx\Prj`

## 扫描口径

- 范围：除 `FIN` 外的全部顶层目录（`Video_Processing`、`fin2`、`fin2_local_archive`、`prj_fin`、`pro`）。
- 判据：对 `.md/.pdf/.docx/.pptx/.html` 逐文件算 MD5，与 `records/docs_archive/MANIFEST.tsv` 的 842 条哈希比对；再按路径名核对是否为 FIN 已有同内容文件的清理版。
- 命中：4704 份候选文档里 477 份哈希未出现过，其中绝大多数是**清理后的当前版本**（`fin2/release/report/*`、`pro/docs_release/*`、`prj_fin/*`、`deliverables/*`），这些内容 FIN 已经在 `submission/` 与 `prj_fin/` 存了同版本，不重复搬。

## 新增归档（11 份）

| 位置 | 内容 |
|---|---|
| `docs_archive/Video_Processing/report/log/` | v6/v8 时期的 9 份板级调试记录：`eth_bringup`、`v6_root_cause`、`v6_board_measurement`、`version_lineage`、`changelog_v6`、`plan_v8_spec`、`d4c_pointers`、`d5_soft_verdicts`、`README` |
| `docs_archive/fin2_local_archive/` | 清理前的原始架构学习手册与上位机指南各 1 份 |

`fin2_local_archive/report_old_20261022` 的其余 104 份与 `records/previous_report/` 逐名比对后确认是同一棵树：FIN 存的是去掉日期与本机路径的版本，源目录存的是原始版本，文件名与子目录结构完全一致（`timing/` 22 份、`log/` 12 份都对得上），不再重复收。

## 已删除（约 137 MiB）

| 对象 | 判断依据 |
|---|---|
| `pro/edge_tmp`（14 MiB） | 误建的 Edge 浏览器配置目录（`Ad Blocking`、`Autofill`、`Crashpad` 等），无项目文件 |
| `pro/c2_scratch_1003`（99 MiB） | Vivado 草稿工程：`build/`、`src/`、`vivado.log`，可重跑 |
| `pro/tmp_main_tree`（24 MiB） | 发布树临时副本，正式树在 `pro/final_release` 与 `FIN/submission/` |
| `pro/__pycache__`、`.Xil`、`.attic` | Python 字节码、Vivado 临时、1 份引脚草稿（已收进 `records/pro_scratch/`） |
| `pro/` 根 30 余份运行日志 | `export*.log`、`push_*.log`、`vserver*.log`、`ren*.log`、`vivado*.log`、`r120_*` 探针输出、`xvlog.pb` |
| `pro/` 根 39 份文本草稿 | `msg_*`、`commitmsg_*`、`ledger_*.tmp.md`、`ctx*.txt`、`_probe*.txt` 等，内容已进 Git 提交信息与 `records/issues/` |
| `pro/` 根 135 份一次性脚本与探针 | 收进 `records/pro_scratch/`（143 份文件）后删源；可重跑的文档与海报生成器在 `fin2/tools/docs/`，已归档于 `records/design/` |

`pro/tmpsub`（2.1 MiB）与 `pro/doc_audit_20261005`（3.5 MiB）里混有 `.sh`、`.diff` 和未被文档扫描覆盖的补丁文件，体积小且不可再生，保留原位。

## 待作者确认的大块（未动）

| 对象 | 体积 | 说明 |
|---|---:|---|
| `pro/sd_stage` | 1.3 GiB | SD 回放演示素材（`VIDEO000.BIN`、`META.TXT`、预览帧）。拍演示视频第 9 部分要用，删了得重新转换 |
| `pro/Video_Processing` | 978 MiB | `all` 分支 worktree，含完整提交历史 |
| `pro/records_wt` | 415 MiB | records 分支 worktree |
| `pro/pkg_archive` | 168 MiB | 三份按提交号命名的旧打包快照，文档已归档、位流可重打 |
| `pro/delivery_review_20261005` | 165 MiB | 交付评审时点的 worktree（带 `.git`） |
| `pro/final_submission` | 141 MiB | 旧提交树副本，当前提交树在 `pro/final_release` |
| `pro/.sub_stage` | 95 MiB | 旧提交 staging 树，文档已在 `docs_archive/pro/.sub_stage/` |
| `pro/submission` | 49 MiB | 更旧的提交树副本 |

`pro/docs_release`（103 MiB）与 `pro/final_release`（16 MiB）是两个在用分支的 worktree，不在清理范围内。

## 复核后的包状态

- `FIN`：3389 个文件，162.82 MiB。`submission` 489 / `learning` 7 / `records` 2893。
- `prj_fin`：1442 个文件，83.43 MiB，本轮未变。
- `D:\Xilinx\Prj\pro` 根目录：只剩目录，无散件。
