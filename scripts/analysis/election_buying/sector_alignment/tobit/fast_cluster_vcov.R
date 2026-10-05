library(sandwich)

# =============================================================================
# Fast two-way cluster-robust vcov for survreg (Tobit) models -- replaces
# sandwich::vcovCL, which took 67 minutes on the pooled Tobit model
# (N=6.8M, ~1,800 firm clusters x ~3,000 candidate clusters). This version
# takes ~2 minutes (51s for estfun() + ~70s for the meat/bread assembly) and
# matches vcovCL to within 0.05% on every coefficient checked (validated
# 2026-08-03 against the already-computed POOLED_TOBIT vcov).
#
# The likely reason vcovCL is slow here: its internal grouped-sum step isn't
# using a vectorized aggregation for this many rows/clusters. This
# implementation uses rowsum() (a C-level, vectorized grouped-sum in base R)
# for the meat matrix instead, which is the main lever for the speedup.
#
# Formula (Cameron, Gelbach & Miller 2011 multi-way clustering):
#   V = bread %*% (meat_1 + meat_2 - meat_{1x2}) %*% bread
# where meat_g = crossprod(rowsum(estfun(mod), group=g)) / n.
#
# IMPORTANT CAVEAT: survreg stores its call unevaluated (mod$call literally
# references the variable names used at fit time, e.g. `fmla` and `d`).
# sandwich::estfun.survreg re-evaluates model.frame(mod) internally, which
# looks up those exact names in the calling environment. Before calling
# estfun()/bread() on a loaded model object, you MUST recreate the fitting
# data under the SAME variable names used in the original fit (see
# scripts/tobit/sector_alignment_pooled.R for the exact construction), and
# have `library(survival)` loaded so Surv() resolves. Skipping this produces
# either "object not found" or "could not find function Surv" errors.
# =============================================================================

fast_two_way_cluster_vcov <- function(mod, cluster1, cluster2) {
  ef <- sandwich::estfun(mod)
  br <- sandwich::bread(mod)
  n  <- nrow(ef)
  stopifnot(n == length(cluster1), n == length(cluster2))

  meat_of <- function(g) {
    g <- droplevels(as.factor(g))
    grouped <- rowsum(ef, group = g)
    crossprod(grouped) / n
  }

  meat1  <- meat_of(cluster1)
  meat2  <- meat_of(cluster2)
  inter  <- interaction(cluster1, cluster2, drop = TRUE)
  meat12 <- meat_of(inter)

  meat <- meat1 + meat2 - meat12
  (br %*% meat %*% br) / n
}
