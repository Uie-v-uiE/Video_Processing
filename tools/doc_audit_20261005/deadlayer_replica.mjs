#!/usr/bin/env node
// 复刻 build/make_submission.sh 死链自检的那一段抽取（单进程，不 spawn），用来在一棵已暂存的包里快速试改口。
// 三个模式各数一遍：inert（上一版挂在 sed BRE 上的空转写法）/ applied（词表真挡下）/ final（再加
//   模板槽位 `【填入：…】` 与"抽取被词表切短"两层，等同现行导出器）。
// 自证：final 的读数才是导出器会打印的"抓="；inert 用来确认这份复刻与导出器同源（同一棵暂存树上
//   它必须复现导出器当时打印的那个较大的数）。对不上就说明这份复刻不可信，别看别的。
// 用法：node deadlayer_replica.mjs <包根目录>
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.argv[2];
if (!ROOT) { console.log('用法：node deadlayer_replica.mjs <包根目录>'); process.exit(2); }
const SKIP_RE = /不随包|本地留档|不入库|未写|未落地|尚未|规划|待装配|例如|示例|假想|不存在/;
const PATH_RE = /(src|sim|build|board|data|skills?|report|docs)\/[A-Za-z0-9_.\/-]*[A-Za-z0-9_-]\.[A-Za-z0-9]{1,6}/g;
const LOGARG = /-log[ \t]+[^\s;"`]*/g;
const SLOT = /【填入：[^】]*】/g;

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out); else out.push(p);
  }
  return out;
}
const all = walk(ROOT, []).map(p => path.relative(ROOT, p).split(path.sep).join('/'));
const live = all.filter(f =>
  (f.endsWith('.md') && !f.startsWith('report/log/') && !f.startsWith('build/reports/')) ||
  (f.endsWith('.csv') && !f.startsWith('board/compare/'))
).sort();

function run({ applyExempt, stripSlot, tailResolve }) {
  const dead = [], clipped = [];
  for (const f of live) {
    const d = path.posix.dirname(f);
    let text = fs.readFileSync(path.join(ROOT, f), 'utf8').replace(LOGARG, ' ');
    if (stripSlot) text = text.replace(SLOT, ' ');
    let lines = text.split(/\r?\n/);
    if (applyExempt) lines = lines.filter(l => !SKIP_RE.test(l));
    const toks = [...new Set((lines.join('\n').match(PATH_RE) || []))].sort();
    for (const t of toks) {
      if (/[*<$]|NN/.test(t)) continue;
      if (t.endsWith('.out') || t === 'board/uart_script_capture.txt') continue;
      if (fs.existsSync(path.join(ROOT, t)) || fs.existsSync(path.join(ROOT, d, t))) continue;
      if (tailResolve) {
        const tail = all.filter(x => x.endsWith('/' + t));
        if (tail.length) { clipped.push(`${f} -> ${t} 尾部=${tail[0]}`); continue; }
      }
      dead.push(`死链 ${f} -> ${t}`);
    }
  }
  return { dead, clipped };
}
const inert = run({});
const applied = run({ applyExempt: true });
const final = run({ applyExempt: true, stripSlot: true, tailResolve: true });
console.log(`射程 扫=${live.length} 份活文档`);
console.log(`INERT(挂在 sed BRE 上的空转写法)=${inert.dead.length}`);
console.log(`APPLIED(词表真挡下)=${applied.dead.length}`);
console.log(`FINAL(再加槽位与切短两层)=${final.dead.length}  其中切短=${final.clipped.length} 条`);
for (const r of final.dead) console.log(r);
console.log('-- 切短清单 --');
for (const r of final.clipped) console.log(r);
