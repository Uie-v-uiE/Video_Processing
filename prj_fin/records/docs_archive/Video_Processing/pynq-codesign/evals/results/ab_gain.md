# A/B gain measurement - 2026-10-11T08:17:20

One identical PYNQ task, two arms, one ruler.

| arm | lines | parses | api_lint red | codes | offline assertions |
|---|---|---|---|---|---|
| baseline (no skill) | 1587 | yes | 5 | E001, E016 | 0 |
| with skill | 160 | yes | 0 | none | 10 |

## findings

### baseline (no skill) (ab_baseline.py)
- L639 E001 'XlnAllocType' is not exported by pynq in v3.1
- L648 E016 allocate() has no 'count' keyword in v3.1; names this package verified: cache,
- L649 E016 allocate() has no 'count' keyword in v3.1; names this package verified: cache,
- L674 E001 'xlnk' is not exported by pynq in v3.1
- L714 E001 'xlnk' is not exported by pynq in v3.1
- offline: `run_offline: NOT_MEASURED checked=0 (script printed no OFFLINE-ASSERT lines; rc=2)`

### with skill (ab_with_skill.py)
- clean
- offline: `run_offline: checked=10 pass=10 fail=0 skip=0 rc=0 PASS`

- avoided by using the skill: **5** findings
- interpretation: the baseline arm produced 5 ruler findings across 3 distinct (rule, symbol) causes (E001:XlnAllocType, E001:xlnk, E016:allocate()) and the skill arm 0. Repeating the same wrong import inside one file counts once here; do not read 5 findings as 5 failure modes.
- CONFOUND, stated before anyone quotes this as a gain: the with-skill arm was authored by a session that ran `api_lint` as an acceptance gate and iterated until clean, and `api_lint` is the same ruler scoring it. So `with_skill_red=0` is partly an outcome of the workflow, not an independent measurement, and this table cannot separate the two. Two further unfairness terms: the ruler is a version-purity checker, so the baseline's multi-version try/except fallbacks count as hallucinated APIs by definition; and `assertions=0` for the baseline is a CONTRACT mismatch (run_offline counts only OFFLINE-ASSERT lines, which the baseline was never told to emit), not missing capability.
- limits: two arms, one prompt, one model family behind both. The arms were separate sessions that could not see each other, which removes copying but not shared priors. The baseline was written by a session that was told to work without this package, so it is a no-skill proxy, not a published model's benchmark score. To make this a real gain claim: score at least one arm with a ruler neither arm has seen (human review, board `dmesg`/`/sys` capture, or a held-out rule set) and run more prompts.
