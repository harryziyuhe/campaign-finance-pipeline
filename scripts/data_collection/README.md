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
| `fec/FECscraper.py` | Pull FEC API candidate, committee, expenditure, and contribution data. |
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
