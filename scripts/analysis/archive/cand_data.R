library(arrow)
library(dplyr)
library(ggplot2)
library(stringr)
library(sandwich)
library(lmtest)
library(stargazer)
library(fixest)
library(tidyr)
library(splines)
DATA_PATH = "S:/campaignfinance/data/"

########### DATA CREATION ########### 
########### Run Only Once ########### 

cand_data <- read_parquet(paste0(DATA_PATH, "house_firm_cand.parquet"))
rcp_data <- read.csv(paste0(DATA_PATH, "other/RCP.csv"))
consumer <- read.csv(paste0(DATA_PATH, "other/TRBC.csv"))
sector_category <- read.csv(paste0(DATA_PATH, "other/sector_hedge.csv"))

cand_data$GICS_Sector <- factor(cand_data$GICS_Sector,
                                levels = c("Industrials", "Financials", "Information Technology",
                                           "Real Estate", "Energy", "Health Care", "Utilities",
                                           "Materials", "Communication Services", "Consumer Staples",
                                           "Consumer Discretionary"))

state_dict = data.frame(cbind(toupper(state.name), state.abb))
colnames(state_dict) <- c("hq_state", "hq_state_abb")

cand_data <- cand_data %>% 
  filter(!is.na(TRBC_Econ_Sector)) %>% 
  filter((party == "DEMOCRAT") | (party == "REPUBLICAN")) %>% 
  mutate(TRBC_Sector = str_split_fixed(TRBC_Econ_Sector, "'", 3)[, 2],
         subsector = str_split_fixed(TRBC_Business_Sector, "'", 3)[, 2],
         activity_id = str_split_fixed(TRBC_ID, "'", 3)[, 2],
         private = as.numeric(is.na(ric)),
         democrat = ifelse(party == "DEMOCRAT", 1, -1),
         certainty = uncertainty,
         incumbent_party = toupper(incumbent_party),
         same_party = as.numeric(incumbent_party == party),
         same_party = replace_na(same_party, 0)) %>% 
  left_join(state_dict, by = "hq_state")

# Same state variable
cand_data <- cand_data %>% 
  mutate(same_state = as.numeric(hq_state_abb == state),
         same_state = replace_na(same_state, 0),
         race = paste0(state, district),
         foreign = as.numeric(hq != "United States of America"),
         foreign = replace_na(foreign, 1))

# Consumer facing and other sector variable
consumer$activity_id <- as.character(consumer$activity_id)
sector_category <- sector_category %>% 
  select(year, subsector, type)

cand_data <- cand_data %>% 
  left_join(consumer, by = "activity_id") %>% 
  left_join(sector_category, by = c("subsector", "year"))

# Select Columns

cand_data <- cand_data %>% 
  select(c(
    cmte_id, year, corporation, private, foreign, Economic.Sector, Business.Sector,
    Industry.Group, Industry, Activity, consumer_facing, state, district,
    open, special, rating, certainty, same_state, candidate, candidate_id, democrat,
    incumbent_challenge, same_party, party, firm_amount, firm_candidates,
    type, contribute, total_amount, total_count))

# Non-linearity

cand_data <- cand_data %>% 
  mutate(favorability = rating * democrat,
         favorabilitysq = favorability ^ 2,
         favorabilitycb = favorability ^ 3)
spline_basis <- ns(cand_data$favorability, df = 4)
colnames(spline_basis) <- paste0("spline", 1:4)
cand_data <- cbind(cand_data, spline_basis)

cand_data <- cand_data %>% 
  mutate(ppdem_box = replace_na(ppdem_box, "On the Fence"),
         pdem_box = replace_na(pdem_box, "On the Fence"))

names(cand_data) <- c(
  "cmte_id", "year", "corporation", "private", "foreign", "sector", "subsector", "industry",
  "subindustry", "activity", "consumer_facing", "state", "district",
  "open", "special", "rating", "certainty", "same_state", "candidate", "candidate_id",
  "democrat", "incumbency", "same_party", "party", "firm_amount", "firm_candidates",
  "industry_type", "contribute", "contribute_amount", "contribute_count", "favorability", "favorability_sq",
  "favorability_cb", "spline1", "spline2", "spline3", "spline4"
)

saveRDS(cand_data, paste0(DATA_PATH, "cand_model_data.RDS"))

########### MODELS ########### 
########## Extensive Model (Logit) ########## 
cand_data <- readRDS(paste0(DATA_PATH, "cand_model_data.RDS"))

cand_data$industry_type <- factor(cand_data$industry_type,
                                  levels = c("other", "hedged", "lean rep", "strong rep"))

extensive_modbase <- feglm(contribute ~
                             favorability + favorability_sq +
                             open + special +
                             private + foreign + 
                             same_state + log(firm_amount) +
                             party + incumbency +
                             sector + state + factor(year),
                           data = cand_data,
                           family = binomial(link = "logit"),
                           cluster = ~ cmte_id + candidate_id)
saveRDS(extensive_modbase, paste0(DATA_PATH, "extensive_baseline.RDS"))

extensive_modgp1 <- feglm(contribute ~
                             favorability + favorability_sq +
                             open + special +
                             private + foreign + 
                             same_state + log(firm_amount) +
                             party + incumbency +
                             sector + state + factor(year),
                           data = cand_data %>% filter(consumer_facing == 0),
                           family = binomial(link = "logit"),
                           cluster = ~ cmte_id + candidate_id)

extensive_modgp2 <- feglm(contribute ~
                             favorability + favorability_sq +
                             open + special +
                             private + foreign + 
                             same_state + log(firm_amount) +
                             party + incumbency +
                             sector + state + factor(year),
                           data = cand_data %>% filter(consumer_facing == 1),
                           family = binomial(link = "logit"),
                           cluster = ~ cmte_id + candidate_id)

saveRDS(list(
  nonconsumer = extensive_modgp1,
  consumer = extensive_modgp2
), paste0(DATA_PATH, "models/extensive_consumer.RDS"))

extensive_modgp3 <- feglm(contribute ~
                            favorability + favorability_sq +
                            open + special +
                            private + foreign + 
                            same_state + log(firm_amount) +
                            party + incumbency +
                            sector + state + factor(year),
                          data = cand_data %>% filter(industry_type == "hedged"),
                          family = binomial(link = "logit"),
                          cluster = ~ cmte_id + candidate_id)

extensive_modgp4 <- feglm(contribute ~
                            favorability + favorability_sq +
                            open + special +
                            private + foreign + 
                            same_state + log(firm_amount) +
                            party + incumbency +
                            sector + state + factor(year),
                          data = cand_data %>% filter(industry_type == "lean rep"),
                          family = binomial(link = "logit"),
                          cluster = ~ cmte_id + candidate_id)

extensive_modgp5 <- feglm(contribute ~
                            favorability + favorability_sq +
                            open + special +
                            private + foreign + 
                            same_state + log(firm_amount) +
                            party + incumbency +
                            state + factor(year),
                          data = cand_data %>% filter(industry_type == "strong rep"),
                          family = binomial(link = "logit"),
                          cluster = ~ cmte_id + candidate_id)

saveRDS(list(
  hedged = extensive_modgp3,
  leanrep = extensive_modgp4,
  strongrep = extensive_modgp5
), paste0(DATA_PATH, "models/extensive_partisan.RDS"))

extensive_mod1 <- feglm(contribute ~ 
                          favorability + favorability_sq +
                          open + special +
                          private + foreign +
                          same_state + log(firm_amount) +
                          party + incumbency + 
                          consumer_facing + 
                          (favorability + favorability_sq) * private +
                          (favorability + favorability_sq) * same_state +
                          (favorability + favorability_sq) * log(firm_amount) +
                          (favorability + favorability_sq) * party +
                          (favorability + favorability_sq) * incumbency +
                          (favorability + favorability_sq) * consumer_facing +
                          consumer_facing * incumbency +
                          consumer_facing * party +
                          private * incumbency + 
                          private * party +
                          sector + state + factor(year),
                        data = cand_data,
                        family = binomial(link = "logit"),
                        cluster = ~ cmte_id + candidate_id)

saveRDS(extensive_mod1, paste0(DATA_PATH, "models/extensive_consumer_int.RDS"))

extensive_mod2 <- feglm(contribute ~ 
                          favorability + favorability_sq +
                          open + special +
                          private + foreign +
                          same_state + log(firm_amount) +
                          party + incumbency + 
                          industry_type + 
                          (favorability + favorability_sq) * private +
                          (favorability + favorability_sq) * same_state +
                          (favorability + favorability_sq) * log(firm_amount) +
                          (favorability + favorability_sq) * party +
                          (favorability + favorability_sq) * incumbency +
                          (favorability + favorability_sq) * industry_type +
                          industry_type * incumbency +
                          industry_type * party +
                          private * incumbency +
                          private * party +
                          sector + state + factor(year),
                        data = cand_data,
                        family = binomial(link = "logit"),
                        cluster = ~ cmte_id + candidate_id)

saveRDS(extensive_mod2, paste0(DATA_PATH, "models/extensive_partisan_int.RDS"))

mod1 <- coeftable(extensive_modbase)
mod2 <- coeftable(extensive_modgp1)
mod3 <- coeftable(extensive_modgp2)
mod4 <- coeftable(extensive_modgp3)
mod5 <- coeftable(extensive_modgp4)
mod6 <- coeftable(extensive_modgp5)
coefs1 <- setNames(mod1[, "Estimate"],    rownames(mod1))
ses1   <- setNames(mod1[, "Std. Error"],  rownames(mod1))
coefs2 <- setNames(mod2[, "Estimate"],    rownames(mod2))
ses2   <- setNames(mod2[, "Std. Error"],  rownames(mod2))
coefs3 <- setNames(mod3[, "Estimate"],    rownames(mod3))
ses3   <- setNames(mod3[, "Std. Error"],  rownames(mod3))
coefs4 <- setNames(mod4[, "Estimate"],    rownames(mod4))
ses4   <- setNames(mod4[, "Std. Error"],  rownames(mod4))
coefs5 <- setNames(mod5[, "Estimate"],    rownames(mod5))
ses5   <- setNames(mod5[, "Std. Error"],  rownames(mod5))
coefs6 <- setNames(mod6[, "Estimate"],    rownames(mod6))
ses6   <- setNames(mod6[, "Std. Error"],  rownames(mod6))
dummy <- lm(contribute ~ 
              favorability + favorability_sq +
              open + special +
              private + foreign +
              same_state + log(firm_amount) +
              party + incumbency + 
              consumer_facing + 
              industry_type +
              (favorability + favorability_sq) * private +
              (favorability + favorability_sq) * same_state +
              (favorability + favorability_sq) * log(firm_amount) +
              (favorability + favorability_sq) * party +
              (favorability + favorability_sq) * incumbency +
              (favorability + favorability_sq) * consumer_facing +
              consumer_facing * incumbency +
              consumer_facing * party +
              (favorability + favorability_sq) * industry_type +
              industry_type * incumbency +
              industry_type * party,
            data = cand_data[c(1:5, 1683:1693,25231:25241, 37846:37853),])
stargazer(
  dummy, dummy, dummy, dummy, dummy, dummy,                               # <-- just a placeholder
  coef = list(coefs1, coefs2, coefs3, coefs4, coefs5, coefs6),
  se   = list(ses1, ses2, ses3, ses4, ses5, ses6),
  type = "latex",
  dep.var.labels.include = FALSE
)

########## Extensive Model (OLS) ########## 

extensive_olsbase <- feglm(log(contribute_amount + 1) ~
                             favorability + favorability_sq +
                             open + special +
                             private + foreign + 
                             same_state + log(firm_amount) +
                             party + incumbency +
                             sector + state + factor(year),
                           data = cand_data,
                           family = gaussian(),
                           cluster = ~ cmte_id + candidate_id)
saveRDS(extensive_olsbase, paste0(DATA_PATH, "models/extensive_ols_baseline.RDS"))

extensive_olsgp1 <- feglm(log(contribute_amount + 1) ~
                            favorability + favorability_sq +
                            open + special +
                            private + foreign + 
                            same_state + log(firm_amount) +
                            party + incumbency +
                            sector + state + factor(year),
                          data = cand_data %>% filter(consumer_facing == 0),
                          family = gaussian(),
                          cluster = ~ cmte_id + candidate_id)

extensive_olsgp2 <- feglm(log(contribute_amount + 1) ~
                            favorability + favorability_sq +
                            open + special +
                            private + foreign + 
                            same_state + log(firm_amount) +
                            party + incumbency +
                            sector + state + factor(year),
                          data = cand_data %>% filter(consumer_facing == 1),
                          family = gaussian(),
                          cluster = ~ cmte_id + candidate_id)

saveRDS(list(
  nonconsumer = extensive_olsgp1,
  consumer = extensive_olsgp2
), paste0(DATA_PATH, "models/extensive_ols_consumer.RDS"))

extensive_olsgp3 <- feglm(log(contribute_amount + 1) ~
                            favorability + favorability_sq +
                            open + special +
                            private + foreign + 
                            same_state + log(firm_amount) +
                            party + incumbency +
                            sector + state + factor(year),
                          data = cand_data %>% filter(industry_type == "hedged"),
                          family = gaussian(),
                          cluster = ~ cmte_id + candidate_id)

extensive_olsgp4 <- feglm(log(contribute_amount + 1) ~
                            favorability + favorability_sq +
                            open + special +
                            private + foreign + 
                            same_state + log(firm_amount) +
                            party + incumbency +
                            sector + state + factor(year),
                          data = cand_data %>% filter(industry_type == "lean rep"),
                          family = gaussian(),
                          cluster = ~ cmte_id + candidate_id)

extensive_olsgp5 <- feglm(log(contribute_amount + 1) ~
                            favorability + favorability_sq +
                            open + special +
                            private + foreign + 
                            same_state + log(firm_amount) +
                            party + incumbency +
                            state + factor(year),
                          data = cand_data %>% filter(industry_type == "strong rep"),
                          family = gaussian(),
                          cluster = ~ cmte_id + candidate_id)

saveRDS(list(
  hedged = extensive_olsgp3,
  leanrep = extensive_olsgp4,
  strongrep = extensive_olsgp5
), paste0(DATA_PATH, "models/extensive_ols_partisan.RDS"))

extensive_ols1 <- feglm(log(contribute_amount + 1) ~ 
                          favorability + favorability_sq +
                          open + special +
                          private + foreign +
                          same_state + log(firm_amount) +
                          party + incumbency + 
                          consumer_facing + 
                          (favorability + favorability_sq) * private +
                          (favorability + favorability_sq) * same_state +
                          (favorability + favorability_sq) * log(firm_amount) +
                          (favorability + favorability_sq) * party +
                          (favorability + favorability_sq) * incumbency +
                          (favorability + favorability_sq) * consumer_facing +
                          consumer_facing * incumbency +
                          consumer_facing * party +
                          sector + state + factor(year),
                        data = cand_data,
                        family = gaussian(),
                        cluster = ~ cmte_id + candidate_id)

saveRDS(extensive_ols1, paste0(DATA_PATH, "models/extensive_ols_consumer_int.RDS"))

extensive_ols2 <- feglm(log(contribute_amount + 1) ~ 
                          favorability + favorability_sq +
                          open + special +
                          private + foreign +
                          same_state + log(firm_amount) +
                          party + incumbency + 
                          industry_type + 
                          (favorability + favorability_sq) * private +
                          (favorability + favorability_sq) * same_state +
                          (favorability + favorability_sq) * log(firm_amount) +
                          (favorability + favorability_sq) * party +
                          (favorability + favorability_sq) * incumbency +
                          (favorability + favorability_sq) * industry_type +
                          industry_type * incumbency +
                          industry_type * party +
                          sector + state + factor(year),
                        data = cand_data,
                        family = gaussian(),
                        cluster = ~ cmte_id + candidate_id)

saveRDS(extensive_ols2, paste0(DATA_PATH, "models/extensive_ols_partisan_int.RDS"))

mod1 <- coeftable(extensive_olsbase)
mod2 <- coeftable(extensive_olsgp1)
mod3 <- coeftable(extensive_olsgp2)
mod4 <- coeftable(extensive_olsgp3)
mod5 <- coeftable(extensive_olsgp4)
mod6 <- coeftable(extensive_olsgp5)
coefs1 <- setNames(mod1[, "Estimate"],    rownames(mod1))
ses1   <- setNames(mod1[, "Std. Error"],  rownames(mod1))
coefs2 <- setNames(mod2[, "Estimate"],    rownames(mod2))
ses2   <- setNames(mod2[, "Std. Error"],  rownames(mod2))
coefs3 <- setNames(mod3[, "Estimate"],    rownames(mod3))
ses3   <- setNames(mod3[, "Std. Error"],  rownames(mod3))
coefs4 <- setNames(mod4[, "Estimate"],    rownames(mod4))
ses4   <- setNames(mod4[, "Std. Error"],  rownames(mod4))
coefs5 <- setNames(mod5[, "Estimate"],    rownames(mod5))
ses5   <- setNames(mod5[, "Std. Error"],  rownames(mod5))
coefs6 <- setNames(mod6[, "Estimate"],    rownames(mod6))
ses6   <- setNames(mod6[, "Std. Error"],  rownames(mod6))
dummy <- lm(contribute ~ 
              favorability + favorability_sq +
              open + special +
              private + foreign +
              same_state + log(firm_amount) +
              party + incumbency + 
              consumer_facing + 
              industry_type +
              (favorability + favorability_sq) * private +
              (favorability + favorability_sq) * same_state +
              (favorability + favorability_sq) * log(firm_amount) +
              (favorability + favorability_sq) * party +
              (favorability + favorability_sq) * incumbency +
              (favorability + favorability_sq) * consumer_facing +
              consumer_facing * incumbency +
              consumer_facing * party +
              (favorability + favorability_sq) * industry_type +
              industry_type * incumbency +
              industry_type * party,
            data = cand_data[c(1:5, 1683:1693,25231:25241, 37846:37853),])
stargazer(
  dummy, dummy, dummy, dummy, dummy, dummy,                               # <-- just a placeholder
  coef = list(coefs1, coefs2, coefs3, coefs4, coefs5, coefs6),
  se   = list(ses1, ses2, ses3, ses4, ses5, ses6),
  type = "latex",
  dep.var.labels.include = FALSE
)

mod1 <- coeftable(extensive_ols1)
mod2 <- coeftable(extensive_ols2)
coefs1 <- setNames(mod1[, "Estimate"],    rownames(mod1))
ses1   <- setNames(mod1[, "Std. Error"],  rownames(mod1))
coefs2 <- setNames(mod2[, "Estimate"],    rownames(mod2))
ses2   <- setNames(mod2[, "Std. Error"],  rownames(mod2))
dummy <- lm(contribute ~ 
              favorability + favorability_sq +
              open + special +
              private + foreign +
              same_state + log(firm_amount) +
              party + incumbency + 
              consumer_facing + 
              industry_type +
              (favorability + favorability_sq) * private +
              (favorability + favorability_sq) * same_state +
              (favorability + favorability_sq) * log(firm_amount) +
              (favorability + favorability_sq) * party +
              (favorability + favorability_sq) * incumbency +
              (favorability + favorability_sq) * consumer_facing +
              consumer_facing * incumbency +
              consumer_facing * party +
              (favorability + favorability_sq) * industry_type +
              industry_type * incumbency +
              industry_type * party,
            data = cand_data[c(1:5, 1683:1693,25231:25241, 37846:37853),])
stargazer(
  dummy, dummy,                               # <-- just a placeholder
  coef = list(coefs1, coefs2),
  se   = list(ses1, ses2),
  type = "latex",
  dep.var.labels.include = FALSE
)



































logit_model <- feglm(contribute ~ certainty * TRBC_Sector + certainty + factor(year) + 
                       private + certainty * same_state + 
                       certainty * log(firm_amount) + certainty * party + 
                       incumbent_challenge * certainty + 
                       incumbent_challenge * TRBC_Sector, 
                     data = cand_data,
                     family = binomial(link = "logit"),
                     cluster = ~ cmte_id + candidate_id)

logit_model <- feglm(contribute ~ 
                       favorability + favorabilitysq +
                       open + private +
                       favorability * TRBC_Sector + 
                       favorabilitysq * TRBC_Sector +
                       favorability * private + 
                       favorabilitysq * private +
                       favorability * same_state + 
                       favorabilitysq * same_state +
                       favorability * log(firm_amount) + 
                       favorabilitysq * log(firm_amount) +
                       favorability * incumbent_challenge + 
                       favorabilitysq * incumbent_challenge +
                       incumbent_challenge * TRBC_Sector +
                       factor(year),
                     data = cand_data,
                     family = binomial(link = "logit"),
                     cluster = ~ cmte_id + candidate_id)

logit_model <- feglm(contribute ~ 
                       spline1 + spline2 + spline3 + spline4 +
                       open + private +
                       (spline1 + spline2 + spline3 + spline4) * TRBC_Sector +
                       (spline1 + spline2 + spline3 + spline4) * private +
                       (spline1 + spline2 + spline3 + spline4) * same_state +
                       (spline1 + spline2 + spline3 + spline4) * log(firm_amount) +
                       (spline1 + spline2 + spline3 + spline4) * incumbent_challenge +
                       incumbent_challenge * TRBC_Sector +
                       factor(year),
                     data = cand_data,
                     family = binomial(link = "logit"),
                     cluster = ~ cmte_id + candidate_id)


cand_data <- cand_data %>% 
  filter(contribute == 1)

ols_model <- feols(log(total_amount+1) ~ certainty * TRBC_Sector + private + factor(year) + 
                     certainty * same_state + 
                     certainty * log(firm_amount) + certainty * party + 
                     incumbent_challenge * certainty + 
                     certainty * incumbent_history, 
                   data = cand_data,
                   cluster = ~ cmte_id + candidate_id)

saveRDS(list(extensive = logit_model,
             intensive = ols_model),
        paste0(DATA_PATH, "models/firm_cand_20250807.RDS"))


newdata <- data.frame(favorability = seq(-4, 4, length.out = 9))

# Add spline basis terms to match your model
new_spline <- ns(newdata$favorability, df = 4)
colnames(new_spline) <- paste0("spline", 1:4)
newdata <- cbind(newdata, new_spline)

# Fill in average or modal values for other covariates
newdata$open <- 0
newdata$special <- 0
newdata$private <- 0
newdata$foreign <- 0
newdata$party <- "REPUBLICAN"
newdata$same_state <- 0
newdata$firm_amount <- 72990
newdata$sector <- "Consumer Cyclicals"  # or any sector of interest
newdata$incumbency <- "I"   # or any other level
newdata$state = "WA"
newdata$year <- 2010
newdata$favorability_sq <- newdata$favorability^2

# Predict
newdata$predicted_prob <- predict(logit_model, newdata = newdata, type = "link")

# Plot
library(ggplot2)
ggplot(newdata, aes(x = favorability, y = predicted_prob)) +
  geom_line(size = 1.2) +
  labs(
    x = "Favorability (Project Win vs. Loss)",
    y = "Predicted Probability of Contribution",
    title = "Effect of Favorability on Contribution Probability"
  ) +
  theme_minimal()


sample_data <- cand_data %>% 
  filter(year == 2014) %>% 
  na.omit()

sample_data1 <- sample_data %>% 
  filter(industry_type == "strong rep")
sample_data2 <- sample_data %>% 
  filter(industry_type == "hedged")

df_binned <- sample_data %>%
  mutate(x_bin = cut(favorability, breaks = 100)) %>%
  group_by(x_bin) %>%
  summarise(x_mid = mean(favorability, na.rm = TRUE),
            p = mean(contribute, na.rm = TRUE))
df_binned1 <- sample_data1 %>%
  mutate(x_bin = cut(favorability, breaks = 100)) %>%
  group_by(x_bin) %>%
  summarise(x_mid = mean(favorability, na.rm = TRUE),
            p = mean(contribute, na.rm = TRUE))
df_binned2 <- sample_data2 %>%
  mutate(x_bin = cut(favorability, breaks = 100)) %>%
  group_by(x_bin) %>%
  summarise(x_mid = mean(favorability, na.rm = TRUE),
            p = mean(contribute, na.rm = TRUE))
df_binned_combined <- rbind(
  df_binned1 %>% mutate(type = "Strong Republican"),
  df_binned2 %>% mutate(type = "Hedged")
)

ggplot(df_binned, aes(x_mid, p)) +
  geom_smooth(method = "loess", span = 0.8, color = "blue") +
  labs(y = "Probability of Contribution", x = "Chance of Winning",
       title = "Probability of Contribution by Candidate Chance of Winning") +
  theme_minimal() +
  theme(text = element_text(family = "serif"))
ggsave(paste0(DATA_PATH, "figs/empirical_prob.png"))

ggplot(df_binned_combined) +
  geom_smooth(aes(x_mid, p, color = type), method = "loess", span = 0.8) +
  labs(y = "Probability of Contribution", x = "Chance of Winning",
       title = "Probability of Contribution by Candidate Chance of Winning",
       color = "Partisan Type") +
  theme_minimal() +
  theme(text = element_text(family = "serif"),
        legend.position = "bottom")
ggsave(paste0(DATA_PATH, "figs/empirical_prob_type.png"))
