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
const want = [...Array(10).keys(), 25, 26, 27, 28, 29, 30, 31];
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
    // lane30：仲裁**看得见的全部输入**（八位都在 axi 域 ⇒ 读回不交跨域的税）：
    //   bit0 时基可信 / bit1 eth 活着 / bit2 屏幕归 ETH / bit3 PS 引擎搬运中
    //   bit4 ETH 引擎搬运中 / bit[6:5] 仲裁看到的模式（格雷码）
    // 为什么要给到七位：#28 第一次板级跑交接判据就红，而三位版本分不开
    // "模式被钉住 / 时基不可信 / both_idle 从不成立 / 判据说谎"四种解释（见 ISSUES #49）。
    src_state: src === undefined ? null : {
      eth_tb_ok: src & 1, eth_live: (src >> 1) & 1, owner_eth: (src >> 2) & 1,
      fill_busy: (src >> 3) & 1, row_busy: (src >> 4) & 1,
      mode_gray: (src >> 5) & 3,
      mode: ({ 0: 'AUTO', 1: 'LOCK_ETH', 3: 'LOCK_PS', 2: 'LOCK_CARD' })[((src >> 5) & 3)] ?? 'BAD',
    },
    drop_words: l.lane0,
    // V8-6 链路内时延。PL 只报**拍数**（不在硬件里做除法，理由见 frame_latency.v 文件头与 ISSUES #58），
    // 换算集中在这一个常量：fclk0 = 100 MHz ⇒ 1 拍 = 10 ns。换 fclk 频率只改这里，并同步改
    // build/tcl/build_system_axigpio.tcl 的 PCW_FPGA0_PERIPHERAL_FREQMHZ（两处不一致就会报偏心数）。
    //   lane29 c1（等消隐窗口） lane28 c2（整帧搬运） lane27 tot（提交→开始扫描）
    //   lane26 max（历轮最大） lane25 = {n_meas[15:0], 15'd0, clamped}
    // 口径：只有 PL 内部，且 tot 的第三段（等扫描）分辨率 = 一个显示帧 ⇒ 报数带 ±1 帧。
    lat: (() => {
      const NS_PER_CYC = 10;               // ← 唯一的换算点（100 MHz）
      const w29 = g(29), w28 = g(28), w27 = g(27), w26 = g(26), w25 = g(25);
      if ([w29, w28, w27, w26, w25].some(v => v === undefined)) return null;
      if ((w27 >>> 0) === 0xDEADBEEF) return null;      // 老位流没有这些 lane
      const CLAMP = 0xFFFFFFFF;
      const ms = c => (c === CLAMP ? null : +(c * NS_PER_CYC / 1e6).toFixed(3));
      const nmeas = (w25 >>> 16) & 0xFFFF, clamped = w25 & 1;
      return {
        unit: 'cycles', ns_per_cycle: NS_PER_CYC,
        c1_cyc: w29, c2_cyc: w28, tot_cyc: w27, max_cyc: w26,
        c1_ms: ms(w29), c2_ms: ms(w28), tot_ms: ms(w27), max_ms: ms(w26),
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
if (src !== undefined)
  console.log(`  30  0x${src.toString(16).padStart(8, '0')}  片源仲裁：屏幕归` +
    ` ${(src >>> 2) & 1 ? 'ETH' : 'PS'}，eth_live=${(src >>> 1) & 1} 时基可信=${src & 1}` +
    ` 模式=${({ 0: '自动', 1: '锁ETH', 3: '锁PS', 2: '锁图卡' })[((src >>> 5) & 3)]}` +
    ` 搬运中: PS=${(src >>> 3) & 1} ETH=${(src >>> 4) & 1}`);
console.log(`  31  ${clk === undefined ? '(读不到)' : '0x' + clk.toString(16).padStart(8, '0')}  ` +
            `eth_rxc 心跳：${gone === -1 ? '(读不到)' : gone ? '已停 —— 源时钟没有' : slow ? '被拉慢 ~50× ⇒ 网线已拔/PHY 断链' : '正常'}`);
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
