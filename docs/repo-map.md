# Repository Map

This map reflects the repository after the first reorganization pass. The active data collection and processing scripts were separated from exploratory analysis files, and canonical data now lives under `data/raw`, `data/external`, and `data/processed`.

**2026-08 update:** `data/` and `outputs/` described below now live in a *separate* folder (e.g.
a Dropbox folder) from this scripts repository, not physically under it. The internal layout
described in this document (subpaths, file roles) is unchanged -- only the location of the root
changed. Every path below should be read as relative to `$CAMPAIGNFINANCE_DATA_ROOT`, not this
repo's root. See the repository-split note in `README.md`/`CLAUDE.md`/`AGENTS.md` for the env var
requirement.

For old-to-new path mappings and rollback notes, see [`migration-log.md`](migration-log.md).

## Top-Level Layout

| Path | Role |
| --- | --- |
| `README.md` | Original project overview. Some paths may predate the reorganization. |
| `config/` | Configuration files, currently including LSEG configuration. |
| `data/` | Canonical data root. New code should use `data/raw`, `data/external`, and `data/processed`. |
| `docs/` | Repository documentation and migration notes. |
| `docs/projects/` | Project-level documentation. Each project file maps research scope to the scripts, data, outputs, and cleanup tasks that belong to it. |
| `outputs/` | Generated artifacts: figures, logs, models, results, and tables. |
| `scripts/` | Data pipeline scripts, aggregation scripts, analysis scripts, notebooks, and legacy helpers. |
| `utils/` | Shared utility location reserved for future factoring. |
| `.venv/`, `.ruff_cache/`, `.vscode/` | Local environment/editor/cache directories. |
| `.DS_Store`, `._.DS_Store` | macOS metadata files. Not part of the research workflow. |

## Data Layout

| Path | Role |
| --- | --- |
| `data/README.md` | Data layout summary. |
| `data/raw/fec_api/` | FEC API pulls. Contains `candidates/`, `committees/`, `contributions/`, and `expenditures/`. |
| `data/raw/fec_api/candidates/H/`, `data/raw/fec_api/candidates/S/` | Page-level FEC API candidate JSON files by chamber. |
| `data/raw/fec_bulk/` | FEC bulk-download files and raw/hand-match corporate PAC materials. |
| `data/raw/fec_bulk/candidates/` | FEC candidate master files and parquet conversions. |
| `data/raw/fec_bulk/campaigns/` | FEC campaign files and parquet conversions. |
| `data/raw/fec_bulk/committees/` | FEC committee and PAC bulk files, plus corporate committee extracts. |
| `data/raw/fec_bulk/contributions/` | Bulk contribution files, including `committees/` and `individual/` subtrees. |
| `data/raw/fec_bulk/cpac/` | Corporate PAC matching and hand-coding files. |
| `data/raw/fec_bulk/expenditures/` | FEC expenditure files. |
| `data/raw/fec_bulk/firms/` | Raw public/private/all firm lists used by older FEC matching workflows. |
| `data/raw/fec_bulk/hedging/` | Hedging outputs from older FEC workflows. |
| `data/raw/fec_bulk/stocks/` | Raw stock universe inputs. |
| `data/raw/fec_bulk/summary/` | Summary CSVs from older FEC workflows. |
| `data/raw/lseg/` | LSEG firm metadata and raw market returns. |
| `data/raw/lseg/returns/` | Per-ticker return files used by LSEG market scripts. |
| `data/raw/electionratings/IE/` | Inside Elections XML, directory files, and parsed ratings. |
| `data/external/other/` | Hand-curated or external support inputs that do not yet have a domain-specific folder, including industry classifications and general-candidate files. |
| `data/external/congress/scandals/congressional_scandals_1979_2018.csv` | External congressional scandal event source. Identifies scandal actor, timing, salience, criminal flag, political outcome, type, and notes. |
| `data/external/congress/committee_assignments/house_members_103_115.xlsx` | External House member workbook for Congresses 103-115. Used for member/congress covariates and committee-assignment joins. |
| `data/external/congress/committee_assignments/house_committee_assignments_103_115.xls` | External House committee assignment workbook for Congresses 103-115. Used to attach committee positions and institutional covariates. |
| `data/external/congress/committee_assignments/house_members_103_115_sheet*.csv` | CSV sidecars converted from the House member workbook. Prefer these files for parser development; keep the original workbook as source provenance. |
| `data/external/congress/committee_assignments/house_committee_assignments_103_115.csv` | CSV sidecar converted from the House committee assignment workbook. Prefer this file for parser development; keep the original workbook as source provenance. |
| `data/processed/fec/` | Processed FEC tables used by aggregation. Contribution filenames now make direction explicit. |
| `data/processed/fec/committee_to_candidate_contributions.parquet` | Bulk committee/PAC contributions to candidate committees. |
| `data/processed/fec/committee_to_committee_contributions.parquet` | Bulk committee/PAC contributions to other committees. |
| `data/processed/fec/firm_pac_to_candidate_contributions.parquet` | Firm-PAC-enriched contributions to candidates. |
| `data/processed/fec/firm_pac_to_committee_contributions.parquet` | Firm-PAC-enriched contributions to committees. |
| `data/processed/fec/firm_pac_to_principal_committee_contributions.parquet` | Firm PAC contributions matched to candidate principal committees. Main input to House aggregation. |
| `data/processed/fec/firm_pac_to_leadership_pac_contributions.parquet` | Firm PAC contributions to leadership PACs. |
| `data/processed/fec/firm_pac_cycle_panel.parquet` | Firm PAC cycle-level panel with firm metadata and cycle aggregates. |
| `data/processed/fec/corporate_pac_firm_matches.csv` | Corporate PAC to firm matching table. |
| `data/processed/fec/house_candidate_principal_committees.csv` | House candidate principal committee lookup. |
| `data/processed/fec/senate_candidate_principal_committees.csv` | Senate candidate principal committee lookup. |
| `data/processed/fec/leadership_pac_committees.csv` | Leadership PAC committee lookup. |
| `data/processed/fec/fec_firm_universe.csv` | Firm universe retained in processed FEC for reference. It duplicates the LSEG firm universe for convenience. |
| `data/processed/fec/archive/` | Archived processed FEC snapshots, currently including the dated corporate PAC firm-match snapshot. |
| `data/processed/house/` | Generated House-level analysis panels and contribution summaries. |
| `data/processed/congress/` | Recommended generated location for normalized congressional scandal events, member terms, and committee assignment tables derived from `data/external/congress/`. |
| `data/processed/market/` | Market/event-study metadata and outputs, including sector maps, event abnormal returns, event tilts, public/private firm files, and processing markers. |
| `data/processed/modeling/` | Generated model-input datasets such as `cand_model_data.RDS` and `cand_model_data_election_year.RDS`. |
| `data/FEC/`, `data/market/`, `data/electionratings/` | Legacy compatibility shells left in place after migration. Treat the paths above as canonical. |

## Outputs Layout

| Path | Role |
| --- | --- |
| `outputs/README.md` | Output layout summary. |
| `outputs/figures/` | Figure outputs formerly under `figs/`. |
| `outputs/logs/` | Logs formerly under `logs/`. |
| `outputs/models/` | Saved model objects formerly under `models/`. |
| `outputs/models/all/` | All-cycle saved model objects. |
| `outputs/models/election/` | Election-year saved model objects. |
| `outputs/results/` | Saved result objects formerly under `results/`. |
| `outputs/tables/` | LaTeX table outputs formerly under `tables/`. |

## Scripts Layout

| Path | Role |
| --- | --- |
| `scripts/data_collection/README.md` | Entry point for active data collection and processing scripts. |
| `scripts/data_collection/fec/` | Active FEC data collection and processing scripts. |
| `scripts/data_collection/fec/fec_client.py` | Shared `FECClient` base class (HTTP retry, list-endpoint pagination, upsert-by-key CSV merge). Not a standalone script; every script below imports it. |
| `scripts/data_collection/fec/candidates/` | FEC API candidate scripts, one standalone script per datapoint. `candidates_list.py` (current-state list, no history), `candidate_history.py` and `candidate_committees.py` (per-cycle history, upsert by natural key; `--refresh all` re-checks every known candidate, not just new ones -- for catch-up runs or rare retroactive corrections). Write to `data/raw/fec_api/candidates/`. |
| `scripts/data_collection/fec/committees/` | FEC API committee scripts. `leadership_pacs.py`, `joint_committees.py`, `hybrid_pacs.py`, `super_pacs.py`, `corporate_pacs.py` (one script per committee type/designation, full list refresh each run -- current-state-only endpoints, so this is cheap; `corporate_pacs.py` replaces `FECtidy.py`'s bulk committee-master dependency). `leadership_history.py` (per-cycle history, same upsert/`--refresh` pattern as candidate_history.py). `committee_active_period.py` (fills active_start_year/active_end_year onto a committee list file). Write to `data/raw/fec_api/committees/`. |
| `scripts/data_collection/fec/contributions/` | FEC API contribution/expenditure scripts. `{hybrid_pac,super_pac,leadership_pac,corporate_pac}_contributions.py` (Schedule A donor-side receipts, sharing `schedule_a_core.py`) and `{hybrid_pac,super_pac}_expenditures.py` (Schedule E independent expenditures, sharing `schedule_e_core.py`). **Known gap:** both still skip a committee entirely once it has any records on file -- not yet converted to a real incremental (min_date-checkpoint) refresh. Write to `data/raw/fec_api/contributions/` and `data/raw/fec_api/expenditures/`. |
| `scripts/data_collection/fec/FECprocessor.py` | Builds processed FEC contribution, PAC, committee, and contributor files. Reads `data/raw/fec_bulk/`, `data/raw/fec_api/`, and `data/raw/lseg/`; writes `data/processed/fec/`. |
| `scripts/data_collection/fec/FECtidy.py` | Tidies FEC bulk files and corporate PAC extracts under `data/raw/fec_bulk/`. |
| `scripts/data_collection/fec/reformat.py` | Utility to convert pipe-delimited FEC text files to parquet under `data/raw/fec_bulk/`. |
| `scripts/data_collection/fec/FECindividualToFirmPACs.py` | Filters FEC individual contribution bulk files to contributions received by firm PACs. Writes partitioned parquet under `data/processed/fec/individual_to_firm_pac_contributions/`. |
| `scripts/data_collection/fec/FECsuperOrganizationFirmMatcher.py` | Conservatively matches `data/raw/fec_api/contributions/super_organization_contributors.csv` to `data/processed/fec/fec_firm_universe.csv`; can run a resumable `lseg-search` stage from a saved first-pass output, checkpoint organisation `PI` matches, and add equity RIC/PermID for public-company hits; can merge prebuilt LSEG crosswalk and firm-info files into the final matched output. |
| `scripts/data_collection/fec/utils.py` | FEC helper functions used by legacy and active scripts. |
| `scripts/data_collection/fec/data_fields.json` | Field definitions used by FEC reformatting. |
| `scripts/data_collection/lseg/` | Active LSEG firm and market-data scripts. |
| `scripts/data_collection/lseg/LSEGfirms.py` | Builds/updates LSEG firm metadata in `data/raw/lseg/`. |
| `scripts/data_collection/lseg/Stockscraper.py` | Pulls per-ticker returns into `data/raw/lseg/returns/` and market metadata into `data/processed/market/`. |
| `scripts/data_collection/lseg/EventStudy.py` | Main event-study script. Reads returns from `data/raw/lseg/returns/` and writes outputs under `data/processed/market/`. |
| `scripts/data_collection/lseg/ExposureStudy.py` | Alternate market exposure/event-study script. |
| `scripts/data_collection/lseg/BetaOneExposure.py` | Alternate event exposure script with SPY/equal-weighted market options. |
| `scripts/data_collection/lseg/LSEGfirmInfoFromPermIDs.py` | Pulls firm metadata for resolved LSEG identifiers produced by `FECsuperOrganizationFirmMatcher.py --stage lseg-search`; private-company hits use organisation `PI`, public-company hits use equity-search PermID; writes `data/processed/fec/super_organization_lseg_firm_info.csv` with firm-universe-style columns. |
| `scripts/data_collection/lseg/data_fields.json` | Field definitions used by LSEG firm metadata scripts. |
| `scripts/data_collection/electionratings/inside_elections/` | Inside Elections parsers. |
| `scripts/data_collection/electionratings/inside_elections/directory.py` | Parses `directory.xml` to `directory.csv`. |
| `scripts/data_collection/electionratings/inside_elections/house_records.py` | Parses House ratings XML files to `house_ratings.csv`. |
| `scripts/aggregate/` | Data aggregation and R model-input preparation. |
| `scripts/aggregate/HouseData.py` | Builds House candidate-level contribution panels. Reads processed FEC, FEC API candidate history, election ratings, and external candidate inputs; writes `data/processed/house/`. |
| `scripts/aggregate/HouseCandData.R` | Builds R model-input data from `data/processed/house/` and `data/external/other/`; writes `data/processed/modeling/`. |
| `scripts/aggregate/utils.py` | Helpers used by aggregation scripts. |
| `scripts/analysis/` | Analysis/modeling scripts. These were not the focus of the first reorganization pass and may still need path updates before running. |
| `scripts/analysis/logit/` and `scripts/analysis/tobit/` | Current homes for the completed firm heterogeneity in House contribution behavior project. Suggested future home: `scripts/analysis/firm_heterogeneity_house/` with `logit/`, `tobit/`, and output-helper subfolders after R path cleanup. |
| `scripts/notebooks/` | General exploratory notebooks. |
| `scripts/FEC/` | Legacy/exploratory FEC notebooks and helper scripts left in place for reference. Active FEC scripts moved to `scripts/data_collection/fec/`. |
| `scripts/LSEG/` | Legacy/exploratory LSEG notebook location. Active LSEG scripts moved to `scripts/data_collection/lseg/`. |
| `scripts/electionratings/` | Legacy container left after moving active parsers to `scripts/data_collection/electionratings/`. |

## Active Data Pipeline

The current canonical data pipeline is:

1. Pull or refresh FEC API data with the scripts under `scripts/data_collection/fec/candidates/`, `fec/committees/`, and `fec/contributions/`.
2. Reformat/tidy FEC bulk data with `scripts/data_collection/fec/FECtidy.py` and `scripts/data_collection/fec/reformat.py`.
3. Build processed FEC tables with selected functions in `scripts/data_collection/fec/FECprocessor.py`.
4. Optionally build individual-to-firm-PAC contribution data with `scripts/data_collection/fec/FECindividualToFirmPACs.py`.
5. Optionally match super-PAC organization contributors with `scripts/data_collection/fec/FECsuperOrganizationFirmMatcher.py`; for the staged LSEG pass, run its `lseg-search` stage, then fetch firm metadata with `scripts/data_collection/lseg/LSEGfirmInfoFromPermIDs.py`, then rerun the matcher with `--use-lseg-files`.
6. Maintain LSEG firm metadata with `scripts/data_collection/lseg/LSEGfirms.py`.
7. Pull market returns with `scripts/data_collection/lseg/Stockscraper.py`.
8. Run market/event exposure scripts with `scripts/data_collection/lseg/EventStudy.py` or the alternate LSEG exposure scripts.
9. Refresh Inside Elections ratings with `scripts/data_collection/electionratings/inside_elections/*.py` if source ratings changed.
10. Build House candidate analysis panels with `scripts/aggregate/HouseData.py`.
11. Build R model-input datasets with `scripts/aggregate/HouseCandData.R`.

Analysis scripts, model estimation, figures, tables, and paper outputs are intentionally lower priority in this map.

## Compatibility Notes

| Compatibility issue | Current handling |
| --- | --- |
| Old notebooks may reference `../data/...`, `data/FEC/...`, `data/market/...`, or top-level `figs/`, `models/`, `tables/`, `results/`, `logs/`. | Use `docs/migration-log.md` to translate those paths to the new layout before running older notebooks. |
| Empty or near-empty legacy containers remain under `data/FEC/`, `data/market/`, `data/electionratings/`, `scripts/FEC/`, `scripts/LSEG/`, and `scripts/electionratings/`. | These are retained for orientation and to avoid destructive cleanup. New code should not target them unless maintaining legacy workflows. |
| Some `__pycache__/` folders remain under legacy script areas and aggregation. | They are generated Python caches and not part of the workflow. |
| R tooling was not available in the shell during the migration. | Python active scripts were syntax-checked; `HouseCandData.R` should be parse-checked in an R-enabled environment before the next production run. |
