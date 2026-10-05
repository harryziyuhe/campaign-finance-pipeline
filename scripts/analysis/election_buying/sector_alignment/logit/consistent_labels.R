# Consistency-based alignment labels.
#
# Motivation. Each measure exists in two constructions built over different
# event windows ("_pre" and "_all"). The stability diagnostic showed that the
# strongly-scored sectors are reproducible across both while the weakly-scored
# middle is not merely noisy but SIGN-UNSTABLE: Automobile runs -0.375 -> +0.246,
# Insurance -0.105 -> +0.371, Healthcare -0.146 -> +0.266, and Consumer Products
# -0.396 -> -0.027. A sector whose estimated partisan advantage changes sign
# between constructions has no reproducible directional advantage, and labelling
# it from a single construction is what produced the misclassification corrected
# in subsec:robust6.
#
# A label that requires agreement across BOTH constructions therefore encodes
# the threshold the data actually support, rather than a cutoff on one estimate.
#
# Rule: label a sector GOP (DEM) only if BOTH scores exceed +t (fall below -t).
# Anything sign-inconsistent, or consistent but weak, or missing either score,
# is Other. Applied to singlename and ETF separately, then compared.
#
# Validation: a good label should produce a DEM bucket that actually tilts
# Democratic (rate_D / rate_R > 1) and a GOP bucket that tilts Republican.
# The current ETF DEM bucket fails this badly (tilt 0.73).

suppressPackageStartupMessages({ library(dplyr) })
PATH <- "/htaa/hhe/projects/election_buying/"
d <- readRDS(paste0(PATH, "cand_model_data_v2.RDS")) %>%
  mutate(cand = ifelse(party == "REPUBLICAN", "R", "D"))

sec <- d %>% filter(!is.na(category)) %>% group_by(category) %>%
  summarise(firms = n_distinct(cmte_id), dyads = n(),
            events = sum(contribute == 1, na.rm = TRUE),
            sn_pre = first(singlename_score_pre), sn_all = first(singlename_score_all),
            etf_pre = first(etf_score_pre),       etf_all = first(etf_score_all),
            rate_D = 100*mean(contribute[cand=="D"] == 1, na.rm = TRUE),
            rate_R = 100*mean(contribute[cand=="R"] == 1, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(tilt = rate_D / rate_R)

label_consistent <- function(p, a, t) {
  ifelse(is.na(p) | is.na(a), "Other",
    ifelse(p >  t & a >  t, "GOP",
    ifelse(p < -t & a < -t, "DEM", "Other")))
}

for (t in c(0.3, 0.4, 0.5)) {
  cat("\n", strrep("=", 68), "\n threshold |score| > ", t,
      " required in BOTH constructions\n", strrep("=", 68), "\n", sep = "")
  s <- sec %>% mutate(sn_lab = label_consistent(sn_pre, sn_all, t),
                      etf_lab = label_consistent(etf_pre, etf_all, t))

  for (meas in c("sn", "etf")) {
    lab <- s[[paste0(meas, "_lab")]]
    cat("\n--", if (meas=="sn") "SINGLENAME" else "ETF", "--\n")
    mem <- s %>% mutate(lab = lab) %>% filter(lab != "Other") %>%
      select(category, firms, lab,
             pre = !!sym(paste0(meas,"_pre")), all = !!sym(paste0(meas,"_all")), tilt) %>%
      arrange(lab, pre)
    if (nrow(mem)) print(as.data.frame(mem %>% mutate(across(c(pre,all,tilt), ~round(.x,3)))),
                         row.names = FALSE) else cat("  (no sector labelled)\n")
    # bucket-level behaviour, weighted by dyads
    agg <- d %>% left_join(s %>% mutate(lab = lab) %>% select(category, lab), by = "category") %>%
      filter(!is.na(lab)) %>% group_by(lab) %>%
      summarise(firms = n_distinct(cmte_id), dyads = n(),
                events = sum(contribute == 1, na.rm = TRUE),
                rate_D = 100*mean(contribute[cand=="D"] == 1, na.rm = TRUE),
                rate_R = 100*mean(contribute[cand=="R"] == 1, na.rm = TRUE), .groups = "drop") %>%
      mutate(tilt = round(rate_D / rate_R, 2))
    cat("  bucket behaviour:\n")
    print(as.data.frame(agg %>% mutate(across(c(rate_D,rate_R), ~round(.x,3)))), row.names = FALSE)
  }
}

cat("\n", strrep("=", 68), "\n current labels, for comparison\n", strrep("=", 68), "\n", sep="")
cur <- d %>% filter(!is.na(singlename_partisan_pre), trimws(singlename_partisan_pre) != "") %>%
  group_by(singlename_partisan_pre) %>%
  summarise(firms = n_distinct(cmte_id), dyads = n(),
            events = sum(contribute == 1, na.rm = TRUE),
            rate_D = round(100*mean(contribute[cand=="D"] == 1, na.rm = TRUE), 3),
            rate_R = round(100*mean(contribute[cand=="R"] == 1, na.rm = TRUE), 3), .groups="drop") %>%
  mutate(tilt = round(rate_D/rate_R, 2))
print(as.data.frame(cur), row.names = FALSE)
cat("\nDone.\n")
