# Redistricting/Timing Fix — Status

Short checklist view. Full reasoning, numbers, and design decisions are in
[`redistricting-timing-fix-log.md`](redistricting-timing-fix-log.md); this file is just the
scoreboard.

**Goal**: replace the cycle-mean "chance of winning" construction (one rating per race per cycle)
with a contribution-date-matched one (rating as of when the money actually moved, using the correct
map even across redistricting), and propagate it through the modeling pipeline.

## Done

1. **Recovered missing IE data + fixed a district-format bug** — off-year snapshots were being
   silently dropped by the scraper; recovered them, then found and fixed a format mismatch
   (`"PA-17"` vs `"17"`) that affected 40% of the ratings file.
2. **Race-stability diagnostic** (Signal A: incumbent-identity discontinuity; Signal B: structural
   break in rating level) — flags races where a label likely describes two different districts.
3. **50-state map enactment-date table** — pulled from All About Redistricting; gives the exact
   date each state's map became effective, every cycle 2010-2022.
4. **Confirmed mid-decade double-map cases** (FL, NC, PA, VA) using the same table.
5. **Built the contribution-date-matched rating construction** — old-map matching via a race-level
   (not candidate-level) crosswalk, three favorability variants (entry-date, election-day-nearest,
   contribution-weighted), no-lookahead throughout. Wired into `HouseCandData.R` and all model
   scripts.
6. **Pre-election-year sample given its own parallel construction** (same logic, filtered to the
   pre-Election-Day contribution window).
7. **Propagated the variant pattern to all logit scripts** (`partisan_model1-3.R`,
   `reputation_model.R`) — each now fits cycle-mean/entry/election-day, both samples.
8. **Propagated to both Tobit scripts** (`partisan_model1-2.R`) — each now fits
   cycle-mean/weighted, both samples.

All 8 R scripts touched parse-check cleanly. Every change has an explicit `# REVERT:` comment
showing how to get back to the original single-spec behavior.

## Remaining (redistricting/timing fix)

1. **Rebuild downstream pipeline and re-estimate models** — actually run the fits (blocked on
   memory here; each logit script now fits ~3x as many models, each Tobit script ~2x). Needs to
   happen wherever there's enough RAM, then compare the favorability variants against the original
   results.
2. **Structural-lean placebo measure + validation writeup** — build an independent, non-IE-based
   competitiveness proxy (e.g. prior presidential vote share) as a robustness check against both the
   timing and reverse-causality concerns; not started.

## Department reviewer comments (new, separate track)

3. **Candidate-party asymmetry — implemented in both scripts, not yet run.** Originally added to
   `partisan_model3.R` (subsec/ind measures); corrected once the user caught it, since the measure
   that actually feeds the paper's Table 1-3 is `partisan_model2.R`'s `singlename_*` variables
   (continuous ReLU-style hinge-split + discrete/categorical) — added the same triple-interaction +
   split-sample-by-party pattern there too. Verified formulas parse and all referenced columns
   exist in both scripts. **Open question**: is `partisan_model3.R`'s subsec/ind version actually
   used in the paper, or should it be dropped from this track? Actual fitting deferred to the same
   memory-constrained Phase 5 step as everything else above.
4. **Document/verify clustering level** — state clustering (two-way, cmte_id + candidate_id)
   explicitly in the paper text; consider robustness to alternative clustering choices.
5. **Sharpen novelty vs. Knight (2006) / Jayachandran (2006)** — rewrite intro/lit review to cite
   both explicitly and state the contribution precisely (market-implied exposure predicts *where*
   in the risk distribution a firm concentrates giving and incumbency weighting, not just partisan
   exposure itself). Writing only.
6. **Intro wording fix** — "at other times" implies firms do access-buying OR election-buying at a
   given time, when a firm can do both simultaneously across its portfolio. Minor.
7. **Theory-data aggregation gap — firm x cycle FE check built and test-verified, scope-statement
   writing still needed.** Theory (Appendix A) is literally a per-candidate independent-decision
   rule with no budget constraint -- confirmed the existing pooled logit is already the faithful
   econometric counterpart, not a departure. Built `scripts/analysis/logit/firm_cycle_fe_check.R`,
   which nets out a firm-cycle's budget "shadow price" via `cmte_id^year` fixed effects (tests
   Hypothesis 1 only, not the sector-heterogeneity interactions). Subsample test fit (549k rows,
   1.9 sec): favorability = 0.409, favorability_sq = -0.111, both p<2.2e-16 -- same sign and close
   magnitude to the paper's existing Table 1 baseline (0.423 / -0.094). Full-N fit still pending
   (Phase 5 memory constraint). Scope-statement paragraph for the paper not yet drafted.
