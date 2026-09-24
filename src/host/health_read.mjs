#!/usr/bin/env node
/**
 * health_read.mjs — V7.6 (P0-A) 从 PS 侧读回 PL 的链路健康快照。
 *
 * 硬件接口（不加 AXI 从设备，只用两个 GPIO）：
 *   · Lane 号写在**已存在**的 GPIO_0 的 bit[31:27]；脚本先读回 GPIO_0 的原值，
 *     只改这 5 位，最后再把原值写回去 —— effect_en/threshold/src_sel 不受影响。
 *   · 数据从新加的 GPIO_1（只读 32bit）读。
 *   · lane 0..9 = link_monitor 的快照；lane 31 bit0=源时钟消失，bit1=源时钟被拉慢（拔线）；
 *     其它 lane 号硬件返回 0xDEADBEEF，一眼能看出号写错了。
 *
 * 用法：
 *   node health_read.mjs [--gpio0 41200000] [--gpio1 41210000] [--once] [--gapclr]
 *   --gapclr 读之前把「帧间隔统计」归零（lane3/4/5）；其余 lane 仍是自启动以来。
 *   前置：板子上电、bit 已下载、hw_server 在跑（见 HOST_GUIDE.md）。
 *   两个基地址在 build/v76_build.log 的 `ADDR GPIO0 = …` / `ADDR GPIO1 = …` 行里。
 *
 * 默认把 10 条 lane 读两遍：单调计数器的第二遍只允许 >= 第一遍，变小就意味着
 * 采到了快照刷新的那一拍（撕烈），会单独报出来。非单调 lane（stall/gap/flags）
 * 两遍不同是正常的，只标注不报错。
 */
import { execSync } from 'node:child_process';
import { writeFileSync, readFileSync, unlinkSync } from 'node:fs';
import { dump } from './repo_path.mjs';

function get(name, def) {
  const i = process.argv.indexOf('--' + name);
  if (i < 0) return def;
  const nxt = process.argv[i + 1];
  return nxt && !nxt.startsWith('--') ? nxt : true;
}
const XSDB  = String(get('xsdb', 'D:\\Software\\Vivado\\2025.2.1\\Vitis\\bin\\xsdb.bat'));
const PORT  = Number(get('port', 3121));
const GPIO0 = '0x' + String(get('gpio0', '41200000'));
const GPIO1 = '0x' + String(get('gpio1', '41210000'));
const PASSES = get('once') ? 1 : 2;
// v7.6c：--gapclr 会在读之前把 gpio_o[26] 拉高一下，把**帧间隔统计**归零。
// 为什么需要：gap_max 是终身保持的，而两件事会污染它 —— ① 上一次实验留下的长空闲；
// ② 修好之前 16bit 毫秒计数还会回卷。没有归零入口，lane3/4/5 就只能当“自启动以来”看。
const CLR = get('gapclr', false) === true;
const CLR_BIT = 26;

// 两遍比对的判据必须按"这个 lane 是不是单调"来分：
//   · 单调 lane（累计计数）只有在**第二次比第一次小**时才是撕烈 —— 推流过程中
//     它两遍本来就该不等（板级实测：15 fps 下 pkts 两遍差了几千，这是正常）。
//   · 非单调 lane（gap/flags/stall 会回卷或被清零）两遍不等没有意义，只标注不报错。
const MONO = new Set([0, 1, 5, 6, 8, 9]);
const LIVE = new Set([2, 3, 4, 7]);
const LANES = [
  ['drop_words',   '被 fifo_full 挡住而永久消失的 16bit 字数（板上唯一真实丢数据通道）'],
  ['bad|err',      '低16=被作废的帧数，高16=坏包数（上板 p_good 恒 1 ⇒ 坏包应为 0）'],
  ['stall|rows',   '低16=距上一个完整帧过了多少 ms，高16=作废帧最多缺几行'],
  ['gap_last',     '最近一帧间隔 ms（≈1000/fps）；只统计自上次 --gapclr 以来'],
  ['gap_min|max',  '低16=最小间隔，高16=最大间隔 ms（终身保持，测量前用 --gapclr 归零）'],
  ['gap_sum',      'Σ间隔 ms；平均 = gap_sum / (frames_ok - 1)（>65.5 s 的间隔饱和在 0xFFFF）'],
  ['cdc_episodes', 'CDC 从"没满"跳到"满"的次数'],
  ['flags',        'bit0 丢过字 / bit1 作废过帧 / bit2 灌满过 / bit3 流活着 / bit4 间隔已校准'],
  ['pkts',         '收到的 UDP 包数'],
  ['bytes',        '收到的有效字节数'],
];

// ============================ lane30 译码（一份实现，两处用）============================
// 位序来自 RTL：pl_video_top.v 的 `assign dbg_src = {...}`，与台架 tb_v796_src_arb.v 的
// G1 表逐位对齐。台架证明的是**硬件里那 16 位的内容**；这一份 JS 是第二个独立实现，
// 它自己也要有判据（--selfcheck）——否则"读回 0x310"被译成"没有流"而其实位挪了一格，
// 板级报告就会把一句译码错误写成结论。（#59 的教训：屏上/读回两边各译各的。）
function decodeSrc(src) {
  if (src === undefined) return null;
  const b = (n) => (src >>> n) & 1;
  const why = (src >>> 8) & 7;
  return {
    eth_tb_ok: b(0), eth_live: b(1), owner_eth: b(2),
    fill_busy: b(3), row_busy: b(4), mode_gray: (src >>> 5) & 3,
    why_gray: why,
    why_tb_untrusted: b(8), why_no_stream: b(9), why_force_ps: b(10),
    mode: ({ 0: 'AUTO', 1: 'LOCK_ETH', 3: 'LOCK_PS', 2: 'LOCK_CARD' })[((src >>> 5) & 3)] ?? 'BAD',
    why: (['手动锁 PS', '没有流', '源时基不可信'].filter((_, i) => (why >>> (2 - i)) & 1)).join('+')
         || '无（ETH 想要总线）',
  };
}

// ============================ lane23 译码（V8-8 最后一跳）============================
// 位序唯一出处：pl_video_top.v 的 `assign dbg_zoom = {...}`；台架 tb_v95_zoom_snap.v 的 Z2 段
// 逐字段钉住同一张表。这一份 JS 是**第三个读者**（RTL / 台架 / 这里），所以它也要有判据（S4 段）。
function decodeZoom(v) {
  if (v === undefined) return null;
  const b = (n) => (v >>> n) & 1;
  return {
    alive: b(31),
    zman: b(18), zsel: (v >>> 15) & 7, zcode: (v >>> 12) & 7,
    zoom_active: b(11), zoom_dir: b(10), inv_scale: v & 0x3FF,
  };
}
// 八档的**倍率**（与 src/ps/main.c 的 ZOOM_X100、zoom_ctrl.v 的档位表同序，但这里的期望
// 不是抄它们的整数表 —— 而是从"倍率"这个定义算出来的，见 inv_exp_of）。
const ZOOM_X100 = [25, 33, 50, 75, 100, 133, 150, 200];
// inv_scale 是 Q8 的**倒数**：期望值 = 256 ÷ 倍率 = 25600 ÷ x100，四舍五入，
// 再夹到 10 bit 的天花板 1023（0.25x 本该是 1024，但 inv_scale 只有 10 位 ⇒ 1024 会回绕成 0，
// 见 zoom_ctrl.v 里 tbl(0) 的那段注释）。这样"表被谁改了一个数"是**推导出来的红**，
// 而不是"两边一起改"的假绿 —— tb_v94 用的是同一个式子。
const inv_exp_of = (i) => Math.min(1023, Math.round(25600 / ZOOM_X100[i]));
// 最近一档：拿 Q8 倍率(256×256/inv... )与八档的期望 inv 比距离 —— 与 zoom_ctrl 的 zoom_code 同定义。
const near_of = (inv) => ZOOM_X100.map((_, i) => i)
  .reduce((best, i) => (Math.abs(inv - inv_exp_of(i)) < Math.abs(inv - inv_exp_of(best)) ? i : best), 0);

// ---- --selfcheck：译码器自己的判据，不碰板子 ----// 三条：① 逐位独热走查（每个 bit 只许动它该动的字段，硬件里恒 0 的 bit7/bit11..15 一个都不许动）；
// ② 八个 why 组合对**手抄的语义表**（不从 decode 反推，抄过来就等于自证）；
// ③ 反向对照：把 why 整体错移一位后必须被 ① 抓到 —— 抓不到就说明这条判据是假的。
if (get('selfcheck', false) === true) {
  const KEYS = Object.keys(decodeSrc(0));
  const OWN = {   // bit → 允许变化的字段；空数组 = 这一位在硬件里恒 0，译码器必须无视它
    0: ['eth_tb_ok'], 1: ['eth_live'], 2: ['owner_eth'], 3: ['fill_busy'], 4: ['row_busy'],
    5: ['mode_gray', 'mode'], 6: ['mode_gray', 'mode'], 7: [],
    8: ['why_gray', 'why_tb_untrusted', 'why'], 9: ['why_gray', 'why_no_stream', 'why'],
    10: ['why_gray', 'why_force_ps', 'why'], 11: [], 12: [], 13: [], 14: [], 15: [],
  };
  let n_ok = 0, n_bad = 0;
  const say = (tag, pass, txt) => {
    console.log(`${pass ? 'PASS' : 'FAIL'} ${tag}${txt ? ' ' + txt : ''}`);
    pass ? n_ok++ : n_bad++;
  };
  const base = decodeSrc(0);
  const norm = (a) => JSON.stringify([...a].sort());
  const OWN_S = Object.fromEntries(Object.entries(OWN).map(([k, v]) => [k, norm(v)]));
  for (let bit = 0; bit < 16; bit++) {
    const d = decodeSrc(1 << bit);
    const moved = norm(KEYS.filter((k) => String(d[k]) !== String(base[k])));
    say(`S1 bit${bit} 只改 [${OWN[bit].join(',')}]`,
        moved === OWN_S[bit], `实际改了 [${JSON.parse(moved).join(',')}]`);
  }
  // ② 手抄语义表：{锁PS, 没流, 时基不可信} 三位的 8 种组合各自该印成什么
  const WHY_TXT = ['无（ETH 想要总线）', '源时基不可信', '没有流', '没有流+源时基不可信',
                   '手动锁 PS', '手动锁 PS+源时基不可信', '手动锁 PS+没有流',
                   '手动锁 PS+没有流+源时基不可信'];
  for (let w = 0; w < 8; w++)
    say(`S2 why=0b${w.toString(2).padStart(3, '0')} → 「${WHY_TXT[w]}」`,
        decodeSrc(w << 8).why === WHY_TXT[w] && decodeSrc(w << 8).why_gray === w,
        `实际「${decodeSrc(w << 8).why}」`);
  // ③ 反向对照（变异测试）：造两个"整体错移一位"的坏译码器（右移、左移各一个），
  //    同一张表必须能看出它们不对。为什么按位判、又不写"抓到 15/16"这种总数：
  //      · 恒 0 的位（bit7、bit11..15）怎么移都"什么都没改"⇒ 天生抓不到，写总数就是抄数字；
  //      · bit5/bit6 同属 mode_gray，右移后落进同一个字段集合 ⇒ 单向移位会漏；
  //    所以判据写成"**十个真实位里的每一个，至少被一个方向的移位抓到**"——这条会随
  //    位表变化自动收紧或放松，而不是一个可以随手改小的常数。
  const LIVE_BITS = [0, 1, 2, 3, 4, 5, 6, 8, 9, 10];
  const moves = (v) => { const d = decodeSrc(v); return norm(KEYS.filter((k) => String(d[k]) !== String(base[k]))); };
  let blind = [];
  for (const bit of LIVE_BITS) {
    const r = moves((1 << bit) >>> 1), l = moves(((1 << bit) << 1) & 0xffff);
    if (r === OWN_S[bit] && l === OWN_S[bit]) blind.push(bit);
  }
  say(`S3 变异对照：${LIVE_BITS.length} 个真实位全部至少被一个错移方向抓到`,
      blind.length === 0, blind.length ? `漏网 bit${blind.join(',bit')}` : '');

  // ---- S4/S5：lane23 的译码与档位期望表（同一套手法：独热走查 + 从定义推导的期望）----
  const ZKEYS = Object.keys(decodeZoom(0));
  const zbase = decodeZoom(0);
  const ZOWN = {
    31: ['alive'], 18: ['zman'], 15: ['zsel'], 16: ['zsel'], 17: ['zsel'],
    12: ['zcode'], 13: ['zcode'], 14: ['zcode'], 11: ['zoom_active'], 10: ['zoom_dir'],
  };
  for (let bit = 0; bit < 10; bit++) ZOWN[bit] = ['inv_scale'];
  let z_ok = 0;
  for (let bit = 0; bit < 32; bit++) {
    const d = decodeZoom(1 << bit);
    const moved = norm(ZKEYS.filter((k) => String(d[k]) !== String(zbase[k])));
    const want = norm(ZOWN[bit] || []);        // 19..30 恒 0 ⇒ 译码器必须无视
    if (moved === want) z_ok++;
    else console.log(`  DBG S4 bit${bit}: 改了 ${moved} 期望 ${want}`);
  }
  say('S4 lane23 逐位独热走查 32/32（19..30 是保留位，译码器不许被它们动）', z_ok === 32, `${z_ok}/32`);
  // S5 八档期望：全部由"倍率"推导（25600/x100 四舍五入，夹到 10 bit 天花板 1023），
  //   并顺手验最近一档函数在**每一档的期望值**上必须回到自己（不然 lane23 的 zcode 判据是空的）。
  let s5 = 0;
  for (let i = 0; i < 8; i++) {
    const e = inv_exp_of(i);
    const okRange = e >= 128 && e <= 1023 && Number.isInteger(e);
    const okNear = near_of(e) === i;
    if (okRange && okNear) s5++;
    else console.log(`  DBG S5 档${i} x100=${ZOOM_X100[i]} → inv=${e}（区间 ${okRange}）最近档=${near_of(e)}`);
  }
  say('S5 八档 inv 期望都在 10bit 区间内且"最近档"回到自己（8/8）', s5 === 8, `${s5}/8`);
  // S5b 反向对照：0.25x 这一档必须被夹到 1023 而不是 1024 —— 这是板级"缩到最小反而变成无限大"的根，
  //     也是 lane23 判据里唯一一条**不能靠放松解决**的：式子给 1024，硬件只能到 1023。
  say('S5b 0.25x 的期望被 10 bit 天花板夹住（=1023，不是 1024）',
      inv_exp_of(0) === 1023 && Math.round(25600 / ZOOM_X100[0]) === 1024);
  console.log(`${n_bad === 0 ? 'PASS' : 'FAIL'} health_read --selfcheck pass=${n_ok} fail=${n_bad}`);
  process.exit(n_bad === 0 ? 0 : 1);
}

const HEAD = [
  `catch {connect -host localhost -port ${PORT}}`,
  `targets -set -filter {name =~ "*#0"}`,
  // 读 PL 外设用 stop/con（和 build/tcl/set_src.tcl 同一套路）：A9 停在断点时
  // mrd/mwr 走 CoreSight 直接打到 GP0 从端口，绕过 D-Cache 也不会有 MMU 参与。
  // 不用 ddr_verify 的 rst -processor —— 那会停掉正在跑的 ELF，而这里不该伤到
  // PS 侧的状态。最后一步再 con 回去。
  `catch {stop}`,
  `after 100`,
];

// xsdb 的 mrd 返回形如 "41200000:   00010000"。**不要**在 Tcl 里 lindex/split 它
// （实测 [split $v] 拿不到第二段，会把整条链读成 0）；直接把整串打出来，
// 由 Node 侧按 "地址: 数据" 解析。
const VAL_RE = /VAL\s*[0-9a-fA-F]{1,8}:\s*([0-9a-fA-F]{1,8})/;
const READ = (addr) => `puts "VAL [mrd -force ${addr} 1]"`;

function clrScript(keepVal) {
  // 拉高 250 ms 再落下：gapclr 是电平，链路里已经 3FF 同步，短脉冲会被拉长到安全宽度
  return [...HEAD,
    `mwr -force ${GPIO0} 0x${(((keepVal | (1 << CLR_BIT)) >>> 0)).toString(16)} 32`,
    'after 250',
    `mwr -force ${GPIO0} 0x${(keepVal >>> 0).toString(16)} 32`,
    'after 50'].join('\n') + '\n';
}

function passScript(lanes, restoreTo, keep) {
  const L = [...HEAD];
  for (const n of lanes) {
    L.push(`mwr -force ${GPIO0} 0x${((keep | (n << 27)) >>> 0).toString(16)} 32`);
    L.push('after 20');
    L.push(`puts "LANE ${n}"`);
    L.push(READ(GPIO1));
  }
  if (restoreTo !== undefined) {
    L.push(`mwr -force ${GPIO0} 0x${(restoreTo >>> 0).toString(16)} 32`);
    L.push('catch {con}');                       // 只有最后一步才把 A9 放回去
  }
  return L.join('\n') + '\n';
}

function runXsdb(body, tag) {
  const tcl = dump(`health_${tag}.tcl`);
  const out = dump(`health_${tag}.out`);
  writeFileSync(tcl, body);
  try {
    execSync(`"${XSDB}" ${tcl} > "${out}" 2>&1`, { windowsVerbatimArguments: true });
  } catch (e) {
    console.log(`[HEALTH] xsdb(${tag}) 退出码 ${e.status}：${String(e.message).slice(0, 140)}`);
  }
  unlinkSync(tcl);
  const text = readFileSync(out, 'utf8').replace(/\r\n/g, '\n');
  if (/^error|no targets|cannot|invalid target/im.test(text.split('\n').slice(0, 8).join('\n'))) {
    console.log('[HEALTH] xsdb 报错，前几行：\n' + text.split('\n').slice(0, 8).join('\n'));
    console.log('[HEALTH] 先确认：板子有电、bit 已下载、hw_server 在跑（HOST_GUIDE.md）');
    process.exit(1);
  }
  return text;
}

// 第 0 步：把 GPIO_0 当前值读回来，后面原样还回去。
// 读不到就必须**直接退出**：第一版在这里失败后继续往下写，结果 keep=0，
// 把 src_sel / effect_en / threshold 全清零了 —— 读诊断的脚本自己改掉了工况。
const curRaw = runXsdb([...HEAD, READ(GPIO0)].join('\n') + '\n', 'cur').match(VAL_RE);
if (!curRaw) {
  console.log('[HEALTH] 读不到 GPIO_0 的当前值，拒绝继续（否则会踩掉 src_sel/特效/阈值）。');
  console.log('[HEALTH] 先确认 JTAG 与 hw_server 可用：xsdb 里 mrd ' + GPIO0);
  process.exit(1);
}
const cur = parseInt(curRaw[1], 16) >>> 0;
const keep = cur & 0x07ffffff;                       // 清掉 bit[31:27]，保留控制位
if (CLR) { runXsdb(clrScript(keep), 'clr'); console.log('[HEALTH] 已把帧间隔统计归零（gpio_o[26] 拉高 250 ms）'); }
// V8-6 之后 lane25..29 也是真的读数（时延三段 + 最大/次数/钳位），不再是 0xDEADBEEF。
// lane24 = 屏上 Latency 那一格画的毫秒数，与 q_tot **同一轮**。
// ⚠ 顺序有意义，必须排在 25 之后：`system_top` 里 `lat_arm = (lane==25)` —— 指到 lane25 这件事
//   本身就是抄快照的触发。先读 24 会拿到**上一遍**武装的那一轮，与这一遍的 27 对不上，
//   于是下面那条同源判据恒红（假红，而且是脚本自己造成的）。
// 顺序是判据的一部分（见上面 lat 段的配对说明）：25 既是"轮次/钳位位"也是**武装位**，
// 所以 25 必须排在 26..29、24 之前。lane23 不参与武装（它是自己一路的快照总线），
// 放在 24 之后读只是让"缩放/时延"两组挨在一起 —— 插在 25 与 24 之间也不会错，但没必要。
const want = [...Array(10).keys(), 25, 26, 27, 28, 29, 24, 23, 30, 31];
const vals = new Map();
for (let p = 0; p < PASSES; p++) {
  const txt = runXsdb(passScript(want, p === PASSES - 1 ? cur : undefined, keep), `p${p}`);
  let lane = -1;
  for (const line of txt.split('\n')) {
    const m = line.match(/^LANE (\d+)$/);
    if (m) { lane = Number(m[1]); continue; }
    const v = line.match(VAL_RE);
    if (v && lane >= 0) {
      if (!vals.has(lane)) vals.set(lane, []);
      vals.get(lane).push(parseInt(v[1], 16) >>> 0);
      lane = -1;
    }
  }
}

const g = (n) => (vals.get(n) || [])[0];
const f16 = (v, hi) => v === undefined ? NaN : ((v >>> (hi ? 16 : 0)) & 0xffff);
const bit = (v, i) => v === undefined ? '?' : ((v >>> i) & 1) ? '1' : '0';

// --json：只吐一个机器可读的对象就退出。加这个模式不是为了好看 ——
// `src/host/metrics.mjs` 要把"推流 N 秒 → 读回计数器 → 算抖动/丢包"做成一条可复跑的命令，
// 而去解析上面那些中文判读行会把两个工具焊死在一起（改一句文案就崩）。
if (get('json', false) === true) {
  const l = {}; for (let n = 0; n < 10; n++) l['lane' + n] = g(n);
  const clk = g(31), src = g(30);
  const flags = l.lane7;
  console.log(JSON.stringify({
    gpio0: cur, clk, dbg_src: src,
    // lane30：仲裁**看得见的全部输入**（十六位都在 axi 域 ⇒ 读回不交跨域的税）：
    //   bit0 时基可信 / bit1 eth 活着 / bit2 屏幕归 ETH / bit3 PS 引擎搬运中
    //   bit4 ETH 引擎搬运中 / bit[6:5] 仲裁看到的模式（格雷码）/ bit[10:8] V8-7「为什么归 PS」
    // 为什么要给到七位：#28 第一次板级跑交接判据就红，而三位版本分不开
    // "模式被钉住 / 时基不可信 / both_idle 从不成立 / 判据说谎"四种解释（见 ISSUES #49）。
    // 再加 why_ps 三位把最后一格也填上：前三位说的是"输入现在长什么样"，
    // 后三位说的是"**做判决那一拍**看到了什么"（寄存器，见 src_arb.v）——两者不一致就说明
    // 换手被 busy 挡住了，而不是判据说谎。位序与台架 G1 表逐位对齐（tb_v796_src_arb.v）。
    src_state: decodeSrc(src),
    // lane23（V8-8 最后一跳）：像素域**正在用**的缩放状态 + 两条同源判据：
    //   ① 手动档（zman=1）：inv_scale 必须等于"256 ÷ 该档倍率"（由倍率定义推导，不查表）；
    //   ② 屏上 `Zoom:` 那一格画的 zcode 必须是 inv_scale 的最近档。
    // 两条合起来才叫"屏上写的倍率 = 取数器在用的倍率"；单独任何一条都不够（① 只证链路、
    // ② 只证显示，都抓不到"档号送错了但两边一致"这种错）。
    // alive=0 ⇒ 200 ms 没等到像素帧心跳 ⇒ 这 19 位是旧的：只报 STALE，不下结论。
    //（"不下结论"不等于通过 —— 命令行会在结尾把 STALE 单独列出来。）
    zoom: (() => {
      const w = g(23), z = decodeZoom(w);
      if (!z) return null;
      if (w === 0xDEADBEEF) return { raw: w, verdict: 'NO_LANE' };   // 老位流上没有这一口
      const out = { raw: w, ...z, x100_actual: z.alive ? +(25600 / z.inv_scale).toFixed(1) : null };
      if (!z.alive) { out.verdict = 'STALE'; return out; }
      if (z.zman) {
        out.inv_expected = inv_exp_of(z.zsel);
        out.inv_ok = (z.inv_scale === out.inv_expected);
        out.code_ok = (z.zcode === z.zsel);
      } else {
        out.inv_expected = null;          // 呼吸中：期望值每帧都在变，只对量程负责
        out.inv_ok = (z.inv_scale >= 128 && z.inv_scale <= 1023);
        out.code_ok = (z.zcode === near_of(z.inv_scale));
      }
      out.verdict = (out.inv_ok && out.code_ok) ? 'OK' : 'MISMATCH';
      return out;
    })(),
    drop_words: l.lane0,
    // V8-6 链路内时延。PL 只报**拍数**（不在硬件里做除法，理由见 frame_latency.v 文件头与 ISSUES #58），
    // 换算集中在这一个常量：fclk0 = 100 MHz ⇒ 1 拍 = 10 ns。换 fclk 频率只改这里，并同步改
    // build/tcl/build_system_axigpio.tcl 的 PCW_FPGA0_PERIPHERAL_FREQMHZ（两处不一致就会报偏心数）。
    //   lane29 c1（等消隐窗口） lane28 c2（整帧搬运） lane27 tot（提交→开始扫描）
    //   lane26 max（历轮最大） lane25 = {n_meas[15:0], 15'd0, clamped}
    //   lane24 = {14'd0, pair_ok, 本轮sticky, ms[15:0]} ← 屏上 Latency 那一格画的**就是**这个 ms
    // 口径：只有 PL 内部，且 tot 的第三段（等扫描）分辨率 = 一个显示帧 ⇒ 报数带 ±1 帧。
    lat: (() => {
      const NS_PER_CYC = 10;               // ← 唯一的换算点（100 MHz）
      const w29 = g(29), w28 = g(28), w27 = g(27), w26 = g(26), w25 = g(25);
      if ([w29, w28, w27, w26, w25].some(v => v === undefined)) return null;
      if ((w27 >>> 0) === 0xDEADBEEF) return null;      // 老位流没有这些 lane
      const CLAMP = 0xFFFFFFFF;
      const ms = c => (c === CLAMP ? null : +(c * NS_PER_CYC / 1e6).toFixed(3));
      const nmeas = (w25 >>> 16) & 0xFFFF, clamped = w25 & 1;
      // ---- V8-5 步 5 的同源判据：屏上那个数必须能由回读的拍数算出来 ----
      // 逐遍配对（第 i 遍的 lane24 配第 i 遍的 lane27 —— 同一遍、同一次武装抄的那一组）。
      // 只在这些条件下才判：pair_ok=1（武装那一拍 32 步除法已经收工，否则商还是上一轮的）、
      // 本轮 sticky=0（钳位轮的 ms 是饱和值不是测量值）、q_tot 不是钳位值。
      // 期望值里那个 `min(...,9999)` 是 RTL 饱和的镜像：tot > 999.9 ms 时屏上就该是 9999，
      // 不是"算错了"—— 所以判据照这个口径写，否则超长等待会报成假红。
      const pairs = [];
      // ⚠ 只有**六口都在**（每口都读到 PASSES 个值）才敢按下标配对：某一漏读时数组会错位，
      //   把第 0 遍的 ms 配上第 1 遍的 tot ⇒ 报出一个假红，而假红比不判更糟（它会让人去关这个判据）。
      const six = [24, 25, 26, 27, 28, 29];
      const aligned = six.every((n) => ((vals.get(n) || []).length) === PASSES);
      if (aligned) for (let i = 0; i < PASSES; i++) {
        const a = vals.get(24)[i], t = vals.get(27)[i];
        const usable = ((a >>> 17) & 1) === 1 && ((a >>> 16) & 1) === 0 && t !== CLAMP;
        const exp = Math.min(Math.floor(t / 100000), 9999);
        pairs.push({ usable, ok: usable && (a & 0xffff) === exp, ms: a & 0xffff, exp });
      }

      const usable = pairs.filter((x) => x.usable);
      const bad = usable.filter((x) => !x.ok);
      return {
        unit: 'cycles', ns_per_cycle: NS_PER_CYC,
        c1_cyc: w29, c2_cyc: w28, tot_cyc: w27, max_cyc: w26,
        c1_ms: ms(w29), c2_ms: ms(w28), tot_ms: ms(w27), max_ms: ms(w26),
        // 屏上 Latency 那一格（lane24）与 tot 是否同源。
        // ⚠ osd_ms_matches 在 usable=0 时是 null：**没判过就不算绿**（一条永远红不了的判据是假判据）。
        //   板级正常几乎总能配对（除法只有 32 拍，撞上的概率 ~1e-6），所以拿到 null 说明
        //   要么位流太老（没有 lane24），要么武装顺序被改坏了 —— 两种都得查，不是"跳过"。
        osd_ms: g(24) === undefined ? undefined : (g(24) & 0xffff),
        osd_ms_pair_ok: g(24) === undefined ? undefined : (g(24) >>> 17) & 1,
        osd_ms_sticky: g(24) === undefined ? undefined : (g(24) >>> 16) & 1,
        osd_ms_lanes_aligned: aligned,
        osd_ms_pairs_checked: pairs.length,
        osd_ms_pairs_usable: usable.length,
        osd_ms_mismatch: bad.length,
        osd_ms_matches_tot: usable.length === 0 ? null : bad.length === 0,
        // 第三段（搬完→开始扫描）由恒等式给出，不单独占一口。
        // ⚠ 恒等式 `tot = c1 + c2 + c3` 只有在**同一轮**的数上才成立：r51 之前读回口给的是 live 值，
        //    五个 lane 分五次读 ⇒ 会读到不同轮的碎片（板级 8 组里 4 组破功，见 ISSUES #59）。
        //    r51 起 lane25 那一读会把五口**同时**抄成快照，于是这里能反过来用它当判据：
        //    `torn` 在 r51 位流上必须永远是 false；它是 true 就说明读回口又变回"各读各的"了。
        torn: ![w29, w28, w27].some(v => v === CLAMP) && (w27 >>> 0) < ((w29 + w28) >>> 0),
        c3_ms: (![w29, w28, w27].some(v => v === CLAMP) && w27 >= w29 + w28)
                 ? +(((w27 - w29 - w28) * NS_PER_CYC) / 1e6).toFixed(3) : null,
        n_meas: nmeas, clamped: !!clamped,
        // n_meas 是 16 位的饱和计数：读到 65535 意思是"至少 65535 轮"（约 2 小时 @9 轮/秒），
        // 不是"正好 65535 轮"。别说成精确值 —— 数字的口径写在读数旁边，别等评委问。
        n_meas_saturated: nmeas === 0xFFFF,
        // 没量到 / 钳位过 / 一组不同源 ⇒ 只能当下界用，不许当"实测时延"念
        valid: nmeas > 0 && !clamped && w27 !== CLAMP &&
               !(![w29, w28, w27].some(v => v === CLAMP) && (w27 >>> 0) < ((w29 + w28) >>> 0)),
      };
    })(),
    frames_bad: l.lane1 === undefined ? NaN : f16(l.lane1, false),
    pkt_err:    l.lane1 === undefined ? NaN : f16(l.lane1, true),
    stall_ms:   l.lane2 === undefined ? NaN : f16(l.lane2, false),
    rows_miss_max: l.lane2 === undefined ? NaN : f16(l.lane2, true),
    gap_last:   l.lane3,
    gap_min:    l.lane4 === undefined ? NaN : f16(l.lane4, false),
    gap_max:    l.lane4 === undefined ? NaN : f16(l.lane4, true),
    gap_sum:    l.lane5, cdc_episodes: l.lane6, flags,
    pkts: l.lane8, bytes: l.lane9,
    hb_slow: clk === undefined ? '?' : (clk >> 1) & 1,
    hb_gone: clk === undefined ? '?' : clk & 1,
    flags_bits: { drop_seen: bit(flags, 0), abort_seen: bit(flags, 1), cdc_full_seen: bit(flags, 2),
                  stream_live: bit(flags, 3), gap_valid: bit(flags, 4) },
    passes: [...vals.entries()].map(([n, v]) => [n, v.length]),
  }));
  // GPIO_0 在最后一遍读取的脚本里已经还原成进入时的值（见上面 passScript 的 restoreTo），
  // 所以这里不需要再补一次写回。
  process.exit(0);
}

console.log(`GPIO_0=${GPIO0} 读回 0x${(cur >>> 0).toString(16)}（已还原），GPIO_1=${GPIO1}`);
console.log('lane  value       含义');
console.log('----  ----------  ----------------------------------------');
let torn = 0;
for (let n = 0; n < 10; n++) {
  const vs = vals.get(n);
  if (!vs || !vs.length) { console.log(`${String(n).padStart(4)}  (读不到)`); continue; }
  let tag = '';
  if (PASSES > 1) {
    const moved = vs.some((x) => x !== vs[0]);
    if (MONO.has(n)) {
      // 单调 lane 只在"变小"时是撕烈；变大说明计数器还在走，正是链路活着的证据
      const back = vs.some((x, i) => i > 0 && x < vs[i - 1]);
      if (back) { tag = '   <== 撕烈：单调计数器变小了'; torn++; }
      else tag = moved ? '   增长中 ok' : '   ok';
    } else {
      tag = moved ? '   实时值，两遍不同属正常' : '   ok';
    }
  }
  console.log(
    `${String(n).padStart(4)}  0x${vs[0].toString(16).padStart(8, '0')}  ${LANES[n][0]}${tag}`);
  console.log(`      ${''.padEnd(10)}${LANES[n][1]}`);
}
const clk = g(31);
const src = g(30);
const stall = g(2), drop = g(0), flags = g(7);
const gone = (clk === undefined) ? -1 : (clk & 1);
const slow = (clk === undefined) ? -1 : ((clk >>> 1) & 1);
if (src !== undefined) {
  const s = decodeSrc(src);   // 与 --json 走同一个函数：两处各写一遍移位就会各说一套话
  console.log(`  30  0x${src.toString(16).padStart(8, '0')}  片源仲裁：屏幕归` +
    ` ${s.owner_eth ? 'ETH' : 'PS'}，eth_live=${s.eth_live} 时基可信=${s.eth_tb_ok}` +
    ` 模式=${({ AUTO: '自动', LOCK_ETH: '锁ETH', LOCK_PS: '锁PS', LOCK_CARD: '锁图卡' })[s.mode] ?? s.mode}` +
    ` 搬运中: PS=${s.fill_busy} ETH=${s.row_busy}` +
    // V8-7：判决那一拍看到的三个原因位。PS 拿着屏幕却读不出原因 ⇒ 才是真的"判据说谎"
    ` 原因(判决拍)=0b${s.why_gray.toString(2).padStart(3, '0')}：${s.why}`);
}
console.log(`  31  ${clk === undefined ? '(读不到)' : '0x' + clk.toString(16).padStart(8, '0')}  ` +
            `eth_rxc 心跳：${gone === -1 ? '(读不到)' : gone ? '已停 —— 源时钟没有' : slow ? '被拉慢 ~50× ⇒ 网线已拔/PHY 断链' : '正常'}`);
console.log('');
// V8-6/V8-5：链路内时延这一段单独判，因为**屏上画的数**也在这一组里 —— 两者不同源就说明
// 读回口又变回"各读各的"了（#59），或 OSD 那一格接错了轮次。
{
  const c1 = g(29), c2 = g(28), tt = g(27), cx = g(26);
  const st = g(25), qm = g(24);
  if ([c1, c2, cx, tt, st, qm].some((v) => v === undefined) || (tt >>> 0) === 0xDEADBEEF) {
    console.log('时延：这个位流没有 lane24..29（V8-6 之前的位流）—— 屏上 Latency 也必然是 `--`。');
  } else {
    const CL = 0xFFFFFFFF, n = (st >>> 16) & 0xFFFF;
    const pairOk = (qm >>> 17) & 1, sticky = (qm >>> 16) & 1, omd = qm & 0xffff;
    const exp = Math.min(Math.floor(tt / 100000), 9999);
    console.log(`时延：c1=${c1} c2=${c2} tot=${tt} max=${cx} 拍（${(tt / 1e5).toFixed(2)} ms）` +
                ` 轮数=${n === 0xFFFF ? '≥65535' : n}${st & 1 ? ' 会话内钳位过(当下界)' : ''}`);
    console.log(`  屏上 Latency=${pairOk ? (sticky ? '--(本轮钳位)' : omd + 'ms') : '--(武装撞上除法那 32 拍)'}` +
      `  回读 tot/100000=${exp}  ⇒ ` +
      (!pairOk ? '这一组不可判（重读一次）'
               : sticky ? '本轮不可判（钳位）'
               : omd === exp ? '同源一致 ok'
               : `不一致 ← 屏上数字与回读不是同一轮，别把屏上那个数写进报告`));
    if (c1 !== CL && c2 !== CL && tt !== CL && tt < c1 + c2)
      console.log('  ⚠ 恒等式 tot>=c1+c2 破了 ⇒ 读回口不是同一组（ISSUES #59 的形状）');
  }
}
// V8-8（lane23）：缩放这一组单独判"**屏上写的倍率 = 取数器在用的倍率**"。
// 两条判据缺一不可：只判 inv 对不上档 ⇒ 抓不到"送错档但算得自洽"；只判屏上档 ⇒ 抓不到
// "屏上与寄存器一致但取数器还在用旧值"（那正是 r53 之前唯一缺的那一跳）。
{
  const w = g(23), z = decodeZoom(w);
  if (!z || (w >>> 0) === 0xDEADBEEF)
    console.log('缩放：这个位流没有 lane23（r54 之前的位流）—— 手动缩放只剩"寄存器写了"那一半证据。');
  else if (!z.alive)
    console.log(`缩放：lane23=0x${(w >>> 0).toString(16).padStart(8, '0')} 像素时基 200 ms 没心跳 ⇒ 这一组是旧值，不下结论（不是通过）`);
  else {
    const e = z.zman ? inv_exp_of(z.zsel) : null;
    const invOk = z.zman ? (z.inv_scale === e) : (z.inv_scale >= 128 && z.inv_scale <= 1023);
    const codeOk = z.zman ? (z.zcode === z.zsel) : (z.zcode === near_of(z.inv_scale));
    console.log(`  23  0x${(w >>> 0).toString(16).padStart(8, '0')}  缩放：实际 ${(256 / z.inv_scale).toFixed(3)}x` +
      `（inv=${z.inv_scale}${z.zman ? ` 期望 ${e}` : ' 呼吸中，只卡量程'}）屏上画 ${(ZOOM_X100[z.zcode] / 100).toFixed(2)}x` +
      ` 档${z.zsel}${z.zsel === z.zcode ? '=' : '≠'}屏${z.zcode} zman=${z.zman} active=${z.zoom_active} dir=${z.zoom_dir}`);
    console.log('  ⇒ ' + (invOk && codeOk ? '链路末端与屏上同一档 ok'
      : `不一致（inv ${invOk ? 'ok' : '红'} / 屏上档 ${codeOk ? 'ok' : '红'}）—— 屏上那个倍率不许写进报告`));
  }
}
console.log('');
const fl = [
  '丢过字=' + bit(flags, 0), '作废过帧=' + bit(flags, 1), 'CDC灌满过=' + bit(flags, 2),
  '流活着=' + bit(flags, 3), '间隔已校准=' + bit(flags, 4),
].join('  ');
console.log(`判读：drop_words=${drop}  stall_ms=${f16(stall, false)}  缺行峰值=${f16(stall, true)}  ${fl}`);
if (slow === 1) {
  console.log("结论：链路已断 —— RXC 被 PHY 拉到约 1/48，stall_ms 此刻只是序指标，不是毫秒。");
} else if (drop === 0 && gone === 0 && slow === 0) {
  console.log('结论：入包链一个字都没丢 —— 这正是屏幕上看不出来的那部分证据。');
} else if (gone === 1) {
  console.log('结论：eth_rxc 没有时钟，此刻 stall/frames 全不可信，先查物理链路。');
} else {
  console.log(`结论：丢了 ${drop} 个字。上游太快或 HP0 被长时间占用，对照 video_sender 的限速与拷贝窗口。`);
}
if (torn) console.log(`警告：${torn} 条单调 lane 出现「变小」，那是跨域采到刷新瞬间 —— 重读确认，别记进报告。`);
