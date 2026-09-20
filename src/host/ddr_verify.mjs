#!/usr/bin/env node
/**
 * ddr_verify.mjs — 通过 JTAG 回读板上 DDR 的两个乒乓 bank，逐字比对
 * host/video_sender.mjs --test wordid 发出的自描述图案，从而「不看屏幕」
 * 也能判定 UDP→reasm→CDC→AXI→DDR 这条入包链有没有丢字/错位。
 *
 * 前置：板子已 ps7_init、已 program bit、正在（或刚刚）推 wordid 图案。
 * 用法：node ddr_verify.mjs [--bank-only 0|1] [--xsdb <path>] [--port 3121]
 *
 * 输出：每个 bank 的 命中字数 / 空洞数 / 空洞所在的行段 / 首个不匹配地址。
 */
import { execFileSync, execSync } from 'node:child_process';
import { writeFileSync, readFileSync, unlinkSync } from 'node:fs';
import { MEASURED, host, dump } from './repo_path.mjs';


const WORDS = 38400;             // 512x300 RGB565 / 8B
const BANK0 = 0x10000000;
const BANK1 = 0x10080000;
const CHUNK = 1000;

function get(name, def) {
  const i = process.argv.indexOf('--' + name);
  if (i < 0) return def;
  const nxt = process.argv[i + 1];
  return nxt && !nxt.startsWith('--') ? nxt : true;
}
const XSDB = String(get('xsdb', 'D:\\Software\\Vivado\\2025.2.1\\Vitis\\bin\\xsdb.bat'));
const PORT = Number(get('port', 3121));
const ONE = get('bank-only', undefined);
const ADD = Number(get('add', 0)) & 0xffff;   // 与 video_sender --wordid-add 对应
const FRAMEID = get('frameid', false) === true;  // 配合 --test frameid：反解每字来自第几帧

const U32 = WORDS * 2;             // 每个 64bit 图案字 = 2 个 32bit 字

function dumpScript(addrs) {
  return [
    `catch {connect -host localhost -port ${PORT}}`,
    `targets -set -filter {name =~ "*#0"} `,
    // 关键：Vitis 应用会开 D-Cache，mrd 走 A9 端口会读到缓存旧数据。
    // rst -processor 复位并暂停核心（MMU/Cache 随之关闭，DDR 控制器保持已初始化），
    // 这样回读到的才是 DDR 的真实内容。副作用：PS 上正在跑的 ELF 会被停住。
    `catch {rst -processor}`,
    `after 200`,
    ...addrs.flatMap(a => {
      const lines = [`puts "BANK ${a.toString(16)}"`];
      for (let off = 0; off < U32; off += CHUNK) {
        const cnt = Math.min(CHUNK, U32 - off);
        lines.push(`puts [mrd -force 0x${(a + off * 4).toString(16)} ${cnt}]`);
      }
      return lines;
    }),
    `# 故意不 con：让 A9 停在复位态，避免它重新跑 boot ROM 把 SD/QSPI 里的旧 bit 刷回 PL`,
    '',
  ].join('\n');
}

const OUT = dump('ddr_dump.out');                       // <repo>/data/measured/

function run(tclPath) {
  try {
    execSync(`"${XSDB}" ${tclPath} > "${OUT}" 2>&1`, { windowsVerbatimArguments: true });
  } catch (e) {
    console.log(`[DDR] xsdb exited ${e.status}: ${String(e.message).slice(0, 120)}`);
  }
  return readFileSync(OUT, 'utf8');
}

function analyse(tag, base, text) {
  let good = 0, bad = 0, first = null;
  let stalePattern = 0, never = 0, other = 0;   // 相位位移判别
  const holes = new Map();          // 16-row band → count
  const re = /^\s*([0-9a-fA-F]{8}):\s+([0-9a-fA-F]{8})\s*$/;
  for (const line of text.split('\n')) {
    const m = re.exec(line);
    if (!m) continue;
    const addr = parseInt(m[1], 16);
    const val = parseInt(m[2], 16);
    const w = (addr - base) >> 2;          // 32-bit word index
    if (w < 0 || w >= WORDS * 2) continue;
    // 图案按 64bit（4 像素）编号 → 同一个 64bit 内的两个 32bit 都等于 w>>1
    const v = ((w >> 1) + ADD) & 0xffff;   // 本相位期望值
    const v0 = (w >> 1) & 0xffff;          // 零相位（历史数据）期望值
    const want = (v | (v << 16)) >>> 0;
    if (val === want) good++;
    else {
      bad++;
      const lo = val & 0xffff, hi = (val >> 16) & 0xffff;
      for (const lane of [lo, hi]) {
        if (lane === 0) never++;
        else if (lane === v0) stalePattern++;
        else other++;
      }
      if (!first) first = { w, val };
      const row = Math.floor(w / 256);      // 每行 512 像素 = 256 个 32bit 字
      const band = Math.floor(row / 16);
      holes.set(band, (holes.get(band) || 0) + 1);
    }
  }
  console.log(`[${tag}] base=0x${base.toString(16)} good=${good} bad=${bad} ` +
              `${good + bad === 0 ? '(no data)' : `coverage=${(100 * good / Math.max(good + bad, 1)).toFixed(1)}%`}` +
              `${ADD ? ` lane[本相位缺:never=${never} stale=${stalePattern} other=${other}]` : ''}`);
  if (first) {
    const row = Math.floor(first.w / 256), col = ((first.w * 2) % 512);
    const fv = (first.w >> 1) & 0xffff;
    console.log(`       first mismatch u32=${first.w} (row ${row}, col ${col}) ` +
                `got=0x${first.val.toString(16)} expected=0x${(fv | (fv << 16)).toString(16)}`);
  }
  if (holes.size) {
    const bands = [...holes.entries()].sort((a, b) => a[0] - b[0]);
    console.log(`       bad bands (16-row groups): ` +
                bands.slice(0, 12).map(([b, c]) => `rows${b * 16}-${b * 16 + 15}:${c}`).join(' '));
    if (bands.length > 12) console.log(`       ... ${bands.length - 12} more bands`);
  }
  return { good, bad };
}

// 把转储文本解析成 u32 数组（下标 = 32bit 字序号）
function parseWords(base, text) {
  const arr = new Uint32Array(U32);
  const seen = new Uint8Array(U32);
  const re = /^\s*([0-9a-fA-F]{8}):\s+([0-9a-fA-F]{8})\s*$/;
  for (const line of text.split('\n')) {
    const m = re.exec(line);
    if (!m) continue;
    const w = (parseInt(m[1], 16) - base) >> 2;
    if (w < 0 || w >= U32) continue;
    arr[w] = parseInt(m[2], 16);
    seen[w] = 1;
  }
  return { arr, seen };
}

// --ref 模式：和上位机 dump 出来的参考帧逐 32bit 字比对（图案任意，不再依赖 wordid）
// refs = [{name, buf}]，buf 是 307200 字节的原始帧
function analyseRef(tag, base, text, refs) {
  const { arr, seen } = parseWords(base, text);
  let got = 0;
  for (const s of seen) if (s) got++;
  console.log(`[${tag}] base=0x${base.toString(16)} u32_read=${got}/${U32}`);
  for (const { name, buf } of refs) {
    let bad = 0, first = -1, firstGot = 0, firstWant = 0;
    const rows = new Map();
    for (let w = 0; w < U32; w++) {
      if (!seen[w]) continue;
      const want = buf.readUInt32LE(w * 4);
      if (arr[w] === want) continue;
      bad++;
      if (first < 0) { first = w; firstGot = arr[w]; firstWant = want; }
      const band = (w >> 8) >> 4;              // 每行 256 个 u32，16 行一组
      rows.set(band, (rows.get(band) || 0) + 1);
    }
    console.log(`       vs ${name}: mismatch=${bad}/${got}` +
                (bad === 0 ? '  ⇒ 该 bank 与它逐字节一致' : ''));
    if (first >= 0) {
      const list = [...rows.entries()].sort((a, b) => a[0] - b[0]);
      console.log(`       first mismatch u32=${first} (row ${first >> 8}, col ${(first * 2) % 512}) ` +
                  `got=0x${(firstGot >>> 0).toString(16)} want=0x${(firstWant >>> 0).toString(16)}`);
      console.log(`       mismatch bands(16行为一组): ` +
                  list.slice(0, 10).map(([b, c]) => `r${b * 16}:${c}`).join(' ') +
                  (list.length > 10 ? ` ...+${list.length - 10}` : ''));
    }
  }
}

// --frameid 模式：图案每像素 = 字号 + 帧号 ⇒ 反解每个字来自第几帧
function analyseFrameId(tag, base, text) {
  const { arr, seen } = parseWords(base, text);
  const hist = new Map();          // 帧号 → 计数（按 16bit lane 统计）
  let intraDiff = 0, words = 0, oldest = -1, newest = -1;
  const byBand = new Map();        // 16 行一组 → {帧号: 计数}
  for (let w = 0; w < U32; w++) {
    if (!seen[w]) continue;
    words++;
    const w64 = w >> 1;
    const lo = (arr[w] & 0xffff), hi = (arr[w] >>> 16);
    const nl = (lo - w64) & 0xffff, nh = (hi - w64) & 0xffff;
    for (const nf of [nl, nh]) {
      hist.set(nf, (hist.get(nf) || 0) + 1);
      if (oldest < 0 || nf < oldest) oldest = nf;
      if (nf > newest) newest = nf;
    }
    if (nl !== nh) intraDiff++;
    const band = (w >> 8) >> 4;                 // 每行 256 个 u32，16 行一组
    if (!byBand.has(band)) byBand.set(band, new Map());
    const m = byBand.get(band);
    m.set(nl, (m.get(nl) || 0) + 1);
  }
  const top = [...hist.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8);
  console.log(`[${tag}] u32=${words}/${U32} 帧号跨度=${oldest}..${newest} ` +
              `同一字内两 lane 帧号不同的字数=${intraDiff}`);
  console.log(`       帧号分布(top8): ` + top.map(([k, v]) => `f${k}:${v}`).join(' '));
  // 按字位置分 10 段，看每段里各帧号占比 ⇒ 区分「每帧只写前 X%」与「均匀散布丢字」
  const dom = top.length ? top[0][0] : -1;
  const dec = Array.from({ length: 10 }, () => new Map());
  for (let w = 0; w < U32; w++) {
    if (!seen[w]) continue;
    const w64 = w >> 1;
    const nl = ((arr[w] & 0xffff) - w64) & 0xffff;
    const d = Math.min(9, Math.floor(w / (U32 / 10)));
    dec[d].set(nl, (dec[d].get(nl) || 0) + 1);
  }
  console.log(`       主导帧号=f${dom}，按字位置 10 段的新帧占比：`);
  console.log('         ' + dec.map((m, i) => {
    const tot = [...m.values()].reduce((a, b) => a + b, 0);
    const c = m.get(dom) || 0;
    return `w${i * 10}-${i * 10 + 9}%:${tot ? (100 * c / tot).toFixed(0) : '?'}`;
  }).join(' '));
  let mixedBands = 0, seamBands = 0;
  for (const [band, m] of [...byBand.entries()].sort((a, b) => a[0] - b[0])) {
    if (m.size > 1) {
      mixedBands++;
      const dom = [...m.entries()].sort((a, b) => b[1] - a[1]);
      if (dom.length >= 2 && dom[1][1] * 8 > dom[0][1]) seamBands++;
    }
  }
  console.log(`       含多个帧号的 16 行组=${mixedBands}/19，其中次要帧号占比>12% 的组=${seamBands}` +
              `（⇒ 若 mixedBands 很小且集中在少数行 ⇒ 是整行接缝；若遍布全帧 ⇒ 逐字混合）`);
}

const banks = ONE === undefined ? [BANK0, BANK1] : [Number(ONE) ? BANK1 : BANK0];
const tmp = dump('ddr_dump.tcl');
writeFileSync(tmp, dumpScript(banks));
console.log(`[DDR] dumping ${banks.length} bank(s) over JTAG (${WORDS} words each) ...`);
const out = run(tmp).replace(/\r\n/g, '\n');
unlinkSync(tmp);

if (/error|no targets|Cannot/i.test(out.split('\n').slice(0, 6).join('\n'))) {
  console.log('[DDR] xsdb reported a problem:');
  console.log(out.split('\n').slice(0, 10).map(l => '  ' + l).join('\n'));
}
let hit = null;
const REF = typeof get('ref', null) === 'string' ? String(get('ref', '')) : null;
const refs = [];
if (REF) {
  try {
    refs.push({ name: '最后一帧', buf: readFileSync(REF) });
    refs.push({ name: '倒数第二帧', buf: readFileSync(REF + '.prev') });
  } catch (e) {
    console.log(`[DDR] 参考帧读取失败：${e.message}（用 --dump 让 video_sender.mjs 落盘）`);
  }
}

for (const base of banks) {
  const seg = out.split(`BANK ${base.toString(16)}\n`)[1] || '';
  const nextBank = banks[banks.indexOf(base) + 1];
  const cut = nextBank ? seg.split(`BANK ${nextBank.toString(16)}\n`)[0] : seg;
  if (refs.length) { analyseRef(base === BANK0 ? 'bank0' : 'bank1', base, cut, refs); continue; }
  if (FRAMEID) { analyseFrameId(base === BANK0 ? 'bank0' : 'bank1', base, cut); continue; }
  const r = analyse(base === BANK0 ? 'bank0' : 'bank1', base, cut);
  if (r.good > 0 && (!hit || r.bad < hit.bad)) hit = { base, ...r };
}
if (refs.length) {
  console.log('[DDR] 判读：某个 bank 与「最后一帧」mismatch=0 ⇒ 撕裂不在 DDR，在显示侧；' +
              '两个 bank 都不匹配任何一帧 ⇒ DDR 里就是两帧逐字混合，查乒乓 bank 切换时序。');
} else if (hit) {
  console.log(`[DDR] live bank = 0x${hit.base.toString(16)} bad=${hit.bad}/${U32} ` +
              (hit.bad === 0 ? '→ 入包链无空洞' : '→ 有空洞，见上面的 band 分布'));
} else {
  console.log('[DDR] 两个 bank 都没读到有效 wordid 图案：帧没有写进 DDR（检查是否在推流、src_sel、commit）');
}
