# Individual-Level Contribution Behavior

## Status

This project is ongoing and is still in the data construction and validation phase. It studies individual-level campaign contribution behavior around corporate PACs: who gives to firm PACs, whether those contributors appear to be employees or affiliates of the sponsoring firm, and how their outside political giving compares to their own-firm PAC giving.

The project currently uses active FEC scripts under `scripts/data_collection/fec/` and raw DIME/Bonica files under `data/raw/dime/`. The most important active documentation for the staged firm-PAC donor profile pipeline is also available at `docs/firm-pac-donor-profile-pipeline.md`.

## Research Scope

The project currently has two related data-building tracks:

- FEC bulk individual contributions to firm PACs: filter raw FEC individual contribution files to corporate PAC recipients, then identify likely firm-affiliated contributors and their outside giving.
- DIME/Bonica individual contributions: use Bonica recipient IDs to crosswalk DIME committee records to FEC corporate PAC committee IDs, then review contributor employer strings for likely sponsor-firm affiliation.

The immediate research products are not final models. They are auditable person-firm-cycle datasets, employer/PAC alias review files, and linked outside-giving records.

## Core Scripts

| Script | Role |
| --- | --- |
| `scripts/data_collection/fec/FECindividualToFirmPACs.py` | Filters raw FEC individual contribution parquet files to rows where `CMTE_ID` is a known corporate PAC committee. Writes cycle-level outputs and employer-occupation summaries under `data/processed/fec/individual_to_firm_pac_contributions/`. |
| `scripts/data_collection/fec/FECfirmPacDonorProfiles.py` | Main staged pipeline for firm-PAC donor profiles. Extracts employer-PAC review rows, builds approved employer aliases, searches raw FEC individual files, resolves person-firm-cycle identities, and links outside giving. |
| `scripts/data_collection/fec/FECBonica.py` | Legacy/helper script for converting DIME contribution CSV files into selected parquet columns. It currently has hard-coded `E:/` input/output paths and should be path-migrated before reuse. |
| `scripts/data_collection/fec/FECBonicaCorporatePacCrosswalk.py` | Builds and aggregates a DIME `bonica.rid` to FEC corporate PAC committee crosswalk using normalized committee names and the processed corporate PAC match universe. |
| `scripts/data_collection/fec/FECBonicaEmployerPacReview.py` | Builds DIME employer-to-corporate-PAC review rows, deterministically auto-matches obvious employer/connected-organization names, and generates markdown prompt chunks for unmatched review. |
| `scripts/data_collection/fec/FECprocessor.py` | Upstream dependency for `data/processed/fec/corporate_pac_firm_matches.csv`, the firm PAC universe used by both the FEC and DIME tracks. |

## FEC Track Workflow

1. Build or verify the corporate PAC match table at `data/processed/fec/corporate_pac_firm_matches.csv`.
2. Run `FECindividualToFirmPACs.py` to retain individual contributions received by firm PAC committees.
3. Run `FECfirmPacDonorProfiles.py --stage extract-employer-pac-review` to create employer/PAC triads and manual review rows.
4. Manually fill `manual_status`, `manual_firm_alias`, and `manual_notes` in `data/processed/fec/firm_pac_donor_profiles/employer_pac_alias_review.csv`.
5. Run `FECfirmPacDonorProfiles.py --stage build-approved-aliases` to create approved firm aliases.
6. Run `FECfirmPacDonorProfiles.py --stage search-raw-employees` to search raw FEC individual files for those approved employer aliases.
7. Run `FECfirmPacDonorProfiles.py --stage resolve-identities` to assign person-firm-cycle IDs.
8. Run `FECfirmPacDonorProfiles.py --stage link-outside-giving` to classify own-firm PAC donors and outside contributions.

Example command pattern:

```powershell
.\.venv\Scripts\python.exe scripts\data_collection\fec\FECindividualToFirmPACs.py --stage all --start-year 2004 --end-year 2024 --overwrite
.\.venv\Scripts\python.exe scripts\data_collection\fec\FECfirmPacDonorProfiles.py --stage extract-employer-pac-review --cycles 2004 --overwrite
.\.venv\Scripts\python.exe scripts\data_collection\fec\FECfirmPacDonorProfiles.py --stage build-approved-aliases --overwrite
.\.venv\Scripts\python.exe scripts\data_collection\fec\FECfirmPacDonorProfiles.py --stage search-raw-employees --cycles 2004 --overwrite
.\.venv\Scripts\python.exe scripts\data_collection\fec\FECfirmPacDonorProfiles.py --stage resolve-identities --cycles 2004 --overwrite
.\.venv\Scripts\python.exe scripts\data_collection\fec\FECfirmPacDonorProfiles.py --stage link-outside-giving --cycles 2004 --overwrite
```

## DIME/Bonica Track Workflow

1. Convert raw DIME contribution CSVs to `data/raw/dime/individual_contribution_<cycle>.parquet`. `FECBonica.py` is the current helper, but it needs path cleanup before production use.
2. Run `FECBonicaCorporatePacCrosswalk.py` to build or aggregate `bonica_rid_corporate_pac_crosswalk*.csv` files.
3. Review and correct special corporate PAC matching cases noted in `FECBonicaCorporatePacCrosswalk.py`, such as duplicate/acquired PACs and inactive committees.
4. Run `FECBonicaEmployerPacReview.py --stage build-review` to aggregate contributor-employer strings linked to corporate PAC `bonica.rid` values.
5. Run `FECBonicaEmployerPacReview.py --stage auto-match` to split obvious connected-organization matches from unmatched rows.
6. Manually review `data/raw/dime/dime_employer_bonica_pac_unmatched.csv` and prompt chunks under `data/raw/dime/dime_employer_bonica_pac_prompts/`.

## Key Data Inputs

| Data path | Role |
| --- | --- |
| `data/raw/fec_bulk/contributions/individual/` | Raw FEC individual contribution parquet files, either one file per cycle or split by cycle folder. |
| `data/processed/fec/corporate_pac_firm_matches.csv` | Corporate PAC committee to firm match universe. |
| `data/processed/fec/individual_to_firm_pac_contributions/` | FEC individual contributions received by firm PACs; produced by `FECindividualToFirmPACs.py`. |
| `data/raw/dime/individual_contribution_<cycle>.parquet` | DIME individual contribution files used in the Bonica track. |
| `data/raw/dime/bonica_rid_corporate_pac_crosswalk_aggregated.csv` | Aggregated DIME `bonica.rid` to FEC `CMTE_ID` crosswalk. |
| `data/raw/fec_bulk/cpac/corporate_pacs_list.csv` | Corporate PAC metadata used for DIME crosswalk and employer review. |

## Generated Outputs

| Output path | Contents |
| --- | --- |
| `data/processed/fec/individual_to_firm_pac_contributions/cycle_<year>/individual_<year>.parquet` | FEC individual contributions to firm PAC recipients by cycle. |
| `data/processed/fec/individual_to_firm_pac_contributions/_manifest.csv` | Source coverage and matched row counts from FEC filtering. |
| `data/processed/fec/individual_to_firm_pac_contributions/employer_occupation_pairs.csv` | Employer/occupation summary across retained firm PAC contributions. |
| `data/processed/fec/firm_pac_donor_profiles/employer_pac_alias_review.csv` | Manual review file for observed employer-PAC-firm alias candidates. |
| `data/processed/fec/firm_pac_donor_profiles/approved_employer_pac_firm_aliases.*` | Approved aliases after manual review. |
| `data/processed/fec/firm_pac_donor_profiles/raw_firm_employee_contributions/` | Raw FEC individual rows matching approved employer aliases. |
| `data/processed/fec/firm_pac_donor_profiles/person_firm_cycle_index/` | Person-firm-cycle identity index. |
| `data/processed/fec/firm_pac_donor_profiles/linked_outside_giving/` | Own-firm PAC donor and outside-giving classification outputs. |
| `data/raw/dime/dime_employer_bonica_pac_review.csv` | DIME employer/PAC review rows. |
| `data/raw/dime/dime_employer_bonica_pac_auto_matched.csv` | Deterministic DIME employer/PAC matches. |
| `data/raw/dime/dime_employer_bonica_pac_unmatched.csv` | DIME employer/PAC rows requiring manual or prompt-based review. |

## Review Rules

For the FEC staged pipeline, accepted `manual_status` values are:

- `own_firm`
- `subsidiary_or_affiliate`

Rejected or review-status values are:

- `retiree_or_former_employee`
- `not_own_firm`
- `unclear`
- `invalid_placeholder`

Rows marked as retirees, family-like records, generic self-employment, or board-only records should not be silently mixed into the main employee-affiliation sample.

## Open Work

- Decide whether the FEC and DIME tracks are alternative measures, validation checks, or complementary datasets for the final project.
- Path-migrate `FECBonica.py` away from hard-coded `E:/` paths.
- Add a final aggregation step that summarizes outside giving by person-firm-cycle and separates own-firm PAC giving from other committee/candidate giving.
- Define analysis-ready outcomes: total outside giving, outside partisan direction, PAC donor status, employee-affiliation confidence, and contribution timing relative to PAC giving.
- Add a small validation report for each cycle: raw files scanned, employer aliases used, matched people, excluded-profile share, ambiguous-alias share, and outside-giving rows linked.

