#!/usr/bin/env node
// skill/scripts/check/retire_flat.mjs —— 旧"扁平卡"退役核对器（只读默认；--apply 才删）
//
// 背景：技能包重构前，`skill/` 根下放的是 `skill/<snake_case>.md` 形式的单文件卡（28 张）
// 加一份整包级 `skill/SKILL.md`。新结构要求"每个条目 = 一个目录 + 一份 SKILL.md（八节外壳）"。
// 删除是不可逆动作，所以本脚本先证明**映射关系与内容覆盖**，再允许 --apply：
//   C1 每张旧卡都能在一个类别目录下找到同名 kebab-case 条目目录（目录名 = 卡片名换 `-`）
//   C2 该条目里 SKILL.md 存在、八节齐全（与 gates 的 G4 同一份判据文字）
//   C3 内容覆盖：旧卡里每条"带出处的事实行"（含 `report/`、`build/`、`ISSUES`、`#<n>`、`http` 的行）
//       必须在新条目正文里找得到同一出处串（**逐条比对出处，不是比行数**）
//   C4 反向：新条目里不许出现旧卡没有的**出处**（防止迁移时编造凭据）
//   C5 `skill/SKILL.md`（整包旧外壳）与根 `skill/README.md` 的关系：README 必须存在且有一览表
//
// 输出：一条判据一行，判定 token 放最后一个字段，打印分母；缺输入一律 NOT_MEASURED。
// 退出码：0=全部可退役 1=有缺口 2=读不到输入 3=前置不满足（不在仓库根跑）
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.cwd();
const APPLY = process.argv.includes('--apply');
const HEADINGS = ['## 1. 一句话用途', '## 2. 适用场景', '## 3. 不适用 / 失效条件', '## 4. 前置条件',
  '## 5. 使用方法', '## 6. 判读与失败分叉', '## 7. 已验证的效果', '## 8. 提炼来源与边界'];
const CATS = ['prompts', 'templates', 'scripts', 'pitfalls', 'runtime', 'references'];
if (!fs.existsSync(path.join(ROOT, 'skill', 'README.md'))) {
  console.log('前置 不在仓库根或缺 skill/README.md 判 0 项 请从仓库根运行 NOT_MEASURED');
  process.exit(2);
}
const kebab = s => s.replace(/\.md$/, '').replace(/_/g, '-');
const cards = fs.readdirSync(path.join(ROOT, 'skill'))
  .filter(f => f.endsWith('.md') && f !== 'README.md' && f !== 'SKILL.md')
  .map(f => f);
const citeRe = /(report\/[^\s)`,、]+|docs\/[^\s)`,、]+|build\/[^\s)`,、]+|src\/[^\s)`,、]+|ISSUES[ #]*\d+|#\d{2,}|https?:\/\/[^\s)`,、]+)/g;
function cites(txt) { return new Set((txt.match(citeRe) || []).map(s => s.replace(/[.。，,;；:：)]+$/, ''))); }

let judged = 0;
const red = [];
const lines = [];
function say(id, detail, verdict) { judged++; lines.push(`${id} ${detail} ${verdict}`); if (verdict === 'FAIL') red.push(id); }

const report = [];
for (const card of cards) {
  const name = kebab(card);
  const cat = CATS.find(c => fs.existsSync(path.join(ROOT, 'skill', c, name)));
  const cardTxt = fs.readFileSync(path.join(ROOT, 'skill', card), 'utf8');
  const cardCites = cites(cardTxt);
  if (!cat) { report.push([card, '-', 'NO_ENTRY', `找不到条目目录 skill/*/${name}`, [...cardCites].length]); continue; }
  const sk = path.join(ROOT, 'skill', cat, name, 'SKILL.md');
  if (!fs.existsSync(sk)) { report.push([card, `${cat}/${name}`, 'NO_SKILL', '条目目录已建但 SKILL.md 未写', [...cardCites].length]); continue; }
  const newTxt = fs.readFileSync(sk, 'utf8');
  const missHead = HEADINGS.filter(h => !newTxt.includes(h));
  const newCites = cites(newTxt);
  const lost = [...cardCites].filter(c => !newCites.has(c));
  const invented = [...newCites].filter(c => !cardCites.has(c));
  report.push([card, `${cat}/${name}`, missHead.length ? 'BAD_SHELL' : (lost.length ? 'LOST_CITE' : 'OK'),
    `缺节=${missHead.length} 丢出处=${lost.length}${lost.length ? '[' + lost.slice(0, 3).join('|') + ']' : ''} 新增出处=${invented.length}${invented.length ? '[' + invented.slice(0, 3).join('|') + ']' : ''}`,
    [...cardCites].length]);
}
for (const r of report) console.log(`MAP| ${r[0]} → ${r[1]} | ${r[2]} | ${r[3]} | 旧卡出处数=${r[4]}`);

const ok = report.filter(r => r[2] === 'OK').length;
say('C1+C2', `旧卡=${cards.length} 有条目且壳齐=${report.filter(r => r[2] !== 'NO_ENTRY' && r[2] !== 'NO_SKILL').length} 可退役=${ok}`,
  ok === cards.length ? 'PASS' : 'FAIL');
say('C3', `丢出处的卡数=${report.filter(r => r[2] === 'LOST_CITE').length}`,
  report.filter(r => r[2] === 'LOST_CITE').length === 0 && ok === cards.length ? 'PASS' : 'FAIL');
say('C4', `新增无出处凭据的卡数=${report.filter(r => r[2] === 'OK' && /新增出处=[1-9]/.test(r[3])).length}（新增出处需人工判定：来自后续实测的应允许，凭空的不行）`,
  'NOT_MEASURED');
say('C5', `skill/SKILL.md 旧整包外壳 存在=${fs.existsSync(path.join(ROOT, 'skill', 'SKILL.md')) ? '是（需先确认 README 覆盖其内容才可退役）' : '否'}`,
  fs.existsSync(path.join(ROOT, 'skill', 'SKILL.md')) ? 'FAIL' : 'PASS');

if (APPLY) {
  if (red.length) { console.log(`APPLY 拒绝：仍有 ${red.length} 条红项，未删任何文件 FAIL`); process.exit(1); }
  let n = 0;
  for (const card of cards) { fs.unlinkSync(path.join(ROOT, 'skill', card)); n++; }
  console.log(`APPLY 删除旧卡 ${n} 张（映射与出处覆盖已证明） PASS`);
} else {
  console.log('（只读模式：要真删请加 --apply，且必须先全绿）');
}
console.log(`RETIRE 旧卡核对：判定 ${judged} 项 红=${red.length} ${red.length ? 'FAIL' : 'PASS'}`);
process.exit(red.length ? 1 : 0);
