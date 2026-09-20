#!/usr/bin/env node
/**
 * video_sender.mjs — 与 host/video_sender.py 同协议的 UDP 推流（无需 numpy/python）
 *
 * 协议: 每包 [u32 LE byte_offset][RGB565 载荷], 载荷 <= 1392 B（8 的倍数）
 * 用法: node video_sender.mjs [--ip 192.168.1.10] [--port 5001]
 *                             [--src 192.168.1.100] [--fps 15]
 *                             [--pace-mpbps 15] [--no-pace] [--count N]
 *                             [--test bars|grad|edge]
 *
 * --test 图案：
 *   bars   8px 横向条纹整体滚动（黑横纹一眼可见）+ 每帧右移的黄色方块（拖影判据）
 *          + 左边缘 8 列奇偶行洋红/黑标记（行序错乱判据）
 *   grad   缓变渐变（查量化/色带）
 *   edge   整屏逐帧黑白交替（查换帧是否原子：非原子会看到灰行或残影）
 */
import dgram from 'node:dgram';
import { writeFileSync } from 'node:fs';

const W = 512, H = 300, FRAME_BYTES = W * H * 2, HDR = 4;
// 载荷必须是 8 的倍数：见 video_sender.py 里 MTU_PAYLOAD 的注释（否则每包边界会毁掉一个 64bit DDR 字）
// --mtu-payload 1396 是用来**复现**这个错误的（A/B 对照实验用），不是让你日常这么发。
const MTU = Number(get('mtu-payload', 1392));
if (MTU % 8) console.log(`[TX] 警告：MTU_PAYLOAD=${MTU} 不是 8 的倍数，包边界会毁掉 64bit 字（规律黑点）`);

function get(name, def) {
  const i = process.argv.indexOf('--' + name);
  if (i < 0) return def;
  const nxt = process.argv[i + 1];
  return nxt && !nxt.startsWith('--') ? nxt : true;
}
const IP = String(get('ip', '192.168.1.10'));
const PORT = Number(get('port', 5001));
const SRC = String(get('src', '192.168.1.100'));
const FPS = Number(get('fps', 15));
const NO_PACE = get('no-pace', false) === true;
const PACE = NO_PACE ? 0 : Number(get('pace-mpbps', 15));
const COUNT = Number(get('count', 0));
const TEST = String(get('test', 'bars'));
// --dump <文件>：把最后两帧写到 <文件> 和 <文件>.prev，供 host/ddr_verify.mjs --ref 逐字节比对
const DUMP = typeof get('dump', null) === 'string' ? String(get('dump', '')) : null;
let lastFrame = null;

const buf = Buffer.alloc(FRAME_BYTES);

function put(x, y, r, g, b) {
  buf.writeUInt16LE(((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3), (y * W + x) * 2);
}

function build(n) {
  if (TEST === 'move') {
    // 一次同时判两件事：
    //  · 方块只在白象限内部往返（永不触边、永不跨参考线）⇒ 看到重影/拖尾就是换帧不原子
    //  · 蓝象限铺 4 像素粗网格 ⇒ 若粗网格在右屏不再闪烁，说明之前的细线闪烁是
    //    最近邻缩放的走样（1px 线落到采样间隙），不是数据问题
    const bx = 270 + (1 - Math.cos(n * 0.10)) * 70;   // 270..410，白象限内往返
    const b0 = Math.round(bx);
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        let rgb;
        if (y < 150) rgb = (x < 256) ? [255, 0, 0] : [0, 255, 0];
        else         rgb = (x < 256) ? [0, 0, 255] : [255, 255, 255];
        if (y >= 160 && y < 300 && x >= 8 && x < 248 &&
            ((x % 32) < 4 || (y % 32) < 4)) rgb = [255, 255, 255];
        if (x < 2 || x >= W - 2 || y < 2 || y >= H - 2) rgb = [255, 255, 255];
        if (x === 256 || x === 257 || y === 150 || y === 151) rgb = [0, 0, 0];
        if (x >= b0 && x < b0 + 50 && y >= 190 && y < 240) rgb = [255, 0, 0];
        put(x, y, rgb[0], rgb[1], rgb[2]);
      }
    }
    return buf;
  }
  if (TEST === 'frameid') {
    // 每个 16bit 像素 = (字号 + 帧号) ⇒ 回读 DDR 就能反解「这个字是第几帧写进去的」：
    // n_implied = (lane - w) & 0xffff。用来定量测换帧滞后与逐字混合程度。
    for (let w = 0; w < FRAME_BYTES / 8; w++) {
      const v = (w + n) & 0xffff;
      const o = w * 8;
      buf.writeUInt16LE(v, o); buf.writeUInt16LE(v, o + 2);
      buf.writeUInt16LE(v, o + 4); buf.writeUInt16LE(v, o + 6);
    }
    return buf;
  }
  if (TEST === 'hold') {
    // 内容完全与帧号无关（每帧一模一样）+ 方块固定居中：
    //   · 若屏幕上方块仍撕裂/带残影 ⇒ 显示数据通路问题（两帧相同不可能混出差异）
    //   · 若干净 ⇒ 之前的“撕裂”来自图案自身被裁切 / 或只在运动时才有换帧混合
    // 蓝象限里再铺 1 像素白网格（每 32 像素），用来查行级错位。
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        let rgb;
        if (y < 150) rgb = (x < 256) ? [255, 0, 0] : [0, 255, 0];
        else         rgb = (x < 256) ? [0, 0, 255] : [255, 255, 255];
        if (y >= 160 && y < 300 && x >= 8 && x < 248 && (x % 32 === 0)) rgb = [255, 255, 255];
        if (y >= 160 && y < 300 && x >= 8 && x < 248 && (y % 32 === 0)) rgb = [255, 255, 255];
        if (x < 2 || x >= W - 2 || y < 2 || y >= H - 2) rgb = [255, 255, 255];
        if (x === 256 || x === 257 || y === 150 || y === 151) rgb = [0, 0, 0];
        if (x >= 128 && x < 188 && y >= 200 && y < 260) rgb = [255, 255, 0];
        put(x, y, rgb[0], rgb[1], rgb[2]);
      }
    }
    return buf;
  }
  if (TEST === 'blocks') {
    // 大色块 + 单像素参考线：纯色场不会产生手机摩尔纹，所以屏幕上看到任何
    // 椒盐点都是真实数据问题；同时用来判断换帧是否原子、有没有拖影。
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        let rgb;
        if (y < 150) rgb = (x < 256) ? [255, 0, 0] : [0, 255, 0];
        else         rgb = (x < 256) ? [0, 0, 255] : [255, 255, 255];
        if (x < 2 || x >= W - 2 || y < 2 || y >= H - 2) rgb = [255, 255, 255]; // 边框
        if (x === 256 || x === 257) rgb = [0, 0, 0];                          // 竖参考线
        if (y === 150 || y === 151) rgb = [0, 0, 0];                          // 横参考线
        const cx = ((n * 6) % (W + 120)) - 60;
        if (x >= cx && x < cx + 60 && y >= 200 && y < 260) rgb = [255, 255, 0];
        put(x, y, rgb[0], rgb[1], rgb[2]);
      }
    }
    return buf;
  }
  if (TEST === 'wordid') {
    // 自描述图案：每个 64bit DDR 字（4 像素）填它自己的字号（可加偏移做相位位移，
    // 用来区分「这一帧真丢了」和「上一帧碰巧写过同样的值」）
    const add = Number(get('wordid-add', 0)) & 0xffff;
    for (let w = 0; w < FRAME_BYTES / 8; w++) {
      const v = (w + add) & 0xffff;
      const o = w * 8;
      buf.writeUInt16LE(v, o); buf.writeUInt16LE(v, o + 2);
      buf.writeUInt16LE(v, o + 4); buf.writeUInt16LE(v, o + 6);
    }
    return buf;
  }
  const phase = n % 64;
  const alt = (n & 1) ? 255 : 0;
  const cx = ((n * 7) % (W + 120)) - 60;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      if (TEST === 'edge') {
        put(x, y, alt, alt, alt);
      } else if (TEST === 'grad') {
        put(x, y, (x + n * 2) & 255, (y * 2) & 255, 128);
      } else {
        if (((y + phase) >> 3) & 1) put(x, y, 255, 255, 255);
        else put(x, y, 0, 90, 200);
        if (x < 8) { if ((y >> 1) & 1) put(x, y, 255, 0, 255); else put(x, y, 0, 0, 0); }
        if (x >= cx && x < cx + 60 && y >= 140 && y < 200) put(x, y, 255, 255, 0);
      }
    }
  }
  return buf;
}

const sock = dgram.createSocket('udp4');
if (SRC) {
  try { sock.bind({ address: SRC, port: 0 }); }
  catch (e) { console.log(`[WARN] bind ${SRC} failed: ${e.message}, use default route`); }
}

// 绝对时间限速：帧内逐包匀速发出，避免 221 包以线速倾泻打爆板端入包 FIFO。
// 15 MB/s 下每包只有 ~93 µs 预算，Date.now() 的 1 ms 精度不够，用 performance.now()。
const _sab = new Int32Array(new SharedArrayBuffer(4));
const nowMs = () => performance.now();
function sleepMs(ms) { Atomics.wait(_sab, 0, 0, ms); }

let paceNext = nowMs();
function paceSpend(bytes) {
  if (!PACE) return;
  const target = paceNext + (bytes / (PACE * 1e6)) * 1000;
  if (target < nowMs()) { paceNext = nowMs(); return; }
  const wait = target - nowMs();
  if (wait > 2) sleepMs(wait - 1.5);
  while (nowMs() < target) { /* tail spin */ }
  paceNext = target;
}

function sendFrame(payload) {
  let pkts = 0;
  for (let off = 0; off < payload.length; off += MTU) {
    const chunk = payload.subarray(off, Math.min(off + MTU, payload.length));
    const p = Buffer.allocUnsafe(chunk.length + HDR);
    p.writeUInt32LE(off, 0);
    chunk.copy(p, HDR);
    sock.send(p, 0, p.length, PORT, IP);
    paceSpend(p.length);
    pkts++;
  }
  return pkts;
}

console.log(`[TX] ${IP}:${PORT} ${W}x${H} RGB565 @${FPS}fps test=${TEST} pace=${PACE} MB/s src=${SRC || 'default'}`);
const period = 1000 / FPS;
let n = 0, t0 = Date.now(), nextT = t0;

function tick() {
  build(n);
  sendFrame(buf);
  n++;
  if (n === 1) console.log(`[TX] first frame ${FRAME_BYTES} B = ${Math.ceil(FRAME_BYTES / MTU)} pkts`);
  if (DUMP) {                       // 保留最后两帧：乒乓两个 bank 各对应其一
    try { writeFileSync(DUMP + '.prev', lastFrame); } catch (e) {}
    lastFrame = Buffer.from(buf);
  }
  if (n % 30 === 0) {
    const dt = (Date.now() - t0) / 1000;
    console.log(`[TX] frames=${n} ~${(n / dt).toFixed(1)} fps`);
  }
  if (COUNT && n >= COUNT) {
    // 等内核把已排队的 sendto 真正发出去再关 socket，
    // 否则 --count 1~2 这种短测会把大部分包丢在发送队列里。
    console.log('[TX] waiting for the tx queue to drain ...');
    setTimeout(() => {
      if (DUMP && lastFrame) { try { writeFileSync(DUMP, lastFrame); } catch (e) { console.log('[TX] dump failed: ' + e.message); } }
      sock.close();
    }, 2000);
    return;
  }
  nextT += period;
  const d = nextT - Date.now();
  setTimeout(tick, d > 0 ? d : 0);
  if (d <= 0) nextT = Date.now();
}
tick();

process.on('SIGINT', () => { console.log(`\n[TX] sent ${n} frames`); sock.close(); process.exit(0); });
