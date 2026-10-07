# 复现演练（合成文档，只用于 `--self`）

前置条件见 notes/setup.md，照着逐条做。
刷写用 tools/flash_host.mjs，跑它做身份校验。
打包时 tools/bit_gen.mjs 不随包，现场自备。
换算系数在 notes/appendix.md 里（未写，填了再跑）。

| 件 | 作用 |
|---|---|
| notes/setup.md | 前置条件（表格行，只许统计、不许改写） |
| notes/run.sh | 起台架的脚本 |

```bash
node check_doc.mjs --dir .
bash notes/run.sh
```

下一次要补的读数记在 notes/plan.md（规划）。
