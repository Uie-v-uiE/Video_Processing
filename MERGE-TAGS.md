# Tag merge note

This branch is the all-files branch. The 10 historical tags were merged here and then removed from the remote.

- Merge rule: only paths absent from this branch were added; existing files were kept.
- Duplicate paths across tags: the newest tag wins.
- Skipped regenerable Vivado/build artifacts: 7037 paths (pkg_archive, vivado_system, .gen, .runs, .Xil, sim_work, dcp/rpx/bit/xsa/elf/bin/log etc.).
- Merged source tags: v4-zero-loss, v3-ghosting-attempts, v1-ps-ethernet, v2-pl-ethernet, v3-seamless-zoom, archive-main-2026-09-24, wip-2026-09-28, archive-main-2026-09-29-pre-rtl-opt, review-20261005, records-20261007
- Merge date: 2026-11-02
