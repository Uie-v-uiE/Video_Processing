#!/usr/bin/env node
// 作用：比对"改写前（HEAD）与改写后（工作树）"两份文档里的**事实记号**，一个记号消失就判红（用途：委托改写后的验收）
// 输入：环境变量 VP_FILES=a.md,b.md 指定文件；不给就取工作树里所有已修改的 .md/.txt
// 输出：stdout 每个文件一行 5 类记号的 前→后 计数，加上消失记号清单；最后一行 RESULT
// 退出码：0 全部保住；1 有记号消失；2 用法错（比如 HEAD 里没这个文件）
//
// 为什么单独一支：这轮把十几份交付文档交给并行的改写任务，"读起来不像 AI"是目的，
// 但真正的红线是**数字/路径/判定词一个不许丢**（仓库规矩：数字/路径/失败项不能"整理"掉）。
// 那句话不能只靠肉眼抽查，所以要有一把能数出"少了哪个记号"的尺子。
// 这把尺子只判"消失"，不判"新增"——新增的数字要另外由 metric_recheck / line_cite 管。
import fs from 'node:fs';
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

let judged = 0, lost = 0;
for (const rel of files) {
  const abs = path.join(root, rel);
  if (!fs.existsSync(abs)) { console.log(`SKIP ${rel}（工作树里没有）`); continue; }
  let headTxt;
  try { headTxt = execFileSync('git', ['show', `HEAD:${rel}`], { cwd: root, encoding: 'utf8', maxBuffer: 64 << 20 }); }
  catch { console.log(`SKIP ${rel}（HEAD 里没有这一份：新文件不判）`); continue; }
  const now = fs.readFileSync(abs, 'utf8');
  const a = tally(headTxt), b = tally(now);
  const gone = [];
  for (const k of MULTI) {
    for (const [tok, n] of a[k]) {
      const m = b[k].get(tok) || 0;
      if (m < n) gone.push(`${k}:${tok} x${n}→x${m}`);
    }
  }
  const line = ['number', 'md5', 'path', 'cite', 'verdict']
    .map(k => `${k}=${a[k].size}→${b[k].size}`).join(' ');
  judged++;
  console.log(`HOLD ${rel} ${line} 消失=${gone.length}${gone.length ? ' 例:' + gone.slice(0, 8).join(',') : ''}`);
  lost += gone.length;
}
console.log(`RESULT=${lost ? 'RED' : 'OK'} 判 ${judged} 份文件 消失记号 ${lost} 个`);
process.exit(lost ? 1 : 0);
