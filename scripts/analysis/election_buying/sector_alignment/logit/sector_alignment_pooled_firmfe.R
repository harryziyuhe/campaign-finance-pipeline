library(dplyr)
library(fixest)

# =============================================================================
# Fully pooled (both parties, all candidate types), firm-FE design.
#
# Replaces the single-party-split approach: co_partisan_GOP and co_partisan_DEM
# are defined over the FULL sample (not restricted to one party's targets), so
# each varies WITHIN firm (a GOP-aligned firm has co_partisan_GOP=1 for
# Republican targets, =0 for Democrat targets) -- this lets firm FE do its
# proper job: identify the co-partisan effect from within-firm comparisons
# (does this SAME firm behave differently toward its own party's candidates
# vs. the other party's), rather than the weaker between-firm
# residual-slope-shape comparison the single-party-split + firm-FE combination
# was forced into (see docs/theory_revision_handoff.md §9 for that finding).
#
# Baseline curve: fully flexible by candidate type AND target party
# ((favorability+favorability_sq) * incumbency * party) -- lets Challenger,
# Open-seat, Incumbent x Republican-target, Democrat-target each have their
# own curve, generalizing the earlier C-vs-O baseline-curve-differs finding
# to also allow for a party-of-target difference.
#
# Aligned-shift: co_partisan_GOP and co_partisan_DEM each get their own
# Incumbent-reference shift (H3 test) plus an additional NonIncumbent-only
# increment via incumbency_bin (pooling Challenger+Open-seat for the shift
# term specifically, as licensed by the earlier per-party Wald tests -- H4
# test). Main (level) effects of co_partisan_GOP/DEM are now well-identified
# under firm FE (within-firm variation exists) and give a direct H2 test.
# =============================================================================
PATH <- "/htaa/hhe/projects/election_buying/"
cand_data <- readRDS(paste0(PATH, "cand_model_data.RDS"))

cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre, levels = c("Other", "GOP", "DEM"))
cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))
cand_data$incumbency_bin <- factor(ifelse(cand_data$incumbency == "I", "Incumbent", "NonIncumbent"),
                                    levels = c("Incumbent", "NonIncumbent"))
cand_data$party <- factor(cand_data$party, levels = c("DEMOCRAT", "REPUBLICAN"))

cand_data$co_partisan_GOP <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "GOP")
cand_data$co_partisan_DEM <- as.integer(cand_data$party == "DEMOCRAT" & cand_data$singlename_partisan_pre == "DEM")

cat("=== within-firm variation check (does co_partisan_GOP/DEM vary within firm?) ===\n")
chk <- cand_data %>% group_by(cmte_id) %>%
  summarise(gop_varies = n_distinct(co_partisan_GOP) > 1,
            dem_varies = n_distinct(co_partisan_DEM) > 1, .groups = "drop")
cat("n firms where co_partisan_GOP varies within firm:", sum(chk$gop_varies), "of", nrow(chk), "\n")
cat("n firms where co_partisan_DEM varies within firm:", sum(chk$dem_varies), "of", nrow(chk), "\n")

base_controls <- "special + private + foreign + same_state + log(firm_cash)"

rhs <- paste(
  base_controls,
  "favorability * incumbency * party + favorability_sq * incumbency * party",
  "co_partisan_GOP + favorability:co_partisan_GOP + favorability_sq:co_partisan_GOP",
  "co_partisan_DEM + favorability:co_partisan_DEM + favorability_sq:co_partisan_DEM",
  "co_partisan_GOP:incumbency_bin + favorability:co_partisan_GOP:incumbency_bin + favorability_sq:co_partisan_GOP:incumbency_bin",
  "co_partisan_DEM:incumbency_bin + favorability:co_partisan_DEM:incumbency_bin + favorability_sq:co_partisan_DEM:incumbency_bin",
  sep = " + "
)
fmla <- as.formula(paste("contribute ~", rhs, "| cmte_id + state + year"))

cat("\nFitting pooled two-dummy firm-FE model...\n")
mod <- feglm(fmla, data = cand_data, family = binomial(link = "logit"), cluster = ~ cmte_id + candidate_id)
print(summary(mod))
saveRDS(mod, paste0(PATH, "model/sector_alignment/POOLED_FIRMFE.RDS"))
writeLines(capture.output(summary(mod)), paste0(PATH, "model/sector_alignment/POOLED_FIRMFE_coefficients.txt"))

cf <- coef(mod); V <- vcov(mod)
get_row <- function(nm) {
  if (!nm %in% names(cf)) return(sprintf("%s: MISSING", nm))
  est <- cf[[nm]]; s <- sqrt(V[nm, nm])
  sprintf("%-70s est=%.4f se=%.4f p=%.4g", nm, est, s, 2*pnorm(-abs(est/s)))
}

cat("\n=== H2: within-firm co-partisan level effect ===\n")
cat(get_row("co_partisan_GOP"), "\n")
cat(get_row("co_partisan_DEM"), "\n")

cat("\n=== H3: Incumbent-reference aligned slope/curvature shift (no-rescue check) ===\n")
cat(get_row("favorability:co_partisan_GOP"), "\n")
cat(get_row("favorability_sq:co_partisan_GOP"), "\n")
cat(get_row("favorability:co_partisan_DEM"), "\n")
cat(get_row("favorability_sq:co_partisan_DEM"), "\n")

cat("\n=== H4: additional NonIncumbent aligned slope/curvature shift (bench-packing check) ===\n")
cat(get_row("favorability:co_partisan_GOP:incumbency_binNonIncumbent"), "\n")
cat(get_row("favorability_sq:co_partisan_GOP:incumbency_binNonIncumbent"), "\n")
cat(get_row("favorability:co_partisan_DEM:incumbency_binNonIncumbent"), "\n")
cat(get_row("favorability_sq:co_partisan_DEM:incumbency_binNonIncumbent"), "\n")

cat("\n=== NonIncumbent-level effects (co_partisan_GOP/DEM:incumbency_bin) ===\n")
cat(get_row("co_partisan_GOP:incumbency_binNonIncumbent"), "\n")
cat(get_row("co_partisan_DEM:incumbency_binNonIncumbent"), "\n")
