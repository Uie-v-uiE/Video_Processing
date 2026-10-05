// src/host/ps_hb_check.mjs —— #94 的"固件那一半"的机器凭据
//
// 为什么要它：#94 的红（AUTO 下拔掉 SD 卡 ⇒ 屏幕永久冻在最后一帧）修在**两处**：
//   PL  那边 `src_life` 把"片源存在性"从两位粘滞位换成活判据（凭据 = `sim/tb_v102_src_life.v`，13 条）；
//   PS  那边固件必须**替片源说话**（`ps_hold` + 100 ms 心跳），否则"暂停/定点/FILL"这些
//       "屏上这张是要留住的"状态会被新判据误读成"没片源"⇒ 拿掉一个红换来一个新红。
// 而 FW 这一半以前只有"读代码看起来对"—— 没有机器判据的东西在下一次改动时就是裸奔。
// 所以这里从**源码原文**抠出那几处必须同时成立的事实，逐条钉；判据本身用 `--self` 反着钉
//（四条变异对照：把修法改坏，看它是不是真的会红 —— 不红就是假绿）。
//
// 用法：
//   node src/host/ps_hb_check.mjs          # 只跑当前树（红 ⇒ 退出码 1）
//   node src/host/ps_hb_check.mjs --self    # 当前树必须全绿 + 每条变异必须各自红在它那一判上
//
// A11 顺手管第二件"PS 侧的异常"：半行（残包）留在 cmd_buf 里可以留到永远，下一条命令就会与它
//   拼成一句谁都没敲过的话 ⇒ 症状与心跳那一族一样是"板子做了我没让它做的事"，凭据也放在这里。
//
// ⚠ 这里**不编译、不上板**：它钉的是"三处源码之间的约定还成立"（节拍/超时/调用点/恢复键），
//   行为级的凭据在 tb_v102（PL）与 `board/README.md` 的眼睛那一行（整机）。
import { readFileSync } from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..', '..');
const F = {
    main:   'src/ps/main.c',
    sd:     'src/ps/sd_play.c',
    top:    'src/rtl/top/pl_video_top.v',
    life:   'src/rtl/util/src_life.v',
    tb102:  'sim/tb_v102_src_life.v',
};

// 判据里出现的每一个常数都从源码抠（见 A10），所以这里不放任何"我记得的数"。

function readTree() {
    const t = {};
    for (const [k, rel] of Object.entries(F)) t[k] = readFileSync(path.join(ROOT, rel), 'utf8');
    return t;
}

// 变异：每条都把某个事实改坏，用来证明对应的判据不是摆设
const MUT = {
    // 心跳比看门狗还慢 ⇒ 屏上一定丢画面
    slow_hb:      t => ({ ...t, main: t.main.replace('#define PS_HB_MS 100u', '#define PS_HB_MS 900u') }),
    // 读失败不再停心跳 ⇒ 冻帧回来
    no_lost:      t => ({ ...t, main: t.main.replace('ps_hold = 0u;', 'ps_hold = MUT_OFF;') }),
    // 把心跳也挂在"命令被拒"那条路上 ⇒ 被拒的命令改观感
    lost_on_badj: t => ({ ...t, sd: t.sd.replace('if (!mounted) { err = "not mounted"; return -1; }',
                                                 'if (!mounted) { err = "not mounted"; ps_source_lost(); return -1; }') }),
    // 台架里那个字面量与模块公式脱钩
    stale_tb:     t => ({ ...t, tb102: t.tb102.replace(/TO_FRAMES\s*=\s*30/, 'TO_FRAMES = 31') }),
    // 残包门限放到 9 s ⇒ 实际上等于"永远不丢"（半行会跟下一条命令拼成一句谁都没敲过的话）
    slow_rx:      t => ({ ...t, main: t.main.replace('#define RX_IDLE_MS 3000u', '#define RX_IDLE_MS 9000u') }),
    // #94/#97 追加的四条：卡插回来**自己**要能接上，这四条少一条就退化成"要手/要重下 elf"
    no_recover:   t => ({ ...t, main: t.main.replace('sd_recover_tick();', 'MUT_OFF();') }),
    no_ready:     t => ({ ...t, sd: t.sd.replace('Sd.IsReady = 0u;', '/* MUT: 不清驱动的已初始化旗标 */') }),
    always_rec:   t => ({ ...t, sd: t.sd.replace('if (!seen_mounted || !want_play || giveup) { return; }',
                                                 'if (0) { return; }') }),
    no_resume:    t => ({ ...t, sd: t.sd.replace('(void)sd_play(1);', '/* MUT: 挂上就不管了 */') }),
    // A16 的反例：**只**把收口里"清挂载旗"那一行挖掉（两条读失败路照旧走 `card_gone()`，
    // 所以 A5 不该跟着红 —— 第一版反例把 `card_gone()` 换回 `ps_source_lost()`，结果同时动了
    // A5 的结构前提，实测红=[A5,A16]，那种"一次红两条"的反例不能钉住是哪一条判据在守）。
    no_clear:     t => {
        const cg = /static void card_gone\(void\)\s*\{[\s\S]*?\n\}/;
        const body = t.sd.match(cg)?.[0] ?? '';
        return { ...t, sd: t.sd.replace(cg, body.replace(/mounted\s*=\s*0;/, '/* MUT: 不清 mounted 了 */')) };
    },
};

const num = (s, re, what) => {
    const m = s.match(re);
    if (!m) throw new Error(`抠不到 ${what}`);
    return parseInt(m[1].replace(/_/g, ''), 10);
};

function check(t) {
    const r = [];
    const add = (id, measured, criteria, ok) => r.push({ id, measured, criteria, ok: !!ok });

    // A1/A2：两边各自的数
    const hb = num(t.main, /#define\s+PS_HB_MS\s+(\d+)u?/, 'PS_HB_MS');
    const to = num(t.top, /PS_SRC_TIMEOUT_MS\s*=\s*(\d+)/, 'PS_SRC_TIMEOUT_MS');
    // A1：顶层确实把这一个数交给了 src_life（不是另一个字面量）
    add('A1 超时值交给 src_life',
        /src_life[^;]*HB_TIMEOUT_MS\(PS_SRC_TIMEOUT_MS\)/.test(t.top),
        '实例化里必须是这个参数名',
        /src_life[^;]*HB_TIMEOUT_MS\(PS_SRC_TIMEOUT_MS\)/.test(t.top));
    // A2：心跳至少要在超时窗口里排得下 3 拍（1 拍是掷硬币，2 拍没有余量）
    add('A2 心跳/超时余量', `hb=${hb} to=${to} x${Math.floor(to / hb)}`, `${hb}*3 <= ${to}`, hb * 3 <= to);
    // A3：交出去的那一刻才置 hold，并且把时基对齐（少了后者 ⇒ 第一拍就按上一次的旧时基发）
    const pub = t.main.match(/void ps_publish\(void\)\s*\{[\s\S]*?\n\}/)?.[0] ?? '';
    add('A3 publish 里置 hold 且重设时基', `hold=${/ps_hold\s*=\s*1u/.test(pub)} t=${/XTime_GetTime\(&ps_ka_t\)/.test(pub)}`,
        '两条都要在 ps_publish 体内', /ps_hold\s*=\s*1u/.test(pub) && /XTime_GetTime\(&ps_ka_t\)/.test(pub));
    // A4：`ps_hold = 0` 全设计只许出现一次，且就在 ps_source_lost 体内
    const zeroAt = [...t.main.matchAll(/ps_hold\s*=\s*0u/g)].length;
    const lost = t.main.match(/void ps_source_lost\(void\)\s*\{[\s\S]*?\n\}/)?.[0] ?? '';
    add('A4 只有 read-error 能收回 hold', `清零点=${zeroAt} 在lost内=${/ps_hold\s*=\s*0u/.test(lost)}`,
        '恰好 1 处且在 ps_source_lost 体内', zeroAt === 1 && /ps_hold\s*=\s*0u/.test(lost));
    // A5：sd_play.c 只在"真的去读卡且读失败"那两条路上收心跳；越界/没挂载那两条不许收
    const calls = [...t.sd.matchAll(/ps_source_lost\(\)/g)].length;
    const sf = t.sd.match(/static int show_frame\(u32 idx\)\s*\{[\s\S]*?\n\}/)?.[0] ?? '';
    const badPath = /(!mounted|out of range)[\s\S]{0,120}ps_source_lost/.test(sf);
    add('A5 收心跳的调用点', `次数=${calls} 拒命令也收=${badPath}`,
        '恰好 2 次（open_at/feed_cur），且不挂在被拒路径上', calls === 2 && !badPath);
    // A6：心跳得在主循环里跑（放在哪个 handler 里都只能救那一条命令）
    const loop = t.main.match(/while\s*\(1\)\s*\{[\s\S]*?\n\s*\}/)?.[0] ?? '';
    add('A6 主循环里敲心跳', /ps_keepalive\(\)/.test(loop) ? '在' : '不在', 'while(1) 体内调用 ps_keepalive()',
        /ps_keepalive\(\)/.test(loop));
    // A7：remount 必须先清 mounted 再调 sd_mount（反了就是"假装挂着的卡还在"，#45）
    const rm = t.sd.match(/int sd_remount\(void\)\s*\{[\s\S]*?\n\}/)?.[0] ?? '';
    add('A7 remount 先清再挂',
        `清=${/mounted\s*=\s*0/.test(rm)} 挂在后面=${/mounted\s*=\s*0[\s\S]*sd_mount\(\)/.test(rm)}`,
        '置 0 在 sd_mount() 之前', /mounted\s*=\s*0/.test(rm) && /mounted\s*=\s*0[\s\S]*sd_mount\(\)/.test(rm));
    // A8：串口得有这一个键，不然恢复手段还是"重下 elf"
    add('A8 sd remount 有入口', /"REMOUNT"/.test(t.main) ? '有' : '无', '命令层认 REMOUNT 这个子词',
        /REMOUNT/.test(t.main));
    // ---- A16（2026-09-27 13:1x，#94 追加：门从来没开过的那一半）----
    // 自动恢复的**门**是 `sd_recover_tick()` 的第一行 `if (mounted) return;`。
    // 拔出卡时那两条"真的去读卡并且读失败"的路以前只调 `ps_source_lost()`（= 画面交回仲裁，
    // 用户看到的"切到 test"），却没人清 `mounted` ⇒ 门永远关着，"插回来不自动切回 SD"就是这么来的。
    // 所以这里钉两件：① 两条读失败路都走同一个收口 `card_gone()`；② 那个收口里必须清 `mounted`。
    const sf16 = t.sd.match(/static int show_frame\(u32 idx\)[\s\S]*?\n\}/)?.[0] ?? '';
    const cg16 = t.sd.match(/static void card_gone\(void\)\s*\{[\s\S]*?\n\}/)?.[0] ?? '';
    const n16  = (sf16.match(/card_gone\(\)/g) || []).length;
    add('A16 读失败清挂载旗', `走收口=${n16} 处 收口清mounted=${/mounted\s*=\s*0/.test(cg16) ? '是' : '否'}`,
        'show_frame 的两条读卡失败路都调 card_gone()，且它清 mounted（否则 recover 的门永远关着）',
        n16 === 2 && /mounted\s*=\s*0/.test(cg16));

    // ---- A12~A15（2026-09-27，#94 的"插回不恢复"那一半）：卡插回来必须**自己**接上，不要手 ----
    // A12：自动重挂得敲在主循环里（敲在 sd_tick 里 ⇒ 一旦 playing=0 就再没人叫它，正是用户报的死路）
    add('A12 主循环里敲自动重挂', /sd_recover_tick\(\)/.test(loop) ? '在' : '不在',
        'while(1) 体内调用 sd_recover_tick()', /sd_recover_tick\(\)/.test(loop));
    // A13：#45 那句"每个上电周期只能初始化一次"其实是驱动的 `IsReady` 守卫（`xsdps.c:156-159`），
    //       不清它，`sd_mount()` 第一步就被挡回 ⇒ 重挂永远失败，改多少次软件状态都没用。
    add('A13 重挂前清驱动 IsReady',
        `清=${/Sd\.IsReady\s*=\s*0u/.test(rm)} 挂在后面=${/Sd\.IsReady\s*=\s*0u[\s\S]*sd_mount\(\)/.test(rm)}`,
        '清零在 sd_mount() 之前', /Sd\.IsReady\s*=\s*0u/.test(rm) && /Sd\.IsReady\s*=\s*0u[\s\S]*sd_mount\(\)/.test(rm));
    // A14：动手的条件必须同时是"这个上电周期挂过 + 丢卡那一刻在播 + 还没放弃"，而且要有节拍与次数上限。
    //       少任何一半都会变成：没插卡的板子上电就每拍撞一次 CMD 超时 ⇒ 控制台没人听（#94 文件头那条）。
    const rec = t.sd.match(/void sd_recover_tick\(void\)\s*\{[\s\S]*?\n\}/)?.[0] ?? '';
    // ⚠ 判"闸门在不在"必须判**那一句**，不能判三个标识符是否出现在函数体里：
    //   `seen_mounted/want_play/giveup` 在"挂载成功"那个分支里也各自被赋值，
    //   把 return 守卫删掉它们照样全在 ⇒ 判据结构上红不了（`--self` 的 always_rec 变异
    //   第一次就是这么"红=[]"暴露的）。
    const gate = /if\s*\(\s*!seen_mounted\s*\|\|\s*!want_play\s*\|\|\s*giveup\s*\)\s*\{\s*return;/.test(rec);
    add('A14 自动重挂有闸门',
        `三个条件都在同一句守卫里=${gate} 节拍=${/COUNTS_PER_SECOND/.test(rec)} 上限=${/rec_tries\s*>=/.test(rec)}`,
        '三个条件在**同一句 return 守卫**里 + 有 2 s 级节拍 + 有次数上限并明说',
        gate && /COUNTS_PER_SECOND/.test(rec) && /rec_tries\s*>=/.test(rec));
    // A15：重挂成功必须把回放接回来（只挂载不播 = 屏上仍是一张静止画，用户念的还是"没自动切到 SD"）
    add('A15 挂上就接回放', /sd_play\(1\)/.test(rec) ? '有' : '无',
        '成功分支里调用 sd_play(1)', /sd_play\(1\)/.test(rec));
    // A9：PL 侧不许再留"只置位从不清零"的粘滞位（那是这次的红生的地方）
    add('A9 顶层无粘滞片源位', `ps_src_seen=${(t.top.match(/ps_src_seen/g) || []).length}`,
        '顶层里除了历史注释（0 处代码）不得再有该位',
        !/reg[\s\S]{0,40}ps_src_seen/.test(t.top) && !/ps_src_seen\s*<=/.test(t.top));
    // A10：src_life 的帧数公式与台架里那个字面量必须还是同一个数（各算各的=脱钩）。
    //      四个数全部**从源码抠**：超时来自顶层、帧周期与"先除后乘"的写法来自 src_life、
    //      字面量来自台架 —— 这里再抄一份常数就等于把判据写成"我相信我自己"。
    const cycOk = /localparam\s+integer\s+HB_CYCLES\s*=\s*\(CLK_HZ\s*\/\s*1000\)\s*\*\s*HB_TIMEOUT_MS/.test(t.life);
    const frame = num(t.life, /HB_FRAMES\s*=\s*HB_CYCLES\s*\/\s*(\d[\d_]*)/, 'HB_FRAMES 的帧周期');
    const clk   = num(t.top,  /src_life\s*#\s*\(\s*\.CLK_HZ\((\d[\d_]*)\)/, 'src_life 实例化的 CLK_HZ');
    const tbv   = num(t.tb102, /TO_FRAMES\s*=\s*(\d+)/, 'tb_v102 TO_FRAMES');
    const calc  = Math.floor((clk / 1000) * to / frame) + 1;
    add('A10a 超时先除后乘', cycOk ? '(CLK_HZ/1000)*ms' : '其它写法',
        'HB_CYCLES 必须是 (CLK_HZ/1000)*HB_TIMEOUT_MS（反序在 32 位里溢出成 1 帧）', cycOk);
    add('A10b 台架与公式同一个数', `clk=${clk} to=${to} frame=${frame} → ${calc} 台架=${tbv}`,
        'tb 的 TO_FRAMES == floor(clk/1000*超时ms/帧周期)+1', calc === tbv);
    // A11：残包（半行）必须会被丢掉**并且说出来**。这一条与心跳同族：都是"PS 这一侧的异常"，
    //      而且症状一样讨厌 —— 半行留在缓冲区里，下一条命令就变成一句谁都没敲过的话。
    //      2026-09-29 收紧：过去只要"清空 cmd_buf"就算过，可那会把**已经写完的行一起陪葬**
    //      （派发在这段之后才跑）。现在要求它明确"只丢最后一个行尾之后的那段"：
    //      既算出 keep（最后一个 '\n' 之后），又只把 cmd_len 收到 keep。
    const poll = t.main.match(/static void uart_poll\(void\)\s*\{[\s\S]*?\n\}/)?.[0] ?? '';
    const idle = num(t.main, /#define\s+RX_IDLE_MS\s+(\d+)u/, 'RX_IDLE_MS');
    const keepTail = /keep\s*=\s*k\s*\+\s*1/.test(poll) && /cmd_len\s*=\s*keep/.test(poll);
    add('A11 残包只丢尾巴且明说', `ms=${idle} 只丢尾=${keepTail} 说=${/\[CMD!\]/.test(poll)} 判=${/rx_t\)/.test(poll)}`,
        'uart_poll 里有"计时→算 keep→收到 keep→出声"，且门限在 0.5..5 s',
        keepTail && /\[CMD!\]/.test(poll) && /rx_t\)/.test(poll) && idle >= 500 && idle <= 5000);
    return r;
}

function report(r, label) {
    let bad = 0;
    console.log(`\n== ${label}`);
    for (const c of r) {
        if (!c.ok) bad++;
        console.log(`  ${c.ok ? 'PASS' : 'FAIL'} ${c.id.padEnd(24)} 实测 ${String(c.measured).padEnd(28)} 判据 ${c.criteria}`);
    }
    console.log(`  —— ${r.length - bad}/${r.length}`);
    for (const c of r) if (!c.ok) console.log(`        红项 ${c.id.split(' ')[0]}：判据 ${c.criteria}，实测 ${c.measured}`);
    return bad;
}

const argv = process.argv.slice(2);
if (argv.includes('--self')) {
    // 先钉"当前树全绿"，再逐条钉"改坏它Must红"。变异只在内存里，不落盘、不碰工作树。
    const base = readTree();
    let rc = 0;
    const baseRows = check(base);
    const bad0 = report(baseRows, '当前树');
    if (bad0) { console.log('SELF: 当前树就有红项 —— 变异对照没有意义'); process.exit(1); }
    const expect = { slow_hb: 'A2', no_lost: 'A4', lost_on_badj: 'A5', stale_tb: 'A10b', slow_rx: 'A11',
                     no_recover: 'A12', no_ready: 'A13', always_rec: 'A14', no_resume: 'A15', no_clear: 'A16' };
    for (const [name, mut] of Object.entries(MUT)) {
        const t = mut(structuredClone(base));
        if (JSON.stringify(t) === JSON.stringify(base)) {
            console.log(`SELF: 变异 ${name} **没有改动任何字节** ⇒ 它钉不住任何东西（判据写法过期了）`);
            rc = 1; continue;
        }
        const rows = check(t);
        const red = rows.filter(x => !x.ok).map(x => x.id.split(' ')[0]);
        const want = expect[name];
        const ok = red.length === 1 && red[0] === want;
        console.log(`  ${ok ? 'PASS' : 'FAIL'} 变异 ${name.padEnd(14)} 只红在 ${want.padEnd(4)} 实测红=[${red.join(',')}]`);
        if (!ok) rc = 1;
    }
    console.log(rc ? 'SELF: 有红 —— 判据或变异之一不成立'
                   : `SELF: 全绿（当前树 ${baseRows.length} 条 + 变异对照 ${Object.keys(MUT).length} 条）`);
    process.exit(rc);
}
process.exit(report(check(readTree()), '当前树') ? 1 : 0);
