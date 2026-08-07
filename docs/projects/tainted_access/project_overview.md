# Firm Contributions Around Congressional Scandals

## Status

This is an early-stage causal-design project. The current work is data organization and design documentation, not final modeling. The project studies whether firm PACs change contributions around congressional scandals by comparing pre- and post-scandal contribution behavior for scandal-exposed members against appropriate comparison members.

The external source files now live under `data/external/congress/`. Keep these originals unchanged. Build cleaned, merge-ready tables under `data/processed/congress/`, then build final analysis panels under a project-specific processed folder such as `data/processed/house/scandal_did/`.

## Research Purpose

The main empirical question is whether firms adjust political contributions when a member of Congress becomes publicly tied to a scandal. The scandal data supply event timing, actor identity, and salience. The House member and committee assignment workbooks supply congressional context that can be merged with FEC contributions and candidate/election covariates.

The likely design is a DiD or event-study setup:

- Treated units: members with scandal events.
- Timing: public scandal break date or best available event timing.
- Outcomes: firm PAC contribution probability, amount, timing, or persistence.
- Comparisons: non-scandal members, future-treated members, same-party or same-state members, committee peers, or matched candidate/member controls.

## Scope And Unit Of Analysis

The final analysis-ready unit should be chosen deliberately.

| Unit | Use case |
| --- | --- |
| Firm PAC by member by cycle | Best for two-year election-cycle contribution outcomes and compatibility with existing House/FEC panels. |
| Firm PAC by member by event window | Best for exact pre/post scandal timing when contribution dates are retained. |
| Firm PAC by member by relative event period | Best for event-study plots around scandal timing. |

The scandal source spans 1979-2018. The House member and committee assignment sources cover Congresses 103-115. The first practical analysis window should be the overlap between these sources and the repository's processed FEC contribution data.

## Source File Organization

These source files are external support inputs. They are not generated processed data and should not be overwritten by scripts.

| Source file | Type | Role |
| --- | --- | --- |
| `data/external/congress/scandals/congressional_scandals_1979_2018.csv` | External CSV | Scandal event source with actor identity, Congress, state/district, party, break timing, salience, criminal flag, political outcome, scandal type, and notes. |
| `data/external/congress/committee_assignments/house_members_103_115.xlsx` | External workbook | House member source for Congresses 103-115. Use for member-Congress records and joins to committee assignments. |
| `data/external/congress/committee_assignments/house_committee_assignments_103_115.xls` | External workbook | House committee assignment source for Congresses 103-115. Use for committee membership, roles, and institutional covariates. |
| `data/external/congress/committee_assignments/house_members_103_115_sheet1.csv` | Converted external CSV | Main converted sheet from `house_members_103_115.xlsx`; appears to contain member-Congress records. Prefer this for parser development after confirming columns. |
| `data/external/congress/committee_assignments/house_members_103_115_sheet2.csv` | Converted external CSV | Small supplemental member background table with district, representative, party-change flag, prior background, and birth year fields. |
| `data/external/congress/committee_assignments/house_members_103_115_sheet3.csv` | Converted external CSV | Parsed/split supplemental member table that appears related to sheet2, with separated name/state/district fields. Confirm exact role before using it as a covariate source. |
| `data/external/congress/committee_assignments/house_committee_assignments_103_115.csv` | Converted external CSV | Converted committee assignment sheet. Prefer this for parser development instead of reading the `.xls` workbook directly. |

This layout is preferable to `data/external/other/` because the files are all congressional institutional or event sources for the same causal project. The split between `scandals/` and `committee_assignments/` keeps event timing separate from member/committee context.

The Excel originals are retained for provenance. The CSV files are mechanical conversions for easier script development and should be treated as source sidecars, not cleaned processed tables.

## Recommended Processed Storage

Create standardized script-generated tables under `data/processed/congress/`:

| Recommended table | Role |
| --- | --- |
| `data/processed/congress/congressional_scandals.parquet` | One row per scandal event or member-scandal event with normalized identifiers, parsed dates, salience, type, criminal flag, outcome, and notes. |
| `data/processed/congress/house_member_terms_103_115.parquet` | One row per member-Congress term with normalized member ID, Congress, state, district, party, and name fields. |
| `data/processed/congress/house_committee_assignments_103_115.parquet` | One row per member-Congress-committee assignment with committee names/codes and role fields when available. |
| `data/processed/congress/house_member_committee_panel_103_115.parquet` | Optional convenience panel merging member terms to committee assignments. |

Create final project panels under:

```text
data/processed/house/scandal_did/
```

Suggested final tables:

| Recommended table | Role |
| --- | --- |
| `firm_member_cycle_scandal_panel.parquet` | Firm PAC by member by cycle panel with contribution outcomes, scandal treatment indicators, event time, firm covariates, member covariates, and election covariates. |
| `firm_member_event_window_contributions.parquet` | Contribution-date or event-window table for exact pre/post scandal timing. |
| `member_scandal_event_windows.parquet` | Scandal events expanded into relative event periods and matched to member/Congress/cycle records. |

## Merge Strategy

Use stable congressional identifiers wherever possible.

1. Normalize scandal actors by `bioguide` from the scandal CSV.
2. Normalize House member and committee assignment workbooks to the same member identifier. If the Excel sources lack Bioguide IDs, create a reviewed name-state-district-Congress bridge.
3. Build or verify a bridge from `bioguide_id` to FEC `candidate_id` by cycle using FEC API candidate history and House principal committee files.
4. Link firm PAC contributions through `data/processed/fec/firm_pac_to_principal_committee_contributions.parquet` or through existing House panels under `data/processed/house/`.
5. Attach candidate/election covariates from existing House aggregation outputs and external candidate support files.

Avoid name-only merges from scandals directly to FEC contribution rows. Names are not stable enough for a causal panel because of suffixes, aliases, redistricting, and repeated candidate names.

## Upstream Dependencies

| Script or data | Role |
| --- | --- |
| `data/external/congress/scandals/congressional_scandals_1979_2018.csv` | Treatment event source. |
| `data/external/congress/committee_assignments/house_members_103_115.xlsx` | Member-Congress source for institutional covariates and assignment joins. |
| `data/external/congress/committee_assignments/house_committee_assignments_103_115.xls` | Committee assignment source for committee-level context and heterogeneity. |
| `data/processed/fec/firm_pac_to_principal_committee_contributions.parquet` | Main firm PAC contribution source for member/candidate outcomes. |
| `data/processed/fec/house_candidate_principal_committees.csv` | Candidate-principal committee bridge used to map firm PAC contributions to House candidates. |
| `data/raw/fec_api/candidates/H/` | Candidate history source that can help build a Bioguide-to-FEC-candidate bridge if the needed fields are available. |
| `data/processed/house/` | Existing House-level panels and contribution summaries that can be extended with scandal and committee covariates. |
| `data/external/other/house_general_cands.csv` | Existing candidate/election support file. It remains under `external/other/` until there is a broader candidate/election external namespace. |

## Project Scripts To Add

No project-specific scripts exist yet. Recommended future scripts:

| Proposed script | Role | Inputs | Outputs |
| --- | --- | --- | --- |
| `scripts/data_collection/congress/ScandalEvents.py` | Parse and normalize the scandal CSV. | `data/external/congress/scandals/congressional_scandals_1979_2018.csv` | `data/processed/congress/congressional_scandals.parquet` |
| `scripts/data_collection/congress/HouseCommitteeAssignments.py` | Parse converted House member and assignment CSV sidecars into normalized tables. | `data/external/congress/committee_assignments/*.csv` | `data/processed/congress/house_member_terms_103_115.parquet`, `data/processed/congress/house_committee_assignments_103_115.parquet` |
| `scripts/aggregate/ScandalDidPanel.py` | Build firm-member-cycle or firm-member-event-window panel for the causal design. | Processed FEC, processed House, processed congressional scandal/committee tables | `data/processed/house/scandal_did/*.parquet` |

## Workflow

1. Preserve the external source files under `data/external/congress/`.
2. Normalize scandal, member, and committee assignment sources into `data/processed/congress/`.
3. Build a `bioguide_id` to FEC `candidate_id` by cycle bridge.
4. Merge firm PAC contributions to member-cycle or member-event-window records.
5. Expand scandals into treatment timing variables: pre/post, event time, salience bins, and optional anticipation/exclusion windows.
6. Add committee assignment covariates and candidate/election covariates.
7. Save final analysis panels under `data/processed/house/scandal_did/`.

## Validation

- Check every scandal row has either a parseable event date or an explicit approximate-date flag. The source includes non-standard timing such as `Fall 1986`, so date uncertainty needs to be preserved.
- Check uniqueness of scandal events by `bioguide_id`, event timing, scandal type, and notes or a generated `scandal_event_id`.
- Check workbook coverage by Congress before relying on committee assignment covariates.
- Check assignment rows merge to member records within the same Congress.
- Check scandal actors merge to FEC candidates through `bioguide_id` and cycle, not name-only matching.
- Check event windows for scandals near cycle boundaries, redistricting cases, and duplicate candidate-cycle rows.

## Assumptions And Manual Decisions

- Treat the scandal CSV as an event source, not as a ready-made treatment panel.
- Treat `breakdate` as the first public scandal timing when parseable, but document a rule for approximate dates before estimating effects.
- Treat `salience` as treatment intensity or heterogeneity only after defining thresholds or a continuous specification.
- Normalize committee assignments to member-Congress-committee rows before merging with FEC contributions.

## Open Work

- Decide whether `house_members_103_115_sheet2.csv` or `house_members_103_115_sheet3.csv` should feed member background covariates, or whether they should remain provenance-only supplemental sheets.
- Build `scripts/data_collection/congress/` parsers for scandals, members, and committee assignments.
- Decide whether committee assignment covariates are controls, moderators, or part of treatment definition.
- Define comparison groups and event windows before estimation.
- Decide whether the main outcome is contribution probability, amount, timing, or relationship persistence.
