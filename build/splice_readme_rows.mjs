// 用途：把首页五行表的内容从改名前的 README 原文里取回来，替换本轮重写时改窄的那五行。
// 输入输出：读 git show HEAD:README.md 与 git show HEAD:README_EN.md 里按行名匹配的行；写 README.md / README_EN.md；stdout 每行一条替换记录。
// 退出码：0 十行全部换回 1 有行名找不到（不动任何文件） 2 git 不可用。
import { execSync } from 'node:child_process';
import fs from 'node:fs';

const ROOT = process.cwd();
const run = (c) => { try { return execSync(c, { cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 28 }); } catch { return null; } };
const CN = ['全设计 setup WNS', '逐时钟 setup 余量', '保持时间', 'BRAM / LUT / FF / DSP', '功耗'];
const EN = ['Design-wide setup WNS', 'Per-clock setup slack', 'Hold time', 'BRAM / LUT / FF / DSP', 'Power'];
const pick = (txt, keys) => keys.map((k) => {
  const l = txt.split(/\r?\n/).find((x) => x.startsWith(`| ${k} |`));
  return l || null;
});
const oldCn = run('git show HEAD:README.md'), oldEn = run('git show HEAD:README_EN.md');
if (oldCn === null || oldEn === null) { console.log('SPLICE-ROWS 判 0 项 NOT_MEASURED git 读不到 HEAD 版本'); process.exit(2); }
const rowsCn = pick(oldCn, CN), rowsEn = pick(oldEn, EN);
const plan = [['README.md', CN, rowsCn], ['README_EN.md', EN, rowsEn]];
const missing = plan.flatMap(([f, keys, rows]) => rows.map((r, i) => r ? null : `${f}:${keys[i]}`).filter(Boolean));
if (missing.length) { console.log(`缺行名：${missing.join(' , ')} FAIL`); process.exit(1); }
let cmp = 0, done = 0;
for (const [f, keys, rows] of plan) {
  const cur = fs.readFileSync(f, 'utf8');
  const lines = cur.split(/\r?\n/);
  const out = lines.map((l) => {
    for (let i = 0; i < keys.length; i++) {
      if (l.startsWith(`| ${keys[i]} |`)) { cmp++; done++; console.log(`${f} 行名「${keys[i]}」换回原文（${l.length} → ${rows[i].length} 字符）PASS`); return rows[i]; }
    }
    return l;
  });
  if (out.join('\n').length <= cur.length) { console.log(`${f} 结果没变长，拒绝写入 FAIL`); process.exit(1); }
  fs.writeFileSync(f, out.join('\n'));
}
console.log(`SPLICE-ROWS 判 ${cmp} 项 换回=${done} ${done === 10 ? 'PASS' : 'FAIL'}`);
process.exit(done === 10 ? 0 : 1);
