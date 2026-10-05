library(dplyr)
library(survival)
library(sandwich)
library(lmtest)

# =============================================================================
# Tobit (intensive-margin) counterpart of
# scripts/logit/sector_alignment_pooled_firmfe.R -- same design principle
# (pool both parties, two direction-specific co-partisan dummies so each
# varies across a firm's own dyads, baseline curve fully flexible by
# incumbency x party, aligned-shift pooled across Challenger+Open-seat via
# incumbency_bin, licensed by the earlier Wald equality test) -- but WITHOUT
# firm fixed effects: survreg has no FE-absorption mechanism, and a literal
# ~1,800-firm-dummy design matrix at N=6.8M is not just slow but infeasible
# (dense matrix > 100GB), nor would naive dummies be a valid FE estimator for
# a censored-outcome MLE the way a within-transform is for OLS. state/year
# stay as plain RHS covariates, matching every other scripts/tobit/*.R file
# and the convention documented in this project's memory.
# =============================================================================
PATH <- "/htaa/hhe/projects/election_buying/"
cand_data <- readRDS(paste0(PATH, "cand_model_data.RDS"))

cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre, levels = c("Other", "GOP", "DEM"))
cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))
cand_data$incumbency_bin <- factor(ifelse(cand_data$incumbency == "I", "Incumbent", "NonIncumbent"),
                                    levels = c("Incumbent", "NonIncumbent"))
cand_data$party <- factor(cand_data$party, levels = c("DEMOCRAT", "REPUBLICAN"))

cand_data$co_partisan_GOP <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "GOP")
cand_data$co_partisan_DEM <- as.integer(cand_data$party == "DEMOCRAT" & cand_data$singlename_partisan_pre == "DEM")

d <- cand_data %>%
  filter(contribute_limit > 0) %>%
  mutate(
    y1 = case_when(
      contribute_amount <= 0 ~ NA_real_,
      contribute_amount >= contribute_limit ~ contribute_limit,
      TRUE ~ contribute_amount
    ),
    y2 = case_when(
      contribute_amount <= 0 ~ 0,
      contribute_amount >= contribute_limit ~ NA_real_,
      TRUE ~ contribute_amount
    )
  ) %>%
  droplevels()

cat("N after filtering:", nrow(d), "\n")

rhs <- paste(
  "special + private + foreign + same_state + log(firm_cash)",
  "state + factor(year)",
  "favorability * incumbency * party + favorability_sq * incumbency * party",
  "co_partisan_GOP + favorability:co_partisan_GOP + favorability_sq:co_partisan_GOP",
  "co_partisan_DEM + favorability:co_partisan_DEM + favorability_sq:co_partisan_DEM",
  "co_partisan_GOP:incumbency_bin + favorability:co_partisan_GOP:incumbency_bin + favorability_sq:co_partisan_GOP:incumbency_bin",
  "co_partisan_DEM:incumbency_bin + favorability:co_partisan_DEM:incumbency_bin + favorability_sq:co_partisan_DEM:incumbency_bin",
  sep = " + "
)
fmla <- as.formula(paste0("Surv(y1, y2, type = 'interval2') ~ ", rhs))

cat("\nFitting pooled two-dummy Tobit (survreg, gaussian, interval-censored)...\n")
t0 <- Sys.time()
mod <- survreg(fmla, data = d, dist = "gaussian")
cat("Fit time:", as.numeric(Sys.time() - t0, units = "mins"), "min\n")

cat("\nComputing cluster-robust vcov...\n")
t0 <- Sys.time()
v_cl <- sandwich::vcovCL(mod, cluster = d[, c("cmte_id", "candidate_id"), drop = FALSE])
cat("vcov time:", as.numeric(Sys.time() - t0, units = "mins"), "min\n")

ct <- lmtest::coeftest(mod, vcov. = v_cl)
saveRDS(list(model = mod, vcov_cluster = v_cl), paste0(PATH, "model/sector_alignment/POOLED_TOBIT.RDS"))
writeLines(capture.output(ct), paste0(PATH, "model/sector_alignment/POOLED_TOBIT_coefficients.txt"))

cf <- ct[, "Estimate"]; se <- ct[, "Std. Error"]; pv <- ct[, "Pr(>|z|)"]
get_row <- function(nm) {
  if (!nm %in% names(cf)) return(sprintf("%s: MISSING", nm))
  sprintf("%-70s est=%.4f se=%.4f p=%.4g", nm, cf[[nm]], se[[nm]], pv[[nm]])
}

cat("\n=== H2: co-partisan level effect (amount) ===\n")
cat(get_row("co_partisan_GOP"), "\n")
cat(get_row("co_partisan_DEM"), "\n")

cat("\n=== H3: Incumbent-reference aligned slope/curvature shift (no-rescue, amount) ===\n")
cat(get_row("favorability:co_partisan_GOP"), "\n")
cat(get_row("favorability_sq:co_partisan_GOP"), "\n")
cat(get_row("favorability:co_partisan_DEM"), "\n")
cat(get_row("favorability_sq:co_partisan_DEM"), "\n")

cat("\n=== H4: additional NonIncumbent aligned slope/curvature shift (bench-packing, amount) ===\n")
cat(get_row("favorability:co_partisan_GOP:incumbency_binNonIncumbent"), "\n")
cat(get_row("favorability_sq:co_partisan_GOP:incumbency_binNonIncumbent"), "\n")
cat(get_row("favorability:co_partisan_DEM:incumbency_binNonIncumbent"), "\n")
cat(get_row("favorability_sq:co_partisan_DEM:incumbency_binNonIncumbent"), "\n")

cat("\n=== NonIncumbent-level effects (amount) ===\n")
cat(get_row("co_partisan_GOP:incumbency_binNonIncumbent"), "\n")
cat(get_row("co_partisan_DEM:incumbency_binNonIncumbent"), "\n")
