# Changelog

<!-- markdownlint-disable MD024 -->

All notable changes to S2DCartographer are documented here. For the complete history see the
[root CHANGELOG.md](https://github.com/AzureLocal/azurelocal-s2d-cartographer/blob/main/CHANGELOG.md)
in the repository.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.7.0] — 2026-06-30

> **Wave 3 — Validation & report correctness.** Locks accuracy against regression and fixes the
> PDF/Word report rendering defects, plus collection robustness on empty or contended clusters.

### Added

- **Cross-tool reconciliation keystone.** A byte-valued golden-cluster fixture
  (`tests/maproom/Fixtures/golden-clusters.json`), identical to Surveyor's, drives a Pester suite
  that runs the Cartographer engine and asserts reconciliation within the ±2% gate. 24 Pester cases
  across 4 clusters. (AB#4633)
- **Concurrent collection guard** — a module-scoped flag set at the start of
  `Invoke-S2DCartographer` and released in a `finally`; a second concurrent collection throws a
  clear terminating error instead of corrupting shared state. (AB#279)
- **Empty-data safeguards** — `Get-S2DCapacityWaterfall`, `Get-S2DHealthStatus`, and
  `Get-S2DStoragePoolInfo` now handle null/empty disk, pool, and volume data gracefully (warn +
  zeroed result) rather than throwing on an empty cluster. (AB#279)

### Fixed

- PDF capacity-model **waterfall** bar graph now uses exact byte-derived TB values instead of a
  truncated `1.0995` approximation. (AB#263)
- PDF **pool allocation** reserve boundary line is positioned at `poolTotal − reserve` (start of the
  reserve zone) instead of the reserve value, and the **pool health** bar's x-axis max now includes
  every segment so healthy clusters no longer clip. (AB#264)
- Word **executive summary** table given explicit column widths (35/65), fixed layout, and cell
  padding so values like `22.44 TiB (24.65 TB)` are no longer cramped. (AB#265)
- Word document **overall layout** — 1-inch margins, page-width tables with fixed layout, section-
  header cell margins, and hand-tuned column widths for the wide disk/volume tables. (AB#266)

---

## [1.6.0] — 2026-06-29

> **Wave 2 — Legibility.** Capacity figures are now unambiguous in unit and space. No capacity math
> changed.

### Added

- The capacity waterfall and HTML report label every figure with both its unit (decimal **TB** and
  binary **TiB**) and its space — each stage is badged `FOOTPRINT`, `DATA (usable)`, or
  `INFORMATIONAL`. (AB#4645)
- 70% planning line — **70% of available-for-volumes**, compared against consumed volume
  **footprint** (matches Surveyor's definition exactly). Surfaced as `PlanningLine70Pct` /
  `IsAbove70PctLine` on `S2DCapacityWaterfall`, as a KPI tile (amber when crossed) and a dashed
  plan-line on the HTML report chart. (AB#4644)

---

## [1.5.0] — 2026-06-29

> **Wave 1 — Capacity accuracy.** The capacity waterfall is reconciled to the canonical model
> (`docs/capacity-model.md`) shared with Azure Local Surveyor.

### Changed

- Resiliency factor is now always derived from each volume's actual `NumberOfDataCopies` when
  present. When that value is unavailable, the unsafe default fallback changed from `3.0` to `2.0`
  (two-way mirror) and the waterfall stage is labeled
  `[ASSUMED — actual NumberOfDataCopies not available]` via the new `-ResiliencyIsAssumed` switch.
  A real pool value is always preferred over the assumption. (AB#4642)

### Confirmed

- Reserve calculation confirmed canonical — one capacity drive per server, up to 4 drives
  (raw-byte basis). No change required. (AB#4643)

---

## [1.4.2] — 2026-04-14

### Fixed

- `RebuildCapacity` health check fired false Critical when pool-member disk deduplication could not
  assign correct `NodeName` via `StorageNode` associations — all disks landed on one node making
  the check compare pool free against the full pool total instead of one node's capacity. Fix: fall
  back to `pool.TotalSize / nodeCount` when `NodeName` group count is less than `nodeCount`.

---

For versions 1.4.1 and earlier, see the
[root CHANGELOG.md](https://github.com/AzureLocal/azurelocal-s2d-cartographer/blob/main/CHANGELOG.md).
