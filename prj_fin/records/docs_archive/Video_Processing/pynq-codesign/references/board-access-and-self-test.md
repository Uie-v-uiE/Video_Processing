# 上板访问、自检与数据留存

## 适用范围

第一次拿到 PYNQ 板、或者要在比赛现场“复现给别人看”的时候：登录方式、权限、缺网怎么
办、怎么把一次跑通变成可核查的数据。初级组丢分最多的是“能演示但没数据”，其次是
“在 Jupyter 里跑通了但脚本不可复现”。

## 使用方法

1. 登录与权限（v3.1 镜像官方口径）：
   - 浏览器 `http://192.168.2.99`（默认主机名 `pynq`，默认静态 IP 就是这个）；
     用户名 `xilinx`，密码 `xilinx`。
   - USB 串口 115200 8N1，提示符 `xilinx@pynq:~$`
     （<https://pynq.readthedocs.io/en/v3.1/getting_started/terminal.html>）。
   - Jupyter 里 New ▸ Terminal 打开的是 **root** 终端；`MMIO` 需要 root（`/dev/mem`）。
   - 局域网共享：`\\192.168.2.99\xilinx`，拷 `.bit/.hwh/py` 比 scp 直观。
2. 没网是默认状态：“unless you can bridge the Ethernet connection … your board will not
   have Internet access”，所以不要指望板上 `pip install`。把依赖放在主机侧，板子上只跑
   标准库 + `pynq` + `numpy`
   （<https://pynq.readthedocs.io/en/v3.1/getting_started/network_connection.html>）。
   本包的脚本全部 stdlib，正是为了这一点。
3. 现场最小流程（每条都是一行命令，可直接抄）：

   ```bash
   scp design.bit design.hwh xilinx@192.168.2.99:/home/xilinx/design/
   ssh xilinx@192.168.2.99 'sudo python3 /home/xilinx/design/overlay_load_and_verify.py /home/xilinx/design/design'
   ssh xilinx@192.168.2.99 'sudo python3 /home/xilinx/design/capture_metrics.py --out /home/xilinx/design/metrics.csv'
   scp xilinx@192.168.2.99:/home/xilinx/design/metrics.csv data/
   python3 scripts/measure_report.py data/metrics.csv --require fps,luts,wns --md
   ```

4. `metrics.csv` 的表头固定为 `name,value,unit,spec,source`，`spec` 写
   `min:60` / `max:23040` / `range:0.5-2` / `declare`；`source` 必须是产生这个数字的
   日志或脚本路径。`measure_report.py` 会：
   - 把 `未测`、`n/a`、`-` 之类占位值判为 `NOT_MEASURED`（退出码 2）；
   - 把同名不同值的重复指标判红（这是报告里最常见的自相矛盾）；
   - 把没有 `source` 的行点名（数字必须可追溯）。
5. 板级自检用官方 pytest 套件，不要只跑自己的脚本：
   `cd /home/xilinx/pynq && sudo py.test -vsrw`（官方页里就是这条，注意文档中出现了
   一个en dash（U+2013），不是半角减号也不是全角连字符 `-vsrw`，实际输入半角）
   （<https://pynq.readthedocs.io/en/v3.1/appendix/verification.html>）。
   部分用例需要回环线或交互确认（会问 `Test trace analyzers? ([yes]/no)`）。
6. 赛事方远程板卡：报名后开放 PYNQ-Z2 与 KV260 远程使用（指南第四节）。远程板的串口与
   重启窗口受限，所以更要靠第 3 步的可复现脚本而不是手点。

## 失效条件

- 换镜像就换 API：任何“板上 `import` 失败”先怀疑版本（差异见 `references/sources.md`），
  而不是怀疑代码。
- 用普通用户跑 `MMIO`/`DMA`：会得到 `Root permissions required.` 或 mmap 失败，
  不是权限不够而是 `/dev/mem` 受限。
- 把 Jupyter Notebook 当唯一交付物：Notebook 的顺序依赖会让“他人从零复现”失败，
  必须同时提供 `.py` 入口脚本与一条命令。
- `metrics.csv` 手工填数：`measure_report.py` 只保证形状与判定，数据来源仍需
  `source` 列指向真实日志；空 source 会被点名。

## 已验证效果

```bash
python3 scripts/measure_report.py --selftest   # checked=7 red=0 PASS
```

其中三条是阴性对照：占位值与缺失必填指标必须 `NOT_MEASURED`（退出码 2），同名冲突值必须
判红。完整命令与输出集中在 `evals/results/tool_evidence.txt`，交作品时随包提交即可复查。
板上部分（登录、pytest）本机无硬件、未实测，步骤按官方文档抄写并注明出处。

## 来源

v3.1 Getting started / Terminal / Network / Verification 四页（见上），
镜像烧写页 <https://pynq.readthedocs.io/en/v3.1/pynq_sd_card.html>
（Ubuntu 22.04 构建主机，Vivado/Vitis/PetaLinux 2024.1）。
