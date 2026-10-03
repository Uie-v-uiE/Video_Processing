#!/usr/bin/env bash
# build/r114_maxfanout_ab.sh —— 名字保留，实体已经改名了（这一支只是转接）
#
#   为什么保留这个路径：正在等待的排期脚本 `build/r113_after_chain_experiments.sh` 按这个名字调用，
#   而规矩是"不许改一个后台实例还在执行的脚本"——所以换实现的方式是新建 `r114_replication_ab.sh`，
#   这里留一个转接，不复制判读逻辑（死代码要删得有凭据，这里连代码都没有）。
#
#   为什么换名字：2026-10-03 实测（build/evidence/r113_help_fanout2_console.txt）`set_max_fanout`
#   在本工具 2025.2.1 里**不存在**，这一刀真正的杠杆是 `phys_opt_design -force_replication_on_nets`，
#   所以名字里的 "maxfanout" 是错的，新脚本按机制命名。
set -u
cd "$(dirname "$0")/.."
exec bash build/r114_replication_ab.sh "$@"
