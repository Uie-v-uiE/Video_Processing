// 合成判据 5（对照件）：跑的过程中抛异常 ⇒ 没跑出判定就是 NOT_MEASURED（既不绿也不假装红）
export const ID = 'crash-gate';

export function run() {
  throw new Error('读输入件时炸了（合成）');
}
