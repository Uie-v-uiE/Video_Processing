#!/usr/bin/env python3
"""build/build_ps_app.py —— 不用 Vitis IDE，把 src/ps 直接编成板上能跑的 ELF。

为什么要脚本化：交付要求"从零复现"，而"在 IDE 里手工点 New Platform / New Application"
不属于能复现的步骤。另外这个 app 只需要 PS 侧的 xparameters（UART/SD/DDR/GLOBALTIMER），
PL 侧一律走 literal 地址（0x41200000 / 0x10000000），所以 BSP 只要 PS7 配置一致就能用。

输入（全部可用环境变量覆盖，**没有一个默认值指向某台机器的绝对路径**）：
  PS_CC    arm-none-eabi-gcc 的前缀或完整路径。不设就假定工具链已在 PATH 上
           （把 <Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin 放进 PATH 即可）
  PS_BSP   一个已经 generate 过的 zynq BSP 目录（里面有 include/ 与 lib/libxil.a）；
           默认指**仓库内**的那份：vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp
  PS_OBJ   中间产物目录（默认 build/ps_obj）
  PS_OUT   输出 ELF 的路径（默认 build/ps_app.elf；想验证脚本而不动交付件时指到别处）

用法：python3 build/build_ps_app.py [--clean]

没有现成平台时怎么得到一个（一次性，手工，之后就能一直用本脚本）：
  Vitis → New → Platform → 选 build/system.xsa → BSP 勾 uartps/xsdps/xgpiops → Generate。
  把生成目录里的 standalone_ps7_cortexa9_0/bsp 指给 PS_BSP 即可。

退出码：2 输入不在 / 1 编译或链接失败 / 3 成品自检不过（"链接成功"不等于可执行，见下面
self_check 的注释）。这三个码是分开给的，因为把"空镜像下到板上"和"工具链没装"混成一种报错，
会让人去怀疑自己改的代码。
"""
import io
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CC = os.environ.get("PS_CC") or "arm-none-eabi-gcc"
BSP = os.environ.get("PS_BSP") or os.path.join(
    ROOT, "vitis", "platform", "ps7_cortexa9_0", "standalone_ps7_cortexa9_0", "bsp")
SRC = os.path.join(ROOT, "src", "ps")
OBJ = os.environ.get("PS_OBJ") or os.path.join(ROOT, "build", "ps_obj")
OUT = os.environ.get("PS_OUT") or os.path.join(ROOT, "build", "ps_app.elf")

BSP_ASM = ["asm_vectors.S", "boot.S", "translation_table.S"]
REQUIRED_SYMBOLS = [(r"\bT _start\b", "_start"), (r"\bT _boot\b", "_boot"),
                    (r"\bT _vector_table\b", "_vector_table"), (r"MMUTable", "MMUTable"),
                    (r"\bT main\b", "main"), (r"XSdPs_CardInitialize", "XSdPs_CardInitialize")]
MIN_TEXT = 20000


def tool(suffix):
    """把 gcc 的路径换成同目录里的 size/nm/readelf；CC 只是个名字时就交给 PATH。"""
    if os.path.sep in CC:
        return re.sub(r"gcc(\.exe)?$", suffix, CC)
    return suffix


def need(path, what):
    if not os.path.isfile(path):
        print("FATAL: %s 不存在：%s" % (what, path))
        print("  用 PS_CC / PS_BSP 环境变量指到实际位置（见本文件头部注释）。")
        sys.exit(2)


def run(args):
    """编译告警走 stderr，而成功时不会随返回值带回来 ⇒ 必须自己转发，否则 -Wall/-Wextra 等于没开。
    args 是**给编译器的参数**，编译器本体由 CC 决定（这里拼上）。"""
    proc = subprocess.run([CC] + args, cwd=OBJ, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          universal_newlines=True)
    if proc.stdout and proc.stdout.strip():
        sys.stdout.write(proc.stdout)
    if proc.stderr and proc.stderr.strip():
        sys.stderr.write(proc.stderr)
    if proc.returncode != 0:
        print("FATAL: 编译/链接失败 (exit %d)" % proc.returncode)
        sys.exit(1)
    return proc.stdout or ""


def capture(exe, args):
    try:
        return subprocess.run([exe] + args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              universal_newlines=True).stdout
    except OSError as e:
        print("FATAL: 跑不起来 %s（%s）—— 设 PS_CC 或把工具链的 bin 放进 PATH" % (exe, e))
        sys.exit(2)


def cflags():
    return ["-mcpu=cortex-a9", "-mfpu=vfpv3", "-mfloat-abi=hard",
            # 非对齐访问：板上撞到过两处，症状一模一样（data abort），根因不同。
            # ① -O2 会把逐字节读合并成一条 ldr（objdump 里看得见，源码没写错）⇒ 关掉合并。
            # ② newlib memcpy 的半字快路径：预编译的库改不了，只能按它的前提来——
            #    **MMU 关掉时非对齐访问一定 fault**（SCTLR.A=0 的豁免只在 MMU 开着时成立），
            #    而 MMU 是标准启动 boot.S 开的 ⇒ 这条选项 + 链上那三个 BSP 启动文件，两条一起才成立。
            "-mno-unaligned-access", "-DSDT",
            "-ffunction-sections", "-fdata-sections", "-Wall", "-Wextra", "-Wno-unused-parameter",
            "-O2", "-I" + os.path.join(BSP, "include"), "-specs=" + os.path.join(BSP, "Xilinx.spec")]


def compile_units(objs):
    srcs = sorted(f for f in os.listdir(SRC) if re.search(r"\.(c|S)$", f))
    if not srcs:
        print("FATAL: src/ps 下没有 .c")
        sys.exit(2)
    for f in srcs:
        o = re.sub(r"\.(c|S)$", ".o", f)
        print("CC  %s" % f)
        run(cflags() + ["-c", os.path.join(SRC, f), "-o", o])
        objs.append(o)
    # BSP 自己的三个启动文件必须进来：asm_vectors.S(_vector_table 与把出错地址写进全局的那些
    # handler)、boot.S(_boot：设 VBAR、六个模式的栈、CPACR+FPEXC、L2/SCU、开 MMU 再 b _start)、
    # translation_table.S(MMUTable)。链接脚本的 ENTRY 改成 _boot 之后这三个对象没人引用，
    # --gc-sections 会全裁；裁掉的后果今晚全数兑现过（#42 与"异常可诊断"那两族）。
    asm_dir = os.path.join(BSP, "libsrc", "standalone", "src", "arm", "cortexa9", "gcc")
    for f in BSP_ASM:
        p = os.path.join(asm_dir, f)
        need(p, "BSP startup asm")
        o = "bsp_" + re.sub(r"\.S$", ".o", f)
        print("CC  BSP/%s" % f)
        run(cflags() + ["-c", p, "-o", o])
        objs.append(o)
    return srcs


def link(objs, lds):
    print("LD  %s" % os.path.basename(OUT))
    # 三个归档都得给：2025.2 的 BSP 把驱动、standalone、xiltimer 分装成 libxil.a /
    # libxilstandalone.a / libxiltimer.a，而 _start 只在中间那个里。少了它，入口符号找不到、
    # --gc-sections 又把没人引用的 main 裁掉 ⇒ "链接成功"但镜像是空的。
    # 入口只从脚本走（lscript_ocm.ld 的 ENTRY(_boot)）：命令行 -Wl,-e,_boot 会被脚本顶掉，
    # readelf 的入口悄悄变成 0x0，一声不响——self_check 里那条等值校验就是它的哨兵。
    run(cflags() + objs + ["-Wl,--gc-sections", "-Wl,-n", "-Wl,--no-warn-mismatch",
                           "-T" + lds, "-L" + os.path.join(BSP, "lib"), "-Wl,--start-group",
                           # -lm 是 gamma 曲线（pow）要的；放进 group 是因为 newlib 的 libm 反过来依赖 libc
                           "-lxil", "-lxilstandalone", "-lxiltimer", "-lgcc", "-lc", "-lm",
                           "-Wl,--end-group", "-o", OUT])


def self_check():
    """成品自检：符号在 ≠ 从它开始跑，也 ≠ 向量表在 CPU 会去找的地址上。所以判**等值**。"""
    sz = capture(tool("size.exe"), ["-A", OUT])
    print("\n".join("    " + l for l in sz.splitlines()))
    nm = capture(tool("nm.exe"), ["-g", OUT])
    for pattern, what in REQUIRED_SYMBOLS:
        if not re.search(pattern, nm):
            print("FATAL: %s 不在 ELF 里 —— 链接被 --gc-sections 裁掉了，别把空镜像下到板上" % what)
            sys.exit(3)
    m = re.search(r"(?:^|\n)\s*\.text\s+(\d+)", sz)
    if not m or int(m.group(1)) < MIN_TEXT:
        print("FATAL: .text = %s B，远小于这个 app 应有的体积（下界 %d）"
              % (m.group(1) if m else "?", MIN_TEXT))
        sys.exit(3)
    reh = capture(tool("readelf.exe"), ["-h", OUT])
    # readelf 打的是 `0xcc`：早先这里写 `0*([0-9a-f]+)`，'0' 被 0* 吃掉后捕获到空 ⇒ 入口永远
    # 被读成 0，判据本身就是坏的（规矩：判据也要有测试）。改成显式剥 0x 前缀。
    ep = re.search(r"Entry point address:\s+(?:0x)?([0-9a-f]+)", reh, re.I)

    def sym(name):
        s = re.search(r"([0-9a-f]+) [Tt] %s\b" % re.escape(name), nm)
        return s.group(1) if s else None

    vt, bt, st = sym("_vector_table"), sym("_boot"), sym("_start")
    if not ep or not vt or not bt or not st:
        print("FATAL: 取不到入口/符号地址 (readelf=%s, _vector_table=%s, _boot=%s, _start=%s)"
              % ("ok" if ep else "无 Entry point 行", vt or "?", bt or "?", st or "?"))
        sys.exit(3)
    if int(ep.group(1), 16) != int(bt, 16):
        print("FATAL: ELF 入口 0x%s != _boot 0x%s —— 标准启动没跑，VBAR/栈/MMU 都没设"
              % (ep.group(1), bt))
        sys.exit(3)
    if int(vt, 16) != 0:
        print("FATAL: _vector_table 不在 0x0（实际 0x%s）—— VBAR 复位值就是 0，表放别处等于没有表" % vt)
        sys.exit(3)
    print("ENTRY _boot@0x%s  (_vector_table@0x%s -> 0x0 是 b _boot)  _start@0x%s  OK" % (bt, vt, st))


def main():
    need(os.path.join(BSP, "include", "xparameters.h"), "BSP xparameters.h")
    need(os.path.join(BSP, "lib", "libxil.a"), "BSP libxil.a")
    if os.path.sep in CC:
        need(CC, "arm-none-eabi-gcc")
    elif not shutil.which(CC):
        print("FATAL: PATH 上找不到 %s；设 PS_CC=<...>/bin/arm-none-eabi-gcc.exe 或把工具链 bin 放进 PATH" % CC)
        sys.exit(2)
    lds = os.path.join(SRC, "lscript_ocm.ld")
    need(lds, "linker script")
    if "--clean" in sys.argv and os.path.isdir(OBJ):
        shutil.rmtree(OBJ, ignore_errors=True)
    os.makedirs(OBJ, exist_ok=True)
    objs = []
    compile_units(objs)
    link(objs, lds)
    self_check()
    print("OK  " + OUT)
    print("板上跑法（JTAG，不写 flash）：xsdb> source build/tcl/ps_jtag_boot.tcl（含 ps7_init）")
    print("                             xsdb> targets -set -filter {name =~ \"ps7_cortexa9_0*\"} ; download <elf> ; con")


if __name__ == "__main__":
    main()
