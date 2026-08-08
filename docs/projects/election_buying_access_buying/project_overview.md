# Firm Heterogeneity In House Contribution Behavior

## Status

This is the completed House-election analysis project. It studies firm heterogeneity in corporate PAC contribution behavior, especially how contribution probability and contribution amount vary with race competitiveness, candidate party, incumbency, firm reputation exposure, public/private status, consumer-facing status, and several measures of partisan alignment.

For the paper's theory revision history, dead ends, and statistical traps already worked through, see [`theory_revision_handoff.md`](theory_revision_handoff.md) in this folder.

The analysis code currently lives under `scripts/analysis/logit/` and `scripts/analysis/tobit/`. A good future master folder for these scripts would be:

```text
scripts/analysis/firm_heterogeneity_house/
```

Suggested subfolders under that future master folder:

```text
scripts/analysis/firm_heterogeneity_house/logit/
scripts/analysis/firm_heterogeneity_house/tobit/
scripts/analysis/firm_heterogeneity_house/tables_figures/
scripts/analysis/firm_heterogeneity_house/archive/
```

Do not move the scripts until their hard-coded paths are cleaned up. Several R scripts still assume `PATH <- "~/campaigncontributions/"` and write to `model/`, `figs/`, or `tables/`, while the reorganized repository convention is `data/processed/` and `outputs/`.

## Research Scope

The unit of analysis is a firm-PAC by House candidate or race-year observation built from processed FEC, firm, market, and election-rating data. The project separates:

- Extensive margin: whether a firm PAC contributes to a House candidate.
- Intensive margin: how much the firm PAC contributes, conditional on contribution limits and observed contribution amounts.
- Heterogeneity: public/private firms, consumer-facing firms, partisan giving history, market-reaction partisanship, single-name donor partisanship, and industry/subsector partisan measures.

## Upstream Scripts

| Script | Role in this project |
| --- | --- |
| `scripts/data_collection/fec/candidates/` and `fec/committees/` | Refresh FEC API candidate and committee inputs used by downstream House aggregation (one standalone script per datapoint; see `scripts/data_collection/README.md`). |
| `scripts/data_collection/fec/FECtidy.py` and `scripts/data_collection/fec/reformat.py` | Prepare raw FEC bulk files and parquet conversions used by the processed FEC pipeline. |
| `scripts/data_collection/fec/FECprocessor.py` | Builds processed firm-PAC contribution tables, including firm PAC to candidate/principal-committee contributions. |
| `scripts/data_collection/lseg/LSEGfirms.py` | Maintains the firm universe and metadata used to classify and join PAC sponsors. |
| `scripts/data_collection/lseg/Stockscraper.py`, `EventStudy.py`, `ExposureStudy.py`, `BetaOneExposure.py` | Produce market/event-study inputs that feed market-reaction and partisan market measures. |
| `scripts/data_collection/electionratings/inside_elections/directory.py` and `house_records.py` | Parse Inside Elections House ratings used for race competitiveness/favorability measures. |
| `scripts/aggregate/HouseData.py` | Builds House candidate/race contribution panels under `data/processed/house/`. |
| `scripts/aggregate/HouseCandData.R` | Builds model-ready RDS files under `data/processed/modeling/`, including `cand_model_data.RDS` and `cand_model_data_election_year.RDS`. |

## Analysis Scripts

### Logit Models

| Script | Role |
| --- | --- |
| `scripts/analysis/logit/baseline_model.R` | Main extensive-margin logit model. Fits baseline, spline, consumer-facing subset, public/private subset, giving-pattern partisanship subset, ETF/market-reaction partisanship subset, and single-name partisanship subset models. |
| `scripts/analysis/logit/reputation_model.R` | Fits interaction models for public/private status and consumer-facing status against favorability, incumbency, and party. |
| `scripts/analysis/logit/partisan_model1.R` | Fits interaction models for firm giving-pattern partisanship and ETF/market-reaction partisanship, including categorical and continuous pre-period measures. |
| `scripts/analysis/logit/partisan_model2.R` | Fits interaction models for single-name donor partisanship, both categorical pre-period bins and continuous GOP/DEM score components. |
| `scripts/analysis/logit/partisan_model3.R` | Fits interaction models for subsector and industry partisan scores, including all-firm industry category measures. |
| `scripts/analysis/logit/model_interpret.R` | Reads fitted logit models, creates baseline and interaction tables, and creates favorability-probability figures. |
| `scripts/analysis/logit/subsec_model_interpret.R` | Reads subsector and industry interaction models and writes the corresponding table output. |
| `scripts/analysis/logit/plot_figures.R` | Produces publication-style prediction, marginal-effect, and peak-probability figures for partisan heterogeneity models. |

### Tobit Models

| Script | Role |
| --- | --- |
| `scripts/analysis/tobit/partisan_model1.R` | Intensive-margin Tobit-style model using `survival::survreg` with interval censoring for contribution limits. Focuses on single-name partisanship bins and continuous score components. |
| `scripts/analysis/tobit/partisan_model2.R` | Intensive-margin interaction models for giving-pattern partisanship and industry/all-firm industry partisan measures. |
| `scripts/analysis/tobit/partisan_tables.R` | Reads Tobit model objects and clustered covariance matrices, then writes LaTeX interaction tables. |
| `scripts/analysis/tobit/partisan_plots.R` | Produces Tobit prediction, marginal-effect, and peak-contribution figures for partisan heterogeneity models. |

### Archive

`scripts/analysis/archive/` contains older candidate-model, race-model, model-output, and interpretation scripts. Treat these as provenance/reference unless a project note explicitly says a result depends on them.

## Key Data Inputs

| Data path | Role |
| --- | --- |
| `data/processed/fec/firm_pac_to_principal_committee_contributions.parquet` | Main processed firm PAC contribution input for House aggregation. |
| `data/processed/fec/corporate_pac_firm_matches.csv` | PAC-to-firm match table used to attach firm identities. |
| `data/processed/house/` | House-level panels generated by `HouseData.py`. |
| `data/processed/modeling/cand_model_data.RDS` | Full-sample model-ready candidate data. |
| `data/processed/modeling/cand_model_data_election_year.RDS` | Election-year model-ready candidate data used by most current scripts. |
| `data/external/other/` | External support data such as industry classifications, candidate lists, congressional records, and partisan/consumer measures. |
| `data/processed/market/` | Market/event-study outputs used for market-reaction and firm/industry partisan measures. |

## Expected Outputs

| Output area | Contents |
| --- | --- |
| `outputs/models/`, `outputs/models/election/`, `outputs/models/all/` | Saved model objects from logit and Tobit scripts after path migration. Current scripts may still write to a top-level `model/` path depending on `PATH`. |
| `outputs/tables/` | LaTeX tables such as baseline, interaction, and Tobit interaction tables after path migration. |
| `outputs/figures/` | Conditional probability, marginal-effect, peak-probability, and Tobit prediction figures after path migration. |

## Recommended Run Order

1. Refresh or verify processed FEC and firm data with the active data collection scripts.
2. Run `scripts/aggregate/HouseData.py`.
3. Run `scripts/aggregate/HouseCandData.R`.
4. Run logit model scripts in this order: `baseline_model.R`, `reputation_model.R`, `partisan_model1.R`, `partisan_model2.R`, `partisan_model3.R`.
5. Run logit interpretation and plotting scripts: `model_interpret.R`, `subsec_model_interpret.R`, `plot_figures.R`.
6. Run Tobit model scripts: `tobit/partisan_model1.R`, `tobit/partisan_model2.R`.
7. Run Tobit output scripts: `tobit/partisan_tables.R`, `tobit/partisan_plots.R`.

## Cleanup Notes

- Replace `PATH <- "~/campaigncontributions/"` with project-root-relative path handling.
- Standardize inputs to `data/processed/modeling/` and outputs to `outputs/models/`, `outputs/tables/`, and `outputs/figures/`.
- Move logit and Tobit scripts into `scripts/analysis/firm_heterogeneity_house/` only after path migration and a successful R parse/run check.
- Consider factoring repeated R helpers for `prep_cand_data()`, model fitting, model reads, and plot prediction scaffolding.

