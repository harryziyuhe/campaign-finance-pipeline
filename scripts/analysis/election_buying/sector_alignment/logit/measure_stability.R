# Two diagnostics on the alignment measures.
#
# (1) STABILITY. Each measure exists in two constructions, "_pre" and "_all",
#     built over different event windows. If the Democratic tail is populated by
#     estimation noise rather than genuine directional advantage, DEM-labelled
#     groups should be markedly less stable across the two constructions than
#     GOP-labelled ones. If DEM scores are stable but still fail to predict
#     giving, that points to genuine sensitivity without directional advantage,
#     which is a different and more interesting claim.
#
# (2) ETF AGREEMENT. `etf_*` is an independently constructed measure: it
#     aggregates cross-sectionally first and then temporally, where `singlename_*`
#     aggregates temporally first and then cross-sectionally. It is therefore a
#     check on the aggregation rule itself, not just on the classification
#     threshold. It has never been run on the co-partisan design.

suppressPackageStartupMessages({ library(dplyr) })
PATH <- "/htaa/hhe/projects/election_buying/"
d <- readRDS(paste0(PATH, "cand_model_data_v2.RDS"))

d <- d %>% mutate(cand = ifelse(party == "REPUBLICAN", "R", "D"),
                  ctype = ifelse(incumbency == "I", "Inc", "NonInc"))

cat("=== sector-level scores, both constructions, both measures ===\n")
tab <- d %>%
  filter(!is.na(category)) %>%
  group_by(category) %>%
  summarise(firms = n_distinct(cmte_id),
            sn_pre = round(first(singlename_score_pre), 3),
            sn_all = round(first(singlename_score_all), 3),
            etf_pre = round(first(etf_score_pre), 3),
            etf_all = round(first(etf_score_all), 3),
            sn_lab  = first(singlename_partisan_pre),
            etf_lab = first(etf_partisan),
            rate_D = 100*mean(contribute[cand=="D"] == 1, na.rm = TRUE),
            rate_R = 100*mean(contribute[cand=="R"] == 1, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(tilt = round(rate_D / rate_R, 2),
         sn_shift = round(sn_all - sn_pre, 3),
         etf_shift = round(etf_all - etf_pre, 3)) %>%
  arrange(sn_pre)
print(as.data.frame(tab %>% select(category, firms, sn_pre, sn_all, sn_shift,
                                   etf_pre, etf_all, etf_shift, sn_lab, etf_lab, tilt)),
      row.names = FALSE)

cat("\n=== stability: |score_all - score_pre| by label ===\n")
st <- tab %>% filter(!is.na(sn_lab), trimws(sn_lab) != "") %>%
  group_by(sn_lab) %>%
  summarise(groups = n(),
            mean_abs_shift_singlename = round(mean(abs(sn_shift), na.rm=TRUE), 3),
            mean_abs_shift_etf        = round(mean(abs(etf_shift), na.rm=TRUE), 3),
            .groups = "drop")
print(as.data.frame(st), row.names = FALSE)

cat("\n  correlation singlename pre vs all: ",
    round(cor(tab$sn_pre, tab$sn_all, use = "complete.obs"), 4), "\n")
cat("  correlation etf pre vs all:        ",
    round(cor(tab$etf_pre, tab$etf_all, use = "complete.obs"), 4), "\n")
cat("  correlation singlename_pre vs etf_pre: ",
    round(cor(tab$sn_pre, tab$etf_pre, use = "complete.obs"), 4), "\n")

cat("\n=== ETF categorical labels: bucket sizes and behaviour ===\n")
etf <- d %>% filter(!is.na(etf_partisan), trimws(etf_partisan) != "") %>%
  group_by(etf_partisan) %>%
  summarise(firms = n_distinct(cmte_id), dyads = n(),
            events = sum(contribute == 1, na.rm = TRUE),
            rate_D = 100*mean(contribute[cand=="D"] == 1, na.rm = TRUE),
            rate_R = 100*mean(contribute[cand=="R"] == 1, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(tilt = round(rate_D / rate_R, 2))
print(as.data.frame(etf), row.names = FALSE)

cat("\n=== which sectors does ETF call DEM, and how do they give? ===\n")
etf_dem <- tab %>% filter(etf_lab == "DEM") %>% select(category, firms, etf_pre, sn_pre, sn_lab, tilt)
print(as.data.frame(etf_dem), row.names = FALSE)

cat("\n=== agreement between the two labelling schemes (sector level) ===\n")
print(table(singlename = tab$sn_lab, etf = tab$etf_lab, useNA = "ifany"))

cat("\nDone.\n")
