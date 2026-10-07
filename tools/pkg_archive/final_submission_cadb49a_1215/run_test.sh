#!/bin/bash
# run_test.sh —— 跨平台入口：调一键测试工具的 Python 侧（Node 侧的双击入口是 run_test.bat）。
# 用途：跑四步并把每步读数打成一行结论（判定词在行尾）——ping 板卡 → 连上读回口 → 发 data/ 里的
#      内置测试片源 → 回收计数对账；路径全部相对本文件所在的仓库根，不写绝对路径。
# 输入：命令行参数原样转给 src/host/one_click_test.py（--help 有全表），如 bash run_test.sh --dry-run
# 输出：stdout 四行 [n/4] 结论 + 一行 ONE-CLICK 总结论；xsdb 原始回读留在 data/measured/。
# 退出码：0=四步全 PASS 1=任一步 FAIL 2=参数或片源文件不对、或本机没有 python3（--dry-run 恒 0）。
set -u
cd "$(dirname "$0")" || exit 2
PY=${PYTHON:-python3}
command -v "$PY" >/dev/null 2>&1 || PY=python
command -v "$PY" >/dev/null 2>&1 || { echo "REFUSE: 本机找不到 python3/python ⇒ Python 侧跑不起来（装了 Node 就改用 run_test.bat）"; exit 2; }
"$PY" src/host/one_click_test.py "$@"
rc=$?
echo "run_test.sh 转达 src/host/one_click_test.py 的退出码=${rc}（0=四步全 PASS，1=任一步 FAIL，2=参数或片源文件不对）"
exit $rc
