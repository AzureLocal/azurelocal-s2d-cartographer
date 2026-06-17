# azurelocal-s2d-cartographer — Claude Code Context

## What this repo is

S2D Cartographer is a PowerShell module that audits and reports on Storage Spaces Direct (S2D) clusters in Azure Local environments. It collects cluster state, disk topology, fault domain layout, and capacity data, then renders structured HTML, Word, and Excel reports. It is not a remediation tool — it reads and reports only, never writes to cluster state.

---

## ADO project details

- **ADO org:** https://dev.azure.com/hybridcloudsolutions
- **ADO project:** Azure Local
- **Area path:** Platform Engineering\Onboarding
- **Work item format:** `AB#<id>` in commit messages and PR descriptions

---

## Standards

This repo follows all HCS platform standards defined in the Platform Engineering repo:

| Standard | Reference |
|---|---|
| Governance | [docs/standards/governance.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/governance.md) |
| Scripting (PowerShell 7) | [docs/standards/scripting.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/scripting.md) |
| Automation | [docs/standards/automation.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/automation.md) |
| Variables and naming | [docs/standards/variables.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/variables.md) |
| Documentation | [docs/standards/documentation.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/documentation.md) |
| Claude Code | [docs/standards/claude-code.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/claude-code.md) |

Key rules:
- All scripts: PowerShell 7+ only. `#Requires -Version 7.0`, `Set-StrictMode -Version Latest`, ` $ErrorActionPreference = 'Stop'`.
- All docs: Markdown only. No Word documents in any repo.
- Commit format: `type(scope): short description` — types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`
- No secrets, tokens, or credentials committed to any file.

---

## Key facts

| Fact | Value |
|---|---|
| Primary language | PowerShell 7 |
| GitHub org | AzureLocal |
| Azure login | kris@hybridsolutions.cloud |
| Key Vault | kv-hcs-vault-01 |

### Environment variables expected

| Variable | Source | Purpose |
|---|---|---|
| `GITHUB_TOKEN` | kv-hcs-vault-01 via Load-HCSEnvironment.ps1 | GitHub CLI and git operations |
| `AZURE_DEVOPS_EXT_PAT` | kv-hcs-vault-01 via Load-HCSEnvironment.ps1 | ADO CLI (`az boards`, `az devops`) |
Load before starting a session:
```powershell
. D:\git\platform\scripts\Load-HCSEnvironment.ps1
```

### Build and test commands

```
mkdocs build
mkdocs serve  # http://127.0.0.1:8000
```

---

## Repo structure

```
azurelocal-s2d-cartographer/
├── .github/
    ├── ISSUE_TEMPLATE/
    ├── workflows/
    ├── CODEOWNERS
    └── PULL_REQUEST_TEMPLATE.md
├── docs/
    ├── assets/
    ├── cmdlets/
    ├── collectors/
    ├── concepts/
    └── project/
├── Modules/
    ├── Classes/
    ├── Collectors/
    ├── Outputs/
    ├── Private/
    └── Public/
├── repo-management/
    ├── plans/
    ├── automation.md
    ├── README.md
    └── setup.md
├── samples/
    ├── cluster-snapshot.json
    ├── overprovisioned-report.html
    ├── sample-html-report.html
    ├── sample-waterfall.svg
    └── sample-whatif-report.html
├── tests/
    ├── maproom/
    ├── trailhead/
    └── README.md
├── .azurelocal-platform.yml
├── .gitignore
├── .release-please-manifest.json
├── azurelocal-s2d-cartographer.code-workspace
├── CHANGELOG.md
├── CLAUDE.md
├── CONTRIBUTING.md
├── LICENSE
├── mkdocs.yml
├── README.md
├── release-please-config.json
├── S2DCartographer.psd1
└── ...
```

---

## Claude Code actions

**Run autonomously:**
- Read, search, and grep any file in this repo
- Write and edit files in this repo
- `git add`, `git commit`, `git push`
- `gh issue`, `gh pr`, `gh run` CLI commands
- `mkdocs build` and `mkdocs serve`
- `pip install` for MkDocs plugins

**Always confirm before:**
- Creating or deleting Azure resources
- Any `az` CLI write operation that modifies Azure state
- Running destructive operations
- Making API calls to external services


---

## Subagents available in this repo

- `azurelocal-s2d-cartographer-engineer` (model: sonnet) — PowerShell module engineer for S2D Cartographer: collector design, report rendering, Pester tests, PSGallery publishing.

User-level agents (every repo): `triage-lookup`, `markdown-prose-editor`, `azurelocal-domain-expert`, `mkdocs-material-doctor`, `turner-module-scaffold-engineer`, `mms-2026-demo-presenter`.

Platform repo agents (when working in `D:\git\platform`): `orchestration-pm`, `security-waf-caf`, `terraform-validator`, `bicep-validator`, `arm-validator`, `ansible-linter`, `powershell-linter`, `reviewer`, `security-reviewer`, `documenter`, `coder`, `planner`, `operator`, `investigator`, `test-writer`, `router`.

---

## Owner

**Kristopher Turner**
kris@hybridsolutions.cloud
Senior Product Technology Architect, TierPoint | Microsoft MVP (Azure) | MCT
Owner, Hybrid Cloud Solutions LLC — hybridsolutions.cloud
Country Cloud Boy — thisismydemo.cloud

---

## HCS Orchestration Profile

**Validation profile:** iac-powershell — see `D:\git\platform\profiles\iac-powershell.yaml`

This repo is a **pilot** for the `iac-powershell` type in the HCS multi-agent orchestration system.
Run `/dispatch iac-powershell` (or `/dispatch` for all pilots) to validate this repo.

**Repo-specific notes for validators:**
PSScriptAnalyzer `-Severity Warning,Error` must pass. All `.ps1` files require `#Requires -Version 7.0`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`. Pester tests in `tests/`. Module public/private structure in `Modules/Public/` and `Modules/Private/`.
