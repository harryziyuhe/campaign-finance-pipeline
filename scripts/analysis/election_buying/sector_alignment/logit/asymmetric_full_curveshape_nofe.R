library(dplyr)
library(fixest)

# =============================================================================
# "Table 4": full curve-shape asymmetric model. Consolidates the out-party-
# incumbent hedging (H_i) finding -- previously estimated in ad hoc single-
# party-subsample scripts (scripts/logit/sector_alignment_partisan.R) -- into
# the SAME pooled, fully-crossed 4-dummy framework as
# scripts/logit/asymmetric_pooled_nofe.R, so S_i (co-partisan) and H_i
# (cross-partisan) channels are directly comparable coefficients from one
# model rather than results from separate scripts with different samples.
#
# Unlike asymmetric_pooled_nofe.R's Table 2/3 analogs (which deliberately
# mirror the OLD table's additive-only incumbency interaction, to keep an
# apples-to-apples "before/after" comparison clean), this model lets
# favorability AND favorability_sq interact fully with incumbency_bin for
# every one of the 4 asymmetric dummies -- this is what's actually needed to
# see the H_i hedging shape (single-peaked at moderate risk, not monotonic)
# distinctly from the S_i bench-packing shape (peak shifts toward longshots).
#
# Baseline curve is fully flexible by incumbency x party
# (favorability*incumbency*party), same convention as
# scripts/logit/sector_alignment_pooled_firmfe.R, but WITHOUT firm FE here
# (state+year only) -- the firm-FE version is a separate extension/robustness
# script, not this one (docs/theory_revision_handoff.md §10.2 placement
# decision, task #14, still open).
# =============================================================================
PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")

# Optional args (same convention as asymmetric_pooled_nofe.R):
#   arg 1 = input RDS basename  (default "cand_model_data")
#   arg 2 = output name suffix  (default "", e.g. "_PREELECTION")
.args     <- commandArgs(trailingOnly = TRUE)
DATA_NAME <- if (length(.args) >= 1) .args[1] else "cand_model_data"
SUFFIX    <- if (length(.args) >= 2) .args[2] else ""
MOD_NAME  <- paste0("ASYM_FULLCURVE_NOFE", SUFFIX)

cat("Input data:   ", DATA_NAME, ".RDS\n", sep = "")
cat("Output model: ", MOD_NAME, "\n", sep = "")
cand_data <- readRDS(paste0(PATH, DATA_NAME, ".RDS"))

cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre, levels = c("Other", "GOP", "DEM"))
cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))
cand_data$incumbency_bin <- factor(ifelse(cand_data$incumbency == "I", "Incumbent", "NonIncumbent"),
                                    levels = c("Incumbent", "NonIncumbent"))
cand_data$party <- factor(cand_data$party, levels = c("DEMOCRAT", "REPUBLICAN"))

cand_data$co_partisan_GOP    <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "GOP")
cand_data$cross_partisan_GOP <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "GOP")
cand_data$co_partisan_DEM    <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "DEM")
cand_data$cross_partisan_DEM <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "DEM")

cat("=== within-incumbency_bin cell counts for cross_partisan dummies (thin-cell check, §4.4) ===\n")
for (v in c("cross_partisan_GOP", "cross_partisan_DEM")) {
  t <- cand_data %>% filter(.data[[v]] == 1) %>% count(incumbency_bin, contribute)
  cat(sprintf("-- %s --\n", v)); print(t)
}

base_controls <- "special + private + foreign + same_state + log(firm_cash)"

rhs <- paste(
  base_controls,
  "favorability * incumbency * party + favorability_sq * incumbency * party",
  "co_partisan_GOP + favorability:co_partisan_GOP + favorability_sq:co_partisan_GOP",
  "cross_partisan_GOP + favorability:cross_partisan_GOP + favorability_sq:cross_partisan_GOP",
  "co_partisan_DEM + favorability:co_partisan_DEM + favorability_sq:co_partisan_DEM",
  "cross_partisan_DEM + favorability:cross_partisan_DEM + favorability_sq:cross_partisan_DEM",
  "co_partisan_GOP:incumbency_bin + favorability:co_partisan_GOP:incumbency_bin + favorability_sq:co_partisan_GOP:incumbency_bin",
  "cross_partisan_GOP:incumbency_bin + favorability:cross_partisan_GOP:incumbency_bin + favorability_sq:cross_partisan_GOP:incumbency_bin",
  "co_partisan_DEM:incumbency_bin + favorability:co_partisan_DEM:incumbency_bin + favorability_sq:co_partisan_DEM:incumbency_bin",
  "cross_partisan_DEM:incumbency_bin + favorability:cross_partisan_DEM:incumbency_bin + favorability_sq:cross_partisan_DEM:incumbency_bin",
  sep = " + "
)
fmla <- as.formula(paste("contribute ~", rhs, "| state + year"))

cat("\nFitting full curve-shape asymmetric model (no FE)...\n")
t0 <- Sys.time()
mod <- feglm(fmla, data = cand_data, family = binomial(link = "logit"), cluster = ~ cmte_id + candidate_id)
cat("fit time:", as.numeric(Sys.time() - t0, units = "mins"), "min\n")
saveRDS(mod, paste0(OUT_DIR, MOD_NAME, ".RDS"))
writeLines(capture.output(summary(mod)), paste0(OUT_DIR, MOD_NAME, "_coefficients.txt"))

cf <- coef(mod); V <- vcov(mod)
get_row <- function(nm) {
  if (!nm %in% names(cf)) return(sprintf("%s: MISSING", nm))
  est <- cf[[nm]]; s <- sqrt(V[nm, nm])
  sprintf("%-65s est=%.4f se=%.4f p=%.4g", nm, est, s, 2 * pnorm(-abs(est / s)))
}
diff_row <- function(a, b) {
  if (!a %in% names(cf) || !b %in% names(cf)) return(cat(sprintf("  [%s vs %s] MISSING\n", a, b)))
  d <- cf[[a]] - cf[[b]]
  se <- sqrt(V[a, a] + V[b, b] - 2 * V[a, b])
  cat(sprintf("  %-45s vs %-45s diff=%.4f se=%.4f p=%.4g\n", a, b, d, se, 2 * pnorm(-abs(d / se))))
}

cat("\n=== S_i channel (co-partisan): Incumbent-reference slope/curvature ===\n")
cat(get_row("favorability:co_partisan_GOP"), "\n")
cat(get_row("favorability_sq:co_partisan_GOP"), "\n")
cat(get_row("favorability:co_partisan_DEM"), "\n")
cat(get_row("favorability_sq:co_partisan_DEM"), "\n")

cat("\n=== S_i channel: additional NonIncumbent shift (H4 bench-packing) ===\n")
cat(get_row("favorability:co_partisan_GOP:incumbency_binNonIncumbent"), "\n")
cat(get_row("favorability_sq:co_partisan_GOP:incumbency_binNonIncumbent"), "\n")
cat(get_row("favorability:co_partisan_DEM:incumbency_binNonIncumbent"), "\n")
cat(get_row("favorability_sq:co_partisan_DEM:incumbency_binNonIncumbent"), "\n")

cat("\n=== H_i channel (cross-partisan): Incumbent-reference slope/curvature (hedging test) ===\n")
cat(get_row("favorability:cross_partisan_GOP"), "\n")
cat(get_row("favorability_sq:cross_partisan_GOP"), "\n")
cat(get_row("favorability:cross_partisan_DEM"), "\n")
cat(get_row("favorability_sq:cross_partisan_DEM"), "\n")

cat("\n=== H_i channel: additional NonIncumbent shift (should be weak/absent per theory -- H_i is incumbent-specific) ===\n")
cat(get_row("favorability:cross_partisan_GOP:incumbency_binNonIncumbent"), "\n")
cat(get_row("favorability_sq:cross_partisan_GOP:incumbency_binNonIncumbent"), "\n")
cat(get_row("favorability:cross_partisan_DEM:incumbency_binNonIncumbent"), "\n")
cat(get_row("favorability_sq:cross_partisan_DEM:incumbency_binNonIncumbent"), "\n")

cat("\n=== DIRECT ASYMMETRY TEST at the Incumbent reference: S_i vs H_i slope/curvature ===\n")
diff_row("favorability:co_partisan_GOP", "favorability:cross_partisan_GOP")
diff_row("favorability_sq:co_partisan_GOP", "favorability_sq:cross_partisan_GOP")
diff_row("favorability:co_partisan_DEM", "favorability:cross_partisan_DEM")
diff_row("favorability_sq:co_partisan_DEM", "favorability_sq:cross_partisan_DEM")

cat("\nDone.\n")
