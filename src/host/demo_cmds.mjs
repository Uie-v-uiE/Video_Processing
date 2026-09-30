// src/host/demo_cmds.mjs —— 把 `report/DEMO_SCRIPT.md` 代码块里的命令**逐条抽出来**，两个用途：
//   --emit <file>   抽成一份可发的脚本（`board/demo_rehearsal.txt`），板子上逐条跑一遍
//   --check <capture>  对着串口回包判"演示目录里没有任何一条命令是板子不认的 / 是'硬件待接'"
//
// 为什么要它：`report/DEMO_SCRIPT.md` 顶部写的是"照抄就能演"。这句话要么是被验过的，
//   要么就是又一份"文档里有、板上没有"（#67 那一族的反面：帮助/清单与硬件不符）。
//   抽命令这件事交给脚本而不是我手抄，是为了**清单与文档不能各说各话**：
//   文档改一行，脚本抽出来的就少一行/多一行，`--check` 会拿新的那份去问板子。
//
// 只抽代码块（``` 围栏）里、去掉行首空白后**非空且不以 `#`/`::`/`//` 开头**的行；
//   代码块之外的一切（说明、表格、md 标题）都不算命令。
// 明确不算命令的两类（列出来而不是假装通过）：
//   · `send_demo.bat` 这类 PC 侧动作（不是串口命令）
//   · 需要按键的（KEY1/KEY2）—— 串口脚本发不出手指
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..', '..');
const DOC = path.join(ROOT, 'report', 'DEMO_SCRIPT.md');
const PC_SIDE = /^(run_sender|node |bash |powershell|md5sum|xsdb|vivado|%)/i;

export function extract() {
    const lines = readFileSync(DOC, 'utf8').split(/\r?\n/);
    const out = [];
    let inFence = false;
    for (const raw of lines) {
        const l = raw.trim();
        if (l.startsWith('```')) { inFence = !inFence; continue; }
        if (!inFence || l === '' || l.startsWith('#') || l.startsWith('::') || l.startsWith('//')) continue;
        if (PC_SIDE.test(l)) continue;
        out.push(l);
    }
    return out;
}

const argv = process.argv.slice(2);
if (argv[0] === '--emit') {
    const cmds = extract();
    // 骨架：首尾各补一条 `stat`（第 0 步与第 8 步本来就要求敲它，只是第 0 步那条落在表格里、
    // 不在代码块里）。没有这对基线，"回到初态"就没有可比的两条数 —— 而那正是这一项要判的事。
    const list = ['stat', ...cmds, 'stat'];
    writeFileSync(path.resolve(ROOT, argv[1] || 'board/demo_rehearsal.txt'),
                  '# 由 src/host/demo_cmds.mjs --emit 从 report/DEMO_SCRIPT.md 抽出，不要手改\n'
                  + list.join('\n') + '\n', { encoding: 'utf8' });
    console.log(`emit ${list.length} 条（含首尾 stat 基线）-> ${argv[1] || 'board/demo_rehearsal.txt'}`);
    process.exit(0);
}
if (argv[0] === '--check') {
    const cap = readFileSync(path.resolve(ROOT, argv[1]), 'utf8');
    // 发送脚本按 `>> <命令>` 分段，所以可以**逐条**看它的回包：
    //   演示目录里任何一条命令，只要回包里出现"拒绝/单位不对/参数不在范围"这一类话，
    //   就说明文档教了一条板子不接受的写法 —— 那正是"清单里有、板上没有"（#67 的反面），
    //   而演示当天它表现为"我敲了没反应"。第一批凭据就是它抓到的一条：
    //   `gamma auto 1.0 3.0 0.2 2000` 被固件拒绝（step 要的是 γ×100 的正整数）。
    const REJECT = [/\b不认\b/, /硬件未接/, /\[CMD!\]/, /只认/, /要的是/, /要跟/, /不在范围/, /越界/];
    const bad = [];
    const cmds = extract();
    const seg = {};
    {
        const lines = cap.split(/\r?\n/);
        let cur = null;
        for (const l of lines) {
            const m = l.match(/^>>\s+(.*)$/);
            if (m) { cur = m[1].trim(); seg[cur] = ''; continue; }
            if (cur !== null) seg[cur] += l + '\n';
        }
    }
    for (const c of cmds) {
        if (!(c in seg)) { bad.push(`没有这条命令的回显：>> ${c}（没发出去？还是被合并了？）`); continue; }
        for (const re of REJECT) if (re.test(seg[c])) {
            bad.push(`被拒/待接：${c}\n            回包 ${seg[c].trim().split('\n').filter(x => x.trim())[0]?.slice(0, 110) || '(空)'}`);
            break;
        }
    }
    const cov = cmds.filter(c => c in seg).length;
    // 第 8 幕的"回到初态"不许只是说说：拿这一份捕获里**第一条与最后一条 [STAT]** 逐字段比。
    // 只放过 `pub=`（那是发布位的电平，固件每 100 ms 翻一次，本来就不会相等）。
    const stats = (cap.match(/^\[STAT\].*$/gm) || []).map(s => s.trim());
    const SKIP = new Set(['pub']);
    if (stats.length < 2) bad.push(`捕获里只有 ${stats.length} 条 [STAT] —— 排练脚本首尾各要一条`);
    else {
        const parse = s => Object.fromEntries(s.replace(/^\[STAT\] /, '').split(/\s+/)
            .filter(t => t.includes('=')).map(t => [t.slice(0, t.indexOf('=')), t.slice(t.indexOf('=') + 1)]));
        const a = parse(stats[0]), b = parse(stats[stats.length - 1]);
        for (const k of Object.keys(a)) {
            if (SKIP.has(k)) continue;
            if (a[k] !== b[k]) bad.push(`没回到初态：${k} 开始 ${a[k]} → 结束 ${b[k]}`);
        }
    }
    const ok = bad.length === 0 && cmds.length > 0;
    console.log(`  ${ok ? 'PASS' : 'FAIL'} demo 目录回包：抽出 ${cmds.length} 条命令，回显对上 ${cov} 条，拒绝 ${bad.length} 条`);
    for (const b of bad) console.log('        ' + b);
    process.exit(ok ? 0 : 1);
}
console.log('用法：node src/host/demo_cmds.mjs --emit [file] | --check <capture>');
process.exit(2);
