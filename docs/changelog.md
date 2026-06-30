# Changelog

<!-- markdownlint-disable MD024 -->

All notable changes to S2DCartographer are documented here. For the complete history see the
[root CHANGELOG.md](https://github.com/AzureLocal/azurelocal-s2d-cartographer/blob/main/CHANGELOG.md)
in the repository.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.10.1] — 2026-06-30

### Fixed

- **ImportExcel is now an optional runtime dependency.** Removed `ImportExcel` from the manifest
  `RequiredModules` list so `Test-ModuleManifest` and `Import-Module` succeed in CI without
  ImportExcel pre-installed. `Export-S2DExcelReport` loads ImportExcel on demand; other report
  formats (HTML, Word, PDF, JSON) are completely unaffected.

---

## [1.10.0] — 2026-06-30

### Added

- **Graduated health-check scoring engine (#57, AB#267).** `Get-S2DHealthStatus` now adds
  `Weight`, `MaxPoints`, `AwardedPoints`, `ScoreBand`, and `ScorePercent` to every
  `S2DHealthCheck`. A `CollectedData['HealthScore']` rollup carries the weighted
  `OverallScore` (0–100), `ScoreStatus` (Excellent/Good/Fair/Needs Improvement),
  `TotalAwarded`, `TotalMax`, and the legacy `OverallHealth` string. All existing output
  fields are unchanged — fully backward-compatible.

- **Named calculation references via `config/health-checks.json` (#58, AB#268).** All 12
  check definitions (weights, thresholds, named bands) externalized to a JSON config file
  shipped with the module. Thresholds and weights are editable without code changes.
  Mirrors Ranger's `waf-rules.json` schema shape.

- **`Export-S2DHealthConfig` and `Import-S2DHealthConfig` (#59, AB#269).** Export writes
  the active config to JSON; Import validates and activates an override for the session.
  Use `-Validate` for a dry-run schema check; use `-Default` to reset to shipped defaults.
  Mirrors Ranger's `Export-RangerWafConfig` / `Import-RangerWafConfig` hot-swap pattern.

---

## [1.9.0] — 2026-06-30

### Added

- **Provisioning-aware 70% headroom presentation** — the 70% amber/warning treatment in the HTML KPI
  tile, capacity-waterfall planning-line row, and expansion-headroom table now fires **only when
  thin-provisioned volumes are present** (a full pool takes thin volumes offline). When all volumes are
  fixed/thick, the 70% row is rendered as advisory/neutral (blue label, "Advisory — fixed volumes commit
  footprint up front") because footprint is committed at creation time. The `Get-S2DExpansionHeadroom`
  function gains a `HasThinVolumes` boolean on its output to drive this. Reworded all 70% prose to:
  "70% is a recommended operational headroom guideline — mainly relevant for thin-provisioned volumes,
  where a full pool takes thin volumes offline. Not a Microsoft hard limit. The firm storage limits are
  footprints fitting the pool and the rebuild reserve staying intact."

- **"Size to enter (New-Volume / WAC)" column** in all expansion-headroom tables (HTML, Word/PDF).
  PowerShell `New-Volume -Size` and WAC parse size suffixes as binary (typing `2TB` means 2 TiB).
  Each headroom row now shows the exact value to type, rendered as `{value}TB` (e.g. `0.65TB`),
  computed as `NewUsableData.TiB` rounded **down** to 2 decimal places so the new volume always fits.
  Past-line rows show `—`. A footnote explains the binary-suffix convention. The `SizeToEnterTiB`
  property flows through to the JSON snapshot automatically. Identical wording and rounding to
  Surveyor 2.6.0 so the two tools match exactly.

### Fixed / Correction

- **N+1/N+2 maintenance reserve re-framed as compute-advisory** — the v1.8.0 implementation
  incorrectly treated N+1/N+2 as a **storage-pool capacity check**. Microsoft WAF documents it as a
  **COMPUTE resiliency target** (reserve CPU + RAM so a node can be drained for updates or lost
  without dropping VMs), listed separately from storage. `Get-S2DMaintenanceReserveAssessment` now
  returns `Status='Info'`, `Meets=$null`, and surfaces `LargestNodeCapacity` as informational
  context. Check 12 (`MaintenanceReserveN1`) always emits `Status='Pass'` at `Severity='Info'` and
  never contributes a storage Warning or Fail to the health rollup. HTML and Word report sections
  re-labelled as compute advisory. All 70% prose corrected to not imply N+1 is a firm storage limit.

---

## [1.8.0] — 2026-06-30

### Added

- **Maintenance reserve (N+1) assessment** — reports whether the scanned cluster currently has enough free
  capacity (beyond the rebuild reserve) to drain a node for updates, per Microsoft's Well-Architected
  guidance. Surfaced as a new `MaintenanceReserveN1` health check and a report indicator (Meets / Does not
  meet, with the required vs available headroom in TB and TiB). Configurable target via
  `-MaintenanceReserveTarget None|N+1|N+2` (default N+1). This is **assessment only** — it does not change
  any measured capacity number. On two-node two-way-mirror clusters it notes that each node already holds a
  full copy, so a drained node keeps data available.

---

## [1.7.1] — 2026-06-30

### Added

- **Expansion Headroom** report section (HTML, Word, PDF, JSON) — at 70% / 80% / 90% / 100% pool-fill
  targets, shows the remaining pool footprint and the **new usable data** you can still store
  (footprint ÷ resiliency copies), in both TB and TiB, with a Chart.js chart. The 70% row is styled as the
  recommended planning line. Math is identical to Surveyor's so the two tools reconcile by construction.

### Fixed

- Per-volume **capacity efficiency** is now derived from the measured `FootprintOnPool ÷ Size` ratio (ground
  truth) when available. A two-copy mirror correctly reports **50%** efficiency; the previous logic
  mislabeled it as **25%** ("nested two-way mirror") on two-node clusters. Nested two-way mirror, which
  writes four copies, correctly reports 25%.

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
