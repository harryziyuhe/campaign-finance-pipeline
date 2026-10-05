library(dplyr)
library(fixest)

# =============================================================================
# Firm (cmte_id) fixed-effects version of sector_alignment_hybrid_pool.R.
# Adds firm FE on top of the existing log(firm_cash) control, state+year FE.
#
# Identification check: within a single-party subsample (e.g. Republican-only
# candidates), co_partisan_snp is firm-invariant (it depends only on the
# firm's own sector alignment, which doesn't change within a subsample where
# candidate party is fixed) -- so co_partisan_snp's plain MAIN effect would be
# absorbed by firm FE. But every term of actual interest here is an
# INTERACTION of co_partisan_snp with favorability (a within-firm-varying
# regressor, since a given firm targets many different candidates across the
# favorability range) -- those remain identified off within-firm variation in
# the favorability-giving slope, exactly like a standard panel
# time-invariant-characteristic x time-varying-regressor design. Firm FE
# nets out each firm's overall giving propensity level; the slope/curvature
# interaction coefficients are the thing being tested either way.
# =============================================================================
PATH <- "/htaa/hhe/projects/election_buying/"
cand_data <- readRDS(paste0(PATH, "cand_model_data.RDS"))

cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre, levels = c("Other", "GOP", "DEM"))
cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))
cand_data$incumbency_bin <- factor(ifelse(cand_data$incumbency == "I", "Incumbent", "NonIncumbent"),
                                    levels = c("Incumbent", "NonIncumbent"))
cand_data$co_partisan_snp <- dplyr::case_when(
  cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "GOP" ~ 1,
  cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "DEM" ~ 1,
  TRUE ~ 0
)

# co_partisan_snp's main effect will be collinear with firm FE (see note
# above) -- drop it from the RHS rather than let fixest silently absorb it,
# and drop the (non-favorability-interacted) co_partisan_snp:incumbency_bin
# level term for the same reason. Keep every favorability-interacted term.
base_controls <- "favorability + favorability_sq + special + private + foreign + same_state + log(firm_cash)"

fit_hybrid_fe <- function(party_val, label) {
  cat("\n=====", label, "(firm FE) =====\n")
  d <- cand_data %>% filter(party == party_val) %>% droplevels()

  rhs <- paste(
    base_controls,
    "favorability:incumbency + favorability_sq:incumbency",
    "favorability:co_partisan_snp + favorability_sq:co_partisan_snp",
    "favorability:co_partisan_snp:incumbency_bin + favorability_sq:co_partisan_snp:incumbency_bin",
    "incumbency",
    sep = " + "
  )
  fmla <- as.formula(paste("contribute ~", rhs, "| cmte_id + state + year"))
  mod <- feglm(fmla, data = d, family = binomial(link="logit"), cluster = ~cmte_id + candidate_id)
  print(summary(mod))
  saveRDS(mod, paste0(PATH, "model/sector_alignment/HYBRID_FIRMFE_", label, ".RDS"))

  cf <- coef(mod); V <- vcov(mod)
  bNI1 <- cf[["favorability:co_partisan_snp:incumbency_binNonIncumbent"]]
  bNI2 <- cf[["favorability_sq:co_partisan_snp:incumbency_binNonIncumbent"]]
  se_bNI1 <- sqrt(V["favorability:co_partisan_snp:incumbency_binNonIncumbent","favorability:co_partisan_snp:incumbency_binNonIncumbent"])
  se_bNI2 <- sqrt(V["favorability_sq:co_partisan_snp:incumbency_binNonIncumbent","favorability_sq:co_partisan_snp:incumbency_binNonIncumbent"])
  cat(sprintf("\nfv:co_partisan_snp:NonIncumbent (firm FE)  est=%.4f se=%.4f z=%.3f p=%.4g\n",
              bNI1, se_bNI1, bNI1/se_bNI1, 2*pnorm(-abs(bNI1/se_bNI1))))
  cat(sprintf("fv_sq:co_partisan_snp:NonIncumbent (firm FE) est=%.4f se=%.4f z=%.3f p=%.4g\n",
              bNI2, se_bNI2, bNI2/se_bNI2, 2*pnorm(-abs(bNI2/se_bNI2))))

  b3 <- cf[["favorability:co_partisan_snp"]]; b4 <- cf[["favorability_sq:co_partisan_snp"]]
  se_b3 <- sqrt(V["favorability:co_partisan_snp","favorability:co_partisan_snp"])
  cat(sprintf("fv:co_partisan_snp (Incumbent-reference, firm FE) est=%.4f se=%.4f p=%.4g  [H3 no-rescue check]\n",
              b3, se_b3, 2*pnorm(-abs(b3/se_b3))))
}

fit_hybrid_fe("REPUBLICAN", "Republican")
fit_hybrid_fe("DEMOCRAT", "Democrat")
