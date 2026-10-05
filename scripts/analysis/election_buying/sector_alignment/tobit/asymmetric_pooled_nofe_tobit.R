library(dplyr)
library(survival)
library(sandwich)
library(lmtest)

# =============================================================================
# Tobit (intensive-margin) counterpart of
# scripts/logit/asymmetric_pooled_nofe.R -- same fully-crossed 4-dummy /
# 4-variable asymmetric design (co_partisan_GOP/DEM, cross_partisan_GOP/DEM,
# and their continuous score_* analogs), same baseline vs incumbency-
# interacted split (Table 2 / Table 3 analogs), but for contribution AMOUNT
# (Table 5 analog). No firm FE (survreg has no FE-absorption mechanism; see
# scripts/tobit/sector_alignment_pooled.R for the full infeasibility
# rationale) -- state/year enter as plain RHS covariates, matching this
# project's Tobit convention.
#
# Uses scripts/sector_alignment/tobit/fast_cluster_vcov.R for two-way cluster-robust SEs
# instead of sandwich::vcovCL directly (67 min -> ~2 min per model, see
# docs/theory_revision_handoff.md §9.3) -- with 4 models to fit here, the
# naive vcovCL would be prohibitively slow.
# =============================================================================
PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")
source(paste0(PATH, "scripts/sector_alignment/tobit/fast_cluster_vcov.R"))

# Optional args (same convention as asymmetric_pooled_nofe.R):
#   arg 1 = input RDS basename  (default "cand_model_data")
#   arg 2 = output name suffix  (default "", e.g. "_PREELECTION")
.args     <- commandArgs(trailingOnly = TRUE)
DATA_NAME <- if (length(.args) >= 1) .args[1] else "cand_model_data"
SUFFIX    <- if (length(.args) >= 2) .args[2] else ""
cat("Input data:   ", DATA_NAME, ".RDS\n", sep = "")
cat("Output suffix: ", if (nzchar(SUFFIX)) SUFFIX else "(none)", "\n", sep = "")

cand_data <- readRDS(paste0(PATH, DATA_NAME, ".RDS"))

cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre, levels = c("Other", "GOP", "DEM"))
cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))
cand_data$party <- factor(cand_data$party, levels = c("DEMOCRAT", "REPUBLICAN"))

cand_data$co_partisan_GOP    <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "GOP")
cand_data$cross_partisan_GOP <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "GOP")
cand_data$co_partisan_DEM    <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "DEM")
cand_data$cross_partisan_DEM <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "DEM")

singlename_GOP_pre <- pmax(cand_data$singlename_score_pre, 0)
singlename_DEM_pre <- pmax(-cand_data$singlename_score_pre, 0)
cand_data$score_co_GOP    <- singlename_GOP_pre * (cand_data$party == "REPUBLICAN")
cand_data$score_cross_GOP <- singlename_GOP_pre * (cand_data$party == "DEMOCRAT")
cand_data$score_co_DEM    <- singlename_DEM_pre * (cand_data$party == "DEMOCRAT")
cand_data$score_cross_DEM <- singlename_DEM_pre * (cand_data$party == "REPUBLICAN")

d <- cand_data %>%
  filter(contribute_limit > 0) %>%
  mutate(
    y1 = case_when(contribute_amount <= 0 ~ NA_real_, contribute_amount >= contribute_limit ~ contribute_limit, TRUE ~ contribute_amount),
    y2 = case_when(contribute_amount <= 0 ~ 0, contribute_amount >= contribute_limit ~ NA_real_, TRUE ~ contribute_amount)
  ) %>%
  droplevels()
cat("N after filtering:", nrow(d), "\n")

base_controls <- "special + private + foreign + same_state + log(firm_cash) + party + incumbency + state + factor(year)"

fit_one <- function(rhs, out_name) {
  out_name <- paste0(out_name, SUFFIX)
  fmla <- as.formula(paste0("Surv(y1, y2, type = 'interval2') ~ ", rhs))
  cat(sprintf("\nFitting %s...\n", out_name))
  t0 <- Sys.time()
  mod <- survreg(fmla, data = d, dist = "gaussian")
  cat(sprintf("  fit time: %.2f min\n", as.numeric(Sys.time() - t0, units = "mins")))

  t0 <- Sys.time()
  ef <- sandwich::estfun(mod)
  mf <- model.frame(mod)
  used_idx <- as.integer(rownames(mf))
  d2 <- d[used_idx, ]
  v_cl <- fast_two_way_cluster_vcov(mod, d2$cmte_id, d2$candidate_id)
  nm <- c(names(coef(mod)), "Log(scale)")
  dimnames(v_cl) <- list(nm, nm)
  cat(sprintf("  vcov time: %.2f min\n", as.numeric(Sys.time() - t0, units = "mins")))

  ct <- lmtest::coeftest(mod, vcov. = v_cl)
  saveRDS(list(model = mod, vcov_cluster = v_cl), paste0(OUT_DIR, out_name, ".RDS"))
  writeLines(capture.output(ct), paste0(OUT_DIR, out_name, "_coefficients.txt"))
  list(mod = mod, vcov = v_cl, ct = ct)
}

diff_test_tobit <- function(ct, v_cl, term_a, term_b) {
  cf <- ct[, "Estimate"]
  if (!term_a %in% names(cf) || !term_b %in% names(cf)) return(cat(sprintf("  [%s vs %s] MISSING\n", term_a, term_b)))
  dd <- cf[[term_a]] - cf[[term_b]]
  se <- sqrt(v_cl[term_a, term_a] + v_cl[term_b, term_b] - 2 * v_cl[term_a, term_b])
  cat(sprintf("  %-45s %-45s diff=%.2f se=%.2f p=%.4g\n", term_a, term_b, dd, se, 2 * pnorm(-abs(dd / se))))
}

# --- 1) Baseline (Table 5 analog, no incumbency interaction) ---------------
rhs_base_cat <- paste(
  base_controls,
  "favorability + favorability_sq",
  "co_partisan_GOP + favorability:co_partisan_GOP + favorability_sq:co_partisan_GOP",
  "cross_partisan_GOP + favorability:cross_partisan_GOP + favorability_sq:cross_partisan_GOP",
  "co_partisan_DEM + favorability:co_partisan_DEM + favorability_sq:co_partisan_DEM",
  "cross_partisan_DEM + favorability:cross_partisan_DEM + favorability_sq:cross_partisan_DEM",
  sep = " + "
)
rhs_base_cont <- paste(
  base_controls,
  "favorability + favorability_sq",
  "score_co_GOP + favorability:score_co_GOP + favorability_sq:score_co_GOP",
  "score_cross_GOP + favorability:score_cross_GOP + favorability_sq:score_cross_GOP",
  "score_co_DEM + favorability:score_co_DEM + favorability_sq:score_co_DEM",
  "score_cross_DEM + favorability:score_cross_DEM + favorability_sq:score_cross_DEM",
  sep = " + "
)

res_base_cat  <- fit_one(rhs_base_cat,  "ASYM_TOBIT_BASE_CATEGORICAL")
res_base_cont <- fit_one(rhs_base_cont, "ASYM_TOBIT_BASE_CONTINUOUS")

# --- 2) Incumbency-interacted (Table 3-for-Tobit analog) -------------------
rhs_inc_cat <- paste(
  rhs_base_cat,
  "co_partisan_GOP:incumbency + cross_partisan_GOP:incumbency",
  "co_partisan_DEM:incumbency + cross_partisan_DEM:incumbency",
  sep = " + "
)
rhs_inc_cont <- paste(
  rhs_base_cont,
  "score_co_GOP:incumbency + score_cross_GOP:incumbency",
  "score_co_DEM:incumbency + score_cross_DEM:incumbency",
  sep = " + "
)

res_inc_cat  <- fit_one(rhs_inc_cat,  "ASYM_TOBIT_INCUMBENCY_CATEGORICAL")
res_inc_cont <- fit_one(rhs_inc_cont, "ASYM_TOBIT_INCUMBENCY_CONTINUOUS")

cat("\n=== DIRECT ASYMMETRY TEST (dollar scale): co-partisan vs cross-partisan slope ===\n")
cat("-- baseline categorical --\n")
diff_test_tobit(res_base_cat$ct, res_base_cat$vcov, "favorability:co_partisan_GOP", "favorability:cross_partisan_GOP")
diff_test_tobit(res_base_cat$ct, res_base_cat$vcov, "favorability:co_partisan_DEM", "favorability:cross_partisan_DEM")
cat("-- baseline continuous --\n")
diff_test_tobit(res_base_cont$ct, res_base_cont$vcov, "favorability:score_co_GOP", "favorability:score_cross_GOP")
diff_test_tobit(res_base_cont$ct, res_base_cont$vcov, "favorability:score_co_DEM", "favorability:score_cross_DEM")

cat("\nDone.\n")
