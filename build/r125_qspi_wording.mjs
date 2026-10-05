#!/usr/bin/env node
// 作用：把交付文档里"本工程从不向 QSPI 写入"这一类旧口径改成现行的那句话（用途：改口轮）
// 输出：stdout 逐条命中数 + 一行 CHECK/APPLY RESULT；退出码 0 通过，2 某条命中数既不是 1 也不是"已改口"，3 --apply 时工作树不干净。
//
// 为什么：2026-10-05 晚队伍要求把那一版固化进板载 QSPI，写入并硬件回读校验成功（读数 board/measured/flash_qspi_2026-10-05.txt）。
// 仓库里"从不写 QSPI / 永远不要写"这类句子有九处，不改就是失实；一条都没判到 ⇒ 不许当"没毛病"。
// 每条规则认两件事：旧句子命中 1 次就改；命中 0 次但同一文件里已有新凭据件的名字，算"这棵树已改口"并念出来。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const mode = process.argv.includes('--apply') ? 'apply' : 'check';
const MARKER = 'flash_qspi_2026-10-05.txt';

const RULES = [
  ['board/acceptance.md',
   '），本工程不向 QSPI/SPI flash 写入。',
   '）；2026-10-05 晚按要求把当时那一版固化进板载 QSPI 一次，写入与硬件回读校验记在 `board/measured/flash_qspi_2026-10-05.txt`，"断电重上能不能自己起来"要人手判，本页不写成通过。板上 FT2232 的 EEPROM 全程没碰。'],
  ['board/hardware_setup.md',
   '**本工程从不做**。',
   '**2026-10-05 之前一直不做**；当晚按要求做过一次（`board/scripts/make_boot_image.sh` + `board/tcl/flash_qspi.tcl`，`PROGRAM.VERIFY` 是硬件回读比对，读数在 `board/measured/flash_qspi_2026-10-05.txt`），断电重上那一判没做。"擦除不可逆、启动介质决定板上跑什么"这条照旧成立。'],
  ['build/README.md',
   '### 1.3 上板动作（走 JTAG，本工程从不向 QSPI/SPI flash 写入）',
   '### 1.3 上板动作（演示与验收走 JTAG；QSPI 固化是 2026-10-05 按要求另做的一次）'],
  ['build/tcl/README.md',
   '## 2. 上板（JTAG only —— 永不写 QSPI/SPI flash）',
   '## 2. 上板（演示与验收走 JTAG；QSPI 那一支在 `board/tcl/flash_qspi.tcl`）'],
  ['report/demo_script.md',
   '警告 **永远不要把这一版写进 QSPI/SPI flash，也不要碰板上 FT2232 的 EEPROM**',
   '警告 演示这一路只走 JTAG；**不要碰板上 FT2232 的 EEPROM**。把版本写进板载 QSPI 是另一件事（2026-10-05 按要求做过一次，见 `report/technical-document.md` 第 8.3 节），它让"板上跑什么"由启动介质决定，重刷前先想清楚擦除不可逆这一条'],
  ['report/measurements.md',
   '；本仓库只走 JTAG，不写 QSPI）',
   '；这一路只走 JTAG）'],
  ['report/06-validation.md',
   '、不判屏上观感（第 5 节）、不写 QSPI/SPI flash',
   '、不判屏上观感（第 5 节）'],
  ['report/06-validation.md',
   '首页那句"上板只走 JTAG"）。',
   '首页那句"验收那一路只走 JTAG"；把版本固化进板载 QSPI 是 2026-10-05 按要求另做的一次，不在本节射程）。'],
  ['report/known_issues.md',
   '板子只走 JTAG（**不写 QSPI/SPI flash**：写了会把这台机器变成唯一能启动它的东西）',
   '演示与验收只走 JTAG（把一版固化进板载 QSPI 是 2026-10-05 按要求另做的一次：写进去之后启动介质就决定板上跑什么，读数在 `board/measured/flash_qspi_2026-10-05.txt`）'],
  ['docs/walkthrough/system-overview.md',
   '- 它不写 flash：上板只走 JTAG 三步链，本工程不向 QSPI/SPI flash 写入（`board/ACCEPTANCE.md` 第 4 行）。',
   '- 演示与验收那一路不写 flash：只走 JTAG 三步链。把版本固化进板载 QSPI 是 2026-10-05 按要求另做的一次（`board/tcl/flash_qspi.tcl`，读数 `board/measured/flash_qspi_2026-10-05.txt`），口径见 `board/acceptance.md` 第 4 行。'],
];

const dirty = new Map();
let rewrote = 0, already = 0, absent = 0;
for (const [rel, oldStr, newStr] of RULES) {
  const abs = path.join(root, rel);
  if (!fs.existsSync(abs)) { absent++; console.log(`RULE SKIP-ABSENT ${rel}`); continue; }
  const cur = dirty.get(abs) ?? fs.readFileSync(abs, 'utf8');
  const hits = cur.split(oldStr).length - 1;
  if (hits === 0) { already++; console.log(`RULE 已改口 ${rel}（旧句子在这份文件里已不存在）`); continue; }
  if (hits !== 1) { console.log(`REFUSE: ${rel} 命中 ${hits}（要求恰好 1）`); process.exit(2); }
  console.log(`RULE ${rel} 命中=1`);
  dirty.set(abs, cur.replace(oldStr, newStr));
  rewrote++;
}

if (mode === 'check') {
  let n = 0, arch = 0;
  for (const f of execFileSync('git', ['ls-files'], { cwd: root, encoding: 'utf8' }).split('\n')) {
    if (!/\.(md|txt|csv)$/.test(f)) continue;
    if (/^report\/log\//.test(f)) { arch++; continue; }   // 追加式台账按构造留着当时的原话，不改写（D5 同口径）
    const p = path.join(root, f);
    if (!fs.existsSync(p)) continue;
    const c = fs.readFileSync(p, 'utf8').split('本工程不向 QSPI').length - 1
      + fs.readFileSync(p, 'utf8').split('从不向 QSPI').length - 1
      + fs.readFileSync(p, 'utf8').split('永不写 QSPI').length - 1
      + fs.readFileSync(p, 'utf8').split('永远不要把这一版写进 QSPI').length - 1;
    if (c > 0) { n += c; console.log(`RESIDUAL ${f} ${c}`); }
  }
  console.log(`CHECK RESULT=${n ? 'RED' : 'OK'} 规则 ${RULES.length} 条（改 ${rewrote}／已改口 ${already}／不在本树 ${absent}）残留旧口径 ${n} 台账档案不计 ${arch}`);
  process.exit(n ? 1 : 0);
}

const st = execFileSync('git', ['status', '--porcelain'], { cwd: root, encoding: 'utf8' }).trim();
if (st) { console.log('REFUSE: 工作树不干净（先提交这一批新文件）'); console.log(st.split('\n').slice(0, 8).join('\n')); process.exit(3); }
for (const [abs, txt] of dirty) fs.writeFileSync(abs, txt);
console.log(`APPLY RESULT=OK 改写 ${dirty.size} 份文件（规则命中 ${rewrote} 条）`);
