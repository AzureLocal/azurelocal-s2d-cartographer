# Roadmap

S2DCartographer follows a milestone-based release cadence. Each milestone targets a focused
capability area. The current stable release is **v1.9.0**, published live on PSGallery.

Live status of everything below is tracked on
[GitHub Milestones](https://github.com/AzureLocal/azurelocal-s2d-cartographer/milestones).

---

## Upcoming — v2.0.0 — Extended Hardware Coverage

| Issue | Feature |
| --- | --- |
| [#25](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/25) | **OEM-specific disk enrichment** — extend `Get-S2DPhysicalDiskInventory` with vendor-specific data from Dell iDRAC, HPE iLO, Lenovo XClarity, and DataON interfaces. Surfaces drive bay location, predicted failure, and platform-level health alongside standard S2D disk data. Pending a validation environment across all four vendors. |

---

## Upcoming — Future Release — Visualization, Scoring & Output

Feature uplift covering interactive diagrams, graduated health check scoring, PDF layout
improvements, and operational robustness. Targeting a release after v2.0.0.

### Health Check & Scoring

| Issue | Feature |
| --- | --- |
| [#57](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/57) | **Graduated threshold scoring** — partial-credit rules for health checks; replaces flat pass/fail with weighted, threshold-based scoring. |
| [#58](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/58) | **Named calculation references** — pre-computed aggregates defined in health check config; depends on #57. |
| [#59](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/59) | **Health check config download and hot-swap** — download and upload the health check JSON config via CLI without re-running collection; depends on #57, #58. |

### Visualization

| Issue | Feature |
| --- | --- |
| [#60](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/60) | **vis.js interactive topology diagram** — cluster, pool, and volume hierarchy rendered as an interactive in-browser diagram. |
| [#61](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/61) | **html2canvas diagram capture** — embed the interactive vis.js diagram as a PNG in PDF and Word reports; depends on #60. |

### PDF & Report Layout

| Issue | Feature |
| --- | --- |
| [#62](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/62) | **Page-break-aware table helper** — automatic header repeat across page breaks for all multi-page tables. |
| [#63](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/63) | **Portrait/landscape page switching per PDF section** — wide tables switch to landscape and back; depends on #62. |
| [#64](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/64) | **Conditional cell coloring** — status and severity-based colour coding in HTML and PDF tables; depends on #62. |

### Output & Cost

| Issue | Feature |
| --- | --- |
| [#65](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/65) | **JSON evidence export** — raw collected data export with no scoring metadata, for downstream tooling and audit trails. |
| [#68](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/68) | **Azure Hybrid Benefit and licensing cost savings** — surface AHB coverage, per-core cost, and potential savings in the report. |

### UX

| Issue | Feature |
| --- | --- |
| [#66](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/66) | **Full-screen progress overlay** — named collection stage labels shown during run so operators know what is happening. |
| [#67](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/67) | **Per-section search and filter** — search input in HTML report to filter table rows per section. |

---

## Completed

| Version | Highlights |
| --- | --- |
| **v1.9.0** | **Provisioning-aware 70% headroom presentation** — amber/warning on the 70% KPI tile, waterfall planning-line row, and headroom table fires only when thin-provisioned volumes are present. All-fixed clusters render 70% as advisory/neutral. `Get-S2DExpansionHeadroom` gains `HasThinVolumes` boolean. **"Size to enter (New-Volume / WAC)" column** — each headroom row shows the exact value to type (`{TiB-floor2}TB`); PowerShell/WAC read suffixes as binary. JSON snapshot gains `SizeToEnterTiB` per threshold. **WAF correction: N+1/N+2 re-framed as compute advisory** — v1.8.0 incorrectly treated this as a storage check; corrected to informational context only (`Status='Info'`, no storage verdict, Check 12 always `Status='Pass'` at `Severity='Info'`). Reports re-labelled as compute advisory. |
| **v1.8.0** | **Maintenance reserve (N+1) assessment** — reports whether the scanned cluster has enough free capacity (beyond the rebuild reserve) to drain a node for updates, per Microsoft Well-Architected guidance. New `MaintenanceReserveN1` health check and report indicator (Meets / Does not meet, with required vs available headroom in TB and TiB); configurable target via `-MaintenanceReserveTarget None\|N+1\|N+2` (default N+1). Assessment only — does not change any measured capacity number. Mirrors Surveyor's optional N+1/N+2 deduction. |
| **v1.7.1** | **Expansion Headroom** report section (HTML, Word, PDF, JSON) — at 70% / 80% / 90% / 100% pool-fill targets, shows remaining pool footprint and new usable data (footprint ÷ resiliency copies) in TB and TiB, with a Chart.js chart; 70% row styled as the recommended planning line. Math identical to Surveyor's so the two tools reconcile. Fixed per-volume capacity efficiency to derive from the measured `FootprintOnPool ÷ Size` ratio — a two-copy mirror now correctly reports 50% (was mislabeled 25% on two-node clusters). |
| **v1.7.0** | Wave 3 — Validation & report correctness. Cross-tool reconciliation keystone: golden-cluster Pester suite (24 cases, 4 clusters) asserts Cartographer engine output reconciles with Surveyor within ±2% (AB#4633). Concurrent collection guard prevents overlapping runs from corrupting shared state (AB#279). Empty-data safeguards added to `Get-S2DCapacityWaterfall`, `Get-S2DHealthStatus`, and `Get-S2DStoragePoolInfo` (AB#279). PDF waterfall bar now uses exact byte-derived TB values (AB#263 / [#53](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/53)). PDF pool allocation reserve boundary and pool health bar x-axis fixed (AB#264 / [#54](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/54)). Word executive summary table given explicit column widths and cell padding (AB#265 / [#55](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/55)). Word overall document layout — margins, fixed-layout tables, hand-tuned column widths (AB#266 / [#56](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/56)). |
| **v1.6.0** | Wave 2 — Legibility. Every capacity figure now carries both TB and TiB labels plus a space badge (`FOOTPRINT`, `DATA (usable)`, `INFORMATIONAL`) in the waterfall and HTML report (AB#4645). 70% planning line added — 70% of available-for-volumes vs. consumed volume footprint, matching Surveyor's definition exactly; surfaced as a KPI tile and dashed chart line (AB#4644). |
| **v1.5.0** | Wave 1 — Capacity accuracy. Resiliency factor always derived from each volume's actual `NumberOfDataCopies`; fallback changed from 3.0 to 2.0 (two-way mirror) with explicit labeling when assumed (AB#4642). Reserve calculation confirmed canonical — one capacity drive per server, up to 4 drives, raw-byte basis (AB#4643). |
| **v1.4.2** | Fix `RebuildCapacity` false Critical when NodeName grouping is unreliable after pool-member disk deduplication. |
| **v1.4.1** | Fix pool-member disk duplication on multi-node clusters — `Get-PhysicalDisk` on any S2D node returns all pool members globally; deduplicate by `UniqueId` to prevent 4× inflation of Stage 1 raw capacity. Adds top-level `NodeCount` to JSON snapshot. |
| **v1.4.0** | 7-stage waterfall (Stage 8 removed), stage health isolation (all stages always OK, reserve health on `ReserveStatus` only), reserve formula corrected, infra volume detection extended (`UserStorage_N`, `HCI_UserStorage_N`, `SBEAgent`), HTML delta column, Word report waterfall table, `Invoke-S2DCapacityWhatIf` delta loop fix. Closes [#46](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/46)–[#52](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/52). |
| **v1.3.1** | Sample output reports in docs. |
| **v1.3.0** | What-if capacity modeling (`Invoke-S2DCapacityWhatIf`), thin provisioning risk detection (Check 6 tiered thresholds + new Check 11 ThinReserveRisk), `ThinGrowthHeadroom` / `MaxPotentialFootprint` volume properties, Thin Provision Risk KPI in HTML report, `Invoke-S2DWaterfallCalculation` pure function. Closes [#27](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/27), [#44](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/44). |
| **v1.2.1** | Capacity model correctness — pool-member-only Stage 1, purely theoretical Stages 7/8, resiliency factor from pool settings. Closes [#43](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/43). |
| **v1.2.0** | JSON snapshot export (SchemaVersion 1.0), opt-in CSV per-collector tables, pool-member disk filter (`IsPoolMember`) across reports and health checks, Surveyor cross-link in docs, `-IncludeNonPoolDisks` switch. Closes [#35](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/35), [#40](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/40), [#41](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/41), [#42](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/42). |
| **v1.1.1** | Fix parameter-set splat in `Invoke-S2DCartographer` that broke `-KeyVaultName` and explicit `-Authentication`; added `-Username` parameter for Key Vault secrets without a ContentType tag. Closes [#39](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/39). |
| **v1.1.0** | Default `-Format` changed to `All`; `ImportExcel` bundled as a `RequiredModules` dependency; per-run output folder structure `<OutputDir>\<ClusterName>\<yyyyMMdd-HHmm>\`; session log file; thicker pool allocation breakdown bar; full authentication / remoting / node fan-out docs with flowchart diagram. Closes [#34](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/34), [#36](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/36), [#37](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/37), [#38](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/38). |
| **v1.0.8** | Fix `Get-S2DHealthStatus` crash on live clusters — replaced `Generic.List[S2DHealthCheck]` with a plain array to work around PowerShell class type resolution on dot-sourced classes. |
| **v1.0.7** | Storage Pool Health bar (WAC-style), Pool Allocation Breakdown bar, Capacity Model stage descriptions, Critical Reserve Status KPI. |
| **v1.0.2 – v1.0.6** | Workgroup / non-domain-joined connectivity fixes — WinRM authentication inheritance, TrustedHosts short-name resolution, per-node CIM fan-out FQDN resolution, pre-flight credential validation. |
| **v1.0.0** | Full pipeline: all 6 collectors, HTML/Word/PDF/Excel reports, 6 SVG diagram types, `Invoke-S2DCartographer` orchestrator, 119 Pester tests, MkDocs documentation site. |
| **v0.1.0-preview2** | Bug fix: non-domain-joined connectivity (`Connect-S2DCluster`). |
| **v0.1.0-preview1** | Foundation: `S2DCapacity` class, `ConvertTo-S2DCapacity`, `Connect-S2DCluster`, `Get-S2DPhysicalDiskInventory`. |

---

## Requesting Features

Open an issue at [AzureLocal/azurelocal-s2d-cartographer](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/new) using the feature request template. Include the cluster configuration context (node count, drive types, Azure Local version) — most useful features come from real deployment scenarios.
