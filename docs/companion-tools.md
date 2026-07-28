# Companion Tools

S2DCartographer is part of a broader set of Azure Local tooling. These tools are designed to complement each other across the full cluster lifecycle.

---

## Azure Local Surveyor

**[Azure Local Surveyor](https://azurelocal.github.io/azurelocal-surveyor)** is a pre-deployment capacity and workload modeling tool. Use it before you build the cluster to validate hardware sizing, model resiliency scenarios, and plan workload placement.

| | Surveyor | S2DCartographer |
|---|---|---|
| **When to use** | Before deployment | After deployment |
| **Input** | Hardware specs, workload requirements | Live cluster or JSON snapshot |
| **Output** | Capacity model, sizing recommendations | Audit report, health checks, what-if scenarios |
| **Live cluster required** | No | No (snapshot mode) |

> [!TIP]
> **The workflow**
> **Surveyor plans; Cartographer verifies.** Run Surveyor during the design phase to confirm your hardware choices meet your capacity requirements. Run S2DCartographer after deployment to validate the build matches what was planned — and on an ongoing basis to track health and available headroom.
