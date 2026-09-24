// lane30_watch.mjs —— 连采"仲裁看得见的那一口"（lane30），查**没人按键时 mode 会不会自己动**
//
// 用户报了两件看起来矛盾的事：
//   ① 显示 ETH 时"过一会偶然变成彗星图卡"；② 长按有时没反应，要先点一下再长按才稳。
// ① 的两种成因在屏幕上长得一模一样：
//   (A) 凭空多出的长按事件 ⇒ src_mode 自己走格 ⇒ 走到"锁图卡"就是图卡；
//   (B) `have_src` 用的是"链路活着"(eth_link_pix) 而不是"有已提交帧" ⇒ 推流偶发 >200 ms 空档、
//       且 PS 的发布从没被消费过 (ps_src_seen=0) ⇒ have_src 掉 0 ⇒ AUTO 下 fb_vis=0 ⇒ 露出图卡。
// lane30 把 mode 与 owner/live 都读回来了 ⇒ 一次采样分开两种解释：
//   没人按键时 mode[6:5] 只要变过一次 ⇒ (A)；mode 一直是 0 而画面会跳 ⇒ (B)。
//
// 用法：node src/host/lane30_watch.mjs [秒=45] [间隔ms=150]
// 唯一写的是 gpio_o 的 lane 字段 [31:27]（写完立刻读回；PS 应用下一帧会把整字重写回去 ——
// 这是 health_read.mjs 一直在用的回读窗口）。
import { execSync } from 'node:child_process';
import { writeFileSync, readFileSync } from 'node:fs';
import { dump } from './repo_path.mjs';

const SECS = Number(process.argv[2] || 45);
const GAP = Number(process.argv[3] || 150);
const N = Math.max(4, Math.floor(SECS * 1000 / GAP));
const XSDB = 'D:\\Software\\Vivado\\2025.2.1\\Vitis\\bin\\xsdb.bat';

// mrd 的返回值形如 "41200000:   000b5000" ⇒ 用 regexp 取数，不 lindex（坑记在 skill 里）。
const TCL = [
  'catch {connect -host localhost -port 3121} ce',
  'puts "CONNECT=$ce"',
  'targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}',
  'puts "RAW=[mrd -force 0x41200000]"',
  'for {set i 0} {$i < ' + N + '} {incr i} {',
  '  set gv ""',
  '  regexp {:\\s*([0-9a-fA-F]{1,8})} [mrd -force 0x41200000] -> gv',
  '  if {$gv eq ""} { puts "BADG $i"; after ' + GAP + '; continue }',
  '  scan $gv {%x} gi',
  '  set keep [expr {$gi & 0x07FFFFFF}]',
  '  catch {mwr -force 0x41200000 [format 0x%08x [expr {$keep | (30 << 27)}]]}',
  '  set sv ""',
  '  regexp {:\\s*([0-9a-fA-F]{1,8})} [mrd -force 0x41210000] -> sv',
  '  if {$sv eq ""} { puts "BADS $i"; after ' + GAP + '; continue }',
  '  puts "S $i $sv $gv"',
  '  after ' + GAP,
  '}',
  'puts WATCH_DONE',
].join('\n');

const f = dump('lane30_watch.tcl');
writeFileSync(f, TCL);
try { execSync('"' + XSDB + '" ' + f + ' > "' + dump('lane30_watch.out') + '" 2>&1',
               { windowsVerbatimArguments: true }); }
catch (e) { /* 输出全在文件里，判据也从文件读 */ }
const txt = readFileSync(dump('lane30_watch.out'), 'utf8');

const rows = [];
for (const line of txt.split('\n')) {
  const k = /^S (\d+) ([0-9a-fA-F]{1,8}) ([0-9a-fA-F]{1,8})/.exec(line.trim());
  if (k) rows.push({ t: +k[1], lane30: parseInt(k[2], 16), gpio0: parseInt(k[3], 16) });
}
if (rows.length === 0) {
  console.log('PARSE_FAIL —— 一条都没采到。xsdb 输出前 10 行：');
  console.log(txt.split('\n').slice(0, 10).join('\n'));
  process.exit(1);
}

let prev = null, changes = 0, modeSteps = 0, liveDrops = 0;
for (const r of rows) {
  const b = i => (r.lane30 >> i) & 1;
  const mode = (r.lane30 >> 5) & 3;
  const sig = [0, 1, 2, 3, 4].map(b).join('') + '|' + mode;      // tb_ok live owner fill row | mode
  if (prev !== null && sig !== prev) {
    changes++;
    if (mode !== +prev.slice(-1)) modeSteps++;
    if (prev[1] === '1' && b(1) === 0) liveDrops++;
    console.log('t=' + (r.t * GAP / 1000).toFixed(2) + 's  ' + prev + ' -> ' + sig +
      '  (lane30=0x' + (r.lane30 >>> 0).toString(16) + ' gpio0=0x' + (r.gpio0 >>> 0).toString(16) + ')');
  }
  prev = sig;
}
const hist = {};
for (const r of rows) { const m = (r.lane30 >> 5) & 3; hist[m] = (hist[m] || 0) + 1; }
console.log('\n采样 ' + rows.length + ' 次，间隔 ' + GAP + ' ms（约 ' +
  (rows.length * GAP / 1000).toFixed(0) + ' s）');
console.log('mode 直方图 ' + JSON.stringify(hist) + ' —— 没人按键时应当只有 {"0":N}');
console.log('lane30 共变 ' + changes + ' 次；其中 mode 变 ' + modeSteps + ' 次、eth_live 掉 ' + liveDrops + ' 次');
console.log('(位序 bit0=eth_tb_ok bit1=eth_live bit2=owner_eth bit3=fill_busy bit4=row_busy bit[6:5]=mode)');
console.log(modeSteps === 0
  ? (liveDrops > 0
      ? '=> 没有凭空走格；但 eth_live 会瞬断 ⇒ 图卡更像成因 (B)：have_src 用"活着"代替了"有已提交帧"'
      : '=> 没走格、也没见 live 掉 ⇒ 需要症状出现的那一刻再采一次（人在场）')
  : '=> 没人按键 mode 也动了 ⇒ key_long / src_mode 在凭空发事件，先修它');
