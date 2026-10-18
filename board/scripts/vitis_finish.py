"""作用：在已建好的 workspace 上补齐 standalone domain 与 PS 应用（`rebuild_vitis.py` 的后半段）。
输入：`VP_VITIS_WS` 指向的 workspace（里面有 `vitis_platform`）。输出：`SIG add_domain …`、
      `DOMAIN_ADDED`、`APP_BUILD_RC`、`ELFS`；失败逐条打印阶段名。退出码：0=应用建成。
跑法：先起 vitis-server，再 `vitis -s board/scripts/vitis_finish.py <port>`。
"""
import inspect
import os
import shutil
import sys

import vitis

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WS = os.environ.get("VP_VITIS_WS") or os.path.join(REPO, "board", "vitis_ws4")
PS_SRC = os.path.join(REPO, "src", "ps")
DOMAIN = "standalone_ps7_cortexa9_0"

nums = [a for a in sys.argv[1:] if a.isdigit()]
port = int(nums[0]) if nums else None
client = vitis.create_client(port=port, workspace=WS) if port else vitis.create_client(workspace=WS)
plat = client.get_component("vitis_platform")
sig = inspect.signature(plat.add_domain)
print("SIG add_domain %s" % sig)
params = list(sig.parameters)
doms = plat.list_domains()
print("DOMAINS_BEFORE %r" % (doms,))
if not any(DOMAIN in str(d) for d in (doms or [])):
    kw = {}
    for p in params:
        if p in ("self",):
            continue
        low = p.lower()
        if "name" in low and "domain" in low:
            kw[p] = DOMAIN
        elif low in ("os", "ostype", "os_name"):
            kw[p] = "standalone"
        elif "proc" in low or "cpu" in low:
            kw[p] = "ps7_cortexa9_0"
    print("ADD_DOMAIN_KW %r" % (kw,))
    try:
        kw["name"] = DOMAIN
        kw["support_app"] = True
        plat.add_domain(**kw)
        print("DOMAIN_ADDED %s" % DOMAIN)
        print("PLATFORM_REBUILD_RC %r" % (plat.build(),))
    except Exception as e:
        print("ADD_DOMAIN_FAIL %s: %s" % (type(e).__name__, str(e)[:200]))

app = None
try:
    app = client.create_app_component(name="video_ps", platform="vitis_platform", domain=DOMAIN,
                                      os="standalone", template="empty_application")
    print("APP_CREATED")
except Exception as e:
    print("APP_CREATE_FAIL %s: %s" % (type(e).__name__, str(e)[:200]))
    try:
        app = client.get_component("video_ps")
    except Exception as e2:
        print("APP_GET_FAIL %s" % type(e2).__name__)
if app is not None:
    print("APP_METHODS %s" % [m for m in dir(app) if not m.startswith("_")])
    print("APP_BUILD_RC1 %r" % (app.build(),))
    roots = [os.path.join(r, d) for r, ds, _ in os.walk(WS) for d in ds if d == "src" and "video_ps" in r]
    print("APP_SRC_ROOTS %d %s" % (len(roots), roots[:2]))
    if roots:
        for f in sorted(os.listdir(PS_SRC)):
            if f.endswith((".c", ".h")):
                shutil.copyfile(os.path.join(PS_SRC, f), os.path.join(roots[0], f))
        print("COPIED_PS -> %s" % roots[0])
        print("APP_BUILD_RC2 %r" % (app.build(),))
    elfs = [os.path.join(r, f) for r, _, fs in os.walk(WS) for f in fs if f.endswith(".elf")]
    print("ELFS %d %s" % (len(elfs), [os.path.basename(e) for e in elfs[:4]]))
vitis.dispose()
sys.exit(0 if app is not None else 1)
