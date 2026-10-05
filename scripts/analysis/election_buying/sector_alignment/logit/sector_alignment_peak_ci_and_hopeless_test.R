library(sandwich)

# =============================================================================
# Two things, both requested 2026-08-03:
#
# 1) Correctly computed CIs of PEAK LOCATIONS (not naive marginal-CI overlap,
#    per docs/theory_revision_handoff.md §4.1) for every candidate-type x
#    alignment-side cell in the current primary logit (POOLED_FIRMFE) and
#    Tobit (POOLED_TOBIT) models. Peaks outside the data's actual support
#    ([-4,4] for favorability) are flagged explicitly -- see §9's discovery
#    that some derived peaks extrapolate past the real range of the data.
#
# 2) A DIRECT test at the extreme end (favorability = -4, the literal
#    boundary of the data, and -3, matching the established fav_cut
#    convention) of whether aligned firms are more willing to give (logit)
#    and give more money (Tobit) to hopeless co-partisan NON-INCUMBENTS --
#    candidates institutional/party money wouldn't bother with (docs §3.6).
#    Computed as a DIFFERENCE (aligned vs. baseline), with delta-method SE of
#    the difference directly (never comparing two marginal CIs -- §4.1).
#    Incumbent-side numbers are reported alongside as a placebo/contrast: the
#    theory predicts this effect is specific to non-incumbents.
#
# Uses a generic numerical-gradient delta-method helper throughout (avoids
# hand-deriving analytical gradients per cell, which is error-prone -- see
# the manual-formula version in sector_alignment_analysis.R for contrast).
# =============================================================================
PATH <- "/htaa/hhe/projects/election_buying/"

# --- Load models -------------------------------------------------------------
logit_mod <- readRDS(paste0(PATH, "model/sector_alignment/POOLED_FIRMFE.RDS"))
tobit_obj <- readRDS(paste0(PATH, "model/sector_alignment/POOLED_TOBIT.RDS"))
tobit_mod <- tobit_obj$model
tobit_vcov_fast <- readRDS(paste0(PATH, "model/sector_alignment/POOLED_TOBIT_vcov_fast.RDS"))

logit_cf <- coef(logit_mod)
logit_V  <- vcov(logit_mod)

tobit_cf_full <- coef(tobit_mod)                 # 90 coefficients, no scale
tobit_V_full  <- tobit_vcov_fast[names(tobit_cf_full), names(tobit_cf_full)]

# =============================================================================
# Generic delta method: numerical gradient of an arbitrary scalar function of
# the coefficient vector, against the model's own vcov.
# =============================================================================
delta_method <- function(cf, V, fn, eps = 1e-6) {
  val <- fn(cf)
  k <- length(cf)
  grad <- numeric(k)
  for (i in seq_len(k)) {
    cf_up <- cf; cf_up[i] <- cf_up[i] + eps
    cf_dn <- cf; cf_dn[i] <- cf_dn[i] - eps
    grad[i] <- (fn(cf_up) - fn(cf_dn)) / (2 * eps)
  }
  se <- sqrt(as.numeric(t(grad) %*% V %*% grad))
  c(est = val, se = se, ci_low = val - 1.96 * se, ci_high = val + 1.96 * se)
}

g <- function(cf, nm) cf[[nm]]   # loud KeyError if nm absent -- no silent-0 fallback

# =============================================================================
# Baseline (non-aligned) curve assembly: favorability * incumbency * party
# =============================================================================
lin_base <- function(cf, type, party_r) {
  v <- g(cf, "favorability")
  if (type == "C") v <- v + g(cf, "favorability:incumbencyC")
  if (type == "O") v <- v + g(cf, "favorability:incumbencyO")
  if (party_r) v <- v + g(cf, "favorability:partyREPUBLICAN")
  if (type == "C" && party_r) v <- v + g(cf, "favorability:incumbencyC:partyREPUBLICAN")
  if (type == "O" && party_r) v <- v + g(cf, "favorability:incumbencyO:partyREPUBLICAN")
  v
}
quad_base <- function(cf, type, party_r) {
  v <- g(cf, "favorability_sq")
  if (type == "C") v <- v + g(cf, "incumbencyC:favorability_sq")
  if (type == "O") v <- v + g(cf, "incumbencyO:favorability_sq")
  if (party_r) v <- v + g(cf, "partyREPUBLICAN:favorability_sq")
  if (type == "C" && party_r) v <- v + g(cf, "incumbencyC:partyREPUBLICAN:favorability_sq")
  if (type == "O" && party_r) v <- v + g(cf, "incumbencyO:partyREPUBLICAN:favorability_sq")
  v
}

# Aligned curve = baseline (at the relevant target party) + co-partisan shift
# (+ additional NonIncumbent-only increment, per the pooling licensed in §9)
lin_aligned <- function(cf, type, side) {
  party_r <- (side == "GOP")
  v <- lin_base(cf, type, party_r) + g(cf, paste0("favorability:co_partisan_", side))
  if (type != "I") v <- v + g(cf, paste0("favorability:co_partisan_", side, ":incumbency_binNonIncumbent"))
  v
}
quad_aligned <- function(cf, type, side) {
  party_r <- (side == "GOP")
  v <- quad_base(cf, type, party_r) + g(cf, paste0("favorability_sq:co_partisan_", side))
  if (type != "I") v <- v + g(cf, paste0("favorability_sq:co_partisan_", side, ":incumbency_binNonIncumbent"))
  v
}

peak_fn <- function(lin, quad) -lin / (2 * quad)

# =============================================================================
# 1) Peak + CI table
# =============================================================================
run_peak_table <- function(cf, V, model_label) {
  rows <- list()
  for (type in c("I", "C", "O")) {
    for (side in c("GOP", "DEM")) {
      party_r <- (side == "GOP")

      base_fn <- function(cf) peak_fn(lin_base(cf, type, party_r), quad_base(cf, type, party_r))
      aligned_fn <- function(cf) peak_fn(lin_aligned(cf, type, side), quad_aligned(cf, type, side))

      base_res <- delta_method(cf, V, base_fn)
      aligned_res <- delta_method(cf, V, aligned_fn)

      flag_base <- if (base_res["est"] < -4 || base_res["est"] > 4) "OUT-OF-RANGE" else ""
      flag_aligned <- if (aligned_res["est"] < -4 || aligned_res["est"] > 4) "OUT-OF-RANGE" else ""

      rows[[length(rows) + 1]] <- data.frame(
        model = model_label, type = type, side = side, curve = "baseline",
        peak = base_res["est"], se = base_res["se"],
        ci_low = base_res["ci_low"], ci_high = base_res["ci_high"], flag = flag_base
      )
      rows[[length(rows) + 1]] <- data.frame(
        model = model_label, type = type, side = side, curve = "aligned",
        peak = aligned_res["est"], se = aligned_res["se"],
        ci_low = aligned_res["ci_low"], ci_high = aligned_res["ci_high"], flag = flag_aligned
      )
    }
  }
  do.call(rbind, rows)
}

cat("Computing peak CIs (logit)...\n")
peak_logit <- run_peak_table(logit_cf, logit_V, "logit")
cat("Computing peak CIs (tobit)...\n")
peak_tobit <- run_peak_table(tobit_cf_full, tobit_V_full, "tobit")

peak_table <- rbind(peak_logit, peak_tobit)
write.csv(peak_table, paste0(PATH, "model/sector_alignment/peak_ci_table.csv"), row.names = FALSE)

cat("\n=== PEAK CI TABLE ===\n")
print(peak_table, row.names = FALSE, digits = 4)

# =============================================================================
# 2) Direct hopeless-candidate test: diff(f) = aligned - baseline at fixed f,
#    for NonIncumbent (primary) and Incumbent (contrast/placebo)
# =============================================================================
diff_fn <- function(side, type, f) {
  function(cf) {
    lvl <- g(cf, paste0("co_partisan_", side))
    lin <- g(cf, paste0("favorability:co_partisan_", side))
    quad <- g(cf, paste0("favorability_sq:co_partisan_", side))
    if (type == "NonIncumbent") {
      lvl <- lvl + g(cf, paste0("co_partisan_", side, ":incumbency_binNonIncumbent"))
      lin <- lin + g(cf, paste0("favorability:co_partisan_", side, ":incumbency_binNonIncumbent"))
      quad <- quad + g(cf, paste0("favorability_sq:co_partisan_", side, ":incumbency_binNonIncumbent"))
    }
    lvl + lin * f + quad * f^2
  }
}

run_hopeless_test <- function(cf, V, model_label, is_logit) {
  rows <- list()
  for (side in c("GOP", "DEM")) {
    for (type in c("Incumbent", "NonIncumbent")) {
      for (f in c(-4, -3, -2)) {
        res <- delta_method(cf, V, diff_fn(side, type, f))
        row <- data.frame(
          model = model_label, side = side, cand_type = type, favorability = f,
          diff_est = res["est"], diff_se = res["se"],
          diff_ci_low = res["ci_low"], diff_ci_high = res["ci_high"]
        )
        if (is_logit) {
          row$odds_ratio <- exp(res["est"])
          row$or_ci_low <- exp(res["ci_low"])
          row$or_ci_high <- exp(res["ci_high"])
        }
        rows[[length(rows) + 1]] <- row
      }
    }
  }
  do.call(rbind, rows)
}

cat("\nComputing hopeless-candidate test (logit)...\n")
hopeless_logit <- run_hopeless_test(logit_cf, logit_V, "logit", is_logit = TRUE)
cat("Computing hopeless-candidate test (tobit)...\n")
hopeless_tobit <- run_hopeless_test(tobit_cf_full, tobit_V_full, "tobit", is_logit = FALSE)

write.csv(hopeless_logit, paste0(PATH, "model/sector_alignment/hopeless_test_logit.csv"), row.names = FALSE)
write.csv(hopeless_tobit, paste0(PATH, "model/sector_alignment/hopeless_test_tobit.csv"), row.names = FALSE)

cat("\n=== HOPELESS-CANDIDATE TEST: logit (log-odds diff + odds ratio) ===\n")
print(hopeless_logit, row.names = FALSE, digits = 4)

cat("\n=== HOPELESS-CANDIDATE TEST: tobit (dollar diff) ===\n")
print(hopeless_tobit, row.names = FALSE, digits = 4)
