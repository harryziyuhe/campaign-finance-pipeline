library(dplyr)
PATH <- "/htaa/hhe/projects/election_buying/"
cand_data <- readRDS(paste0(PATH, "cand_model_data.RDS"))

cat("=== Front 1 supporting stat: how close to binding is the budget constraint? ===\n\n")

# 1) Fraction of actual contributions that hit the per-candidate cap
givers <- cand_data %>% filter(contribute == 1, !is.na(contribute_amount), !is.na(contribute_limit), contribute_limit > 0)
cat("N contribution events:", nrow(givers), "\n")
cat("Fraction of contribution events at/above the candidate cap:",
    mean(givers$contribute_amount >= givers$contribute_limit, na.rm = TRUE), "\n")
cat("Mean contribution amount (conditional on giving):", mean(givers$contribute_amount, na.rm = TRUE), "\n")
cat("Mean candidate cap:", mean(givers$contribute_limit, na.rm = TRUE), "\n")
cat("Mean amount as fraction of cap:", mean(givers$contribute_amount / givers$contribute_limit, na.rm = TRUE), "\n\n")

# 2) Firm-cycle level: how many candidates does a typical firm fund per cycle,
#    and how does total disbursed compare to firm_cash (receipts proxy)?
firm_cycle <- cand_data %>%
  group_by(cmte_id, year) %>%
  summarise(
    n_candidates_considered = n(),
    n_funded = sum(contribute, na.rm = TRUE),
    total_disbursed = sum(contribute_amount, na.rm = TRUE),
    firm_cash = first(firm_cash),
    .groups = "drop"
  ) %>%
  filter(n_funded > 0)

cat("N firm-cycle observations with >=1 contribution:", nrow(firm_cycle), "\n")
cat("Median candidates funded per firm-cycle:", median(firm_cycle$n_funded), "\n")
cat("Mean candidates funded per firm-cycle:", mean(firm_cycle$n_funded), "\n")
cat("Distribution of candidates funded per firm-cycle:\n")
print(quantile(firm_cycle$n_funded, probs = c(0.5, 0.75, 0.9, 0.95, 0.99)))

firm_cycle$payout_ratio <- firm_cycle$total_disbursed / firm_cycle$firm_cash
cat("\nTotal disbursed as a share of firm_cash (per firm-cycle):\n")
print(summary(firm_cycle$payout_ratio))
cat("Fraction of firm-cycles where total disbursed exceeds 50% of firm_cash:",
    mean(firm_cycle$payout_ratio > 0.5, na.rm = TRUE), "\n")
cat("Fraction of firm-cycles where total disbursed exceeds 90% of firm_cash:",
    mean(firm_cycle$payout_ratio > 0.9, na.rm = TRUE), "\n")
