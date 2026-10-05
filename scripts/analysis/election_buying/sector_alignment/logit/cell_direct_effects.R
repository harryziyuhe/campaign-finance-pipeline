library(dplyr)

# =============================================================================
# Direct tests for Cells 1-3 of the 2x2 theoretical framework, addressing the
# user's critique (2026-08-11) that peak-location comparisons are insensitive
# for Cell 3 (bench-packing): the baseline curve is so small at low
# favorability that even a large ODDS-RATIO increase barely moves the
# absolute peak. The fix is to report the odds ratio (aligned vs. baseline,
# same candidate type) across a grid of favorability points directly, rather
# than inferring shape from peak location or curvature alone.
#
#   Cell 1 (no-rescue):   co_partisan_GOP/DEM   vs Other, at Incumbent   -- expect flat ~1 across the whole grid
#   Cell 2 (insurance):   cross_partisan_GOP/DEM vs Other, at Incumbent  -- expect a hump around moderate favorability
#   Cell 3 (bench-pack):  co_partisan_GOP/DEM   vs Other, at NonIncumbent -- expect large OR at low favorability, shrinking toward 1 at high favorability
#
# Built on ASYM_FULLCURVE_NOFE (categorical measure, corrected data), which
# already lets favorability/favorability_sq interact fully with incumbency_bin
# for each alignment-by-party dummy -- reuses the exact coefficient-assembly
# logic from scripts/logit/asymmetric_peak_ci.R.
# =============================================================================
PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")
mod <- readRDS(paste0(OUT_DIR, "ASYM_FULLCURVE_NOFE.RDS"))
cf <- coef(mod); V <- vcov(mod)

delta_method <- function(cf, V, fn, eps = 1e-6) {
  val <- fn(cf); k <- length(cf); grad <- numeric(k)
  for (i in seq_len(k)) {
    cf_up <- cf; cf_up[i] <- cf_up[i] + eps
    cf_dn <- cf; cf_dn[i] <- cf_dn[i] - eps
    grad[i] <- (fn(cf_up) - fn(cf_dn)) / (2 * eps)
  }
  se <- sqrt(as.numeric(t(grad) %*% V %*% grad))
  c(est = val, se = se, ci_low = val - 1.96 * se, ci_high = val + 1.96 * se)
}
g <- function(cf, nm) if (nm %in% names(cf)) cf[[nm]] else stop(sprintf("missing coef: %s", nm))

# log-odds DIFFERENCE from the same-type Other-sector baseline, as a function
# of favorability f, for a given alignment dummy (e.g. "co_partisan_GOP") and
# candidate type ("Incumbent" or "NonIncumbent").
diff_logodds_fn <- function(dummy, type) {
  function(cf) {
    lvl <- g(cf, dummy)
    lin <- g(cf, paste0("favorability:", dummy))
    quad <- g(cf, paste0("favorability_sq:", dummy))
    if (type == "NonIncumbent") {
      lvl  <- lvl  + g(cf, paste0(dummy, ":incumbency_binNonIncumbent"))
      lin  <- lin  + g(cf, paste0("favorability:", dummy, ":incumbency_binNonIncumbent"))
      quad <- quad + g(cf, paste0("favorability_sq:", dummy, ":incumbency_binNonIncumbent"))
    }
    function(f) lvl + lin * f + quad * f^2
  }
}

FAV_GRID <- c(-4, -3, -2, -1, 0, 1, 2, 3, 4)

run_cell <- function(dummy, type, cell_label) {
  rows <- lapply(FAV_GRID, function(f) {
    fn_f <- function(cf) diff_logodds_fn(dummy, type)(cf)(f)
    res <- delta_method(cf, V, fn_f)
    data.frame(cell = cell_label, dummy = dummy, type = type, favorability = f,
               log_or = res["est"], se = res["se"],
               or = exp(res["est"]), or_lo = exp(res["ci_low"]), or_hi = exp(res["ci_high"]),
               p = 2 * pnorm(-abs(res["est"] / res["se"])))
  })
  do.call(rbind, rows)
}

#   Cell 4 (placebo):     cross_partisan_GOP/DEM vs Other, at NonIncumbent -- theory predicts
#     a NULL: an aligned firm has no partisan-stake motive toward an opposing-party candidate
#     and no incumbent relationship to insure, so it should treat opposing-party non-incumbents
#     the way any other firm does. This is the framework's only cell with a predicted null and
#     therefore its cleanest internal placebo; it was omitted from earlier runs.
results <- rbind(
  run_cell("co_partisan_GOP",    "Incumbent",    "Cell 1: no-rescue (GOP co-partisan, Incumbent)"),
  run_cell("cross_partisan_GOP", "Incumbent",    "Cell 2: insurance (GOP cross-partisan, Incumbent)"),
  run_cell("co_partisan_GOP",    "NonIncumbent", "Cell 3: bench-pack (GOP co-partisan, Non-Incumbent)"),
  run_cell("cross_partisan_GOP", "NonIncumbent", "Cell 4: placebo (GOP cross-partisan, Non-Incumbent)"),
  run_cell("co_partisan_DEM",    "Incumbent",    "Cell 1: no-rescue (DEM co-partisan, Incumbent)"),
  run_cell("cross_partisan_DEM", "Incumbent",    "Cell 2: insurance (DEM cross-partisan, Incumbent)"),
  run_cell("co_partisan_DEM",    "NonIncumbent", "Cell 3: bench-pack (DEM co-partisan, Non-Incumbent)"),
  run_cell("cross_partisan_DEM", "NonIncumbent", "Cell 4: placebo (DEM cross-partisan, Non-Incumbent)")
)

write.csv(results, paste0(OUT_DIR, "cell_direct_effects.csv"), row.names = FALSE)
cat("=== Direct odds-ratio effects by cell and favorability ===\n")
print(results, row.names = FALSE, digits = 3)

# Raw cell counts. Per the project's standing rule (thin cells can produce large
# coefficients that are separation artifacts rather than real effects), print
# n dyads / n contribution events for every cell before any of these odds ratios
# are trusted -- especially the two cross-partisan non-incumbent cells added above.
cat("\n=== Raw cell counts (dyads / contribution events) ===\n")
d <- readRDS(paste0(PATH, "cand_model_data.RDS"))
d <- d %>%
  mutate(
    co_partisan_GOP    = as.integer(party == "REPUBLICAN" & singlename_partisan_pre == "GOP"),
    cross_partisan_GOP = as.integer(party == "DEMOCRAT"   & singlename_partisan_pre == "GOP"),
    co_partisan_DEM    = as.integer(party == "DEMOCRAT"   & singlename_partisan_pre == "DEM"),
    cross_partisan_DEM = as.integer(party == "REPUBLICAN" & singlename_partisan_pre == "DEM"),
    incumbency_bin     = ifelse(incumbency == "I", "Incumbent", "NonIncumbent")
  )
counts <- lapply(
  c("co_partisan_GOP", "cross_partisan_GOP", "co_partisan_DEM", "cross_partisan_DEM"),
  function(dm) {
    d %>% filter(.data[[dm]] == 1) %>% group_by(incumbency_bin) %>%
      summarise(dummy = dm, dyads = n(),
                events = sum(contribute == 1, na.rm = TRUE),
                rate_pct = round(100 * mean(contribute == 1, na.rm = TRUE), 3),
                firms = n_distinct(cmte_id), .groups = "drop")
  })
counts <- do.call(rbind, counts) %>% select(dummy, incumbency_bin, firms, dyads, events, rate_pct)
print(as.data.frame(counts), row.names = FALSE)
write.csv(counts, paste0(OUT_DIR, "cell_counts.csv"), row.names = FALSE)

# -----------------------------------------------------------------------------
# Direct co-partisan vs. cross-partisan asymmetry test, on the same odds-ratio
# scale, at each favorability point. Cell 3 minus Cell 4 within candidate type.
# This is the quantity Hypothesis 4 (asymmetry) actually claims: that the
# alignment effect for non-incumbents is LARGER for the firm's own party than
# for the opposing party. Comparing the two cells' individual CIs for overlap
# would be the marginal-CI fallacy; this differences them inside one model.
# -----------------------------------------------------------------------------
cat("\n=== Co-partisan vs cross-partisan asymmetry, Non-Incumbents (Cell 3 - Cell 4) ===\n")
asym_rows <- function(side) {
  co <- paste0("co_partisan_", side); cr <- paste0("cross_partisan_", side)
  do.call(rbind, lapply(FAV_GRID, function(f) {
    fn_f <- function(cf) diff_logodds_fn(co, "NonIncumbent")(cf)(f) -
                         diff_logodds_fn(cr, "NonIncumbent")(cf)(f)
    res <- delta_method(cf, V, fn_f)
    data.frame(side = side, favorability = f,
               log_or_diff = res["est"], se = res["se"],
               or_ratio = exp(res["est"]),
               lo = exp(res["ci_low"]), hi = exp(res["ci_high"]),
               p = 2 * pnorm(-abs(res["est"] / res["se"])))
  }))
}
asym <- rbind(asym_rows("GOP"), asym_rows("DEM"))
print(asym, row.names = FALSE, digits = 3)
write.csv(asym, paste0(OUT_DIR, "cell_asymmetry_test.csv"), row.names = FALSE)

cat("\nDone.\n")
