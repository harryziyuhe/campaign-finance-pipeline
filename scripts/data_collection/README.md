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
| `fec/candidates/candidate_history.py` | Pull per-cycle candidate history, upserting by (candidate_id, candidate_election_year). `--refresh all` re-checks every known candidate, not just new ones -- use for catch-up runs or to pick up rare retroactive corrections. |
| `fec/candidates/candidate_committees.py` | Pull candidate-affiliated committee history (including joint committees), same upsert/`--refresh` pattern. |
| `fec/committees/{leadership_pacs,joint_committees,hybrid_pacs,super_pacs,corporate_pacs}.py` | One standalone script per committee type/designation -- full list refresh each run (cheap, these are current-state-only endpoints). `corporate_pacs.py` replaces `FECtidy.py`'s bulk committee-master dependency for discovering the corporate-PAC universe. |
| `fec/committees/leadership_history.py` | Per-cycle leadership PAC history, same upsert/`--refresh` pattern as candidate_history.py. |
| `fec/committees/committee_active_period.py` | Fills active_start_year/active_end_year onto a committee list file. |
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
