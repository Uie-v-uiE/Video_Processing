// 用途：合成判据 3（对照件）：一条比较都没做却自称通过 ⇒ 跑批器必须把它降级成 NOT_MEASURED
// 输入：无字面量输入路径；参数解析见本文件
// 输出：stdout（本文件没有仓库内的写盘路径字面量）
// 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
// 合成判据 3（对照件）：一条比较都没做却自称通过 ⇒ 跑批器必须把它降级成 NOT_MEASURED
export const ID = 'vacuous-green';

export function run() {
  return { id: ID, detail: '恒绿、且一次 ctx.cmp 都没调（真空通过的样子）', verdict: 'PASS' };
}
