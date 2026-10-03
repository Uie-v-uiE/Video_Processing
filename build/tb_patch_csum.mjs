// 一次性补丁脚本（r112 台架的三处小修）：把 A 腿抓取的门与 K4 的判据形状改对。
// 用字面串替换、不用正则，避开 shell/node 的转义坑。
import { readFileSync, writeFileSync } from 'node:fs';
const p = 'sim/tb_v112_ip_csum.v';
let s = readFileSync(p, 'utf8');
const REPS = [
  ['integer errors = 0, i, vec, maxsum = 0, gotsum = 0, exp16 = 0, got = 0;',
   'integer errors = 0, i, vec, maxsum = 0, gotsum = 0, exp16 = 0, got = 0, captured = 0, bigfold = 0;'],
  ['            checked = 1\'b0; gotsum = 0;',
   '            checked = 1\'b0; gotsum = 0; captured = 0;'],
  ['                            if (gotsum != 0 && u_dut.ip_head[2][15:0] !== 16\'d0) begin',
   '                            if (captured == 1 && u_dut.ip_head[2][15:0] !== 16\'d0) begin'],
  ['                if (fold1 > 65535) k4ok = 1;\n                else if (maxsum > 65535) k4ok = 0;',
   '                if (fold1 > 65535) bigfold = 1;'],
  ['expect_line("K4 大和必须靠第二次折叠才回到 16 位（折叠次序没被简化掉）", k4ok == 1);',
   'expect_line("K4 至少一个矢量的和要靠第二次折叠才回到 16 位", bigfold == 1);'],
];
let bad = 0;
for (const [a, b] of REPS) {
  const n = s.split(a).length - 1;
  if (n !== 1) { console.log('MISS x' + n + ' :: ' + a.slice(0, 56)); bad++; continue; }
  s = s.split(a).join(b);
  console.log('OK   :: ' + a.slice(0, 56));
}
if (bad === 0) { writeFileSync(p, s); console.log('WROTE ' + p); }
else console.log('NO-WRITE 有替换没命中');
process.exit(bad ? 1 : 0);
