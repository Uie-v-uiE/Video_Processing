// 双击演示入口改口径：先 ping 并显示正常 ping 结果，再推内置测试图 300 s（5 分钟）。
// 作用：换掉根目录 send_demo.bat 这一份双击入口（输入=三棵树里的现文件，输出=改写后的 .bat 与 host_guide 那一行）。
// 退出码：0 = 规则全部判完且无坏规则（--check 不落盘）；1 = 有坏规则、Σ 不闭合，或没给树根。
// 树根由命令行给（相对路径）——本文件不许出现绝对路径，交付包的绝对路径判据会拒收整包。
// 用法：node build/r127_demo_entry.mjs --check|--apply <树根> [<树根> …]
import fs from 'node:fs';
import path from 'node:path';

const APPLY = process.argv.includes('--apply');
const TREES = process.argv.slice(2).filter((a) => !a.startsWith('--')).map((a) => a.replace(/[\\/]+$/, ''));
if (!TREES.length) { console.log('用法：node build/r127_demo_entry.mjs --check|--apply <树根> …'); process.exit(1); }

// .bat 要 CRLF：cmd.exe 对 LF-only 批处理的 if 块解析不稳
const BAT = [
  '@echo off',
  'rem send_demo.bat - Purpose: double-click demo entry for the panel. Step 1 pings the board and',
  'rem        leaves the normal ping output on screen; step 2 streams the BUILT-IN test pattern for',
  'rem        DEMO_SECONDS (default 300 s = 5 minutes) so the picture can be watched and photographed',
  'rem        without the clip ending mid-sentence. Tool behind it: src/host/video_sender.py --demo',
  'rem        (Python 3 standard library only; ffmpeg is needed only for your own video file).',
  'rem Usage: send_demo.bat            = ping + 300 s built-in pattern at 192.168.1.10:5001',
  'rem        send_demo.bat my.mp4      = ping + stream your own file (needs ffmpeg)',
  'rem        Change the length or the address by editing the two set lines below.',
  'rem Exit code: whatever video_sender.py returns (0 = finished normally).',
  'setlocal',
  'cd /d "%~dp0"',
  'chcp 65001 >nul',
  'set BOARD_IP=192.168.1.10',
  'set DEMO_SECONDS=300',
  'where python >nul 2>&1',
  'if errorlevel 1 (',
  '  echo [ERR] python not found in PATH. Install Python 3 and open this file again.',
  '  pause',
  '  exit /b 1',
  ')',
  'echo [STEP 1] ping %BOARD_IP%',
  'ping -n 4 %BOARD_IP%',
  'echo.',
  'if "%~1"=="" (',
  '  echo [STEP 2] push the built-in test pattern for %DEMO_SECONDS% s',
  '  python src\\host\\video_sender.py --demo --ip %BOARD_IP% --seconds %DEMO_SECONDS%',
  ') else (',
  '  echo [STEP 2] pushing "%~1" - decoding needs ffmpeg',
  '  python src\\host\\video_sender.py --input "%~1" --demo --ip %BOARD_IP% --seconds %DEMO_SECONDS%',
  ')',
  'set RC=%ERRORLEVEL%',
  'echo.',
  'echo [DONE] exit code %RC%. On the panel the moving white line and the red block prove frames',
  'echo        are swapped atomically; the counters behind it are readable over the serial port and',
  'echo        by JTAG (see report/host_guide.md). Press any key.',
  'pause >nul',
  'exit /b %RC%',
  '',
].join('\r\n');

const HG_OLD = '再推 12 s';
const HG_NEW = '再推 300 s（5 分钟；时长与地址写在脚本开头两个 `set` 里，可改）';

let bat = 0, hg = 0, bad = 0, rules = 0;
for (const tree of TREES) {
  if (!fs.existsSync(tree)) { console.log(`跳过（树不在）：${tree}`); continue; }
  const b = path.join(tree, 'send_demo.bat');
  const h = path.join(tree, 'report', 'host_guide.md');
  rules += 2;
  const want = BAT;
  if (fs.existsSync(b)) {
    const cur = fs.readFileSync(b, 'utf8');
    if (cur === want) { hg++; console.log(`已在位 ${b}`); }
    else { if (APPLY) fs.writeFileSync(b, want); bat++; console.log(`${APPLY ? '已写' : '待写'} ${b}（旧 ${cur.length} 字节 → 新 ${want.length} 字节，CRLF=${want.split('\r\n').length - 1} 行）`); }
  } else { bad++; console.log(`BAD 文件不在：${b}`); }
  if (fs.existsSync(h)) {
    const t = fs.readFileSync(h, 'utf8');
    const nOld = t.split(HG_OLD).length - 1, nNew = t.split(HG_NEW).length - 1;
    if (nOld === 1) { if (APPLY) fs.writeFileSync(h, t.replace(HG_OLD, HG_NEW)); hg++; console.log(`${APPLY ? '已改' : '待改'} ${h}`); }
    else if (nOld === 0 && nNew === 1) { hg++; console.log(`已在位 ${h}`); }
    else { bad++; console.log(`BAD ${h} 旧串=${nOld} 新串=${nNew}（要 1/0 或 0/1）`); }
  } else { bad++; console.log(`BAD 文件不在：${h}`); }
}
console.log(`双击演示入口  规则×树=${rules}  写/改=${bat + hg}  不命中/坏=${bad}  ${APPLY ? '已落盘' : '（--check 未落盘）'}`);
if (bat + hg + bad !== rules) { console.log(`REFUSE 判定 ${bat + hg + bad} ≠ 规则 ${rules}`); process.exit(1); }
if (bad) { console.log('REFUSE 有坏规则'); process.exit(1); }
