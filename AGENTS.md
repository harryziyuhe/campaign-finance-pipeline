# Repository Guidelines

## Repository split (2026-08)

This is the scripts/code side of a two-location split -- `data/` and `outputs/` (~155GB) now live
in a separate folder (e.g. a Dropbox folder), not under this repo. Every script requires the
`CAMPAIGNFINANCE_DATA_ROOT` environment variable to be set to that folder's path (it contains
`data/` and `outputs/` as immediate children) before it will run; scripts raise a clear error if
it's unset rather than silently resolving a wrong path. `.venv/` and `config/` still live here,
with the scripts, not the data.

FEC API scripts also require a `FEC_API_KEY` environment variable (get one at
https://api.data.gov/signup/) -- no hardcoded key is checked in.

## Project Structure & Module Organization

This repository supports a corporate campaign contribution research pipeline. Active code lives under `scripts/`: `scripts/data_collection/fec/` handles FEC API and bulk processing, `scripts/data_collection/lseg/` handles LSEG firm and market data, `scripts/data_collection/electionratings/inside_elections/` parses Inside Elections ratings, `scripts/aggregate/` builds analysis panels, and `scripts/analysis/` contains R modeling scripts. Legacy notebooks live under `scripts/FEC/` and `scripts/LSEG/`; `scripts/_archive/` holds what was reviewed and found fully superseded or scratch during the 2026-08 split (see `scripts/_archive/README.md`).

Canonical data paths are `data/raw/`, `data/external/`, and `data/processed/`. Generated figures, models, logs, tables, and results belong in `outputs/`. Both are resolved via `CAMPAIGNFINANCE_DATA_ROOT`, not a path relative to this repo. Use `docs/repo-map.md` and `docs/migration-log.md` when translating older paths.

## Build, Test, and Development Commands

There is no central build system. Run scripts directly from the repository root so relative data paths resolve correctly, and make sure `CAMPAIGNFINANCE_DATA_ROOT` is set first (see above).

- One-time environment setup: `pip install -r requirements.txt` (Python deps) and `Rscript scripts/setup_r_packages.R` (R deps).
- `python -m py_compile scripts/data_collection/fec/FECindividualToFirmPACs.py`: syntax-check a Python script before running it.
- `python scripts/data_collection/fec/committees/corporate_pacs.py`: example of the one-script-per-datapoint FEC API scrapers under `fec/{candidates,committees,contributions}/` (see `scripts/data_collection/README.md` for the full list); all need `FEC_API_KEY` set.
- `python scripts/aggregate/HouseData.py`: rebuild House-level processed panels.
- `Rscript scripts/aggregate/HouseCandData.R`: rebuild R model-input datasets.
- `Rscript scripts/analysis/logit/partisan_model2.R`: run the current candidate-level model code after inputs are current (`scripts/analysis/archive/cand_model.R` is the superseded predecessor, kept for history only).

## Coding Style & Naming Conventions

Use Python 3 with 4-space indentation, `snake_case` functions and variables, and descriptive script names. Prefer `pathlib` or project-root-relative paths over hard-coded local drive paths. Keep data outputs named by source, unit, and cycle when relevant, such as `firm_pac_to_candidate_contributions.parquet` or `house_contribution_2024.csv`. R scripts should use clear object names and keep generated `.RDS` outputs under `data/processed/modeling/` or `outputs/models/`.

## Testing Guidelines

No formal test suite is present. For Python changes, at minimum run `python -m py_compile` on modified scripts and, when feasible, run the smallest pipeline stage that exercises the change. For R changes, use `Rscript` to parse or execute the touched script in an R-enabled environment. Validate that regenerated files land in the expected `data/processed/` or `outputs/` subdirectory.

## Commit & Pull Request Guidelines

This checkout does not include Git history, so no repository-specific commit convention can be inferred. Use concise, imperative commit subjects such as `Update FEC processing paths` or `Add House panel validation`. Pull requests should describe the data or script paths touched, list commands run, note any regenerated large artifacts, and link the related issue or research task when available.

## Data & Configuration Notes

Do not commit local environment folders, caches, credentials, or editor files (see `.gitignore`).
Keep LSEG-related settings in `config/lseg-data.config.json` (gitignored; `config/lseg-data.config.json.example` documents the expected shape with placeholder values) and avoid embedding API keys or machine-specific paths in scripts.
