#!/bin/bash
# skill/scripts/selftest/run_all.sh — 判据脚本的自测串跑（G11 的判据对象）
#
# 做什么：对 skill/scripts/ 下每支判据脚本跑「正例 + 反例 + 守卫 + 读不到输入」四类对照，
#         每个脚本恰好一行 `<id> <label> 判 <N> 项 <detail> PASS|FAIL|NOT_MEASURED`（判定 token 在最后一列），
#         收尾一行汇总。分母 `判 N 项` 数的是**做了多少次对照**，不是通过了几次。
#         反例的验收标准不是"整体变红"，而是"它点名的那一条判据变红"（否则红在哪不知道）。
#
# 用法（仓库根或任意目录都行，脚本自己定位仓库根）：
#   bash skill/scripts/selftest/run_all.sh
# 退出码：0=全部对照成立 1=有红项 2=有 NOT_MEASURED（脚本/fixture 读不到）3=前置不满足（没有 node / 仓库根定位失败）
#
# 硬约束（本仓库的规矩）：
#  - 读不到脚本或 fixture ⇒ 那一行 NOT_MEASURED 且计入未测，绝不静默跳过、绝不判绿；
#  - 不跑综合/仿真/Vivado/板级/串口工具，只跑 node 与 bash；
#  - 所有产物写进 mktemp -d 的临时目录，绝不写交付树。静态守卫之外还要跑**动态那一半**
#    （`check/static_check.mjs:122` 明写"真把 --out-dir 指到工程目录时会不会拒绝，在 selftest/run_all.sh 里逐脚本跑"），
#    所以每支会写文件的脚本都被喂一个工程目录做 --out-dir，要求它拒绝且真的没落盘；
#  - 运行时文字一律 ASCII（本机控制台 cp936，CJK 会让 grep 失真），只有分母 token `判 N 项` 是 UTF-8。
#
# fixture ↔ 脚本 对应（2026-10-04 逐个实跑确认；细节见各脚本目录的 SKILL.md 第 7 节）：
#   contract_gen    正 skill/scripts/regmap_check/contract.tsv（14 列表，本仓示例取值）
#                   反 fixtures/contract_gen_negative_bad_widest（C3 红）
#                      fixtures/regmap_negative_missing_field（C1 红 ⇒ 退出 3，不生成）
#   golden_compare  正/反 fixtures/golden_compare_positive|negative（C2 增减都红）
#   regmap_check    正 axi_gpio_contract.tsv + build/tcl/build_system_axigpio.tcl（--only K1,K3,K6,K7,K8）
#                   反 临时合成的 BD（多钉一个表里没有的地址 ⇒ 只有 K6 红）
#                   注：fixtures/regmap_negative_{missing_field,bad_cite} 是 14 列旧词表的件，
#                       22 列的 regmap_check 读它们会在 K5 崩（TypeError）而不是判红 ⇒ 本 runner 不接，
#                       missing_field 那份改由 contract_gen 的 C1 消费（缺格退出 3），bad_cite 那份目前无人消费。
#   report_metrics  正 build/timing_summary.rpt + build/utilization.rpt（给阈值 + 上一份 csv 当 baseline）
#                   反 fixtures/report_metrics_negative（R3 红）、越界阈值（R6 红）、被改过的 baseline（R7 红）
#   repro_check     正 临时合成源码树 capture + verify（七个 V 判据全绿）
#                   反 fixtures/repro_negative/report_head.rpt（V5 红）、改过 aggregate 的证据件（V1 红）
#   static_check    正 --root skill/scripts/contract_gen；反 临时拷贝 fixtures/static_negative_{net,write}（T1/T2 各红一条）

set -u

SELFTEST_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_ABS=$(cd "$SELFTEST_DIR/../../.." && pwd)     # skill/scripts/selftest -> 仓库根
cd "$ROOT_ABS" || { echo 'SELFTEST precondition     判 0 项 cwd_failed NOT_MEASURED'; exit 3; }

if [ ! -d skill/scripts ] || [ ! -d skill/scripts/selftest/fixtures ]; then
  echo 'SELFTEST precondition     判 0 项 repo_layout_not_found NOT_MEASURED'
  exit 3
fi
command -v node >/dev/null 2>&1 || {
  echo 'SELFTEST precondition     判 0 项 node_not_on_path NOT_MEASURED'; exit 3; }
NODE_VER=$(node --version 2>/dev/null || echo none)
case "$NODE_VER" in
  v*) : ;;
  *) echo "SELFTEST precondition     判 0 项 node_probe_gave_$NODE_VER NOT_MEASURED"; exit 3 ;;
esac

WORK=$(mktemp -d 2>/dev/null) || { echo 'SELFTEST precondition     判 0 项 mktemp_failed NOT_MEASURED'; exit 3; }
trap 'rm -rf "$WORK"' EXIT
: > "$WORK/empty.tsv"                       # 各家脚本共用的"空输入"件（读空文件必须 NOT_MEASURED）
PROJ_DIR='build/_selftest_scratch'          # 动态守卫的靶子：只用来被脚本拒绝，绝不允许真的出现

# ---------- 计数器与打印 ----------
S_MADE=0; S_BAD=0; S_NM=0; S_DET=''
G_MADE=0; G_BAD=0; G_NM=0; G_PASS=0; G_LINES=0
RC=0; LOGF="$WORK/log.txt"

run() { run_in "$ROOT_ABS" "$@"; }
run_in() { # run_in <cwd> <log> <cmd...> — 结果只落临时 log，屏上不印（屏上每脚本一行）
  local d=$1; LOGF=$2; shift 2
  ( cd "$d" && "$@" >"$LOGF" 2>&1 )
  RC=$?
}

need() { # need <path> — 输入读不到 ⇒ 记一次未测，不记通过
  if [ -e "$1" ]; then return 0; fi
  S_NM=$((S_NM + 1)); S_DET="$S_DET miss=$(basename "$1")"
  return 1
}

chk() { # chk <tag> <want_rc|NZ> <want_last_token|''> <crit_regex|''> — 对上一次 run 做一次对照
  local tag=$1 want_rc=$2 want_last=$3 crit=$4 got_last='' why=''
  S_MADE=$((S_MADE + 1))
  got_last=$(grep -v '^[[:space:]]*$' "$LOGF" 2>/dev/null | tail -1 | awk '{print $NF}')
  if [ "$want_rc" = 'NZ' ]; then
    [ "$RC" -ne 0 ] || why="rc=$RC"
  else
    [ "$RC" -eq "$want_rc" ] || why="rc=$RC/$want_rc"
  fi
  if [ -n "$want_last" ] && [ "$got_last" != "$want_last" ]; then
    why="$why last=${got_last:-none}/$want_last"
  fi
  if [ -n "$crit" ] && ! grep -qE "$crit" "$LOGF"; then
    why="$why crit_absent"
  fi
  if [ -z "$why" ]; then S_DET="$S_DET $tag=ok"
  else S_BAD=$((S_BAD + 1)); S_DET="$S_DET $tag=BAD($why)"; fi
}

ckc() { # ckc <tag> <1|0> <why> — 非命令类对照（产物在不在盘上、空集有没有被判绿）
  S_MADE=$((S_MADE + 1))
  if [ "$2" = '1' ]; then S_DET="$S_DET $1=ok"
  else S_BAD=$((S_BAD + 1)); S_DET="$S_DET $1=BAD($3)"; fi
}

emit() { # emit <id> <label> — 一个脚本一行；红>0 判 FAIL，未测>0 或一次都没判 判 NOT_MEASURED
  local v
  if [ "$S_BAD" -gt 0 ]; then v='FAIL'; G_BAD=$((G_BAD + 1))
  elif [ "$S_NM" -gt 0 ] || [ "$S_MADE" -eq 0 ]; then v='NOT_MEASURED'; G_NM=$((G_NM + 1))
  else v='PASS'; G_PASS=$((G_PASS + 1)); fi
  G_MADE=$((G_MADE + S_MADE)); G_LINES=$((G_LINES + 1))
  printf '%-7s %-22s 判 %d 项 %.180s %s\n' "$1" "$2" "$S_MADE" "$S_DET" "$v"
  S_MADE=0; S_BAD=0; S_NM=0; S_DET=''
}

FIX=skill/scripts/selftest/fixtures

# ---------- 1) contract_gen ----------
CG=skill/scripts/contract_gen/contract_gen.mjs
CG_TSV=skill/scripts/regmap_check/contract.tsv
if need "$CG"; then
  if need "$CG_TSV"; then
    run "$LOGF" node "$CG" --contract "$CG_TSV" --out-dir "$WORK/gen"
    chk pos 0 PASS '^C5_units_and_domain_in_code .* PASS'
    ckc pos_files "$([ -f "$WORK/gen/regmap_host.mjs" ] && [ -f "$WORK/gen/regmap_host_stub.mjs" ] && echo 1 || echo 0)" 'emitted_lt2'
    if need "$WORK/gen/regmap_host_stub.mjs"; then
      run "$LOGF" node "$WORK/gen/regmap_host_stub.mjs"
      chk stub 0 PASS '^GEN_STUB'
    fi
  fi
  if need "$FIX/contract_gen_negative_bad_widest/contract.tsv"; then
    run "$LOGF" node "$CG" --contract "$FIX/contract_gen_negative_bad_widest/contract.tsv" --out-dir "$WORK/neg3"
    chk negC3 1 FAIL '^C3_widest_input_recheck .* FAIL'
  fi
  if need "$FIX/regmap_negative_missing_field/contract.tsv"; then
    run "$LOGF" node "$CG" --contract "$FIX/regmap_negative_missing_field/contract.tsv" --out-dir "$WORK/neg1"
    chk negC1 3 FAIL '^C1_required_fields .* FAIL'
  fi
  run "$LOGF" node "$CG" --contract "$CG_TSV" --out-dir "$PROJ_DIR"
  chk guard NZ '' ''
  ckc guard_no_write "$([ ! -e "$PROJ_DIR" ] && echo 1 || echo 0)" 'wrote_into_project_dir'
  run "$LOGF" node "$CG" --contract "$WORK/empty.tsv" --out-dir "$WORK/g_empty"
  chk empty 2 NOT_MEASURED '^GEN'
fi
emit CGEN contract_gen

# ---------- 2) golden_compare ----------
GC=skill/scripts/golden_compare/golden_compare.mjs
GPOS="$FIX/golden_compare_positive"
if need "$GC"; then
  if need "$GPOS/golden.tsv" && need "$GPOS/produced.tsv"; then
    run "$LOGF" node "$GC" --golden "$GPOS/golden.tsv" --produced "$GPOS/produced.tsv" \
        --golden-key '$1' --golden-values 'endpoints=@2,unsafe=@1' \
        --produced-key '$1' --produced-values 'endpoints=@2,unsafe=@1' --out-dir "$WORK/gold"
    chk pos 0 PASS '^C2_value_vs_tolerance .* PASS'
    ckc pos_art "$([ -f "$WORK/gold/golden_diff.csv" ] && echo 1 || echo 0)" 'diff_csv_absent'
    run "$LOGF" node "$GC" --golden "$GPOS/golden.tsv" --produced "$GPOS/produced.tsv" \
        --golden-key '$1' --golden-values 'endpoints=@2,unsafe=@1' \
        --produced-key '$1' --produced-values 'endpoints=@2,unsafe=@1' --out-dir "$PROJ_DIR"
    chk guard 3 FAIL '^GOLDEN'
    printf '# header line only, no data row\n' > "$WORK/empty_produced.tsv"
    run "$LOGF" node "$GC" --golden "$GPOS/golden.tsv" --produced "$WORK/empty_produced.tsv" \
        --golden-key '$1' --golden-values 'endpoints=@2,unsafe=@1' \
        --produced-key '$1' --produced-values 'endpoints=@2,unsafe=@1'
    chk empty_set 1 FAIL '^C1_key_coverage .* FAIL'
  fi
  if need "$FIX/golden_compare_negative/produced.tsv"; then
    run "$LOGF" node "$GC" --golden "$GPOS/golden.tsv" --produced "$FIX/golden_compare_negative/produced.tsv" \
        --golden-key '$1' --golden-values 'endpoints=@2,unsafe=@1' \
        --produced-key '$1' --produced-values 'endpoints=@2,unsafe=@1'
    chk negC2 1 FAIL '^C2_value_vs_tolerance .* FAIL'
  fi
  run "$LOGF" node "$GC" --golden no_such_a.tsv --produced no_such_b.tsv \
      --golden-key '$1' --golden-values 'endpoints=@2' --produced-key '$1' --produced-values 'endpoints=@2'
  chk missing 2 NOT_MEASURED '^GOLDEN'
  if need build/CDC_BASELINE.txt && need build/frozen_r23_srcseen/cdc.rpt; then
    run "$LOGF" node "$GC" --golden build/CDC_BASELINE.txt --golden-format kv --golden-key '$1' \
        --golden-values 'endpoints=@2,unsafe=@1' --produced build/frozen_r23_srcseen/cdc.rpt \
        --produced-format kv --produced-key '$2>$3' --produced-values 'endpoints=@5,unsafe=@3' \
        --produced-where '$1=Critical' --tolerance 0
    chk real_pair 0 PASS '^C4_parse_surface_nonempty .* PASS'
  fi
fi
emit GCMP golden_compare

# ---------- 3) regmap_check ----------
RG=skill/scripts/regmap_check/regmap_check.mjs
RG_TSV=skill/scripts/regmap_check/axi_gpio_contract.tsv
RG_BD=build/tcl/build_system_axigpio.tcl
if need "$RG"; then
  printf 'selftest/pin 0x41299999\n' > "$WORK/bd_extra.tcl"
  printf '# a bd file that pins no address at all\n' > "$WORK/bd_none.tcl"
  if need "$RG_TSV" && need "$RG_BD"; then
    run "$LOGF" node "$RG" --contract "$RG_TSV" --bd "$RG_BD" --only K1,K3,K6,K7,K8
    chk pos 0 PASS '^K8 reset_provenance .* PASS'
    run "$LOGF" node "$RG" --contract "$RG_TSV" --bd "$WORK/bd_extra.tcl" --only K6
    chk negK6 1 FAIL '^K6 .* pinned_not_in_table=1.* FAIL'
    run "$LOGF" node "$RG" --contract "$RG_TSV" --bd "$WORK/bd_none.tcl" --only K6
    k6v=$(grep -E '^K6 ' "$LOGF" | tail -1 | awk '{print $NF}')
    ckc emptyK6 "$([ "$RC" -ne 0 ] && [ "$k6v" != 'PASS' ] && echo 1 || echo 0)" "K6_green_on_zero_pinned_bd(rc=$RC)"
    run "$LOGF" node "$RG" --bd "$RG_BD"
    chk precondition 3 FAIL '^REGMAP'
    run "$LOGF" node "$RG" --contract "$WORK/empty.tsv" --bd "$RG_BD"
    chk empty_tsv 2 NOT_MEASURED '^REGMAP'
    run "$LOGF" node "$RG" --contract "$RG_TSV" --bd "$RG_BD" --only K9
    chk only_typo 2 NOT_MEASURED '^REGMAP'
  fi
fi
emit RGMAP regmap_check

# ---------- 4) report_metrics ----------
MM=skill/scripts/report_metrics/report_metrics.mjs
MM_T=build/timing_summary.rpt
MM_U=build/utilization.rpt
if need "$MM"; then
  if need "$MM_T" && need "$MM_U"; then
    run "$LOGF" node "$MM" --timing "$MM_T" --utilization "$MM_U" --out-dir "$WORK/m1" \
        --max-pct lut_slice=40 --min-pct lut_slice=10
    chk no_baseline 2 NOT_MEASURED '^R7_baseline_drift .* NOT_MEASURED'
    if need "$WORK/m1/metrics.csv"; then
      run "$LOGF" node "$MM" --timing "$MM_T" --utilization "$MM_U" --out-dir "$WORK/m2" \
          --max-pct lut_slice=40 --min-pct lut_slice=10 --baseline "$WORK/m1/metrics.csv" --max-drift-pct 0
      chk pos 0 PASS '^R6_threshold_band .* PASS'
      ckc pos_art "$([ -f "$WORK/m2/metrics.csv" ] && [ -f "$WORK/m2/metrics.md" ] && echo 1 || echo 0)" 'csv_or_md_absent'
      sed 's/^reg_slice,[0-9.]*,/reg_slice,7000,/' "$WORK/m1/metrics.csv" > "$WORK/m1_bad.csv"
      run "$LOGF" node "$MM" --timing "$MM_T" --utilization "$MM_U" --out-dir "$WORK/m3" \
          --max-pct lut_slice=40 --min-pct lut_slice=10 --baseline "$WORK/m1_bad.csv" --max-drift-pct 0
      chk negR7 1 FAIL '^R7_baseline_drift .* FAIL'
    fi
    run "$LOGF" node "$MM" --timing "$MM_T" --utilization "$MM_U" --out-dir "$WORK/m4" \
        --max-pct lut_slice=1 --min-pct lut_slice=0
    chk negR6 1 FAIL '^R6_threshold_band .* FAIL'
    run "$LOGF" node "$MM" --timing "$MM_T" --utilization "$MM_U" --out-dir "$PROJ_DIR" \
        --max-pct lut_slice=40 --min-pct lut_slice=10
    chk guard 3 FAIL '^METRICS'
    ckc guard_no_write "$([ ! -e "$PROJ_DIR" ] && echo 1 || echo 0)" 'wrote_into_project_dir'
  fi
  if need "$FIX/report_metrics_negative/timing_summary.rpt" && need "$FIX/report_metrics_negative/utilization.rpt"; then
    run "$LOGF" node "$MM" --timing "$FIX/report_metrics_negative/timing_summary.rpt" \
        --utilization "$FIX/report_metrics_negative/utilization.rpt" --out-dir "$WORK/m5" \
        --max-pct lut_slice=40 --min-pct lut_slice=10
    chk negR3 1 FAIL '^R3_whole_vs_parts .* FAIL'
  fi
  run "$LOGF" node "$MM" --timing no_such.rpt --utilization "$MM_U" --out-dir "$WORK/m6"
  chk missing 2 NOT_MEASURED '^METRICS'
fi
emit METRIC report_metrics

# ---------- 5) repro_check ----------
RP=skill/scripts/repro_check/repro_check.mjs
RP_STAMP='2026-10-04T04:00:00+08:00'
if need "$RP"; then
  mkdir -p "$WORK/src" "$WORK/art" "$WORK/ev"
  printf 'module self_a;\nendmodule\n' > "$WORK/src/a.v"
  printf 'module self_b;\nendmodule\n' > "$WORK/src/b.v"
  if need "$WORK/src/a.v" && need "$WORK/src/b.v"; then
    run_in "$WORK" "$LOGF" node "$ROOT_ABS/$RP" capture --root "$WORK/src" --out-dir "$WORK/ev" --stamp "$RP_STAMP"
    chk capture 0 PASS '^CAP_surface .* PASS'
    EV="$WORK/ev/fingerprint_manifest.txt"
    if need "$EV" && need "$ROOT_ABS/$MM_T" && need "$ROOT_ABS/report/BUILD.md"; then
      AGG=$(sed -n 's/^aggregate_norm1_findshape=\([0-9a-f]\{12\}\)$/\1/p' "$EV")
      [ -n "$AGG" ] && printf 'rtl=%s\n' "$AGG" > "$WORK/recorded.txt"
      ( cd "$WORK/art" && cp "$WORK/src/a.v" "$WORK/src/b.v" . && md5sum a.v b.v > MD5SUMS.txt )
      run_in "$WORK" "$LOGF" node "$ROOT_ABS/$RP" verify --root "$WORK/src" --evidence "$EV" \
          --report "$ROOT_ABS/$MM_T" --declare "$ROOT_ABS/report/BUILD.md" \
          --recorded "$WORK/recorded.txt" --manifest "$WORK/art/MD5SUMS.txt" --strict-set
      chk verify 0 PASS '^V2_fingerprint_binds_content .* PASS'
      if need "$FIX/repro_negative/report_head.rpt"; then
        run_in "$WORK" "$LOGF" node "$ROOT_ABS/$RP" verify --root "$WORK/src" --evidence "$EV" \
            --report "$ROOT_ABS/$FIX/repro_negative/report_head.rpt" --declare "$ROOT_ABS/report/BUILD.md"
        chk negV5 1 FAIL '^V5_captured_before_build .* FAIL'
      fi
      sed 's/^aggregate=[0-9a-f]\{12\}$/aggregate=000000000000/' "$EV" > "$WORK/ev_bad.txt"
      run_in "$WORK" "$LOGF" node "$ROOT_ABS/$RP" verify --root "$WORK/src" --evidence "$WORK/ev_bad.txt" \
          --report "$ROOT_ABS/$MM_T" --declare "$ROOT_ABS/report/BUILD.md"
      chk negV1 1 FAIL '^V1_same_source .* FAIL'
      run_in "$WORK" "$LOGF" node "$ROOT_ABS/$RP" verify --root "$WORK/src" --evidence "$WORK/no_such_ev.txt" \
          --report "$ROOT_ABS/$MM_T"
      chk pair_required NZ '' '^V4_pair_required .* NOT_MEASURED'
    fi
    run_in "$WORK" "$LOGF" node "$ROOT_ABS/$RP" capture --root "$WORK/src" --out-dir "$PROJ_DIR" --stamp "$RP_STAMP"
    chk guard 3 FAIL '^REPRO'
    ckc guard_no_write "$([ ! -e "$PROJ_DIR" ] && echo 1 || echo 0)" 'wrote_into_project_dir'
  fi
fi
emit REPRO repro_check

# ---------- 6) static_check（check/ 条目自带 SKILL.md，这里只跑它的正反例对照） ----------
SC=skill/scripts/check/static_check.mjs
if need "$SC"; then
  run "$LOGF" node "$SC" --root skill/scripts/contract_gen
  chk pos 0 PASS '^T4_must_catch_bad_sample .* PASS'
  if need "$FIX/static_negative_net/tools/pull.mjs"; then
    cp -r "$FIX/static_negative_net" "$WORK/net"
    run "$LOGF" node "$SC" --root "$WORK/net"
    chk negT1 1 FAIL '^T1_no_network .* FAIL'
  fi
  if need "$FIX/static_negative_write/tools/dump.mjs"; then
    cp -r "$FIX/static_negative_write" "$WORK/write"
    run "$LOGF" node "$SC" --root "$WORK/write"
    chk negT2 1 FAIL '^T2_no_write_into_project .* FAIL'
  fi
fi
emit STATIC static_check

# ---------- 汇总 ----------
if [ "$G_BAD" -gt 0 ]; then SV='FAIL'; EX=1
elif [ "$G_NM" -gt 0 ]; then SV='NOT_MEASURED'; EX=2
else SV='PASS'; EX=0; fi
printf 'SELFTEST node=%s scripts=%d 判 %d 项 pass=%d fail=%d nm=%d %s\n' \
       "$NODE_VER" "$G_LINES" "$G_MADE" "$G_PASS" "$G_BAD" "$G_NM" "$SV"
exit "$EX"
