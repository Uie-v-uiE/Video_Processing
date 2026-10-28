# Documentation index

`docs/` holds the design, verification, optimisation, bring-up, interface and limit documents. The design report and the verification document are the reference for every number; supporting evidence lives in `hw/reports/` and `hw/measured/`.

## Reading order

1. `design-report.md` — what the system is, why it is split this way, the key algorithms and timing, results and boundaries.
2. `verification.md` — the bench matrix, special-purpose checks, board acceptance, and what is not covered.
3. `optimization.md` — how timing and resources were improved, which attempts were rejected, and where the physical limits are.
4. `reproduction.md` — build, simulate, compile the PS application, rebuild the Vivado/Vitis projects, program the board and write QSPI.
5. `limits.md` — the limits that still stand, plus unfixed items.
6. `issues/key-issues.md` — the defects that changed the design: symptom, root cause, check, fix and evidence.
7. `interface-table.md` — control bits, telemetry, serial commands, lane numbers, addresses and video constants.
8. `commands.md` — the serial command reference, with parameters, expected replies and rejected inputs.
9. `declarations.md` — device, toolchain, third-party components and where the in-house boundary sits.
10. `glossary.md` — one English term per object, with the Chinese original.

## Figures

`figures/` holds the diagrams used by the design report: system overview, packet-ingest chain, display chain, effect-chain latency and the timing/resource plots. The same-frame comparison image is rendered from a test frame, not photographed from the panel; the report cites it that way.

## Where the evidence lives

| Item | Location |
|---|---|
| Timing, resource, CDC and power reports | `hw/reports/` |
| Full-video bench and regression verdicts | `hw/reports/`, `sim/results/`, `sim/README.md` |
| Board boot, serial, telemetry and self-test logs | `hw/measured/` |
| Control bits, telemetry fields, serial commands | `interface-table.md`, `commands.md`, appendix A of `design-report.md` |
| Device, toolchain and third-party declarations | `declarations.md` |
| Defects and root causes | `issues/key-issues.md` |
| Measured-versus-reference comparison | `hw/compare/` |

## Writing rules

- Every number carries its measurement conditions and evidence. Anything not measured is written as `NOT_MEASURED`, never as "should be fine".
- No changelog of versions. Optimisation is written as before/after plus the cost.
- No local paths, dates or tool installation paths. Repository paths stay relative.
- Human-eye checks and machine checks are kept apart. A green bench is never described as a green board.

## Current boundaries

On-chip memory sets the maximum frame size, the RGMII transmit side has a hold-margin gap, telemetry latency covers the PL only, and the HDMI picture still needs a human to sign it off. Each item is explained in `limits.md`.
