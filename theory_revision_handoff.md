# Theory Revision & Empirical Heterogeneity — Session Handoff

**Purpose of this document:** a complete, self-contained summary of an extended collaborative session
working on the paper *"Buying Access or Buying Elections? Sectoral Partisan Alignment and Corporate PAC
Contributions under Electoral Uncertainty"* (Harry He, draft dated 2026-05-26, PDF at
`Buying Access or Buying Elections_20260622.pdf` in this directory). Written so a fresh Claude Code
session (with no memory of the conversation that produced it) can pick up the work without re-deriving
anything below. Read this whole file before doing new analysis — several dead ends and statistical traps
are documented here specifically so they aren't repeated.

---

## 1. Where the paper stands

The paper's core theory (Section 3 + Appendix A) models a single firm deciding whether to contribute to
a candidate with win probability `p`. Contributing costs `c(p)`, yields benefit `B(p)` if the candidate
wins, and penalty `λ(p)` if they lose. Four assumptions on `B`, `c`, `λ` (Appendix A) imply:

- **Proposition/Implication 1 (Entry threshold):** a cutoff `p* ∈ (0,1)` below which firms don't contribute.
- **Proposition/Implication 2 (Single-peaked incentive):** conditional on entry, contribution incentive is
  an inverse-U (concave) function of `p`, empirically estimated as a quadratic in `favorability`
  (`favorability + favorability_sq`, roughly a -4-to-+4 scaled proxy for `p`).
- **H1:** firms favor intermediate-to-high-probability candidates over both longshots and safe locks.
- **H2:** sectoral partisan alignment shifts the peak toward lower `p` (more risk tolerance).
- **H3:** alignment reduces weight on incumbency, increasing willingness to back challengers.

This session's work was triggered by the user's realization: *"the formal model just talks about a
one-firm-one-candidate interaction dynamic; if I want to say the story depends on industry AND
incumbency (two distinct types of activity — election-buying and access-retaining), I need to be more
explicit in the theory section."* Everything below is the empirical exploration and theory-repair work
that followed.

---

## 2. Key definitions used throughout (IMPORTANT — not the same as the paper's existing `singlename_partisan_pre`)

For this session's exploratory work, "aligned" firms were redefined more narrowly than the paper's
existing categorical variable, based on user's suspicion that `singlename_partisan_pre`'s DEM bucket
(Consumer Products + Renewables) is contaminated by a possibly-mis-scored Consumer Products firm:

```r
firm_lean = case_when(
  category %in% c("Materials", "Fossil Fuels", "Industrials") ~ "GOP-leaning",
  category == "Renewables"                                    ~ "DEM-leaning (Renewables only)",
  TRUE                                                         ~ "Other/no-lean"
)
co_partisan = case_when(
  party == "REPUBLICAN" & firm_lean == "GOP-leaning"                    ~ 1,
  party == "DEMOCRAT"   & firm_lean == "DEM-leaning (Renewables only)"   ~ 1,
  TRUE ~ 0
)
```

`category` → `singlename_partisan_pre` / `singlename_score_pre` mapping (full reference table):

| category | partisan_pre | score_pre |
|---|---|---|
| Renewables | DEM | −0.997 |
| Consumer Products | DEM | −0.498 |
| Industrials | GOP | 0.727 |
| Fossil Fuels | GOP | 0.848 |
| Materials | GOP | 0.982 |
| Healthcare, Utilities, Real Estate, Transportation, Chemicals, Automobile, Insurance, Defense, Technology, Finance, Professional Services | Other | (various, weak) |

**Open item:** user is independently re-verifying whether the Consumer Products DEM score (−0.498) is a
construction error. Until resolved, prefer the Renewables-only DEM definition above for any new analysis,
and flag results built on the full `singlename_partisan_pre` DEM bucket as potentially contaminated.

`fav_cut` bins (**diagnostic/exploratory use only — see §4 for why these must never be the basis of a
reported inferential test**):
```r
fav_cut = case_when(
  favorability <= -3 ~ "hopeless",
  favorability <= -1 ~ "longshot",
  favorability <=  1 ~ "competitive",
  TRUE               ~ "favored"
)
```
`incumbency`: `"I"` = incumbent, `"C"` = challenger, `"O"` = open-seat.

---

## 3. Empirical results ledger — what survived, what didn't

All tests below use `cand_model_data.RDS` (~6.75M dyad-level rows), `feglm` logit with
`cluster = ~cmte_id + candidate_id`. State/year fixed effects were used in the main production models but
generally omitted in these smaller exploratory subsample regressions (this is a simplification for speed;
final reported numbers should be re-run with FE + full covariate set — see §7 open items).

### 3.1 Bench-packing (co-partisan non-incumbents) — SUPPORTED, well-powered

GOP-leaning firms fund co-partisan (Republican) challengers/open-seat candidates at significantly
elevated rates vs. an Other-lean-Republican baseline, and — critically — the elevation is *largest for the
weakest candidates*, not flat or driven by easy wins:

- Diagnostic (binned) test: `contribute ~ aligned*fav_cut`, non-incumbents only.
  `aligned:hopeless` = +0.409, **p = 0.027**. (Binned — descriptive only, do not cite as the formal test.)
- **Publication-ready (continuous) test:** delta-method peak-location difference,
  `peak = -favorability/(2·favorability_sq)`, computed on GOP-leaning-co-partisan vs.
  Other-lean-Republican, separately by candidate type:
  - **Challenger: peak shifts 1.695 → 1.504, diff = −0.191, SE = 0.064, p = 0.0027.**
  - **Open-seat: peak shifts 2.509 → 2.197, diff = −0.312, SE = 0.119, p = 0.0086.**
  - Both computed via delta method on the joint covariance of a single fitted model (not by eyeballing
    two separate CIs — see §4.1 for why that matters).

Composition check (share of actual co-partisan-non-incumbent *contributions* going to weak candidates):
GOP-leaning puts 21.6% of such dollars into hopeless+longshot tiers vs. 17.9% for Other-lean-Republican —
real, modest, directionally consistent with the ratio-based tests.

### 3.2 No co-partisan-incumbent rescue — REJECTED (a clean non-finding, report it explicitly)

GOP-leaning firms do **not** show elevated support for their own weak/endangered co-partisan incumbents.
If anything, significantly less than baseline: within incumbents, `aligned:hopeless` = −0.302, **p = 0.026**
(GOP-leaning is *below* Other-lean-Republican specifically at the weak end; tracks baseline closely
elsewhere, main `aligned` effect n.s., p=0.96).

### 3.3 Triple-interaction confirmation: election-buying is a non-incumbent phenomenon

Single regression, `contribute ~ aligned * fav_cut * incumbency_type` (Incumbent vs. NonIncumbent),
GOP-leaning-co-partisan + Other-lean-Republican:

- `aligned:hopeless` (within Incumbent, reference group) = **−0.302, p = 0.026**
- `aligned:hopeless:NonIncumbent` (the triple interaction) = **+0.711, p = 0.0009**
- Net effect for NonIncumbent = −0.302 + 0.711 = +0.409, matching §3.1's standalone estimate almost exactly
  — good internal consistency check.

This is diagnostic/binned, so **also confirmed in fully continuous form**: separate delta-method
peak-difference tests by candidate type (§3.1 numbers) show significant divergence for Challenger
(p=0.0027) and Open-seat (p=0.0086) but a much weaker, borderline result for Incumbent
(diff = −1.090 pooled, or +0.481 restricted to co-partisan-only, p ≈ 0.05–0.06) — see §4.2 for why the
incumbent peak estimate is inherently unstable.

**Trap discovered and worth flagging for future work:** attempting to force Challenger + Open-seat into
one pooled "NonIncumbent" category with a *single shared* continuous quadratic curve **washed the effect
out** (diff = −0.111, p = 0.45) — because challenger and open-seat have genuinely different baseline peak
locations (1.70 vs. 2.51) and forcing a shared curve is itself a specification error. **Keep candidate
types as separate models; don't pool them for the sake of a single triple-interaction coefficient.**

### 3.4 Out-party incumbent "insurance" — real but different shape than expected

For OUT-PARTY (Democrat) incumbents targeted by GOP-leaning vs. Other-lean-Republican... (Other-lean-Democrat
comparison, i.e. GOP-leaning firms' Democrat-incumbent targets vs. baseline firms' Democrat-incumbent targets):

- Continuous quadratic: baseline is **U-shaped** (`favorability_sq` = +0.0127, convex — avoids the
  moderately-positioned middle, elevated at both extremes). GOP-leaning's curve is significantly *more
  concave* (`aligned:favorability_sq` = −0.0347, **p = 0.026**), implying a real single interior peak
  around favorability ≈ −0.35 rather than baseline's bimodal U.
- Binned specificity test (diagnostic): `aligned:competitive` = **+0.570, p<0.001** (real elevation at the
  *moderately*-contested tier); `aligned:hopeless` = −0.680, p=0.136 (n.s., wrong sign even) — **the
  elevation is NOT at the extreme/hopeless end**, contradicting an initial "rescue the weakest" reading.

**Theoretical resolution (see §5):** an insurance/hedging value shouldn't be monotonically increasing as
danger increases — it should itself be single-peaked, highest at *moderate* risk. You don't buy insurance
on a house that already burned down. A near-hopeless out-party incumbent isn't worth spending relationship
capital on (you're losing that relationship regardless); a genuinely contested one is where preserving
optionality has real expected value. This is the *same* value-under-uncertainty logic as Assumption 1,
applied to a hedging motive instead of a portfolio motive — not a new, unrelated assumption.

**Specificity checks (important, partially resolved, partially open):**
- GOP-leaning's competitive-tier bump does **not** appear for GOP-leaning's own co-partisan (Republican)
  incumbents (`aligned:competitive` = −0.077, p=0.42, n.s.) — confirms the pattern is specific to
  cross-party targeting for GOP-leaning, not a general trait. Clean result.
- **BUT** Renewables shows a significant competitive-tier bump for its *own* co-partisan (Democrat)
  incumbents instead (`aligned:competitive` = +1.007, **p=0.0014**). The pattern does not mirror
  symmetrically: for GOP-leaning it's an out-party phenomenon, for Renewables it appears to be a
  co-partisan phenomenon. **Unresolved — see §7 open items** (hypothesis: Renewables' pool of co-partisan
  Democrat incumbents may be systematically less "safe"/more genuinely competitive than GOP-leaning's
  pool of Republican incumbents — not yet checked directly).

### 3.5 Renewables — small-sample reality check (do not over-read these cells)

Renewables (24 firms total) has an overall giving propensity of 0.86%, vs. 2.86% (GOP-leaning) and 3.63%
(Other-lean) — raw cross-group rate comparisons are confounded by this and should use within-group
normalization or regression interactions, not raw ratios.

**Renewables targeting out-party (Republican) incumbents is literally untestable at the weak end:**
0 contribution events out of 33 dyads (hopeless) and 0 out of 74 dyads (longshot). Any regression
coefficient here (e.g. an early attempt produced `aligned:hopeless` = −6.7 to −8.7, absurdly large) is a
quasi-complete-separation artifact, not a real effect. **Always print raw cell counts (n dyads, n events)
before trusting an interaction coefficient in any Renewables subsample split this fine.**

### 3.6 The "why fund hopeless challengers instead of rescuing contestable incumbents" puzzle — resolved

Raised by the user: a pure "maximize expected seats for my party" firm should prefer a *contestable*
troubled incumbent (a seat genuinely in play) over a *hopeless* challenger (near-zero win probability
regardless of the marginal dollar). Yet GOP-leaning shows the opposite pattern. Resolution (not yet written
into the paper — see §5 and §6):

**Marginal-impact / crowding-out argument.** A troubled incumbent is, by construction, a race the party
establishment has already flagged as important — institutional/leadership-PAC/national-committee money
floods in specifically because it's recognized as at-risk. A firm's capped, small PAC check there is one
drop in an already-large bucket (low marginal impact, high crowding). A hopeless challenger is exactly the
kind of race mainstream money ignores — the counterfactual funding level is thin, so the same capped
check buys much more marginal consequence and goodwill (the candidate remembers who showed up when the
smart money didn't). This is a sharpened version of the paper's own Assumption 1 (`B'(p) ≤ 0`, "the cost
of waiting is positive... early support is more valuable when uncertain") — consequentiality should be
tied to the *firm's own marginal* impact, not just the race's raw probability, and marginal impact and
raw probability move in opposite directions across race types.

**Directly testable, not yet run:** if you have (or can construct) a proxy for total corporate PAC money
received per candidate-cycle (even summed across firms in this dataset), the prediction is: troubled
incumbents should show systematically higher total PAC receipts than hopeless challengers at a comparable
favorability level. Confirming this would give direct empirical support for the mechanism rather than an
ex post rationalization.

**This also naturally explains why the money looks categorically different from institutional/party
money**, tied to contribution limits: a corporate PAC's capped check is too small to plausibly move a
*competitive* race's outcome regardless of target — so *where* a firm chooses to spend a small, fixed-size
check is diagnostic of motive (relationship-investment) rather than capacity to swing an outcome. Party
committees/leadership PACs, operating at a scale where targeting the closest races is a coherent
seats-maximizing strategy, would not be expected to show this same "fund the neglected long-shot" pattern.
**User specifically wants this contrast (small-check corporate PAC money vs. large-check institutional
money) drawn out explicitly in Section 3 — see §6.**

---

## 4. Methodological traps discovered this session (read before running more tests)

### 4.1 Never compare two individual/marginal confidence intervals for "overlap" to test whether they differ

This was an actual mistake made and caught mid-session. Two point estimates from the *same* regression
(e.g., `peak_baseline` and `peak_gop_leaning`) are correlated — they share underlying coefficients — so
their individual, marginal 95% CIs can overlap substantially even when their **difference** is highly
significant. Always compute the delta-method SE of the difference directly, using the joint gradient
against the full coefficient vector and the model's `vcov()`. Concretely:
```r
g_diff <- g_treatment - g_baseline   # gradients of each derived quantity wrt every coefficient
se_diff <- sqrt(t(g_diff) %*% V %*% g_diff)
z <- diff / se_diff
```
This exact mistake, when corrected, flipped "no story" into p=0.0027 and p=0.0086 for the challenger and
open-seat peak-shifts (see §3.1) — do not repeat the marginal-CI-overlap heuristic anywhere else in the
paper; it's worth auditing the existing draft for the same error.

### 4.2 Peak location (`-b1/(2·b2)`) is numerically unstable when curvature (`b2`) is near zero

Incumbent-directed giving is close to flat in favorability for *everyone* (small `favorability_sq` in
every group, an order of magnitude smaller than for challengers/open-seat) — consistent with access-value
being already banked and not sensitive to exact electoral risk. But dividing by a small, noisily-estimated
`b2` to locate a peak is unstable; small perturbations swing the ratio wildly (observed 95% CI for one
incumbent peak estimate: [−1.34, 1.56], wider than the entire meaningful range). **Don't lean on a "peak
location" statistic for incumbents as a headline claim.** If an incumbent-specific claim is needed, report
the raw slope/curvature coefficients directly (well-identified) or predicted-probability curves across the
favorability range, not the derived peak ratio.

### 4.3 Discretizing a continuous variable into researcher-chosen bins is a real reviewer risk

Raised directly by the user mid-session ("I am afraid this will not be accepted in top journals") and is
correct. The `fav_cut` bins used throughout §3 were useful for *diagnosing* where in the distribution an
effect concentrates (turning an abstract "peak shifted by 0.19" into "this is about hopeless-tier
candidates specifically"), but **should never be the basis of a reported inferential test** — cutpoints
chosen after looking at the data are exactly what a reviewer flags as researcher degrees of freedom.

**The fix already exists and requires no new bins:** every one of the headline findings in §3.1 and §3.3
is separately confirmed via the fully continuous quadratic specification (`favorability + favorability_sq`
interacted with `aligned` and/or `incumbency_type`), using the same delta-method machinery as §4.1. Use
those numbers in the paper. If a nonparametric robustness check is wanted for the reviewer who doesn't
trust a quadratic, use **deciles** (a standard, non-cherry-picked convention) or a spline/GAM overlay on
the fitted quadratic — not ad hoc threshold bins. This was proposed but not yet built (§7).

### 4.4 Complete/quasi-complete separation in thin subsample cells

Always print raw `n dyads` / `n contribution events` per cell before trusting any regression coefficient
in a subsample split fine enough that some cells could be near-zero-event. Coefficients like −6.7 or −8.7
in a logit are almost always this artifact, not a real effect, even when they arrive with a deceptively
normal-looking SE. Renewables' small sample (24 firms) makes this a recurring risk for any split finer than
"co-partisan vs. out-party incumbent, pooled across favorability."

### 4.5 Raw cross-group rate ratios are confounded by differing overall giving propensity

Renewables' overall giving rate (0.86%) is far below GOP-leaning (2.86%) and Other-lean (3.63%) — a raw
`rate_A / rate_B` comparison conflates "does group A target weak candidates disproportionately" with
"group A just gives less/more overall." Use within-group normalization (`rate_in_bin / group's own
overall rate`) or, better, a proper regression interaction test (`aligned × fav_cut` or continuous
equivalent), which nets out the main-effect level difference automatically.

### 4.6 ntile()-based quantile binning breaks on bimodal variables

`favorability` is heavily bimodal for challengers — over 2.4M of ~3.5M challenger-dyads sit at exactly
−4, another large mass at +4. `ntile(favorability, 4)` produced three "quartiles" that were all
identical to −4. Use fixed substantive cutoffs (or better, avoid bins entirely per §4.3) rather than
quantile-based bins on this variable.

### 4.7 Communicating a "small-looking" coefficient's magnitude

A peak-shift of −0.19 to −0.31 on an 8-unit (−4 to +4) scale reads as trivial to a reader, even when
p<0.01. Two ways to reframe, with real numbers already computed (Republican challengers, GOP-leaning vs.
Other-lean, predicted probability from `peak_ci_incumbency_mod.RDS`):

- **SD-standardized:** both shifts (challenger and open-seat) work out to ≈0.091 SD of favorability in
  their respective populations — a small-to-modest effect size by Cohen's-d convention; worth mentioning
  but not leading with.
- **Predicted-probability ratio (lead with this):** GOP-leaning firms are **~2.6×–3.7× as likely** as an
  otherwise-identical Other-lean firm to fund a Republican challenger, across the viability range — and
  the ratio is *largest* at the hopeless end (3.69× at favorability=−4) and *smallest* at the safest end
  (2.59× at favorability=+4). At the two estimated peak locations specifically: predicted probability
  ≈1.6% (baseline) vs. ≈4.8% (GOP-leaning), a ~2.9–3.0× ratio. **This is the number to lead with in the
  paper — "three times as likely, and even more so for genuine long-shots" — not the raw peak-location
  shift.** Recommended: a figure with two predicted-probability curves (GOP-leaning vs. Other-lean) against
  favorability, holding other covariates at representative values — visually shows both the vertical gap
  (level effect) and the leftward peak-shift together.
  - **Not yet done:** the same probability-ratio translation for the open-seat result and for the
    out-party-incumbent "competitive tier" finding — flagged as next step, see §7.

---

## 5. Theory revision plan (Section 3 + Appendix A)

### 5.1 The 2×2 hypothesis-competition framework (current organizing structure — present this explicitly as an ex ante competition, not a single story arrived at post hoc)

| | Election-buying hypothesis | Access-buying hypothesis |
|---|---|---|
| **Incumbents** | H-inc-1: rescue weak co-partisan incumbents — **REJECTED** (§3.2) | H-inc-2: support moderately-strong incumbents, any party — **SUPPORTED**, extends cross-party (§3.4) |
| **Challengers/Open-seat** | H-chal-1: bench-pack weak co-partisan long-shots — **SUPPORTED**, well-powered (§3.1, §3.3) | H-chal-2: strategic investment in likely future winners, any party — **not what's driving aligned firms** (their non-incumbent money is overwhelmingly co-partisan and skewed weak, not party-blind and skewed strong); **whether this is the *non-aligned* firms' default story is the one open gap** (§7) |

**Resolved diagonal:** partisan-aligned firms are access-oriented toward incumbents (even cross-party) but
election-buying-oriented toward co-partisan challengers/open-seat — not the alternative diagonal
(rescue-your-own-incumbent + party-blind-strong-challenger-investing), and not a mixed/unclear reading.
State explicitly in the paper that one hypothesis from each cell was tested and rejected, leaving this
specific diagonal — this is a stronger rhetorical structure than presenting only the surviving story.

### 5.2 Formal decomposition of `B_i(p)` (extends Appendix A)

Split the firm's benefit function into three additive components, each keyed to a different observable
of the candidate `D`:

```
B_i(p; party_D, incumbent_D) =
    A(incumbent_D)                                    [access value]
  + S_i(p) · 1{party_D = firm's aligned party}         [partisan-stake / portfolio value]
  + H_i(p) · 1{party_D ≠ firm's aligned party, incumbent_D}   [cross-party insurance/hedging value]
```

- **`A(incumbent_D)`:** large and roughly flat in `p` when `D` is an incumbent (relationship/access value
  from an already-held office — not a bet on a future relationship); near zero for non-incumbents. This is
  what makes incumbent-directed curves flat for everyone regardless of alignment (§3.2, §4.2).
- **`S_i(p) · 1{co-partisan}`:** front-loaded toward lower `p` for firms in partisan-advantaged sectors —
  this is where H2's original peak-shift content lives, now scoped specifically to non-incumbents. This is
  the well-supported bench-packing mechanism (§3.1).
- **`H_i(p) · 1{out-partisan, incumbent}`:** **must be single-peaked in `p`, centered at moderate risk —
  NOT monotonically increasing as danger increases.** (Original draft of this term assumed monotonic
  increase toward `p→0`; §3.4's data corrected this — the elevation concentrates at "competitive," not
  "hopeless.") The insurance-value logic: you don't buy insurance on a house that's already burned down;
  value is highest under genuine uncertainty about whether the relationship survives, which is the *same*
  value-under-uncertainty logic as Assumption 1, not a qualitatively different assumption for a different
  population.

This decomposition is not just descriptive scaffolding — each piece has a specific, already-tested
empirical signature (§3.1–§3.4), and the `H_i(p)` single-peaked-not-monotonic correction is itself a
direct, falsifiable improvement over the first draft of this term (which would have predicted the wrong
shape).

### 5.3 New/revised hypotheses

- **H4:** Alignment's peak-shift (H2) and incumbency-discounting (H3) effects concentrate in non-incumbent
  races. Among incumbents, behavior is uniformly access-oriented regardless of alignment or
  co-partisanship; among non-incumbents, alignment's risk-tolerance effect is present for co-partisan
  candidates specifically. **Well-supported** (§3.1, §3.3).
- **H5 (weaker, flag as such):** Among out-party incumbents, aligned firms show more interest in
  *moderately* (not extremely) endangered candidates than unaligned firms — a hedging motive that peaks at
  genuine uncertainty. **Supported for GOP-leaning; the Renewables mirror shows the analogous bump but on
  the co-partisan side instead — the cross-sector symmetry claim is not yet resolved (§3.4, §7).**
- **Explicit non-result to state up front (preempt a reviewer finding it first):** no evidence that aligned
  firms rescue their *own* endangered incumbents at elevated rates — if anything the opposite (§3.2). Worth
  a sentence explaining why: own-side incumbents are already the safest bet (no insurance motive, since
  there's no risk of losing that specific relationship in the same sense) and funding your own weak
  incumbent doesn't buy incremental party control the way funding an *additional* challenger does.

### 5.4 Defending the inverse-U abstraction (user specifically asked for help on this)

Reviewer objection to anticipate: *"you assumed an inverse-U and found one."* Response, in two parts:

1. **Single-peakedness is a derived implication (Appendix A, Assumptions 1–4), not an assumed shape.** The
   quadratic-in-`p` specification is the *minimal* functional form flexible enough to nest a monotonic
   increasing curve, a monotonic decreasing curve, a single interior peak (concave), **or a U-shape
   (convex)** as special cases — concavity was never forced by construction.
2. **The model was NOT gerrymandered to only find concavity — it found the opposite sign where the theory
   doesn't commit to concavity.** The out-party-incumbent baseline curve (§3.4) came back significantly
   *convex* (U-shaped, `favorability_sq` > 0) using the exact same specification that returns concave
   curves elsewhere. That's the strongest evidence the functional form is agnostic and the concavity found
   in challenger/open-seat/GOP-leaning-out-party-incumbent populations is a real, tested finding rather than
   a foregone conclusion.
   - Frame the one apparent "counterexample" (Other-lean, out-party incumbent, U-shaped) as informative,
     not threatening: a U-shape in a pooled, unaligned-firm subsample is what you'd expect from mixing
     heterogeneous firm motives (some pure committee/access-farmers rising monotonically with safety, some
     with residual hedging motives rising again at the dangerous end) that the paper's own heterogeneity
     design is built to separate. Aggregating across heterogeneous agents can produce a shape no individual
     agent's curve has — a standard aggregation point, not a model defect. Suggest framing as "the
     single-peaked prediction is conditional on a reasonably homogeneous firm population; the one slice
     with a violation is also the slice with the most left-over unmodeled heterogeneity (non-aligned firms
     lumped together) — a natural direction for future work."
3. **Recommended addition (not yet built):** a nonparametric robustness check — binned-decile scatter of
   actual contribution rate vs. fitted quadratic overlay, or a GAM/spline fit, for the pooled sample and
   separately for challengers/open-seat. Standard, cheap, and preempts "why should I believe a quadratic"
   with a picture. Use deciles, not ad hoc threshold bins (§4.3).

### 5.5 Institutional money contrast (user's sharpest point this session — draft this explicitly)

Corporate PAC contributions are capped at a size too small to plausibly move a *competitive* race's
outcome regardless of target. This means the choice of *where* to spend a small, fixed-size check reveals
motive rather than capacity to swing outcomes. Institutional money (leadership PACs, party committees),
operating at a scale where targeting the closest/most flippable races is a coherent expected-seats-
maximizing strategy, would not be expected to fund neglected long-shots. Finding that small-check corporate
PAC money *does* disproportionately fund hopeless co-partisan long-shots (§3.1, §3.6) is therefore evidence
this behavior is categorically different from — not a smaller version of — what institutional money does;
it's better understood as a relationship/loyalty investment that only makes sense once the size constraint
is taken seriously. **Draft this as an explicit contrast paragraph in Section 3**, tied directly to the
crowding-out mechanism in §3.6.

---

## 6. Presentation/effect-size plan (in progress, user wants to keep brainstorming this)

Session ended mid-brainstorm on "how to pack more weight behind the punch" for presenting effect sizes.
Established so far (§4.7): lead with predicted-probability ratios (2.6×–3.7×), not raw peak-shift units;
SD-standardization is a secondary/supporting number. **Explicitly flagged as unfinished — user wants to
keep exploring more ways to present this.** Ideas not yet tried, worth raising with the user next session:
- Same probability-ratio translation applied to open-seat and out-party-incumbent-competitive-tier results
  (mechanically straightforward extension of the code in §4.7, not yet run).
- A single combined figure (predicted-probability curves, GOP-leaning vs. Other-lean, for
  challenger/open-seat/incumbent side by side) to let a reader see the whole heterogeneity story in one
  panel.
- Consider expressing effect sizes relative to the estimated entry threshold `p*` (i.e., what fraction of
  the "decision-relevant" range between entry and certainty does the shift represent), which ties the
  effect size back to the paper's own theoretical primitives rather than an arbitrary external benchmark
  (SD, raw scale). Not yet attempted.

---

## 7. Open items / next steps (in priority order as best understood)

1. **Awaiting user input:** independent re-verification of the Consumer Products continuous score
   (possible construction error) — affects whether the Renewables-only DEM definition (§2) should remain
   the standard going forward, or whether the original `singlename_partisan_pre` DEM bucket can be trusted.
2. **Awaiting user input:** the paper itself, to align theory-section language with whatever revised
   framing the user settles on (mentioned they need to "slightly modify" the theory to fit the story).
3. Resolve the Renewables/GOP-leaning asymmetry in §3.4 (competitive-tier bump on out-party side for
   GOP-leaning vs. co-partisan side for Renewables) — proposed check (not yet run): compare the
   favorability distribution of each group's own co-partisan incumbent portfolio to see if Renewables'
   Democrat incumbents are systematically less safe/more competitive than GOP-leaning's Republican
   incumbents.
4. Test whether H-chal-2 (party-blind strategic investment in likely-winner challengers) is actually the
   *non-aligned* firms' default story — the one identified gap in the hypothesis-competition table (§5.1).
   Baseline's own challenger peak (~1.7 out of a 4 max) is itself only moderately safety-favoring, not
   extreme, so this needs a cleaner test rather than an assumption.
5. Re-run the incumbent-specific peak-shift test properly disaggregated (not force-pooled — see §3.3 trap)
   to get a cleaner read on whether the borderline p≈0.05–0.06 result holds up or should be dropped/
   reframed as "cannot be reliably estimated" (§4.2).
6. Build the nonparametric (decile or spline) robustness figure for the inverse-U functional form claim
   (§4.3, §5.4) — not yet built.
7. Continue the effect-size/presentation brainstorm (§6) — user explicitly wants to keep working on this.
8. Decide (user said "try both a and c, decide later") whether Renewables' results are presented as formal
   subsample regressions with honest wide CIs, or purely descriptively — given how many Renewables cells
   turned out to be zero-event or near-zero-event (§3.5), leaning toward descriptive-only for anything
   finer than the coarsest co-partisan/out-party split, but this is not finalized.
9. Once theory language is settled, draft actual Section 3 / Appendix A prose (the `A`/`S`/`H`
   decomposition, H4/H5 statements, institutional-money contrast paragraph, inverse-U defense paragraph) —
   **no paper source file (.tex/.docx) has been located in this directory; only the PDF exists.** Ask the
   user where the editable source lives, or whether this markdown file's content should simply be adapted
   by hand into whatever format they're using.
10. Audit the existing paper draft for any other place that compares point estimates via CI-overlap
    eyeballing (§4.1) rather than a proper difference test — this was only checked for the new analyses
    produced this session, not for pre-existing content in the PDF.

---

## 8. Technical notes for reproducing this session's work

- Data: `/htaa/hhe/projects/election_buying/cand_model_data.RDS` (~6.75M rows) and
  `cand_model_data_election_year.RDS`. Columns used: `category`, `party`, `favorability`, `favorability_sq`
  (derived), `incumbency`, `contribute`, `contribute_amount`, `singlename_score_pre`,
  `singlename_partisan_pre`, `cmte_id`, `candidate_id`, `firm_cash`, `state`, `year`, `same_state`,
  `special`, `private`, `foreign`.
- All exploratory scripts for this session live in a session-specific scratchpad directory that will
  **not** persist to a new session — re-derive from the code snippets embedded in this document (§3, §4)
  rather than looking for the original `.R` files.
- **PDF text extraction:** `pdftoppm`/`poppler-utils` are **not installed** on this system and there is no
  sudo access. `pip install --user pypdf` works and was used to extract page-by-page text
  (`PdfReader(...).pages[i].extract_text()`) for reading the paper's theory/appendix sections. The PDF has
  55 pages per pypdf (vs. "16 pages" reported by an earlier page-count estimate — trust pypdf's count).
  Appendix A (the formal model) is on pages 40–44; Section 3 (theory) is on pages 8–13.
- Saved model object from this session, if the scratchpad still exists in this session's temp dir:
  `peak_ci_incumbency_mod.RDS` — a `feglm` fit of `partisan_model2.R`'s exact FULL spec (see
  `scripts/logit/partisan_model2.R`, function `rhs_snp_full`), with incumbency left at default
  alphabetical factor order (`C` reference, not releveled) to match the original coefficient file
  `model/all/extensive_partisan_singlename_pre_int_full_coefficients.txt` exactly. If unavailable, refit
  with:
  ```r
  rhs <- paste(
    "favorability + favorability_sq", "special + private + foreign", "same_state + log(firm_cash)",
    "party + incumbency", "singlename_partisan_pre",
    "(favorability + favorability_sq) * incumbency",
    "(favorability + favorability_sq) * singlename_partisan_pre",
    "singlename_partisan_pre * party", "singlename_partisan_pre * incumbency", sep = " + ")
  feglm(as.formula(paste("contribute ~", rhs, "| state + year")), data = cand_data,
        family = binomial(link="logit"), cluster = ~ cmte_id + candidate_id)
  ```
- Production scripts (already fixed for data paths, FE convention, coefficient-txt output; unrelated to
  this session's exploratory work but relevant context): `scripts/logit/*.R` and `scripts/tobit/*.R`,
  8 original scripts + `singlename_triple_interaction.R` (logit + tobit versions, the co-partisanship ×
  incumbency triple-interaction specs referenced but not re-litigated this session). Coefficient outputs in
  `model/all/*.txt` and `model/election/*.txt`. RDS model objects are mostly intentionally deleted by the
  user to save disk space (expected, not data loss — see auto-memory `rds_cleanup_by_user.md` if available
  to this session).
