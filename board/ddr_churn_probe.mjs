// 一次性探针：不停核，连续采样三个 DDR 地址，看哪一块正在被写入。
//
// 为什么要有它：`src/host/ddr_verify.mjs` 在读之前执行 `rst -processor`（为了躲开
// D-Cache 的旧数据），那一下正好**把要观察的写入者停掉了** —— 于是"ETH bank 完好"
// 这个结论对"SD 与 ETH 共用 bank0"这一类竞态天生不敏感。要抓竞态必须**边跑边采**。
//
// 判据（配合 video_sender --test wordid）：
//   ETH 的两个乒乓 bank 里，每个 32bit 字都等于 (word>>1) 复制两遍（低 16 位）；
//   不符合这个式子 ⇒ 这一刻这块 bank 装的是别的内容（SD 帧 / 未初始化）。
//
// 用法：node board/ddr_churn_probe.mjs [采样次数] [间隔ms]
import { execSync, execFileSync } from 'node:child_process';
import { writeFileSync, unlinkSync } from 'node:fs';

const XSDB = 'D:\\Software\\Vivado\\2025.2.1\\Vitis\\bin\\xsdb.bat';
const N = Number(process.argv[2] || 40);
const GAP = Number(process.argv[3] || 25);
const ADDRS = [0x10000040, 0x10080040, 0x10100040];   // ETH bank0 / ETH bank1 / PS 专用 bank

const tcl = [
  'catch {connect -host localhost -port 3121}',
  'targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}',
  'set vals {}',
];
for (let i = 0; i < N; i++) {
  for (const a of ADDRS) tcl.push(`lappend vals "[mrd -force 0x${a.toString(16)}]"`);
  tcl.push('after ' + GAP);
}
tcl.push('puts [join $vals "\\n"]', 'puts PROBE_DONE', '');
const f = '_churn.tcl';
writeFileSync(f, tcl.join('\n'));

let out = '';
try { out = execSync(`"${XSDB}" ${f}`, { windowsVerbatimArguments: true, maxBuffer: 1 << 24, encoding: 'utf8' }); }
catch (e) { out = String(e.stdout || '') + String(e.stderr || ''); }
finally { try { unlinkSync(f); } catch {} }

const re = /^\s*([0-9a-fA-F]{8}):\s+([0-9a-fA-F]{8})\s*$/gm;
const seq = [];
for (const m of out.matchAll(re)) seq.push([parseInt(m[1], 16), parseInt(m[2], 16)]);
if (seq.length !== N * ADDRS.length) {
  console.log(`PARSE_FAIL got=${seq.length} want=${N * ADDRS.length}`);
  console.log(out.split('\n').slice(0, 12).join('\n'));
  process.exit(1);
}

function want(a) {                       // wordid 图案在该地址上的期望 u32（偏移按 bank 内算）
  const w = (a & 0x000fffff) >> 2;       // 0x10080040 与 0x10000040 在各自 bank 内的同一个位置
  const v = (w >> 1) & 0xffff;
  return (v | (v << 16)) >>> 0;
}
for (const a of ADDRS) {
  const s = seq.filter(x => x[0] === a).map(x => x[1]);
  const uniq = new Map();
  for (const v of s) uniq.set(v, (uniq.get(v) || 0) + 1);
  const w = want(a);
  const ok = s.filter(v => v === w).length;
  const top = [...uniq.entries()].sort((x, y) => y[1] - x[1]).slice(0, 3)
    .map(([v, c]) => `${v.toString(16)}x${c}`).join(' ');
  console.log(`0x${a.toString(16)}  n=${s.length}  distinct=${String(uniq.size).padStart(3)}  wordid_clean=${ok}/${s.length}` +
    `  ${uniq.size > 1 ? 'CHURNING(有写入)' : 'STATIC'}  top=[${top}]`);
}
