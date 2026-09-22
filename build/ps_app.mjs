#!/usr/bin/env node
/*
 * build/ps_app.mjs —— 不用 Vitis IDE，直接把 src/ps 编成可在板上跑的 ELF。
 *
 * 为什么要脚本化：交付要求"从零复现"，而"在 IDE 里手工点 New Platform / New Application"
 * 不属于能复现的步骤。另外这个 app 只需要 PS 侧的 xparameters（UART/SD/DDR/GLOBALTIMER），
 * PL 侧一律走 literal 地址（0x41200000 / 0x10000000），所以 BSP 只要 PS7 配置一致就能用。
 *
 * 需要的输入（都能用环境变量覆盖）：
 *   PS_CC   arm-none-eabi-gcc.exe 的路径（默认取 2025.2.1 的安装位置）
 *   PS_BSP  一个已经 generate 过的 zynq 平台 BSP 目录（里面有 include/ 和 lib/libxil.a）
 *
 *   node build/ps_app.mjs [--clean]
 *
 * 没有现成平台时怎么得到一个（一次性，手工，之后就能一直用本脚本）：
 *   Vitis → New → Platform → 选 build/system.xsa → BSP 勾 uartps/xsdps/xgpiops → Generate。
 *   把生成目录里的 standalone_ps7_cortexa9_0/bsp 指给 PS_BSP 即可。
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/(\w:)/, '$1')), '..');
const arg = (n, d) => { const i = process.argv.indexOf('--' + n); return i < 0 ? d : process.argv[i + 1]; };

const CC  = process.env.PS_CC  || 'D:/Software/Vivado/2025.2.1/Vitis/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe';
const BSP = process.env.PS_BSP || 'D:/Xilinx/Prj/project_handoff/vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp';
const SRC = path.join(root, 'src', 'ps');
const OBJ = path.join(root, 'build', 'ps_obj');
const OUT = path.join(root, 'build', 'ps_app.elf');

const need = (p, what) => {
  if (!fs.existsSync(p)) {
    console.log(`FATAL: ${what} 不存在：${p}`);
    console.log('  用 PS_CC / PS_BSP 环境变量指到实际位置，见本文件头部的注释。');
    process.exit(2);
  }
};
need(CC, 'arm-none-eabi-gcc');
need(path.join(BSP, 'include', 'xparameters.h'), 'BSP xparameters.h');
need(path.join(BSP, 'lib', 'libxil.a'), 'BSP libxil.a');

const CFLAGS = ['-mcpu=cortex-a9', '-mfpu=vfpv3', '-mfloat-abi=hard', '-DSDT',
                '-ffunction-sections', '-fdata-sections', '-Wall', '-Wextra', '-Wno-unused-parameter',
                '-O2', `-I${path.join(BSP, 'include')}`, `-specs=${path.join(BSP, 'Xilinx.spec')}`];

if (process.argv.includes('--clean') && fs.existsSync(OBJ)) fs.rmSync(OBJ, { recursive: true, force: true });
fs.mkdirSync(OBJ, { recursive: true });

const srcs = fs.readdirSync(SRC).filter(f => f.endsWith('.c')).sort();
if (!srcs.length) { console.log('FATAL: src/ps 下没有 .c'); process.exit(2); }
const lds = path.join(SRC, 'lscript_ocm.ld');
need(lds, 'linker script');

const run = (args) => {
  /* 编译告警走 stderr，成功时也不会被 execFileSync 的返回值带回来 ⇒ 必须自己转发，
   * 否则 -Wall/-Wextra 等于没开。 */
  const r = spawnSync(CC, args, { cwd: OBJ, encoding: 'utf8' });
  if (r.stdout && r.stdout.trim()) process.stdout.write(r.stdout);
  if (r.stderr && r.stderr.trim()) process.stderr.write(r.stderr);
  if (r.status !== 0) { console.log('FATAL: 编译/链接失败 (exit ' + r.status + ')'); process.exit(1); }
  return r.stdout || '';
};

const objs = [];
for (const f of srcs) {
  const o = f.replace(/\.c$/, '.o');
  console.log(`CC  ${f}`);
  run([...CFLAGS, '-c', path.join(SRC, f), '-o', o]);
  objs.push(o);
}
console.log('LD  ps_app.elf');
/*
 * 三个归档都得给：2025.2 的 BSP 把驱动、standalone、xiltimer 分装成
 * libxil.a / libxilstandalone.a / libxiltimer.a —— `_start` 只在中间那个里。
 * 少了它，入口符号找不到、--gc-sections 又把没人引用的 main 裁掉，
 * 结果是"链接成功"但镜像是空的。
 */
run([...CFLAGS, ...objs, '-Wl,--gc-sections', '-Wl,-n', '-Wl,--no-warn-mismatch',
     `-T${lds}`, `-L${path.join(BSP, 'lib')}`, '-Wl,--start-group',
     '-lxil', '-lxilstandalone', '-lxiltimer', '-lgcc', '-lc',
     '-Wl,--end-group', '-o', OUT]);

const sz = execFileSync(CC.replace(/gcc\.exe$/, 'size.exe'), ['-A', OUT], { encoding: 'utf8' });
console.log(sz.replace(/^/gm, '    '));

/*
 * 成品自检：链接"成功"不等于可执行。曾经 ENTRY 指到一个绝对调试符号上，
 * --gc-sections 于是把 main 和整个 XSdPs 裁光，产出 .text=80 B 的空 ELF 而毫无报错。
 * 所以这里硬性要求：入口链路上的符号必须在，且代码量在合理区间。
 */
const nm = execFileSync(CC.replace(/gcc\.exe$/, 'nm.exe'), ['-g', OUT], { encoding: 'utf8' });
const have = (re, what) => {
  if (!re.test(nm)) { console.log(`FATAL: ${what} 不在 ELF 里 —— 链接被 --gc-sections 裁掉了，别把空镜像下到板上`); process.exit(3); }
};
have(/\bT _start\b/, '_start');
have(/\bT main\b/, 'main');
have(/XSdPs_CardInitialize/, 'XSdPs_CardInitialize');
const text = /(^|\n)\s*\.text\s+(\d+)/.exec(sz);
if (!text || Number(text[2]) < 20000) {
  console.log(`FATAL: .text = ${text ? text[2] : '?'} B，远小于这个 app 应有的体积`);
  process.exit(3);
}

fs.copyFileSync(OUT, path.join(root, 'build', 'ps_app.elf'));
console.log('OK  ' + OUT);
console.log('板上跑法（JTAG，不写 flash）：xsdb> source build/tcl/ps_jtag_boot.tcl（含 ps7_init）');
console.log('                             xsdb> targets -set -filter {name =~ "ps7_cortexa9_0*"} ; download <elf> ; con');
