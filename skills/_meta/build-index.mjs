// build-index.mjs —— 生成 README.md 的索引段（索引行由**条目本身**现算，不手写）
//
// 为什么要脚本：手写清单会随目录变深静默变窄（本包自己的账）。索引双向一致是机器判据，
// 那就该由生成器保证一侧，另一侧由检查器判红。
// 用法：node _meta/build-index.mjs <本包根> [--check]
//   默认写回 README.md 的 <!-- INDEX:BEGIN --> / <!-- INDEX:END --> 之间；--check 只报差异不写。
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(process.argv[2] || '.');
const CHECK = process.argv.slice(2).includes('--check');
const SKIP_DIR = /(^|\/)(_meta|node_modules|fixtures|_out)(\/|$)/;
const BEGIN = '<!-- INDEX:BEGIN -->', END = '<!-- INDEX:END -->';
const CAT_ORDER = ['workflow', 'prompts', 'timing', 'rtl', 'runtime', 'verify', 'pitfalls', 'templates', 'scripts', 'references'];
const CAT_TITLE = {
  workflow: '工作流与顺序纪律（提示词工作流）', prompts: '提示词模板（可直接粘贴）',
  timing: '时序与约束', rtl: 'RTL 写法纪律', runtime: '片上运行时范式（加载/寄存器/DMA/带宽/判活）',
  verify: '判据与尺子', pitfalls: '踩坑清单（触发条件与排查步骤）', templates: '案例模板',
  scripts: '校验脚本（含夹具与 --self）', references: '速查表（先分派、先查哪儿）',
};

function walk(d, acc) {
  if (!fs.existsSync(d)) return acc;
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    if (!e.isDirectory()) continue;
    const p = path.join(d, e.name);
    if (SKIP_DIR.test(p.replace(/\\/g, '/'))) continue;
    if (fs.existsSync(path.join(p, 'SKILL.md'))) acc.push(p); else walk(p, acc);
  }
  return acc;
}
// "什么时候用"= 从 description 里取第一段触发条件，**不改写**（改写就又漂移了）
function whenToUse(desc) {
  const s = desc.replace(/^(用于|Use when)\s*/, '').split(/[；;。]/)[0].trim();
  return s.length > 68 ? s.slice(0, 68) + '…' : s;
}
const entries = walk(ROOT, []).map(dir => {
  const raw = fs.readFileSync(path.join(dir, 'SKILL.md'), 'utf8');
  const fm = (raw.match(/^---\r?\n([\s\S]*?)\r?\n---/) || [, ''])[1];
  const name = (fm.match(/^name:\s*(.+)$/m) || [, ''])[1].trim();
  const desc = (fm.match(/^description:\s*(.+)$/m) || [, ''])[1].trim();
  const rel = path.relative(ROOT, dir).replace(/\\/g, '/');
  const cat = rel.split('/')[0];
  return { rel, name, cat, when: whenToUse(desc), hasExtra: fs.existsSync(path.join(dir, 'references')) || fs.existsSync(path.join(dir, 'scripts')) || fs.existsSync(path.join(dir, 'templates')) };
}).sort((a, b) => (CAT_ORDER.indexOf(a.cat) - CAT_ORDER.indexOf(b.cat)) || a.rel.localeCompare(b.rel));

const lines = [];
for (const c of CAT_ORDER.filter(c => entries.some(e => e.rel.startsWith(c + '/')))) {
  lines.push(`### ${CAT_TITLE[c] || c}`, '', '| 条目 | 什么时候用 | 带工具/模板 |', '| --- | --- | --- |');
  for (const e of entries.filter(x => x.rel.startsWith(c + '/')))
    lines.push(`| \`${e.rel}/SKILL.md\` | ${e.when} | ${e.hasExtra ? '有' : '—'} |`);
  lines.push('');
}
const block = `${BEGIN}\n\n${lines.join('\n')}\n${END}`;

const readme = path.join(ROOT, 'README.md');
if (!fs.existsSync(readme)) { console.log(`INDEX 找不到 ${readme} ⇒ 先写 README 骨架（含 ${BEGIN} / ${END} 两个标记） NOT_MEASURED`); process.exit(2); }
const cur = fs.readFileSync(readme, 'utf8');
const i = cur.indexOf(BEGIN), j = cur.indexOf(END);
if (i < 0 || j < 0) { console.log(`INDEX README 里缺索引标记（${BEGIN} / ${END}） FAIL`); process.exit(1); }
const next = cur.slice(0, i) + block + cur.slice(j + END.length);
const changed = next !== cur;
console.log(`INDEX 条目=${entries.length} 类别=${new Set(entries.map(e => e.cat)).size} 索引行=${entries.length} 需改写=${changed ? 'yes' : 'no'} ${CHECK && changed ? 'FAIL' : 'PASS'}`);
if (!CHECK && changed) fs.writeFileSync(readme, next);
process.exit(CHECK && changed ? 1 : 0);
