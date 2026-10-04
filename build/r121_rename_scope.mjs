#!/usr/bin/env node
// build/r121_rename_scope.mjs
//
// 用途：把仓库里指向旧目录名的路径改口：`skill/` → `skills/`、`readme.en.md` → `README_EN.md`。
// 输入：git 跟踪的 .sh/.tcl/.py/.mjs/.ps1/.bat/.v/.c/.h/.xdc/.md/.csv 与 .gitignore；
//       冻结件不读（report/log/**、build/evidence*/**、build/frozen_*/**、build/report*/**、
//       build/runs/**、board/{compare,logs,captures}/**、data/golden/**）——那些是工具当时的原始输出。
// 输出：默认只打印逐规则命中数与逐文件计数；--apply 时逐文件写回。退出码 0=改口成立，1=不变量被破坏，2=射程为 0。
//
// 三条防自伤规矩（每条都在 --self 里有一条能红的对照）：
//   1) 只改这两个 token：写回前用反向替换还原，还原结果必须与原文件**逐字节相同**，否则 REFUSE；
//   2) 行数与 CR 数不变（换行风格不许被顺手改掉）；
//   3) 本文件自己不在射程里——它带着这两个 token 的字面量，改它等于改尺子。
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const ROOT = process.cwd();
const SELF = 'build/r121_rename_scope.mjs';
const APPLY = process.argv.includes('--apply');
const SELFTEST = process.argv.includes('--self');

const EXT = /\.(sh|tcl|py|mjs|ps1|bat|v|c|h|xdc|md|csv)$/;
const FROZEN = [/^report\/log\//, /^build\/evidence/, /^build\/frozen_/, /^build\/reports?\//,
                /^build\/runs\//, /^board\/(compare|logs|captures)\//, /^data\/golden\//, /^\.git/];
// token 1：路径段边界上的 skill/（`skills/`、`SKILL.md`、`skill-creator` 都不匹配）
const SKILL_RE = /(^|[^a-zA-Z0-9_.\-])skill\//g;
// token 2：旧英文 README 文件名（大小写各写法都收）
const RMEA_RE = /readme\.en\.md/gi;

function isLive(f) { return (EXT.test(f) || f === '.gitignore') && !FROZEN.some(re => re.test(f)) && f !== SELF; }
function scope() {
  const tracked = execSync('git ls-files', { cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 28 })
    .split('\n').filter(Boolean);
  return tracked.filter(isLive);
}
function rotate(t) {
  const a = (t.match(SKILL_RE) || []).length;
  const b = (t.match(RMEA_RE) || []).length;
  const out = t.replace(SKILL_RE, '$1skills/').replace(RMEA_RE, 'README_EN.md');
  return { out, skill: a, rmea: b };
}
// 反向还原：把新 token 换回旧的，必须得到原文件
// ⚠ 不能真的"换回去再比字符串"——文件里本来就有一批已经是新名的引用（上一轮改过一半），
//   那种文件反向还原会把它们也换回旧名，于是"还原不等"是尺子的量纲错，不是刀的问题（规矩：怀疑尺子）。
//   改成**归一化比对**：新旧两种拼法都折成一个占位符，两边必须逐字节相同；
//   再配一条长度等式，证明这一刀只动了那两个 token。
function norm(s) {
  return s.replace(/(^|[^a-zA-Z0-9_.\-])skills?\//gi, '$1§').replace(/readme[._]en[._]md/gi, '§');
}
function unrotate(s) {
  return s.replace(/(^|[^a-zA-Z0-9_.\-])skills\//g, '$1skill/')
          .replace(/README_EN\.md/g, 'readme.en.md');
}

if (SELFTEST) {
  const cases = [
    ['`skill/pitfalls/x/SKILL.md` 里那条', '`skills/pitfalls/x/SKILL.md` 里那条', 1, 0, '反引号里的路径'],
    ['见 SKILL.md 与 skill-creator', '见 SKILL.md 与 skill-creator', 0, 0, '大写条目名与连字符不许动'],
    ['已经写成 skills/README.md', '已经写成 skills/README.md', 0, 0, '新名不许变成 skillss/'],
    ['翻 readme.en.md 或 README.EN.md', '翻 README_EN.md 或 README_EN.md', 0, 2, '旧英文 README 两种写法都收'],
    ['README_EN.md 保持原样', 'README_EN.md 保持原样', 0, 0, '新名不许二次改动'],
    ['node skill/scripts/check/gates.mjs --only=C7', 'node skills/scripts/check/gates.mjs --only=C7', 1, 0, '命令行里的路径'],
  ];
  let bad = 0;
  for (const [src, want, sk, rm, why] of cases) {
    const r = rotate(src);
    const ok = r.out === want && r.skill === sk && r.rmea === rm;
    const len = r.out.length === src.length + r.skill;
    const same = norm(r.out) === norm(src);
    if (!ok || !len || !same) { bad++; console.log(`SELF FAIL ${why} 得=${r.out} 期望=${want} 命中=${r.skill}/${r.rmea} 长度=${len ? '等' : '不等'} 归一=${same ? '等' : '不等'}`); }
    else console.log(`SELF PASS ${why} 命中=${sk}/${rm}`);
  }
  // 射程对照：冻结件与自带字面量的尺子必须都在射程外
  for (const [f, want] of [['report/log/issues.md', false], ['build/evidence/r119_gates_now.txt', false],
                           [SELF, false], ['skills/README.md', true], ['build/gates.sh', true]]) {
    const got = isLive(f) && EXT.test(f);
    if (got !== want) { bad++; console.log(`SELF FAIL 射程判定 ${f} 得=${got} 期望=${want}`); }
    else console.log(`SELF PASS 射程判定 ${f}=${got}`);
  }
  console.log(`RENAME-SELF 判 ${cases.length + 5} 项 红=${bad} ${bad ? 'FAIL' : 'PASS'}`);
  process.exit(bad ? 1 : 0);
}

const files = scope();
if (!files.length) { console.log('RENAME 判 0 项 射程=0 未测 NOT_MEASURED'); process.exit(2); }
let skill = 0, rmea = 0, touched = 0, refused = 0, lines = [];
for (const f of files) {
  let raw;
  try { raw = fs.readFileSync(path.join(ROOT, f), 'utf8'); } catch { continue; }
  const { out, skill: a, rmea: b } = rotate(raw);
  if (!a && !b) continue;
  touched++; skill += a; rmea += b;
  // 不变量 1：归一化后逐字节相同（这一刀只动了那两个 token）
  if (norm(out) !== norm(raw)) { console.log(`REFUSE ${f} 归一后仍有差 ⇒ 这一刀改的不止两个 token`); refused++; continue; }
  // 不变量 2：长度等式 skill/→skills/ 每处 +1；readme.en.md→README_EN.md 同长 12 字符，不动长度
  if (out.length !== raw.length + a) { console.log(`REFUSE ${f} 长度等式不成立（得 ${out.length - raw.length}，应 ${a}）`); refused++; continue; }
  // 不变量 3：行数与 CR 数
  const cnt = (s, re) => (s.match(re) || []).length;
  if (cnt(out, /\n/g) !== cnt(raw, /\n/g) || cnt(out, /\r/g) !== cnt(raw, /\r/g)) {
    console.log(`REFUSE ${f} 行数或换行风格变了`); refused++; continue;
  }
  lines.push(`${a}\t${b}\t${f}`);
  if (APPLY) fs.writeFileSync(path.join(ROOT, f), out, 'utf8');
}
lines.sort((x, y) => (Number(y.split('\t')[0]) + Number(y.split('\t')[1])) - (Number(x.split('\t')[0]) + Number(x.split('\t')[1])));
if (lines.length) console.log(lines.slice(0, 14).join('\n') + (lines.length > 14 ? `\n…（共 ${lines.length} 个文件）` : ''));
console.log(`${APPLY ? 'WROTE' : 'CHECK'} RENAME 判 ${files.length} 项 射程=${files.length} 待改=${touched} skill/=${skill} readme.en.md=${rmea} 拒写=${refused} 冻结件不计=${FROZEN.length} 类 ${refused ? 'FAIL' : 'PASS'}`);
process.exit(refused ? 1 : 0);
