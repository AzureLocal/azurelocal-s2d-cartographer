# Repo intent — azurelocal-s2d-cartographer

**Map your storage. Know your capacity. — Storage Spaces Direct inventory and capacity analysis for Azure Local.**

## What this repo is

S2DCartographer connects to a live Azure Local or Windows Server cluster,
inventories every layer of the Storage Spaces Direct stack, and produces
publication-quality capacity analysis, health assessments, and visual diagrams —
generating HTML, Word, PDF, and Excel reports to validate what was actually
built.

## Shape

- `S2DCartographer.psd1`/`.psm1`, `Modules/` — the PowerShell module
- Published on PSGallery

## How it relates to other repos

- **`azurelocal-surveyor`** — plans capacity *before* deployment; this repo
  verifies what was actually built *after* deployment. Explicitly complementary
  per Surveyor's own README ("Surveyor plans before deployment; S2DCartographer
  verifies after deployment")

## Status

Active, published, CI-tested (GitHub Actions badge in README), MIT licensed.
