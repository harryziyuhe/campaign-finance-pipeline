# Cell 3 (co-partisan non-incumbent) vs Cell 4 (cross-partisan non-incumbent)
# odds ratios and their difference, computed identically on the full-sample and
# pre-election full-curve models, so the two windows can be compared directly.
#
# Question this answers: is "bench-packing is co-partisan-only" a property of
# the sample window, or of the specification? Table 3's additive-incumbency
# model says co-partisan-only in BOTH windows; this checks whether the
# full-curve model's contrary signal also appears in both.

suppressPackageStartupMessages({ library(dplyr) })
PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")

delta_method <- function(cf, V, fn, eps = 1e-6) {
  val <- fn(cf); grad <- numeric(length(cf))
  for (i in seq_along(cf)) {
    up <- cf; up[i] <- up[i] + eps
    dn <- cf; dn[i] <- dn[i] - eps
    grad[i] <- (fn(up) - fn(dn)) / (2 * eps)
  }
  se <- sqrt(as.numeric(t(grad) %*% V %*% grad))
  c(est = val, se = se)
}
g <- function(cf, nm) if (nm %in% names(cf)) cf[[nm]] else stop(nm)

curve_fn <- function(dummy) function(cf) {
  lvl  <- g(cf, dummy)                + g(cf, paste0(dummy, ":incumbency_binNonIncumbent"))
  lin  <- g(cf, paste0("favorability:", dummy)) +
          g(cf, paste0("favorability:", dummy, ":incumbency_binNonIncumbent"))
  quad <- g(cf, paste0("favorability_sq:", dummy)) +
          g(cf, paste0("favorability_sq:", dummy, ":incumbency_binNonIncumbent"))
  function(f) lvl + lin * f + quad * f^2
}

FAV <- c(-4, -3, -2, -1, 0, 2, 4)

report <- function(model_file, label) {
  cat("\n==========", label, "==========\n")
  mod <- readRDS(paste0(OUT_DIR, model_file))
  cf <- coef(mod); V <- vcov(mod)
  rows <- lapply(FAV, function(f) {
    co <- delta_method(cf, V, function(k) curve_fn("co_partisan_GOP")(k)(f))
    cr <- delta_method(cf, V, function(k) curve_fn("cross_partisan_GOP")(k)(f))
    df <- delta_method(cf, V, function(k)
            curve_fn("co_partisan_GOP")(k)(f) - curve_fn("cross_partisan_GOP")(k)(f))
    data.frame(
      f = f,
      cell3_OR = exp(co["est"]), cell3_p = 2*pnorm(-abs(co["est"]/co["se"])),
      cell4_OR = exp(cr["est"]), cell4_p = 2*pnorm(-abs(cr["est"]/cr["se"])),
      diff_OR  = exp(df["est"]), diff_p  = 2*pnorm(-abs(df["est"]/df["se"]))
    )
  })
  print(do.call(rbind, rows), row.names = FALSE, digits = 3)
  rm(mod); gc(verbose = FALSE)
}

report("ASYM_FULLCURVE_NOFE.RDS",             "FULL SAMPLE (GOP)")
report("ASYM_FULLCURVE_NOFE_PREELECTION.RDS", "PRE-ELECTION (GOP)")
cat("\nDone.\n")
