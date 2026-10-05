# R4, part 2. Two gaps left by bimodality_checks.R:
#
# (a) Hypothesis 3 (concentration among weak co-partisan non-incumbents) is
#     estimated from the FULL-CURVE spec, not the additive-incumbency spec used
#     in the first script, so it was not actually tested there. Note that
#     dropping the boundary masses is the WRONG test for this hypothesis: the
#     headline quantity (the co-partisan odds ratio at favorability = -4) is
#     evaluated AT the lower boundary, so an interior-only sample removes the
#     very thing being claimed. The right test keeps the full sample and frees
#     the boundary masses with their own indicators, so they no longer anchor
#     the quadratic but the claim can still be evaluated where it is made.
#
# (b) The nonparametric shape check established a humped pattern but not
#     whether the decline at the safe end is statistically distinguishable.
#     Test fav_f(+2) vs fav_f(+4) directly using the model's own covariance.

suppressPackageStartupMessages({ library(dplyr); library(fixest) })
PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")

d <- readRDS(paste0(PATH, "cand_model_data.RDS"))
d$singlename_partisan_pre <- factor(d$singlename_partisan_pre, levels=c("Other","GOP","DEM"))
d$incumbency <- factor(d$incumbency, levels=c("I","C","O"))
d$party <- factor(d$party, levels=c("DEMOCRAT","REPUBLICAN"))
d$incumbency_bin <- factor(ifelse(d$incumbency=="I","Incumbent","NonIncumbent"),
                           levels=c("Incumbent","NonIncumbent"))
d$co_partisan_GOP    <- as.integer(d$party=="REPUBLICAN" & d$singlename_partisan_pre=="GOP")
d$cross_partisan_GOP <- as.integer(d$party=="DEMOCRAT"   & d$singlename_partisan_pre=="GOP")
d$co_partisan_DEM    <- as.integer(d$party=="DEMOCRAT"   & d$singlename_partisan_pre=="DEM")
d$cross_partisan_DEM <- as.integer(d$party=="REPUBLICAN" & d$singlename_partisan_pre=="DEM")
d$at_lo <- as.integer(d$favorability == -4)
d$at_hi <- as.integer(d$favorability ==  4)

DUMS <- c("co_partisan_GOP","cross_partisan_GOP","co_partisan_DEM","cross_partisan_DEM")
full_curve <- paste(sapply(DUMS, function(v)
  sprintf("(favorability + favorability_sq) * %s * incumbency_bin", v)), collapse=" + ")
rhs <- paste("special + private + foreign + same_state + log(firm_cash) + party + incumbency",
             "at_lo + at_hi",
             "(favorability + favorability_sq) * incumbency_bin",
             full_curve, sep=" + ")

cat("=== (a) FULL-CURVE SPEC WITH FREE ENDPOINT INDICATORS ===\n")
m <- feglm(as.formula(paste("contribute ~", rhs, "| state + year")),
           data=d, family=binomial("logit"), cluster=~cmte_id+candidate_id)
saveRDS(m, paste0(OUT_DIR,"BIMODAL_FULLCURVE_ENDPOINTS.RDS"))
writeLines(capture.output(summary(m)), paste0(OUT_DIR,"BIMODAL_FULLCURVE_ENDPOINTS_coefficients.txt"))

cf <- coef(m); V <- vcov(m); se <- se(m)
key <- c("favorability:co_partisan_GOP",
         "favorability_sq:co_partisan_GOP",
         "favorability:co_partisan_GOP:incumbency_binNonIncumbent",
         "favorability_sq:co_partisan_GOP:incumbency_binNonIncumbent",
         "co_partisan_GOP:incumbency_binNonIncumbent",
         "at_lo","at_hi")
for (nm in key) if (nm %in% names(cf))
  cat(sprintf("  %-62s %8.4f (%.4f) p=%.4g\n", nm, cf[[nm]], se[[nm]],
              2*pnorm(-abs(cf[[nm]]/se[[nm]]))))

# Cell 3 odds ratio (co-partisan non-incumbent vs non-advantaged non-incumbent)
# across the favorability range, from this endpoint-freed model.
g <- function(k,n) if (n %in% names(k)) k[[n]] else 0
dm <- function(fn, eps=1e-6) {
  val <- fn(cf); gr <- numeric(length(cf))
  for (i in seq_along(cf)) { u<-cf; u[i]<-u[i]+eps; l<-cf; l[i]<-l[i]-eps
                             gr[i] <- (fn(u)-fn(l))/(2*eps) }
  c(val, sqrt(as.numeric(t(gr) %*% V %*% gr)))
}
cat("\n  Cell 3 odds ratio (co-partisan non-incumbent), endpoint-freed model:\n")
for (f in c(-4,-3,-2,0,2,4)) {
  fn <- function(k) g(k,"co_partisan_GOP") + g(k,"co_partisan_GOP:incumbency_binNonIncumbent") +
    (g(k,"favorability:co_partisan_GOP") + g(k,"favorability:co_partisan_GOP:incumbency_binNonIncumbent"))*f +
    (g(k,"favorability_sq:co_partisan_GOP") + g(k,"favorability_sq:co_partisan_GOP:incumbency_binNonIncumbent"))*f^2
  r <- dm(fn)
  cat(sprintf("    f=%+d   OR=%5.2f   p=%.4g\n", f, exp(r[1]), 2*pnorm(-abs(r[1]/r[2]))))
}

# ---- (b) is the safe-end decline in the nonparametric shape real? ------------
cat("\n\n=== (b) NONPARAMETRIC SHAPE: is the safe-end decline significant? ===\n")
m3 <- readRDS(paste0(OUT_DIR,"BIMODAL_FACTOR.RDS"))
cf3 <- coef(m3); V3 <- vcov(m3)
cmp <- function(a,b) {
  if (!all(c(a,b) %in% names(cf3))) return(invisible(NULL))
  dd <- cf3[[a]]-cf3[[b]]
  s <- sqrt(V3[a,a]+V3[b,b]-2*V3[a,b])
  cat(sprintf("  %-10s minus %-10s  diff=%7.4f se=%.4f  p=%.4g\n", a,b,dd,s,2*pnorm(-abs(dd/s))))
}
cmp("fav_f2","fav_f4"); cmp("fav_f1","fav_f4"); cmp("fav_f2","fav_f3"); cmp("fav_f0","fav_f4")
cat("\nDone.\n")
