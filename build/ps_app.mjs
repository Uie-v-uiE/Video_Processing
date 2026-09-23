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

const CFLAGS = ['-mcpu=cortex-a9', '-mfpu=vfpv3', '-mfloat-abi=hard',
                /* 非对齐访问：板上撞到过两处，症状一模一样（data abort），根因不同。
                 * ① 我们自己的代码：-O2 把 ld32() 的四个连续字节读**合并**成一条
                 *    `ldr r6,[r4,#454]`（objdump 里看得见；源码是一字节一字节读的，没写错）。
                 *    ⇒ 用下面的 -mno-unaligned-access 让编译器别合（FAT 解析只读几十字节头，代价可忽略）。
                 * ② newlib memcpy 的半字快路径（dfsr=0x801 非对齐读）：预编译的库，改不了它，
                 *    只能按它的前提来 —— **MMU 关掉时非对齐访问一定 fault**（SCTLR.A=0 的豁免
                 *    只在 MMU 开着时成立），而 MMU 是标准启动里 boot.S 开的。
                 * ⇒ 两条一起才成立：这条选项 + 链上 boot.S/translation_table.S（见下）。 */
                '-mno-unaligned-access', '-DSDT',
                '-ffunction-sections', '-fdata-sections', '-Wall', '-Wextra', '-Wno-unused-parameter',
                '-O2', `-I${path.join(BSP, 'include')}`, `-specs=${path.join(BSP, 'Xilinx.spec')}`];

if (process.argv.includes('--clean') && fs.existsSync(OBJ)) fs.rmSync(OBJ, { recursive: true, force: true });
fs.mkdirSync(OBJ, { recursive: true });

const srcs = fs.readdirSync(SRC).filter(f => /\.(c|S)$/.test(f)).sort();
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
  const o = f.replace(/\.(c|S)$/, '.o');
  console.log(`CC  ${f}`);
  run([...CFLAGS, '-c', path.join(SRC, f), '-o', o]);
  objs.push(o);
}

/*
 * BSP 自己的三个启动文件必须进来：asm_vectors.S(_vector_table + 各 handler 会把
 * 出错指令地址写进 DataAbortAddr/UndefinedExceptionAddr 全局)、boot.S(_boot：设 VBAR、
 * 六个模式的栈、CPACR+FPEXC、L2/SCU、开 MMU 然后 b _start)、translation_table.S(MMUTable)。
 *
 * 为什么以前没链：lscript.ld 的 ENTRY(_vector_table) 被改成 _start 以后，这三个对象没人引用，
 * --gc-sections 全裁了。后果今晚全数兑现：
 *   · 没人写 CPACR ⇒ 第一条 VFP 指令陷 Undefined（ISSUES #42，已记）；
 *   · 没人设 VBAR ⇒ 异常表落在 0x0，也就是 .text 头上，异常一来就去执行恰好摆在那里的代码
 *     （症状是"板子自己重启了一遍"）；
 *   · **MMU 一直关着** ⇒ newlib 的 memcpy 走"源/目的同余但对齐为奇"的半字快路径时发对齐异常
 *     （MMU 关掉时非对齐访问一定 fault，SCTLR.A=0 的豁免只在 MMU 开着时成立）。
 *     板上实测 dfsr=0x801、出错指令在 memcpy 里 —— 这不是我们代码写错，是"少了标准启动"。
 * Vitis 生成的 app 之所以没这些症状，就是因为它链了这三个文件。
 */
const BSP_ASM = ['asm_vectors.S', 'boot.S', 'translation_table.S'];
const asmDir = path.join(BSP, 'libsrc', 'standalone', 'src', 'arm', 'cortexa9', 'gcc');
for (const f of BSP_ASM) {
  const p = path.join(asmDir, f);
  need(p, 'BSP startup asm');
  const o = 'bsp_' + f.replace(/\.S$/, '.o');
  console.log(`CC  BSP/${f}`);
  run([...CFLAGS, '-c', p, '-o', o]);
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
     /* 入口在链接脚本里（src/ps/lscript_ocm.ld 的 ENTRY(_boot)）：boot.S 的 _boot 设完
      * VBAR/各模式栈/CPACR+FPEXC/MMU 之后自己 b _start。
      * 试过命令行 -Wl,-e,_boot —— 被脚本里的 ENTRY 顶掉，readelf 的入口悄悄变成 0x0，
      * 一声不响；所以入口只从脚本走，这里不传 -e（下面的 ENTRY 等值校验就是它的哨兵）。 */
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
have(/\bT _boot\b/, '_boot');
have(/\bT _vector_table\b/, '_vector_table');
have(/MMUTable/, 'MMUTable');
have(/\bT main\b/, 'main');
have(/XSdPs_CardInitialize/, 'XSdPs_CardInitialize');
const text = /(^|\n)\s*\.text\s+(\d+)/.exec(sz);
if (!text || Number(text[2]) < 20000) {
  console.log(`FATAL: .text = ${text ? text[2] : '?'} B，远小于这个 app 应有的体积`);
  process.exit(3);
}

/*
 * "符号在"不等于"从它开始跑"，也不等于"向量表在 CPU 会去找的地址上"。
 * 所以这里做**等值**校验：ELF 入口 = _boot，且 _vector_table 必须在 0x0
 * （CPSR.V=0 时硬件的向量表就在 0x00000000，而 _boot 会把 VBAR 也指到同一张表）。
 * 差一个字节就等于 #42 和"异常可诊断"两件事都没修上，而症状和修之前一模一样。
 */
const reh = execFileSync(CC.replace(/gcc\.exe$/, 'readelf.exe'), ['-h', OUT], { encoding: 'utf8' });
/* readelf 打的是 `0xcc`：以前这里写的是 `0*([0-9a-f]+)`，'0' 被 0* 吃掉后捕获到空 ⇒
 * 入口永远被读成 0，判据本身就是坏的（规则：判据也要有测试）。改成显式剥掉 0x 前缀。 */
const ep = /Entry point address:\s+(?:0x)?([0-9a-f]+)/i.exec(reh);
const sym = (n) => { const m = new RegExp('([0-9a-f]+) [Tt] ' + n + '\\b').exec(nm); return m ? m[1] : null; };
const vt = sym('_vector_table'), bt = sym('_boot'), st = sym('_start');
if (!ep || !vt || !bt || !st) {
  console.log(`FATAL: 取不到入口/符号地址 (readelf=${ep ? 'ok' : '无 Entry point 行'}, ` +
              `_vector_table=${vt || '?'}, _boot=${bt || '?'}, _start=${st || '?'})`);
  process.exit(3);
}
if (parseInt(ep[1], 16) !== parseInt(bt, 16)) {
  console.log(`FATAL: ELF 入口 0x${ep[1]} != _boot 0x${bt} —— 标准启动没跑，VBAR/栈/MMU 都没设`);
  process.exit(3);
}
if (parseInt(vt, 16) !== 0) {
  console.log(`FATAL: _vector_table 不在 0x0（实际 0x${vt}）—— VBAR 复位值就是 0，表放别处等于没有表`);
  process.exit(3);
}
console.log(`ENTRY _boot@0x${bt}  (_vector_table@0x${vt} -> 0x0 是 b _boot)  _start@0x${st}  ✓`);

fs.copyFileSync(OUT, path.join(root, 'build', 'ps_app.elf'));
console.log('OK  ' + OUT);
console.log('板上跑法（JTAG，不写 flash）：xsdb> source build/tcl/ps_jtag_boot.tcl（含 ps7_init）');
console.log('                             xsdb> targets -set -filter {name =~ "ps7_cortexa9_0*"} ; download <elf> ; con');
