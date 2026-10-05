# Location test on the intensive margin: where does the contribution-AMOUNT
# curve peak, by co-/cross-partisan alignment?
#
# The paper's location tests all run on the extensive margin (probability of
# contributing). If the same firms also shift the peak of the amount curve
# toward more competitive races, the finding is not an artifact of the
# decision-to-give margin. This is the amount analog of
# asymmetric_base_peak_ci.csv.
#
# Model: ASYM_TOBIT_BASE_CATEGORICAL / _CONTINUOUS, fit by
# asymmetric_pooled_nofe_tobit.R. Term names match the logit battery exactly,
# because both are built from the same rhs string pattern.
#
# NOTE: survreg's clustered vcov carries an extra Log(scale) row/col that
# coef() does not return. It must be subset before the delta method or the
# numerical gradient mis-indexes and returns confident nonsense.

suppressPackageStartupMessages({ library(dplyr) })
PATH <- "/htaa/hhe/projects/election_buying/"
OUT  <- paste0(PATH, "model/sector_alignment/")
source(paste0(PATH, "scripts/sector_alignment/logit/peak_helpers.R"))

# Term names differ between the two measures: the categorical battery uses
# co_partisan_GOP-style dummies, the continuous one score_co_GOP-style. Build
# the curve spec from whichever suffix set the model actually carries.
make_curves <- function(suffixes) {
  cs <- list(Other = list(lin = "favorability", quad = "favorability_sq"))
  for (nm in names(suffixes)) {
    v <- suffixes[[nm]]
    cs[[nm]] <- list(lin  = c("favorability",    paste0("favorability:", v)),
                     quad = c("favorability_sq", paste0("favorability_sq:", v)))
  }
  cs
}
CURVES <- list(
  Categorical = make_curves(list(co_GOP = "co_partisan_GOP", cross_GOP = "cross_partisan_GOP",
                                 co_DEM = "co_partisan_DEM", cross_DEM = "cross_partisan_DEM")),
  Continuous  = make_curves(list(co_GOP = "score_co_GOP", cross_GOP = "score_cross_GOP",
                                 co_DEM = "score_co_DEM", cross_DEM = "score_cross_DEM"))
)

run_one <- function(rds, label) {
  curves <- CURVES[[label]]
  obj <- readRDS(paste0(OUT, rds))
  cf  <- coef(obj$model)
  V   <- align_vcov(cf, obj$vcov_cluster)      # drops Log(scale)
  stopifnot(length(cf) == nrow(V))
  rows <- lapply(names(curves), function(nm) {
    r <- peak_for_curve(cf, V, curves[[nm]]$lin, curves[[nm]]$quad)
    data.frame(measure = label, curve = nm,
               peak = as.numeric(r[["est"]]), se = as.numeric(r[["se"]]),
               ci_low = as.numeric(r[["ci_low"]]), ci_high = as.numeric(r[["ci_high"]]),
               flag = r[["flag"]], stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)

  # Peak SHIFT vs the non-advantaged baseline, tested directly.
  # Comparing two marginal CIs for overlap is not a test of the difference.
  shift <- lapply(setdiff(names(curves), "Other"), function(nm) {
    la <- curves[[nm]]$lin; qa <- curves[[nm]]$quad
    dfn <- function(cf) peak_fn(sum(sapply(la, function(t) g(cf, t))),
                                sum(sapply(qa, function(t) g(cf, t)))) -
                        peak_fn(g(cf, "favorability"), g(cf, "favorability_sq"))
    r <- delta_method(cf, V, dfn)
    data.frame(measure = label, curve = nm, shift = r[["est"]], se = r[["se"]],
               p = 2 * pnorm(-abs(r[["est"]] / r[["se"]])), stringsAsFactors = FALSE)
  })
  list(peaks = out, shifts = do.call(rbind, shift))
}

res <- list(run_one("ASYM_TOBIT_BASE_CATEGORICAL.RDS", "Categorical"),
            run_one("ASYM_TOBIT_BASE_CONTINUOUS.RDS",  "Continuous"))

peaks  <- do.call(rbind, lapply(res, `[[`, "peaks"))
shifts <- do.call(rbind, lapply(res, `[[`, "shifts"))
write.csv(peaks,  paste0(OUT, "amount_peak_ci.csv"),    row.names = FALSE)
write.csv(shifts, paste0(OUT, "amount_peak_shift.csv"), row.names = FALSE)

cat("=== AMOUNT curve peak location (Tobit, delta method, 95% CI) ===\n")
print(peaks, row.names = FALSE, digits = 4)
cat("\n=== peak shift vs non-advantaged (negative = peaks on more competitive races) ===\n")
print(shifts, row.names = FALSE, digits = 4)

cat("\n=== extensive-margin comparison (logit, same curves) ===\n")
lg <- paste0(OUT, "asymmetric_base_peak_ci.csv")
if (file.exists(lg)) print(read.csv(lg), row.names = FALSE, digits = 4) else
  cat("  asymmetric_base_peak_ci.csv not found\n")
cat("\nDone.\n")
