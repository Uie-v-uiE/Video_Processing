#!/usr/bin/env node
// build/r125_elf_md5_rotate.mjs —— 把六份交付文档里"重建那颗 ELF 的 md5"从抄死的数字改成指路
//
// 作用：把交付文档里抄死的"重建产物 md5"换成指路（输出：stdout 逐条命中数 + 一行 CHECK/APPLY RESULT）
// 退出码：0 通过；2 某条规则命中数不是 1；3 --apply 时工作树不干净。
//
// 为什么：那条 md5 是 2026-10-05 上午量的（4ed58740785c…），之后 src/ps/main.c 删掉一条永远走不到的
// not_wired("bilin") 分支（0bc578d），今晚用 board/vitis_platform 副本重链得到的是另一颗（c0f9f79a…）。
// 把易变的数字抄在六处正文里，下次重编又会全部失实；数字只留在证据件 build/evidence/1005_ps_app_rebuild.txt。
//
// 用法：node build/r125_elf_md5_rotate.mjs --check   （只读，打印每条命中数）
//       node build/r125_elf_md5_rotate.mjs --apply   （git 工作树须干净；逐条命中数必须为 1，否则整体不写）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const mode = process.argv.includes('--apply') ? 'apply' : 'check';

const OLD = '4ed58740785c';
const RULES = [
  ['board/README.md',
   '重编出来的 ELF 是另一颗：`4ed58740785c…`（`build/evidence/1005_ps_app_rebuild.txt`），它没上过板。',
   '重编出来的 ELF 是另一颗，它没上过板；两颗的 md5 与 `.text`/`.rodata` 大小记在 `build/evidence/1005_ps_app_rebuild.txt`。'],
  ['report/60-failure-analysis.md',
   '记录重建产物 `4ed58740785c158c89c0fbc80a0e9d39`（未采纳，工作树已还原成在板那颗 `d0b07f84a068…`）',
   '记录重建产物（未采纳，工作树已还原成在板那颗 `d0b07f84a068…`）'],
  ['report/60-failure-analysis.md',
   '重建产物 md5 `4ed58740785c158c89c0fbc80a0e9d39`）。',
   '重建产物与在板那颗的两组 md5/section 都在该件里）。'],
  ['report/figures/legend.md',
   '重建件 md5 `4ed58740785c…`）',
   '重建件与在板那颗的 md5/section 差异记在该件里）'],
  ['report/known-limitations.md',
   '重建产物的 md5 是 `4ed58740785c…`，与随包并在板上跑过验收的那颗 `d0b07f84a068…` **不同**',
   '重跑 `node build/ps_app.mjs` 得到的那颗，与随包并在板上跑过验收的那颗 `d0b07f84a068…` **不同**（差在源码比入库 ELF 新；实测数字只记在 `build/evidence/1005_ps_app_rebuild.txt`）'],
  ['report/known_issues.md',
   '但重建那颗（md5 `4ed58740785c158c89c0fbc80a0e9d39`）与随包/在板那颗',
   '但重建那颗（md5 见 `build/evidence/1005_ps_app_rebuild.txt`）与随包/在板那颗'],
  ['src/ps/README.md',
   '重建出来那颗 md5 = `4ed58740785c158c89c0fbc80a0e9d39`，**没有**替换随包这颗',
   '重建出来那颗与随包这颗不同（两颗的 md5 与 section 大小记在 `build/evidence/1005_ps_app_rebuild.txt`），**没有**替换随包这颗'],
];

let dirty = new Map();
for (const [rel, oldStr, newStr] of RULES) {
  const abs = path.join(root, rel);
  if (!fs.existsSync(abs)) { console.log(`RULE SKIP-ABSENT ${rel}`); continue; }
  const txt = fs.readFileSync(abs, 'utf8');
  const hits = txt.split(oldStr).length - 1;
  console.log(`RULE ${rel} 命中=${hits}`);
  if (hits !== 1) { console.log(`REFUSE: ${rel} 命中 ${hits}（要求恰好 1）`); process.exit(2); }
  if (!dirty.has(abs)) dirty.set(abs, txt);
  dirty.set(abs, dirty.get(abs).replace(oldStr, newStr));
}

const applied = [...dirty.keys()].length;
if (mode === 'check') {
  let n = 0, files = 0;
  for (const f of execFileSync('git', ['ls-files'], { cwd: root, encoding: 'utf8' }).split('\n')) {
    if (!f.endsWith('.md') && !f.endsWith('.txt')) continue;
    const p = path.join(root, f);
    if (!fs.existsSync(p)) continue;
    const c = fs.readFileSync(p, 'utf8').split(OLD).length - 1;
    if (c > 0) { n += c; files++; console.log(`RESIDUAL ${f} ${c}`); }
  }
  console.log(`CHECK RESULT=OK 规则 ${RULES.length} 条 待改文件 ${applied} 份 全树残留 ${n}（分布在 ${files} 份文件）`);
  process.exit(0);
}

const st = execFileSync('git', ['status', '--porcelain'], { cwd: root, encoding: 'utf8' }).trim();
if (st) { console.log('REFUSE: 工作树不干净，先提交或还原'); console.log(st.split('\n').slice(0, 8).join('\n')); process.exit(3); }
for (const [abs, txt] of dirty) fs.writeFileSync(abs, txt);
console.log(`APPLY RESULT=OK 改写 ${applied} 份文件`);
