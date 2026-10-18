"""作用：用脚本重建 Vitis 工程（平台 + PS 应用），替代"在 IDE 里手点一遍"。
输入：`build/system.xsa`（由 `build/tcl/build_system_axigpio.tcl` 产出）、`src/ps/` 下的固件源文件。
输出：workspace `board/vitis_ws/` 下的 `vitis_platform` 与 `video_ps` 两个组件；平台 generate、应用 build；
      末尾打印 `VITIS_REBUILD_DONE` 与产物路径，失败打印 `VITIS_REBUILD_FAIL <阶段>`。
退出码：0=平台与应用都建成；1=任一阶段失败（不静默）。
跑法（从仓库根）：
    (nohup <Vitis>/bin/vitis-server --port 8879 &) ; sleep 10
    <Vitis>/bin/vitis.bat -s board/scripts/rebuild_vitis.py 8879
为什么要显式起 server：`create_client()` 不带 port 时在本机报
`'utf-8' codec can't decode byte 0xd5`（2026-10-19 实测，见 report/log/issues.md #487）。
"""
import os
import shutil
import sys

import vitis

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WS = os.environ.get("VP_VITIS_WS") or os.path.join(REPO, "board", "vitis_ws")
XSA = os.path.join(REPO, "build", "system.xsa")
PS_SRC = os.path.join(REPO, "src", "ps")
DOMAIN = "standalone_ps7_cortexa9_0"


def main():
    nums = [a for a in sys.argv[1:] if a.isdigit()]
    port = int(nums[0]) if nums else None
    os.makedirs(WS, exist_ok=True)
    if not os.path.exists(XSA):
        print("VITIS_REBUILD_FAIL xsa-missing %s" % XSA)
        return 1
    client = vitis.create_client(port=port, workspace=WS) if port else vitis.create_client(workspace=WS)
    print("WS %s" % client.get_workspace())

    def show(o):
        return o() if callable(o) else o

    try:
        plat = client.create_platform_component(name="vitis_platform", hw_design=XSA)
    except Exception as e:
        print("CREATE_PLATFORM_RETRY %s: %s" % (type(e).__name__, str(e)[:160]))
        plat = client.get_component("vitis_platform")
    print("PLAT_AT %s" % show(plat.project_location))
    try:
        plat.add_domain(cpu="ps7_cortexa9_0", os="standalone", name=DOMAIN, support_app=True)
        print("ADD_DOMAIN ok")
    except Exception as e:
        print("ADD_DOMAIN_FAIL %s: %s" % (type(e).__name__, str(e)[:160]))
    print("GENERATE_RC %r" % (show(plat.build),))

    try:
        app = client.create_app_component(name="video_ps", platform="vitis_platform", domain=DOMAIN,
                                          cpu="ps7_cortexa9_0", os="standalone", template="empty_application")
    except Exception as e:
        print("CREATE_APP_RETRY %s" % type(e).__name__)
        app = client.get_component("video_ps")
    print("APP_METHODS %s" % [m for m in dir(app) if not m.startswith("_")])
    print("APP_BUILD_RC1 %r" % (app.build(),))

    # 应用源目录不靠猜 getter：建完之后在 workspace 里找 `video_ps/**/src`
    roots = [os.path.join(r, d) for r, ds, _ in os.walk(WS) for d in ds
             if d == "src" and os.sep + "video_ps" in r]
    print("APP_SRC_ROOTS %d %s" % (len(roots), roots[:2]))
    if roots:
        for f in sorted(os.listdir(PS_SRC)):
            if f.endswith((".c", ".h")):
                shutil.copyfile(os.path.join(PS_SRC, f), os.path.join(roots[0], f))
        print("COPIED_PS %s -> %s" % (PS_SRC, roots[0]))
        print("APP_BUILD_RC2 %r" % (app.build(),))
    elf = []
    for r, _, fs in os.walk(WS):
        for f in fs:
            if f.endswith(".elf"):
                elf.append(os.path.join(r, f))
    print("ELFS %d %s" % (len(elf), elf[:3]))
    print("VITIS_REBUILD_DONE ws=%s" % WS)
    vitis.dispose()
    return 0


if __name__ == "__main__":
    sys.exit(main())
