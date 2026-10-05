library(dplyr)
library(fixest)

# =============================================================================
# Reviewer-driven fix (reviewer_comments.md #1, docs/theory_revision_handoff.md
# §10.2): the paper's current Tables 2/3 interact favorability x sector-
# alignment (GOP-sector / DEM-sector), with the candidate's own party entering
# only as an additive control. That means a GOP-sector firm backing a
# vulnerable Democrat and a GOP-sector firm backing a vulnerable Republican
# load identically on "favorability x GOP-sector" -- exactly the asymmetry
# the reviewer flagged.
#
# Fix: replace the 2-dummy sector-only interaction (GOP-sector, DEM-sector)
# with a FULLY CROSSED 4-dummy design (sector-alignment x candidate's-own-
# party), so the same-party (co-partisan, S_i channel) and cross-party
# (cross-partisan, H_i/hedging channel) effects are separately identified in
# ONE pooled model:
#   co_partisan_GOP    = 1{candidate R, firm sector GOP-advantaged}
#   cross_partisan_GOP = 1{candidate D, firm sector GOP-advantaged}
#   co_partisan_DEM    = 1{candidate D, firm sector DEM-advantaged}
#   cross_partisan_DEM = 1{candidate R, firm sector DEM-advantaged}
# Reference category is "Other" (non-advantaged) sector, same as before.
# This directly answers the reviewer's literal question: are
# favorability:co_partisan_GOP and favorability:cross_partisan_GOP the same
# coefficient? (diagnostic z-test for the difference printed below.)
#
# Two alignment measures, mirroring the paper's existing continuous/
# categorical pair:
#   - categorical: co_partisan_GOP/DEM, cross_partisan_GOP/DEM built from
#     singlename_partisan_pre (Other/GOP/DEM)
#   - continuous:  score_co_GOP/DEM, score_cross_GOP/DEM built from
#     singlename_score_pre (magnitude of sector lean, party-signed)
# etf_score_pre is deliberately NOT used here -- it stays the dedicated
# robustness/agreement check (see docs §9), not a third main-table column.
#
# FE structure is state + year ONLY (no firm FE), matching the CURRENT
# paper's exact Table 2/3 specification, per the plan to swap this in as a
# direct apples-to-apples replacement (docs §10.2, user confirmed 2026-08-10).
# The already-built firm-FE / firm x cycle-FE versions are a separate
# robustness/extension track, not this script.
#
# Two model variants per measure, mirroring the paper's existing Table 2 /
# Table 3 split:
#   - "baseline": no interaction with incumbency (incumbency stays an
#     additive control) -- direct swap-in for old Table 2.
#   - "incumbency": adds co_partisan_*/cross_partisan_* x incumbency additive
#     (level-shift) interactions, exactly mirroring how old Table 3 added
#     Incumbent x GOP / Open Seat x GOP on top of the Table 2 spec (main
#     favorability x alignment slope terms are NOT re-interacted with
#     incumbency here, matching the old table's own structure) -- direct
#     swap-in for old Table 3.
# =============================================================================
PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

cand_data <- readRDS(paste0(PATH, "cand_model_data.RDS"))

cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre, levels = c("Other", "GOP", "DEM"))
cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))
cand_data$party <- factor(cand_data$party, levels = c("DEMOCRAT", "REPUBLICAN"))

# --- categorical (4-dummy, fully crossed) -----------------------------------
cand_data$co_partisan_GOP    <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "GOP")
cand_data$cross_partisan_GOP <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "GOP")
cand_data$co_partisan_DEM    <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "DEM")
cand_data$cross_partisan_DEM <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "DEM")

# --- continuous (4-variable, fully crossed) ---------------------------------
singlename_GOP_pre <- pmax(cand_data$singlename_score_pre, 0)
singlename_DEM_pre <- pmax(-cand_data$singlename_score_pre, 0)
cand_data$score_co_GOP    <- singlename_GOP_pre * (cand_data$party == "REPUBLICAN")
cand_data$score_cross_GOP <- singlename_GOP_pre * (cand_data$party == "DEMOCRAT")
cand_data$score_co_DEM    <- singlename_DEM_pre * (cand_data$party == "DEMOCRAT")
cand_data$score_cross_DEM <- singlename_DEM_pre * (cand_data$party == "REPUBLICAN")

cat("=== cell counts (categorical dummies) ===\n")
for (v in c("co_partisan_GOP", "cross_partisan_GOP", "co_partisan_DEM", "cross_partisan_DEM")) {
  n <- sum(cand_data[[v]]); events <- sum(cand_data$contribute[cand_data[[v]] == 1], na.rm = TRUE)
  cat(sprintf("  %-20s n=%d  events=%d  rate=%.4f%%\n", v, n, events, 100 * events / n))
}

base_controls <- "special + private + foreign + same_state + log(firm_cash) + party + incumbency"
cluster_fml <- ~ cmte_id + candidate_id

write_coef_txt <- function(mod, txt_path) {
  con <- file(txt_path, open = "wt"); on.exit(close(con))
  writeLines(capture.output(summary(mod)), con)
}
fit_save <- function(rhs, out_name) {
  fmla <- as.formula(paste("contribute ~", rhs, "| cmte_id + state + year"))
  t0 <- Sys.time()
  mod <- feglm(fmla, data = cand_data, family = binomial(link = "logit"), cluster = cluster_fml)
  cat(sprintf("  fit time (%s): %.2f min\n", out_name, as.numeric(Sys.time() - t0, units = "mins")))
  saveRDS(mod, paste0(OUT_DIR, out_name, ".RDS"))
  write_coef_txt(mod, paste0(OUT_DIR, out_name, "_coefficients.txt"))
  mod
}

diff_test <- function(mod, term_a, term_b) {
  cf <- coef(mod); V <- vcov(mod)
  if (!term_a %in% names(cf) || !term_b %in% names(cf)) return(cat(sprintf("  [%s vs %s] MISSING\n", term_a, term_b)))
  d <- cf[[term_a]] - cf[[term_b]]
  se <- sqrt(V[term_a, term_a] + V[term_b, term_b] - 2 * V[term_a, term_b])
  cat(sprintf("  %-45s %-45s diff=%.4f se=%.4f p=%.4g\n", term_a, term_b, d, se, 2 * pnorm(-abs(d / se))))
}

# =============================================================================
# 1) Baseline models (Table 2 analog)
# =============================================================================
rhs_base_cat <- paste(
  base_controls,
  "favorability + favorability_sq",
  "co_partisan_GOP + favorability:co_partisan_GOP + favorability_sq:co_partisan_GOP",
  "cross_partisan_GOP + favorability:cross_partisan_GOP + favorability_sq:cross_partisan_GOP",
  "co_partisan_DEM + favorability:co_partisan_DEM + favorability_sq:co_partisan_DEM",
  "cross_partisan_DEM + favorability:cross_partisan_DEM + favorability_sq:cross_partisan_DEM",
  sep = " + "
)
rhs_base_cont <- paste(
  base_controls,
  "favorability + favorability_sq",
  "score_co_GOP + favorability:score_co_GOP + favorability_sq:score_co_GOP",
  "score_cross_GOP + favorability:score_cross_GOP + favorability_sq:score_cross_GOP",
  "score_co_DEM + favorability:score_co_DEM + favorability_sq:score_co_DEM",
  "score_cross_DEM + favorability:score_cross_DEM + favorability_sq:score_cross_DEM",
  sep = " + "
)

# =============================================================================
# 2) Incumbency-interacted models (Table 3 analog): add level-shift
#    interactions with incumbency on top of the baseline spec, mirroring how
#    old Table 3 added Incumbent x GOP / Open Seat x GOP on top of Table 2.
# =============================================================================
rhs_inc_cat <- paste(
  rhs_base_cat,
  "co_partisan_GOP:incumbency + cross_partisan_GOP:incumbency",
  "co_partisan_DEM:incumbency + cross_partisan_DEM:incumbency",
  sep = " + "
)
rhs_inc_cont <- paste(
  rhs_base_cont,
  "score_co_GOP:incumbency + score_cross_GOP:incumbency",
  "score_co_DEM:incumbency + score_cross_DEM:incumbency",
  sep = " + "
)

cat("\nFitting incumbency-interacted categorical model WITH FIRM FE (robustness for Table 3)...\n")
mod_inc_cat <- fit_save(rhs_inc_cat, "ASYM_INCUMBENCY_CATEGORICAL_FIRMFE")
cat("\nFitting incumbency-interacted continuous model WITH FIRM FE (robustness for Table 3)...\n")
mod_inc_cont <- fit_save(rhs_inc_cont, "ASYM_INCUMBENCY_CONTINUOUS_FIRMFE")

cat("\n=== Candidate-type-targeting coefficients (firm FE) -- compare to Table 3 (no FE) ===\n")
get_row <- function(mod, nm) {
  cf <- coef(mod); V <- vcov(mod)
  if (!nm %in% names(cf)) return(cat(sprintf("%s: MISSING\n", nm)))
  est <- cf[[nm]]; s <- sqrt(V[nm, nm])
  cat(sprintf("%-45s est=%.4f se=%.4f p=%.4g\n", nm, est, s, 2 * pnorm(-abs(est / s))))
}
for (nm in c("incumbencyC:co_partisan_GOP", "incumbencyO:co_partisan_GOP",
             "incumbencyC:cross_partisan_GOP", "incumbencyO:cross_partisan_GOP")) get_row(mod_inc_cat, nm)
for (nm in c("incumbencyC:score_co_GOP", "incumbencyO:score_co_GOP",
             "incumbencyC:score_cross_GOP", "incumbencyO:score_cross_GOP")) get_row(mod_inc_cont, nm)

cat("\nDone.\n")
