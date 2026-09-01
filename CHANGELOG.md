# Changelog

<!-- markdownlint-disable MD024 -->

All notable changes to S2DCartographer will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.9.0](https://github.com/AzureLocal/azurelocal-s2d-cartographer/compare/v1.8.0...v1.9.0) (2026-06-30)


### Features

* **health:** graduated scoring + named-calc config + hot-swap (Cartographer 1.10.0) ([194f7fa](https://github.com/AzureLocal/azurelocal-s2d-cartographer/commit/194f7fa94fc4a08abaf2080ab78fd69bcf8f6779))
* **report:** provisioning-aware 70% + size-to-enter column; reframe N+1/N+2 as compute advisory (Cartographer 1.9.0) ([7c0b8ea](https://github.com/AzureLocal/azurelocal-s2d-cartographer/commit/7c0b8ea9ab24dffa70db6cd32f41afeb94abce11))


### Bug Fixes

* **deps:** make ImportExcel an optional runtime dependency (Cartographer 1.10.1) ([9ab71d2](https://github.com/AzureLocal/azurelocal-s2d-cartographer/commit/9ab71d2c11e7931c797ddc7293774a443d419143))
* **report:** clarify pool provisioning, scope 70% line to thin volumes, drop N+1 compute box (Cartographer 1.9.1) ([8e96692](https://github.com/AzureLocal/azurelocal-s2d-cartographer/commit/8e9669263be3f0d979d9c6f0217b824864863158))
* **test:** use cross-platform temp path in [#59](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/59) config hot-swap tests ([702d5bd](https://github.com/AzureLocal/azurelocal-s2d-cartographer/commit/702d5bdda47053b181281303e044aee5fda785d8))

## [Unreleased]

## [1.10.1] — 2026-06-30

### Fixed

- **ImportExcel is now an optional runtime dependency.** Removed `ImportExcel` from the manifest
  `RequiredModules` list so `Test-ModuleManifest` and `Import-Module` succeed in CI environments
  that install only Pester and PSScriptAnalyzer. `Export-S2DExcelReport` now loads ImportExcel
  on demand: if the module is available it is imported; if not, it attempts `Install-Module
  ImportExcel -Scope CurrentUser`; if that fails, a clear actionable error is thrown naming the
  install command. All other report formats (HTML, Word, PDF, JSON) are completely unaffected.

## [1.10.0] — 2026-06-30

### Added

- **Graduated health-check scoring engine (#57, AB#267).** `Get-S2DHealthStatus` now emits five
  new fields on every `S2DHealthCheck` object alongside the existing `CheckName / Severity /
  Status / Details / Remediation` fields: `Weight` (relative importance 1–3), `MaxPoints`,
  `AwardedPoints` (Pass = full, Warn = partial, Fail = 0), `ScoreBand` (named band from the
  threshold definition), and `ScorePercent` (0–100 for the individual check). A new
  `CollectedData['HealthScore']` entry on the session carries the weighted roll-up:
  `OverallScore` (0–100 integer), `ScoreStatus` (Excellent ≥ 80 / Good ≥ 60 / Fair ≥ 40 /
  Needs Improvement < 40), `TotalAwarded`, `TotalMax`, and the legacy `OverallHealth` string.
  All existing consumers of `OverallHealth`, `HealthChecks`, `CheckName`, `Severity`, `Status`,
  `Details`, and `Remediation` are fully backward-compatible — no output fields were removed.
  Mirrors the Ranger `Invoke-RangerWafRuleEvaluation` weighted/graduated pattern.

- **Named calculation references via `config/health-checks.json` (#58, AB#268).** All 12 check
  definitions (weights, thresholds, named bands, and descriptions) are now externalized into
  `config/health-checks.json` shipped inside the module. The scoring engine (`Get-S2DHealthConfig`,
  `Get-S2DCheckDefinition`, `Invoke-S2DHealthCheckScoring`, `Invoke-S2DHealthScoreRollup`) reads
  definitions from this file and caches them on first use. Thresholds and weights can be edited in
  the JSON without code changes; the format mirrors Ranger's `waf-rules.json` schema shape.

- **Config hot-swap: `Export-S2DHealthConfig` and `Import-S2DHealthConfig` (#59, AB#269).**
  `Export-S2DHealthConfig [-OutputPath <path>]` writes the active config (or the shipped default)
  to a JSON file, returning a `FileInfo` object. `Import-S2DHealthConfig -Path <path>` validates
  the schema (checks have `id`, `weight`, `title`, and at least one `threshold`) then activates
  the config in-memory for the session — no module reinstall required. Use `-Validate` for a
  dry-run schema check without activating. Use `-Default` to clear any active override and revert
  to the shipped defaults. Both cmdlets are wired into `S2DCartographer.psd1` `FunctionsToExport`
  and `S2DCartographer.psm1` `Export-ModuleMember`. Pattern mirrors Ranger's
  `Export-RangerWafConfig` / `Import-RangerWafConfig` hot-swap design.

## [1.9.1] — 2026-06-30

### Changed

- **Pool "Overcommit" label no longer cries wolf on healthy pools.** The HTML and Word report pool
  summaries printed `Overcommit: 0.24x` for every pool, but "overcommit" only means something when
  provisioned capacity exceeds the pool total (ratio > 1.0x — the thin-provisioning case where writes
  can fail). A lightly-provisioned, healthy pool now reads `Provisioned: 24.2% of pool (within
  capacity)`; the red `Overcommit: N.NNx` label appears only when the ratio is genuinely > 1.0x.

### Removed

- **70% line KPI tile removed from the Executive Summary for fixed-provisioned clusters.** The 70% line
  is a thin-provisioning headroom guideline, not a current-health metric and not a Microsoft hard limit.
  It now appears in the HTML Executive Summary health band **only when thin-provisioned volumes are
  present** (where a full pool takes thin volumes offline). For fixed/thick clusters the figure still
  lives in the Capacity Model waterfall and the expansion-headroom table below — it just no longer
  competes with health signals at the top of the report.
- **"Compute Maintenance Reserve Context (N+1/N+2)" advisory box removed from the HTML and Word reports.**
  N+1/N+2 is a COMPUTE resiliency concept (reserve a node's worth of CPU + RAM so a node can be drained
  for maintenance), not a storage figure — so it added no value to a storage-capacity audit, and half
  the box was spent explaining why it was *not* a storage reserve. The `MaintenanceReserveN1` health
  check (Info severity) still carries the advisory in Health Checks, and the
  `MaintenanceReserveAssessment` object remains on the cluster data for Surveyor's planning deductions.

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
  incorrectly treated the N+1/N+2 guidance as a **storage-pool capacity check** (producing a
  Meets / Does-not-meet storage verdict). This was a framing error. Microsoft WAF documents N+1/N+2
  as a **COMPUTE resiliency target** (reserve CPU + RAM so a node can be drained for updates or
  lost without dropping VMs) and lists it separately from storage. Cartographer audits storage and
  has no VM compute-allocation data; it cannot perform a real compute drain assessment.
  Changes in this release:
  - `Get-S2DMaintenanceReserveAssessment`: `Status` is always `'Info'`; `Meets` is always `$null`;
    the output now surfaces `LargestNodeCapacity` and `ContextCapacity` as informational reference
    values. `RequiredCapacity` and `AvailableHeadroom` are retained as `$null` for JSON schema
    continuity.
  - `Get-S2DHealthStatus` Check 12 (`MaintenanceReserveN1`): always `Status='Pass'`,
    `Severity='Info'` — never contributes a storage Warning or Fail to the health rollup.
    Storage reserve adequacy is governed by Check 1 (ReserveAdequacy) only.
  - HTML and Word reports: MRA section re-labelled "Compute Maintenance Reserve Context — Advisory";
    removed storage-fail styling (amber/red); shows largest-node raw capacity as context.
  - All 70% prose corrected to not imply N+1 is a firm storage limit.

## [1.8.0] — 2026-06-30

### Added

- **Maintenance reserve (N+1) assessment** — reports whether the scanned cluster currently has enough free
  capacity (beyond the rebuild reserve) to drain a node for updates, per Microsoft's Well-Architected
  guidance. Surfaced as a new `MaintenanceReserveN1` health check and a report indicator (Meets / Does not
  meet, with the required vs available headroom in TB and TiB). Configurable target via
  `-MaintenanceReserveTarget None|N+1|N+2` (default N+1). This is **assessment only** — it does not change
  any measured capacity number. On two-node two-way-mirror clusters it notes that each node already holds a
  full copy, so a drained node keeps data available.

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

## [1.5.0] — 2026-06-29

> **Wave 1 — Capacity accuracy.** The capacity waterfall is reconciled to the canonical model
> (`docs/capacity-model.md`) shared with Azure Local Surveyor.

### Changed

- Resiliency factor is now always derived from each volume's actual `NumberOfDataCopies` when present.
  When that value is unavailable, the unsafe default fallback changed from `3.0` to `2.0` (two-way
  mirror) and the waterfall stage is labeled `[ASSUMED — actual NumberOfDataCopies not available]`
  via the new `-ResiliencyIsAssumed` switch. A real pool value is always preferred over the
  assumption. (AB#4642)

### Confirmed

- Reserve calculation confirmed canonical — one capacity drive per server, up to 4 drives (raw-byte
  basis). No change required. (AB#4643)

## [1.4.2] — 2026-04-14

### Fixed

- `RebuildCapacity` health check fired false Critical when pool-member disk deduplication could not assign correct `NodeName` via `StorageNode` associations — all disks landed on one node making the check compare pool free against the full pool total instead of one node's capacity. Fix: fall back to `pool.TotalSize / nodeCount` when `NodeName` group count is less than `nodeCount`.

## [1.4.1] — 2026-04-14

### Fixed

- Pool-member disk duplication on multi-node clusters — `Get-PhysicalDisk` on any S2D cluster node returns all pool-member disks (globally visible pool). Querying each node individually produced `NodeCount×` copies of every pool-member disk, inflating Stage 1 raw capacity by 4× and making Stage 3 pool overhead appear as ~75%. Fixed by deduplicating pool-member disks by `UniqueId` after per-node collection. `StorageNode` associations used to assign correct `NodeName`.
- Top-level `NodeCount` added to JSON snapshot for direct consumption by `Invoke-S2DCapacityWhatIf`.

## [1.4.0] — 2026-04-14

### Fixed

- **Capacity Model is now purely theoretical** — reduced from 8 to 7 stages (redundant Stage 8 removed). All stage `Status` values are always `OK`; reserve adequacy is reported via `ReserveStatus` on the waterfall object, not on pipeline stages. Stage names updated to match Microsoft S2D documentation: Stage 4 is **Reserve** (not "Rebuild Reserve"), Stage 7 is **Usable Capacity**. Stage 4 description corrected to "one drive per server, up to 4 servers". Closes [#52](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/52), [#47](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/47).
- **HTML Capacity Model table** — waterfall reductions moved to a dedicated **Deducted** column in grey. Previously the delta was concatenated onto the stage name with no separator. Closes [#47](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/47).
- **Word report formatting** — complete rewrite with branded cover, KPI tiles, blue section headers, alternating-row tables, and severity-colored remediation cards. Waterfall table updated to 7-stage design with Deducted column. Closes [#48](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/48).
- **Excel repair error on open** — complete rewrite removing the Raw Data tab (corrupt oversized-JSON cell). Fixed `Close-ExcelPackage -NoSave` stripping formatting. Adds table styles, row-level health coloring, and KPI coloring. Closes [#49](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/49).
- **ThinOvercommit/ThinReserveRisk false positives** — `Get-S2DInfraVolumeFlag` now recognises `UserStorage_N`, `HCI_UserStorage_N`, and `SBEAgent` as Azure Local system volumes. These are often thin-provisioned but are not user workload volumes. Closes [#46](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/46).
- **Navigation** — "Related Projects" nav entry replaced with a **Companion Tools** docs page covering Azure Local Surveyor and the Platform repository. Closes [#50](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/50).
- `Invoke-S2DCapacityWhatIf` delta stage loop no longer hardcodes 8 iterations; adapts to `Stages.Count`.

### Added

- `docs/companion-tools.md` — Surveyor vs Cartographer comparison table and lifecycle guidance.
- `tests/maproom/Fixtures/healthy-pool-snapshot.json` — MAPROOM fixture for a correctly configured 4-node cluster: Healthy pool, Adequate reserve, all 12 health checks Pass.
- `tests/maproom/unit/v1.4.0-fixes.Tests.ps1` — regression tests covering all v1.4.0 fixes.

### Changed

- `Build-PreviewReports.ps1` accepts `-SnapshotPath` to target any cluster snapshot.
- `samples/cluster-snapshot.json` updated to 7-stage waterfall with correct names and byte values.
- All unit tests updated: `Should -Be 8` → `Should -Be 7`, `Stages[7]` → `Stages[6]`.

### Testing

- 217 Pester tests passing, 0 failing.

## [1.3.0] — 2026-04-13

### Added

- **What-if capacity modeling** (`Invoke-S2DCapacityWhatIf`) — model the capacity impact of adding nodes, adding disks per node, replacing disks, or changing resiliency without touching the live cluster. Accepts a JSON snapshot (SchemaVersion 1.0), a piped `S2DClusterData` object, or a live cluster name. Returns an `S2DWhatIfResult` object containing both the baseline and projected `S2DCapacityWaterfall` plus a per-stage delta table with TiB and TB values. Optionally generates HTML and JSON reports. Closes [#27](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/27).
- **What-if HTML report** (`Export-S2DWhatIfHtmlReport`) — self-contained HTML file with side-by-side Chart.js horizontal bar charts (baseline left, projected right), a KPI summary row (baseline usable, projected usable, delta, reserve statuses, efficiency percentages), scenario badge, and a color-coded stage-by-stage delta table.
- **What-if JSON output** (`Export-S2DWhatIfJsonReport`) — structured JSON file (SchemaVersion 1.0, Type S2DWhatIfResult) with flat waterfall stage arrays and all delta values for downstream consumption.
- **`Invoke-S2DWaterfallCalculation`** private pure function — all 8-stage waterfall math extracted from `Get-S2DCapacityWaterfall` into a session-independent function callable with explicit numeric inputs. No CIM queries, no module state. `Get-S2DCapacityWaterfall` is now a thin wrapper that extracts session inputs and calls this function.
- **Thin provisioning risk check update** — `Get-S2DHealthStatus` check 6 (ThinOvercommit) now evaluates maximum potential pool footprint (`Size × NumberOfDataCopies` for each thin-provisioned volume) against pool total capacity at two thresholds: Warn at 80%, Critical at 100%. Previously only fired when the current provisioned overcommit ratio exceeded 1.0 — too late to catch risk before it materialises. Closes [#44](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/44).
- **Check 11: ThinReserveRisk** — new health check evaluates whether maximum thin volume growth (potential footprint minus current footprint) would consume the recommended rebuild reserve space. Warns when growth headroom could exhaust reserve; Critical when pool free space after maximum growth is negative. Closes [#44](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/44).
- `S2DVolume.ThinGrowthHeadroom` — new `S2DCapacity` property populated by `Get-S2DVolumeMap` for thin-provisioned volumes: `Size - AllocatedSize` (remaining write headroom before pool footprint equals provisioned size).
- `S2DVolume.MaxPotentialFootprint` — new `S2DCapacity` property: `Size × NumberOfDataCopies` (maximum pool space consumed if the volume is written completely full under current resiliency). `$null` for fixed-provisioned volumes.
- **Thin Provision Risk KPI** in HTML executive summary — color-coded card showing `max potential footprint / pool total` percentage; amber at ≥80%, red at ≥100%.
- **Growth Headroom and Max Potential Footprint columns** in the Volume Map table in HTML, Word, Excel, and CSV reports. Fixed-provisioned volumes show "—" in these columns.
- `docs/what-if.md` — new documentation page covering all scenario parameters, output object shape, worked examples for every scenario type, composite scenarios, pipeline input, and modeling assumptions.

### Changed

- `Get-S2DCapacityWaterfall` is now a thin wrapper around `Invoke-S2DWaterfallCalculation`. Existing callers are unaffected — public API is unchanged.
- `Get-S2DHealthStatus` now returns 11 health check objects (previously 10).

## [1.2.1] — 2026-04-13

### Fixed

- `Get-S2DCapacityWaterfall` Stage 1 now filters to **pool-member capacity-tier disks only** (`IsPoolMember -ne $false`). Boot drives (Dell BOSS, HPE M.2 SmartArray) and SAN-presented LUNs with `Role = 'Capacity'` no longer inflate Raw Physical, which previously caused a false cliff-drop from Stage 1 to Stage 3 on clusters with non-pool disks. Closes [#43](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/43).
- Stages 7 and 8 are now **purely theoretical**. Previously Stage 7 subtracted live provisioned-volume pool footprint from available pool space (yielding "remaining free pool"), and Stage 8 summed live provisioned-volume sizes — two unrelated metrics that broke the monotonic pipeline contract and caused Stage 8 to exceed Stage 7 on clusters with thin-provisioned volumes. Stage 7 now applies the pool's configured resiliency factor (Mirror `NumberOfDataCopies`; default: 3-way mirror) to Stage 6 (Available). Stage 8 equals Stage 7 — pipeline terminus. Closes [#43](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/43).
- `BlendedEfficiencyPercent` on the `S2DCapacityWaterfall` object now reflects theoretical resiliency efficiency (e.g., 33.3% for 3-way mirror) rather than a live average across provisioned volumes. Closes [#43](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/43).
- Stage 2 description clarified: explicitly states no bytes are deducted and that this stage is a vendor-label informational note only (vendor decimal TB vs Windows binary TiB). Closes [#43](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/43).

## [1.2.0] — 2026-04-13

### Added

- **JSON snapshot export** — every run writes a structured `S2DClusterData` snapshot as `<base>.json` alongside the existing reports. Stable schema at SchemaVersion 1.0, documented in `docs/schema/cluster-snapshot.md` with a canonical sample at `samples/cluster-snapshot.json`. Enables downstream tools, diff workflows, what-if calculations, external dashboards, custom scripts. Closes [#40](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/40).
- **CSV export** — opt-in flat per-collector tables (`-physical-disks.csv`, `-volumes.csv`, `-health-checks.csv`, `-waterfall.csv`) for spreadsheet / Power BI consumers. Request with `-Format Csv`. Closes [#40](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/40).
- `IsPoolMember` boolean on every disk returned by `Get-S2DPhysicalDiskInventory`. Lets downstream tooling distinguish S2D pool members from boot drives and SAN-presented LUNs. Closes [#41](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/41).
- `-IncludeNonPoolDisks` switch on `Invoke-S2DCartographer` and `New-S2DReport` for when you explicitly want every disk in the rendered report, not just pool members. Closes [#41](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/41).

### Changed

- Physical Disk Inventory tables in HTML, Word, PDF, and Excel reports now show **pool-member disks only** by default. Boot drives (Dell BOSS, HPE M.2 SmartArray) and SAN-presented LUNs are filtered because they are not S2D scope and their presence in the table misleads readers. JSON and CSV exports always include every disk with an `IsPoolMember` flag. Closes [#41](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/41).
- `DiskSymmetry`, `DiskHealth`, `NVMeWear`, `FirmwareConsistency`, and `RebuildCapacity` health checks now operate only on pool-member disks. Previously a single asymmetric boot drive could trip the symmetry check; now only actual S2D pool disk counts are compared, eliminating false positives on heterogeneous hardware. Closes [#41](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/41).
- `Invoke-S2DCartographer -Format All` now includes `Json` in the expansion (HTML + Word + PDF + Excel + JSON). CSV remains opt-in because it produces multiple files per run.

### Documentation

- Cross-link to Azure Local Surveyor added in README, `docs/index.md`, and the MkDocs "Related Projects" nav entry. Surveyor plans; Cartographer verifies. Closes [#35](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/35).
- `docs/schema/cluster-snapshot.md` — new page documenting every field of the JSON export, including `S2DCapacity` shape, PowerShell / jq / Python consumption examples, and schema versioning policy.
- `docs/collectors/physical-disks.md` — new Pool Membership Filter section; new `IsPoolMember` property row in the output field table.
- `docs/reports.md` — new JSON Snapshot and CSV Tables sections; Formats table updated; `-IncludeNonPoolDisks` documented in the parameter table; per-run folder listing updated to include the `.json` file.
- `docs/getting-started.md` — per-run folder listing updated to include the JSON file.
- `samples/cluster-snapshot.json` — canonical JSON sample committed, generated from the MAPROOM IIC fixture. Closes [#42](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/42).

## [1.1.1] — 2026-04-13

### Fixed

- `Invoke-S2DCartographer` parameter splat to `Connect-S2DCluster` no longer forces the `ByName` parameter set when `-KeyVaultName` / `-SecretName` are passed. The Key Vault credential path now works end-to-end through the orchestrator. Previous behaviour threw `Credentials are required to connect to cluster` because `-Authentication` was always being splatted in (it lives in `ByName` only), forcing PowerShell parameter-set resolution to pick `ByName` and then demanding a `-Credential` that was never supplied. Closes [#39](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/39).
- `Invoke-S2DCartographer` with `-Credential` + explicit `-Authentication Negotiate` no longer throws the same error. Parameter-set discipline is now strict across all four connection paths (`Local`, `ByCimSession`, `ByKeyVault`, `ByName`).

### Added

- `Connect-S2DCluster` and `Invoke-S2DCartographer` now accept a `-Username` parameter for the Key Vault credential path. Lets callers bypass the ContentType tag convention when the KV secret does not have that tag populated — common in infra automation pipelines that write the secret value without also writing the username to ContentType.

## [1.1.0] — 2026-04-13

### Added

- **Per-run output folder structure** — each `Invoke-S2DCartographer` run writes to `<OutputDirectory>\<ClusterName>\<yyyyMMdd-HHmm>\`. Multiple clusters and repeated runs never overwrite each other. Diagrams go into a `diagrams\` subfolder within the run folder. Closes [#37](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/37).
- **Session log file** — a `.log` file is written to the run folder capturing each collection step with duration, warnings, final output paths, overall health, and total run time. A fallback log is written to `OutputDirectory` root if the run fails before the cluster name is known. Closes [#37](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/37).

### Changed

- `Invoke-S2DCartographer` default `-Format` changed from `Html` to `All` — HTML, Word, PDF, and Excel are all generated unless a specific format is requested. Closes [#36](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/36).
- `ImportExcel` added to `RequiredModules` in the module manifest — installs automatically from PSGallery. No manual `Install-Module ImportExcel` step required. Closes [#36](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/36).
- Pool Allocation Breakdown bar height increased from 90 px to 180 px for improved readability. Closes [#38](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/38).

### Documentation

- `connecting.md` — new **Remoting Prerequisites** section covering WinRM setup, TrustedHosts configuration with FQDN guidance, firewall ports table, and the node fan-out flow diagram showing how per-node CIM sessions are established and how auth is inherited. Closes [#34](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/34).
- `getting-started.md` — updated Quick Start to show per-run folder structure, ImportExcel auto-install note, updated examples to reflect `All` as the default format.
- `reports.md` — updated format examples, ImportExcel dependency note, output folder structure documentation.

## [1.0.8] — 2026-04-13

### Fixed

- `Get-S2DHealthStatus` — replaced `[System.Collections.Generic.List[S2DHealthCheck]]` with `[System.Collections.ArrayList]`. PowerShell classes defined via dot-sourcing can fail to resolve as generic type parameters at runtime, causing `.Add()` to throw "Cannot find an overload for 'Add' and the argument count: '1'" when running against a live cluster.

## [1.0.7] — 2026-04-13

### Added

- **Storage Pool Health bar** — WAC-style horizontal bar showing volumes used (blue), free space (green), rebuild reserve intact (amber), reserve consumed (red hazard stripe), and overcommit beyond pool total (dark red). Reserve boundary and pool total marked with labeled vertical lines.
- **Pool Allocation Breakdown bar** — stacked bar showing per-volume pool footprint with reserve and overcommit segments.
- **Capacity Model stage descriptions** — table beneath the capacity chart explaining what each of the 8 stages represents, with delta cost and remaining capacity per step. Descriptions sourced from waterfall stage objects so live cluster data populates them automatically.
- **Critical Reserve Status KPI** — Reserve Status card in the executive summary now renders with red background and text when status is `Critical`.

### Changed

- HTML report section "Capacity Waterfall" renamed to **"Capacity Model"** with subtitle clarifying it is the theoretical S2D best-practice pipeline, not a live utilisation view. Actual state is reflected in the Volume Map and Health Checks sections.

### Fixed

- `Show-S2DOverprovisionedReport.ps1` — replaced hardcoded `using module` with runtime dot-source of class files so the script runs correctly from any working directory without requiring module type export.

## [1.0.6] — 2026-04-12

### Fixed

- `Connect-S2DCluster`: short cluster name resolution now checks `TrustedHosts` first and promotes the short name to a matching FQDN entry (e.g. `tplabs-clus01` → `tplabs-clus01.azrl.mgmt`). On workgroup / non-domain-joined hosts, DNS suffix search lists for internal AD domains are usually absent, so the 1.0.5 DNS-only resolver silently fell through to the short name and produced `0x8009030e`. `TrustedHosts` is authoritative on these hosts and already reflects what WinRM will accept.
- Resolution order is now: TrustedHosts → DNS (`GetHostEntry`) → short name pass-through → precise remediation error.

### Changed

- `Connect-S2DCluster` credential prompt message now includes the accepted username formats (`DOMAIN\user` or `user@fqdn.domain`) and explicitly notes that a plain local username will not authenticate against a domain cluster. Renders directly in the `Get-Credential` dialog.

## [1.0.5] — 2026-04-12

### Fixed

- `Connect-S2DCluster`: when the caller supplies a short cluster name (e.g. `tplabs-clus01` instead of `tplabs-clus01.azrl.mgmt`), the cmdlet now resolves the short name to a FQDN via DNS before opening the CIM session. Workgroup and non-domain-joined hosts typically have `TrustedHosts` configured with FQDNs, so a short-name target would previously fail with `0x8009030e` at `New-CimSession` even with correct credentials. The resolved FQDN is stored in `$Script:S2DSession.ClusterFqdn`.
- `Connect-S2DCluster`: `New-CimSession` failures in the `ByName` path are now caught and rethrown with a multi-line remediation message that calls out the four most common causes — TrustedHosts missing the cluster FQDN, wrong credentials, short-name DNS failure, and `-Local` as an alternative — instead of surfacing the raw WinRM exception. The message also reports whether the host is domain-joined, which is the usual trigger.

## [1.0.4] — 2026-04-12

### Fixed

- `Connect-S2DCluster`: when `-Credential` is not supplied in the `ByName` parameter set, the cmdlet now prompts interactively via `Get-Credential` instead of silently falling through to `New-CimSession` with the current logged-on user context — which almost always fails on workgroup or cross-domain hosts with a cryptic "Access is denied". Callers running non-interactively must supply `-Credential`, use `-Local`, or pass a prebuilt `-CimSession`/`-PSSession`.

## [1.0.3] — 2026-04-12

### Fixed

- **Workgroup / non-domain-joined fan-out failure** — `Connect-S2DCluster` now resolves each enumerated short node name to a fully qualified target (via the cluster FQDN suffix, falling back to DNS) and stores the mapping in `$Script:S2DSession.NodeTargets`. `Get-S2DPhysicalDiskInventory` opens per-node CIM sessions against the FQDN target instead of the short name, which matches typical `TrustedHosts` configuration on workgroup management hosts. Closes [#33](https://github.com/AzureLocal/azurelocal-S2DCartographer/issues/33).
- **Preflight validation** — after cluster connect, `Connect-S2DCluster` now test-opens a CIM session against the first resolved node target. If it fails, the cmdlet throws one precise error listing the node FQDNs and three concrete remediations (domain-joined host, `-Local` mode, or TrustedHosts configuration) instead of letting N generic WinRM warnings fall out of the per-collector fan-out path.

### Added

- `Resolve-S2DNodeFqdn` (private) — deterministic helper that converts a short node name to an FQDN using cluster suffix append → DNS lookup → short-name fallback. Unit-tested offline.

## [1.0.2] — 2026-04-11

### Fixed

- `Get-S2DPhysicalDiskInventory`: per-node CIM sessions now inherit Authentication method and Credential from the module session, fixing WinRM Kerberos failures on non-domain-joined or cross-domain clients — completes [#31](https://github.com/AzureLocal/azurelocal-S2DCartographer/issues/31).
- `Connect-S2DCluster`: `ByKeyVault` parameter set now passes `-Authentication Negotiate` to `New-CimSession` instead of relying on the Kerberos default.
- `Invoke-S2DCartographer`: add `-Authentication` parameter that passes through to `Connect-S2DCluster`.
- Module session state (`$Script:S2DSession`) now stores `Authentication` and `Credential` so downstream collectors can create per-node CIM sessions with the same auth settings.

## [1.0.1] — 2026-04-11

### Fixed

- `Connect-S2DCluster`: add `-Authentication` parameter (default: `Negotiate`) to `New-CimSession`. Fixes WinRM Kerberos failure on non-domain-joined or cross-domain clients — closes [#31](https://github.com/AzureLocal/azurelocal-S2DCartographer/issues/31).

## [1.0.0] — 2026-04-11

### Added

- `Get-S2DStoragePoolInfo` — pool capacity, health, resiliency settings, storage tiers, overcommit ratio.
- `Get-S2DVolumeMap` — per-volume resiliency type, pool footprint, efficiency %, provisioning type, infrastructure volume detection.
- `Get-S2DCacheTierInfo` — cache mode, all-flash/all-NVMe detection, software write-back cache identification.
- `Get-S2DHealthStatus` — 10 health checks (ReserveAdequacy, DiskSymmetry, VolumeHealth, DiskHealth, NVMeWear, ThinOvercommit, FirmwareConsistency, RebuildCapacity, InfrastructureVolume, CacheTierHealth) with pass/warn/fail and remediation guidance.
- `Get-S2DCapacityWaterfall` — 8-stage capacity accounting pipeline from raw physical to final usable VM space.
- `Invoke-S2DCartographer` — one-command orchestrator: connect → collect → report → disconnect. Supports all report formats, diagram types, Key Vault credentials, and `-PassThru`.
- `New-S2DReport` — HTML (Chart.js dashboard), Word (.docx, no Office required), PDF (headless Edge/Chrome), and Excel (.xlsx via ImportExcel).
- `New-S2DDiagram` — 6 SVG diagram types: Waterfall, DiskNodeMap, PoolLayout, Resiliency, HealthCard, TiBTBReference.
- 119 Pester 5 unit tests across all collectors, capacity math, and health checks.
- Complete MkDocs documentation site: getting-started, collectors, reports, diagrams, capacity-math, tib-vs-tb.
- Sample output files: `samples/sample-waterfall.svg`, `samples/sample-html-report.html`.

### Changed

- Minimum PowerShell version raised to 7.2 (was 7.0).
- `ProjectUri` updated to point to the GitHub repository.

## [0.1.0-preview2] — 2026-03-28

### Fixed

- `Connect-S2DCluster` failing on non-domain-joined management machines. S2D validation now uses `Get-StoragePool` via CIM instead of `Get-ClusterS2D`.
- Cluster node discovery switched to `MSCluster_Node` CIM class via remote session instead of `Get-ClusterNode` (which required local RSAT).

## [0.1.0-preview1] — 2026-03-15

### Features

- Initial repository scaffold, module manifest, folder structure, GitHub Actions CI/CD.
- `S2DCapacity` class — dual-unit capacity with `Bytes`, `TiB`, `TB`, `GiB`, `GB`, `Display`.
- `ConvertTo-S2DCapacity` — converts bytes, TB, or TiB to `S2DCapacity`.
- `Connect-S2DCluster`, `Disconnect-S2DCluster`.
- `Get-S2DPhysicalDiskInventory`.
- Pester 5 unit tests for capacity math and reserve calculation.
- MkDocs Material documentation site scaffolding.
- `release-please` configuration.
