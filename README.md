## Corporate Campaign Contribution

This project traces the motivations for corporations in engaging campaign contributions as a non-market strategy, adding to the existing investment versus consumption debate. It proposes a new framework for understanding corporate political donations and offers new ways to empirically test the effects of these strategies in the financial market.

This is a research data pipeline, not an application: Python/R scripts pull and process FEC, LSEG (market), and election-ratings data into analysis panels, and R scripts fit and interpret models on top of those panels. See `CLAUDE.md` and `AGENTS.md` for the fuller guide (commands, conventions, staged pipelines); this file is a quick orientation.

### Repository split (2026-08)

This repository (the scripts/docs/config side) is split from the data. `data/` and `outputs/`
(~155GB) live in a separate folder — e.g. a Dropbox folder — not under this repo. Every script
requires the `CAMPAIGNFINANCE_DATA_ROOT` environment variable to point at that folder (which
contains `data/` and `outputs/` as immediate children) before it will run:

```powershell
$env:CAMPAIGNFINANCE_DATA_ROOT = "C:\Users\<you>\Dropbox\campaign-finance-data"
```

`.venv/` (the Python environment) and `config/` (LSEG credentials) stay with the scripts, not the
data. `git` is not yet initialized in this folder — that's a deliberate later step.

### Data (in the separate data-root folder)

- `data/raw/` — downloaded/scraped source files (FEC bulk data, FEC API pulls, Inside Elections XML, LSEG pulls, DIME/Bonica data). Never hand-edited.
- `data/external/` — hand-curated or externally maintained inputs (industry classifications, congressional scandal/committee workbooks). Fixed inputs, not script-generated.
- `data/processed/` — stable, script-generated analysis inputs (e.g. `data/processed/fec/firm_pac_to_principal_committee_contributions.parquet`). Safe to regenerate.
- `outputs/` — final artifacts: `outputs/figures/`, `outputs/tables/`, `outputs/models/{all,election}/`, `outputs/results/`, `outputs/logs/`.

### Scripts (this repository)

- `scripts/data_collection/fec/` — FEC API scraping and bulk processing. Key scripts: `FECscraper.py` (API pulls), `FECprocessor.py` (processed contribution/PAC/committee tables), `FECtidy.py`/`reformat.py` (bulk file tidying), `FECindividualToFirmPACs.py`, `FECsuperOrganizationFirmMatcher.py`, `FECfirmPacDonorProfiles.py`, `FECBonica*.py` (DIME/Bonica crosswalk track), plus `PartisanHedgingIndex.py`, `HouseRaceCompetitiveness.py`, `ContributionSpikeDetection.py` (extracted from legacy notebooks in 2026-08).
- `scripts/data_collection/lseg/` — LSEG firm metadata and market data: `LSEGfirms.py`, `Stockscraper.py`, `EventStudy.py`, `ExposureStudy.py`/`BetaOneExposure.py`.
- `scripts/data_collection/electionratings/inside_elections/` — Inside Elections ratings parsers.
- `scripts/aggregate/` — builds analysis panels: `HouseData.py` (Python, House candidate/race panels), `HouseCandData.R` (R model-input datasets from those panels), `TaintedAccessPanels.py`.
- `scripts/analysis/` — R modeling (`logit/`, `tobit/` hold the completed firm-heterogeneity-in-House-contributions project; `archive/` holds superseded scripts).
- `scripts/FEC/`, `scripts/LSEG/`, `scripts/electionratings/` — exploratory/legacy, mostly superseded by `scripts/data_collection/`. `scripts/_archive/` holds what was reviewed and archived/extracted during the 2026-08 split — see `scripts/_archive/README.md`.

See `docs/repo-map.md` for the authoritative current structure and pipeline order.
