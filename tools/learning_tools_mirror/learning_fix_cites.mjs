// 一次性修 LEARNING/*.md 里的死指路：路径写错的改成盘上真实存在的那份，
// 盘上根本没有的改成明确写"未随包"的白话（不留一个读者打不开的路径）。
// 用法：node build/learning_fix_cites.mjs --check | --apply
import fs from 'node:fs';
import path from 'node:path';

const APPLY = process.argv.includes('--apply');
const ROOT = 'LEARNING';

// [文件, 旧串, 新串, 为什么]
const EDITS = [
  ['01-foundations-device-and-architecture.md', 'src/host/HOST_GUIDE.md', 'report/host_guide.md', '上位机指南在 report/ 下，且是小写名'],
  ['02-ingress-ethernet-and-framebuffer.md', 'sim/run_sim.tcl', 'build/sim/run_sim.tcl', '跑台架的总入口在 build/sim/ 下'],
  ['03-geometry-effects-osd-and-hdmi.md', 'sim/run_one.sh', 'build/sim/run_one.sh', '单支台架入口在 build/sim/ 下'],
  ['03-geometry-effects-osd-and-hdmi.md', 'build/pipe_len_check.mjs', 'src/host/pipe_len_check.mjs', '静态尺子都在 src/host/ 下'],
  ['05a-constraints-clocks-and-cdc.md', 'build/evidence/r119_xdc_loads_probe2.txt', 'build/evidence/r119_xdc_loads_probe3.txt', '盘上只有 probe3 与 probe4_pinclk 两份'],
  ['06a-board-work-and-delivery-engineering.md', 'build/report.txt', 'build/report/', 'C4 判的是那个目录，不是叫 report.txt 的文件'],
  ['06a-board-work-and-delivery-engineering.md', 'build/evidence/r116_board/board_now.txt', 'build/evidence/r118_board/board_now.txt', '盘上是 r118 那一份'],
  ['06b-experience-summary-and-number-index.md', 'report/log/issues.md:13419', 'report/log/issues.md:13418', '13419 是空行，那句话在 13418'],
  // —— 以下这些名字在整棵树里都找不到（历史文档点名、但件没留下）：改成白话，不假装读者能打开
  ['02-ingress-ethernet-and-framebuffer.md', '`build/evidence/r113_dead_reset_scan.txt`', '当时那份死复位扫描输出没随包留下', '全盘 find 无此件'],
  ['03-geometry-effects-osd-and-hdmi.md', '`build/r80_build2.log`', '那份 r80 的构建日志没随包留下', '全盘 find 无此件'],
  ['05a-constraints-clocks-and-cdc.md', '`build/scan_async_reg_coverage.py`', '那把 ASYNC_REG 覆盖率扫描尺子没随包留下', '全盘 find 无此件'],
  ['05a-constraints-clocks-and-cdc.md', '`build/evidence/r113_async_reg_scan.txt`', '它的扫描输出也没随包留下', '全盘 find 无此件'],
  ['06a-board-work-and-delivery-engineering.md', '`board/measured/qspi_serial_live.txt`', '那份 QSPI 烧写期间的串口留档没随包留下', '全盘 find 无此件'],
  ['06b-experience-summary-and-number-index.md', 'build/script_header_stamp.mjs', '那把批量盖文件头的脚本（未随包）', '全盘 find 无此件'],
];

let bad = 0, fired = 0, already = 0;
const staged = new Map();
for (const [f, oldS, newS, why] of EDITS) {
  const p = path.join(ROOT, f);
  let t = staged.has(p) ? staged.get(p) : fs.readFileSync(p, 'utf8');
  const nOld = t.split(oldS).length - 1;
  const nOldOutsideNew = t.split(newS).join('').split(oldS).length - 1;
  if (nOld === 1 && nOldOutsideNew === 1) { t = t.split(oldS).join(newS); fired++; }
  else if (nOldOutsideNew === 0 && t.split(newS).length - 1 === 1) { already++; }
  else { bad++; console.log(`BAD  ${f}  旧串命中 ${nOld} 次 / 新串命中 ${t.split(newS).length - 1} 次（要 1/1 或 0/1）：${oldS.slice(0, 48)} —— ${why}`); }
  staged.set(p, t);
}
console.log(`LEARNING 死指路修正  规则=${EDITS.length}  命中=${fired}  已改口=${already}  不命中=${bad}  涉及文件=${staged.size}`);
if (fired + already + bad !== EDITS.length) { console.log('REFUSE 判定条数不等于规则条数'); process.exit(1); }
if (bad) { console.log('REFUSE 有不命中的规则，未写盘'); process.exit(1); }
if (!APPLY) { console.log('（--check：只判不改。要落盘加 --apply）'); process.exit(0); }
for (const [p, t] of staged) fs.writeFileSync(p, t, 'utf8');
console.log(`已写盘 ${staged.size} 份`);
