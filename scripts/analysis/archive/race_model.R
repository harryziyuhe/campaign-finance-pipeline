library(arrow)
library(dplyr)
library(ggplot2)
library(stringr)
library(sandwich)
library(lmtest)
library(stargazer)

race_data <- read_parquet("/mnt/shenandoah/campaignfinance/data/house_firm_race.parquet")

# Data Preprocessing
race_data$GICS_Sector <- factor(race_data$GICS_Sector,
                                levels = c("Industrials", "Financials", "Information Technology",
                                           "Real Estate", "Energy", "Health Care", "Utilities",
                                           "Materials", "Communication Services", "Consumer Staples",
                                           "Consumer Discretionary"))

state_dict = data.frame(cbind(toupper(state.name), state.abb))
colnames(state_dict) <- c("hq_state", "hq_state_abb")

race_data <- race_data %>% 
  filter(!is.na(TRBC_Econ_Sector)) %>% 
  mutate(TRBC_Sector = str_split_fixed(TRBC_Econ_Sector, "'", 3)[, 2],
         private = as.numeric(is.na(ric)),
         democrat = sign(rating),
         certainty = uncertainty) %>% 
  left_join(state_dict, by = "hq_state")
race_data <- race_data %>% 
  mutate(same_state = as.numeric(hq_state_abb == state),
         pretrend = as.numeric(year < 2020),
         race = paste0(state, district))

TRBC_sectors = unique(race_data$TRBC_Sector)
race_data$TRBC_Sector <- factor(race_data$TRBC_Sector,
                                level = c("Consumer Cyclicals", TRBC_sectors[!TRBC_sectors %in% c("Consumer Cyclicals")]))

# Extensive Margin Model
extensive <- glm(contribute ~ open + certainty * TRBC_Sector + certainty + factor(year) + private + certainty * same_state, 
              data = race_data)
cluster_se <- vcovCL(extensive, cluster = ~ cmte_id + race)
saveRDS(list(
  "model" = extensive,
  "clusterse" = cluster_se
), "/mnt/shenandoah/campaignfinance/results/race_model_logit.RDS")

# Intensive Margin Model
race_data <- race_data %>% 
  filter(total_amount > 0)

intensive <- lm(log(total_amount+1) ~ open + certainty * TRBC_Sector + private + factor(year) + certainty * same_state, 
             data = race_data)
cluster_se <- vcovCL(intensive, cluster = ~ cmte_id + race)
saveRDS(list(
  "model" = intensive,
  "clusterse" = cluster_se
), "/mnt/shenandoah/campaignfinance/results/race_model_lm.RDS")

extensive <- readRDS("/mnt/shenandoah/campaignfinance/results/race_model_logit.RDS")
intensive <- readRDS("/mnt/shenandoah/campaignfinance/results/race_model_lm.RDS")

se_clustered_extensive <- sqrt(diag(extensive$clusterse))
se_clustered_intensive <- sqrt(diag(intensive$clusterse))
stargazer(extensive$model, intensive$model,
          se = list(se_clustered_extensive, se_clustered_intensive),
          type = "latex",
          header = FALSE,
          align = TRUE,
          digits = 4)

