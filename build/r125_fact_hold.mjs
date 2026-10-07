#!/usr/bin/env node
// 作用：比对"改写前（HEAD）与改写后（工作树）"两份文档里的**事实记号**，一个记号消失就判红（用途：委托改写后的验收）
// 输入：环境变量 VP_FILES=a.md,b.md 指定文件；不给就取工作树里所有已修改的 .md/.txt
// 输出：stdout 每个文件一行 5 类记号的 前→后 计数，加上消失记号清单；最后一行 RESULT
// 退出码：0 全部保住；1 有记号消失；2 用法错（比如 HEAD 里没这个文件）；3 有生成件读不到现算入口（未测）
//
// 为什么单独一支：这轮把十几份交付文档交给并行的改写任务，"读起来不像 AI"是目的，
// 但真正的红线是**数字/路径/判定词一个不许丢**（仓库规矩：数字/路径/失败项不能"整理"掉）。
// 那句话不能只靠肉眼抽查，所以要有一把能数出"少了哪个记号"的尺子。
// 这把尺子只判"消失"，不判"新增"——新增的数字要另外由 metric_recheck / line_cite 管。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CLASSES = {
  number: /(?<![0-9a-zA-Z_.])\d+(?:\.\d+)?(?![0-9a-zA-Z_.])/g,
  md5: /\b[0-9a-f]{12}\b|\b[0-9a-f]{32}\b/g,
  path: /[\w\-./@]+\.(?:v|sv|c|h|md|tcl|sh|mjs|py|xdc|bit|xsa|elf|rpt|csv|txt|json|html|bd|xci|mm)\b/g,
  cite: /:\d+(?:-\d+)?\b/g,
  verdict: /PASS|FAIL|NOT_MEASURED|DECLINE|未实测|未核实|待验证|待你补|队伍未确认|已否决|不随包|不入库|待定/g,
};
const MULTI = ['number', 'md5', 'path', 'cite', 'verdict'];   // 全部按"值 → 出现次数"比，出现两次少一次也要报

// 逐条豁免。改写轮里有两处"记号变少"是**修正**而不是丢事实，硬留着红会让这把尺子失去可信度；
// 但豁免不能变成万能出口，所以每条必须带一个 `need` 字串：改写后的文里当场数得到它，才准放行；
// 数不到就照旧红（依据消失 ⇒ 豁免自动失效，不需要再改代码）。
const 同上_r126 = 'r126 那一轮：板上那版换了（位流没动、PS 应用从 OCM 重链到 DDR），旧句子随结论一起换';
const EXEMPT = {
  'report/technical-document.md': [
    { tok: 'path:src/rtl/eth/link_monitor.v', why: '创新点那一格换成几何算子之后这条指路不再重复第二遍；§1.2 功能清单那一行仍按完整路径点名它', need: 'src/rtl/eth/link_monitor.v' },
    { tok: 'number:600', why: '那一格原写“一轮 600 帧”是轮次挂错：33.34 的 min/avg/max 出自 9000 帧 / 300 s 那一轮的 gap 统计（report/perf_report.md:205-208），而 600 帧那轮自报的是 33.3255 ms；2026-10-07 改名并把轮次写对 ⇒ 600 从本文消失是改正的结果，不是把依据弄丢', need: '9000 帧 / 300 s' },
  ],
  'report/06-validation.md': [
    { tok: 'md5:d0b07f84a068', why: '包内门禁件换成 r126 那份（同一块位流、新 ELF），身份行抄的就是那一版；旧值仍在仓库那件历史门禁里', need: 'ps_app.elf md5=57fa442a7eaf' },
  ],
  'report/repro-check.md': [
    { tok: 'number:2.7', why: 'HEAD 里该节编号错位（## 6 之下写成 ### 2.7），已改号为 6.1', need: '实际执行过的命令' },
  ],
  // ---- 2026-10-07：演示稿第 3 行那条 OSD `FPS:` 口径纠错。旧句写"板上现在这一版数的是显示场同步"，
  //      与现役 RTL 矛盾：`src/rtl/util/shown_rate.v` 在树里、`u_fpsr` 已被顶层例化，而 #128 就在
  //      第 99 批那一次采纳里（`report/40-optimization.md:75` 五行读数那一行点名 #128）⇒ 板上这一版
  //      数的就是写进屏的新帧。屏上例子由 59 改 30、指错行号 915 改 941，都是**改正**不是丢依据。
  'report/demo_script.md': [
    { tok: 'cite::59', why: '屏上例子 `1024X600 FPS:59` 换成 `FPS:30`：这一格从 #128 起数新帧，例子要与代码行为一致。尺子把屏上字串 `:59` 读成行号引用属形状撞车，但记号消失本身是改正', need: 'FPS:30' },
    { tok: 'number:915', why: '顶层 `u_fpsr` 实际在 `pl_video_top.v:941`（现量：该行就是 `shown_rate u_fpsr (`），旧文写 915 是指错行 ⇒ 少一次 915 是改行号', need: 'pl_video_top.v:941' },
    { tok: 'cite::915', why: '同上：915 换成 941', need: 'pl_video_top.v:941' },
  ],
  'report/ai_collaboration.md': [
    { tok: 'path:skills/references/symptom-router/SKILL.md', why: '同一段重复点名同一份技能两次，省掉一次；指路仍在', need: 'skills/references/symptom-router/SKILL.md' },
  ],
  'report/figures/legend.md': [
    { tok: 'path:docs/walkthrough/clocking-and-reset.md', why: '学习文档那一层已撤出仓库，活指路换成不含死路径的说法（导出器要求正文 0 条）', need: '本地学习文档《时钟与复位》那一章' },
  ],
  // 三条是"死名 → 活名"的改口：旧路径本来就读不到，换成的新路径当场在文件里、也在盘上。
  'src/host/line_cite_check.mjs': [
    { tok: 'path:skills/criterion_blind_spot.md', why: '旧包平铺名换成现役条目', need: 'skills/pitfalls/ruler-fake-greens/SKILL.md' },
  ],
  'src/host/metrics.mjs': [
    { tok: 'path:skills/metrics_gap_sum.md', why: '旧包平铺名换成现役条目', need: 'skills/scripts/metrics-collector/SKILL.md' },
  ],
  'build/r120_src_map.mjs': [
    { tok: 'path:skills/runtime/register-map/SKILL.md', why: '目录名与现役条目对齐（生成器与 report/src-map.md 同一说法）', need: 'skills/runtime/register-map-and-readback/SKILL.md' },
  ],

  // ---- r126 那一轮（app 从 OCM 0x0 重链到 DDR、QSPI 自启成立）：下面每一条都是**事实本身变了**，
  //      不是改写带走数字。旧记号少掉的同时，替代它的值必须当场在文里（`need`），否则照旧红。
  //      依据：main 台账 #409 + `build/r126_gates.txt` + `board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt`。
  'README.md': [
    { tok: 'path:build/r118_gates.txt', why: '板上那版换成了位流未变、应用重链后的 r126，身份句跟着门禁件走', need: 'build/r126_gates.txt' },
  ],
  'README_EN.md': [
    { tok: 'path:build/r118_gates.txt', why: 同上_r126, need: 'build/r126_gates.txt' },
  ],
  'board/README.md': [
    { tok: 'verdict:不入库', why: '2026-10-07 改口径：工程本体（vivado_system/ 与 vitis/）随仓库交付，六处"不入库"里两处改成"入库"，剩下四处说的是 .cache / ip_user_files / jou / log 这类噪声', need: '随仓库交付' },
  ],
  'report/70-reproduce.md': [
    { tok: 'md5:d0b07f84a068', why: '期望值换成重链后的那颗', need: '57fa442a7eaf' },
    { tok: 'path:build/r118_gates.txt', why: '对齐的门禁件换成 r126', need: 'build/r126_gates.txt' },
    { tok: 'path:build/ps_app.elf', why: '那格从"mtime 早于 main.c 的论证"换成一句话的现在态', need: '重编出来的' },
    { tok: 'path:src/ps/main.c', why: 同上_r126, need: '位流没换' },
    { tok: 'number:2026', why: '删掉的是"2026-09-29 / 2026-10-02"两个日期、补进一个 2026-10-06', need: '2026-10-06' },
    { tok: 'number:29', why: 同上_r126, need: '2026-10-06' },
    { tok: 'number:167', why: '那格不再引用台账编号（正文里 #NNN 本来就不该出现）', need: '0x00200000' },
  ],
  'report/host_guide.md': [
    { tok: 'md5:d0b07f84a068', why: '孪生工具产物那颗换成重链后的这颗', need: '57fa442a7eaf' },
  ],
  'report/repro-check.md': [
    { tok: 'md5:d0b07f84a068', why: 'B6 那格换成重链后的那颗（文末当天的原始回声仍留着）', need: '57fa442a7eaf' },
    { tok: 'path:build/provenance.md', why: '那半句"登记不同源"的指路随着结论一起换掉', need: '就是板上正在跑的这颗' },
  ],
  'src/ps/README.md': [
    { tok: 'path:build/tcl/create_project.tcl', why: '旧路径从来不存在（死链接），换成现役位置', need: 'build/create_project.tcl' },
  ],
  // r126 的死链收口：下面五条都是"指到从来没有过 / 已被剪掉的东西"的句子被改成能兑现的说法。
  //    规则同 #403/#404 那一族 —— 指路指向不存在的原件就是失实，改口不是丢事实，但替代它的依据
  //    必须当场在文里（need），否则照旧红。逐条判据：`build/make_submission.sh` 的死链自检抓=0。
  'board/raw-vs-golden.md': [
    { tok: 'path:board/captures/index.md', why: '那层抓图索引从未入库，句子换成"没有可复核件"的直说', need: '示相机' },
    { tok: 'path:board/compare/index.md', why: '示例命令里点着两层不存在的目录，照抄会报 No such file，收成一份', need: 'data/golden/[A-Za-z0-9_.-]' },
  ],
  'build/provenance.md': [
    { tok: 'path:build/artifacts/README.md', why: '那份对照表从来不存在，改指同一行下一列的脚本证据', need: 'file copy -force' },
  ],
  'report/collaboration/README.md': [
    { tok: 'path:report/collaboration/metrics.md', why: '该件已随那本入口记录一起迁出，目录清单不再列它', need: 'report/collaboration/prompts-used.md' },
    { tok: 'path:report/collaboration/redaction.md', why: '同上：脱敏台账那件也随记录迁出，清单不再列它', need: 'report/collaboration/prompts-used.md' },
  ],
};

function tally(txt) {
  const out = {};
  for (const [k, re] of Object.entries(CLASSES)) {
    const hits = txt.match(re) || [];
    out[k] = new Map();
    for (const h of hits) out[k].set(h, (out[k].get(h) || 0) + 1);
  }
  return out;
}

const wanted = process.env.VP_FILES ? process.env.VP_FILES.split(',').map(s => s.trim()).filter(Boolean) : null;
let files = wanted;
if (!files) {
  const st = execFileSync('git', ['status', '--porcelain'], { cwd: root, encoding: 'utf8' });
  files = st.split('\n').filter(l => /^ M/.test(l)).map(l => l.slice(3).trim()).filter(f => /\.(md|txt)$/.test(f));
}
if (!files.length) { console.log('RESULT=NOT_MEASURED 没有要比对的文件（工作树干净？）'); process.exit(2); }

function substrCount(hay, needle) {
  let n = 0, i = 0;
  while ((i = hay.indexOf(needle, i)) >= 0) { n++; i += needle.length; }
  return n;
}
// 生成件不比"改写前后"，比"现在与生成器是否一致"：
// report/README.md 的长度列是**关于文档自己的事实**（正文一改就漂），report/90-open-items.md
// 是未决标记的机械索引。这两份按 HEAD 差分必然一片红（330 行→328 行这类），那是有意的更新，不是丢事实；
// 所以换成"重跑生成器、结果必须与盘上那份相同 / 待改 0 格"——照样能红，而且红的是"索引漂了"。
const DERIVED = {
  'report/README.md': () => {
    const out = execFileSync('node', ['build/r125_readme_lengths.mjs'], { cwd: root, encoding: 'utf8' });
    const m = (out.match(/RESULT=\S+ 待改 (\d+) 格/) || [])[1];
    return m === '0' ? { ok: true, why: '长度列现算待改 0 格' } : { ok: false, why: `长度列失同步：待改 ${m === undefined ? '读不出' : m} 格` };
  },
  'report/90-open-items.md': () => {
    const tmp = path.join(os.tmpdir(), 'r125_openitems_probe.md');
    execFileSync('node', ['build/submit_open_items.mjs', '--write'],
      { cwd: root, encoding: 'utf8', env: { ...process.env, SUBMIT_OPEN_ITEMS_OUT: tmp } });
    const same = fs.readFileSync(tmp, 'utf8') === fs.readFileSync(path.join(root, 'report/90-open-items.md'), 'utf8');
    fs.unlinkSync(tmp);
    return same ? { ok: true, why: '与生成器输出逐字节一致' } : { ok: false, why: '与生成器现算结果不一致（表漂了，重跑 build/submit_open_items.mjs --write）' };
  },
};
// 记号少了一种读法 ≠ 记号没了：`30.0` 后面接了个中文句号、或 `1.5 MB` 并入 `1.5MB`，
// 正则的边界会把同一个字串读成不同的 token。所以先按字面数一遍，字面还在就不算消失，
// 但要把降级条数打出来——这个数本身是一条判据，异常膨胀就说明记号在漂。
let judged = 0, lost = 0, downgraded = 0, exempted = 0, idle = 0, refused = 0, derived = 0, unmeasured = 0;
for (const rel of files) {
  const abs = path.join(root, rel);
  if (!fs.existsSync(abs)) { console.log(`SKIP ${rel}（工作树里没有）`); continue; }
  if (DERIVED[rel]) {
    let v;
    try { v = DERIVED[rel](); }
    catch (e) { console.log(`DERIVED ${rel} 未测：现算的入口读不到输入（${String(e.message).slice(0, 60)}）`); unmeasured++; continue; }
    derived++;
    console.log(`DERIVED ${rel} ${v.ok ? '一致' : '漂'}：${v.why}`);
    if (!v.ok) lost++;
    continue;
  }
  let headTxt;
  try { headTxt = execFileSync('git', ['show', `HEAD:${rel}`], { cwd: root, encoding: 'utf8', maxBuffer: 64 << 20 }); }
  catch { console.log(`SKIP ${rel}（HEAD 里没有这一份：新文件不判）`); continue; }
  const now = fs.readFileSync(abs, 'utf8');
  const a = tally(headTxt), b = tally(now);
  const gone = [];
  const fired = new Set();
  const lostToks = new Set();
  let sd = 0;
  for (const k of MULTI) {
    for (const [tok, n] of a[k]) {
      const m = b[k].get(tok) || 0;
      if (m >= n) continue;
      const lit = substrCount(now, tok);
      if (lit >= n) { sd++; continue; }
      const ex = (EXEMPT[rel] || []).find(e => e.tok === `${k}:${tok}`);
      if (ex && substrCount(now, ex.need) >= 1) { fired.add(`${k}:${tok}`); exempted++; continue; }
      lostToks.add(`${k}:${tok}`);
      gone.push(`${k}:${tok} x${n}→x${m}${lit ? '(字面' + lit : ''}`);
    }
  }
  // 名单里的条目若这一轮既没生效、记号也确实没少，就是可以删掉的债（防止豁免名单只增不减）。
  const idleEx = (EXEMPT[rel] || []).filter(e => !fired.has(e.tok) && !lostToks.has(e.tok));
  for (const e of idleEx) console.log(`EXEMPT-IDLE ${rel} ${e.tok}（本轮这个记号没少，豁免可从名单删掉）`);
  idle += idleEx.length;
  // 记号少了但豁免依据读不到 ⇒ 不算 idle，也不放行，照旧红（上面已 push 进 gone）。
  const buyoff = (EXEMPT[rel] || []).filter(e => lostToks.has(e.tok) && !fired.has(e.tok));
  for (const e of buyoff) { console.log(`EXEMPT-REFUSED ${rel} ${e.tok}（依据串「${e.need}」在改写后的文里读不到，豁免失效）`); refused++; }
  const line = ['number', 'md5', 'path', 'cite', 'verdict']
    .map(k => `${k}=${a[k].size}→${b[k].size}`).join(' ');
  judged++;
  downgraded += sd;
  console.log(`HOLD ${rel} ${line} 边界降级=${sd} 豁免=${fired.size} 消失=${gone.length}${gone.length ? ' 例:' + gone.slice(0, 8).join(',') : ''}`);
  lost += gone.length;
}
console.log(`RESULT=${lost ? 'RED' : (unmeasured ? 'NOT_MEASURED' : 'OK')} 判 ${judged} 份改写件 + ${derived} 份生成件（生成件比"与生成器是否一致"）消失记号 ${lost} 个 边界降级 ${downgraded} 个 豁免生效 ${exempted} 条 豁免失效 ${refused} 条 豁免闲置 ${idle} 条 生成件未测 ${unmeasured} 份`);
process.exit(lost ? 1 : (unmeasured ? 3 : 0));
