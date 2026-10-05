library(dplyr)

# =============================================================================
# Peak-location CIs for the new asymmetric (co-partisan vs. cross-partisan)
# battery -- task #13, docs/theory_revision_handoff.md §10.2/§10.5. Reuses the
# generic numerical-gradient delta method from
# scripts/logit/sector_alignment_peak_ci_and_hopeless_test.R (never compare
# two marginal CIs for overlap -- §4.1).
#
# Two model families:
#   1) ASYM_BASE_CATEGORICAL / ASYM_BASE_CONTINUOUS (Table 2 analog, no
#      incumbency split) -- one peak per curve (Other/baseline, co_GOP,
#      cross_GOP, co_DEM, cross_DEM).
#   2) ASYM_FULLCURVE_NOFE (Table 4) -- peaks by Incumbent vs NonIncumbent for
#      each of the same 5 curves, since favorability/favorability_sq are
#      fully interacted with incumbency_bin there.
# =============================================================================
PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")

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
peak_fn <- function(lin, quad) -lin / (2 * quad)

flag_range <- function(est) if (est < -4 || est > 4) "OUT-OF-RANGE" else ""

# =============================================================================
# 1) Table 2 analog (baseline, no incumbency split)
# =============================================================================
run_base_table <- function(cf, V, measure_label, suffix) {
  curves <- list(
    Other      = list(lin = "favorability", quad = "favorability_sq"),
    co_GOP     = list(lin = c("favorability", "favorability:co_partisan_GOP"),
                       quad = c("favorability_sq", "favorability_sq:co_partisan_GOP")),
    cross_GOP  = list(lin = c("favorability", "favorability:cross_partisan_GOP"),
                       quad = c("favorability_sq", "favorability_sq:cross_partisan_GOP")),
    co_DEM     = list(lin = c("favorability", "favorability:co_partisan_DEM"),
                       quad = c("favorability_sq", "favorability_sq:co_partisan_DEM")),
    cross_DEM  = list(lin = c("favorability", "favorability:cross_partisan_DEM"),
                       quad = c("favorability_sq", "favorability_sq:cross_partisan_DEM"))
  )
  rows <- list()
  for (nm in names(curves)) {
    lin_terms <- curves[[nm]]$lin; quad_terms <- curves[[nm]]$quad
    lin_fn <- function(cf) sum(sapply(lin_terms, function(t) g(cf, t)))
    quad_fn <- function(cf) sum(sapply(quad_terms, function(t) g(cf, t)))
    peak_f <- function(cf) peak_fn(lin_fn(cf), quad_fn(cf))
    res <- delta_method(cf, V, peak_f)
    rows[[nm]] <- data.frame(measure = measure_label, curve = nm,
                              peak = res["est"], se = res["se"],
                              ci_low = res["ci_low"], ci_high = res["ci_high"],
                              flag = flag_range(res["est"]))
  }
  do.call(rbind, rows)
}

cat("=== Table 2 analog peak-CI (categorical) ===\n")
mod_cat <- readRDS(paste0(OUT_DIR, "ASYM_BASE_CATEGORICAL.RDS"))
tab_cat <- run_base_table(coef(mod_cat), vcov(mod_cat), "categorical", "")
print(tab_cat, row.names = FALSE, digits = 4)

cat("\n=== Table 2 analog peak-CI (continuous, raw -- DEM side contaminated per wrinkle #1) ===\n")
mod_cont <- readRDS(paste0(OUT_DIR, "ASYM_BASE_CONTINUOUS.RDS"))
# continuous variable names use score_co_/score_cross_ prefix, not co_/cross_
run_base_table_cont <- function(cf, V) {
  curves <- list(
    Other      = list(lin = "favorability", quad = "favorability_sq"),
    co_GOP     = list(lin = c("favorability", "favorability:score_co_GOP"), quad = c("favorability_sq", "favorability_sq:score_co_GOP")),
    cross_GOP  = list(lin = c("favorability", "favorability:score_cross_GOP"), quad = c("favorability_sq", "favorability_sq:score_cross_GOP")),
    co_DEM     = list(lin = c("favorability", "favorability:score_co_DEM"), quad = c("favorability_sq", "favorability_sq:score_co_DEM")),
    cross_DEM  = list(lin = c("favorability", "favorability:score_cross_DEM"), quad = c("favorability_sq", "favorability_sq:score_cross_DEM"))
  )
  rows <- list()
  for (nm in names(curves)) {
    lin_terms <- curves[[nm]]$lin; quad_terms <- curves[[nm]]$quad
    lin_fn <- function(cf) sum(sapply(lin_terms, function(t) g(cf, t)))
    quad_fn <- function(cf) sum(sapply(quad_terms, function(t) g(cf, t)))
    peak_f <- function(cf) peak_fn(lin_fn(cf), quad_fn(cf))
    res <- delta_method(cf, V, peak_f)
    rows[[nm]] <- data.frame(measure = "continuous", curve = nm,
                              peak = res["est"], se = res["se"],
                              ci_low = res["ci_low"], ci_high = res["ci_high"],
                              flag = flag_range(res["est"]))
  }
  do.call(rbind, rows)
}
tab_cont <- run_base_table_cont(coef(mod_cont), vcov(mod_cont))
print(tab_cont, row.names = FALSE, digits = 4)

write.csv(rbind(tab_cat, tab_cont), paste0(OUT_DIR, "asymmetric_base_peak_ci.csv"), row.names = FALSE)

# =============================================================================
# 2) Table 4 (full curve-shape): peaks by Incumbent vs NonIncumbent
# =============================================================================
cat("\n=== Table 4 peak-CI (categorical, by candidate type) ===\n")
mod_fc <- readRDS(paste0(OUT_DIR, "ASYM_FULLCURVE_NOFE.RDS"))
cf_fc <- coef(mod_fc); V_fc <- vcov(mod_fc)

lin_base_fc <- function(cf, type) {
  v <- g(cf, "favorability")
  if (type == "NonIncumbent") v <- v + g(cf, "favorability:incumbencyC")
  v
}
quad_base_fc <- function(cf, type) {
  v <- g(cf, "favorability_sq")
  if (type == "NonIncumbent") v <- v + g(cf, "incumbencyC:favorability_sq")
  v
}
lin_dummy_fc <- function(cf, type, dummy) {
  v <- g(cf, "favorability") + g(cf, paste0("favorability:", dummy))
  if (type == "NonIncumbent") {
    v <- v + g(cf, "favorability:incumbencyC") + g(cf, paste0("favorability:", dummy, ":incumbency_binNonIncumbent"))
  }
  v
}
quad_dummy_fc <- function(cf, type, dummy) {
  v <- g(cf, "favorability_sq") + g(cf, paste0("favorability_sq:", dummy))
  if (type == "NonIncumbent") {
    v <- v + g(cf, "incumbencyC:favorability_sq") + g(cf, paste0("favorability_sq:", dummy, ":incumbency_binNonIncumbent"))
  }
  v
}

rows <- list()
for (type in c("Incumbent", "NonIncumbent")) {
  base_peak_f <- function(cf) peak_fn(lin_base_fc(cf, type), quad_base_fc(cf, type))
  res <- delta_method(cf_fc, V_fc, base_peak_f)
  rows[[paste0("Other_", type)]] <- data.frame(curve = "Other", type = type, peak = res["est"], se = res["se"],
                                                ci_low = res["ci_low"], ci_high = res["ci_high"], flag = flag_range(res["est"]))
  for (dummy in c("co_partisan_GOP", "cross_partisan_GOP", "co_partisan_DEM", "cross_partisan_DEM")) {
    peak_f <- function(cf) peak_fn(lin_dummy_fc(cf, type, dummy), quad_dummy_fc(cf, type, dummy))
    res <- delta_method(cf_fc, V_fc, peak_f)
    rows[[paste0(dummy, "_", type)]] <- data.frame(curve = dummy, type = type, peak = res["est"], se = res["se"],
                                                    ci_low = res["ci_low"], ci_high = res["ci_high"], flag = flag_range(res["est"]))
  }
}
tab_fc <- do.call(rbind, rows)
print(tab_fc, row.names = FALSE, digits = 4)
write.csv(tab_fc, paste0(OUT_DIR, "asymmetric_fullcurve_peak_ci.csv"), row.names = FALSE)

cat("\nDone.\n")
