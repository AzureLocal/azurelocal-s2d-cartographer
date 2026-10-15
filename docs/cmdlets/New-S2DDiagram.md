# New-S2DDiagram

Generates SVG diagrams for capacity waterfall, disk-node map, pool layout, and resiliency.

---

## Synopsis

Accepts an `S2DClusterData` object and renders SVG diagrams to the output directory. SVG files are web-resolution vector graphics suitable for embedding in reports or documentation.

Diagram types:

| Type | Description |
|---|---|
| `Waterfall` | 7-stage capacity waterfall horizontal bar diagram with TiB and TB labels |
| `DiskNodeMap` | Node boxes with disks color-coded by role (cache/capacity) and health |
| `PoolLayout` | Storage pool allocation breakdown — user data, reserve, infrastructure, free |
| `Resiliency` | Per-volume resiliency type, footprint, and efficiency percentage |
| `HealthCard` | Traffic-light health scorecard showing all 11 check results |
| `TiBTBReference` | Common NVMe drive sizes in both TiB and TB for reference |

---

## Syntax

```powershell
<S2DClusterData> | New-S2DDiagram
    [-DiagramType <string[]>]
    [-OutputDirectory <string>]
```

```powershell
New-S2DDiagram
    -InputObject <S2DClusterData>
    [-DiagramType <string[]>]
    [-OutputDirectory <string>]
```

---

## Parameters

### `-InputObject`

| | |
|---|---|
| Type | `object` (S2DClusterData) |
| Required | Yes |
| Pipeline | Yes |
| Default | — |

S2DClusterData object from `Invoke-S2DCartographer -PassThru`. Accepts pipeline input.

---

### `-DiagramType`

| | |
|---|---|
| Type | `string[]` |
| Required | No |
| Default | `All` |
| Valid values | `Waterfall`, `DiskNodeMap`, `PoolLayout`, `Resiliency`, `HealthCard`, `TiBTBReference`, `All` |

One or more diagram types to generate. `All` generates every type.

---

### `-OutputDirectory`

| | |
|---|---|
| Type | `string` |
| Required | No |
| Default | `C:\S2DCartographer` |

Destination folder for SVG files. Created if it does not exist.

---

## Outputs

`string[]` — paths to generated SVG files.

---

## Examples

**All diagrams:**

```powershell
Invoke-S2DCartographer -ClusterName clus01 -PassThru | New-S2DDiagram
```

**Waterfall and disk map only:**

```powershell
New-S2DDiagram -InputObject $data -DiagramType Waterfall, DiskNodeMap
```

**Custom output folder:**

```powershell
$data | New-S2DDiagram -OutputDirectory D:\Diagrams
```
