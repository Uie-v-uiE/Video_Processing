#!/usr/bin/env node
/*
 * gen_inputs.mjs —— `data/inputs/` 边界与非法输入向量的**唯一**生成器（P17）。
 *
 * 为什么放在 data/generated/ 而不是 src/host/：P17 交付清单把 `data/generated/` 定义为
 * "由脚本合成的数据：生成脚本、参数、随机种子、可复现命令"，这个脚本连同它的全部参数与种子
 * 就是那一格的正文；数据本体落在 `data/inputs/`（P17 把边界样本定义在 inputs/ 那一格）。
 *
 * ── 可复现命令（复制即用，仓库根执行；本机 Git Bash + node 24）─────────
 *   node data/generated/gen_inputs.mjs                          # 只打印名单与摘要，不落盘
 *   node data/generated/gen_inputs.mjs --selftest               # 证明"复现比对"这层有牙
 *   node data/generated/gen_inputs.mjs --write                  # 写 data/inputs/（跑第 1 次）
 *   cp -r data/inputs /tmp/p17_run1                             # bash 侧留快照
 *   node data/generated/gen_inputs.mjs --write                  # 同参数再跑第 2 次
 *   diff -r /tmp/p17_run1 data/inputs && echo 两次跑逐字节一致
 *   node data/generated/gen_inputs.mjs --check                  # 第 3 个进程：内存重算 vs 磁盘
 *   ⚠ 路径口径（本次实测过，不是猜的）：Git Bash 会把命令行里的 `/tmp/…` 参数**先转换成**
 *     `C:/Users/<用户>/AppData/Local/Temp/…` 再交给 node，所以从 shell 传 `--check /tmp/xxx`
 *     两边看到的是同一个目录（上面那条 --check 的回显里就打印出了转换后的路径）。
 *     但脚本**内部**自己拼出来的 `/tmp` 不走这套转换，落点与 shell 的不一定同盘。
 *     所以：默认路径只碰仓库内的相对路径，跨侧的快照只由 shell 的 cp/diff 负责，不写进 node。
 *
 * ── 参数与随机种子（默认值 = 入库那一份用的值）─────────────────────────
 *   --seed   20261004   两处都吃它：① 自描述图案的序号基值；② LCG 的初态（只喂 rand64 向量）
 *   --out    data/inputs          写出目录
 *   --check  <同 --out>           比对目录（`--check` 带值则比对到那个目录）
 *   几何常量不在命令行上：W=512 / H=300 / FRAME_BYTES=307200 / MTU 载荷上限 1392
 *   取自 `src/host/video_sender.mjs` 的 `const W = 512, H = 300, FRAME_BYTES = W * H * 2`
 *   与它文件头写的 "载荷 <= 1392 B（8 的倍数）"；改这几个数等于改协议，必须连同那两处一起改。
 *
 * ── 随机源（说清算法，不留口头承诺）───────────────────────────────────
 * 只有一个：`mulberry32`（32 位 state 的 LCG 家族，见下面 lcg()），初态 = --seed。
 * 它只决定 `rand64_512x300.rgb565` 的字节；其余向量是纯算术填充，换 seed 才变的是序号族三个，
 * 连 seed 都不吃的是 empty/zero/full/udp_pkt_edge 四个。
 * 不用 Date、不用 Math.random、不读环境变量、不把时间戳写进文件 ⇒ "同参数 ⇒ 同字节"可判。
 *
 * 为什么要一个随机向量：本设计栽过的两类错都落在 **64 位字的边界**上——载荷不是 8 的倍数时
 * 包边界落在字中间（`src/host/video_sender.mjs` 文件头 "--mtu-payload 1396 是用来复现这个错误的"
 * 那一段），以及发包方自选的 offset 能把字写到帧缓存之外（`src/rtl/eth/frame_reasm.v:144-161`，
 * 台账 #201）。全 0 / 全 F 这两种图案**看不出写出位置**（每个字都一样，写到别的字上磁盘内容不变），
 * 所以要一个"每字取值随位置变化"的图案。实测它并不完美（下面的条数由本次跑出来的字节数出来，
 * 不是估的）：153600 个字里 59252 个不同取值，相邻两字相同的有 2 对，
 * 38400 个 64 位字组里 34392 组（89.6 %）8 字节全不相同、其余 4008 组内含重复字节。
 * 结论按实测口径写：它能抓"整字写错位置"与"字内字节顺序错"，**不保证**每个 64 位字都肉眼可辨。
 *
 * ── 边界 ────────────────────────────────────────────────────────
 * 只写 `--out` 指定目录下的 8 个文件，**不碰** `data/golden/`、`data/measured/`、`data/metrics.csv`。
 * 覆盖不到任何已入库文件是设计：P23 禁止覆盖已入库件，而 golden 的不可变由
 * `data/golden/manifest.md` 的摘要管，不由本脚本管。
 * `--check` 发现目录里有本脚本名单之外的文件时只报 EXTRA、不删除。
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const REPO = process.cwd();
function arg(name, dflt) {
    const i = process.argv.indexOf('--' + name);
    if (i < 0) return dflt;
    const nxt = process.argv[i + 1];
    return nxt && !nxt.startsWith('--') ? nxt : dflt;
}
const SEED = Number(arg('seed', 20261004));
const OUT = String(arg('out', 'data/inputs'));
const CHECK_FLAG = process.argv.includes('--check');
const CHECK = CHECK_FLAG ? (typeof arg('check', null) === 'string' ? String(arg('check', null)) : OUT) : null;
const WRITE = process.argv.includes('--write');
const SELFTEST = process.argv.includes('--selftest');

// —— 协议几何（来源见文件头注释，不要在这里"顺手改大"）
const W = 512, H = 300, FRAME_BYTES = W * H * 2;         // 307200
const WORDS = FRAME_BYTES / 2;                            // 153600 个 RGB565 字
const MTU_PAYLOAD = 1392;                                 // 8 的倍数；非 8 倍数是已知错误形状

// —— 唯一的伪随机源：mulberry32，初态取 --seed
function lcg(seed) {
    let s = seed >>> 0;
    return function () {
        s = (s + 0x6D2B79F5) >>> 0;
        let t = Math.imul(s ^ (s >>> 15), 1 | s);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

/** 自描述序号帧：第 w 个字 = (w + SEED) & 0xffff，小端 u16。
 *  与 `src/host/video_sender.mjs` 的 `--test frameid`（`const v = (w + n) & 0xffff`）同一形状，
 *  差别只在那里 n 是帧号、这里 n 换成 --seed ⇒ 反解式 `n_implied = (v − SEED) & 0xffff` 给出
 *  "这个字是按第几个字写进去的"，用来抓换帧滞后与逐字混合（帧号族判据的既有口径）。 */
function wordidFrame(words, base) {
    const buf = Buffer.alloc(words * 2);
    for (let w = 0; w < words; w++) buf.writeUInt16LE((w + base) & 0xffff, w * 2);
    return buf;
}

/** 随机位帧：每字由 mulberry32 取一个 u16。种子不同 ⇒ 整帧不同；同种子 ⇒ 逐字节同。 */
function randFrame(words, seed) {
    const buf = Buffer.alloc(words * 2);
    const rnd = lcg(seed);
    for (let w = 0; w < words; w++) buf.writeUInt16LE(Math.floor(rnd() * 65536) & 0xffff, w * 2);
    return buf;
}

/** 生成全部向量：返回 [{name, bytes, kind, meaning}]，顺序固定 = 磁盘名单固定 */
function build() {
    const wf = wordidFrame(WORDS, SEED);                    // 307200 B
    const rows299 = Buffer.from(wf.subarray(0, 512 * 299 * 2));
    const over = Buffer.concat([wf, wordidFrame(WORDS / 2, (SEED + WORDS / 2) & 0xffff)]);
    const zero = Buffer.alloc(FRAME_BYTES, 0x00);
    const full = Buffer.alloc(FRAME_BYTES, 0xff);
    const rf = randFrame(WORDS, SEED);

    // —— 包级边界序列：每包 = [u32 小端 byte_offset][payload]
    const pkts = [
        [0, 0x00, 0],                                          // P1 零长载荷
        [0, 0x11, 6],                                          // P2 载荷 6 B：不是 8 的倍数
        [8, 0x22, 6],                                          // P3 载荷 6 B 且落字中间
        [FRAME_BYTES, 0x33, 8],                                // P4 offset 恰在帧尾之外
        [FRAME_BYTES - 2, 0x44, 8],                            // P5 跨帧尾：2 B 合法 + 6 B 越界
        [0xffffffff, 0x55, 4],                                 // P6 offset 取到 32 位最大
        [FRAME_BYTES - 1, 0x66, 2],                            // P7 奇数字节偏移：落在 16 位像素中间
    ];
    const parts = [];
    for (const [off, fill, len] of pkts) {
        const h = Buffer.alloc(4); h.writeUInt32LE(off >>> 0, 0);
        parts.push(h, Buffer.alloc(len, fill));
    }
    const pktBin = Buffer.concat(parts);

    return [
        { name: 'empty_0b.bin', bytes: Buffer.alloc(0), kind: '空', seed: '不吃', meaning: '零字节流：接收端不能把它当成一帧，也不许因为它写任何 DDR 字' },
        { name: 'zero_512x300.rgb565', bytes: zero, kind: '全零', seed: '不吃', meaning: '每字 0x0000 = R5/G6/B5 全 0（黑）：帧缓存与 OSD 叠加的地板值' },
        { name: 'full_512x300.rgb565', bytes: full, kind: '满幅', seed: '不吃', meaning: '每字 0xFFFF = 三通道全 1（白）：饱和/位宽截断的天花板值' },
        { name: 'trunc_299rows.rgb565', bytes: rows299, kind: '截断', seed: '吃', meaning: `只到第 299 行整（${512 * 299 * 2} B = ${FRAME_BYTES} − ${512 * 2}）：行数覆盖门差一行` },
        { name: 'overlong_1p5frame.rgb565', bytes: over, kind: '超长', seed: '吃', meaning: `一帧半（${FRAME_BYTES * 3 / 2} B）：按 ${FRAME_BYTES} 切帧时第二帧必然不完整` },
        { name: 'wordid_512x300.rgb565', bytes: wf, kind: '自描述', seed: '吃', meaning: '每字 = (字序号 + seed) & 0xffff：反解写出位置与滞后帧' },
        { name: 'rand64_512x300.rgb565', bytes: rf, kind: '随机位', seed: '吃(LCG 初态)', meaning: '每字 = mulberry32(seed) 的一个 u16：抓整字写错位置与字内字节序（覆盖率见文件头实测条数）' },
        { name: 'udp_pkt_edge.bin', bytes: pktBin, kind: '非法包', seed: '不吃', meaning: `7 条包级非法/边界形状（零长、载荷非 8 倍数、offset 越界/最大/落像素中间），共 ${pktBin.length} B` },
    ];
}

function sha(buf) { return crypto.createHash('sha256').update(buf).digest('hex'); }
const tsv = (rows) => rows.map((r) => r.join('\t')).join('\n');
const find = (vs, n) => vs.find((v) => v.name === n);

let exitCode = 0;
const head = [`gen_inputs.mjs  node=${process.version}  seed=${SEED}  几何 W=${W} H=${H} FRAME_BYTES=${FRAME_BYTES} MTU_PAYLOAD=${MTU_PAYLOAD}`];

if (SELFTEST) {
    // 三件事都要能判：同参数能重产、换参数确实改字节、改一个 bit 必被摘要抓到（否则 --check 是空转）。
    const a = build(), b = build();
    const sameRun = a.every((v, i) => v.bytes.equals(b[i].bytes));
    head.push(`ST1 同参数两次生成逐字节一致（${a.length}/${a.length}）：${sameRun ? 'PASS' : 'FAIL'}`);
    if (!sameRun) exitCode = 1;
    const other = randFrame(4, (SEED + 1) >>> 0);
    const thisOne = randFrame(4, SEED);
    const seedSensitive = !other.equals(thisOne);
    head.push(`ST2 LCG 初态换 seed 输出必变（否则"随机种子"是装饰）：${seedSensitive ? 'PASS' : 'FAIL'}`);
    if (!seedSensitive) exitCode = 1;
    const mutated = Buffer.from(find(a, 'full_512x300.rgb565').bytes);
    mutated[0] ^= 0x01;
    const caught = sha(mutated) !== sha(find(a, 'full_512x300.rgb565').bytes);
    head.push(`ST3 改 1 bit 必被 sha256 抓到：${caught ? 'PASS' : 'FAIL'}`);
    if (!caught) exitCode = 1;
    const zeroLen = find(a, 'empty_0b.bin').bytes.length === 0;
    head.push(`ST4 "空"这一类真的是 0 字节（不是 1 字节糊弄）：${zeroLen ? 'PASS' : 'FAIL'}`);
    if (!zeroLen) exitCode = 1;
    head.push(`ST5 向量条数 = ${a.length}，名单固定：${a.map((v) => v.name).join(', ')}`);
    console.log(tsv([['文件', '字节', 'sha256(原始字节)'], ...a.map((v) => [v.name, String(v.bytes.length), sha(v.bytes)])]));
    console.log(head.join('\n'));
    console.log(`SELFTEST ${exitCode === 0 ? 'PASS' : 'FAIL'}`);
    process.exit(exitCode);
}

const vectors = build();

if (WRITE) {
    const dir = path.resolve(REPO, OUT);
    fs.mkdirSync(dir, { recursive: true });
    const rows = [['文件', '字节', 'sha256(原始字节)', '类别']];
    for (const v of vectors) {
        fs.writeFileSync(path.join(dir, v.name), v.bytes);
        rows.push([v.name, String(v.bytes.length), sha(v.bytes), v.kind]);
    }
    const extra = fs.readdirSync(dir).filter((f) => !vectors.some((v) => v.name === f) && fs.statSync(path.join(dir, f)).isFile());
    console.log(tsv(rows));
    console.log(`写出 ${vectors.length} 个到 ${OUT}` + (extra.length ? `；目录里另有本脚本名单之外的文件（未删除）：${extra.join(', ')}` : ''));
    console.log(head.join('\n'));
    process.exit(0);
}

if (CHECK) {
    const dir = path.resolve(REPO, CHECK);
    const rows = [['文件', '期望字节', '磁盘字节', 'sha256(期望)', '判定']];
    let ok = 0, bad = 0, missing = 0;
    if (!fs.existsSync(dir)) { console.log(`--check ${CHECK}：目录不存在 ⇒ FAIL`); console.log(head.join('\n')); process.exit(1); }
    for (const v of vectors) {
        const p = path.join(dir, v.name);
        if (!fs.existsSync(p)) { rows.push([v.name, String(v.bytes.length), '—', sha(v.bytes), 'MISSING']); missing++; continue; }
        const disk = fs.readFileSync(p);
        const same = disk.equals(v.bytes);
        rows.push([v.name, String(v.bytes.length), String(disk.length), sha(v.bytes), same ? 'OK' : 'DIFF']);
        if (same) ok++; else bad++;
    }
    const extra = fs.readdirSync(dir).filter((f) => fs.statSync(path.join(dir, f)).isFile() && !vectors.some((v) => v.name === f));
    console.log(tsv(rows));
    const verdict = (bad === 0 && missing === 0) ? 'PASS' : 'FAIL';
    console.log(`--check ${CHECK}：一致 ${ok}/${vectors.length} / 不符 ${bad} / 缺 ${missing} / 名单外 EXTRA ${extra.length}${extra.length ? '（' + extra.join(', ') + '）' : ''} ⇒ ${verdict}`);
    console.log(head.join('\n'));
    process.exit(verdict === 'PASS' ? 0 : 1);
}

console.log(tsv([['文件', '字节', 'sha256(原始字节)', '类别', '吃 seed', '含义'],
    ...vectors.map((v) => [v.name, String(v.bytes.length), sha(v.bytes), v.kind, v.seed, v.meaning])]));
console.log(`seed=${SEED} 几何 W=${W} H=${H} FRAME_BYTES=${FRAME_BYTES}；要落盘加 --write，要核对磁盘加 --check，要看复现性加 --selftest`);
