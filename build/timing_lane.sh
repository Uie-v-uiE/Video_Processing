#!/usr/bin/env bash
# build/timing_lane.sh —— "时序/小刀快车道"：一轮迭代只跑**分钟级**的台架 + 只读时序探针，
# 把那一支约 100 分钟的顶层台架 `tb_v98_top_seam` 留给**采纳前那一次**。
#
# 为什么要有它（2026-10-02 用户明确要求）：以前每把一刀就整链跑一遍，"优化时序"这件事的
# 判决其实来自**只读探针**（同一端点对的 slack/级数/route 占比）与**单元台架**（等价性），
# 而顶层台架那 100 分钟只是重复确认全局观感 —— 逐刀付它不划算。快车道的分工是：
#   快车道（本脚本，分钟级）= 单元等价性 + 受影响锥的专项判据 + 边缘条带；
#   采纳前（build/rNN_chain.sh 那一支）= 顶层台架 + 门禁 + 上板 + board_verify。
# ⚠ 快车道的绿**不代替**门禁：它不产 `build/tb_v98_report.txt`，所以门禁第 15 项仍然必须等
#   顶层台架真跑过。这一条写在末行的提示里，免得下一程把车道绿当成凭据。
#
# 每条判据一行（#121 定的"每轮每条打一行"），退出码只看**清单是否跑齐**与**是否有真红**：
#   0 = 清单全部跑完且无红；3 = 有台架判红（红是结论，不是脚本坏）；2 = 前置不满足（REFUSE 计数不为 0）；
#   1 = 清单没跑齐（地板破了 —— 少跑一支比多跑一支危险）。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-}
[ -f "$V/xvlog" ] || { echo "LANE-REFUSE: 先设 VP_VIVADO_BIN=<Vivado>/bin（当前 '$V'）"; exit 2; }
export VP_VIVADO_BIN="$V"

# 清单：只放**跑得完的**（顶层台架不在内，理由见文件头）。分组注释就是它守的那把锥。
# ⚠ 实测过的分界线（2026-10-02 第一跑，凭据 build/r109_lane_cost.txt）：**例化 `pl_video_top` 的那几支
#   本身就是"顶层台架"**，一支 `tb_v98_c8_edge_column` 跑了 15 分钟还没收尾 ⇒ 它们与 tb_v98 同一档，
#   必须从快车道的清单里剔除；单元/窗口级那十几支实测 **15~19 秒一支**。
#   用 `grep -l pl_video_top sim/tb_*.v` 可以重查这份边界，别凭名字猜。
LANE=(
  # 收包链 / ICMP（r107 分组刀、r108 校验和两拍刀都在这几条上）
  tb_icmp_ping0 tb_icmp_rx_len tb_icmp_len_wrap tb_udp_reasm tb_reasm_bounds tb_udp_parser tb_v795_rx_chain
  # 帧头 / 旋转 / 行环 / 双线性（#98/#102/#167 那一族）
  tb_head_rot_displace tb_v100_raw_delay tb_v100_fit_rot tb_rotate_mapper tb_zoom_mapper
  tb_zoom_fit_corners tb_rotate_window tb_fb_rd5x tb_bilin_lerp tb_v101_fb_bilin
  # 边缘条带（门禁第 15b 项那把尺子，分钟级，留在车道里）
  tb_edge_rim
  # OSD 读侧（#105 那 23 级锥的所在地）
  tb_osd_lines tb_v794_osd_glyph
  # 其它分钟级安全网（在途读 / 仲裁 / 抽头调度 / 链路监视 / CDC / 心跳 / 时序 / 分割控制）
  tb_writer_abort tb_src_arb_why tb_tap_sched tb_link_monitor
  tb_cdc_capacity tb_ps_publish tb_timing tb_v93_split_ctrl
)
[ "${1:-}" = "--list" ] && { printf '%s\n' "${LANE[@]}"; exit 0; }

N=${#LANE[@]}
# ⚠ **门口先验一遍没有活的 xsim**（2026-10-02 第一跑就撞在这一点上）：`run_one.sh` 的"已有 xsim 在跑"
#   那一支 **exit 3**，而"判红"也是 3 —— 只看退出码就会把 20 支"被挡在门外"读成 20 支"判红"，
#   而真正的红只有 1 支（`tb_link_monitor` 的既存 F2e）。这就是本仓那条老规矩的形状：
#   **退出码不够，判定要读文本**（rule 46/#163/#166：红与"没数"与"没跑"必须长得不一样）。
if tasklist //FI "IMAGENAME eq xsim.exe" 2>/dev/null | grep -qi "xsim.exe"; then
    echo "LANE-REFUSE: 已经有 xsim 在跑，车道会被它挡成 rc=3（那**不是判红**）。先确认是谁的再杀："
    echo "               taskkill //F //IM xsim.exe //T && taskkill //F //IM xsimk.exe //T"
    exit 2
fi
echo "LANE-START $(date +%H:%M:%S) 清单=$N（顶层台架 tb_v98_top_seam 不在快车道，见文件头）"
green=0; red=0; refuse=0; cfail=0
t0=$(date +%s)
for tb in "${LANE[@]}"; do
  s=$(date +%s)
  out=$(bash sim/run_one.sh "$tb" 2>&1)
  rc=$?
  w=$(( $(date +%s) - s ))
  nv=$(printf '%s\n' "$out" | grep -a "^VERDICT" | head -1)
  # `rc=3` 有两种：**被别人的 xsim 挡在门外**（没有 VERDICT 行，输出里点名的就是那两句提示）与**真判红**
  #（有 VERDICT 行，判定里带 FAIL）。按文本分家，别按退出码猜。
  case $rc in
    0) green=$((green+1)); tag=GREEN ;;
    3) if [ -n "$nv" ]; then red=$((red+1)); tag=RED;
       else refuse=$((refuse+1)); tag=BLOCKED; fi ;;
    2) refuse=$((refuse+1)); tag=REFUSE ;;
    4) cfail=$((cfail+1));  tag=NO-VERDICT ;;
    *) cfail=$((cfail+1));  tag=RC$rc ;;
  esac
  echo "LANE $tag wall=${w}s rc=$rc ${nv:-$(printf '%s\n' "$out" | tail -1)}"
done
total=$(( $(date +%s) - t0 ))
ran=$((green+red+refuse+cfail))
echo "LANE-SUMMARY ran=$ran/$N green=$green red=$red refuse=$refuse no-verdict/other=$cfail wall=${total}s ($(date +%H:%M:%S))"
# 地板：**比较做了多少次**才算跑齐（rule 47：计数口径不许随红数自己缩水）
if [ "$ran" -ne "$N" ]; then echo "LANE-FATAL ran=$ran != 清单=$N —— 有一支没跑到，读数不完整"; exit 1; fi
if [ "$refuse" -ne 0 ] || [ "$cfail" -ne 0 ]; then echo "LANE-FATAL REFUSE=$refuse 无判定=$cfail（前置或台架形状坏了）"; exit 2; fi
if [ "$red" -ne 0 ]; then echo "LANE 结论：$red 支判红 —— 红是结论，去 log 里点名是哪条判据"; exit 3; fi
echo "LANE 结论：全绿。**这不代替门禁**——采纳前必须跑 sim/run_one.sh tb_v98_top_seam + build/tb98_report.sh"
exit 0
