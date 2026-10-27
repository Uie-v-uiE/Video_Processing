# ISSUES #53 的机器凭据：ETH 与 SD 是否共用同一个 DDR bank（不用看屏幕）
#
# 工具：`board/ddr_churn_probe.mjs`（本次新增）
#   node board/ddr_churn_probe.mjs 60 25          # 60 轮、每轮 3 个地址、每轮 25 ms
# 前置：板子已 ps7_init + program bit（c7f90cc），`--test wordid` 正在推流，SD 自动播放中。
#
# 为什么不能用现成的 `src/host/ddr_verify.mjs` 判这一条：
#   它在回读前先 `catch {rst -processor}`（注释里写明是为了躲 Vitis 应用的 D-Cache 旧数据），
#   而这一下**正好把要观察的写入者停掉**，之后 PL 每 66 ms 就把 bank 重新刷成干净图案，
#   于是"两 bank 全绿"在修复前也照样成立 —— 实测见下面【反例：判据不敏感】。
#   抓写竞态必须**边跑边采**，这就是本探针存在的唯一理由。
#
# 图案与判据：wordid 图案里每个 32bit 字 = (bank 内字序>>1) 复制两遍，且**只与地址有关、
# 不随帧变化** ⇒ 一个地址若反复出现多个值，就说明有别的东西在写这块 DDR。
# 采样点 0x40（每个 bank 的第 16 个 u32）⇒ 期望值恒为 0x00080008。

【绿：修复后的固件 dcdce9b9（PS 片源搬到第三个 bank 0x1010_0000）】
$ node board/ddr_churn_probe.mjs 60 25        # 原始输出见 ddr_churn_r33_newelf.txt
0x10000040  n=60  distinct=  1  wordid_clean=60/60  STATIC  top=[80008x60]
0x10080040  n=60  distinct=  1  wordid_clean=60/60  STATIC  top=[80008x60]
0x10100040  n=60  distinct= 32  wordid_clean= 0/60  CHURNING(有写入)  top=[4fe051ex10 4fe0d1dx5 49d049dx4]
→ ETH 的两个乒乓 bank 全程只有推流内容；SD 帧（32 个不同值 = 真实像素）只落在 PS 专用 bank。

【红：同一块 bit、同一个仲裁器，只把 elf 换回修复前的 c00b6553（FRAME_ADDR=0x1000_0000）】
$ cmd //c "xsdb.bat build/tcl/ps_app_reload.tcl build/frozen_r32_sdfix/ps_app.elf"   # DOW ok / RESUME ok
$ node board/ddr_churn_probe.mjs 60 25
0x10000040  n=60  distinct= 22  wordid_clean=12/60  CHURNING(有写入)  top=[3390338x15 80008x12 3170317x8]
0x10080040  n=60  distinct=  1  wordid_clean=60/60  STATIC  top=[80008x60]
0x10100040  n=60  distinct=  1  wordid_clean= 0/60  STATIC  top=[2760275x60]
→ **60 次里有 48 次（80 %）ETH 的 bank0 装的已经不是 ETH 的画面**（0x03390338、0x03170317 是 RGB565
  像素值，且 0x10100040 完全静止 ⇒ 写入者就是 SD 播放）。这就是眼睛看到的"两个源打架、屏幕闪"的
  机理，也是"只有 bank0 被抢、bank1 没事"的直接证据（bank1 60/60 干净）。
（本段是从同一轮会话的 stdout 转录的，因为采完红之后要把板子留在可看的绿色状态；
  复现只需按上面两条命令再跑一次，探针本身不做任何写操作。）

【反例：判据不敏感（把我自己骗过一次的那次测量，保留下来当反面教材）】
$ node src/host/ddr_verify.mjs          # 修复前的 elf 也报全绿
[bank0] base=0x10000000 good=76800 bad=0 coverage=100.0%
[bank1] base=0x10080000 good=76800 bad=0 coverage=100.0%
→ 停止推流后再跑一次仍全绿 —— 因为它 `rst -processor` 把写入者停在了读之前。
  教训：**"会先把被测者停下来的检查器，看不见只有被测者活着才存在的竞态"**。
