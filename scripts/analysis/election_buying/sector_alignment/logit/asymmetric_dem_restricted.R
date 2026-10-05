library(dplyr)
library(fixest)

# =============================================================================
# Formalizes the DEM-restricted continuous-measure diagnostic
# (scripts/logit/wrinkle_diagnostics.R) into a saved robustness model, for
# Appendix~\ref{appendix:robust}. Confirms that the raw continuous-measure
# Democratic-side coefficients in Table~\ref{tab:asym_incumbency} are
# contaminated by weak/moderate negative-score "Other"-labeled sectors
# (Consumer Products, Healthcare, Utilities, etc. -- Renewables is the only
# category the categorical measure actually labels DEM) by re-estimating the
# same incumbency-interacted continuous specification with the DEM continuous
# variables zeroed out for anything not also categorically DEM-labeled
# (collapsing the DEM-side sample to essentially Renewables-only).
# =============================================================================
PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")
cand_data <- readRDS(paste0(PATH, "cand_model_data.RDS"))

cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre, levels = c("Other", "GOP", "DEM"))
cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))
cand_data$party <- factor(cand_data$party, levels = c("DEMOCRAT", "REPUBLICAN"))

cand_data$co_partisan_GOP    <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "GOP")
cand_data$cross_partisan_GOP <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "GOP")

singlename_GOP_pre <- pmax(cand_data$singlename_score_pre, 0)
singlename_DEM_pre <- pmax(-cand_data$singlename_score_pre, 0)
cand_data$score_co_GOP    <- singlename_GOP_pre * (cand_data$party == "REPUBLICAN")
cand_data$score_cross_GOP <- singlename_GOP_pre * (cand_data$party == "DEMOCRAT")

# DEM continuous variables RESTRICTED to categorically-DEM sectors (i.e.,
# Renewables) -- zero everywhere else, unlike the main-text Table 3 continuous
# column which uses the raw, unrestricted score.
score_co_DEM_all    <- singlename_DEM_pre * (cand_data$party == "DEMOCRAT")
score_cross_DEM_all <- singlename_DEM_pre * (cand_data$party == "REPUBLICAN")
cand_data$score_co_DEM_restricted    <- score_co_DEM_all    * as.integer(cand_data$singlename_partisan_pre == "DEM")
cand_data$score_cross_DEM_restricted <- score_cross_DEM_all * as.integer(cand_data$singlename_partisan_pre == "DEM")

cat("N score_co_DEM (unrestricted) > 0:   ", sum(score_co_DEM_all > 0, na.rm = TRUE), "\n")
cat("N score_co_DEM (restricted) > 0:     ", sum(cand_data$score_co_DEM_restricted > 0, na.rm = TRUE), "\n")

base_controls <- "special + private + foreign + same_state + log(firm_cash) + party + incumbency"
rhs <- paste(
  base_controls,
  "favorability + favorability_sq",
  "co_partisan_GOP + favorability:co_partisan_GOP + favorability_sq:co_partisan_GOP",
  "cross_partisan_GOP + favorability:cross_partisan_GOP + favorability_sq:cross_partisan_GOP",
  "score_co_DEM_restricted + favorability:score_co_DEM_restricted + favorability_sq:score_co_DEM_restricted",
  "score_cross_DEM_restricted + favorability:score_cross_DEM_restricted + favorability_sq:score_cross_DEM_restricted",
  "co_partisan_GOP:incumbency + cross_partisan_GOP:incumbency",
  "score_co_DEM_restricted:incumbency + score_cross_DEM_restricted:incumbency",
  sep = " + "
)
fmla <- as.formula(paste("contribute ~", rhs, "| state + year"))

cat("\nFitting DEM-restricted-to-categorical-DEM continuous model (incumbency-interacted)...\n")
mod <- feglm(fmla, data = cand_data, family = binomial(link = "logit"), cluster = ~ cmte_id + candidate_id)
saveRDS(mod, paste0(OUT_DIR, "ASYM_INCUMBENCY_CONTINUOUS_DEM_RESTRICTED.RDS"))
writeLines(capture.output(summary(mod)), paste0(OUT_DIR, "ASYM_INCUMBENCY_CONTINUOUS_DEM_RESTRICTED_coefficients.txt"))

cf <- coef(mod); V <- vcov(mod)
get_row <- function(nm) {
  if (!nm %in% names(cf)) return(cat(sprintf("%s: MISSING\n", nm)))
  est <- cf[[nm]]; s <- sqrt(V[nm, nm])
  cat(sprintf("%-45s est=%.4f se=%.4f p=%.4g\n", nm, est, s, 2 * pnorm(-abs(est / s))))
}
cat("\n=== DEM-restricted results (compare to unrestricted Table 3 continuous column) ===\n")
for (nm in c("score_co_DEM_restricted", "score_cross_DEM_restricted",
             "favorability:score_co_DEM_restricted", "favorability_sq:score_co_DEM_restricted",
             "favorability:score_cross_DEM_restricted", "favorability_sq:score_cross_DEM_restricted",
             "incumbencyC:score_co_DEM_restricted", "incumbencyO:score_co_DEM_restricted",
             "incumbencyC:score_cross_DEM_restricted", "incumbencyO:score_cross_DEM_restricted")) get_row(nm)

cat("\nDone.\n")
