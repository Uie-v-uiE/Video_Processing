#!/usr/bin/env node
/**
 * one_click_test.mjs —— 一键测试工具（上位机 §1.3 两类工具之一的 Node 侧；Python 同名实现见 one_click_test.py）。
 *
 * 用途：一条命令做完四步，每步打一行结论（判定词在行尾）：
 *   ① PING    板卡（--ip）
 *   ② CONNECT 连上读回口：板侧固件没有 UDP 回包 ⇒ 这条通路是 JTAG —— xsdb 把 lane 号写进 GPIO_0 的
 *             bit[31:27]、从 GPIO_1 读数（与 src/host/health_read.mjs 同一套 lane 与同一组基址），
 *             lane8 = 收到的 UDP 包数、lane9 = 收到的有效字节数；这里取它们的基线
 *   ③ SEND    发内置测试片源：把 data/inputs/ 的裸帧从 stdin 交给 src/host/video_sender.mjs
 *             （每包 [u32 LE 帧内偏移][RGB565 载荷] 的协议只有它一份，这里不重写）
 *   ④ COLLECT 再读一次 lane8/lane9，用增量和「应发的包数/字节数」对账，差额直接打出来
 * 输入：命令行参数（--help 有全表）+ 仓库根相对路径的片源文件。
 * 输出：stdout 每步一行 + 一行 `ONE-CLICK` 总结论；xsdb 的原始回读留在 data/measured/one_click_*.out。
 * 退出码：0=四步全 PASS；1=任一步 FAIL（ping 不通 / 读不到寄存器 / 账对不上）；2=参数或片源文件不对；
 *        --dry-run 只打印将要做什么（不 ping、不连板、不发包），恒 0。
 */
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { isAbsolute, join } from 'node:path';
import { dump, host, ROOT } from './repo_path.mjs';

const FRAME_BYTES = 512 * 300 * 2;                       // 与 src/host/video_sender.mjs 的 W/H/RGB565 同源
const MTU = 1392;                                        // 每包载荷上限（必须是 8 的倍数，理由见那支的文件头）
const PKTS_PER_FRAME = Math.ceil(FRAME_BYTES / MTU);     // 221 包/帧（udp_sink_check.mjs 用的是同一个数）

const DEFS = {
  ip: '192.168.1.10', port: '5001', clip: 'data/inputs/wordid_512x300.rgb565',
  frames: '5', fps: '15', 'pace-mbps': '15',
  gpio0: '41200000', gpio1: '41210000', 'hw-port': '3121',
  xsdb: process.env.VP_XSDB || 'xsdb.bat',
};
const NAMES = Object.keys(DEFS);
const FLAGS = ['help', 'dry-run'];

const USAGE = [
  '用法：node src/host/one_click_test.mjs [参数]',
  '     （Python 同名实现：python src/host/one_click_test.py，四步与判定口径一致）',
  '四步各打一行结论，判定词 PASS/FAIL/NOT_MEASURED 放在行尾最后一个字段。',
  '退出码：0=四步全 PASS  1=任一步 FAIL  2=参数或片源文件不对  --dry-run 恒 0。',
  '',
  '参数（默认值就是代码里的取值）：',
  `  --ip        板卡地址：步骤 ① ping 它、步骤 ③ 发给它        默认 ${DEFS.ip}`,
  `  --port      UDP 目标端口（转给发送脚本）                    默认 ${DEFS.port}`,
  `  --clip      内置测试片源（仓库根相对路径）                  默认 ${DEFS.clip}`,
  `  --frames    发多少帧（片源不足则整片重复补足后截到该帧数）  默认 ${DEFS.frames}`,
  `  --fps       转给发送脚本的帧率：Python 侧 udp_push.py 按它分帧停，Node 侧 video_sender.mjs 的 stdin 模式只按 --pace-mbps 匀速    默认 ${DEFS.fps}`,
  `  --pace-mbps 发送限速 MB/s（保护板端入包 FIFO）              默认 ${DEFS['pace-mbps']}`,
  `  --gpio0     写 lane 号的 AXI GPIO_0 基址（十六进制，无 0x） 默认 ${DEFS.gpio0}`,
  `  --gpio1     读 lane 值的 AXI GPIO_1 基址（十六进制，无 0x） 默认 ${DEFS.gpio1}`,
  `  --hw-port   hw_server 的端口                                默认 ${DEFS['hw-port']}`,
  `  --xsdb      xsdb 可执行文件                                 默认 环境变量 VP_XSDB，没给则 ${'xsdb.bat'}`,
  '  --dry-run   只打印将要做什么：不 ping、不连板、不发包       默认关',
  '  --help      打印本用法                                      默认关',
].join('\n');

function arg(name, def) {
  const i = process.argv.indexOf('--' + name);
  if (i < 0) return def;
  const v = process.argv[i + 1];
  return (v === undefined || v.startsWith('--')) ? true : v;
}

// 一行结论 = `[步/4] 名字 读数…… 判定词`：判定词永远是最后一个字段（与 build/deliver_spec_check.mjs 同口径）
const line = (n, tag, fields, verdict) => console.log(`[${n}/4] ${tag} ${fields} ${verdict}`);
const say = (n, tag, fields, ok) => line(n, tag, fields, ok ? 'PASS' : 'FAIL');

if (arg('help', false) === true) { console.log(USAGE); process.exit(0); }

const unknown = process.argv.slice(2)
  .filter(a => a.startsWith('--') && !FLAGS.includes(a.slice(2)) && !NAMES.includes(a.slice(2)));
if (unknown.length) {
  say(0, 'SETUP', `未知参数=${unknown.join(',')} 可用=${[...NAMES, ...FLAGS].map(x => '--' + x).join(',')}（--help 有全表）`, false);
  process.exit(2);
}

const IP = String(arg('ip', DEFS.ip));
const PORT = Number(arg('port', DEFS.port));
const CLIP_REL = String(arg('clip', DEFS.clip));
const FRAMES = Number(arg('frames', DEFS.frames));
const FPS = Number(arg('fps', DEFS.fps));
const PACE = Number(arg('pace-mbps', DEFS['pace-mbps']));
const GPIO0 = '0x' + String(arg('gpio0', DEFS.gpio0));
const GPIO1 = '0x' + String(arg('gpio1', DEFS.gpio1));
const HWPORT = Number(arg('hw-port', DEFS['hw-port']));
const XSDB = String(arg('xsdb', DEFS.xsdb));
const DRY = arg('dry-run', false) === true;

const CLIP = isAbsolute(CLIP_REL) ? CLIP_REL : join(ROOT, CLIP_REL);
const bad = [];
if (!Number.isInteger(FRAMES) || FRAMES < 1) bad.push(`--frames=${FRAMES} 要 ≥1 的整数`);
if (!Number.isInteger(PORT) || PORT < 1 || PORT > 65535) bad.push(`--port=${PORT} 不是合法端口`);
if (!Number.isFinite(PACE) || PACE < 0) bad.push(`--pace-mbps=${PACE} 不是非负数`);
if (!Number.isFinite(FPS) || FPS <= 0) bad.push(`--fps=${FPS} 要 >0`);
let clipBytes = null;
if (!bad.length) {
  if (!existsSync(CLIP)) bad.push(`找不到片源 ${CLIP_REL}（相对仓库根；--clip 可指到 data/inputs/ 的另一个文件）`);
  else {
    clipBytes = readFileSync(CLIP);
    if (clipBytes.length < FRAME_BYTES) bad.push(`片源 ${CLIP_REL} 不足一帧（${clipBytes.length} B < ${FRAME_BYTES} B）`);
  }
}
if (bad.length) { say(0, 'SETUP', `参数检查 ${bad.join('；')}`, false); process.exit(2); }

// 要发的字节：整片重复补足后截到 FRAMES 帧 ⇒ 两实现喂给发送脚本的是**同一串字节**
const payload = (() => {
  const reps = Math.ceil((FRAMES * FRAME_BYTES) / clipBytes.length);
  const acc = [];
  for (let i = 0; i < reps; i++) acc.push(clipBytes);
  return Buffer.concat(acc, reps * clipBytes.length).subarray(0, FRAMES * FRAME_BYTES);
})();
const EXP_PKTS = FRAMES * PKTS_PER_FRAME;
const EXP_BYTES = FRAMES * FRAME_BYTES;

if (DRY) {
  const [p1, p2] = process.platform === 'win32' ? ['-n 1 -w 1000', '-c 1 -W 1'] : ['-c 1 -W 1', '-n 1 -w 1000'];
  line(1, 'PING', `将执行 ping ${p1} ${IP}，不通再试 ping ${p2} ${IP}（仍不通则整轮判红并退出 1） 未执行`, 'NOT_MEASURED');
  line(2, 'CONNECT', `将用 "${XSDB}" 连 hw_server localhost:${HWPORT}：读 ${GPIO0} 原值 → lane 号写 bit[31:27] → 从 ${GPIO1} 取 lane0/1/8/9 基线 → 原值写回 未执行`, 'NOT_MEASURED');
  line(3, 'SEND', `将执行 node src/host/video_sender.mjs --ip ${IP} --port ${PORT} --fps ${FPS} --pace-mbps ${PACE} --file - ；stdin=${CLIP_REL}×${FRAMES} 帧=${payload.length} B 预计 ${EXP_PKTS} 包 未执行`, 'NOT_MEASURED');
  line(4, 'COLLECT', `将再读一次 lane0/1/8/9，与预计 ${EXP_PKTS} 包 / ${EXP_BYTES} 字节对账 未执行`, 'NOT_MEASURED');
  console.log(`ONE-CLICK dry-run=true clip=${CLIP_REL} 存在=是 frames=${FRAMES} 预计包数=${EXP_PKTS} 预计字节=${EXP_BYTES} 未碰网络与板子 NOT_MEASURED`);
  process.exit(0);
}

/* ---------------- ① ping ---------------- */
// 两种写法都试一次（Windows 的 -n/-w 与 POSIX 的 -c/-W），与 video_sender.py 的 ping_host 同一对命令。
const TRY = process.platform === 'win32'
  ? [['-n', '1', '-w', '1000', IP], ['-c', '1', '-W', '1', IP]]
  : [['-c', '1', '-W', '1', IP], ['-n', '1', '-w', '1000', IP]];
let pingOk = false;
const pingTried = [];
for (const c of TRY) {
  const r = spawnSync('ping', c, { encoding: 'utf8' });
  pingTried.push(`ping ${c.join(' ')}`);
  if (!r.error && r.status === 0) { pingOk = true; break; }
}
say(1, 'PING', `ip=${IP} tried="${pingTried.join(' | ')}" reply=${pingOk ? '通' : '不通'} hint=查供电/网线/IP`, pingOk);
if (!pingOk) process.exit(1);

/* ---------------- ②④ 读回口（沿用 health_read.mjs 的 lane 通路） ---------------- */
// xsdb 的 mrd 返回形如 "41200000:   00010000" ⇒ 整串打出来由这里按 "地址: 数据" 解析（别在 Tcl 里 split）。
// 地址那一截**不进捕获组**：组 1 必须是数据（health_read.mjs 的 VAL_RE 就是这个形状）。
const VAL_RE = /VAL\s*[0-9a-fA-F]{1,8}:\s*([0-9a-fA-F]{1,8})/;
const HEAD = [
  `catch {connect -host localhost -port ${HWPORT}}`,
  `targets -set -filter {name =~ "*#0"}`,
  'catch {stop}',            // A9 停在断点时 mrd/mwr 走 CoreSight 直接打到 GPIO 从端口（health_read 同一套路）
  'after 100',
];
const READ = (addr) => `puts "VAL [mrd -force ${addr} 1]"`;

function runXsdb(lines, tag) {
  const tcl = dump(`one_click_${tag}.tcl`), out = dump(`one_click_${tag}.out`);
  writeFileSync(tcl, lines.join('\n') + '\n');
  try {
    spawnSync(`"${XSDB}" ${tcl} > "${out}" 2>&1`, { shell: true, windowsVerbatimArguments: true });
  } catch (e) { /* 回读全在 out 里，判定只看文件内容 */ }
  try { unlinkSync(tcl); } catch (e) { /* 临时脚本删不掉不影响判据 */ }
  return existsSync(out) ? readFileSync(out, 'utf8').replace(/\r\n/g, '\n') : '';
}

/** 读一组 lane：先把 GPIO_0 原值读回来，写完 lane 号再原样还回去 —— 不知道原值就写会踩掉 src_sel/特效/阈值。 */
function readLanes(lanes) {
  const cur = runXsdb([...HEAD, READ(GPIO0)], 'cur').match(VAL_RE);
  if (!cur) return { err: `读不到 ${GPIO0}（hw_server 没起 / 板子没电 / xsdb=${XSDB} 指错？）` };
  const curVal = parseInt(cur[1], 16) >>> 0;
  const keep = curVal & 0x07ffffff;
  const L = [...HEAD];
  for (const n of lanes) {
    L.push(`mwr -force ${GPIO0} 0x${((keep | (n << 27)) >>> 0).toString(16)} 32`);
    L.push('after 20');
    L.push(`puts "LANE ${n}"`);
    L.push(READ(GPIO1));
  }
  L.push(`mwr -force ${GPIO0} 0x${curVal.toString(16)} 32`);   // 原样还回去
  L.push('catch {con}');
  const v = new Map();
  let lane = -1;
  for (const line of runXsdb(L, 'lane').split('\n')) {
    const m = /^LANE (\d+)$/.exec(line.trim());
    if (m) { lane = Number(m[1]); continue; }
    const r = line.match(VAL_RE);
    if (r && lane >= 0) { v.set(lane, parseInt(r[1], 16) >>> 0); lane = -1; }
  }
  for (const n of lanes) if (!v.has(n)) return { err: `lane${n} 没读到值（data/measured/one_click_lane.out 里只有采到的那几条）` };
  return { cur: curVal, v };
}

const LANES = [0, 1, 8, 9];        // 0=drop_words 1=frames_bad|bad_pkts 8=pkts 9=bytes（定义见 health_read.mjs）
const base = readLanes(LANES);
if (base.err) {
  say(2, 'CONNECT', `xsdb="${XSDB}" hw_server=localhost:${HWPORT} 读回口拿不到 lane 值 reason=${base.err}`, false);
  process.exit(1);
}
const g = (n) => base.v.get(n);
say(2, 'CONNECT', `xsdb="${XSDB}" hw_server=localhost:${HWPORT} gpio0=${GPIO0} 原值=0x${(base.cur >>> 0).toString(16)} ` +
    `基线 lane8_pkts=${g(8)} lane9_bytes=${g(9)} lane0_drop_words=${g(0)} lane1_frames_bad=${g(1) & 0xffff}`, true);

/* ---------------- ③ 发送：把字节交给已有的发送脚本，协议不在这里重写 ---------------- */
const s = spawnSync(process.execPath,
  [host('video_sender.mjs'), '--ip', IP, '--port', String(PORT), '--fps', String(FPS),
   '--pace-mbps', String(PACE), '--file', '-'],
  { input: payload, encoding: 'utf8', timeout: 180000 });
const sout = String(s.stdout || '') + String(s.stderr || '');
// 发送脚本自己报的账：`[TX] stream end: N frames, M pkts (dropped D)`
const m = sout.match(/stream end: (\d+) frames, (\d+) pkts \(dropped (\d+)\)/);
const sentFrames = m ? Number(m[1]) : NaN;
const counted = m ? Number(m[2]) : NaN;          // 含被主动丢掉的
const sentDropped = m ? Number(m[3]) : NaN;
const sentPkts = m ? counted - sentDropped : NaN;
const sendOk = !!m && s.status === 0 && sentPkts === EXP_PKTS;
say(3, 'SEND', `via=src/host/video_sender.mjs clip=${CLIP_REL} frames=${FRAMES} 发出帧=${sentFrames} 发出包=${sentPkts} 主动丢包=${sentDropped} ` +
    `应发包=${EXP_PKTS}${sendOk ? '' : ` 发送脚本输出=${JSON.stringify(sout.split('\n').slice(0, 3).join(' | ').slice(0, 140))}`}`, sendOk);

/* ---------------- ④ 回收：增量对账 ---------------- */
const after = readLanes(LANES);
if (after.err) {
  say(4, 'COLLECT', `xsdb="${XSDB}" 读回失败 reason=${after.err} 差额=拿不到读数`, false);
  process.exit(1);
}
const d = (n) => after.v.get(n) - base.v.get(n);
const dPkts = d(8), dBytes = d(9);
const collectOk = dPkts === EXP_PKTS && dBytes === EXP_BYTES;
say(4, 'COLLECT', `lane8_pkts_delta=${dPkts} 应发=${EXP_PKTS} lane9_bytes_delta=${dBytes} 应发=${EXP_BYTES} ` +
    `差额_pkts=${dPkts - EXP_PKTS} 差额_bytes=${dBytes - EXP_BYTES} 期间 drop_words=${d(0)} frames_bad=${d(1) & 0xffff} bad_pkts=${(d(1) >>> 16) & 0xffff}`, collectOk);

const fails = (pingOk ? 0 : 1) + (sendOk ? 0 : 1) + (collectOk ? 0 : 1);   // ② 已经 PASS 才能走到这里
console.log(`ONE-CLICK steps=4 ip=${IP} clip=${CLIP_REL} frames=${FRAMES} 发出包=${sentPkts} pkts增量=${dPkts} bytes增量=${dBytes} 判红步数=${fails} ${fails === 0 ? 'PASS' : 'FAIL'}`);
process.exit(fails === 0 ? 0 : 1);
