#!/usr/bin/env node
/**
 * ku5p_cmd.mjs — 给 KU5P 板下**一条**命令，并等它的 ack（= 下一包遥测）
 *
 * 用法:
 *   node src/host/ku5p_cmd.mjs CLR                [--ip 192.168.1.11] [--timeout 4]
 *   node src/host/ku5p_cmd.mjs SNAP
 *   node src/host/ku5p_cmd.mjs SPD5                改成每 5 秒上报一次
 *   node src/host/ku5p_cmd.mjs SPD1 --no-ack       只管发不等（例如同板上还开着 ku5p_stats.mjs）
 *   node src/host/ku5p_cmd.mjs --selftest          不打板子，验证本地校验/编码/ack 解码
 *
 * 命令的**规则表**与 `ku5p/src/rtl/ku5p_cmd.v` 是同一份，两边都必须一起改：
 *   载荷 = 纯 ASCII，无长度前缀、无二进制头
 *   CLR / SNAP            三条命令里的两条脉冲型
 *   SPD<1..255>           上报周期；十进制 1~3 位，>255 由板上钳到 255，0 视为坏命令
 *   首尾空格/Tab/CR/LF    板上会忽略，本工具会**先自己 trim** 再校验
 *   其它一律拒发（宁可 PC 报错，也不要发出去让板子默默记一条 cmds_bad）
 *
 * ack 为什么可信：SNAP/CLR/SPD 都会让板子把当前状态打包回来源端口 1234，
 * 里面 [36:37]=cmds_ok、[38:39]=cmds_bad、[40]=当前周期 ⇒ "命令生效没有"是**读回来的**，
 * 不是"我发出去了所以应该生效了"。
 *
 * 端口这件事：板的源/目的端口都是厂商 udp_tx 写死的 1234，所以本工具要收 ack 就得占 1234；
 * 如果 ku5p_stats.mjs 正在监听，会 bind 失败 —— 那时用 `--no-ack`，去 stats 窗口里看
 * cmds/period 那两栏变化就是同一份证据。
 */
import dgram from 'node:dgram';

function get(name, def) {
  const i = process.argv.indexOf('--' + name);
  if (i < 0) return def;
  const nxt = process.argv[i + 1];
  return nxt && !nxt.startsWith('--') ? nxt : true;
}
const pos = process.argv.slice(2).filter((a) => !a.startsWith('--') &&
  (() => { const i = process.argv.indexOf(a); return !(i > 1 && process.argv[i - 1].startsWith('--')); })());

const IP     = String(get('ip', '192.168.1.11'));
const CPORT  = Number(get('port', 5002));       // 板上 udp_rx_parser 的 CMD_PORT
const LISTEN = Number(get('listen', 1234));     // 遥测的目的端口（厂商 udp_tx 写死）
const TMO    = Number(get('timeout', 4));
const NOACK  = get('no-ack', false) === true;

/** 与 RTL 同一条规则表的校验 + 编码。返回 {ok:true, buf} 或 {ok:false, why}。 */
export function encode(raw) {
  const s = String(raw).replace(/^[\s]+|[\s]+$/g, '');      // 板上也会忽略首尾空白
  if (s === '') return { ok: false, why: '空命令' };
  if (s === 'CLR' || s === 'SNAP') return { ok: true, buf: Buffer.from(s, 'ascii') };
  const m = /^SPD(\d{1,3})$/.exec(s);
  if (!m) return { ok: false, why: `不认识 "${s}"（只接受 CLR / SNAP / SPD<数字>）` };
  const n = Number(m[1]);
  if (n === 0) return { ok: false, why: 'SPD0：0 秒不是合法周期（板上也按坏命令计）' };
  return { ok: true, buf: Buffer.from('SPD' + m[1], 'ascii'), period: n > 255 ? 255 : n };
}

/** 从一包遥测里只取"命令通道那 6 个字节"（完整字段解析在 ku5p_stats.mjs，不重复一份）。 */
export function readAck(b) {
  if (b.length < 36) return { ok: false, why: `ack 包只有 ${b.length} B（连 v1 的 36 B 都不到）` };
  if (b.toString('ascii', 0, 4) !== 'KU5P') return { ok: false, why: '魔数不是 KU5P，端口上有人在发别的' };
  // 版本要先于长度判：手里可能有旧 bit，那时"没有命令字段"才是真话，
  // 报"包太短"会把人指向一条错线索（v1 本来就只有 36 B）。
  if (b[4] < 2) return { ok: false, why: `板子的载荷是 v${b[4]}（旧 bit，没有命令字段）` };
  if (b.length < 42) return { ok: false, why: `v${b[4]} 需要 42 B，只到 ${b.length} B —— 板子与工具版本不匹配` };
  return { ok: true, ver: b[4], cmdsOk: b.readUInt16BE(36), cmdsBad: b.readUInt16BE(38),
           period: b[40], flags2: b[41], frames: b.readUInt32BE(10), secs: b.readUInt32BE(32) };
}

// ---------------------------------------------------------------- selftest
if (get('selftest', false) === true) {
  let bad = 0;
  const t = (name, cond) => { if (!cond) { bad++; console.log('FAIL ' + name); } else console.log('PASS ' + name); };

  // 1) 规则表：与 sim/tb_v80_ku5p_cmd.v 里的 A/B 组**同一批用例**，两边必须给出同样的判定
  t('CLR 接受', encode('CLR').ok === true);
  t('SNAP 接受', encode('SNAP').ok === true);
  t('SPD5 接受并编码成 4 个 ASCII 字节',
    encode('SPD5').ok && encode('SPD5').buf.toString('hex') === '53504435');
  t('SPD12 编码 5 字节', encode('SPD12').buf.length === 5);
  t('首尾空白先 trim', encode('  CLR\r\n').ok && encode('  CLR\r\n').buf.toString() === 'CLR');
  t('SPD0 被拒（与板上同判）', encode('SPD0').ok === false);
  t('SPD1X 被拒', encode('SPD1X').ok === false);
  t('光秃秃 SPD 被拒', encode('SPD').ok === false);
  t('SNA 不被当成 SNAP（前缀不误匹配）', encode('SNA').ok === false);
  t('spd5 小写被拒（规则表大小写敏感，板上也是）', encode('spd5').ok === false);
  t('SPD999 由板上钳位，PC 侧预告钳后的值', encode('SPD999').period === 255);

  // 2) ack 解码：手工按 ku5p_telem.v 的表拼一包 v2
  const b = Buffer.alloc(42);
  b.write('KU5P', 0, 'ascii'); b[4] = 2; b[5] = 0b1111;
  b.writeUInt16BE(512, 6); b.writeUInt16BE(300, 8);
  b.writeUInt32BE(4321, 10); b.writeUInt32BE(1, 14); b.writeUInt32BE(2, 18);
  b.writeUInt32BE(3, 22); b.writeUInt32BE(4, 26);
  b.writeUInt16BE(5, 30); b.writeUInt32BE(120, 32);
  b.writeUInt16BE(7, 36); b.writeUInt16BE(2, 38); b[40] = 5; b[41] = 0b11;
  const a = readAck(b);
  t('ack 解出 cmds_ok=7 cmds_bad=2 period=5',
    a.ok && a.cmdsOk === 7 && a.cmdsBad === 2 && a.period === 5 && a.flags2 === 3);
  t('ack 的 frames 与 v2 的偏移没错位', a.ok && a.frames === 4321 && a.secs === 120);

  // 3) 三条反面对照：解不开时必须**说清为什么**，不能返回一个 0 值的"看着像 ack"
  t('短包被拒', readAck(b.subarray(0, 40)).ok === false);
  t('错魔数被拒', readAck(Buffer.from('XXXX' + b.subarray(4).toString('binary'), 'binary')).ok === false);
  t('v1（旧 bit）被明确告知没有命令字段',
    (() => { const v1 = Buffer.alloc(36); v1.write('KU5P', 0, 'ascii'); v1[4] = 1;
             const r = readAck(v1); return !r.ok && /v1/.test(r.why); })());

  console.log(bad ? `FAIL ku5p_cmd selftest (${bad})` : 'PASS ku5p_cmd selftest');
  process.exit(bad ? 1 : 0);
}

// ---------------------------------------------------------------- 正常路径
const cmd = pos[0];
if (!cmd) {
  console.log('用法: node src/host/ku5p_cmd.mjs <CLR|SNAP|SPD<n>> [--ip 192.168.1.11] [--timeout 4] [--no-ack]');
  console.log('     先跑 --selftest（不打板子就能验证 PC 侧与线上格式一致）');
  process.exit(2);
}
const enc = encode(cmd);
if (!enc.ok) { console.log(`FAIL 命令不合法：${enc.why}`); process.exit(2); }

const sock = NOACK ? null : dgram.createSocket({ type: 'udp4', reuseAddr: true });
const out  = dgram.createSocket('udp4');
const t0 = Date.now();
let done = false;

const finish = (code, msg) => {
  if (done) return;
  done = true;
  console.log(msg);
  try { out.close(); if (sock) sock.close(); } catch (e) { /* 已关 */ }
  process.exit(code);
};

if (sock) {
  sock.on('message', (b) => {
    const a = readAck(b);
    if (!a.ok) return;                              // 端口上可能还有别的东西，只认我们的包
    finish(0, `PASS ${cmd} -> ${IP}:${CPORT}，${((Date.now() - t0) / 1000).toFixed(2)}s 后收到 ack：`
            + `cmds_ok=${a.cmdsOk} cmds_bad=${a.cmdsBad} period=${a.period}s `
            + `frames=${a.frames} up=${a.secs}s flags2=${a.flags2.toString(2)}`
            + (enc.period !== undefined && a.period !== enc.period
               ? `  <WARN 板子回显的周期是 ${a.period}，与请求的 ${enc.period} 不符>` : ''));
  });
  sock.on('error', (e) => finish(1, `FAIL 监听 :${LISTEN} 失败：${e.message}`
                                    + '（同板上是否开着 ku5p_stats.mjs？加 --no-ack 用它看效果）'));
  sock.bind(LISTEN, '0.0.0.0', () => {
    out.send(enc.buf, 0, enc.buf.length, CPORT, IP, (err) => {
      if (err) finish(1, 'FAIL 发送失败：' + err.message);
    });
    setTimeout(() => finish(1, `FAIL ${TMO}s 内没有 ack：板子没学到 ARP（先 ping ${IP}）、`
                             + `CMD_PORT 不是 ${CPORT}、或线没插`), TMO * 1000);
  });
} else {
  out.send(enc.buf, 0, enc.buf.length, CPORT, IP, (err) => {
    if (err) finish(1, 'FAIL 发送失败：' + err.message);
    finish(0, `INFO ${cmd} 已发往 ${IP}:${CPORT}（--no-ack：效果请看 ku5p_stats.mjs 的 cmds/period 两栏）`);
  });
}
