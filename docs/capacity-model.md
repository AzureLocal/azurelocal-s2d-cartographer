# Canonical Capacity Model (Wave 0 — ratified)

> **Single source of truth** for capacity math in **both** Surveyor and S2D Cartographer.
> Identical copy in both repos. Waves 1+ code against this. Produced by the Wave 0 formula audit
> (2026-06-29) of both codebases, grounded in Microsoft Storage Spaces Direct documentation.

## Why this exists

A scan (Cartographer) and an estimate (Surveyor) of the **same** cluster reported different
"Available for Volumes" (22.44 vs 20.45 TB). The audit traced the gap to four concrete, fixable
differences plus a unit mismatch. This document defines the one model both tools must implement so the
numbers reconcile within **±2%**.

---

## The four open questions — ANSWERED

### Q1. What is Surveyor's `0.92` per-drive factor? → A *blended, partly double-counted* constant. **Decompose it.**
- It lives at `src/engine/capacity.ts:79` (`capacityEfficiencyFactor`, default `0.92`,
  `types.ts:65`, commented "filesystem overhead per drive").
- It bundles ReFS/format overhead + NVMe over-provisioning + **roughly half of the TB→TiB unit
  conversion**. Surveyor *also* converts TB→TiB separately at `capacity.ts:103` (`1e12/2^40 ≈ 0.9091`),
  so part of the unit difference is **counted twice**.
- Cartographer applies **no** haircut because Windows `PhysicalDisk.Size` is already the drive's true
  byte count — there is nothing to "haircut" at the pool/byte level.
- **Decision:** raw capacity is the true byte count (no blended 0.92). Any real filesystem overhead is a
  **separate, small, explicitly named factor applied to volume usable space**, never silently to the pool,
  and the TB↔TiB conversion is done **once**, explicitly. *(AB#4641)*

### Q2. Is Cartographer's `÷3` a calculation or a label? → A **real calculation**, with a dangerous default.
- `Invoke-S2DWaterfallCalculation.ps1:100` divides by `$ResiliencyFactor` (default `3.0`, line 67).
- The live collector *does* read the real copy count (`Get-S2DCapacityWaterfall.ps1:76-80`,
  `NumberOfDataCopies`), but when a pool exposes no resiliency setting it **silently falls back to ÷3**,
  understating a 2-copy cluster's usable capacity by 33%.
- **Decision:** always divide by the **actual `NumberOfDataCopies`** per volume (or the pool's real
  setting); change the unsafe fallback from `3.0` to `2.0` and label it as an assumption. *(AB#4642)*

### Q3. TB vs TiB → **One internal unit (bytes); display TiB primary + TB in parens; convert once.**
- Cartographer already does this correctly (`S2DCapacity.ps1:12-17`).
- Surveyor mixes: the engine runs in decimal TB, converts to TiB only at the end, **and** the
  `VolumeTable` UI labels inputs "TiB" while storing decimal TB with no conversion
  (`VolumeTable.tsx:29-57`). *(AB#4640)*

### Q4. Footprint vs usable → **Label every figure.**
- `footprint = volume size × copies`; `usable (data) = footprint ÷ copies`. Pool-level "available" is
  **footprint space**; per-volume "usable" is **data space**. Never present a number without saying which.
  *(AB#4640 / AB#4645)*

---

## The canonical pipeline (both tools implement this exact order)

All math is in **bytes** internally. Display derives TiB (`÷2^40`) and TB (`÷10^12`) from the same byte value.

| # | Stage | Formula | Space |
|---|---|---|---|
| 1 | **Raw** | `Σ PhysicalDisk.Size` (capacity tier), true bytes | footprint |
| 2 | **Pool metadata overhead** | live `StoragePool.Size`, else `raw × 0.99` (~1%) | footprint |
| 3 | **Reserve** | `min(nodes, 4) × largestCapacityDriveBytes` — **same basis both tools** | footprint |
| 4 | **Infrastructure volume** | measured `VirtualDisk.FootprintOnPool` when scan exists; else labeled estimate | footprint |
| 5 | **Available for Volumes** | `raw − poolOverhead − reserve − infra` | **footprint** |
| 6 | **Usable (data)** | `availableForVolumes ÷ copies` where `copies = actual NumberOfDataCopies` | **data** |
| 7 | **70% planning line** | `0.70 × availableForVolumes` (footprint basis — what the alert fires on) | footprint |
| 8 | **ReFS/format overhead** | *optional*, small, explicit, applied to **usable**, never to the pool | data |

### Locked S2D facts (Microsoft docs)

| Resiliency | Copies | Efficiency | Min nodes |
|---|---|---|---|
| Two-way mirror | 2 | 50.0% | 2 |
| Three-way mirror | 3 | 33.3% | **3** |
| Nested two-way mirror | 4 | 25% | 2 |
| Nested mirror-accelerated parity | — | ~35–40% | 2 |
| Dual parity | — | 50–80% | 4 |

- **3-way requires ≥3 nodes** — on 2 nodes only two-way or nested is valid. Surveyor's engine does **not**
  hard-block 3-way on 2 nodes today (`capacity.ts` never calls `minNodesForResiliency`; gating is only an
  advisory health check) → **AB#4636 is a real bug.** For 2-node *production*, surface **nested** resiliency.
- **Reserve = one capacity drive per server, up to 4** (per-server, drive-based — not a flat % or 0.75 TB).
- `footprint = size × copies`; `efficiency = usable ÷ footprint`.
- Asymmetric drives → stranded capacity; only capacity present in **every** server is guaranteed usable.

---

## What each tool must change to reconcile

| Driver | Surveyor today | Cartographer today | Canonical |
|---|---|---|---|
| Per-drive efficiency | `× 0.92` blended (double-counts units) | none | true bytes; split out a small named ReFS factor; convert units once *(AB#4641)* |
| Reserve basis | `× usable/drive` (eff-adjusted) | `× raw drive bytes` | one agreed basis: `min(nodes,4) × largest drive bytes` *(AB#4643)* |
| Copies divisor | factor by resiliency type | real `NumberOfDataCopies`, **fallback 3.0 unsafe** | actual copies; fallback **2.0** *(AB#4642)* |
| Infra volume | `0.25/resiliency` placeholder (0.5–0.75 TB) | measured footprint | measured when scanned, else labeled estimate *(AB#4638)* |
| Units | engine TB; UI mislabels TiB | bytes → TiB(+TB) correct | bytes internal; TiB primary + TB parens *(AB#4640/4645)* |
| 70% line | thresholds in health check/suggestions; not drawn as a line | absent | draw against available-for-volumes in both *(AB#4639/4644)* |

### Reference-cluster reconciliation (3.84 TB × 4 drives × 2 nodes, two-way mirror)

| Stage | Canonical (TB / TiB) |
|---|---|
| Raw | 30.72 / 27.94 |
| − pool overhead (~1%) | 30.41 / 27.66 |
| − reserve (2 drives) | 22.73 / 20.68 |
| − infra (measured, ~0.3) | ~22.4 / ~20.4 |
| **Available for Volumes (footprint)** | **~22.4 / ~20.4** |
| Usable data (÷2) | ~11.2 / ~10.2 |

Surveyor's old `20.45` came from applying `0.92` to every drive **and** running three-way default
(infra 0.75). Cartographer's `22.44` is the byte-accurate footprint. Under the canonical model both land
at ~22.4 TB / ~20.4 TiB footprint — the apparent "2 TB gap" was the 0.92 double-count plus a
TB-vs-TiB comparison.

## Definition of done (Wave 1 exit gate)
Same cluster → **Available for Volumes agrees within ±2%** and every intermediate stage matches to the
same precision, enforced by a golden-cluster reconciliation test in CI (Wave 3).

## References
- Fault tolerance & efficiency — <https://learn.microsoft.com/windows-server/storage/storage-spaces/fault-tolerance>
- Plan volumes (footprint, reserve, resiliency by node count) — <https://learn.microsoft.com/windows-server/storage/storage-spaces/plan-volumes>
- Nested resiliency — <https://learn.microsoft.com/windows-server/storage/storage-spaces/nested-resiliency>
- Drive symmetry / stranded capacity — <https://learn.microsoft.com/windows-server/storage/storage-spaces/drive-symmetry-considerations>
