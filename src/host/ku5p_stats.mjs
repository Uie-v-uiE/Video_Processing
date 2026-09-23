#!/usr/bin/env node
/**
 * ku5p_stats.mjs — 收 KU5P 板的 UDP 遥测包并打印成一行（无需 numpy/python）
 *
 * 用法: node src/host/ku5p_stats.mjs [--port 1234] [--bind 0.0.0.0] [--once] [--watch 3] [--selftest]
 *
 * 线上格式与 ku5p/src/rtl/ku5p_telem.v 的文件头一一对应（**两处必须一起改**）：
 *   [0:3]='KU5P' [4]=版本 [5]=标志位 [6:7]=宽 [8:9]=高
 *   [10:13]=完整帧 [14:17]=包数 [18:21]=载荷字节 [22:25]=错包 [26:29]=越界字节
 *   [30:31]=本帧缺行 [32:35]=上电秒数    （全部大端）
 *
 * 两个线上事实（都由 sim/tb_ku5p_telem.v 逐字节量过，不是猜的）：
 *   1) 端口是厂商 udp_tx 里写死的 1234（`ip_head[5] <= {16'd1234,16'd1234}`），不可配；
 *   2) IP 头校验和是**算过的**（台架按一补数和验等于 0xFFFF），UDP 校验和恒 0（IPv4 允许）。
 *      所以 Linux 也能收 —— 明天如果在 Linux 上抓不到包，先查 ARP（板子按设计不往没学到
 *      的对端发）和端口占用，而不是怀疑校验和。
 *   板上要先 ARP 学到 PC（`ping 192.168.1.11` 一下即可），否则固件按设计不发遥测。
 */
import dgram from 'node:dgram';

function get(name, def) {
  const i = process.argv.indexOf('--' + name);
  if (i < 0) return def;
  const nxt = process.argv[i + 1];
  return nxt && !nxt.startsWith('--') ? nxt : true;
}

const PORT = Number(get('port', 1234));
const BIND = String(get('bind', '0.0.0.0'));
const ONCE = get('once', false) === true;
const WATCH = Number(get('watch', 0));      // --watch N：N 秒内没收到包就报失败退出

const FLAGS = ['link_up', 'frames_seen', 'abort_seen', 'data_alive'];
let last = null;      // {frames, secs} —— 用来算 fps 与丢包间隔
let got = 0;
let timer = null;

function decode(b, rinfo) {
  if (b.length < 36) return `包太短 ${b.length} B（期望 ≥36 B 载荷）`;
  const magic = String.fromCharCode(b[0], b[1], b[2], b[3]);
  if (magic !== 'KU5P') return `魔数不对: ${JSON.stringify(magic)} —— 端口上有人在发别的东西`;
  const u32 = (o) => b.readUInt32BE(o);
  const ver = b[4];
  // 两个版本都要能解：手里可能有旧 bit。v2 多了 6 个命令字段，而且**计数含义变了**
  // （CLR 之后是"自上次 CLR 以来"的差值），所以不能只是"多印六个数"。
  if (ver >= 2 && b.length < 42) return `v${ver} 需要 42 B 载荷，只到 ${b.length} B —— 板子与解析器版本不匹配`;
  const flags = b[5];
  const on = FLAGS.filter((_, i) => flags & (1 << i));
  const frames = u32(10), pkts = u32(14), bytes = u32(18), bad = u32(22), oob = u32(26);
  const rows = b.readUInt16BE(30), secs = u32(32);
  let cmdTxt = '';
  let sinceClr = '';
  if (ver >= 2) {
    const cok = b.readUInt16BE(36), cbad = b.readUInt16BE(38), per = b[40], f2 = b[41];
    cmdTxt = ` cmds=${cok}/${cbad} period=${per}s`;
    if (f2 & 2) sinceClr = '[自上次 CLR]';        // 基线推过 ⇒ 上面四个计数是差值
    if (!(f2 & 1) && cok === 0) cmdTxt += ' (没收到过命令)';
  }
  let extra = '';
  if (last) {
    const dF = frames - last.frames, dS = secs - last.secs;
    extra = dS > 0 ? `  Δframes=${dF} (${(dF / dS).toFixed(2)} fps)` : `  Δframes=${dF}`;
    // CLR 会让 frames 突然变小 —— 那是命令的效果，不是计数回绕，别报错误的诊断
    if (dF < 0) extra += sinceClr ? ' [CLR 推了基线]' : ' [计数回绕]';
  }
  // bad 的口径：v2 起收侧是 FCS 判定（ISSUES #38 结案），所以它可以当证据；
  // 但仍要说清"FCS 只保证介质上没打坏，不保证内容合规"（后者是 rows_miss/oob）。
  const badTxt = `bad=${bad}${ver >= 2 ? '(FCS)' : '(未接FCS判定)'}`;
  last = { frames, secs };
  return `${rinfo.address}:${rinfo.port} v${ver} ${b.readUInt16BE(6)}x${b.readUInt16BE(8)}`
       + ` frames=${frames}${sinceClr} pkts=${pkts} bytes=${bytes} ${badTxt} oob=${oob}`
       + ` rows_miss=${rows} up=${secs}s flags=[${on.join(',') || '-'}]${cmdTxt}${extra}`;
}

const sock = dgram.createSocket({ type: 'udp4', reuseAddr: true });

// --selftest：不打板子也能验证"PC 侧解析器与 RTL 的线上格式对得上"——
// 这里按 ku5p_telem.v 的注释手工拼包，期望被原样解出来（防止两边各改一半）。
// 三个方向都要测：v1 仍要能解（手里可能有旧 bit）、v2 的六个新字段要解对、
// 以及**v2 被截短时必须拒绝**（否则字段错位会安静地印出一堆假数字）。
if (get('selftest', false) === true) {
  const mk = (n, ver) => { const b = Buffer.alloc(n); b.write('KU5P', 0, 'ascii'); b[4] = ver; return b; };
  const body = (b, frames, pkts, bytes, bad, oob, rows, secs) => {
    b[5] = 0b1010;                                     // bit1 frames_seen + bit3 data_alive
    b.writeUInt16BE(512, 6); b.writeUInt16BE(300, 8);
    b.writeUInt32BE(frames, 10); b.writeUInt32BE(pkts, 14); b.writeUInt32BE(bytes, 18);
    b.writeUInt32BE(bad, 22); b.writeUInt32BE(oob, 26);
    b.writeUInt16BE(rows, 30); b.writeUInt32BE(secs, 32);
  };
  let bad2 = 0;
  const need = (tag, line, list) => {
    const miss = list.filter((w) => !line.includes(w));
    if (miss.length) { bad2++; console.log(`FAIL ${tag} 缺 ${miss.join(',')}\n     行: ${line}`); }
    else console.log(`PASS ${tag}`);
  };

  const b1 = mk(36, 1); body(b1, 4321, 65535, 2000000000, 7, 9, 3, 120);
  last = null;
  need('v1 载荷（旧 bit 仍要能读）', decode(b1, { address: '127.0.0.1', port: 1234 }),
       ['v1', '512x300', 'frames=4321', 'pkts=65535', 'bytes=2000000000',
        'bad=7(未接FCS判定)', 'oob=9', 'rows_miss=3', 'up=120s', 'frames_seen,data_alive']);

  const b2 = mk(42, 2); body(b2, 100, 250, 30700, 2, 3, 7, 120);
  b2.writeUInt16BE(3, 36); b2.writeUInt16BE(1, 38); b2[40] = 5; b2[41] = 0b11;
  last = null;
  need('v2 载荷（命令字段）', decode(b2, { address: '127.0.0.1', port: 1234 }),
       ['v2', 'frames=100[自上次 CLR]', 'cmds=3/1', 'period=5s', 'bad=2(FCS)', 'oob=3']);

  need('v2 被截短必须拒绝', decode(b2.subarray(0, 40), { address: '127.0.0.1', port: 1234 }),
       ['不匹配']);

  // CLR 之后计数会突然变小：那是命令的效果，不能报成"计数回绕"
  last = null;
  const b3 = mk(42, 2); body(b3, 9000, 9, 9, 9, 9, 9, 130);
  const b4 = mk(42, 2); body(b4, 12, 9, 9, 9, 9, 9, 131);
  b4.writeUInt16BE(4, 36); b4.writeUInt16BE(0, 38); b4[40] = 1; b4[41] = 0b11;
  decode(b3, { address: '127.0.0.1', port: 1234 });
  need('CLR 后的下跳不误报回绕', decode(b4, { address: '127.0.0.1', port: 1234 }),
       ['CLR 推了基线']);

  console.log(bad2 ? `FAIL ku5p_stats selftest (${bad2} 组红)` : 'PASS ku5p_stats selftest');
  process.exit(bad2 ? 1 : 0);
}

sock.on('message', (b, rinfo) => {
  got++;
  console.log(`[KU5P${got % 2 ? '' : '#'}] ${decode(b, rinfo)}`);
  if (WATCH > 0) {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
      console.log(`[KU5P] ${WATCH}s 内没再收到包 —— 板子停了、线拔了，或没学到 ARP`);
      process.exit(got ? 0 : 1);
    }, WATCH * 1000);
  }
});
sock.on('error', (e) => { console.error('[KU5P] ' + e.message); process.exit(1); });
sock.bind(PORT, BIND, () => {
  console.log(`[KU5P] 监听 udp://${BIND}:${PORT}（板子发完 ARP 学到对端后每秒一包）`);
  if (ONCE) console.log('[KU5P] --once：收到一包就退出');
});
if (ONCE) setInterval(() => { if (got) process.exit(0); }, 200);
