/** build/r116_ab_summary.mjs —— 把两轮（r114 对照 / r116 复测）的健康读数并排念出来。
 *
 * 为什么要单独一个文件：在 bash 里内联 `node -e '...new RegExp("\\"pkt_err\\"...")'` 的反斜杠
 * 会被 shell 吃掉一层，结果三个字段全打成 "?"（看着像"没有这个计数器"，其实是正则没拼对）。
 * 判据要能读，读不出来的时候必须显式说"没读到"，不能留一个 "?" 冒充读数。
 */
import { readFileSync, existsSync } from 'node:fs';

const KEYS = ['drop_words', 'pkt_err', 'frames_bad', 'drop_seen', 'rx_ok', 'stall'];
const grab = (o, k) => {
  if (o && Object.prototype.hasOwnProperty.call(o, k)) return o[k];
  let found;
  for (const [key, v] of Object.entries(o || {})) {
    if (key === k) return v;
    if (v && typeof v === 'object') { const r = grab(v, k); if (r !== undefined) found = r; }
  }
  return found;
};

for (const label of process.argv.slice(2)) {
  for (const t of ['a', 'b']) {
    const f = `build/evidence/r116_board/health_${label}_${t}.json`;
    if (!existsSync(f)) { console.log(`${label}.${t} 文件不在 ⇒ 这一轮没测`); continue; }
    let j;
    try { j = JSON.parse(readFileSync(f, 'utf8')); }
    catch (e) { console.log(`${label}.${t} NOT_JSON：${readFileSync(f, 'utf8').slice(0, 70)}`); continue; }
    const ss = j.src_state || {};
    const cells = KEYS.map(k => {
      const v = grab(j, k);
      return `${k}=${v === undefined ? 'ABSENT' : v}`;
    });
    console.log(`${label}.${t} eth_live=${ss.eth_live} owner_eth=${ss.owner_eth} ${cells.join(' ')}`);
  }
}
