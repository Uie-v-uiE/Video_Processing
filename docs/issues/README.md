# Defect ledger

This directory records the defects that actually changed a decision. Numbering follows the original ledger so entries can be cross-referenced with older notes, bench names and skill cards; the numbers are not release versions.

## How to read it

- `key-issues.md` — 20 entries in the form symptom → root cause → check → fix/status → evidence. Written for whoever picks this up next.
- Only those 20 entries are in this repository. The full process ledger, with early-round detail, rejected options and per-run readings, is not published.
- Boundaries that are still open live in [`../limits.md`](../limits.md); do not look for "current conclusions" here.

## Status words

| Word | Meaning |
|---|---|
| fixed | code changed, with a bench or board reading to show it |
| partly | RTL or bench changed, but the full-chain or board re-check is incomplete |
| open | confirmed, code untouched |
| shelved | tried or evaluated; the cost outweighs the benefit; not adopted |
| false alarm | did not survive line-by-line checking; kept so it is not investigated twice |
| NOT_MEASURED | input unreadable, so no verdict |

## Division of labour

Every entry carries the issue number or the bench name, so it leads straight back to code, bench and board log instead of retelling the same story.

## Evidence

Each entry names one primary piece of evidence. Bench verdicts are in `sim/results/` or `hw/reports/`, board readings in `hw/measured/`, timing and resources in `hw/reports/`. The raw process ledger stays out of the repository; the 20 selected entries are kept here.
