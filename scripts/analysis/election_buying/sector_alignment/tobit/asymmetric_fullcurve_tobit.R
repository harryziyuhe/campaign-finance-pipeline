# Tobit (intensive-margin) counterpart of
# scripts/sector_alignment/logit/asymmetric_full_curveshape_nofe.R.
#
# The existing ASYM_TOBIT_INCUMBENCY_* models interact alignment with
# incumbency at the LEVEL only. Nothing on the dollar scale currently lets the
# curve's slope and curvature differ by candidate type, so neither a
# by-candidate-type amount curve nor a by-candidate-type amount peak can be
# computed from what is on disk. This fits that model.
#
# Specification mirrors the logit full-curve model term for term: baseline
# curve fully interacted with incumbency x party, and each of the four
# alignment dummies interacted with favorability, favorability_sq, and
# incumbency_bin. Tobit conventions follow asymmetric_pooled_nofe_tobit.R --
# interval-censored survreg, state and year as plain covariates (survreg has
# no FE absorption), two-way clustered SEs via fast_cluster_vcov.R.
# =============================================================================
library(dplyr)
library(survival)
library(sandwich)
library(lmtest)

PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")
source(paste0(PATH, "scripts/sector_alignment/tobit/fast_cluster_vcov.R"))

cand_data <- readRDS(paste0(PATH, "cand_model_data.RDS"))

cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre, levels = c("Other", "GOP", "DEM"))
cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))
cand_data$incumbency_bin <- factor(ifelse(cand_data$incumbency == "I", "Incumbent", "NonIncumbent"),
                                    levels = c("Incumbent", "NonIncumbent"))
cand_data$party <- factor(cand_data$party, levels = c("DEMOCRAT", "REPUBLICAN"))

cand_data$co_partisan_GOP    <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "GOP")
cand_data$cross_partisan_GOP <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "GOP")
cand_data$co_partisan_DEM    <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "DEM")
cand_data$cross_partisan_DEM <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "DEM")

# Interval-censoring construction, identical to asymmetric_pooled_nofe_tobit.R.
d <- cand_data %>%
  filter(contribute_limit > 0) %>%
  mutate(
    y1 = case_when(contribute_amount <= 0 ~ NA_real_, contribute_amount >= contribute_limit ~ contribute_limit, TRUE ~ contribute_amount),
    y2 = case_when(contribute_amount <= 0 ~ 0, contribute_amount >= contribute_limit ~ NA_real_, TRUE ~ contribute_amount)
  ) %>%
  droplevels()
cat("N after filtering:", nrow(d), "\n")

base_controls <- "special + private + foreign + same_state + log(firm_cash) + state + factor(year)"
D <- c("co_partisan_GOP", "cross_partisan_GOP", "co_partisan_DEM", "cross_partisan_DEM")

blocks <- unlist(lapply(D, function(v) paste(
  v, paste0("favorability:", v), paste0("favorability_sq:", v), sep = " + ")))
shifts <- unlist(lapply(D, function(v) paste(
  paste0(v, ":incumbency_bin"),
  paste0("favorability:", v, ":incumbency_bin"),
  paste0("favorability_sq:", v, ":incumbency_bin"), sep = " + ")))

rhs <- paste(c(base_controls,
  "favorability * incumbency * party + favorability_sq * incumbency * party",
  blocks, shifts), collapse = " + ")

fmla <- as.formula(paste0("Surv(y1, y2, type = 'interval2') ~ ", rhs))
cat("\nFitting ASYM_TOBIT_FULLCURVE_CATEGORICAL...\n")
t0 <- Sys.time()
mod <- survreg(fmla, data = d, dist = "gaussian")
cat(sprintf("  fit time: %.2f min\n", as.numeric(Sys.time() - t0, units = "mins")))

t0 <- Sys.time()
mf <- model.frame(mod)
used_idx <- as.integer(rownames(mf))
d2 <- d[used_idx, ]
v_cl <- fast_two_way_cluster_vcov(mod, d2$cmte_id, d2$candidate_id)
nm <- c(names(coef(mod)), "Log(scale)")
dimnames(v_cl) <- list(nm, nm)
cat(sprintf("  vcov time: %.2f min\n", as.numeric(Sys.time() - t0, units = "mins")))

ct <- lmtest::coeftest(mod, vcov. = v_cl)
saveRDS(list(model = mod, vcov_cluster = v_cl),
        paste0(OUT_DIR, "ASYM_TOBIT_FULLCURVE_CATEGORICAL.RDS"))
writeLines(capture.output(ct), paste0(OUT_DIR, "ASYM_TOBIT_FULLCURVE_CATEGORICAL_coefficients.txt"))
cat("N used:", nrow(d2), "  params:", length(coef(mod)), "\n")

# Fail loudly here rather than in the plotting script if any term the figures
# need is absent or named differently than the logit model's.
cf <- coef(mod)
want <- c(D, paste0("favorability:", D), paste0("favorability_sq:", D),
          paste0(D, ":incumbency_binNonIncumbent"),
          paste0("favorability:", D, ":incumbency_binNonIncumbent"),
          paste0("favorability_sq:", D, ":incumbency_binNonIncumbent"))
found <- sapply(want, function(w) {
  p <- strsplit(w, ":")[[1]]
  any(sapply(names(cf), function(k) setequal(strsplit(k, ":")[[1]], p)))
})
cat("\n=== term availability ===\n")
if (all(found)) cat("  all", length(want), "figure terms present\n") else
  cat("  MISSING:\n", paste0("    ", want[!found], collapse = "\n"), "\n")
cat("\nDone.\n")
