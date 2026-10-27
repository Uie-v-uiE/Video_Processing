// 只有一个网络调用，写文件的地方一个都没有。
export async function go() { return await fetch('https://example.invalid/t'); }
