// src/host/doc_enc_check.mjs —— 手写的文件必须是 UTF-8，而且不许有"打坏的字"
//
// 为什么要它：`report/COMMANDS.md` 第 5 节有一整段（bilin 那几行）在某个时刻被 cp936 控制台
// 写坏了 —— 2026-09-26 才发现（`grep` 把整个文件当二进制、编辑器里是一串看不出意思的块）。
// 这类事故的讨厌之处是**它不改变任何行为**：位流照编、台架照跑、门禁照绿，
// 坏的是"演示时念给自己听的那份清单"，而那份清单要给评审看。
// 所以判据要能自己跑：`build/gates.sh` 第 17 项。
//
// 边界（说清楚，不然就是假红）：
//   * 只扫**手写**的扩展名（.md .v .c .h .mjs .sh .ps1 .tcl）。`*.txt` 一律不扫 ——
//     那里放的是 Vivado / xsdb / PowerShell 的原始回显，本来就是 cp936 或 UTF-16；
//     把它们"修成 UTF-8"才是破坏凭据（原始件不许动）。
//   * .ps1 / .tcl 允许开头那一个 BOM（Windows 侧写出来的，Vivado 与 PowerShell 都认），但只允许第 0 个字符。
//   * 扫描范围是**点名**的几棵树（见 SCOPE）：`vitis/**` 是 Xilinx 的 BSP/FSBL（版权行本来就不是 UTF-8），
//     报它红等于让门禁永远不绿，改它更是破坏第三方件；`build/uram_probe/` 是被 md5 引用的早期探针原始件，
//     注释在这条判据出现之前就已经坏了 —— 见 ALLOW_BAD 那段。
//   * 什么算坏：解不出 UTF-8；或行里出现 C0/C1 控制符（\t \r \n 除外）、U+FFFD 替换符、
//     落单的代理对、私用区 E000-F8FF（cp936 打坏最常见的落点）。
//
// 用法：node src/host/doc_enc_check.mjs [--self]
import { readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..', '..');
const EXT = new Set(['.md', '.v', '.c', '.h', '.mjs', '.sh', '.ps1', '.tcl']);
// 只扫**我写的东西**所在的那几棵树。为什么不是"整仓库扫一遍"：
//   `vitis/platform/**` 是 Xilinx 的 BSP/FSBL 源码（版权行里就有非 UTF-8 的字节），
//   把它们报成红等于让门禁永远不会绿，而"修它们"是破坏第三方件 —— 两条都不接受。
const SCOPE = ['report/', 'board', 'src', 'sim', 'tools', 'build/tcl', 'skill'];   // 交付文档在 report//（含 report//log/）；report/ 与 study/ 已不存在；skill/ 是给评委读的手写正文，2026-09-29 补进扫描范围（漏掉它的那天我刚往 skill/ 加了一条 CJK 条目）
// 明确点名放行的一类：早期探针的原始件。`build/uram_probe/uram_probe.v` 的中文注释在
// 出现这个判据**之前**就已经坏掉（字节丢失，不可恢复），而它的结论被
// `build/frozen_r57_remap/MANIFEST.md5` 与两份报告按 md5 引用 —— 改一个字节就等于伪造凭据。
// 所以这里放行，并把"不要再拿它当可读文本来引用"这句话留在这。
const ALLOW_BAD = ['build/uram_probe/uram_probe.v'];
const BOM_OK_EXT = new Set(['.ps1', '.tcl']);     // Windows 侧写出来的脚本常带开头 BOM，工具认它
const SKIP_DIR = new Set(['.git', 'vivado_system', 'xsim.dir', 'node_modules', '.Xil', 'dist']);

function walk(dir, out) {
    for (const name of readdirSync(dir)) {
        const p = path.join(dir, name);
        const st = statSync(p);
        if (st.isDirectory()) { if (!SKIP_DIR.has(name)) walk(p, out); }
        else if (EXT.has(path.extname(name))) out.push(p);
    }
    return out;
}

function scopedFiles() {
    const out = [];
    for (const rel of SCOPE) {
        let st;
        try { st = statSync(path.join(ROOT, rel)); } catch { continue; }
        if (st.isDirectory()) walk(path.join(ROOT, rel), out);
        else out.push(path.join(ROOT, rel));
    }
    return out;
}

function badChar(c) {
    if (c === 0x09 || c === 0x0d || c === 0x0a) return false;
    if (c >= 0x20 && c <= 0x7e) return false;
    if (c === 0xfeff) return true;                     // 中间的 BOM（开头那个由 .ps1 单独放行）
    if (c < 0xa0) return true;                         // 剩下的 C0/C1
    if (c === 0xfffd) return true;                     // 替换符 = 已经丢过字节
    if (c >= 0xd800 && c <= 0xdfff) return true;       // 落单的代理对
    if (c >= 0xe000 && c <= 0xf8ff) return true;       // 私用区
    return false;
}

function scanText(rel, text, rows) {
    const lines = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
        const l = lines[i];
        for (let j = 0; j < l.length; j++) {
            const c = l.charCodeAt(j);
            const isLeadBom = (i === 0 && j === 0 && c === 0xfeff && BOM_OK_EXT.has(path.extname(rel)));
            if (isLeadBom) break;
            if (badChar(c)) { rows.push(`${rel}:${i + 1} 第 ${j + 1} 列 U+${c.toString(16).toUpperCase().padStart(4, '0')}`); break; }
        }
    }
}

function scan() {
    const rows = [];
    let n = 0;
    for (const p of scopedFiles()) {
        const rel = path.relative(ROOT, p).replace(/\\/g, '/');
        if (ALLOW_BAD.includes(rel)) continue;
        n++;
        let text;
        try {
            text = new TextDecoder('utf-8', { fatal: true }).decode(readFileSync(p));
        } catch {
            rows.push(`${rel}:0 整个文件不是 UTF-8（手写文件请存成 UTF-8 无 BOM；原始回显放 .txt）`);
            continue;
        }
        scanText(rel, text, rows);
    }
    return { rows, n };
}

const argv = process.argv.slice(2);
if (argv.includes('--self')) {
    // 判据自己的反例：造两条坏行，必须被同一段代码抓出来（不抓就是假绿）；好行不许上榜。
    const probe = [];
    scanText('P1.md', '这一行是好的中文：门禁\n这一行有 \uFFFD 替换符\n', probe);
    scanText('P2.md', '这一行有私用区字符 \uE123\n', probe);
    scanText('P3.md', '这一行有 C1 控制符 \u0085\n', probe);
    const ok = probe.length === 3 && !probe.some(r => r.startsWith('P1.md:1'));
    console.log(`  ${probe.length === 3 ? 'PASS' : 'FAIL'} 三条坏行各抓一条（实测 ${probe.length}）`);
    for (const r of probe) console.log('        ' + r);
    console.log(`  ${ok ? 'PASS' : 'FAIL'} 好行不误报（P1.md 第 1 行没上榜）`);
    process.exit(ok ? 0 : 1);
}
const { rows, n } = scan();
console.log(`扫了 ${n} 个手写文件：${rows.length ? '有坏字' : '全部干净'}`);
for (const r of rows.slice(0, 40)) console.log('  ' + r);
if (rows.length > 40) console.log(`  …另外 ${rows.length - 40} 条`);
process.exit(rows.length ? 1 : 0);
