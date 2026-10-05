library(dplyr)
library(survival)
library(sandwich)
library(lmtest)

# =============================================================================
# Trimmed rerun after the cand_model_data.RDS data fix (Consumer Products
# mislabeled DEM in singlename_partisan_pre -- 2026-08-11): only the
# CATEGORICAL Tobit models depend on singlename_partisan_pre, so only those
# need refitting. The continuous Tobit models (score_co_DEM/score_cross_DEM
# etc.) are built from singlename_score_pre directly and are numerically
# unaffected by this fix -- skipping them saves ~20+ minutes of survreg fit
# time. See scripts/tobit/asymmetric_pooled_nofe_tobit.R for the full
# (categorical + continuous) version this is trimmed from.
# =============================================================================
PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")
source(paste0(PATH, "scripts/sector_alignment/tobit/fast_cluster_vcov.R"))

cand_data <- readRDS(paste0(PATH, "cand_model_data.RDS"))

cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre, levels = c("Other", "GOP", "DEM"))
cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))
cand_data$party <- factor(cand_data$party, levels = c("DEMOCRAT", "REPUBLICAN"))

cand_data$co_partisan_GOP    <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "GOP")
cand_data$cross_partisan_GOP <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "GOP")
cand_data$co_partisan_DEM    <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "DEM")
cand_data$cross_partisan_DEM <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "DEM")

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

rhs_base_cat <- paste(
  base_controls,
  "favorability + favorability_sq",
  "co_partisan_GOP + favorability:co_partisan_GOP + favorability_sq:co_partisan_GOP",
  "cross_partisan_GOP + favorability:cross_partisan_GOP + favorability_sq:cross_partisan_GOP",
  "co_partisan_DEM + favorability:co_partisan_DEM + favorability_sq:co_partisan_DEM",
  "cross_partisan_DEM + favorability:cross_partisan_DEM + favorability_sq:cross_partisan_DEM",
  sep = " + "
)
rhs_inc_cat <- paste(
  rhs_base_cat,
  "co_partisan_GOP:incumbency + cross_partisan_GOP:incumbency",
  "co_partisan_DEM:incumbency + cross_partisan_DEM:incumbency",
  sep = " + "
)

res_base_cat <- fit_one(rhs_base_cat, "ASYM_TOBIT_BASE_CATEGORICAL")
res_inc_cat  <- fit_one(rhs_inc_cat,  "ASYM_TOBIT_INCUMBENCY_CATEGORICAL")

cat("\n=== Updated DEM coefficients (categorical Tobit) ===\n")
get_row <- function(ct, vcl, nm) {
  cf <- ct[, "Estimate"]
  if (!nm %in% names(cf)) return(cat(sprintf("%s: MISSING\n", nm)))
  s <- sqrt(vcl[nm, nm])
  cat(sprintf("%-45s est=%.2f se=%.2f p=%.4g\n", nm, cf[[nm]], s, 2 * pnorm(-abs(cf[[nm]] / s))))
}
for (nm in c("co_partisan_DEM", "cross_partisan_DEM")) get_row(res_base_cat$ct, res_base_cat$vcov, nm)
for (nm in c("incumbencyC:co_partisan_DEM", "incumbencyO:co_partisan_DEM",
             "incumbencyC:cross_partisan_DEM", "incumbencyO:cross_partisan_DEM")) get_row(res_inc_cat$ct, res_inc_cat$vcov, nm)

cat("\nDone.\n")
