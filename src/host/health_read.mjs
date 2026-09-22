#!/usr/bin/env node
/**
 * health_read.mjs — V7.6 (P0-A) 从 PS 侧读回 PL 的链路健康快照。
 *
 * 硬件接口（不加 AXI 从设备，只用两个 GPIO）：
 *   · Lane 号写在**已存在**的 GPIO_0 的 bit[31:27]；脚本先读回 GPIO_0 的原值，
 *     只改这 5 位，最后再把原值写回去 —— effect_en/threshold/src_sel 不受影响。
 *   · 数据从新加的 GPIO_1（只读 32bit）读。
 *   · lane 0..9 = link_monitor 的快照；lane 31 = eth_rxc 心跳是否还在；
 *     其它 lane 号硬件返回 0xDEADBEEF，一眼能看出号写错了。
 *
 * 用法：
 *   node health_read.mjs [--gpio0 41200000] [--gpio1 41210000] [--once]
 *   前置：板子上电、bit 已下载、hw_server 在跑（见 HOST_GUIDE.md）。
 *   两个基地址在 build/v76_build.log 的 `ADDR GPIO0 = …` / `ADDR GPIO1 = …` 行里。
 *
 * 默认把 10 条 lane 读两遍并比对：AXI GPIO 的输入同步器有百万分之一的概率正好
 * 采样到快照刷新的一拍，两遍不一致就标出来，免得把撕烈的数字当成实测值记进报告。
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

// 必须与 src/rtl/eth/link_monitor.v 尾部 lane0..lane9 的顺序一致
const LANES = [
  ['drop_words',   '被 fifo_full 挡住而永久消失的 16bit 字数（板上唯一真实丢数据通道）'],
  ['bad|err',      '低16=被作废的帧数，高16=坏包数（上板 p_good 恒 1 ⇒ 坏包应为 0）'],
  ['stall|rows',   '低16=距上一个完整帧过了多少 ms，高16=作废帧最多缺几行'],
  ['gap_last',     '最近一帧间隔 ms（≈1000/fps）'],
  ['gap_min|max',  '低16=最小间隔，高16=最大间隔 ms'],
  ['gap_sum',      'Σ间隔 ms；平均 = gap_sum / (frames_ok - 1)'],
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

// mrd 的返回形如 "0x41200000\tdeadbeef"，取第二段
const READ = (addr) =>
  `set v [mrd -force ${addr} 1]; puts "VAL [lindex [split $v] 1]"`;

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

// 第 0 步：把 GPIO_0 当前值读回来，后面原样还回去
const cur = parseInt(
  (runXsdb([...HEAD, READ(GPIO0)].join('\n') + '\n', 'cur').match(/VAL ([0-9a-f]{1,8})/) || [])[1] || '0',
  16
);
const keep = cur & 0x07ffffff;                       // 清掉 bit[31:27]，保留控制位
const want = [...Array(10).keys(), 31];
const vals = new Map();
for (let p = 0; p < PASSES; p++) {
  const txt = runXsdb(passScript(want, p === PASSES - 1 ? keep : undefined, keep), `p${p}`);
  let lane = -1;
  for (const line of txt.split('\n')) {
    const m = line.match(/^LANE (\d+)$/);
    if (m) { lane = Number(m[1]); continue; }
    const v = line.match(/^VAL ([0-9a-f]{1,8})$/);
    if (v && lane >= 0) {
      if (!vals.has(lane)) vals.set(lane, []);
      vals.get(lane).push(parseInt(v[1], 16) >>> 0);
    }
  }
}

const g = (n) => (vals.get(n) || [])[0];
const f16 = (v, hi) => v === undefined ? NaN : ((v >>> (hi ? 16 : 0)) & 0xffff);
const bit = (v, i) => v === undefined ? '?' : ((v >>> i) & 1) ? '1' : '0';

console.log(`GPIO_0=${GPIO0} 读回 0x${(cur >>> 0).toString(16)}（已还原），GPIO_1=${GPIO1}`);
console.log('lane  value       含义');
console.log('----  ----------  ----------------------------------------');
for (let n = 0; n < 10; n++) {
  const vs = vals.get(n);
  if (!vs || !vs.length) { console.log(`${String(n).padStart(4)}  (读不到)`); continue; }
  const torn = vs.some((x) => x !== vs[0]);
  console.log(
    `${String(n).padStart(4)}  0x${vs[0].toString(16).padStart(8, '0')}  ${LANES[n][0]}` +
    (PASSES > 1 ? (torn ? '   <== 两遍不一致' : '   ok') : '')
  );
  console.log(`      ${''.padEnd(10)}${LANES[n][1]}`);
}
const clk = g(31);
const stall = g(2), drop = g(0), flags = g(7);
const gone = (clk === undefined) ? -1 : (clk & 1);
console.log(`  31  ${clk === undefined ? '(读不到)' : '0x' + clk.toString(16).padStart(8, '0')}  ` +
            `eth_rxc 心跳：${gone === -1 ? '(读不到)' : gone ? '已停 —— 先看网线/PHY' : '正常'}`);
console.log('');
const fl = [
  '丢过字=' + bit(flags, 0), '作废过帧=' + bit(flags, 1), 'CDC灌满过=' + bit(flags, 2),
  '流活着=' + bit(flags, 3), '间隔已校准=' + bit(flags, 4),
].join('  ');
console.log(`判读：drop_words=${drop}  stall_ms=${f16(stall, false)}  缺行峰值=${f16(stall, true)}  ${fl}`);
if (drop === 0 && gone === 0) {
  console.log('结论：入包链一个字都没丢 —— 这正是屏幕上看不出来的那部分证据。');
} else if (gone === 1) {
  console.log('结论：eth_rxc 没有时钟，此刻 stall/frames 全不可信，先查物理链路。');
} else {
  console.log(`结论：丢了 ${drop} 个字。上游太快或 HP0 被长时间占用，对照 video_sender 的限速与拷贝窗口。`);
}
