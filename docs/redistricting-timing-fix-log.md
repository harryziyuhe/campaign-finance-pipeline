# Redistricting-Aware Timing Fix — Progress Log

Working log for the fix to the "chance of winning" / `favorability` construction in the House
contribution panel (used by `scripts/analysis/logit/` and `scripts/analysis/tobit/`), motivated by
two related concerns raised in review: (1) the current construction (`process_elections` in
`scripts/aggregate/HouseData.py`, mean of post-May Inside Elections ratings per race-cycle) matches
contributions to a rating that postdates many of them, and (2) the same `(state, district)` label
can refer to different underlying geography across and within cycles, so a naive per-contribution
date match would misclassify race competitiveness around redistricting events.

See conversation history for the full reasoning trail. This log tracks concrete steps and findings
only.

## Phase 1 — Recover missing off-year IE snapshots (complete)

- `directory.csv` (parsed from `directory.xml` by `directory.py`) lists 311 Inside Elections house
  rating snapshot pages, 2010-2025. `house_records.py` previously filtered to even years only
  (`date.dt.year % 2 == 0`), discarding 131 odd-year (off-year) snapshots before they ever reached
  `house_ratings.csv`.
- Of those 131 off-year pages, only 5 had been fetched to local XML. Confirmed the
  `insideelections.com/api/xml/ratings/by-id/house/{id}` endpoint requires no auth/subscription —
  a plain request was 403'd only because of a missing browser-like User-Agent/Accept/Referer, not
  real access control.
- Fetched all 126 missing files (0 failures). Removed the even-year filter in `house_records.py`
  and reran it. `house_ratings.csv` now has 135,297 rows across 310 snapshot dates, 2010-2025
  (previously 78,312 rows / 180 dates, even years only).

## Phase 2 — Race-stability diagnostic (complete)

Script: `scripts/data_collection/electionratings/inside_elections/race_stability_diagnostic.py`
Outputs: `data/processed/electionratings/race_stability_signal_a.csv`,
`race_stability_signal_b.csv`, `race_stability_state_cycle_summary.csv`

Rejected a flat magnitude-threshold-on-adjacent-snapshot-jumps approach (can't distinguish a
redistricting relabel from a real political swing; misses smaller relabels; a single jump doesn't
confirm a persistent level shift). Replaced with two combined signals, evaluated within
`(state, district, cycle)` groups (odd-year snapshots mapped forward to their upcoming even-year
cycle):

- **Signal A** (near-certain relabeling evidence): the rated incumbent's surname changes between
  snapshots in the same cycle with no special election (`special` flag) on either side — a named
  officeholder cannot change through the ordinary electoral process before the next election.
  136 transitions flagged, 125 distinct races.
- **Signal B** (catches same-incumbent-different-electorate cases Signal A misses): best single
  split point in the rating series such that the two segments are stable (low within-segment
  variance) and meaningfully different (large between-segment gap); flagged when the split
  explains >=60% of the series' variance and the gap is >=2 rating points. 294 races flagged.
- Overlap: 52 races flagged by both (highest confidence). Total distinct races flagged (union):
  367, collapsing to 118 distinct `(state, cycle)` events.

**Important refinement found during manual review of the 56-row overlap set**: not every flag
needs a fix. Signal A/B only matter when the underlying *geography* changed — real political
events that also change the named incumbent (disqualification, resignation + special election,
retirement) are legitimate temporal information the date-matched design is supposed to capture
correctly, not artifacts to exclude. Confirmed non-redistricting cases found in the overlap set:
MI-11 2012 (McCotter ballot disqualification), PA-14 2018 (Murphy resignation / Lamb special
election, tangled with the same-window PA redraw), OH-13 2022 (A. Gonzalez retirement, plausibly
unrelated to OH's map fight). The tell for "this is really a boundary change" is coordinated,
same-date breaks across *many* districts in one state — isolated 1-2-district flags are more
likely real politics and should not be assumed to need a floor date without individual confirmation.

State-cycle event counts (collapsed): dominated by FL-2012 (39), NY-2012 (35), PA-2018 (28),
FL-2022 (25), NC-2022 (21), IL-2022 (15), NY-2022 (15), PA-2022 (12), MI-2022 (10); remaining ~109
events have <=7 flagged districts each and are lower-priority / plausibly not boundary-driven.

## Phase 3 — External adjudication (in progress)

**Key realization (changes scope of this phase):** FL-2012 and NY-2012 are *not* mid-cycle
litigation cases in the PA-2018 sense. FL's 2012 map was signed into law Feb 16, 2012 and not
struck down until 2014 (replacement used starting 2016); NY's federal court didn't finalize its
2012 map until March 19, 2012. What Signal A/B were detecting for these states is the mechanical
fact that the *2011* snapshots recovered in Phase 1 describe the old, pre-2012 map, because the new
decade's map didn't exist yet — not a second map appearing within an otherwise-stable cycle.

This splits Phase 3 into two different-sized problems:

1. **Redistricting-year cycles (2012, 2022):** universal, not limited to flagged states — every
   state gets a new map at some specific date in these years, whether or not the old/new
   competitiveness happened to differ enough to trigger a flag. Needs one comprehensive
   per-state "date the map actually used in that cycle's election became final" lookup, applied
   as a floor for all states in 2012 and 2022.
2. **True mid-cycle cases (PA-2018 confirmed; NY/NC/OH/IL/PA-2022 per Brennan Center summary,
   where a legislature-drawn map was itself replaced by a court/commission map within the same
   2022 cycle):** rarer, needs the case-by-case Signal A/B + external confirmation already in use.

Confirmed so far:
- PA 2018: PA Supreme Court adopted its own remedial map Feb 19, 2018, for that year's May 15
  primary (struck down the prior map Jan 22, 2018).
- FL 2012: legislature map signed Feb 16, 2012; not replaced until 2016 cycle (not a within-cycle
  case).
- NY 2012: federal court finalized map March 19, 2012 (not a within-cycle case; explains the old
  vs. new map mismatch, not litigation churn).
- 2022 cycle, high level (needs per-state effective dates next): OH map struck down Jan 2022,
  remedial map approved by Ohio Redistricting Commission March 2, 2022; NC Supreme Court struck
  down maps Feb 4, 2022, replacement map instituted Feb 23, 2022; NY maps struck down by trial
  court, special-master remedial maps used for the 2022 election (exact effective date not yet
  pulled).

**Resolved — turned out to fully subsume both 3a and 3b.** All About Redistricting publishes a
downloadable CSV ("full data about all cycles") with the enacted-plan history for every state,
every redistricting cycle, including Start Date / End Date / Plan Status for every revision
(court-ordered or otherwise). This single source gives the correct floor date for every state and
cycle mechanically, without needing separate treatment for "ordinary decennial transition" vs.
"mid-decade litigation" -- both are just entries in the same plan-history table; the floor for a
given (state, cycle) is the Start Date of whichever enacted plan's window contains that cycle's
Election Day.

Source: `https://redistricting.lls.edu/wp-content/uploads/StatesAndCyclesData_production-20260710.csv`,
saved to `data/external/redistricting/aar_states_and_cycles.csv`.

Script: `scripts/data_collection/electionratings/inside_elections/redistricting_floor_dates.py`
Output: `data/processed/electionratings/redistricting_floor_dates.csv` (346 rows, 44 states with
Congress-level entries -- the 6 missing are single-district at-large states with no meaningful
within-state boundary dispute: AK, DE, MT, ND, SD, VT, WY).

**Genuine mid-decade revisions within the stable 2010s map (2012-2020, i.e. NOT just the ordinary
2010->2012 or 2020->2022 decennial transition) confirmed in exactly four states**: FL (struck 2014,
replacement used starting 2016), NC (two revisions -- 2016 and again 2019/2020), PA (Feb 19, 2018,
matches the earlier confirmed date exactly), VA (Jan 2016, the racial-gerrymander remedy). No other
state shows more than one distinct floor date within 2012-2020.

**Cross-validated against the Phase 2 Signal A/B diagnostic** by joining
`race_stability_state_cycle_summary.csv` to the floor-date table: every heavily-flagged
state-cycle (FL/NY-2012, PA-2018, FL/NC/NY/IL/PA/MI/GA-2022, TX/KY/CA/MN/KS-2012) has a matching
floor date landing inside or very near that specific cycle, with court-action text confirming a
real dispute (struck by state/federal court, court drew map, pending litigation, etc.). Two useful
disambiguations fell out of this join:
  - **MI-2022** (10 districts flagged): plan status is "Active" (survived legal challenge) --
    this is Michigan's first-ever map from its new independent redistricting commission, a real
    one-time difference from the prior decade's map, not litigation churn. No special mid-cycle
    handling needed beyond the ordinary 2022 floor already in the table.
  - **NJ-2018** (4 districts flagged): floor date is 2011-12-23 -- i.e. the *original* 2010s map,
    unchanged. These flags have no matching redistricting event and are very likely genuine
    political variation (consistent with the Phase 2 rule that isolated flags without a
    coordinated statewide pattern are probably real politics, not artifacts).

Phases 3a and 3b are complete as a result of this single data source. Remaining manual-adjudication
need is much smaller than originally scoped: mainly spot-checking the long tail of 1-3-district
flags in state-cycles where the floor-date table shows no revision, to confirm they're safe to
leave untouched.

## Phase 4 design decisions (resolved through discussion)

- **Old-map matching for pre-floor contributions**: rather than dropping or backfilling with the
  new-map rating, use whatever map was actually in effect when the contribution was made. Applies
  uniformly to all floor-date cases (2012/2022 decennial transitions and the FL/NC/PA/VA mid-decade
  revisions), not just the two redistricting-year cycles.
- **Race-level, not candidate-level, crosswalk**: a challenger contesting a newly-drawn district
  doesn't need an independent old-district identity -- whatever old district the *race* corresponds
  to (via incumbent continuity) applies to every candidate contesting it, since firms are reacting to
  the same underlying contest regardless of who's on the ballot. This is purely empirical (no new
  external data): for a new district's earliest post-floor snapshot, take the incumbent's surname and
  search the same state's pre-floor districts for a match. Implemented in
  `scripts/data_collection/electionratings/inside_elections/race_old_district_crosswalk.py`, output
  `data/processed/electionratings/race_old_district_crosswalk.csv`.
  - Match rate on races where the district genuinely changed: 59.9% overall, but **89.9% for 2012
    and 96.3% for 2022** -- the two cycles that actually carry the contribution volume. Unmatched
    cases (open seats from retirement, brand-new seats from apportionment) have no valid old-map
    proxy and get excluded/flagged downstream rather than guessed at.
- **Aggregation-level fix** (the panel stays at firm-candidate-cycle granularity; only how the
  rating *input* is constructed changes):
  - Tobit (intensive margin, total amount): contribution-amount-weighted average of the date-matched
    (old-map-aware) rating across all of that dyad's contribution events in the cycle.
  - Logit (extensive margin), two variants run as mutual robustness checks: (a) entry-date variant --
    contributors get the rating at their first contribution, non-contributors get the rating nearest
    Election Day; (b) election-day variant -- everyone gets the rating nearest Election Day. The two
    variants differ only in how contributors are anchored, isolating the entry-vs-resolution-timing
    comparison cleanly.
  - No-lookahead constraint applies throughout: every date match uses the nearest available snapshot
    at-or-before the target date, never a later one.
- **76% of total contribution dollars come from firm-candidate-cycle pairs with more than one
  contribution event** (49.8% of dyads have >1 event; median span between first and last event is
  347 days), which is why the Tobit's weighted-average construction matters substantively, not just
  as a technical nicety -- worth a sentence in the paper's methods section.

## Critical bug found and fixed: odd-year district format

While tracing the unmatched-candidate question below, `HouseData.py`'s exact `load_data()` call
crashed on `pl.read_csv` with `could not parse "PA-17" as dtype i64`. Root cause: **odd-year
(off-cycle) Inside Elections snapshot pages encode `district` as `"{state}-{n}"` (e.g. "PA-17")
instead of the bare number (`"17"`) used in even-year pages**, and at-large states as
`"{state}-AL"` instead of `"1"`. This affected 54,810 rows -- 40.5% of the entire ratings file --
exclusively in odd calendar years (2011, 2013, 2015, 2017, 2019, 2021, 2023), across all 50 states.

This is a bug in the Phase 1 recovery work itself, not a pre-existing issue: the previously-excluded
odd-year snapshots use a different district format than the even-year ones the pipeline was built
around, and every downstream script built on `house_ratings.csv` since Phase 1 inherited it. Fixed
in `house_records.py` (`normalize_district()`, strips the state prefix and maps "AL" to "1"),
verified zero remaining non-numeric district values, and re-ran the two downstream scripts that
depend on the ratings file:

- `race_stability_diagnostic.py`: Signal A jumped from 136 to **1,901** flagged transitions (14x).
  Explanation: before the fix, odd-year and even-year snapshots of the *same actual district* were
  grouped as two entirely separate district identities (since the string values didn't match), so
  the diagnostic never actually compared across that boundary at all -- the incumbent-continuity
  check across the off-year/election-year seam was effectively invisible. Signal B changed much
  less (294 -> 319), since it operates mostly within already-correctly-grouped even-year series.
- `race_old_district_crosswalk.py`: overall match rate on genuinely-relabeled races dropped sharply
  (59.9% -> 12.4%), suggesting the earlier figure included spurious matches from the format bug.
  **The two cycles that actually carry contribution volume are largely unaffected**: 2012 at 89.3%
  (was 89.9%), 2022 at 98.6% (was 96.3%). The long tail of smaller mid-decade cases is less
  well-covered than previously reported and will lean more heavily on the documented-exclusion
  treatment.

All Phase 2/3 output files have been regenerated with the corrected data. `redistricting_floor_dates.py`
was unaffected (it reads from the AAR export, not `house_ratings.csv`).

## Side investigation: the unmatched-contribution question, precisely traced

Traced exactly which pipeline step drops each dollar, using `HouseData.py`'s actual functions
rather than a reimplementation.

**Correction to the earlier 35.6%/$494.8M headline number**: that included contribution cycles as
far back as 2004, because `firm_pac_to_principal_committee_contributions.parquet` covers a much
longer span than the paper's stated 2010-2022 window. The `elections` table (built from Inside
Elections ratings) only has data starting 2010, so pre-2010 contributions necessarily fail to
match -- correctly, not as a bug. Boehner (OH-08, missing 2006/2008) and Hastert (IL-14, missing
2004/2006) are exactly this: outside the study window entirely, not evidence of anything wrong.
**Properly scoped to 2010-2022, the unmatched share is 6.40% of dollars** ($61.2M of $956.2M) --
real, but far more modest than first reported.

Precise attribution of that $61.2M, walking through `process_candidates()` -> `elections` join ->
`general_cands` join in `get_cand_data()`'s `filter_cands`:

| Step | Dollars | Rows | What it means |
|---|---|---|---|
| No row in `candidate_history_H.csv` for that (candidate_id, cycle) at all | $5.46M | 3,133 | Missing/null in the FEC source itself |
| Survives that, but race missing from `elections` entirely | $6.65M | 3,885 | IE never rated that specific (state, district, cycle) even within 2010-2022 |
| Survives both, but candidate's last name didn't match `general_cands` | **$49.11M** | 26,783 | The dominant bucket |

For the dominant bucket: **every single one of these races does appear in `general_cands`** (the
MIT general-election-returns file) for that state/district/cycle -- it's specifically *this*
candidate's name that fails to match. Confirmed for Cantor 2014: his name doesn't appear under any
candidate in VA-7's 2014 general election at all (only Brat, Carr, Trammell, and a generic WRITEIN
row) -- he lost his primary to Dave Brat and never reached the general ballot, so his exclusion
from that cycle's `cand_data` is a real, defensible consequence of `filter_cands` only tracking
candidates who appeared in the actual general election, not a bug. What's still open: whether the
rest of this $49.11M bucket is entirely primary-loser cases like Cantor (expected, correct) or
partly a name-formatting mismatch between `candidate_history_H.csv` and `general_cands` for
candidates who *did* reach the general under a differently-parsed name (a real bug) -- not yet
separated out.

**Net read**: the candidate-matching gap is real but much smaller than first reported (6.4% of
in-scope dollars, not 35.6%), and the largest piece of it traces to a defensible design choice
(only candidates who reached the general election count), not obviously a bug -- though the
name-matching sub-question for that bucket is still unresolved.

**Closed as a side quest** -- 6.4% is small enough not to block Phase 4. Not pursuing the
primary-loser-vs-name-bug split further unless it resurfaces.

## Follow-up checks (both resolved)

**Election Day precision**: fixed. `election_day()` in `redistricting_floor_dates.py` now computes
the actual Tuesday-after-first-Monday-in-November per cycle (verified against all 8 known dates,
2010-2024) instead of approximating with Nov 1. Rebuilt the floor-date table and the race crosswalk
on top of it -- results shifted only slightly as expected (5801->5783 races considered, match rate
82.9%->83.0%), confirming the Nov-1 approximation was close but not exact in edge cases where a
plan's End Date fell between Nov 1 and the real Election Day.

**Unmatched House contributions -- NOT benign, found a real pre-existing pipeline gap.** Traced the
318,834 unmatched H-prefixed contribution rows:
  - Only 8.4% are firm-side (the PAC's committee never appears in `house_firm_cand` at all).
  - The rest (91.6%) are candidate-side. Checking party affiliation via `candidate_history_H.csv`
    contradicted the "benign, third-party candidates" hypothesis: **~98% of unmatched rows are to
    candidates coded REP or DEM**, not minor parties.
  - Of the 2,703 unique unmatched candidate_ids, 1,698 (62.8%) never appear in `house_firm_cand` for
    *any* cycle (plausibly a consistent, if unexplained, exclusion) -- but **1,005 (37.2%) do appear
    in `house_firm_cand` for a *different* cycle**, meaning these are otherwise-valid, included
    candidates who are missing specifically for one cycle. That's a real candidate-cycle matching
    gap somewhere in the existing `HouseData.py`/`HouseCandData.R` pipeline, not an artifact of this
    redistricting work and not obviously explained by the documented party/sector filters.
  - This predates and is independent of the timing/redistricting fix -- flagging it here since it
    surfaced during this work, but treating it as a separate, out-of-scope data-quality issue rather
    than blocking Phase 4 on it. Worth a dedicated look at some point.
- ~~Contributions made before any valid post-floor-date snapshot exists for a race: drop, use first
  available post-floor snapshot, or impute?~~ -- superseded by the old-map matching decision above;
  narrowed down to just the residual unmatched races from `race_old_district_crosswalk.py` (open
  seats from retirement, brand-new seats from apportionment), which get excluded/flagged rather than
  guessed at.
- ~~Whether to also fetch pre-2010 (Cycle Year 2000) AAR rows to correctly floor the 2010 election
  itself~~ -- fixed: `load_congress_plans()` now includes Cycle Year 2000 rows, so the 2010 cycle
  correctly floors against each state's 2000s-era map (e.g. FL 2010 floor is 2002-06-07, not a
  2010s-map date).

## Phase 4 implementation (core construction built and validated)

Script: `scripts/aggregate/contribution_favorability.py`. Implements every design decision above:
old-map matching via `race_old_district_crosswalk.csv` for pre-floor contributions (uniformly
across all floor-date cases, not just 2012/2022), unmatched pre-floor contributions excluded rather
than guessed at, no-lookahead nearest-prior-snapshot matching via `pd.merge_asof`, and all three
favorability constructions.

Outputs:
- `data/processed/house/contribution_favorability_dyad.parquet` (252,637 rows): per
  (cmte_id, candidate_id, cycle) dyad with >=1 contribution -- `favorability_entry` (first
  contribution, feeds the entry-date logit variant), `favorability_weighted` (dollar-weighted
  average, feeds the Tobit), plus `n_contribs`/`total_amount`.
- `data/processed/house/race_favorability_election_day.parquet` (20,386 rows): per candidate-cycle
  (contributors and non-contributors alike) -- `favorability_election_day`, nearest rating at/before
  that cycle's actual Election Day. Feeds the election-day logit variant for everyone, and is the
  non-contributor fallback for the entry-date variant.

Diagnostics from the run: 6,511 of 549,243 contributions (1.2%) excluded for no valid old-district
match; 59,829 (11%) have no snapshot at/before their own date (plausibly concentrated in the 2010
cycle, where there's no prior-cycle data to fall back on at all -- not yet broken out by cycle to
confirm); 269 of 20,386 races (1.3%) have no Election-Day-eligible snapshot.

**Spot-check**: Conor Lamb (PA, H8PA18181) in the new 2018 district 17 crosswalks to old district
12 (Rothfus's old seat) -- matches the real PA remap. His dyad-level favorability values are
sensible (-4 for pre-floor 2018 contributions, consistent with the old district's safe-R rating).

**Not yet done (at the time this was written)**: wiring this into the actual R modeling pipeline --
see Phase 5 below, now underway.

## Phase 5: pipeline integration (in progress -- R changes UNVERIFIED, Rscript not available here)

**Important caveat for all of this section**: `Rscript` is not installed in this environment
(`which Rscript` fails). Everything below the Python merge step is written carefully but has not
been executed or tested by me -- it needs to be run in an R-enabled environment and checked before
trusting the output.

**Column-naming fix**: renamed `contribution_favorability.py`'s outputs from `favorability_*` to
`rating_*` -- they're still on the raw IE scale (positive = Democrat-favored) at that point, not
yet the candidate-specific value. The `* democrat` transformation (existing convention, from
`HouseCandData.R`) happens later, after the party filter is applied, same as the original pipeline.
Outputs renamed to `contribution_rating_dyad.parquet` / `race_rating_election_day.parquet`.

**`scripts/aggregate/merge_contribution_ratings.py`** (Python, verified): joins the dyad-level
(`rating_entry`, `rating_weighted`) and race-level (`rating_election_day`) ratings onto
`house_firm_cand.parquet`, renaming the original cycle-mean `rating` to `rating_cyclemean` to avoid
ambiguity. Caught and fixed a silent column collision (`total_amount` existed in both the dyad file
and the original panel -- renamed the dyad's to `matched_contrib_dollars`). Output:
`data/processed/house/house_firm_cand_datematch.parquet` (10,571,940 rows; sanity-checked:
`rating_election_day` populated for all rows as designed, `rating_entry` for a sensible subset of
contributors only).

**`scripts/aggregate/HouseCandData.R`** (R, NOT verified): modified to read the datematch file for
the main sample, alias `rating_cyclemean` back to `rating`, add the three favorability variants
(`favorability_entry`, `favorability_election_day`, `favorability_weighted`, each with a `_sq`
term) with the coalesce-to-election-day fallback for non-contributors, and pass everything else
through unchanged. Also replaced the original fragile *positional* `names(cand_data) <- c(...)`
rename (which did several real renames, e.g. `industry_group`->`industry`,
`industry`->`subindustry`, not just relabeling) with an explicit name-based `rename()` -- the
positional version would have silently misaligned once the datematch columns changed the column
count/order, and I have no way to catch that without running R. The industry/subindustry swap goes
through a temporary column name to avoid relying on exact dplyr rename-evaluation-order semantics.
The "_election_year" sample doesn't have a datematch construction yet (see Phase 4 notes) -- filled
with placeholder NA columns so that arm still runs, just with all three variants NA (only the
original cycle-mean `favorability` stays valid for that sample until it gets its own construction).

**`scripts/analysis/logit/baseline_model.R`** (R, NOT verified): parameterized `build_formula()` /
`fit_logit()` / `fit_group_models()` to take a `favorability_var` argument instead of hard-coding
"favorability". Uncommented the main ("") sample in the loop alongside "_election_year" (previously
only the pre-election-year sample ran by default). Added two new baseline fits, guarded to only run
on the main sample where the datematch columns are populated: `extensive_baseline_entry.RDS`
(entry-date variant) and `extensive_baseline_election_day.RDS` (election-day variant), alongside
the existing `extensive_baseline.RDS` (cycle-mean, kept for comparison).

**R environment correction**: R was in fact installed (4 versions under `Program Files/R/`), just not
on the shell's PATH -- `Rscript.exe` runs fine via full path, and all needed packages (arrow, dplyr,
tidyr, splines, stringr, fixest, survival, sandwich, lmtest, ggplot2) are present. Ran
`HouseCandData.R` successfully on the main sample: 7,126,861 rows, 61 columns, all three
favorability variants present with sane summary stats matching the earlier Python-side replication
exactly (same row count, same descriptive pattern) -- good cross-validation that the R code does
what it was designed to do.

**Model fitting hit a real memory ceiling.** Attempted the three baseline logit fits (cyclemean,
entry, election-day) sequentially in one R session. The first fit alone (feglm, ~6.8M obs after NA
drop, state+year+category fixed effects, two-way cluster by cmte_id+candidate_id) drove the R
process to ~14.5GB and climbing before finishing, dropping system free memory from ~21GB to ~5.5GB.
Killed the process before it could complete or risk a harder crash -- system memory recovered
immediately to ~21GB, confirming the R process was the entire cause, not a broader system issue.
No completed model results yet. Likely driver: fixest's two-way (Cameron-Gelbach-Miller) cluster-
robust variance computation is memory-intensive at this N, independent of my changes -- the model
spec itself is the paper's own original spec (matches Table 1), so this isn't a consequence of the
new favorability columns, just of fitting large clustered models in this particular session/machine
state.

## Pre-election-year sample now has its own datematch construction

Extended `contribution_favorability.py` with an `election_year_only` filter (matches HouseData.py's
`aggregate_candidate_contribution(election_year=True)`: `year % 2 == 0 & month < 11`) and refactored
`main()` to build both samples' dyad-level ratings, reusing the same race-level Election-Day file
(it doesn't depend on contribution timing). `merge_contribution_ratings.py` similarly parameterized
to merge both samples, producing `house_firm_cand_election_year_datematch.parquet` alongside the
main one. `HouseCandData.R`'s placeholder-NA branch removed -- both samples now read a real
datematch file.

**Bug found and fixed along the way (unrelated to the redistricting work)**: `readline()` does not
read stdin at all under `Rscript` -- it silently returns `""` regardless of what's piped in, so
`echo y | Rscript HouseCandData.R` always behaved as "N" no matter what was piped. This caused two
sequential invocations to both target the main-sample file, racing on the same write and corrupting
it. Fixed by checking `interactive()`: keeps the original prompt for interactive/RStudio use, takes
the answer as a command-line arg (`Rscript HouseCandData.R Y`) when run via Rscript. Verified both
`cand_model_data.RDS` (7,126,861 rows, 249,449 contribute==1) and `cand_model_data_election_year.RDS`
(7,126,861 rows, 191,697 contribute==1) build correctly and independently now.

## All model-fitting scripts now parameterized (propagation complete)

Applied the same pattern to every remaining script that hard-coded "favorability"/"favorability_sq":
`partisan_model1.R` (give/etf/etfpre), `partisan_model2.R` (singlename), `partisan_model3.R`
(subsector/industry), `reputation_model.R` (private/consumer) in `scripts/analysis/logit/`, and
`tobit/partisan_model1.R` (singlename), `tobit/partisan_model2.R` (give/industry) in
`scripts/analysis/tobit/`.

**Pattern used in each**: converted `BASE_CONTROLS` and each `RHS_*` from fixed strings into
functions of a `favorability_var` argument; added a `FAVORABILITY_VARS` named vector at the top of
each script (logit: `favorability`/`entry`/`election_day`; Tobit: `favorability`/`weighted`, since
the intensive margin uses the dollar-weighted construction, not the entry/election-day pair); the
main loop now iterates over both `FAVORABILITY_VARS` and both samples (added `""`/`"all/"` alongside
the pre-existing `"_election_year"`/`"election/"` in every script, since both samples now have real
datematch data). Output filenames get the variant name suffixed (e.g.
`extensive_partisan_give_int_base_entry.RDS`); the original "favorability" variant keeps its
original filename with no suffix, so anyone only using the pre-existing files sees no change.

**Revert path, marked explicitly in every file**: each script has a `# REVERT:` comment at the
`FAVORABILITY_VARS` definition (set it back to `c(favorability = "favorability")` to fit only the
original spec) and at the `election_data`/`election_dir` definition (set back to
`"_election_year"`/`"election/"` only, matching every script's pre-existing default before this
session touched them). `baseline_model.R`'s date-matched block also has an explicit revert comment.
`HouseCandData.R`'s revert path is documented at the top of its datematch section.

All 8 modified R scripts (`HouseCandData.R`, `baseline_model.R`, `partisan_model1-3.R`,
`reputation_model.R`, `tobit/partisan_model1-2.R`) parse-check cleanly (`Rscript -e "parse(...)"`),
but have NOT been run end-to-end past `HouseCandData.R` -- the `feglm`/`survreg` fits themselves are
the memory-heavy step (see the OOM incident above) and are left for the user to run where there's
enough headroom. Given every logit script now fits 3x as many models (3 favorability variants x
existing spec count) and every Tobit script 2x, expect proportionally longer runtimes and higher
peak memory than before -- worth fitting one variant at a time in fresh sessions if memory is tight,
same mitigation as discussed for the OOM incident.

## Department reviewer comments -- separate track from the redistricting/timing work

A department faculty reviewer gave 5 comments on the draft (independent of everything above). Full
text and severity assessment discussed in conversation; tracked as tasks #11-15. Comment 1 addressed
immediately since it's a direct extension of the same triple-interaction plan raised earlier by
another faculty reader (see the "aggregation-level fix" discussion above).

### Comment 1: candidate-party asymmetry (task #11, implemented)

The reviewer's point: `favorability x sector-alignment` is estimated pooling both parties'
candidates, with candidate party only entering as a level control -- so a GOP-sector firm backing
a vulnerable Republican and the same firm backing a vulnerable Democrat load identically on the
interaction the paper uses to claim "GOP-sector firms tolerate more electoral risk." That conflates
two different claims: "these firms are more risk-tolerant toward candidates of either party" vs.
"these firms specifically favor vulnerable candidates of their own party."

Added to `scripts/analysis/logit/partisan_model3.R` (subsector/industry sector-alignment models,
the ones that map to the paper's Table 1-3 heterogeneity results):

- **Triple interaction** (`rhs_subsec_full3`, `rhs_ind_full3`, `rhs_indc_full3`): adds
  `favorability:sector_alignment:party` and the squared-term analog on top of the existing "full"
  spec (which already has every lower-order term), for a formal test of whether the sector-alignment
  effect differs by candidate party.
- **Split-sample-by-party fits** (`fit_group_models` helper, new): fits the base spec separately for
  Republican-candidate and Democrat-candidate observations -- the more interpretable companion,
  comparable directly to the existing peak-location figures. `party` becomes constant within each
  subset and fixest will drop it with a NOTE; expected, not an error.
- Both added for all four favorability variants (cyclemean/entry/election-day/weighted) and both
  samples, following the same `FAVORABILITY_VARS` pattern as everything else. REVERT comments at
  each new block.

**Verified without running the expensive fit**: wrote a standalone check
(not committed -- scratchpad only) that rebuilds the same formula-building functions, calls
`as.formula()` on all four variants' triple-interaction RHS, and confirms via `terms()` that each
produces exactly the expected 28 terms with no duplication (e.g. `favorability:party:subsec_GOP`
appears once, not accidentally multiplied by the pre-existing `subsec_GOP * party` two-way term).
Also confirmed every referenced column (`subsec_partisan_score`-derived, `party`, `incumbency`,
`category`, `state`, `year`, all four favorability variants and their `_sq` terms) exists in
`cand_model_data.RDS`, and that `party` takes exactly the two expected values (`REPUBLICAN`,
`DEMOCRAT`). Actual fitting deferred to the same memory-constrained Phase 5 step as everything else.

**What the three possible outcomes would mean** (from earlier conversation, still the framing to
use once results come back): own-party-only effect confirms the "buying elections for their own
team" story cleanly; symmetric-across-both-parties suggests sector alignment proxies general
political salience rather than a directional partisan mechanism; opposite-party effect would point
to a hedging/insurance story instead, requiring a different theoretical framing.

### Correction: comment 1's triple interaction belongs in partisan_model2.R, not (only) partisan_model3.R

User caught this while reviewing on a separate machine: the measure that actually feeds the paper's
Table 1-3 (continuous hinge-split GOP/DEM scores + categorical bins, both present) is
`partisan_model2.R`'s `singlename_*` variables -- `singlename_partisan_pre` (discrete: Other/GOP/DEM)
and `singlename_GOP_pre`/`singlename_DEM_pre` (continuous, `pmax(singlename_score_pre, 0)` /
`pmax(-singlename_score_pre, 0)` -- the same ReLU/hinge-split construction as `partisan_model3.R`'s
subsector/industry measures, confirming these two scripts share the same construction pattern but
represent different underlying scores). Earlier guess (this log, "Correction: comment 1's triple
interaction...") that `partisan_model3.R`'s subsec/ind measures were the main Table 1-3 measure was
wrong -- that ambiguity was flagged as unresolved back in the original paper review (see the
"sector vs. subsector vs. industry naming" note), and this resolves it: `partisan_model2.R` is the
one that matters for the reviewer's comment.

Added the identical pattern to `partisan_model2.R`: `rhs_snp_full3` (categorical triple interaction),
`rhs_sncp_full3` (continuous triple interaction), `fit_group_models` helper, and split-sample-by-
party calls on `rhs_snp_base`/`rhs_sncp_base`. Verified via the same standalone formula-parsing check
as `partisan_model3.R`: 27 terms, exactly the intended 4 three-way terms present once each (for all
three favorability variants), and `singlename_score_pre`/`singlename_partisan_pre`/`party` all exist
in `cand_model_data.RDS`.

**Left `partisan_model3.R`'s version in place** (not removed) -- it's still a valid check for the
subsector/industry measures, just not confirmed to be what's reported in the paper's main tables.
Open question for the user: keep both, or is `partisan_model3.R`'s measure not used in the paper at
all (in which case its triple-interaction addition, and possibly the whole script's relevance, is
moot for this reviewer-response track)?

### Comment 5b: theory-data aggregation gap (task #15, firm x cycle FE check built and test-verified)

The reviewer's deeper point (beyond the "at other times" wording, task #14): the theory (Appendix A)
is a per-candidate, independent decision rule with no budget constraint; real firms allocate a
finite PAC budget across a portfolio of candidates in the same cycle. Worked through which
interpretation the theory actually implies (see conversation): the model as literally formalized
*is* the per-candidate marginal-decision framing -- it has no portfolio/adding-up term at all -- so
the existing pooled dyadic logit is a faithful econometric counterpart to the theory as written, not
a departure from it. The open question is whether that abstraction (no budget constraint) survives
contact with reality.

Standard constrained-optimization logic: a budget-constrained firm's per-candidate choice still
satisfies an independent threshold rule, just with a shared "shadow price" of the budget constraint
added to every candidate's cost *within that firm-cycle*. That shadow price is common across
candidates for the same firm in the same cycle, so it should be fully absorbed by firm x cycle fixed
effects. If the inverse-U survives with firm x cycle FE, that's direct evidence the per-candidate
margin is real net of whatever budget pressure the firm faced that cycle -- not proof the budget
constraint doesn't exist, but evidence the separable/additive-objective assumption implicit in the
theory isn't obviously wrong.

Built `scripts/analysis/logit/firm_cycle_fe_check.R`: fits the baseline inverse-U (favorability +
favorability_sq only -- NOT the sector-alignment interactions, since sector alignment is
firm-time-invariant and would be collinear with firm, let alone firm x cycle, fixed effects) with
`| cmte_id^year + state` fixed effects (moved `state` into the FE slot too; dropped
private/foreign/log(firm_cash)/category/factor(year), all firm-cycle-invariant and would just be
auto-dropped by fixest as collinear with the FE anyway). Both samples, all three favorability
variants, same two-way clustering as everywhere else.

**Column-naming gotcha hit and fixed**: `cand_model_data.RDS` has no column literally called
`cycle` -- it's renamed to `year` early in `HouseCandData.R` and `cycle` itself isn't retained in
the final `select()`. First attempt used `cmte_id^cycle` and failed with "variable 'cycle' ... not
in the data set"; fixed to `cmte_id^year` throughout (code and comments) and noted explicitly in the
script's docstring so it doesn't trip up again.

**Test-fit result (subsample only, not the definitive answer)**: fit on a 549,449-row subsample (all
249,449 contribute==1 rows + a random 300,000 of the contribute==0 rows, to keep it fast and light
while not being all-zeros) with 8,365 firm x year FE groups + state FE. Ran in **1.9 seconds** --
very promising for the full-scale run's feasibility. Coefficients: favorability = 0.409 (SE 0.017,
p<2.2e-16), favorability_sq = -0.111 (SE 0.005, p<2.2e-16) -- same sign pattern (positive linear,
negative quadratic) and closely comparable magnitude to the paper's existing Table 1 continuous-
measure baseline (0.423 / -0.094). Strongly suggestive the inverse-U is not an artifact of ignoring
the budget constraint, but this is a subsampled sanity check, not the full-N result -- the full fit
still needs to run wherever there's enough memory, same as everything else in Phase 5.

**Still needed for task #15**: the scope-statement paragraph for the paper (per-candidate framing is
intentional and standard in this literature; acknowledge the budget-constraint abstraction; cite the
constrained-optimization argument for why it's defensible; point to this check as the test of that
specific claim). Not yet drafted.
