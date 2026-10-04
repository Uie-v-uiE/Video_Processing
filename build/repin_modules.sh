#!/usr/bin/env bash
# build/repin_modules.sh —— 把 `report/modules.md` 的 D5b「例化者」列**该指到哪一行**算出来（只打印，不改文件）。
#
# 为什么需要它（2026-10-03，r109）：这一轮往 `pl_video_top.v` 里挪了一段翻转拍点（净增 ~26 行），
# 该行之后所有行号整体位移 ⇒ 门禁第 20 项（`line_cite` 的 D5b）当场报了 8 条"指错"，
# 而这 8 条**不是坏引用**，是"引用是对的、行号跟着代码搬家了"。
# 规矩：改过 RTL 之后要不要重锚，取决于**这一版采不采纳**（记忆里的"re-pin only if adopted"）——
# 所以这里只算不改：采纳那一笔把打印出来的映射贴进 `report/modules.md`，不采纳就整体回退、一处都不用改。
#
# 口径：D5b 判的是"被引的那一行必须是那个模块的**例化行**"，所以正确行号 = 该实例名在
# `pl_video_top.v` 里 `u_xxx ( ... )` 的**起始行**（不是端口连接行）。找法用两条：
#   ① 先按模块名找例化语句（`模块名 #(...) 实例名 (` 或 `模块名 实例名 (`）；
#   ② 再用实例名反查（`实例名 (`），因为有的例化跨多行、模块名与实例名不同行。
# ⚠ **这张表只是候选，不是权威**：尺子 `line_cite` 的 D5b 才是判"指错"的人，
#   它今天点名的是 8 条，而本脚本报了 21 条要动 —— 差在那种"文件里同名单元出现多处"的行上
#   （例如 `osd_overlay` 这一条脚本给 915→999，位移 +84 明显不对，真位移应与全文件一致的 +26 同量级）。
#   所以采纳那一笔的正确顺序是：**先按 +26 平移动那 8 条尺子点名的行，再重跑 line_cite，
#   以它的红单为准逐条收敛**；本脚本只用来给候选，不许整表贴上去。
set -u
cd "$(dirname "$0")/.."
T=${1:-report/modules.md}
SRC=src/rtl/top/pl_video_top.v
echo "# 映射：$T 里指向 $SRC 的例化引用 —— 现在应该指到哪一行（来源：$T 的行号 + 尺子点名的模块）"
echo "# 用法：采纳那一笔按这张表改 $T 的行号，然后 node src/host/line_cite.mjs 与门禁第 20 项都要复跑"
echo
grep -nE "pl_video_top\.v:[0-9]+" "$T" | while IFS= read -r row; do
    ln=${row%%:*}
    # 这一行里的"模块名"取第一列（modules.md 的表形状：| 模块 | 例化者 file:line | ...）
    mod=$(printf '%s\n' "$row" | awk -F'|' '{gsub(/[` ]/,"",$2); print $2; exit}')   # 剥掉反引号与空格：modules.md 里模块名写成 `xxx`
    ref=$(printf '%s\n' "$row" | grep -oE "pl_video_top\.v:[0-9]+" | head -1 | cut -d: -f2)
    [ -n "$mod" ] || continue
    # ① 按模块名找：模块名后面允许有 #( … )，再跟实例名和 `(`
    hit=$(grep -nE "^[[:space:]]*${mod}[[:space:]]+(#\(|[a-zA-Z_])" "$SRC" | head -1 | cut -d: -f1)
    # ② 按实例名反查（模块名那一行不在这条语句开头时）
    if [ -z "${hit:-}" ]; then
        inst=$(grep -nE "^[[:space:]]*${mod}[[:space:]]" "$SRC" | head -1 | cut -d: -f1)
        [ -n "$inst" ] && hit=$inst
    fi
    if [ -z "${hit:-}" ]; then
        printf '  %-22s %s:%-5s -> ?? 在 %s 里找不到该模块的例化行（可能改名或退役了，先别动）\n' "$mod" "$T" "$ln" "$SRC"
    else
        flag=""; [ "$hit" != "$ref" ] && flag="  <== 需要重锚"
        printf '  %-22s %s:%-5s 旧=%-5s 新=%-5s%s\n' "$mod" "$T" "$ln" "$ref" "$hit" "$flag"
    fi
done
