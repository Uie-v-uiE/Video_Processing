// build/r120_fix_dangling_cites.mjs —— 把导出器抓出的 95 条死引用按"一条一个决定"关掉。
// 为什么要有这个文件而不是手改：手改 50 处一定会漏，漏了就是把死链接交付出去；
//   而且每条决定要能被人复核（规则表在下面，一条一行，判定与命中数一起打出来）。
// 两种动作，都**不删句子**（删句子等于把"这里本该有什么"这条信息抹掉）：
//   repoint  旧名/错名 → 真件（真件必须当场 test -e 成立，否则整批拒绝）
//   mark     在名字后面就地补一个声明词（不随包/未写/示例/不存在），让"这行不是指路"变成同行可读的事实
//            —— 词表与 build/make_submission.sh 里 SKIP_RE 同源；两边不一致就是死链自检的红。
// 用法：node build/r120_fix_dangling_cites.mjs [--apply]
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = process.cwd();
const APPLY = process.argv.includes('--apply');
const P = (...a) => path.join(ROOT, ...a);

const REP = [
  ['docs/questions-for-team-p04.md', 'report/questions-for-team.md'],
  ['docs/questions-for-team-p16a.md', 'report/questions-for-team.md'],
  ['docs/questions-for-team-p16c.md', 'report/questions-for-team.md'],
  ['docs/questions-for-team-p18a.md', 'report/questions-for-team.md'],
  ['docs/questions-for-team-p19.md', 'report/questions-for-team.md'],
  ['docs/questions-for-team-p20.md', 'report/questions-for-team.md'],
  ['docs/questions-for-team-P16a.md', 'report/questions-for-team.md'],
  ['docs/questions-for-team-P17.md', 'report/questions-for-team.md'],
  ['report/07-skill-distillation.md', 'report/07-skill-distillation.md'],
  ['report/acceptance.md', 'board/acceptance.md'],
  ['build/board/project/system.bit', 'board/project/system.bit'],
];
const MARK = [
  ['docs/data-format.md', '未写'], ['docs/optimization-rounds.md', '未写'],
  ['docs/src-audit.md', '未写'], ['docs/verification-claim.md', '未写'],
  ['report/10-background.md', '未写'], ['report/20-principle.md', '未写'],
  ['report/30-partition-if.md', '未写'], ['report/novelty-claims.md', '未写'],
  ['report/prior-art-search.md', '未写'], ['board/bringup-checklist.md', '未写'],
  ['board/run/env_probe.sh', '未写'], ['board/run/flash_chain.sh', '未写'],
  ['build/runs/baselines.md', '未写'], ['src/host/run_sender.bat', '未写'],
  ['board/HANDS_ON.md', '不随包'], ['board/uart_capture.txt', '不随包'],
  ['build/ps7_init.tcl', '不随包'], ['build/c2_build_console2.txt', '不随包'],
  ['build/artifacts/20261004-2025.2.1', '不随包'],
  ['data/parts/installed_devices.txt', '不随包'],
  ['docs/walkthrough/README.md', '不随包'], ['docs/walkthrough/_progress.md', '不随包'],
  ['docs/walkthrough/_sources.md', '不随包'], ['docs/walkthrough/clocking-and-reset.md', '不随包'],
  ['docs/walkthrough/glossary.md', '不随包'], ['docs/walkthrough/system-overview.md', '不随包'],
  ['skill/scripts/_out/base/metrics.md', '不随包'], ['skill/scripts/_out/b110/metrics.md', '不随包'],
  ['build/checks/my_gate.sh', '示例'], ['report/metrics_table.md', '示例'],
  ['report/register_contract.md', '示例'], ['src/xaxidma_hw.h', '示例'],
  ['src/xintc_l.h', '示例'], ['src/arm/cortexa9/xil_cache.c', '示例'],
  ['src/rtl/zoom_ctrl.v', '不存在'], ['src/rtl/eth/axi_frame_writer_gated.v', '不存在'],
];

// 射程与导出器同源：所有 *.md（除 report/log、build/reports、report/study、docs/walkthrough）+ 两份根 README
const files = execFileSync('git', ['-c', 'core.quotePath=false', 'ls-files', '*.md'], { cwd: ROOT, encoding: 'utf8' })
  .split(/\r?\n/).filter(s => s && !/^report\/log\//.test(s) && !/^build\/reports\//.test(s))
  .concat(['README.md', 'readme.en.md'].filter(f => fs.existsSync(P(f))));
const uniq = [...new Set(files)];
const hits = {}; let changed = 0, linesTotal = 0;
for (const f of uniq) {
  const abs = P(f);
  if (!fs.existsSync(abs)) continue;
  const before = fs.readFileSync(abs, 'utf8');
  const lb = before.split('\n').length;
  let txt = before;
  for (const [o, n] of REP) {
    if (!txt.includes(o)) continue;
    if (!fs.existsSync(P(n))) { console.log(`REFUSE 改指的真件不在盘上：${n}（来自 ${o}）`); process.exit(1); }
    hits[o] = (hits[o] || 0) + txt.split(o).length - 1;
    txt = txt.split(o).join(n);
  }
  for (const [t, w] of MARK) {
    // **必须逐行看**：第一版把标记直接拼在名字后面，结果命令行变成
    //   grep -o "…" "$VP_VIVADO_BIN/../data/parts/installed_devices.txt（不随包）"
    // ——为了过关而把可跑的命令改坏，比死链接更糟（死链接至少不会让人跑出错误结果）。
    // 现在：命令行（有引号 / 有 $变量 / 以 shell 动词开头）把声明挂到**行尾的 # 注释**上，
    // 路径原样不动；散文行才就地补「（词）」。两种落点都在同一行 ⇒ 导出器的行级过滤器照样认。
    // **必须逐行看，且"这是不是命令行"要看得准**：
    //   第一版一律就地拼「（词）」⇒ README 里那条命令变成 `…installed_devices.txt（不随包）"`（坏命令比死链接更糟）；
    //   第二版把"含反引号"也算命令行 ⇒ markdown 表格行被追加行尾 `# 词`，渲染时凭空多出一格。
    // 现在：以 `|`、`>`、`-`、`*` 开头的（表格行/引文/列表）一律算散文；其余按 shell 动词或 `$(`、`"$` 判命令行。
    // 命令行把声明挂到**行尾 `# 词`**（路径原样不动），散文行就地补「（词）」——两种落点都在同一行，导出器的行级过滤器认。
    const isCmd = l => !/^\s*[|>*-]/.test(l) && (/\$\(|["']\$|\$\{/.test(l)
      || /(^|\s)(grep|sed|awk|bash|sh|node|vivado|xsdb|cp|mv|ls|cat|head|tail|test|find|echo|printf|xargs|sort)\s/.test(l));
    const lines = txt.split('\n');
    let n = 0;
    for (let i = 0; i < lines.length; i++) {
      const l = lines[i];
      if (!l.includes(t)) continue;
      if (isCmd(l)) {
        if (new RegExp(`#.*${w}`).test(l)) continue;
        lines[i] = `${l} # ${w}`; n++;
      } else {
        let out = '', j = 0, k = 0;
        while (true) {
          const p = l.indexOf(t, j);
          if (p < 0) { out += l.slice(j); break; }
          out += l.slice(j, p) + t;
          if (!l.slice(p + t.length).startsWith(`（${w}）`)) { out += `（${w}）`; k++; }
          j = p + t.length;
        }
        if (k) { lines[i] = out; n += k; }
      }
    }
    if (n) { hits[t] = (hits[t] || 0) + n; txt = lines.join('\n'); }
  }
  if (txt !== before) {
    const la = txt.split('\n').length;
    if (la !== lb) { console.log(`REFUSE ${f} 行数变了 ${lb}->${la}（本工具只允许同行加词/同长替换）`); process.exit(1); }
    changed++; linesTotal += lb;
    if (APPLY) fs.writeFileSync(abs, txt, 'utf8');
  }
}
for (const [t, w] of MARK) { if (!hits[t]) continue; console.log(`MARK ${t} 命中 ${hits[t]} 次 → 同行加“${w}”`); }
for (const [o, n] of REP) { if (!hits[o]) continue; console.log(`REPOINT ${o} → ${n} 命中 ${hits[o]} 次`); }
console.log(`${APPLY ? 'APPLY' : 'CHECK'} 扫 ${uniq.length} 份 / 待改 ${changed} 份 / 规则 ${REP.length + MARK.length} 条 判定 ${Object.values(hits).reduce((a, b) => a + b, 0)} 处 ${APPLY ? '' : '（只读，未写盘）'}`);
