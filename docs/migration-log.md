# Migration Log

This file records physical repository moves made during the staged reorganization. If a script breaks, use this file to map the old path to the new path and update the script path constants.

Migration date: 2026-05-01

## Rules Used

| Rule | Meaning |
| --- | --- |
| Source/API downloads | Move under `data/raw/`. |
| Hand-curated/external support files | Move under `data/external/`. |
| Generated analysis inputs | Move under `data/processed/`. |
| Final or paper-facing artifacts | Move under `outputs/`. |
| Active collection/processing scripts | Move under lowercase domain folders in `scripts/`. |
| Exploratory notebooks and older relative-path scripts | Leave in place for now unless explicitly migrated later. |

## Data Moves

| Old path | New path | Notes |
| --- | --- | --- |
| `data/FEC/API/` | `data/raw/fec_api/` | FEC API candidate, committee, expenditure, and contribution pulls. |
| `data/FEC/raw/` | `data/raw/fec_bulk/` | FEC bulk data and related raw corporate PAC matching files. |
| `data/FEC/processed/` | `data/processed/fec/` | Processed FEC contribution, PAC, and principal committee files. |
| `data/LSEG/` | `data/raw/lseg/` | LSEG firm metadata and firm universe files. |
| `data/electionratings/` | `data/raw/electionratings/` | Inside Elections raw XML and parsed ratings. |
| `data/other/` | `data/external/other/` | Hand-curated and external support files. |
| `data/market/returns/` | `data/raw/lseg/returns/` | Per-ticker return files used by LSEG market scripts. |
| Remaining `data/market/*` files | `data/processed/market/` | Market/event-study intermediate and processed outputs. |
| `data/house_*` files | `data/processed/house/` | House-level generated analysis panels and contribution summaries. |
| `data/cand_model_data*.RDS` | `data/processed/modeling/` | Generated R model input datasets. |

## Processed FEC File Renames

These renames were made after the first directory migration to make table direction and role explicit.

| Old path | New path | Notes |
| --- | --- | --- |
| `data/processed/fec/candidate_contributions.parquet` | `data/processed/fec/committee_to_candidate_contributions.parquet` | Bulk committee/PAC contributions to candidates. |
| `data/processed/fec/committee_contributions.parquet` | `data/processed/fec/committee_to_committee_contributions.parquet` | Bulk committee/PAC contributions to other committees. |
| `data/processed/fec/firm_candidate_contributions.parquet` | `data/processed/fec/firm_pac_to_candidate_contributions.parquet` | Firm-PAC-enriched contributions to candidates. |
| `data/processed/fec/firm_committee_contributions.parquet` | `data/processed/fec/firm_pac_to_committee_contributions.parquet` | Firm-PAC-enriched contributions to committees. |
| `data/processed/fec/firms_principal_committees_contributions.parquet` | `data/processed/fec/firm_pac_to_principal_committee_contributions.parquet` | Firm PAC contributions to candidate principal committees. |
| `data/processed/fec/firms_leadership_pacs_contributions.parquet` | `data/processed/fec/firm_pac_to_leadership_pac_contributions.parquet` | Firm PAC contributions to leadership PACs. |
| `data/processed/fec/firm_pacs.parquet` | `data/processed/fec/firm_pac_cycle_panel.parquet` | Firm PAC cycle-level panel used by House aggregation. |
| `data/processed/fec/corporate_pacs.csv` | `data/processed/fec/corporate_pac_firm_matches.csv` | Corporate PAC to firm matching table. |
| `data/processed/fec/corporate_pacs_250729.csv` | `data/processed/fec/archive/corporate_pac_firm_matches_2025-07-29.csv` | Archived dated snapshot. |
| `data/processed/fec/candidate_principal_committees_H.csv` | `data/processed/fec/house_candidate_principal_committees.csv` | House principal committee lookup. |
| `data/processed/fec/candidate_principal_committees_S.csv` | `data/processed/fec/senate_candidate_principal_committees.csv` | Senate principal committee lookup. |
| `data/processed/fec/leadership_committees.csv` | `data/processed/fec/leadership_pac_committees.csv` | Leadership PAC committee lookup. |
| `data/processed/fec/all_firms.csv` | `data/processed/fec/fec_firm_universe.csv` | Copy/reference firm universe retained in processed FEC for convenience. Canonical firm metadata also exists under `data/raw/lseg/`. |

## Output Moves

| Old path | New path | Notes |
| --- | --- | --- |
| `figs/` | `outputs/figures/` | Figure outputs. |
| `tables/` | `outputs/tables/` | LaTeX table outputs. |
| `models/` | `outputs/models/` | Saved model objects. |
| `results/` | `outputs/results/` | Saved result objects. |
| `logs/` | `outputs/logs/` | Logs and manual run notes. |

## Script Moves

| Old path | New path | Notes |
| --- | --- | --- |
| `scripts/FEC/FECscraper.py` | `scripts/data_collection/fec/FECscraper.py` | Active FEC API collection script. |
| `scripts/FEC/FECprocessor.py` | `scripts/data_collection/fec/FECprocessor.py` | Active FEC processing script. |
| `scripts/FEC/FECtidy.py` | `scripts/data_collection/fec/FECtidy.py` | Active FEC bulk tidying script. |
| `scripts/FEC/reformat.py` | `scripts/data_collection/fec/reformat.py` | FEC bulk reformat utility. |
| `scripts/FEC/utils.py` | `scripts/data_collection/fec/utils.py` | FEC helper module. |
| `scripts/FEC/data_fields.json` | `scripts/data_collection/fec/data_fields.json` | FEC bulk field definitions. |
| `scripts/LSEG/*.py` | `scripts/data_collection/lseg/*.py` | Active LSEG firm/market scripts. |
| `scripts/LSEG/data_fields.json` | `scripts/data_collection/lseg/data_fields.json` | LSEG/FEC field helper JSON retained with scripts. |
| `scripts/electionratings/IE/*.py` | `scripts/data_collection/electionratings/inside_elections/*.py` | Election ratings parsers. |

## Active Path Constants After Migration

| Script | New canonical data roots |
| --- | --- |
| `scripts/data_collection/fec/FECscraper.py` | `data/raw/fec_api/` |
| `scripts/data_collection/fec/FECprocessor.py` | `data/raw/fec_bulk/`, `data/raw/fec_api/`, `data/processed/fec/`, `data/raw/lseg/` |
| `scripts/data_collection/fec/FECtidy.py` | `data/raw/fec_bulk/` |
| `scripts/data_collection/fec/reformat.py` | `data/raw/fec_bulk/` |
| `scripts/data_collection/lseg/Stockscraper.py` | `data/raw/lseg/returns/`, `data/processed/market/public_firms.csv`, `data/processed/market/firm_sector.csv`, `data/processed/market/processed.txt` |
| `scripts/data_collection/lseg/EventStudy.py` | `data/raw/lseg/returns/` plus market metadata/outputs under `data/processed/market/` |
| `scripts/data_collection/lseg/ExposureStudy.py` | Same market layout as `EventStudy.py`. |
| `scripts/data_collection/lseg/BetaOneExposure.py` | Same market layout as `EventStudy.py`. |
| `scripts/data_collection/lseg/LSEGfirms.py` | `data/raw/lseg/` |
| `scripts/data_collection/electionratings/inside_elections/*.py` | `data/raw/electionratings/IE/` |
| `scripts/aggregate/HouseData.py` | `data/processed/fec/`, `data/raw/fec_api/`, `data/raw/electionratings/`, `data/external/other/`, `data/processed/house/` |
| `scripts/aggregate/HouseCandData.R` | `data/processed/house/`, `data/external/other/`, `data/processed/modeling/` |

## Compatibility Shells Left In Place

Windows blocked whole-directory renames for a few old container folders, so their contents were moved instead and the empty or near-empty containers were left in place:

| Old container | Current status |
| --- | --- |
| `data/FEC/` | Container remains; `API/` and `raw/` subfolders should be treated as old compatibility shells. Canonical contents are now under `data/raw/fec_api/` and `data/raw/fec_bulk/`. |
| `data/electionratings/` | Container remains empty; canonical contents are now under `data/raw/electionratings/`. |
| `data/market/` | Container remains empty; canonical contents are now split between `data/raw/lseg/returns/` and `data/processed/market/`. |

## Rollback Notes

To restore an old path, move the new path back to the old path listed above. For example, if a legacy notebook expects `data/FEC/processed`, use the mapping `data/processed/fec/ -> data/FEC/processed/`.

Do not delete new directories during rollback until you confirm that no updated active script depends on them.

## 2026-08 FEC API Scraper Restructuring

`scripts/data_collection/fec/FECscraper.py` (one monolithic `FECScraper` class covering
candidates, committees, and contributions) was split into one standalone script per
specific datapoint, sharing a `FECClient` base class for HTTP retry/pagination/upsert.
The old file was moved to `scripts/_archive/data_collection_fec/FECscraper.py` -- see
`scripts/_archive/README.md` for the full old-to-new mapping. No data paths changed;
every new script writes to the same `data/raw/fec_api/` locations the old methods did.

This restructuring also fixed a real gap: `fetch_candidate_history`,
`fetch_candidate_committees`, and `fetch_leadership_history` used to skip a
candidate/committee entirely once its ID had ever been seen, so a known entity's
history was frozen after its first pull (a new cycle filed against a long-tracked
candidate would never be picked up). The new `candidate_history.py`,
`candidate_committees.py`, and `leadership_history.py` upsert by natural key instead,
and support `--refresh all` to re-check every known entity, not just newly-appeared
ones -- use that for a one-time catch-up run and to catch rare retroactive corrections.

Schedule A (`contributions/*_contributions.py`) and Schedule E
(`contributions/*_expenditures.py`) still have the old "skip a committee entirely once
it has any records on file" limitation -- not fixed in this pass, called out in
`scripts/data_collection/README.md` as a known gap.
