#!/usr/bin/env node
/**
 * skill/scripts/check/gen_index.mjs — 从目录实际内容生成 skill/README.md 的一览表
 *
 * 用法：
 *   node skill/scripts/check/gen_index.mjs            # 写入（只替换 BEGIN/END 之间的块）
 *   node skill/scripts/check/gen_index.mjs --check    # 只比较，不写；不一致 exit 1
 * 退出码：0=一致/写成功 1=不一致或有红 3=前置不满足（找不到 skill/ 或锚点）
 *
 * 为什么必须由脚本生成：一览表手维护过一次就会漂（G7 就是抓这个的）。
 * 打印分母（判 N 项）与三态，读不到输入一律 NOT_MEASURED。
 */
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(process.cwd());
const SKILL = path.join(ROOT, 'skill');
const README = path.join(SKILL, 'README.md');
const BEGIN = '<!-- BEGIN GENERATED INDEX -->';
const END = '<!-- END GENERATED INDEX -->';
const check = process.argv.includes('--check');

const CATS = ['prompts', 'templates', 'scripts', 'pitfalls', 'runtime', 'references'];
if (!fs.existsSync(SKILL)) { console.log('gen_index 前置不满足：找不到 skill/ NOT_MEASURED'); process.exit(3); }

const entries = [];
for (const c of CATS) {
  const base = path.join(SKILL, c);
  if (!fs.existsSync(base)) continue;
  for (const e of fs.readdirSync(base, { withFileTypes: true })) {
    if (!e.isDirectory() || e.name.startsWith('_')) continue;
    const f = path.join(base, e.name, 'SKILL.md');
    if (!fs.existsSync(f)) continue;
    entries.push({ cat: c, dir: `${c}/${e.name}`, file: f });
  }
}
// skill/ 根上的既有单目录条目（如 zynq-video-rtl-debug/）也算条目
for (const e of fs.readdirSync(SKILL, { withFileTypes: true })) {
  if (!e.isDirectory() || e.name.startsWith('_') || CATS.includes(e.name)) continue;
  const f = path.join(SKILL, e.name, 'SKILL.md');
  if (fs.existsSync(f)) entries.push({ cat: 'entry', dir: e.name, file: f });
}

function section(txt, want) {
  const m = txt.split('\n');
  let out = [], on = false;
  for (const l of m) {
    if (/^## /.test(l)) { on = l.startsWith(want); if (on) continue; }
    else if (on) out.push(l);
  }
  return out.join('\n').trim();
}
function firstItem(s) {
  const m = s.split('\n').map(l => l.replace(/^[-*]\s+/, '').trim()).filter(Boolean);
  return m.length ? m[0] : '';
}
function clip(s, n) { s = s.replace(/\|/g, '/').replace(/\s+/g, ' ').trim(); return s.length > n ? s.slice(0, n - 1) + '…' : s; }
function oneLiner(txt) {
  const s = section(txt, '## 1.');
  if (s) return clip(s.split('\n')[0], 40);
  const m = txt.match(/^## 1\..*\n+([^\n]+)/m);
  return m ? clip(m[1], 40) : '';
}

const recordsDir = path.join(SKILL, 'evals', 'records');
const records = fs.existsSync(recordsDir) ? fs.readdirSync(recordsDir).filter(f => f.endsWith('.md')) : [];

function statusOf(dir, txt) {
  const key = dir.replace(/\//g, '-');
  const has = records.some(r => r.startsWith(key));
  const s7 = section(txt, '## 7.');
  if (has && !/【待验证】|【未实测】/.test(s7)) return `已复跑(见 evals/records/${records.find(r => r.startsWith(key))})`;
  if (/【待验证】|【未实测】|【未核实】/.test(s7)) return '待验证';
  return has ? '已复跑(见 evals/records/' + key + ')' : '待验证';
}

const rows = [];
for (const e of entries.sort((a, b) => a.dir.localeCompare(b.dir))) {
  const txt = fs.readFileSync(e.file, 'utf8');
  rows.push(`| \`skill/${e.dir}/SKILL.md\` | ${e.cat} | ${oneLiner(txt) || '【未填】'} | ` +
            `${clip(firstItem(section(txt, '## 2.')), 34) || '【未填】'} | ` +
            `${clip(firstItem(section(txt, '## 3.')), 34) || '【未填】'} | ${statusOf(e.dir, txt)} |`);
}
const block = [BEGIN,
  '',
  `<!-- 由 skill/scripts/check/gen_index.mjs 生成，共 ${rows.length} 条；条目增删后必须重跑，不要手抄 -->`,
  '',
  '| 条目路径 | 类别 | 一句话用途 | 适用场景关键词 | 失效条件关键词 | 验证状态 |',
  '| --- | --- | --- | --- | --- | --- |',
  ...rows,
  '',
  END].join('\n');

if (!fs.existsSync(README)) {
  fs.writeFileSync(README, `# skill/ 技能包总索引\n\n${block}\n`, 'utf8');
  console.log(`gen_index 新建 README.md 条目=${rows.length} 判 ${rows.length} 项 PASS`);
  process.exit(0);
}
const cur = fs.readFileSync(README, 'utf8');
let i = cur.indexOf(BEGIN), j = cur.indexOf(END);
if (i < 0 || j < 0) {
  // 锚点还没有：不覆盖任何人写的正文，把生成区追加到文件末尾，并打印这件事
  i = cur.length; j = cur.length - 1;
  var appended = true;
}
const next = (appended ? cur + '\n\n## 一览表（生成区）\n\n' : cur.slice(0, i)) + block + (appended ? '\n' : cur.slice(j + END.length));
if (check) {
  const same = !appended && cur === next;
  // 审计指出的洞：条目=0 时生成块也能与 README 逐字相同 ⇒ 原来判 PASS + exit 0。
  // "空表"不等于"索引一致"，这条本文件自己在 SKILL.md 里也写过不算通过。
  const verdict = rows.length === 0 ? 'NOT_MEASURED' : (appended ? 'FAIL' : (same ? 'PASS' : 'FAIL'));
  console.log(`gen_index --check 条目=${rows.length} 判 ${rows.length} 项 一致=${same ? 'yes' : 'no'} ` + verdict);
  process.exit(verdict === 'PASS' ? 0 : verdict === 'NOT_MEASURED' ? 2 : 1);
}
fs.writeFileSync(README, next, 'utf8');
const after = fs.readFileSync(README, 'utf8');
console.log(`gen_index 写入 条目=${rows.length} 行数 ${cur.split('\n').length}->${after.split('\n').length} 判 ${rows.length} 项 ` +
            (after.includes(END) && after.length >= cur.length ? 'PASS' : 'FAIL'));
process.exit(after.includes(END) && after.length >= cur.length ? 0 : 1);
