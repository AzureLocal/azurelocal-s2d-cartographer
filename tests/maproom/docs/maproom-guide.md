# Operation MAPROOM Guide

## What MAPROOM Is

Operation MAPROOM is the offline synthetic and fixture-backed testing solution for S2DCartographer.

MAPROOM exists so the project can validate capacity math, unit conversion, disk inventory processing,
and health check logic without requiring a live S2D cluster or WinRM session.

## Why MAPROOM Exists

Live cluster access is not always available.

If every unit test or capacity math regression required a WinRM session, the project would be
untestable in most environments. MAPROOM solves that by working from known fixture data and
the IIC synthetic cluster generator.

## Relationship To TRAILHEAD

`TRAILHEAD` and `MAPROOM` are complementary, not the same.

- `TRAILHEAD` is live field validation against a real S2D cluster.
- `MAPROOM` is offline testing against fixture data and synthetic cluster definitions.

If the question is "does S2DCartographer work against a real cluster," that belongs to `TRAILHEAD`.

If the question is "does the capacity math or disk inventory logic work when fed valid cluster-shaped data," that belongs to `MAPROOM`.

## Folder Layout

```text
tests/
  maproom/
    Fixtures/
    unit/
    integration/
    scripts/
    docs/
    README.md
```

### `Fixtures/`

Committed offline test data including:

- Per-configuration mock cluster JSON (2-node, 3-node, 4-node, 16-node)
- Degraded-state fixtures
- Synthetic cluster JSON from `New-S2DSyntheticCluster.ps1`

### `unit/`

Focused Pester unit tests covering:

- TiB/TB capacity conversion math
- Reserve calculation logic
- Resiliency efficiency percentages
- Health check pass/fail evaluation

### `integration/`

Fixture-backed integration tests validating larger slices without a live cluster.

### `scripts/`

- `New-S2DSyntheticCluster.ps1` — generates a standards-compliant IIC synthetic cluster fixture
- `Test-S2DFromSyntheticCluster.ps1` — validates module outputs against the synthetic cluster

### `docs/`

This guide and detailed MAPROOM documentation.

## Main Scripts

### `New-S2DSyntheticCluster.ps1`

Generates `tests/maproom/Fixtures/synthetic-cluster.json` with a 4-node IIC cluster using 3.84 TB NVMe disks and three-way mirror. Use to regenerate fixture data after changing the cluster shape.

```powershell
.\tests\maproom\scripts\New-S2DSyntheticCluster.ps1
```

### `Test-S2DFromSyntheticCluster.ps1`

Loads the synthetic fixture, runs `ConvertTo-S2DCapacity` against known-good values, and validates health check outputs. Use for manual regression testing.

```powershell
.\tests\maproom\scripts\Test-S2DFromSyntheticCluster.ps1
```

## IIC Canonical Data Standard

All Pester tests and synthetic fixtures use the IIC (Infinite Improbability Corp) fictional company data. Never use real environment names (real cluster names, customer names) in committed test data.

IIC reference:
- Company: Infinite Improbability Corp
- Domain: `iic.local` / NetBIOS: `IMPROBABLE`
- Cluster: `azlocal-iic-s2d-01`
- Nodes: `azl-iic-n01` through `azl-iic-n04`
