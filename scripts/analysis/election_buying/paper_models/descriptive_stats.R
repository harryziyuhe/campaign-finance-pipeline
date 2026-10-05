# Descriptive statistics table for the paper (Table 1 companion).
# Produces model/descriptives/descriptive_stats.txt (raw numbers) and a LaTeX
# fragment at paper/regressions/descriptives.tex.
#
# Follows the project convention: read cand_model_data.RDS from PATH, write a
# plain-text dump alongside any generated table so the numbers are auditable.

suppressPackageStartupMessages({
  library(dplyr)
})

PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/descriptives/")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

cat("Reading data...\n")
d <- readRDS(paste0(PATH, "cand_model_data.RDS"))
cat("Rows:", nrow(d), " Cols:", ncol(d), "\n")

sink(paste0(OUT_DIR, "descriptive_stats.txt"))

cat("=== PANEL DIMENSIONS ===\n")
cat("Firm-candidate-cycle dyads:      ", format(nrow(d), big.mark = ","), "\n")
cat("Distinct firms (cmte_id):        ", format(n_distinct(d$cmte_id), big.mark = ","), "\n")
cat("Distinct candidates:             ", format(n_distinct(d$candidate_id), big.mark = ","), "\n")
cat("Election cycles:                 ", n_distinct(d$year), "\n")
cat("Cycle range:                     ", min(d$year), "-", max(d$year), "\n")
cat("Distinct states:                 ", n_distinct(d$state), "\n")

cat("\n=== OUTCOME ===\n")
cat("Contribution events:             ", format(sum(d$contribute == 1, na.rm = TRUE), big.mark = ","), "\n")
cat("Contribution rate (%):           ", round(100 * mean(d$contribute == 1, na.rm = TRUE), 3), "\n")
pos <- d$contribute_amount[d$contribute == 1 & !is.na(d$contribute_amount)]
cat("Mean amount | contributed ($):   ", round(mean(pos), 1), "\n")
cat("Median amount | contributed ($): ", round(median(pos), 1), "\n")
cat("SD amount | contributed ($):     ", round(sd(pos), 1), "\n")
cat("Max amount ($):                  ", round(max(pos), 1), "\n")

cat("\n=== FAVORABILITY (Chance of Winning) ===\n")
cat("Mean:   ", round(mean(d$favorability, na.rm = TRUE), 3), "\n")
cat("SD:     ", round(sd(d$favorability, na.rm = TRUE), 3), "\n")
cat("Min/Max:", min(d$favorability, na.rm = TRUE), "/", max(d$favorability, na.rm = TRUE), "\n")
cat("Distribution:\n")
print(round(100 * prop.table(table(d$favorability)), 2))

cat("\n=== CANDIDATE TYPE ===\n")
print(d %>% count(incumbency) %>% mutate(pct = round(100 * n / sum(n), 2)))
cat("\nContribution rate by candidate type (%):\n")
print(d %>% group_by(incumbency) %>%
        summarise(dyads = n(), events = sum(contribute == 1, na.rm = TRUE),
                  rate = round(100 * mean(contribute == 1, na.rm = TRUE), 3), .groups = "drop"))

cat("\n=== CANDIDATE PARTY ===\n")
print(d %>% count(party) %>% mutate(pct = round(100 * n / sum(n), 2)))

cat("\n=== SECTORAL PARTISAN ALIGNMENT (categorical) ===\n")
print(d %>% group_by(singlename_partisan_pre) %>%
        summarise(dyads = n(),
                  firms = n_distinct(cmte_id),
                  events = sum(contribute == 1, na.rm = TRUE),
                  rate = round(100 * mean(contribute == 1, na.rm = TRUE), 3), .groups = "drop"))

cat("\n=== SECTORAL PARTISAN ALIGNMENT (continuous score) ===\n")
cat("Mean:   ", round(mean(d$singlename_score_pre, na.rm = TRUE), 4), "\n")
cat("SD:     ", round(sd(d$singlename_score_pre, na.rm = TRUE), 4), "\n")
cat("Min/Max:", round(min(d$singlename_score_pre, na.rm = TRUE), 4), "/",
    round(max(d$singlename_score_pre, na.rm = TRUE), 4), "\n")

cat("\n=== SECTOR COMPOSITION (category) ===\n")
print(d %>% group_by(category) %>%
        summarise(firms = n_distinct(cmte_id), dyads = n(),
                  score = round(mean(singlename_score_pre, na.rm = TRUE), 3),
                  partisan = first(singlename_partisan_pre),
                  rate = round(100 * mean(contribute == 1, na.rm = TRUE), 3), .groups = "drop") %>%
        arrange(score) %>% as.data.frame())

cat("\n=== FIRM-LEVEL CONTROLS ===\n")
cat("firm_cash mean ($):  ", round(mean(d$firm_cash, na.rm = TRUE), 0), "\n")
cat("firm_cash median ($):", round(median(d$firm_cash, na.rm = TRUE), 0), "\n")
cat("private (%):         ", round(100 * mean(d$private == 1, na.rm = TRUE), 2), "\n")
cat("foreign (%):         ", round(100 * mean(d$foreign == 1, na.rm = TRUE), 2), "\n")
cat("same_state (%):      ", round(100 * mean(d$same_state == 1, na.rm = TRUE), 2), "\n")
cat("special (%):         ", round(100 * mean(d$special == 1, na.rm = TRUE), 2), "\n")

cat("\n=== PORTFOLIO / BUDGET (for the separability argument) ===\n")
fc <- d %>% filter(contribute == 1) %>% group_by(cmte_id, year) %>%
  summarise(n_cands = n(), total = sum(contribute_amount, na.rm = TRUE), .groups = "drop")
cat("Median candidates funded per firm-cycle:", median(fc$n_cands), "\n")
cat("Mean candidates funded per firm-cycle:  ", round(mean(fc$n_cands), 1), "\n")

sink()

cat("Wrote", paste0(OUT_DIR, "descriptive_stats.txt"), "\n")
