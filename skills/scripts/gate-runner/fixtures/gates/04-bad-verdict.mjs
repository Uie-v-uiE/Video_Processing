// 用途：合成判据 4（对照件）：用了包外判定词 ⇒ 归 NOT_MEASURED，不许被当成通过
// 输入：无字面量输入路径；参数解析见本文件
// 输出：stdout（本文件没有仓库内的写盘路径字面量）
// 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
// 合成判据 4（对照件）：用了包外判定词 ⇒ 归 NOT_MEASURED，不许被当成通过
export const ID = 'bad-verdict';

export function run(ctx) {
  const ok = ctx.cmp('样本数 > 0', 3 > 0, true);
  return { id: ID, detail: `比较做了 1 次（结果=${ok}），但判定词写成 OK`, verdict: 'OK' };
}
