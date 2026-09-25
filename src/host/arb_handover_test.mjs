#!/usr/bin/env node
/**
 * arb_handover_test.mjs — 把"停流后 PL 自动把屏幕交回 PS"从**眼睛判据**变成**机器判据**。
 *
 * 为什么需要它：仲裁（`src/rtl/util/src_arb.v`）的结果以前只有两个观测渠道 —— 看屏幕、
 * 或看 OSD（也要眼睛）。于是 #24 收尾那两条判据（"停流会交回""不来回抖"）只能等有人
 * 坐在板子前面。`build#26` 起把 `{eth_tb_ok, eth_live, owner_eth}` 映到健康 GPIO 的 lane30，
 * 本脚本就只需要做一件事：**在已知时间点开关推流，同时按毫秒密度采样 lane30** ——
 * 判据于是变成"owner_eth 在第几毫秒翻了"，半夜也能自己跑。
 *
 * 覆盖范围要说清楚，别夸大：
 *   · 本脚本证明的是 **owner 位的交接时序**（谁拥有 AXI 读口 + 帧缓存写口）。
 *   · 它**不**证明屏幕上真有画面、也不证明画面不撕裂 —— 那两条仍然是眼睛的活（`board/README.md`）。
 *
 * 用法（前置：板子上电、目标 bit 已下载、hw_server 在跑、PC 网卡直连**PL 侧** RJ45）：
 *   node arb_handover_test.mjs                 # 完整一轮：静默→推流→停→再推
 *   node arb_handover_test.mjs --selftest      # 不打板子，只验判据本身（合成序列）
 * 可调：--pre 3 --stream 12 --after 15 --restart 8 --period-ms 100
 *       --settle-ms 2000 --handback-max-ms 1500 --ip 192.168.1.10 --fps 15
 *
 * 一个必须记住的副作用：连续采样要求 A9 **停在断点**（`stop`…`con`，与 health_read 同一套路），
 * 所以整轮测试期间 PS 不喂帧、串口不打字。这不影响本判据（交接只看 PL 里两个 busy 位
 * 和 eth 侧两位），但**别把这段时间当成"PS 活着时的观感"**。
 */
import { spawn, execSync, execFileSync } from 'node:child_process';
import { writeFileSync, readFileSync, appendFileSync, unlinkSync } from 'node:fs';
import { dump, host } from './repo_path.mjs';
import { join } from 'node:path';
import { ROOT } from './repo_path.mjs';

function get(name, def) {
  const i = process.argv.indexOf('--' + name);
  if (i < 0) return def;
  const nxt = process.argv[i + 1];
  return nxt && !nxt.startsWith('--') ? nxt : true;
}
const XSDB  = String(get('xsdb',  'D:\\Software\\Vivado\\2025.2.1\\Vitis\\bin\\xsdb.bat'));
const PORT  = Number(get('port',  3121));
const GPIO0 = '0x' + String(get('gpio0', '41200000'));
const GPIO1 = '0x' + String(get('gpio1', '41210000'));
const IP    = String(get('ip', '192.168.1.10'));
const SPORT = Number(get('sport', 5001));
const FPS   = Number(get('fps', 15));

const PRE       = Number(get('pre', 3));        // 静默基线（秒）
const STREAM    = Number(get('stream', 12));    // 推流时长
const AFTER     = Number(get('after', 15));     // 停流后观察（交回 + 不回跳）
const RESTART   = Number(get('restart', 8));    // 再推一次（可逆性）
const PERIOD    = Number(get('period-ms', 300));
// 默认每点 stop→读→con；--hold-session 回到“整轮按住”的旧写法（只作对照，别拿它出判据）
const HALT_EACH = get('hold-session', false) !== true;
// 串口：本脚本要**按住 A9**，而按住正在传 SD 的内核会把控制器留在未完成的传输里
// （2026-09-24 实测：几次之后 `sd_mount()` 直接失败，只能断电重插 —— ISSUES #50/#45）。
// 所以默认先问一次 STAT：如果在放，就先 STOP、测完再 PLAY 回原状；端口不能共享，占着就跳过。
const COM       = String(get('com', 'COM6'));
const PS_APP    = get('no-serial', false) !== true;
const POWERSH   = 'powershell';
const UART_PS1  = join(ROOT, 'board', 'uart_cap_once.ps1');
const SETTLE_MS = Number(get('settle-ms', 2000));
const HBACK_MS  = Number(get('handback-max-ms', 1500));

// lane30 位序与 pl_video_top.dbg_src 一致（八位全是 axi 域电平 ⇒ 读回不交跨域的税）
const OWN = (v) => (v >>> 2) & 1;
const LIV = (v) => (v >>> 1) & 1;
const TBK = (v) => v & 1;
const FILL = (v) => (v >>> 3) & 1;      // PS 引擎搬运中
const ROW = (v) => (v >>> 4) & 1;       // ETH 引擎搬运中
const MODEG = (v) => (v >>> 5) & 3;     // 仲裁"看到"的模式（格雷码）
// V8-7（r54 起的 bit 才有）：判决那一拍看到的三个原因位 = {强制看 fb, 没流, 时基不可信}
const WHY = (v) => (v >>> 8) & 7;
const WHY_PS = (v) => (v >>> 10) & 1;
// 档名 2026-09-25 起与屏上同源（ETH / SD / TEST，编号不变：SD=3、TEST=2）；
//   旧文档里的"锁PS/锁图卡"= 这里的 SD/TEST。
const MODE = { 0: 'AUTO', 1: 'ETH', 3: 'SD', 2: 'TEST' };
const fmt = (x) => Number.isFinite(x) ? Math.round(x) : '—';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/* ---------------------- 串口：把 PS 的状态保住，别拿它当牺牲品 ---------------------- */
/**
 * 跑一次 uart_cap_once.ps1，返回抓到的文本（失败就返回空串，不影响判据）。
 * 注意 PowerShell 的坑（见 board/uart_cap_once.ps1 头部）：多命令走 -Cmds 逗号分隔，
 * 脚本本体保持 ASCII。
 */
function uart(cmds, seconds) {
  if (!PS_APP) return '';
  const out = dump('arb_uart.txt');
  const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', UART_PS1,
                '-Port', COM, '-Seconds', String(seconds), '-Out', out];
  if (cmds) args.push('-Cmds', cmds.join(','), '-CmdDelay', '2');
  try {
    execFileSync(POWERSH, args, { stdio: 'ignore', windowsVerbatimArguments: false });
  } catch (e) {
    console.log(`[ARB] 串口 ${COM} 不可用（被占用？），跳过 STOP/PLAY 保护：${String(e.message).slice(0, 70)}`);
    return '';
  }
  try { return readFileSync(out, 'utf8'); } catch { return ''; }
}

/** 问一次 STAT；返回 true 表示"测之前 SD 正在放"，测完要还回去。 */
function sdWasPlaying() {
  const t = uart(['STAT'], 6);
  const m = t.match(/\[STAT\].*?playing=(\d)/);
  if (!m) { console.log('[ARB] 没读到 STAT 回包（固件没跑？），按"没在放"处理'); return false; }
  const on = m[1] === '1';
  console.log(`[ARB] 测前 SD playing=${m[1]}${on ? ' ⇒ 先 STOP，测完再 PLAY 回去' : ''}`);
  return on;
}

/**
 * 把片源模式钉回 AUTO，并**验它真的回去了**。
 * 为什么必须有这一步（2026-09-25 的误红）：模式环以前只有 KEY1 长按能改，脚本没有入口 ⇒
 * 用户按过几轮之后板子停在"锁 PS"，我的八条判据里 V3/V6 就红了 —— 症状像硬件坏了，
 * 实际是**起点未知**。从 r58 起固件有 `src auto`（STAT 末尾也回显 `mode=`），这里用它钉起点；
 * 遇到旧固件（没有 mode= 这个字段）就明说"起点不可知"，不许假装钉好了。
 * 返回 true = 起点已确认为 AUTO。
 */
function ensureAutoMode() {
  const t1 = uart(['src auto', 'STAT'], 8);
  const m = t1.match(/\[STAT\].*?mode=(\d)/);
  if (!m) {
    console.log('[ARB] ⚠ 这份固件没有 mode= 回显（早于 r58）⇒ **片源模式的起点不可知**，'
              + '若 V3/V6 红了先怀疑板子被长按钉住了，不是仲裁坏了');
    return false;
  }
  console.log(`[ARB] 测前片源模式 mode=${m[1]}${m[1] === '0' ? '（AUTO，起点干净）' : ' ⇒ 钉不回 AUTO，起点不干净'}`);
  return m[1] === '0';
}

/* ------------------------- 判据（纯函数，可台架验） ------------------------- */
/**
 * samples: [{ms, v}] —— ms 是 PC 单调毫秒，v 是 lane30 的 32bit 值
 * 返回 [a,b) 窗口内的 `{n, own1, first1, first0, flips}`（first* = 首次出现该电平的 ms）。
 */
function windowStats(samples, a, b) {
  const s = samples.filter((x) => x.ms >= a && x.ms < b);
  let first1 = NaN, first0 = NaN, flips = 0, prev = null;
  for (const x of s) {
    const o = OWN(x.v);
    if (o === 1 && !Number.isFinite(first1)) first1 = x.ms;
    if (o === 0 && !Number.isFinite(first0)) first0 = x.ms;
    if (prev !== null && o !== prev) flips++;
    prev = o;
  }
  return { n: s.length, own1: s.filter((x) => OWN(x.v)).length, first1, first0, flips };
}

/**
 * 一轮时间线 → 八条判据（r54 起；#32 那版是七条，历史记录里的"七条全绿"指它）。t1=推流起、t2=停流、t3=再推、t4=结束。
 * 编号会写进报告，别在文案里改名。
 * "不抖"这条**必须在交接完成之后**才开始算：交接过程本身就要翻一次位，
 * 从停流那一刻起算会把正确的行为判成抖动（判据台架的第 ③ 项就是盯这个）。
 */
function judge(samples, t1, t2, t3, t4) {
  const R = [];
  const add = (id, ok, msg) => R.push({ id, ok: !!ok, msg });

  const base = windowStats(samples, t1 - PRE * 1000, t1);
  add('V1 基线归 PS', base.n > 0 && base.own1 === 0,
      `静默 ${PRE}s 内 owner_eth=1 的样本 ${base.own1}/${base.n}（应为 0）`);

  const w1 = windowStats(samples, t1, t2);
  const takeMs = Number.isFinite(w1.first1) ? w1.first1 - t1 : NaN;
  add('V2 接管时限', Number.isFinite(takeMs) && takeMs <= SETTLE_MS,
      `推流后 owner_eth→1 用时 ${fmt(takeMs)} ms（门限 ${SETTLE_MS}）`);
  const hold = windowStats(samples, t1 + Math.max(SETTLE_MS, (takeMs || 0) + 1), t2);
  add('V3 推流期不抖', hold.n > 0 && hold.flips === 0 && hold.own1 === hold.n,
      `稳占段 owner_eth=1 的样本 ${hold.own1}/${hold.n}，翻转 ${hold.flips} 次`);

  const w2 = windowStats(samples, t2, t3);
  const backMs = Number.isFinite(w2.first0) ? w2.first0 - t2 : NaN;
  add('V4 停流交回', Number.isFinite(backMs) && backMs <= HBACK_MS,
      `停流后 owner_eth→0 用时 ${fmt(backMs)} ms（门限 ${HBACK_MS}）`);
  const stay = windowStats(samples, t2 + Math.max(HBACK_MS, (backMs || 0) + 1000), t3);
  add('V5 交回后不回跳', stay.n > 0 && stay.own1 === 0 && stay.flips === 0,
      `交回之后 owner_eth=1 的样本 ${stay.own1}/${stay.n}，翻转 ${stay.flips} 次（都应为 0）`);

  const w3 = windowStats(samples, t3, t4);
  const againMs = Number.isFinite(w3.first1) ? w3.first1 - t3 : NaN;
  add('V6 可逆（再推又接管）', Number.isFinite(againMs) && againMs <= SETTLE_MS,
      `再推流后 owner_eth→1 用时 ${fmt(againMs)} ms（门限 ${SETTLE_MS}）`);

  const all = windowStats(samples, t1, t4);
  add('V0 采样密度', all.n >= Math.floor(((t4 - t1) / PERIOD) * 0.35),
      `全程 ${all.n} 个样本 / 期望约 ${Math.round((t4 - t1) / PERIOD)}（掉一半即判采样链有问题）`);

  // V7（V8-7 / r54 的 bit 才有）：**交回之后那一段必须说得出为什么归 PS**。
  // AUTO 模式下 PS 占着屏只有两种正当理由：没流（bit1）或时基不可信（bit0）；
  // 而"锁 PS"（bit2）本测试从不设置 ⇒ 出现即说明有人把模式钉住了，交接其实是假的。
  // ⚠ 板上若是 r54 之前的 bit，这一条必然红（三位还没出生，恒 0）—— 那是**正确的红**：
  //    先按 md5 核对 bit，别去改判据。（凭据 `build/frozen_*/MANIFEST.md`。）
  const whyBad = samples.filter((x) => x.ms >= t2 && x.ms < t3 &&
      x.ms > t2 + Math.max(HBACK_MS, (backMs || 0) + 1000) &&
      ((WHY(x.v) & 0b011) === 0 || WHY_PS(x.v) === 1));
  add('V7 交回后原因位自洽', stay.n > 0 && whyBad.length === 0,
      `交回段 ${stay.n} 个样本里原因位不可用的 ${whyBad.length} 个` +
      `（要 没流/时基 至少亮一位、且不亮强制看 fb；全 0 = 板上的 bit 早于 r54）`);
  return R;
}

/**
 * 红了要能自己说"是谁占着"。四种解释在 `src_arb` 里各自对应一个可观测条件：
 *   ① 模式不是 AUTO（手动锁钉住）      → 停流段里 MODEG 恒为非 0
 *   ② 时基不可信（eth_tb_ok=0）        → 停流段里 TBK 有 0
 *   ③ ETH 引擎从不空闲（both_idle 假） → 停流段里 ROW 的占空比接近 1
 *   ④ 判据本身判"还在流"（eth_live 谎）→ 停流段里 LIV 一直为 1
 * 这一段**不参与判红**，只把证据摆出来 —— 第一版上板跑就是靠它一眼看到 ①（模式=锁ETH）。
 */
function diagnose(samples, t2, t3) {
  const s = samples.filter((x) => x.ms >= t2 && x.ms < t3);
  if (!s.length) return '停流段没有样本，无法定位原因';
  const n = s.length;
  const mset = new Set(s.map(MODEG));
  const rowOn = s.filter((x) => ROW(x.v)).length;
  const fillOn = s.filter((x) => FILL(x.v)).length;
  const livOn = s.filter((x) => LIV(x.v)).length;
  const tbOff = s.filter((x) => !TBK(x.v)).length;
  const out = [`停流段 ${n} 点：模式={${[...mset].map((m) => MODE[m] ?? m).join(',')}}`
    + ` eth_live 为 1 的点 ${livOn}/${n}，时基不可信 ${tbOff}/${n}`
    + `，row_busy 占空 ${rowOn}/${n}，fill_busy 占空 ${fillOn}/${n}`];
  if (mset.size === 1 && !mset.has(0)) out.push(`⇒ 模式被钉在 ${MODE[[...mset][0]]}，`
    + '仲裁的 force_* 生效，这不是自动判据的问题（长按/上电边沿都会造成这种状态）');
  else if (livOn === n) out.push('⇒ eth_live 整段没落下：判据那一侧还在说"有流"，先看 lane2 的 stall');
  else if (rowOn / n > 0.9) out.push('⇒ ETH 引擎几乎从不空闲，换手条件 both_idle 没机会成立');
  else if (tbOff) out.push('⇒ 时基被判不可信（eth_tb_ok=0），eth_live 被按"没有流"处理');
  else out.push('⇒ 以上四条都不像：需要看 owner 位自己的翻转时刻表（json 里有原始样本）');
  return out.join('\n');
}

/* ------------------------------- 打板子的部分 ------------------------------- */
function readKeep() {
  // 必须先读回 GPIO_0 原值：lane 号写在 bit[31:27]，低 27 位是 src_sel / effect_en /
  // threshold / zoom —— 不知道原值就写，等于把工况改掉（health_read 第一版踩过这个坑）。
  // 这里**只读不写**，写回原值交给采样会话收尾时做（它才知道 keep）。
  const tcl = dump('arb_gpio0.tcl'), out = dump('arb_gpio0.out');
  writeFileSync(tcl, [
    `catch {connect -host localhost -port ${PORT}}`,
    `targets -set -filter {name =~ "*#0"}`,
    'catch {stop}', 'after 100',
    `puts "VAL [mrd -force ${GPIO0} 1]"`,
    'catch {con}',
  ].join('\n') + '\n');
  try {
    execSync(`"${XSDB}" ${tcl} > "${out}" 2>&1`, { windowsVerbatimArguments: true });
  } catch (e) {
    console.log('[ARB] xsdb 退出码异常：' + String(e.message).slice(0, 120));
  }
  const txt = readFileSync(out, 'utf8').replace(/\r\n/g, '\n');
  unlinkSync(tcl);
  const m = txt.match(/VAL\s*[0-9a-fA-F]{1,8}:\s*([0-9a-fA-F]{1,8})/);
  if (!m) {
    console.log('[ARB] 读不到 GPIO_0 的原值，拒绝继续（否则会踩掉 src_sel/特效/阈值）');
    console.log('[ARB] 先确认：板子有电、bit 已下载、hw_server 在跑（HOST_GUIDE.md）');
    console.log('[ARB] xsdb 前几行：\n' + txt.split('\n').slice(0, 6).join('\n'));
    process.exit(1);
  }
  return (parseInt(m[1], 16) >>> 0) & 0x07ffffff;
}

/** 一个 xsdb 会话采完整轮；返回 lane30/lane31 的样本序列。 */
async function sampleSession(keep, durMs) {
  const tcl = dump('arb_session.tcl');
  const sel = (n) => '0x' + (((keep | (n << 27)) >>> 0).toString(16));
  // 采样节拍：**每点都 stop→读→con**，而不是整轮按住 A9。
  // 为什么改（2026-09-24 02:0x 实测）：整轮按住 40 s 之后再看，SD 回放会停在
  // `frame file not found on card` —— 调试器把内核停在一次 SD 传输中间，恢复之后
  // 驱动器/控制器仍留在那次未完成的传输里（ISSUES #50/#45 那一族）。
  // 也就是说**测量本身会杀死被测对象**：那样测出来的"交接"是 PS 引擎已经停摆时的交接，
  // 强度不够，还会让人以为 SD 回放不可靠。
  // 改成每点只按住几十毫秒（两条 mwr + 两条 mrd），代价是每点多含一次 xsdb 固定开销
  // ⇒ 默认周期从 100 ms 放宽到 300 ms。`--hold-session` 保留旧写法，只用于对照实验。
  const body = HALT_EACH ? [
    `catch {connect -host localhost -port ${PORT}}`,
    `targets -set -filter {name =~ "*#0"}`,
    'set t0 [clock clicks -milliseconds]',
    `set endt [expr {$t0 + ${durMs}}]`,
    'while {1} {',
    '  set now [clock clicks -milliseconds]',
    '  if {$now > $endt} { break }',
    '  catch {stop}',
    `  mwr -force ${GPIO0} ${sel(30)} 32`,
    `  puts "S $now 30 [mrd -force ${GPIO1} 1]"`,
    `  mwr -force ${GPIO0} ${sel(31)} 32`,
    `  puts "S $now 31 [mrd -force ${GPIO1} 1]"`,
    `  mwr -force ${GPIO0} 0x${keep.toString(16)} 32`,
    '  catch {con}',
    `  after ${PERIOD}`,
    '}',
    'catch {con}',
  ] : [
    `catch {connect -host localhost -port ${PORT}}`,
    `targets -set -filter {name =~ "*#0"}`,
    'catch {stop}',
    'after 100',
    'set t0 [clock clicks -milliseconds]',
    `set endt [expr {$t0 + ${durMs}}]`,
    'while {1} {',
    '  set now [clock clicks -milliseconds]',
    '  if {$now > $endt} { break }',
    `  mwr -force ${GPIO0} ${sel(30)} 32`,
    `  after 5`,
    `  puts "S $now 30 [mrd -force ${GPIO1} 1]"`,
    `  mwr -force ${GPIO0} ${sel(31)} 32`,
    `  after 5`,
    `  puts "S $now 31 [mrd -force ${GPIO1} 1]"`,
    `  after ${PERIOD}`,
    '}',
    `mwr -force ${GPIO0} 0x${keep.toString(16)} 32`,      // 原样还回去
    'after 50',
    'catch {con}',
  ];
  writeFileSync(tcl, body.join('\n') + '\n');

  // 先声明再交给 Promise：第一次上板跑就撞了 TDZ —— 回调在 `const samples = await ...`
  // 这一行**求值期间**就往数组里 push 了，那时 samples 还在暂时死区里。
  const samples = [];
  await new Promise((resolve, reject) => {
    const child = spawn(`"${XSDB}" "${tcl}"`, { shell: true });
    let buf = '';
    child.stdout.on('data', (d) => {
      buf += d.toString();
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i).replace(/\r$/, ''); buf = buf.slice(i + 1);
        const m = line.match(/^S\s+(\d+)\s+(\d+)\s*[0-9a-fA-F]{1,8}:\s*([0-9a-fA-F]{1,8})/);
        if (m) {
          samples.push({ ms: Number(m[1]), lane: Number(m[2]), v: parseInt(m[3], 16) >>> 0 });
          markFirst();
        }
      }
    });
    child.stderr.on('data', (d) => process.stdout.write(String(d)));
    child.on('error', reject);
    child.on('close', () => resolve());
  });
  try { unlinkSync(tcl); } catch {}
  return samples;
}

// 采样会话"第一拍出数"的信号。runBoard 在掐四个阶段的时间点**之前**等它 —— 原因见 runBoard 里那段注释。
let markFirst = () => {};

function spawnSender() {
  return spawn(process.execPath, [host('video_sender.mjs'),
    '--ip', IP, '--port', String(SPORT), '--fps', String(FPS), '--test', 'move'],
    { stdio: 'ignore' });
}

async function runBoard() {
  const keep = readKeep();
  console.log(`[ARB] GPIO_0 控制位保留 0x${keep.toString(16)}，采样周期 ${PERIOD} ms`);
  // 按住 A9 之前先把 SD 回放停下来：控制器不在传输中间，就不会被调试器留在半途（ISSUES #50）。
  const wasPlaying = sdWasPlaying();
  const autoOk = ensureAutoMode();     // 起点不干净 ⇒ 红了先看这一行（见函数注释）
  if (wasPlaying) uart(['STOP'], 6);
  // +10 s 余量：会话真正开始出数之前有一段"xsdb 连上 hw_server + 第一次 mrd"的爬坡，
  // 这段时间算在 total 里，否则四个阶段跑完时会话已经先断了（尾部样本会丢）。
  const total = (PRE + STREAM + AFTER + RESTART) * 1000 + 6000 + 10000;
  const sess = sampleSession(keep, total);       // 先起会话，再掐推流的时间点

  // ⚠ 必须等**第一拍样本真的到了**再掐 t0（2026-09-25 r59a 的一条误红就出在这里）：
  //   V1 量的是"推流前 PRE 秒这段静默里 owner_eth 必须为 0，而且窗口里**要有样本**"。
  //   上一版直接 `const t0 = Date.now()`，于是 PRE 那 3 s 全花在"会话还在爬坡"上 ——
  //   那次的 json 里第一个样本落在 t1+1254 ms（即 t0 之后 4.25 s），PRE 窗口 0 个样本 ⇒ V1 红。
  //   当时机器上同时跑着综合与一台 xsim，爬坡比 r58 那次长，所以同样的脚本一次绿一次红：
  //   **这是判据自己的时间起点和采样链路抢跑，不是仲裁坏了**。
  //   修法不是把 PRE 放大或把 `base.n > 0` 去掉（那等于把判据阉掉），而是把时间起点挪到"确实在出数"之后：
  //   基线段仍然被完整覆盖，V1 该红的时候照样红（基线里 owner=1 就红、样本永远不来则 V0 红）。
  const firstSeen = new Promise((r) => { markFirst = r; });
  const raced = await Promise.race([firstSeen.then(() => 'live'), sleep(15000).then(() => 'stall')]);
  markFirst = () => {};
  if (raced === 'stall')
    console.log('[ARB] ⚠ 采样会话 15 s 内一拍都没出 —— 继续跑，但 V0（密度）会据此判红，别看 V1');
  else
    console.log('[ARB] 采样会话已出数，开始掐四个阶段的时间点');

  const t0 = Date.now();
  await sleep(PRE * 1000);
  const t1 = Date.now();
  const s1 = spawnSender();
  console.log(`[ARB] +${t1 - t0} ms 开始推流（--test move --fps ${FPS}）`);
  await sleep(STREAM * 1000);
  s1.kill();
  const t2 = Date.now();
  console.log(`[ARB] +${t2 - t0} ms 停流（"交回"用时从这一毫秒起算）`);
  await sleep(AFTER * 1000);
  const t3 = Date.now();
  const s2 = spawnSender();
  console.log(`[ARB] +${t3 - t0} ms 再推流（测可逆）`);
  await sleep(RESTART * 1000);
  s2.kill();
  const t4 = Date.now();
  console.log(`[ARB] +${t4 - t0} ms 结束，等采样会话收尾`);

  const samples = await sess;
  if (wasPlaying) { uart(['PLAY'], 8); console.log('[ARB] 已把 SD 回放恢复到测前状态（PLAY）'); }
  const lane30 = samples.filter((s) => s.lane === 30).map((s) => ({ ms: s.ms, v: s.v }));
  const lane31 = samples.filter((s) => s.lane === 31);
  if (!lane30.length) {
    console.log('[ARB] 一个样本都没采到 —— 先确认 hw_server 在跑、目标选对、GPIO 基址没变');
    process.exit(1);
  }
  console.log(`[ARB] 采到 lane30 ${lane30.length} 点、lane31 ${lane31.length} 点`);
  // 0xDEADBEEF 是"没有这一条 lane"的硬件返回值 ⇒ 板上是 #25 或更早的 bit（lane30 还没出生）。
  // 不挡下来会把 bit2=1 读成"ETH 一直占着"，红得让人误判成仲裁坏了。
  if (lane30.every((s) => s.v === 0xDEADBEEF)) {
    console.log('[ARB] lane30 返回 0xDEADBEEF ⇒ 板上的 bit 还没有 lane30（需要 #26 或更新的 bit）。');
    console.log('[ARB] 先 program 带 dbg_src 的 bit，再重跑本脚本。');
    process.exit(1);
  }
  console.log('[ARB] 每约 2 s 的上下文：' + lane30.filter((_, i) => i % 20 === 0)
    .map((s) => `${Math.round((s.ms - t1) / 100) / 10}s:own${OWN(s.v)}:live${LIV(s.v)}:tb${TBK(s.v)}`)
    .join(' '));

  const R = judge(lane30, t1, t2, t3, t4);
  console.log('');
  for (const r of R) console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.id}  ${r.msg}`);
  const clkBad = lane31.filter((s) => (s.v & 3)).length;
  if (clkBad) console.log(`  注：lane31 有 ${clkBad}/${lane31.length} 点报"时基被拉慢/消失"（拔线态）`);
  const bad = R.filter((r) => !r.ok);
  if (bad.length) console.log('\n[ARB] 定位（不判红，只摆证据）：\n  ' + diagnose(lane30, t2, t3) + '\n');
  if (bad.length && !autoOk) {
    // 今天真实发生过：板子被 KEY1 长按钉在"锁 PS"，V3/V6 一起红，看起来像仲裁坏了。
    console.log('[ARB] ⚠ 起点没确认成 AUTO（见上面那行 mode=）⇒ 先排这一条再谈硬件：'
              + '模式被钉住时 owner_eth 本来就不该动，那两条红是脚本的起点问题。\n');
  }
  console.log('');
  console.log(bad.length
    ? `[ARB] 结论：${bad.length} 条不通过 ⇒ 判红，这一版不能采纳`
    : '[ARB] 结论：八条全过 ⇒ "自动交回 + 不抖 + 可逆"有凭据了（屏幕观感仍欠眼睛）');

  appendFileSync(dump('arb_handover_last.json'), JSON.stringify({
    at: new Date().toISOString(), t1, t2, t3, t4, keep,
    params: { PRE, STREAM, AFTER, RESTART, PERIOD, SETTLE_MS, HBACK_MS, IP, SPORT, FPS },
    verdict: bad.length ? 'RED' : 'GREEN',
    results: R.map((r) => ({ id: r.id, ok: r.ok, msg: r.msg })),
    lane31_slow_or_gone: clkBad, samples: lane30,
  }) + '\n');
  console.log('[ARB] 判据与原始样本落盘：data/measured/arb_handover_last.json');
  process.exit(bad.length ? 1 : 0);
}

/* --------------------- 判据自己的台架（不打板子，必须能跑） --------------------- */
function selftest() {
  // 合成一条 lane30：[ms, owner, live, tb, why]。后两列有默认值，why 缺省时**由 live/tb 推**
  // （与 src_arb 的 `why_ps <= {force_ps, ~eth_live, ~eth_tb_ok}` 同义）——
  // 注意这是"让激励自洽"，不是"用被测式子当判据"：判据（V7）只看采样到的位。
  const mk = (arr) => arr.map(([ms, o, live = 1, tb = 1, why]) => ({
    ms,
    v: (((why ?? (((~live & 1) << 1) | (~tb & 1))) & 7) << 8) | (o << 2) | (live << 1) | tb,
  }));
  const T1 = 10000, T2 = 30000, T3 = 50000, T4 = 60000;
  const ok = [];
  const chk = (name, cond) => { ok.push([name, !!cond]); console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${name}`); };
  const red = (list, id) => !list.find((r) => r.id === id).ok;

  // ① 理想序列（接管 400 ms、交回 300 ms、之后一路平）：除"采样太稀"外不该有红。
  //    live 这一列现在**跟着时间线走**（停流段=0）：不然这条合成序列自己就不自洽，
  //    V7 会红在一个"激励本来就说谎"的样本上 —— 那是台架的错，不是判据的错。
  const good = mk([
    [T1 - 2000, 0, 0], [T1 - 1000, 0, 0],
    [T1 + 100, 0, 1], [T1 + 400, 1, 1], [T1 + 5000, 1, 1], [T2 - 100, 1, 1],
    [T2 + 300, 0, 0], [T2 + 5000, 0, 0], [T3 - 100, 0, 0],
    [T3 + 200, 0, 1], [T3 + 400, 1, 1], [T4 - 100, 1, 1],
  ]);
  const g = judge(good, T1, T2, T3, T4);
  chk('理想序列只该红在采样密度一条', g.filter((r) => !r.ok).map((r) => r.id).join() === 'V0 采样密度');
  chk('理想序列：交回用时=300 ms', g.find((r) => r.id === 'V4 停流交回').msg.includes(' 300 '));

  // ② 永不交回（#24 那版板级就是这个表现）⇒ V4、V5 必须同时红
  const stuck = mk([[T1 + 400, 1], [T2 + 100, 1], [T2 + 5000, 1], [T3 + 100, 1], [T4 - 100, 1]]);
  const r2 = judge(stuck, T1, T2, T3, T4);
  chk('停在 ETH 不交回 ⇒ V4 红', red(r2, 'V4 停流交回'));
  chk('停在 ETH 不交回 ⇒ V5 也红（不能只报一条假装看见了原因）', red(r2, 'V5 交回后不回跳'));

  // ③ 交接过程本身翻一次位，不该被算成"抖"（这条是判据最容易出错的地方）
  const flap = mk([
    [T1 - 1000, 0, 0], [T1 + 400, 1, 1], [T1 + 5000, 1, 1],
    [T2 + 100, 1, 0], [T2 + 400, 0, 0],       // 正常交接：这 400 ms 里翻一次
    [T2 + 5000, 0, 0], [T2 + 10000, 0, 0], [T3 - 100, 0, 0],
    [T3 + 400, 1, 1], [T4 - 100, 1, 1],
  ]);
  const r3 = judge(flap, T1, T2, T3, T4);
  chk('正常交接（含 100 ms 滞后）⇒ V3/V5 都不该红',
      !red(r3, 'V3 推流期不抖') && !red(r3, 'V5 交回后不回跳'));

  // ④ 交回后又抢回去 ⇒ V5 必须红
  const flapBack = mk([[T2 + 400, 0], [T2 + 6000, 1], [T2 + 12000, 0], [T3 - 100, 0], [T3 + 400, 1], [T4, 1]]);
  chk('交回后又抢回 ⇒ V5 红', red(judge(flapBack, T1, T2, T3, T4), 'V5 交回后不回跳'));

  // ⑤ 接管太慢 ⇒ V2 红
  const slow = mk([[T1 + 5000, 1], [T2 + 400, 0], [T2 + 5000, 0], [T3 + 500, 1], [T4, 1]]);
  chk('接管超时限 ⇒ V2 红', red(judge(slow, T1, T2, T3, T4), 'V2 接管时限'));

  // ⑥ 基线就不是 PS（上一轮没交回来）⇒ V1 红
  const dirty = mk([[T1 - 1000, 1], [T1 + 400, 1], [T2 + 400, 0], [T3 + 400, 1], [T4, 1]]);
  chk('基线已被 ETH 占住 ⇒ V1 红', red(judge(dirty, T1, T2, T3, T4), 'V1 基线归 PS'));

  // ⑦ 一个样本都没有 ⇒ 不能悄悄判绿
  chk('空样本 ⇒ 至少 5 条红（不许出现"全过"）',
      judge([], T1, T2, T3, T4).filter((r) => !r.ok).length >= 5);

  // ⑧ 位序：解码错一位，全部判据都会"看起来正常"
  chk('位序解码 owner/live/tb = bit2/1/0',
      OWN(0b100) === 1 && LIV(0b010) === 1 && TBK(0b001) === 1 && OWN(0b011) === 0);

  // ⑨⑩⑪（V8-7 的 V7）：新加的这条必须**能红**，而且只在原因位说谎时红。
  //    不做这三条就等于"加了一条永远不会红的判据"——那比不加更糟（它会让人以为有人看着）。
  chk('理想序列 ⇒ V7 绿（原因位与时间线自洽）', !red(g, 'V7 交回后原因位自洽'));
  const lie = mk([
    [T1 - 1000, 0, 0], [T1 + 400, 1, 1], [T2 - 100, 1, 1],
    [T2 + 400, 0, 0, 1, 0b000],       // 停流了、也交回了，原因位却说"一切正常" ⇒ 判据说谎的形状
    [T2 + 5000, 0, 0, 1, 0b000], [T3 - 100, 0, 0, 1, 0b000],
    [T3 + 400, 1, 1], [T4 - 100, 1, 1],
  ]);
  chk('交回后原因位全 0 ⇒ V7 红（这条不是装饰）', red(judge(lie, T1, T2, T3, T4), 'V7 交回后原因位自洽'));
  const lock = mk([[T2 + 400, 0, 0, 1, 0b110], [T2 + 5000, 0, 0, 1, 0b110], [T3 - 100, 0, 0, 1, 0b110]]);
  chk('亮着「强制看 fb(SD)」也不自洽 ⇒ V7 红（本测试从不锁模式）',
      red(judge(lock, T1, T2, T3, T4), 'V7 交回后原因位自洽'));

  const bad = ok.filter(([, c]) => !c).length;
  console.log(bad ? `\n[ARB] 判据台架：${ok.length - bad}/${ok.length} 通过 ⇒ 判据本身有问题，别信它的红绿`
                  : `\n[ARB] 判据台架：${ok.length}/${ok.length} 通过`);
  process.exit(bad ? 1 : 0);
}

if (get('selftest', false) === true) selftest();
else runBoard();
