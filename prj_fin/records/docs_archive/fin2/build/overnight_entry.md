
## 2026-10-22 凌晨：r162 定版、固件两条命令行修正、校验和台架补洞

- **r162 定版**：UDP 发送 IPv4 头校验和从一拍 10 项拆成 4 拍，WNS 1.172→1.378 ns、WHS 0.046 ns，失败端点 0；四支 ETH 台架 PASS，JTAG 上板 FLASH/HEALTH GREEN，10 秒 11 包遥测。位流 `84076c0f1961`。
- **r163 否决**：给 ARP/ICMP 各加本地复位同步器，post-route WNS 0.920，明显更差；源已按 r162 逐字节还原，报告留在 `build/r163/`。结论：这条复位恢复不能靠再复制同步器压，得换拓扑。
- **固件两条**：`main.c` 的超长行从“截断前缀照常派发”改成“整行丢弃”；`src 2` 改成先确认 `sd_play(1)` 成功再切源。A/B 用 128 字节 `th 120` + 空格 + 哨兵：老 ELF 读回 thr=120，新 ELF 保持 80；扩展探针 O0–O5 PASS；105 条命令电池 97.5 s PASS。最终 ELF `c5be592ca30d`。
- **台架补洞**：`tb_udp_telemetry` 原来不验 IPv4 头校验和，少加一项照样绿；补了 10 个 16 bit 字求和折叠判据后，变异体 T1/T2 报 `FAIL ip checksum sum=003c`，恢复源码后四支全过。日志 `build/msim/r162_checksum_mutation_fail3.txt` / `r162_checksum_final4.txt`。
- **文档/包**：A3/A4/A10 的“未修”状态按证据改成已关闭或只剩 #200；`doc-audit` 记下 C1–C12 的 6 绿/1 红/5 未测（C6 是检查器找 `skills/`、本包用 `skill/`，没有为变绿改尺子）；导出补上 `build/reports/`、`build/msim/*.txt`、重建 ELF 与固件备份，`fin` 现在 1183 文件 / 71 MB，MANIFEST 身份为 `84076c0f1961` / `9462460d1f29` / `c5be592ca30d`。
