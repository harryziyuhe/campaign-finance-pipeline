# R4: does the estimated contribution curve depend on the endpoint masses?
#
# Motivation: `favorability` is severely bimodal -- 37.3% of dyads sit at exactly
# -4 and 43.9% at exactly +4, so ~81% of the panel is at a boundary and the
# entire interior of the fitted curve is identified off the remaining ~19%.
# A quadratic anchored by two large boundary masses could in principle
# manufacture curvature that the interior data do not support.
#
# Three checks:
#   (1) INTERIOR   -- re-estimate the main targeting spec on |favorability| < 4
#                     only, dropping both boundary masses entirely.
#   (2) ENDPOINTS  -- full sample, but with free indicators for favorability
#                     == -4 and == +4, so the boundary masses get their own
#                     levels and stop anchoring the quadratic.
#   (3) SHAPE      -- baseline model with favorability entered as an unordered
#                     factor (rounded to the underlying 9-point scale) instead
#                     of a quadratic, so the shape is not imposed at all.
#
# Checks 1-2 target the candidate-type-targeting and concentration results;
# check 3 targets single-peakedness (Hypothesis 1).

suppressPackageStartupMessages({ library(dplyr); library(fixest) })

PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")

d <- readRDS(paste0(PATH, "cand_model_data.RDS"))
d$singlename_partisan_pre <- factor(d$singlename_partisan_pre, levels = c("Other","GOP","DEM"))
d$incumbency <- factor(d$incumbency, levels = c("I","C","O"))
d$party      <- factor(d$party, levels = c("DEMOCRAT","REPUBLICAN"))

d$co_partisan_GOP    <- as.integer(d$party=="REPUBLICAN" & d$singlename_partisan_pre=="GOP")
d$cross_partisan_GOP <- as.integer(d$party=="DEMOCRAT"   & d$singlename_partisan_pre=="GOP")
d$co_partisan_DEM    <- as.integer(d$party=="DEMOCRAT"   & d$singlename_partisan_pre=="DEM")
d$cross_partisan_DEM <- as.integer(d$party=="REPUBLICAN" & d$singlename_partisan_pre=="DEM")
d$at_lo <- as.integer(d$favorability == -4)
d$at_hi <- as.integer(d$favorability ==  4)

base_controls <- "special + private + foreign + same_state + log(firm_cash) + party + incumbency"
cl <- ~ cmte_id + candidate_id
DUMS <- c("co_partisan_GOP","cross_partisan_GOP","co_partisan_DEM","cross_partisan_DEM")
curve <- paste(sapply(DUMS, function(v)
  sprintf("%s + favorability:%s + favorability_sq:%s", v, v, v)), collapse=" + ")
inc   <- paste(sapply(DUMS, function(v) sprintf("%s:incumbency", v)), collapse=" + ")

show_targeting <- function(m, label) {
  cf <- coef(m); se <- se(m)
  cat("\n--- ", label, " ---\n", sep="")
  for (v in c("co_partisan_GOP","cross_partisan_GOP")) for (lv in c("C","O")) {
    nm <- paste0("incumbency",lv,":",v)
    if (nm %in% names(cf)) cat(sprintf("  %-38s %8.4f (%.4f) p=%.4g\n",
        nm, cf[[nm]], se[[nm]], 2*pnorm(-abs(cf[[nm]]/se[[nm]]))))
  }
  for (nm in c("favorability:co_partisan_GOP","favorability_sq:co_partisan_GOP")) {
    if (nm %in% names(cf)) cat(sprintf("  %-38s %8.4f (%.4f) p=%.4g\n",
        nm, cf[[nm]], se[[nm]], 2*pnorm(-abs(cf[[nm]]/se[[nm]]))))
  }
}

# ---- (1) interior only -------------------------------------------------------
di <- d %>% filter(abs(favorability) < 4)
cat("=== CHECK 1: INTERIOR ONLY (|favorability| < 4) ===\n")
cat("dyads:", format(nrow(di), big.mark=","), " events:",
    format(sum(di$contribute==1, na.rm=TRUE), big.mark=","), "\n")
cat("cell counts (events) by dummy x candidate type:\n")
print(di %>% mutate(typ=ifelse(incumbency=="I","Inc","NonInc")) %>%
        filter(co_partisan_GOP==1 | cross_partisan_GOP==1) %>%
        mutate(rel=ifelse(co_partisan_GOP==1,"co","cross")) %>%
        group_by(rel,typ) %>% summarise(dyads=n(),
          events=sum(contribute==1,na.rm=TRUE), .groups="drop") %>% as.data.frame())

m1 <- feglm(as.formula(paste("contribute ~", base_controls,
            "+ favorability + favorability_sq +", curve, "+", inc, "| state + year")),
            data=di, family=binomial("logit"), cluster=cl)
saveRDS(m1, paste0(OUT_DIR,"BIMODAL_INTERIOR.RDS"))
writeLines(capture.output(summary(m1)), paste0(OUT_DIR,"BIMODAL_INTERIOR_coefficients.txt"))
show_targeting(m1, "interior only")

# ---- (2) endpoint indicators, full sample ------------------------------------
cat("\n\n=== CHECK 2: FULL SAMPLE + FREE ENDPOINT INDICATORS ===\n")
m2 <- feglm(as.formula(paste("contribute ~", base_controls,
            "+ at_lo + at_hi + favorability + favorability_sq +", curve, "+", inc,
            "| state + year")),
            data=d, family=binomial("logit"), cluster=cl)
saveRDS(m2, paste0(OUT_DIR,"BIMODAL_ENDPOINTS.RDS"))
writeLines(capture.output(summary(m2)), paste0(OUT_DIR,"BIMODAL_ENDPOINTS_coefficients.txt"))
show_targeting(m2, "endpoint indicators")
cf<-coef(m2); se<-se(m2)
for (nm in c("at_lo","at_hi")) cat(sprintf("  %-38s %8.4f (%.4f)\n", nm, cf[[nm]], se[[nm]]))

# ---- (3) nonparametric shape -------------------------------------------------
cat("\n\n=== CHECK 3: FAVORABILITY AS UNORDERED FACTOR (baseline, H1) ===\n")
d$fav_f <- factor(round(d$favorability), levels = -4:4)
m3 <- feglm(as.formula(paste("contribute ~ special + private + foreign + same_state +",
            "log(firm_cash) + party + incumbency + fav_f | state + year")),
            data=d, family=binomial("logit"), cluster=cl)
saveRDS(m3, paste0(OUT_DIR,"BIMODAL_FACTOR.RDS"))
writeLines(capture.output(summary(m3)), paste0(OUT_DIR,"BIMODAL_FACTOR_coefficients.txt"))
cf<-coef(m3); se<-se(m3)
cat("  fitted level at each rounded favorability value (reference = -4):\n")
for (lv in -3:4) {
  nm <- paste0("fav_f",lv)
  if (nm %in% names(cf)) cat(sprintf("    %-6s %8.4f (%.4f)\n", lv, cf[[nm]], se[[nm]]))
}
cat("\nDone.\n")
