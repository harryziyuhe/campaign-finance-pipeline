# Continuous-measure counterpart to asymmetric_full_curveshape_nofe.R.
#
# The full-curve specification was the only main-text model fit on the
# categorical measure alone, while the baseline (ASYM_BASE_*) and
# incumbency-interacted (ASYM_INCUMBENCY_*) models are each reported on both
# measures. This closes that gap so the appendix full table can carry a
# continuous column and the measurement choice is visible rather than implicit.
#
# Specification is identical to the categorical version in every respect --
# same controls, same fully-flexible baseline curve, same state + year FE, same
# two-way clustering, same three-way interaction structure. The ONLY change is
# the four alignment variables: co_/cross_partisan_{GOP,DEM} dummies are
# replaced by the score_co_/score_cross_{GOP,DEM} continuous variables, built
# exactly as in asymmetric_pooled_nofe.R.
# =============================================================================
library(dplyr)
library(fixest)

PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")

.args     <- commandArgs(trailingOnly = TRUE)
DATA_NAME <- if (length(.args) >= 1) .args[1] else "cand_model_data"
SUFFIX    <- if (length(.args) >= 2) .args[2] else ""
MOD_NAME  <- paste0("ASYM_FULLCURVE_CONTINUOUS", SUFFIX)

cat("Input data:   ", DATA_NAME, ".RDS\n", sep = "")
cat("Output model: ", MOD_NAME, "\n", sep = "")
cand_data <- readRDS(paste0(PATH, DATA_NAME, ".RDS"))

cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre, levels = c("Other", "GOP", "DEM"))
cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))
cand_data$incumbency_bin <- factor(ifelse(cand_data$incumbency == "I", "Incumbent", "NonIncumbent"),
                                    levels = c("Incumbent", "NonIncumbent"))
cand_data$party <- factor(cand_data$party, levels = c("DEMOCRAT", "REPUBLICAN"))

# Continuous alignment, identical construction to asymmetric_pooled_nofe.R:87-90.
singlename_GOP_pre <- pmax(cand_data$singlename_score_pre, 0)
singlename_DEM_pre <- pmax(-cand_data$singlename_score_pre, 0)
cand_data$score_co_GOP    <- singlename_GOP_pre * (cand_data$party == "REPUBLICAN")
cand_data$score_cross_GOP <- singlename_GOP_pre * (cand_data$party == "DEMOCRAT")
cand_data$score_co_DEM    <- singlename_DEM_pre * (cand_data$party == "DEMOCRAT")
cand_data$score_cross_DEM <- singlename_DEM_pre * (cand_data$party == "REPUBLICAN")

cat("=== continuous alignment support, by incumbency_bin ===\n")
for (v in c("score_co_GOP", "score_cross_GOP", "score_co_DEM", "score_cross_DEM")) {
  nz <- !is.na(cand_data[[v]]) & cand_data[[v]] > 0   # score is NA for unscored sectors
  cat(sprintf("  %-16s nonzero=%9d  mean|nonzero=%.4f  events=%d\n",
              v, sum(nz), mean(cand_data[[v]][nz]),
              sum(cand_data$contribute[nz], na.rm = TRUE)))
}

base_controls <- "special + private + foreign + same_state + log(firm_cash)"
S <- c("score_co_GOP", "score_cross_GOP", "score_co_DEM", "score_cross_DEM")

# Mirrors the categorical rhs term-for-term.
blocks <- unlist(lapply(S, function(v) paste(
  v, paste0("favorability:", v), paste0("favorability_sq:", v), sep = " + ")))
shifts <- unlist(lapply(S, function(v) paste(
  paste0(v, ":incumbency_bin"),
  paste0("favorability:", v, ":incumbency_bin"),
  paste0("favorability_sq:", v, ":incumbency_bin"), sep = " + ")))

rhs <- paste(c(base_controls,
  "favorability * incumbency * party + favorability_sq * incumbency * party",
  blocks, shifts), collapse = " + ")
fmla <- as.formula(paste("contribute ~", rhs, "| state + year"))

cat("\nFitting full curve-shape asymmetric model (continuous, no firm FE)...\n")
t0 <- Sys.time()
mod <- feglm(fmla, data = cand_data, family = binomial(link = "logit"), cluster = ~ cmte_id + candidate_id)
cat("fit time:", as.numeric(Sys.time() - t0, units = "mins"), "min\n")
saveRDS(mod, paste0(OUT_DIR, MOD_NAME, ".RDS"))
writeLines(capture.output(summary(mod)), paste0(OUT_DIR, MOD_NAME, "_coefficients.txt"))
cat("N =", format(nobs(mod), big.mark = ","), "\n")

# Confirm every term the appendix table asks for is actually present, so a
# missing-coefficient problem surfaces here rather than as a blank table cell.
cf <- coef(mod)
want <- c(S,
          paste0("favorability:", S), paste0("favorability_sq:", S),
          paste0("incumbency_binNonIncumbent:", S),
          paste0("favorability:incumbency_binNonIncumbent:", S),
          paste0("favorability_sq:incumbency_binNonIncumbent:", S))
perm <- function(nm) {  # fixest may order interaction parts either way
  p <- strsplit(nm, ":")[[1]]
  any(sapply(list(p, rev(p)), function(q) paste(q, collapse = ":") %in% names(cf))) ||
    any(names(cf) %in% apply(gtools::permutations(length(p), length(p)), 1,
                             function(i) paste(p[i], collapse = ":")))
}
missing <- want[!sapply(want, perm)]
cat("\n=== table-term availability ===\n")
if (length(missing)) { cat("MISSING:\n"); cat(paste0("  ", missing, collapse = "\n"), "\n") } else
  cat("  all 24 table terms present\n")

cat("\n=== S_i channel (co-partisan), Incumbent reference ===\n")
gr <- function(nm) {
  hit <- names(cf)[sapply(names(cf), function(k)
    setequal(strsplit(k, ":")[[1]], strsplit(nm, ":")[[1]]))]
  if (!length(hit)) return(sprintf("%-60s MISSING", nm))
  V <- vcov(mod); est <- cf[[hit[1]]]; s <- sqrt(V[hit[1], hit[1]])
  sprintf("%-60s est=%+.4f se=%.4f p=%.4g", hit[1], est, s, 2 * pnorm(-abs(est / s)))
}
for (v in S) for (t in c(paste0("favorability:", v), paste0("favorability_sq:", v),
                         paste0("favorability:incumbency_binNonIncumbent:", v),
                         paste0("favorability_sq:incumbency_binNonIncumbent:", v)))
  cat(gr(t), "\n")
cat("\nDone.\n")
