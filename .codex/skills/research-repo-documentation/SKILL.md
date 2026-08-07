---
name: research-repo-documentation
description: Generate or update repository-level and project-level documentation for this campaign finance research repository. Use when Codex is asked to improve docs, create project documentation, explain which scripts/data belong to a project, update roadmaps, document replication workflows, or maintain docs under docs/, docs/projects/, data/README.md, outputs/README.md, scripts/data_collection/README.md, AGENTS.md, or README.md.
---

# Research Repo Documentation

## Core Goal

Create documentation that lets another researcher replicate the work with the right scripts, data, run order, outputs, assumptions, and validation checks. Prefer detailed, explicit documentation over terse summaries.

## Required Context Pass

Before editing documentation:

1. Read `AGENTS.md`.
2. Read `docs/README.md` and `docs/repo-map.md` if they exist.
3. Read any existing project document under `docs/projects/` when the request is project-specific.
4. Inventory relevant scripts with `rg --files`, then inspect the scripts that actually read/write the data or outputs being documented.
5. Search relevant scripts for path usage, stage names, CLI arguments, reads, writes, and model output names. In this repository, useful search terms include `read`, `write`, `scan_`, `readRDS`, `saveRDS`, `ggsave`, `argparse`, `--stage`, `OUTPUT`, `INPUT`, `PATH`, `data/`, and `outputs/`.

Do not infer script roles from filenames alone. If a role cannot be verified from code or existing docs, say that it is unknown or likely, and describe what evidence is missing.

## Documentation Locations

Use these locations unless the user requests otherwise:

- Repository orientation: `docs/README.md`, `docs/repo-map.md`.
- Project-level documentation: `docs/projects/`.
- Data layout: `data/README.md`.
- Output layout: `outputs/README.md`.
- Data collection and processing scripts: `scripts/data_collection/README.md`.
- Focused workflow docs: `docs/<workflow-name>.md`.

For project-level work, create or update one markdown file per project under `docs/projects/` and ensure `docs/projects/README.md` links to it.

## What To Document

For repository-level docs, include:

- Current top-level folder roles.
- Canonical raw, external, processed, and output paths.
- Active versus legacy script locations.
- Pipeline run order.
- Known path migrations or compatibility notes.
- Commands or script entry points needed for reproduction.

For project-level docs, include:

- Project status and research purpose.
- Unit of analysis and scope.
- Upstream scripts and how they feed the project.
- Project-specific analysis or data construction scripts.
- Key data inputs and generated outputs.
- Recommended run order.
- Manual review gates, assumptions, and exclusion rules.
- Validation checks and unresolved cleanup tasks.

Use `references/project-doc-template.md` when creating a new project document or when a project doc needs a consistent structure.

## Repository-Specific Conventions

Use the repository's canonical paths:

- `data/raw/` for raw source data.
- `data/external/` for hand-curated or externally maintained support data.
- `data/processed/` for generated analysis-ready datasets.
- `outputs/` for generated figures, logs, models, results, and tables.
- `scripts/data_collection/` for active data collection and source processing.
- `scripts/aggregate/` for panel/model-input construction.
- `scripts/analysis/` for modeling, tables, and figures.

When scripts still use legacy or machine-specific paths, document that clearly and recommend a cleanup step rather than pretending they already follow the canonical layout.

## Editing Rules

- Prefer markdown tables for script/data/output inventories.
- Use relative repository paths in documentation.
- Keep documentation extensive enough for replication, but avoid duplicating large code blocks.
- Update indexes and cross-links when adding a new document.
- Do not move scripts or data as part of a documentation request unless the user explicitly asks for reorganization.
- Preserve existing documentation that records migration history or manual review decisions; add clarifications instead of overwriting provenance.

## Final Check

Before finishing:

1. Verify every new markdown file is linked from the relevant index.
2. Check that every documented script has a specific role, inputs, outputs, and run position when known.
3. Check that every documented data artifact says whether it is raw, external, processed, or generated output.
4. Report any docs that still depend on unverified assumptions.

