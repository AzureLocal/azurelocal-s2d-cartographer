# Plan of Attack — Surveyor & S2D Cartographer

> **This is a shared cross-tool plan.** An identical copy lives in both
> [`azurelocal-surveyor`](https://github.com/AzureLocal/azurelocal-surveyor) and
> [`azurelocal-s2d-cartographer`](https://github.com/AzureLocal/azurelocal-s2d-cartographer).
> Keep the two copies in sync.

## North star

**The two tools must agree.** When S2D Cartographer *scans* a real cluster and Surveyor
*estimates* the same hardware, every shared capacity figure — raw, usable, available-for-volumes,
reserve, and the 70% line — must reconcile within a documented tolerance. **Accuracy is the
priority; every formula gets double-checked against the canonical model below before any new
functionality is built.**

Work is grouped into **waves**, ordered accuracy/correctness → legibility → validation →
enrichment → UX → new capabilities. Do not start a wave until the prior wave's exit criteria pass.

---

## The canonical capacity model (source of truth)

Both tools must implement this exact pipeline, in this order, with these definitions. Numbers in
parentheses are grounded in Microsoft Storage Spaces Direct documentation (see References).

```
 1. Raw per drive (TB, decimal)        ← nameplate, e.g. 3.84 TB
 2. Usable per drive  = raw × Eff       ← Eff = per-drive efficiency factor (SEE OPEN QUESTION #1)
 3. Pool raw          = usable/drive × drives/node × nodes
 4. Reserve           = one capacity drive per server, up to 4 drives total   (NOT a flat %)
 5. Pool after reserve= pool raw − reserve
 6. Footprint→size    ÷ copies          ← copies = actual NumberOfDataCopies per volume
 7. Available for vol. = usable capacity available for new volume *size*
 8. 70% alert line    = 70% of available-for-volumes (footprint basis the alert fires on)
```

### Resiliency facts (locked, from MS docs)

| Resiliency | Copies | Storage efficiency | Min nodes | Tolerates |
|---|---|---|---|---|
| Two-way mirror | 2 | 50.0% | 2 | 1 failure |
| Three-way mirror | 3 | 33.3% | 3 | 2 failures |
| Nested two-way mirror | 4 | 25% | 2 | 2 failures |
| Nested mirror-accelerated parity | — | ~35–40% | 2 | 2 failures |
| Dual parity | — | 50–80% | 4 | 2 failures |

- **`footprint = volume size × copies`**; `capacity efficiency = usable ÷ footprint`.
- **3-way mirror requires ≥3 nodes.** On a 2-node cluster only **two-way** (or **nested**) is valid.
- For **2-node production**, Microsoft recommends **nested resiliency**, not plain two-way. Both
  tools currently ignore nested — flag wherever a 2-node cluster is modeled.
- **Reserve = one capacity drive per server (up to 4 drives)** — per-server, drive-based, not a flat
  0.75 TB or flat %. Reserve must be computed on the **same basis** (efficiency-adjusted) in both tools.
- With **asymmetric drives**, only capacity present in *every* server is guaranteed usable (stranded
  capacity). Treat the smallest-common-denominator per server as the safe usable figure.

### Open questions to resolve in Wave 0 (these ARE the bugs)

1. **What is the ~0.92 per-drive efficiency factor?** Surveyor shows `3.84 × 0.92 = 3.5328 TB/drive`.
   Is `0.92` a real ReFS/metadata/format overhead, **or** is it silently standing in for the
   TB→TiB decimal-to-binary conversion (`3.84 TB = 3.49 TiB`, ≈9.95%)? These are *different things*
   and conflating them is the crux of the 22.44 vs 20.45 TB divergence. Pin it down, document it,
   apply it identically in both tools. *(AB#4641)*
2. **Is Cartographer's `÷3` a calculation or a label?** Confirm whether usable capacity is actually
   divided by 3 regardless of volume resiliency, or whether `3-way mirror` is only display text.
   Drive the answer from `NumberOfDataCopies` on each real volume. *(AB#4642)*
3. **TB vs TiB everywhere.** Decide which stages are decimal (TB) and which are binary (TiB), show
   both, and never mix silently. *(AB#4640 / AB#4645)*
4. **Footprint vs usable.** Every figure must be labeled which space it is in. *(AB#4640 / AB#4645)*

### Definition of "reconciled" (exit gate for Wave 1)

Given the same cluster hardware fed to both tools, **Available-for-Volumes agrees within ±2%** (or a
tolerance you ratify), and every intermediate stage (raw, usable/drive, reserve, footprint, usable)
matches to the same precision. A golden-cluster fixture (Wave 3) enforces this in CI.

---

## Waves

| Wave | Theme | ADO items | Exit criteria |
|---|---|---|---|
| **0** | Canonical model + formula audit | AB#4633 (Epic) | This document ratified; every formula traced to a source; open questions answered |
| **1** | Accuracy fixes (reconcile the math) | AB#4642, AB#4643, AB#4641, AB#4635, AB#4636, AB#4638, AB#4637 | Same cluster → numbers reconcile within tolerance |
| **2** | Legibility (units, labels, thresholds) | AB#4640, AB#4645, AB#4639, AB#4644 | Every figure labeled TB/TiB + footprint/usable; 70% line drawn in both |
| **3** | Validation + report correctness | AB#154, AB#263, AB#264, AB#265, AB#266, AB#279 | Golden-cluster reconciliation test in CI; reports render correct numbers |
| **4** | Enrichment that feeds accuracy | AB#262, AB#414, AB#267, AB#268, AB#269 | Better drive/inventory data flows into the model; health-check scoring configurable |
| **5** | Reporting UX & visualization | AB#270, AB#271, AB#272, AB#273, AB#274, AB#275, AB#276, AB#277, AB#280, AB#278 | Diagrams, PDF/Word layout, exports, progress, search, cost |
| **6** | New capabilities + docs | AB#153, AB#155, AB#4646, AB#4647, AB#4648 | Reverse planner; settings UX; clear docs; VitePress migration |

---

### Wave 0 — Canonical model & formula audit *(do first, blocks everything)*
**Epic AB#4633.** Ratify the model above. Walk every capacity formula in both codebases and trace it
to a documented source or this spec. Answer the four open questions. Produce a one-page
`capacity-model` reference (this section can graduate into it) that both engineering tracks code against.
- **Exit:** no formula in either tool is unexplained; 0.92 and ÷3 are definitively classified.

### Wave 1 — Accuracy fixes
Make each tool match the canonical model.
- **Cartographer:** AB#4642 (use `NumberOfDataCopies`, not hardcoded ÷3) · AB#4643 (reserve on
  efficiency-adjusted, per-server-drive basis) · AB#4641 (insert the explicit efficiency-haircut stage).
- **Surveyor:** AB#4635 (fix the “× nodes” mislabel) · AB#4636 (only offer valid resiliency for the
  node count; surface nested for 2-node) · AB#4638 (use measured infra-volume footprint when scan data
  exists) · AB#4637 (two-way/three-way toggle that recomputes suggested TiB from the pool target).
- **Exit:** the reconciliation gate passes on at least one real golden cluster.

### Wave 2 — Legibility
The numbers are now correct; make them unambiguous.
- AB#4640 / AB#4645 — show TB **and** TiB; label every figure footprint vs usable; consistent
  decimal/binary usage.
- AB#4639 / AB#4644 — draw the 70% line against available-for-volumes in both tools, identically.
- **Exit:** a reader can tell, for every number, which unit and which space it is in.

### Wave 3 — Validation & report correctness
Lock accuracy in so it can't regress.
- AB#154 — expand Surveyor test coverage (Custom Workloads JSON import lifecycle).
- **New (create as a child of AB#4633):** a *golden-cluster cross-tool reconciliation test* — a fixed
  hardware fixture asserted equal across both tools in CI. Add regression tests for the Wave 1 bugs.
- AB#263 / AB#264 / AB#265 / AB#266 — fix the PDF/Word render bugs so correct numbers display correctly.
- AB#279 — concurrent-collection guard + empty-data safeguards.
- **Exit:** CI fails if the two tools diverge; reports are visually correct.

### Wave 4 — Enrichment that feeds accuracy
- AB#262 — OEM disk enrichment (iDRAC/iLO/XClarity/DataON) → better drive truth into the model.
- AB#414 — RVTools import → real inventory into Surveyor suggestions.
- AB#267 / AB#268 / AB#269 — health-check graduated scoring, named calc references, config hot-swap.

### Wave 5 — Reporting UX & visualization
AB#270, AB#271 (diagrams + capture), AB#272, AB#273, AB#274 (PDF layout/coloring), AB#275 (evidence
export), AB#276 (progress overlay), AB#277 (HTML search), AB#280 (Spectre TUI), AB#278 (cost savings).

### Wave 6 — New capabilities & docs
AB#153 (reverse hardware planner), AB#155 (keep/reset settings prompt), AB#4646 (rewrite getting-started
docs), AB#4647 / AB#4648 (migrate both doc sites MkDocs → VitePress, Epic AB#4634).

---

## References (Microsoft Learn, verified 2026-06-29)

- Fault tolerance & storage efficiency — <https://learn.microsoft.com/windows-server/storage/storage-spaces/fault-tolerance>
- Plan volumes (size vs footprint, reserve capacity, resiliency by node count) — <https://learn.microsoft.com/windows-server/storage/storage-spaces/plan-volumes>
- Nested resiliency (2-node production) — <https://learn.microsoft.com/windows-server/storage/storage-spaces/nested-resiliency>
- Drive symmetry / stranded capacity — <https://learn.microsoft.com/windows-server/storage/storage-spaces/drive-symmetry-considerations>
- Reserve capacity recommendation — <https://learn.microsoft.com/azure/azure-local/concepts/plan-volumes#reserve-capacity>
