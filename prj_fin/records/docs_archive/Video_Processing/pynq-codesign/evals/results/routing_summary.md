# routing evidence (single table)

router rows parsed: 12; lexical scorer bm25 with background 12 reference files; prediction files found: route_llm_i.jsonl, route_llm_k.jsonl, route_llm_l.jsonl

| set | n | weight | lexical strict | lexical acceptable | lexical neg refused | LLM router `i` strict/acceptable/neg | LLM router `k` strict/acceptable/neg | LLM router `l` strict/acceptable/neg |
|---|---|---|---|---|---|---|---|---|
| 1 | 14 | tuning set - router written against it | 0.83 | 0.83 | 2/2 | 0.92/0.92/2/2 | 0.92/0.92/2/2 | 0.92/0.92/2/2 |
| 2 | 16 | blind set - consumed by the change it graded | 1.00 | 1.00 | 2/2 | 1.00/1.00/2/2 | 1.00/1.00/2/2 | 1.00/1.00/2/2 |
| 3 | 20 | blind set - CERTIFICATION GRADE (untouched) | 0.50 | 0.56 | 1/2 | 0.94/0.94/2/2 | 0.89/0.94/2/2 | 0.89/0.94/2/2 |

Lexical columns are a LOWER BOUND (literal overlap only). LLM columns are the deployment path: an agent shown the entry document and the question and nothing else. Missing = that router did not cover this set.

## inter-rater agreement (same questions, independent agents)

| router A | router B | shared | exact choice match | Cohen kappa | distinct reasons | identical reasons |
|---|---|---|---|---|---|---|
| route_llm_i.jsonl | route_llm_k.jsonl | 50 | 0.98 | 0.98 | 100/100 | 0/50 |
| route_llm_i.jsonl | route_llm_l.jsonl | 50 | 0.98 | 0.98 | 100/100 | 0/50 |
| route_llm_k.jsonl | route_llm_l.jsonl | 50 | 1.00 | 1.00 | 100/100 | 0/50 |

`distinct reasons` 只证明两份文件不是互相粘贴出来的，不证明作者独立。

- certification-set (blind set 3) strict, LLM router, worst-of-N: 0.89 (worst of 3 routers)
- worst inter-rater exact agreement: 0.98 (kappa 0.98)
- distinct per-router reasons on the thinnest admissible pair: 100/100 (a byte-identical or all-same-reason pair is excluded, not scored)
- table bound: predictions must carry skill_sha256 of the current SKILL.md (3f986c9e8796). Graded: route_llm_i.jsonl, route_llm_k.jsonl, route_llm_l.jsonl. Ignored as history (different/absent hash): route_llm_a.jsonl(sha=none,table=3f986c9e), route_llm_b.jsonl(sha=none,table=3f986c9e), route_llm_current_e.jsonl(sha=5536111c,table=3f986c9e), route_llm_current_f.jsonl(sha=5536111c,table=3f986c9e), route_llm_g.jsonl(sha=00c2e966,table=3f986c9e), route_llm_h.jsonl(sha=00c2e966,table=3f986c9e), route_llm_post.jsonl(sha=none,table=3f986c9e)
- verdict: PASS

