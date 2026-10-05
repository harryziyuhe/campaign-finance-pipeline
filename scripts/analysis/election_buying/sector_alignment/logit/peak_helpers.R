# Shared peak-location helpers.
#
# The numerical-gradient delta method below was previously copy-pasted verbatim
# into sector_alignment_peak_ci_and_hopeless_test.R, asymmetric_peak_ci.R and
# cell_direct_effects.R. New scripts source this file instead. The three
# existing callers still carry their own copies and are deliberately left
# alone -- they are known-good and re-pointing them is not worth the risk.
#
# Convention: peak CIs are delta-method at 95%. The figure code in
# asymmetric_figures.R historically used a 10,000-draw simulation interval at
# 90% constrained to the [-4, 4] grid, which is a different estimator of the
# same quantity. Anything new should use this file so the paper reports one
# convention.

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

# Loud on a missing coefficient name. A silent zero here once produced a
# plausible-looking but wrong odds ratio, so never fall back to 0.
g <- function(cf, nm) if (nm %in% names(cf)) cf[[nm]] else stop(sprintf("missing coef: %s", nm))

peak_fn <- function(lin, quad) -lin / (2 * quad)

flag_range <- function(est) if (est < -4 || est > 4) "OUT-OF-RANGE" else ""

# Peak for one curve given the coefficient names that add up to its linear and
# quadratic terms. Returns est/se/ci_low/ci_high plus the range flag.
peak_for_curve <- function(cf, V, lin_terms, quad_terms) {
  lin_fn  <- function(cf) sum(sapply(lin_terms,  function(t) g(cf, t)))
  quad_fn <- function(cf) sum(sapply(quad_terms, function(t) g(cf, t)))
  res <- delta_method(cf, V, function(cf) peak_fn(lin_fn(cf), quad_fn(cf)))
  c(res, flag = flag_range(res[["est"]]))
}

# survreg vcov carries an extra Log(scale) row/col that coef() does not.
# Subsetting is mandatory before the delta method, or the gradient mis-indexes.
align_vcov <- function(cf, V) V[names(cf), names(cf), drop = FALSE]
