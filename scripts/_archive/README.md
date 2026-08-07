# Archived legacy notebooks/scripts (2026-08 migration)

These were reviewed cell-by-cell during the scripts/data split migration and found to be
either fully superseded by an active script, or one-off exploratory scratch work. Kept for
historical reference, not maintained, not expected to run against the current data layout
(most still reference the old `../data/...`, `S:/campaignfinance/...`, or `E:/...` paths).

## Fully superseded by an active script

| Archived | Superseded by |
| --- | --- |
| `notebooks/CandData.ipynb` | `scripts/aggregate/HouseData.py` |
| `notebooks/DataView.ipynb` | `scripts/data_collection/fec/FECprocessor.py` |
| `FEC/company_info.ipynb` | `scripts/data_collection/lseg/LSEGfirms.py` |
| `FEC/match_firms.py` | inlined into the active pipeline |
| `notebooks/experiment.ipynb` (tainted-access/asof-join cells) | `scripts/aggregate/TaintedAccessPanels.py`, `scripts/data_collection/fec/utils.py` |
| `FEC/company_match.ipynb` | `scripts/data_collection/fec/FECsuperOrganizationFirmMatcher.py` (more robust matcher) |
| `data_collection_fec/experiment.ipynb` (LSEG org-search cell) | `FECsuperOrganizationFirmMatcher.py`; remaining cells are one-off DIME/Bonica debugging scratch |

## Logic extracted into new scripts, then archived

| Archived | Extracted to |
| --- | --- |
| `FEC/get_hedging.py` | `scripts/data_collection/fec/PartisanHedgingIndex.py` |
| `FEC/race.py` | `scripts/data_collection/fec/HouseRaceCompetitiveness.py` |
| `FEC/pre_election.ipynb`'s `zscore_rolling_spike` | `scripts/data_collection/fec/ContributionSpikeDetection.py` (`pre_election.ipynb` itself was left in place, not archived -- it has other reporting/plotting content not part of this extraction) |

`get_hedging.py`/`race.py` also had a pre-existing broken import (`from utils import *` against
a `scripts/FEC/utils.py` that no longer exists) -- unrelated to the migration, not fixed, moot
now that the logic lives in the new scripts above.

## Pure scratch, no unique logic worth keeping active

`FEC/conributions.ipynb`, `FEC/experiment.ipynb`, `FEC/reformat.ipynb` (diff briefly against
`scripts/data_collection/fec/{FECtidy,reformat}.py` if ever revisited -- names overlap but the
active scripts are the current versions).

## Left in place, not archived

`scripts/FEC/analysis.ipynb`, `analysis_2024.ipynb`, `candidates.ipynb`, `pre_election.ipynb`,
`summary_stats.ipynb`, `network.ipynb` -- these still hold reporting/plotting logic beyond what
was extracted above (sector diagnostics, HII scatter plots, PAC-similarity network analysis).
`network.ipynb` specifically is lower-priority: only worth promoting into `scripts/analysis/` if
the donor-cohesion research thread is revived. `scripts/LSEG/test.ipynb` was also left in place --
its unused `TR.WACCBeta` field may be worth checking as a shortcut for the OLS beta estimation in
`EventStudy.py`/`ExposureStudy.py`/`BetaOneExposure.py`, but that's an investigation, not an
extraction. `scripts/FEC/analysis.R` was left in place too (dead code, hard-codes a different
author's Mac path).
