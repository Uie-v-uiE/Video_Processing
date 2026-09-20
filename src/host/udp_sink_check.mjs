#!/usr/bin/env node
/**
 * udp_sink_check.mjs — 本机回环校验上位机自身：统计收到的 UDP 视频包/字节，
 * 并按 offset 检查是否有缺洞。用来把「上位机丢包」和「板端丢包」区分开。
 *
 *   终端1: node udp_sink_check.mjs --port 5001 --expect-frames 5
 *   终端2: node video_sender.mjs --ip 127.0.0.1 --src 127.0.0.1 --count 5
 */
import dgram from 'node:dgram';

function get(n, d) {
  const i = process.argv.indexOf('--' + n);
  if (i < 0) return d;
  const v = process.argv[i + 1];
  return v && !v.startsWith('--') ? v : true;
}
const PORT = Number(get('port', 5001));
const EXPECT = Number(get('expect-frames', 0));
const FRAME = 307200, HDR = 4;

const seen = new Map();          // frameSeq -> {pkts, bytes, holes:bitmap}
let cur = null, frames = 0, errs = 0;
function newFrame() { return { pkts: 0, bytes: 0, offs: new Set() }; }
cur = newFrame();

const sock = dgram.createSocket('udp4');
sock.on('message', (msg) => {
  if (msg.length <= HDR) { errs++; return; }
  const off = msg.readUInt32LE(0);
  if (off === 0 && cur.pkts) {      // 新帧开始
    seen.set(frames, cur); frames++; cur = newFrame();
  }
  cur.pkts++;
  cur.bytes += msg.length - HDR;
  cur.offs.add(off);
  if (EXPECT && frames >= EXPECT) done();
});

function done() {
  const expPkts = Math.ceil(FRAME / 1392);
  let ok = 0, bad = 0;
  for (const [n, f] of seen) {
    const gap = FRAME - f.bytes;
    if (f.bytes === FRAME) ok++; else { bad++; console.log(`  frame ${n}: bytes=${f.bytes} pkts=${f.pkts} missing=${gap}`); }
  }
  console.log(`[SINK] frames=${seen.size} complete=${ok} incomplete=${bad} err=${errs}` +
              ` (expect ${expPkts} pkts/frame)`);
  sock.close();
  process.exit(0);
}

sock.bind(PORT, '127.0.0.1', () => console.log(`[SINK] listening 127.0.0.1:${PORT}`));
setTimeout(() => { console.log('[SINK] timeout'); done(); }, Number(get('timeout-ms', 20000)));
