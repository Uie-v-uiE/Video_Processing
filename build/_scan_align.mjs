/* 一次性检查：整份 ELF 里还有没有"非对齐的字访问"（MMU 关掉时必然发对齐异常）。
 * 用法: node build/_scan_align.mjs
 * 只看 ldr/str（无 b/h/d 后缀）配 [rN,#imm] 且 imm%4!=0 的形式；寄存器变址（[r4,r2]）
 * 静态判不出来（基址对齐性未知），所以还要人眼扫一遍反汇编 —— 这个脚本是"别把已知的一类漏掉"。 */
import { execFileSync } from 'node:child_process';
// 与 build/ps_app.mjs 用同一个变量名 PS_CC（一个东西只有一个说法），VP_CC 只是别名；
// 没设变量时假定工具链已在 PATH 上（docs/BUILD.md §1 讲的是怎么设）。
const CC = process.env.PS_CC || process.env.VP_CC || 'arm-none-eabi';
const d = execFileSync(CC + '-objdump.exe', ['-d', 'build/ps_app.elf'], { encoding: 'utf8' });
const re = /^\s*([0-9a-f]+):\s+[0-9a-f]+\s+(ldr|str)(b|h|d|sb|sh|db|)?\s+r\d+,\s*\[r\d+,\s*#(\d+)\]/;
let bad = 0, tot = 0, cur = '';
for (const line of d.split('\n')) {
  const f = /^([0-9a-f]+) <([^>]+)>:/.exec(line);
  if (f) cur = f[2];
  const m = re.exec(line);
  if (!m) continue;
  if (m[3]) continue;                 /* ldrb/ldrh/... 不算字访问 */
  tot++;
  if (Number(m[4]) % 4) { bad++; console.log(`UNALIGNED ${cur}: ${line.trim()}`); }
}
console.log(`word [rN,#imm] loads/stores scanned=${tot} unaligned=${bad}`);
if (bad) process.exit(1);
