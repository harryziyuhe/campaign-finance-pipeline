# Data Collection And Processing Scripts

This folder contains the scripts that maintain data inputs and processed datasets. Exploratory notebooks and older analysis scripts are intentionally left outside this folder.

| Path | Purpose |
| --- | --- |
| `fec/` | FEC API scraping, FEC bulk tidying, and processed contribution table construction. |
| `lseg/` | LSEG firm metadata, return scraping, and market/event-study processing. |
| `electionratings/inside_elections/` | Inside Elections directory and House ratings parsers. |

Important FEC scripts:

| Script | Purpose |
| --- | --- |
| `fec/fec_client.py` | Shared `FECClient` base class (HTTP retry, list-endpoint pagination, upsert-by-key CSV merge) used by every script below. Not runnable on its own. |
| `fec/candidates/candidates_list.py` | Pull the FEC candidate list (current state only, no history) for one office. |
| `fec/candidates/candidate_history.py` | Pull per-cycle candidate history. Only calls the API for candidates with a gap or a current-cycle row (see `current_cycle_threshold()`); merges in by (candidate_id, candidate_election_year) via `merge_cyclical` -- settled past cycles are frozen (a differing fresh value is flagged in a `*_discrepancies.csv` instead of overwriting). |
| `fec/candidates/candidate_committees.py` | Pull candidate-affiliated committee history (including joint committees), same skip/merge/freeze pattern as candidate_history.py. |
| `fec/committees/{leadership_pacs,joint_committees,hybrid_pacs,super_pacs,corporate_pacs}.py` | One standalone script per committee type/designation. Each fetches just committee_id + active_start/active_end (derived from the committee's `cycles` field, no extra per-committee calls) and merges via `merge_active_period`: a new committee_id is inserted, and for a known one only active_end can grow -- active_start and everything else is never overwritten. `corporate_pacs.py` replaces `FECtidy.py`'s bulk committee-master dependency for discovering the corporate-PAC universe. |
| `fec/committees/leadership_history.py` | Per-cycle leadership PAC history, same skip/merge/freeze pattern as candidate_history.py. |
| `fec/contributions/{hybrid_pac,super_pac,leadership_pac,corporate_pac}_contributions.py` | Schedule A (donor-side) contributions per PAC type, sharing `schedule_a_core.py`. **Known gap:** still skips a committee entirely once it has any contributions on file -- not yet converted to a real incremental checkpoint. |
| `fec/contributions/{hybrid_pac,super_pac}_expenditures.py` | Schedule E independent expenditures per PAC type, sharing `schedule_e_core.py`. Same known gap as above. |
| `fec/FECprocessor.py` | Build processed committee/firm-PAC contribution tables. |
| `fec/FECtidy.py` | Tidy FEC bulk files and corporate PAC match inputs. |
| `fec/reformat.py` | Convert pipe-delimited FEC bulk text files to parquet. |
| `fec/FECindividualToFirmPACs.py` | Filter raw individual contributions to contributions received by firm PACs. |
| `fec/FECsuperOrganizationFirmMatcher.py` | Conservatively match super-PAC organization contributors to firm-universe records; its `lseg-search` stage can reuse a saved first-pass output, checkpoint LSEG organisation matches, and add equity RIC/PermID for public-company hits. |

Important LSEG scripts:

| Script | Purpose |
| --- | --- |
| `lseg/LSEGfirmInfoFromPermIDs.py` | Fetch firm-universe-style metadata for resolved identifiers produced by the FEC super-organization LSEG crosswalk. |

The active scripts have been updated to use the reorganized data layout. See `docs/migration-log.md` for old-to-new path mappings.
