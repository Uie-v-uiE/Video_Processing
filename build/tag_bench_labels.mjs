// tag_bench_labels.mjs —— #55 的第一步（也是最小可用的一步）：给每一条带非 ASCII 的
// $display/$monitor **在字符串开头插一个 ASCII 锚点 `[<文件名>:<行号>]`**。
//
// 为什么是锚点而不是把中文全翻译成英文：xsim 的日志里中文会不会坏是**按行随机**的
//   （同一次运行里有一行中文完好、下一行全是问号，见 report/ISSUES.md #75 与 task #55 的记录），
//   所以只要中文是"含义的唯一载体"，判据就有读不出来的风险。但**数字一直是清楚的**，
//   缺的只是"这是哪一条"。一个 `[tb_v89_align.v:312]` 让人三步之内定位到源码里那句中文，
//   比把 190 条中文硬翻成英文更不容易翻错（翻译错了是**判据变味**，比读不出来更糟）。
//   剩下那 55 条 FAIL/PASS 行如果要英文化，应当连着"这条到底在判什么"一起重写，那是另一件事。
//
// 用法：node build/tag_bench_labels.mjs [--dry]      （只改 sim/*.v，不碰 ku5p/）
// 幂等：已经有锚点的行不再插第二次。
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const DRY = process.argv.includes('--dry');
const dir = 'sim';
// 锚点放在**格式串开头**，所以匹配要允许 `$display` 出现在行中（`if (e==0) $display("PASS ...` 这种）；
// 只认"行首的 $display"会漏掉一半的判据行 —— 第一版就漏了 tb_osd_lines.v:393 那条 PASS。
const RE = /(?:\$display|\$monitor|\$write)\s*\(\s*"/;
let nfile = 0, nline = 0;

for (const f of readdirSync(dir).filter((s) => s.endsWith('.v'))) {
  const p = join(dir, f);
  // 用 latin1 读写：字节进字节出，中文与 CRLF 一个都不动，只在前引号后面插 ASCII。
  const src = readFileSync(p, 'latin1');
  const lines = src.split('\n');
  let touched = 0;
  const out = lines.map((ln, i) => {
    const m = RE.exec(ln);
    if (!m) return ln;
    if (!/[^\x00-\x7F]/.test(ln)) return ln;              // 纯 ASCII 的打印不需要锚点
    if (ln.includes(`[${f}:`)) return ln;                  // 幂等
    touched++;
    return ln.replace(RE, (mm) => mm + `[${f}:${i + 1}] `);
  });
  if (touched) {
    nfile++; nline += touched;
    console.log(`${String(touched).padStart(3)}  ${p}`);
    if (!DRY) writeFileSync(p, out.join('\n'), 'latin1');
  }
}
console.log(`${DRY ? '[DRY] 将改' : '已改'} ${nfile} 个文件、${nline} 条打印`);
