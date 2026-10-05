# Level test for the gated 2x2: does an aligned firm give MORE than a
# non-advantaged firm to a given kind of candidate, holding candidate party and
# candidate type fixed?
#
# This is the gate for the paper's non-incumbent analysis. The location/density
# question ("where in the favorability distribution does that money go?") is
# only motivated for cells where a level difference exists in the first place.
# Estimand deliberately contains NO sector-by-favorability interaction: it is a
# pure level comparison, which is what the gating argument invokes.
#
# Run separately for each alignment side, with the corresponding candidate party
# labelled co- or cross-partisan from that side's point of view.
#
# Output: model/sector_alignment/level_test_by_cell.csv

suppressPackageStartupMessages({ library(dplyr); library(fixest) })
PATH <- "/htaa/hhe/projects/election_buying/"

d0 <- readRDS(paste0(PATH, "cand_model_data.RDS"))
ctrl <- "special + private + foreign + same_state + log(firm_cash) + favorability + favorability_sq"

run_side <- function(side) {
  own_party <- if (side == "GOP") "REPUBLICAN" else "DEMOCRAT"
  d <- d0 %>%
    filter(!is.na(singlename_partisan_pre),
           singlename_partisan_pre %in% c(side, "Other")) %>%
    mutate(sector    = factor(singlename_partisan_pre, levels = c("Other", side)),
           cand_type = ifelse(incumbency == "I", "Incumbent", "NonIncumbent"),
           relation  = ifelse(party == own_party, "co-partisan", "cross-partisan"))

  out <- list()
  for (ct in c("Incumbent", "NonIncumbent")) {
    for (rel in c("co-partisan", "cross-partisan")) {
      sub <- d %>% filter(cand_type == ct, relation == rel)
      n_al <- sum(sub$sector == side)
      ev_al <- sum(sub$contribute[sub$sector == side] == 1, na.rm = TRUE)
      m <- feglm(as.formula(paste("contribute ~ sector +", ctrl, "| state + year")),
                 data = sub, family = binomial("logit"), cluster = ~ cmte_id + candidate_id)
      nm <- paste0("sector", side)
      cf <- coef(m)[nm]; se <- se(m)[nm]; p <- 2 * pnorm(-abs(cf / se))
      out[[paste(ct, rel)]] <- data.frame(
        side = side, cand_type = ct, relation = rel,
        aligned_dyads = n_al, aligned_events = ev_al,
        est = as.numeric(cf), se = as.numeric(se),
        odds_ratio = exp(as.numeric(cf)), p = as.numeric(p))
      cat(sprintf("  [%s] %-13s %-15s  aligned n=%7d ev=%6d  OR=%6.3f  p=%.3g\n",
                  side, ct, rel, n_al, ev_al, exp(cf), p))
    }
  }
  do.call(rbind, out)
}

cat("=== LEVEL TEST: aligned vs non-advantaged firms, same candidate party & type ===\n\n")
res <- rbind(run_side("GOP"), run_side("DEM"))
write.csv(res, paste0(PATH, "model/sector_alignment/level_test_by_cell.csv"), row.names = FALSE)

cat("\n=== TABLE-READY ===\n")
print(res %>% mutate(across(c(est, se, odds_ratio), ~round(.x, 4)),
                     p = signif(p, 3)) %>% as.data.frame(), row.names = FALSE)
cat("\nDone.\n")
