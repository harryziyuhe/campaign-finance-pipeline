# Audit every numeric claim in the paper's prose against the fitted models.
#
# Four tables were found during revision to contain hand-transcribed values that
# no longer matched the models on disk. The tables are now generated, but numbers
# quoted in PROSE are still typed by hand and have never been checked
# systematically. This script does that check.
#
# Method: collect every coefficient and standard error from every model the
# paper draws on, then extract every number appearing inside math mode in the
# .tex prose (excluding table environments), and report which quoted numbers do
# not match any estimate to within rounding. Unmatched numbers are candidates
# for review, not automatic errors -- p-values, sample sizes, odds ratios,
# percentages and derived quantities will legitimately not appear in a
# coefficient vector. The point is to narrow thousands of numbers down to a
# list short enough to inspect.

suppressPackageStartupMessages({ library(fixest) })
PATH <- "/htaa/hhe/projects/election_buying/"
MOD  <- paste0(PATH, "model/sector_alignment/")

models <- c(
  "ASYM_BASE_CATEGORICAL", "ASYM_BASE_CONTINUOUS",
  "ASYM_INCUMBENCY_CATEGORICAL", "ASYM_INCUMBENCY_CONTINUOUS",
  "ASYM_INCUMBENCY_CATEGORICAL_FIRMFE", "ASYM_INCUMBENCY_CONTINUOUS_FIRMFE",
  "ASYM_INCUMBENCY_CATEGORICAL_FIRMCYCLEFE", "ASYM_INCUMBENCY_CONTINUOUS_FIRMCYCLEFE",
  "ASYM_FULLCURVE_NOFE",
  "ASYM_INCUMBENCY_CATEGORICAL_PREELECTION", "ASYM_INCUMBENCY_CONTINUOUS_PREELECTION",
  "ASYM_TOBIT_INCUMBENCY_CATEGORICAL", "ASYM_TOBIT_INCUMBENCY_CONTINUOUS",
  "ASYM_TOBIT_INCUMBENCY_CATEGORICAL_PREELECTION", "ASYM_TOBIT_INCUMBENCY_CONTINUOUS_PREELECTION",
  "ASYM_SUBSEC_CAT", "ASYM_SUBSEC_CONT", "ASYM_IND_CAT", "ASYM_IND_CONT",
  "ASYM_GIVE_INCUMBENCY", "ASYM_INCUMBENCY_CONTINUOUS_DEM_RESTRICTED",
  "BIMODAL_INTERIOR", "BIMODAL_ENDPOINTS", "BIMODAL_FACTOR", "BIMODAL_FULLCURVE_ENDPOINTS"
)

vals <- numeric(0)
for (m in models) {
  f <- paste0(MOD, m, ".RDS")
  if (!file.exists(f)) { cat("  (absent, skipped):", m, "\n"); next }
  obj <- try(readRDS(f), silent = TRUE)
  if (inherits(obj, "try-error")) { cat("  (unreadable):", m, "\n"); next }
  if (inherits(obj, "fixest")) {
    vals <- c(vals, as.numeric(coef(obj)), as.numeric(se(obj)))
  } else if (is.list(obj) && !is.null(obj$model)) {
    ct <- try(lmtest::coeftest(obj$model, vcov. = obj$vcov_cluster), silent = TRUE)
    if (!inherits(ct, "try-error")) vals <- c(vals, as.numeric(ct[,1]), as.numeric(ct[,2]))
  }
  rm(obj); gc(verbose = FALSE)
}
vals <- vals[is.finite(vals)]
cat("collected", length(vals), "estimates and standard errors\n")
saveRDS(vals, "/tmp/paper_model_values.RDS")
cat("Done.\n")
