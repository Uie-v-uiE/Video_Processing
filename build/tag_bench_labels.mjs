// tag_bench_labels.mjs —— #55 的第一步（也是最小可用版）：给每一条带非 ASCII 的
// $display/$monitor/$write **在格式串开头插一个 ASCII 锚点 `[文件名:行号]`**。
//
// 为什么是锚点而不是把中文全翻译成英文：xsim 的日志里中文会不会坏是**按行随机**的
//   （同一次运行里有一行中文完好、下一行全是问号），所以只要中文是"含义的唯一载体"，
//   判据就有读不出来的风险。但**数字一直是清楚的**，缺的只是"这是哪一条"。
//   一个 `[tb_v89_align.v:312]` 让人三步定位到源码里那句中文，比把 190 条中文硬翻成英文更不容易翻错
//   —— 翻译错了是**判据变味**，比读不出来更糟。剩下 55 条 FAIL/PASS 行若要英文化，
//   得连着"这条到底在判什么"一起重写，那是另一件事（任务 #55 里记着）。
//
// ⚠ 两件事必须知道：
//  1) 锚点必须**成对维护**：`$display` 不在行首的那些（`if (e==0) $display("PASS ...`）也要打，
//     第一版只认行首 ⇒ 漏了 tb_osd_lines.v:393 那条 PASS。所以匹配的是"$display( 出现"，不限行首。
//  2) **行号会漂移**：往文件里插了新行，旧锚点就指向别处。所以有 `--refresh`：
//     把每一处 `[xxx.v:123]` 重写成当前真实行号。改了台架文件就跑一次它。
//
// 用法：node build/tag_bench_labels.mjs [--dry] [--refresh]     （只改 sim/*.v，不碰 ku5p/）
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const DRY = process.argv.includes('--dry');
const REFRESH = process.argv.includes('--refresh');
const dir = 'sim';
const RE = /(?:\$display|\$monitor|\$write)\s*\(\s*"/;
const ANCH = /\[[\w.]+\.v:\d+\]\s+/;
let nfile = 0, nins = 0, nfix = 0;

for (const f of readdirSync(dir).filter((s) => s.endsWith('.v'))) {
  const p = join(dir, f);
  // 用 latin1 读写：字节进字节出，中文与 CRLF 一个都不动，只在格式串开头插 ASCII。
  const lines = readFileSync(p, 'latin1').split('\n');
  let ins = 0, fix = 0;
  const out = lines.map((ln, i) => {
    if (!RE.test(ln)) return ln;
    if (!/[^\x00-\x7F]/.test(ln)) return ln;            // 纯 ASCII 的打印不需要锚点
    const want = `[${f}:${i + 1}] `;
    const got = ANCH.exec(ln);
    if (got) {
      if (!REFRESH || got[0] === want) return ln;
      fix++;
      return ln.replace(ANCH, want);
    }
    ins++;
    return ln.replace(RE, (m) => m + want);
  });
  if (ins || fix) {
    nfile++; nins += ins; nfix += fix;
    console.log(`ins=${ins} refresh=${fix}  ${p}`);
    if (!DRY) writeFileSync(p, out.join('\n'), 'latin1');
  }
}
console.log(`${DRY ? '[DRY]' : 'done'} ${nfile} 个文件：新插 ${nins} 条、刷新 ${nfix} 条行号`);
