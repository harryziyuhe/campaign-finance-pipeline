library(readr)
library(tidyverse)
library(scales)
library(patchwork)
library(stargazer)
library(sandwich)
library(lmtest)
library(stats)
library(here)

`%!in%` <- function(x, table) {
  !(x %in% table)
}

state_to_abbr <- function(state_name) {
  # Built-in datasets in R
  full_names <- c(state.name, "District of Columbia")
  abbrs <- c(state.abb, "DC")
  
  # Match input to full names (case-insensitive)
  match_idx <- match(tolower(state_name), tolower(full_names))
  
  if (!is.na(match_idx)) {
    return(abbrs[match_idx])
  } else {
    return(NA)  # Return NA if not found
  }
}

seat_type_labels <- c(
  "R" = "Regular",
  "O" = "Open Seat"
)

cand_type_labels <- c(
  "I" = "Incumbent",
  "C" = "Challenger",
  "O" = "Open Seat"
)

get_first_item <- function(x) {
  list_x <- substr(x, 2, (nchar(x) - 1))
  first_x <- unlist(strsplit(list_x, "',"))[1]
  clean_x <- substr(first_x, 2, nchar(first_x))
  return(unlist(strsplit(clean_x, "'"))[1])
}

color_palettes <- c("steelblue", "seagreen3", "coral")

hii_plots <- function(df, x, y, color,
                      xlab, ylab, clab,
                      title, legend) {
  ggplot(data = df) +
    geom_point(aes(x = {{ x }}, y = {{ y }}, color = {{ color }}), size = 2.7, alpha = 0.85) +
    scale_x_continuous(labels = comma) +
    scale_y_continuous(labels = comma) +
    scale_color_manual(
      values = color_palettes[1:length(clab)],
      labels = clab
    ) +
    labs(
      title = title,
      x = xlab,
      y = ylab,
      color = legend
    ) +
    theme_minimal(base_size = 14, base_family = "serif") +
    theme(
      plot.title = element_text(face = "bold", hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5),
      legend.position = "inside",
      legend.position.inside = c(0.95, 0.05),
      legend.justification = c("right", "bottom"),
      legend.background = element_rect(fill = "white", color = "black", linewidth = 0.3),
      legend.title = element_text(face = "bold"),
      panel.grid.minor = element_blank()
    ) +
    guides(color = guide_legend(override.aes = list(size = 5, alpha = 1)))
}

cpac_hedging <- read_csv("../data/hedging/jan_cutoff/election_hedge.csv")
house_contrib <- read_csv("../data/summary/house_contribution.csv")
house_contrib_party <- read_csv("../data/summary/house_contribution_party.csv")
house_compete <- read_csv("../data/summary/house_compete_contribution_pac.csv")
cpac_firms <- read_csv("../data/cpac/cpac_firms.csv")

cpac_firms <- cpac_firms %>% 
  mutate(Sector_TRBC = sapply(TRBC_Econ_Sector, get_first_item),
         Sector_NAICS = sapply(NAICS_Sector, get_first_item),
         private = as.numeric(is.na(RIC))) |> 
  mutate(Sector_TRBC = factor(Sector_TRBC, levels = c("Basic Materials", "Technology",
                                                      "Real Estate", "Financials", "Utilities",
                                                      "Industrials", "Healthcare", "Consumer Non-Cyclicals",
                                                      "Energy", "Consumer Cyclicals", "Academic & Educational Services",
                                                      "Institution", "Government Activity")),
         Sector_NAICS = factor(Sector_NAICS, levels = c("Manufacturing", "Finance and Insurance",
                                                        "Utilities", "Transportation and Warehousing",
                                                        "Real Estate and Rental and Leasing",
                                                        "Professional, Scientific, and Technical Services",
                                                        "Mining, Quarrying, and Oil and Gas Extraction",
                                                        "Retail Trade", "Accommodation and Food Services",
                                                        "Health Care and Social Assistance",
                                                        "Construction", "Wholesale Trade", "Information",
                                                        "Administrative and Support and Waste Management and Remediation Services",
                                                        "Other Services (except Public Administration)",
                                                        "Agriculture, Forestry, Fishing and Hunting",
                                                        "Arts, Entertainment, and Recreation",
                                                        "Management of Companies and Enterprises",
                                                        "Public Administration")),
         energy = case_when(Sector_TRBC == "Energy" ~ "Energy", TRUE ~ "Not Energy"))


house_contrib$TOP_CAND = factor(house_contrib$TOP_CAND,
                                levels = c("I", "O", "C"))
house_contrib_party$TOP_CAND = factor(house_contrib_party$TOP_CAND,
                                      levels = c("I", "O", "C"))
house_contrib$SEAT_TYPE = factor(house_contrib$SEAT_TYPE,
                                 levels = c("R", "O"))
house_contrib_party$SEAT_TYPE = factor(house_contrib_party$SEAT_TYPE,
                                       levels = c("R", "O"))

cpac_hedging <- cpac_hedging %>% 
  left_join(cpac_firms, by=c("CMTE_ID", "YEAR")) %>% 
  drop_na(Instrument)

p1 <- ggplot(cpac_hedging) +
  geom_point(aes(x = (contribute_sum), y = house_balance_amount,
                 color = as.factor(energy)), alpha = 0.8, size = 2.5) +
  scale_x_continuous(labels = comma) +
  scale_y_continuous(labels = comma) +
  scale_color_manual(
    values = c("Energy" = "coral", "Not Energy" = "steelblue"),
    labels = c("Energy" = "Energy Sector", "Not Energy" = "Other Sectors")
  ) +
  labs(x = "Total Amount Contributed", y = "Partisan Balance by Amount (House)",
       color = "Energy Sector", title = "Partisan Balance") +
  theme_minimal(base_size = 14, base_family = "serif") +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5),
    legend.position = "inside",
    legend.position.inside = c(0.95, 0.8),
    legend.justification = c("right", "bottom"),
    legend.background = element_rect(fill = "white", color = "black", linewidth = 0.3),
    legend.title = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  ) +
  guides(color = guide_legend(override.aes = list(size = 5, alpha = 1)))

p2 <- ggplot(cpac_hedging) +
  geom_point(aes(x = (contribute_sum), y = house_hedge_amount,
                 color = as.factor(energy)), alpha = 0.8, size = 2.5) +
  scale_x_continuous(labels = comma) +
  scale_y_continuous(labels = comma) +
  scale_color_manual(
    values = c("Energy" = "coral", "Not Energy" = "steelblue"),
    labels = c("Energy" = "Energy Sector", "Not Energy" = "Other Sectors")
  ) +
  labs(x = "Total Amount Contributed", y = "Hedging by Amount (House)",
       color = "Energy Sector", title = "Hedging") +
  theme_minimal(base_size = 14, base_family = "serif") +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5),
    legend.position = "inside",
    legend.position.inside = c(0.95, 0.3),
    legend.justification = c("right", "bottom"),
    legend.background = element_rect(fill = "white", color = "black", linewidth = 0.3),
    legend.title = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  ) +
  guides(color = guide_legend(override.aes = list(size = 5, alpha = 1)))

ggsave("../figure/Balance and Hedge by Contribute Amount (Energy).png", p1+p2, width = 12, height = 6)
ggsave("../figure/Partisan Balance by Contribute Amount (Energy).png", p1, width = 6, height = 6)
ggsave("../figure/Hedge by Contribute Amount (Energy).png", p2, width = 6, height = 6)

filtered_cpac <- cpac_hedging %>%
  group_by(Sector_TRBC) %>%
  filter(n() > 20) %>%
  ungroup() |> 
  drop_na(Sector_TRBC)

p_balance_sector <- ggplot(filtered_cpac) +
  geom_point(aes(x = contribute_sum, y = house_balance_amount), 
             color = "steelblue", alpha = 0.8, size = 2.5) +
  scale_x_continuous(labels = comma) +
  scale_y_continuous(labels = comma) +
  labs(
    x = "Total Amount Contributed",
    y = "Hedging by Amount (House)",
    color = "Energy Sector",
    title = "Hedging by Sector"
  ) +
  facet_wrap(~ Sector_TRBC, scales = "free") +  # <-- one plot per sector!
  theme_minimal(base_size = 14, base_family = "serif") +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5),
    legend.position = "inside",
    legend.position.inside = c(0.95, 0.2),
    legend.justification = c("right", "bottom"),
    legend.background = element_rect(fill = "white", color = "black", linewidth = 0.3),
    legend.title = element_text(face = "bold"),
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold", size = 12) # facet labels
  ) +
  guides(color = guide_legend(override.aes = list(size = 5, alpha = 1)))

p_hedge_sector <- ggplot(filtered_cpac) +
  geom_point(aes(x = contribute_sum, y = house_hedge_amount), 
             color = "steelblue", alpha = 0.8, size = 2.5) +
  scale_x_continuous(labels = comma) +
  scale_y_continuous(labels = comma) +
  labs(
    x = "Total Amount Contributed",
    y = "Hedging by Amount (House)",
    color = "Energy Sector",
    title = "Hedging by Sector"
  ) +
  facet_wrap(~ Sector_TRBC, scales = "free") +  # <-- one plot per sector!
  theme_minimal(base_size = 14, base_family = "serif") +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5),
    legend.position = "inside",
    legend.position.inside = c(0.95, 0.2),
    legend.justification = c("right", "bottom"),
    legend.background = element_rect(fill = "white", color = "black", linewidth = 0.3),
    legend.title = element_text(face = "bold"),
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold", size = 12) # facet labels
  ) +
  guides(color = guide_legend(override.aes = list(size = 5, alpha = 1)))

ggsave("../figure/Balance by Contribute Amount (Sector).png", p_balance_sector, width = 12, height = 12)
ggsave("../figure/Hedge by Contribute Amount (Sector).png", p_hedge_sector, width = 12, height = 12)

p3 <- ggplot(cpac_hedging) +
  geom_point(aes(x = n_states, y = house_balance_amount,
                 color = as.factor(energy)), alpha = 0.8, size = 2) +
  scale_x_continuous(labels = comma) +
  scale_y_continuous(labels = comma) +
  scale_color_manual(
    values = c("Energy" = "coral", "Not Energy" = "steelblue"),
    labels = c("Energy" = "Energy Sector", "Not Energy" = "Other Sectors")
  ) +
  labs(x = "Number of States Donated to", y = "Partisan Balance by Amount (House)",
       color = "Energy Sector", title = "Partisan Balance") +
  theme_minimal(base_size = 14, base_family = "serif") +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5),
    legend.position = "inside",
    legend.position.inside = c(0.95, 0.8),
    legend.justification = c("right", "bottom"),
    legend.background = element_rect(fill = "white", color = "black", linewidth = 0.3),
    legend.title = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  ) +
  guides(color = guide_legend(override.aes = list(size = 5, alpha = 1)))

p4 <- ggplot(cpac_hedging) +
  geom_point(aes(x = n_states, y = house_hedge_amount,
                 color = as.factor(energy)), alpha = 0.8, size = 2) +
  scale_x_continuous(labels = comma) +
  scale_y_continuous(labels = comma) +
  scale_color_manual(
    values = c("Energy" = "coral", "Not Energy" = "steelblue"),
    labels = c("Energy" = "Energy Sector", "Not Energy" = "Other Sectors")
  ) +
  labs(x = "Number of States Donated to", y = "Hedging by Amount (House)",
       color = "Energy Sector", title = "Hedging") +
  theme_minimal(base_size = 14, base_family = "serif") +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5),
    legend.position = "inside",
    legend.position.inside = c(0.95, 0.3),
    legend.justification = c("right", "bottom"),
    legend.background = element_rect(fill = "white", color = "black", linewidth = 0.3),
    legend.title = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  ) +
  guides(color = guide_legend(override.aes = list(size = 5, alpha = 1)))

ggsave("../figure/Balance and Hedge by Number of States (Energy).png", p3+p4, width = 12, height = 6)

#Amount
p5 <- hii_plots(house_contrib %>% drop_na(SEAT_TYPE), amount_sum, amount_hii, SEAT_TYPE,
                "Total Contribution Amount", "Contribution to Candidate HII (Amount)",
                seat_type_labels, "Candidate Concentration", "Seat Type")

p6 <- hii_plots(house_contrib_party %>% drop_na(SEAT_TYPE), amount_sum, amount_hii, SEAT_TYPE,
                "Total Contribution Amount", "Contribution to Party HII (Amount)",
                seat_type_labels, "Party Concentration", "Seat Type")
ggsave("../figure/HII Amount Seat Type.png", p5+p6, width=12, height=6)

p7 <- hii_plots(house_contrib, amount_sum, amount_hii, TOP_CAND,
                "Total Contribution Amount", "Contribution to Candidate HII (Amount)",
                cand_type_labels, "Candidate Concentration", "Top Contributed Candidate")

p8 <- hii_plots(house_contrib_party, amount_sum, amount_hii, TOP_CAND,
                "Total Contribution Amount", "Contribution to Party HII (Amount)",
                cand_type_labels, "Party Concentration", "Top Contributed Candidate")
ggsave("../figure/HII Amount Top Cand.png", p7+p8, width=12, height=6)

#Count
hii_plots(house_contrib, count_sum, amount_hii, SEAT_TYPE,
          "Number of Contributions", "Contribution to Candidate HII (Amount)",
          seat_type_labels, "Seat Type")
ggsave("/Users/ziyuhe/Library/CloudStorage/OneDrive-UCSanDiego/Projects/Campaign Finance/figure/HII Count Seat Type Cand.png")

hii_plots(house_contrib, count_sum, amount_hii, TOP_CAND,
          "Number of Contributions", "Contribution to Candidate HII (Amount)",
          cand_type_labels, "Top Contributed Candidate")
ggsave("/Users/ziyuhe/Library/CloudStorage/OneDrive-UCSanDiego/Projects/Campaign Finance/figure/HII Count Top Cand Cand.png")

hii_plots(house_contrib_party, count_sum, amount_hii, SEAT_TYPE,
          "Number of Contributions", "Contribution to Party HII (Amount)",
          seat_type_labels, "Seat Type")
ggsave("/Users/ziyuhe/Library/CloudStorage/OneDrive-UCSanDiego/Projects/Campaign Finance/figure/HII Count Seat Type Party.png")

hii_plots(house_contrib_party, count_sum, amount_hii, TOP_CAND,
          "Number of Contributions", "Contribution to Party HII (Amount)",
          cand_type_labels, "Top Contributed Candidate")
ggsave("/Users/ziyuhe/Library/CloudStorage/OneDrive-UCSanDiego/Projects/Campaign Finance/figure/HII Count Top Cand Party.png")








lm_amount_sum1 <- lm(house_hedge_amount ~ log10(contribute_sum) + private + Sector_TRBC + factor(YEAR), data = cpac_hedging)
lm_amount_sum1_se <- sqrt(diag(vcovCL(lm_amount_sum1, cluster = ~CMTE_ID)))
lm_amount_sum2 <- lm(house_hedge_amount ~ log10(contribute_sum) + private + Sector_NAICS + factor(YEAR), data = cpac_hedging)
lm_amount_sum2_se <- sqrt(diag(vcovCL(lm_amount_sum2, cluster = ~CMTE_ID)))
lm_amount_nstates1 <- lm(house_hedge_amount ~ n_states + private + Sector_TRBC + factor(YEAR), data = cpac_hedging)
lm_amount_nstates1_se <- sqrt(diag(vcovCL(lm_amount_nstates1, cluster = ~CMTE_ID)))
lm_amount_nstates2 <- lm(house_hedge_amount ~ n_states + private + Sector_NAICS + factor(YEAR), data = cpac_hedging)
lm_amount_nstates2_se <- sqrt(diag(vcovCL(lm_amount_nstates2, cluster = ~CMTE_ID)))
lm_amount_ncands1 <- lm(house_hedge_amount ~ n_cands + private + Sector_TRBC + factor(YEAR), data = cpac_hedging)
lm_amount_ncands1_se <- sqrt(diag(vcovCL(lm_amount_ncands1, cluster = ~CMTE_ID)))
lm_amount_ncands2 <- lm(house_hedge_amount ~ n_cands + private + Sector_NAICS + factor(YEAR), data = cpac_hedging)
lm_amount_ncands2_se <- sqrt(diag(vcovCL(lm_amount_ncands2, cluster = ~CMTE_ID)))
lm_amount_full1 <- lm(house_hedge_amount ~ log10(contribute_sum) + n_states + log(n_cands) + private + Sector_TRBC + factor(YEAR), data = cpac_hedging)
lm_amount_full1_se <- sqrt(diag(vcovCL(lm_amount_full1, cluster = ~CMTE_ID)))
lm_amount_full2 <- lm(house_hedge_amount ~ log10(contribute_sum) + n_states + n_cands + private + Sector_NAICS + factor(YEAR), data = cpac_hedging)
lm_amount_full2_se <- sqrt(diag(vcovCL(lm_amount_full2, cluster = ~CMTE_ID)))

stargazer(lm_amount_sum1, lm_amount_nstates1, lm_amount_ncands1, lm_amount_full1,
          se = list(lm_amount_sum1_se, lm_amount_nstates1_se,
                    lm_amount_ncands1_se, lm_amount_full1_se))

lm_count_sum1 <- lm(house_hedge_count ~ log10(contribute_sum) + private + Sector_TRBC + factor(YEAR), data = cpac_hedging)
lm_count_sum1_se <- sqrt(diag(vcovCL(lm_count_sum1, cluster = ~CMTE_ID)))
lm_count_sum2 <- lm(house_hedge_count ~ log10(contribute_sum) + private + Sector_NAICS + factor(YEAR), data = cpac_hedging)
lm_count_nstates1 <- lm(house_hedge_count ~ n_states + private + Sector_TRBC + factor(YEAR), data = cpac_hedging)
lm_count_nstates1_se <- sqrt(diag(vcovCL(lm_count_nstates1, cluster = ~CMTE_ID)))
lm_count_nstates2 <- lm(house_hedge_count ~ n_states + private + Sector_NAICS + factor(YEAR), data = cpac_hedging)
lm_count_ncands1 <- lm(house_hedge_count ~ n_cands + private + Sector_TRBC + factor(YEAR), data = cpac_hedging)
lm_count_ncands1_se <- sqrt(diag(vcovCL(lm_count_ncands1, cluster = ~CMTE_ID)))
lm_count_ncands2 <- lm(house_hedge_count ~ n_cands + private + Sector_NAICS + factor(YEAR), data = cpac_hedging)
lm_count_full1 <- lm(house_hedge_count ~ log10(contribute_sum) + n_states + n_cands + private + Sector_TRBC + factor(YEAR), data = cpac_hedging)
lm_count_full1_se <- sqrt(diag(vcovCL(lm_count_full1, cluster = ~CMTE_ID)))
lm_count_full2 <- lm(house_hedge_count ~ log10(contribute_sum) + n_states + n_cands + private + Sector_NAICS + factor(YEAR), data = cpac_hedging)

stargazer(lm_count_sum1, lm_count_nstates1, lm_count_ncands1, lm_count_full1,
          se = list(lm_count_sum1_se, lm_count_nstates1_se,
                    lm_count_ncands1_se, lm_count_full1_se))



house_contrib$amount_compete <- 1 - house_contrib$amount_hii
house_contrib$count_compete <- 1 - house_contrib$count_hii
house_contrib_party$amount_compete <- 1 - house_contrib_party$amount_hii
house_contrib_party$count_compete <- 1 - house_contrib_party$count_hii
house_contrib$race_id <- paste(house_contrib$CAND_OFFICE_ST, house_contrib$CAND_OFFICE_DISTRICT, sep="-")
house_contrib_party$race_id <- paste(house_contrib_party$CAND_OFFICE_ST, house_contrib_party$CAND_OFFICE_DISTRICT, sep="-")
house_contrib$amount_sumk <- house_contrib$amount_sum/1000
house_contrib_party$amount_sumk <- house_contrib_party$amount_sum/1000

lm_hii_cand1 <- lm(amount_hii ~ amount_sumk * SEAT_TYPE + CAND_OFFICE_ST + factor(YEAR), data = house_contrib)
lm_hii_cand1_se <- sqrt(diag(vcovCL(lm_hii_cand1, cluster = ~race_id)))
lm_hii_cand2 <- lm(amount_hii ~ amount_sumk * TOP_CAND + CAND_OFFICE_ST + factor(YEAR), data = house_contrib)
lm_hii_cand2_se <- sqrt(diag(vcovCL(lm_hii_cand2, cluster = ~race_id)))
lm_hii_party1 <- lm(amount_hii ~ amount_sumk * SEAT_TYPE + CAND_OFFICE_ST + factor(YEAR), data = house_contrib_party)
lm_hii_party1_se <- sqrt(diag(vcovCL(lm_hii_party1, cluster = ~race_id)))
lm_hii_party2 <- lm(amount_hii ~ amount_sumk * TOP_CAND + CAND_OFFICE_ST + factor(YEAR), data = house_contrib_party)
lm_hii_party2_se <- sqrt(diag(vcovCL(lm_hii_party2, cluster = ~race_id)))

stargazer(lm_hii_cand1, lm_hii_cand2, lm_hii_party1, lm_hii_party2,
          se = list(lm_hii_cand1_se, lm_hii_cand2_se, 
                    lm_hii_party1_se, lm_hii_party2_se))

contribute_seqI <- seq(
  from = min(house_contrib_party[house_contrib_party$TOP_CAND == "I", "amount_sumk"], na.rm = TRUE),
  to = max(house_contrib_party[house_contrib_party$TOP_CAND == "I", "amount_sumk"], na.rm = TRUE),
  length.out = 100
)
contribute_seqO <- seq(
  from = min(house_contrib_party[house_contrib_party$TOP_CAND == "O", "amount_sumk"], na.rm = TRUE),
  to = max(house_contrib_party[house_contrib_party$TOP_CAND == "O", "amount_sumk"], na.rm = TRUE),
  length.out = 100
)
contribute_seqC <- seq(
  from = min(house_contrib_party[house_contrib_party$TOP_CAND == "C", "amount_sumk"], na.rm = TRUE),
  to = max(house_contrib_party[house_contrib_party$TOP_CAND == "C", "amount_sumk"], na.rm = TRUE),
  length.out = 100
)

predict_dataI <- expand.grid(
  amount_sumk = contribute_seqI,
  TOP_CAND = "I",
  CAND_OFFICE_ST = "CA",
  YEAR = 2024
)
predict_dataO <- expand.grid(
  amount_sumk = contribute_seqO,
  TOP_CAND = "O",
  CAND_OFFICE_ST = "CA",
  YEAR = 2024
)
predict_dataC <- expand.grid(
  amount_sumk = contribute_seqC,
  TOP_CAND = "C",
  CAND_OFFICE_ST = "CA",
  YEAR = 2024
)

predict_data <- predict_dataI %>% 
  rbind(predict_dataO) %>% 
  rbind(predict_dataC)

pred <- predict(
  lm_hii_party2,
  newdata = predict_data,
  se.fit = TRUE
)
predict_data$fit <- pred$fit
predict_data$se.fit <- pred$se.fit
predict_data$lower <- pred$fit - 1.96 * pred$se.fit
predict_data$upper <- pred$fit + 1.96 * pred$se.fit
predict_data$amount <- predict_data$amount_sumk * 1000

race_margin <- ggplot(predict_data, aes(x = amount, y = fit, color = as.factor(TOP_CAND))) +
  geom_line(size = 1.2) +
  geom_ribbon(
    aes(ymin = lower, ymax = upper, fill = as.factor(TOP_CAND)),
    alpha = 0.2,
    color = NA
  ) +
  scale_x_continuous(labels = comma) +
  scale_y_continuous(labels = comma) +
  scale_color_manual(
    values = c("C" = "coral", "I" = "steelblue", "O" = "seagreen3"),
    labels = cand_type_labels
  ) +
  scale_fill_manual(
    values = c("C" = "coral", "I" = "steelblue", "O" = "seagreen3"),
    labels = cand_type_labels
  ) +
  labs(
    x = "Total Contribute Amount",
    y = "Predicted Concentration of Campaign Contributions",
    color = "Top Contributed Candidate",
    fill = "Top Contributed Candidate",
  ) +
  theme_minimal(base_size = 14, base_family = "serif") +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5),
    legend.position = "inside",
    legend.position.inside = c(0.95, 0.1),
    legend.justification = c("right", "bottom"),
    legend.background = element_rect(fill = "white", color = "black", linewidth = 0.3),
    legend.title = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  ) +
  guides(color = guide_legend(override.aes = list(size = 5, alpha = 1)))
ggsave("../figure/interact_race.png", race_margin, width = 10, height = 6)

lm_hii_cand3 <- lm(count_hii ~ count_sum * SEAT_TYPE + CAND_OFFICE_ST + factor(YEAR), data = house_contrib)
lm_hii_cand3_se <- sqrt(diag(vcovCL(lm_hii_cand3, cluster = ~race_id)))
lm_hii_cand4 <- lm(count_hii ~ count_sum * TOP_CAND + CAND_OFFICE_ST + factor(YEAR), data = house_contrib)
lm_hii_cand4_se <- sqrt(diag(vcovCL(lm_hii_cand4, cluster = ~race_id)))
lm_hii_party3 <- lm(count_hii ~ count_sum * SEAT_TYPE + factor(YEAR), data = house_contrib_party)
lm_hii_party3_se <- sqrt(diag(vcovCL(lm_hii_party3, cluster = ~race_id)))
lm_hii_party4 <- lm(count_hii ~ count_sum * TOP_CAND + factor(YEAR), data = house_contrib_party)
lm_hii_party4_se <- sqrt(diag(vcovCL(lm_hii_party4, cluster = ~race_id)))


cpac_challenger <- house_compete |> 
  filter(C == 1) |> 
  select(c(CMTE_ID, YEAR)) |> 
  distinct() |> 
  mutate(C = 1) |> 
  right_join(cpac_hedging, by = c("CMTE_ID", "YEAR")) |> 
  drop_na(house_hedge_amount) |> 
  mutate(C = replace_na(C, 0))

lm_challenger1 <- glm(C ~ log(contribute_sum) + house_hedge_amount + private + Sector_TRBC + factor(YEAR), data = cpac_challenger, family="binomial")
lm_challenger1_se <- sqrt(diag(vcovCL(lm_challenger1, cluster = ~CMTE_ID)))
lm_challenger2 <- glm(C ~ n_states + house_hedge_amount + private + Sector_TRBC + factor(YEAR), data = cpac_challenger, family="binomial")
lm_challenger2_se <- sqrt(diag(vcovCL(lm_challenger2, cluster = ~CMTE_ID)))
lm_challenger3 <- glm(C ~ log(contribute_sum) + n_states + house_hedge_amount + private + Sector_TRBC + factor(YEAR), data = cpac_challenger, family="binomial")
lm_challenger3_se <- sqrt(diag(vcovCL(lm_challenger3, cluster = ~CMTE_ID)))
stargazer(lm_challenger1, lm_challenger2, lm_challenger3,
          se = list(lm_challenger1_se, lm_challenger2_se, lm_challenger3_se))

contribute_seq <- seq(
  from = min(cpac_challenger$contribute_sum, na.rm = TRUE),
  to = max(cpac_challenger$contribute_sum, na.rm = TRUE),
  length.out = 100
)
mean_n_states <- median(cpac_challenger$n_states, na.rm = TRUE)
baseline_sector <- levels(cpac_challenger$Sector_TRBC)[6]
predict_data <- expand.grid(
  contribute_sum = contribute_seq,
  house_hedge_amount = c(0, 1),
  n_states = mean_n_states,
  Sector_TRBC = baseline_sector,
  YEAR = 2024,
  private = 0
)
predict_data$log_contribute_sum <- log(predict_data$contribute_sum)
pred <- predict(
  lm_challenger3,
  newdata = predict_data,
  type = "link",
  se.fit = TRUE
)
predict_data$fit <- plogis(pred$fit)
predict_data$se.fit <- pred$se.fit
predict_data$lower <- plogis(pred$fit - 1.96 * pred$se.fit)
predict_data$upper <- plogis(pred$fit + 1.96 * pred$se.fit)

p_margin1 <- ggplot(predict_data, aes(x = contribute_sum, y = fit, color = as.factor(house_hedge_amount))) +
  geom_line(size = 1.2) +
  geom_ribbon(
    aes(ymin = lower, ymax = upper, fill = as.factor(house_hedge_amount)),
    alpha = 0.2,
    color = NA
  ) +
  scale_x_continuous(labels = comma) +
  scale_y_continuous(labels = comma) +
  scale_color_manual(
    values = c("0" = "coral", "1" = "steelblue"),
  ) +
  scale_fill_manual(
    values = c("0" = "coral", "1" = "steelblue"),
  ) +
  labs(
    x = "Contribute Sum",
    y = "Predicted Probability of Supporting Challengers",
    color = "Hedging Score",
    fill = "Hedging Score",
  ) +
  theme_minimal(base_size = 14, base_family = "serif") +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5),
    legend.position = "inside",
    legend.position.inside = c(0.95, 0.1),
    legend.justification = c("right", "bottom"),
    legend.background = element_rect(fill = "white", color = "black", linewidth = 0.3),
    legend.title = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  ) +
  guides(color = guide_legend(override.aes = list(size = 5, alpha = 1)))
ggsave("../figure/margin_challenger.png", p_margin1, width = 10, height = 6)

cpac_ni <- house_compete |> 
  filter((C == 1) | (SEAT_TYPE == "O")) |> 
  select(c(CMTE_ID, YEAR)) |> 
  distinct() |> 
  mutate(NI = 1) |> 
  right_join(cpac_hedging, by = c("CMTE_ID", "YEAR")) |> 
  drop_na(house_hedge_amount) |> 
  mutate(NI = replace_na(NI, 0))

lm_ni1 <- glm(NI ~ log(contribute_sum) + house_hedge_amount + private + Sector_TRBC + factor(YEAR), data = cpac_ni, family="binomial")
lm_ni1_se <- sqrt(diag(vcovCL(lm_ni1, cluster = ~CMTE_ID)))
lm_ni2 <- glm(NI ~ n_states + house_hedge_amount + private + Sector_TRBC + factor(YEAR), data = cpac_ni, family="binomial")
lm_ni2_se <- sqrt(diag(vcovCL(lm_ni2, cluster = ~CMTE_ID)))
lm_ni3 <- glm(NI ~ log(contribute_sum) + n_states + house_hedge_amount + private + Sector_TRBC + factor(YEAR), data = cpac_ni, family="binomial")
lm_ni3_se <- sqrt(diag(vcovCL(lm_ni3, cluster = ~CMTE_ID)))

stargazer(lm_ni1, lm_ni2, lm_ni3,
          se = list(lm_ni1_se, lm_ni2_se, lm_ni3_se))

contribute_seq <- seq(
  from = min(cpac_ni$contribute_sum, na.rm = TRUE),
  to = max(cpac_ni$contribute_sum, na.rm = TRUE),
  length.out = 100
)
mean_n_states <- median(cpac_ni$n_states, na.rm = TRUE)
baseline_sector <- levels(cpac_ni$Sector_TRBC)[6]
predict_data <- expand.grid(
  contribute_sum = contribute_seq,
  house_hedge_amount = c(0, 1),
  n_states = mean_n_states,
  Sector_TRBC = baseline_sector,
  YEAR = 2024,
  private = 0
)
predict_data$log_contribute_sum <- log(predict_data$contribute_sum)
pred <- predict(
  lm_ni3,
  newdata = predict_data,
  type = "link",
  se.fit = TRUE
)
predict_data$fit <- plogis(pred$fit)
predict_data$se.fit <- pred$se.fit
predict_data$lower <- plogis(pred$fit - 1.96 * pred$se.fit)
predict_data$upper <- plogis(pred$fit + 1.96 * pred$se.fit)

p_margin2 <- ggplot(predict_data, aes(x = contribute_sum, y = fit, color = as.factor(house_hedge_amount))) +
  geom_line(size = 1.2) +
  geom_ribbon(
    aes(ymin = lower, ymax = upper, fill = as.factor(house_hedge_amount)),
    alpha = 0.2,
    color = NA
  ) +
  scale_x_continuous(labels = comma) +
  scale_y_continuous(labels = comma) +
  scale_color_manual(
    values = c("0" = "coral", "1" = "steelblue"),
  ) +
  scale_fill_manual(
    values = c("0" = "coral", "1" = "steelblue"),
  ) +
  labs(
    x = "Contribute Sum",
    y = "Predicted Probability of Supporting Non-Incumbents",
    color = "Hedging Score",
    fill = "Hedging Score",
  ) +
  theme_minimal(base_size = 14, base_family = "serif") +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5),
    legend.position = "inside",
    legend.position.inside = c(0.95, 0.1),
    legend.justification = c("right", "bottom"),
    legend.background = element_rect(fill = "white", color = "black", linewidth = 0.3),
    legend.title = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  ) +
  guides(color = guide_legend(override.aes = list(size = 5, alpha = 1)))
ggsave("../figure/margin_non_incumbent.png", p_margin2, width = 10, height = 6)


mod1 <- lm(house_hedge_amount ~ log(contribute_sum) + private + Sector_TRBC + factor(YEAR), data = cpac_hedging)
se1 <- sqrt(diag(vcovCL(mod1, cluster = ~CMTE_ID)))
mod2 <- lm(house_hedge_amount ~ n_states + private + Sector_TRBC + factor(YEAR), data = cpac_hedging)
se2 <- sqrt(diag(vcovCL(mod2, cluster = ~CMTE_ID)))
mod3 <- lm(house_hedge_amount ~ n_cands + private + Sector_TRBC + factor(YEAR), data = cpac_hedging)
se3 <- sqrt(diag(vcovCL(mod3, cluster = ~CMTE_ID)))

make_robust_tidy <- function(model, robust_se, model_name) {
  broom::tidy(model, conf.int = FALSE) %>% 
    select(term, estimate) %>% 
    mutate(
      robust_se  = robust_se,
      conf.low   = estimate - qnorm(0.975) * robust_se,
      conf.high  = estimate + qnorm(0.975) * robust_se,
      model      = model_name
    )
}

tidy1 <- make_robust_tidy(mod1, se1, "Model 1")
tidy2 <- make_robust_tidy(mod2, se2, "Model 2")
tidy3 <- make_robust_tidy(mod3, se3, "Model 3")
coef_all <- bind_rows(tidy1, tidy2, tidy3)

keep_terms <- c("log(contribute_sum)", "n_states", "n_cands", "private", "Sector_TRBCEnergy")
coef_plot <- coef_all %>%
  filter(term %in% keep_terms) %>%
  mutate(
    term = recode_factor(
      term,
      "log(contribute_sum)" = "Contribution Sum (Log)",
      "n_states" = "Number of States",
      "n_cands" = "Number of Candidates",
      "private" = "Private Firm",
      "Sector_TRBCEnergy" = "Energy Firm"
    )
  ) %>%
  mutate(term = factor(term))

p_coef = ggplot(coef_plot, aes(x = estimate, y = term, color = model)) +
  geom_errorbarh(aes(xmin = conf.low, xmax = conf.high),
                 height = 0,
                 size = 1.2,
                 position = position_dodge(width = 0.6)) +
  geom_point(size = 3,
             position = position_dodge(width = 0.6)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
  scale_x_continuous(expand = expansion(mult = c(0.05,0.05))) +
  scale_y_discrete(limits = rev(levels(coef_plot$term))) +
  # here’s where we set the three colors and rename the legend entries
  scale_color_manual(
    name   = "Campaign Contribution \n Footprint",
    values = c(
      "Model 1" = "steelblue",
      "Model 2" = "coral",
      "Model 3" = "seagreen3"
    ),
    labels = c(
      "Model 1" = "Contribution Sum",
      "Model 2" = "Number of States",
      "Model 3" = "Number of Candidates"
    )
  ) +
  theme_minimal(base_size = 14, base_family = "serif") +
  theme(
    panel.grid.minor   = element_blank(),
    panel.grid.major.y = element_blank(),
    axis.ticks.y       = element_blank(),
    plot.title         = element_text(face = "bold", hjust = 0.5),
    legend.position = "inside",
    legend.position.inside = c(1, 0),
    legend.justification = c(1, 0),
    legend.background  = element_rect(fill = alpha("white", 0.7), color = NA)
  ) +
  labs(
    x     = "Regression Coefficients",
    y     = NULL
  )
ggsave("../figure/coef_plot.png", p_coef, width = 8, height = 6)
