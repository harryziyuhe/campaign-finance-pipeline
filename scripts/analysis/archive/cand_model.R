library(dplyr)
library(fixest)

PATH <- "~/campaigncontributions/"

election_data <- c("", "_election_year")
election_dir <- c("all/", "election/")

for (i in 1:2) {
  data_path <- election_data[i]
  dir_path <- election_dir[i]
  
  cand_data <- readRDS(paste0(PATH, "data/cand_model_data", data_path, ".RDS"))
  
  cand_data$partisanship_give <- factor(cand_data$partisanship_give,
                                        levels = c("other", "Hedged", "GOP"))
  cand_data$partisanship_market <- factor(cand_data$partisanship_market,
                                          levels = c("Hedged", "DEM", "GOP"))
  
  # Baseline Model
  
  extensive_modbase <- feglm(contribute ~
                               favorability + favorability_sq +
                               special + private + foreign + 
                               same_state + log(firm_amount) +
                               party + incumbency +
                               sector + state + factor(year),
                             data = cand_data,
                             family = binomial(link = "logit"),
                             cluster = ~ cmte_id + candidate_id)
  saveRDS(extensive_modbase, paste0(PATH, "model/", dir_path, "extensive_baseline.RDS"))
  
  extensive_modbase <- feglm(contribute ~
                               spline1 + spline2 + spline3 + spline4 +
                               special + private + foreign + 
                               same_state + log(firm_amount) +
                               party + incumbency +
                               sector + state + factor(year),
                             data = cand_data,
                             family = binomial(link = "logit"),
                             cluster = ~ cmte_id + candidate_id)
  saveRDS(extensive_modbase, paste0(PATH, "model/", dir_path, "extensive_baseline_spline.RDS"))
  
  # Consumer Facing Subsets
  
  extensive_modconsum0 <- feglm(contribute ~
                                  favorability + favorability_sq +
                                  special + private + foreign + 
                                  same_state + log(firm_amount) +
                                  party + incumbency +
                                  sector + state + factor(year),
                                data = cand_data %>% filter(consumer_facing == 0),
                                family = binomial(link = "logit"),
                                cluster = ~ cmte_id + candidate_id)
  
  extensive_modconsum1 <- feglm(contribute ~
                                  favorability + favorability_sq +
                                  special + private + foreign + 
                                  same_state + log(firm_amount) +
                                  party + incumbency +
                                  sector + state + factor(year),
                                data = cand_data %>% filter(consumer_facing == 1),
                                family = binomial(link = "logit"),
                                cluster = ~ cmte_id + candidate_id)
  
  saveRDS(list(
    nonconsumer = extensive_modconsum0,
    consumer = extensive_modconsum1
  ), paste0(PATH, "model/", dir_path, "extensive_consumer.RDS"))
  
  # Public Private Subsets
  
  extensive_modpublic <- feglm(contribute ~
                                 favorability + favorability_sq +
                                 special + foreign +
                                 same_state + log(firm_amount) +
                                 party + incumbency +
                                 sector + state + factor(year),
                               data = cand_data %>% filter(private == 0),
                               family = binomial(link = "logit"),
                               cluster = ~ cmte_id + candidate_id)
  
  extensive_modprivate <- feglm(contribute ~
                                  favorability + favorability_sq +
                                  special + foreign +
                                  same_state + log(firm_amount) +
                                  party + incumbency +
                                  sector + state + factor(year),
                                data = cand_data %>% filter(private == 1),
                                family = binomial(link = "logit"),
                                cluster = ~ cmte_id + candidate_id)
  
  saveRDS(list(
    public = extensive_modpublic,
    private = extensive_modprivate
  ), paste0(PATH, "model/", dir_path, "extensive_private.RDS"))
  
  # Giving Pattern Partisanship Subsets
  
  extensive_modhedged <- feglm(contribute ~
                                 favorability + favorability_sq +
                                 special + private + foreign + 
                                 same_state + log(firm_amount) +
                                 party + incumbency +
                                 sector + state + factor(year),
                               data = cand_data %>% filter(partisanship_give == "Hedged"),
                               family = binomial(link = "logit"),
                               cluster = ~ cmte_id + candidate_id)
  
  extensive_modGOP <- feglm(contribute ~
                              favorability + favorability_sq +
                              special + private + foreign + 
                              same_state + log(firm_amount) +
                              party + incumbency +
                              sector + state + factor(year),
                            data = cand_data %>% filter(partisanship_give == "GOP"),
                            family = binomial(link = "logit"),
                            cluster = ~ cmte_id + candidate_id)
  
  extensive_modDEM <- feglm(contribute ~
                                favorability + favorability_sq +
                                special + private + foreign + 
                                same_state + log(firm_amount) +
                                party + incumbency +
                                state + factor(year),
                              data = cand_data %>% filter(partisanship_give == "DEM"),
                              family = binomial(link = "logit"),
                              cluster = ~ cmte_id + candidate_id)
  
  extensive_modother <- feglm(contribute ~
                                favorability + favorability_sq +
                                special + private + foreign + 
                                same_state + log(firm_amount) +
                                party + incumbency +
                                state + factor(year),
                              data = cand_data %>% filter(partisanship_give == "other"),
                              family = binomial(link = "logit"),
                              cluster = ~ cmte_id + candidate_id)
  
  saveRDS(list(
    hedged = extensive_modhedged,
    GOP = extensive_modGOP,
    DEM = extensive_modDEM,
    other = extensive_modother
  ), paste0(PATH, "model/", dir_path, "extensive_partisan_give.RDS"))
  
  # Market Reaction Partisanship Subsets
  
  extensive_modhedged <- feglm(contribute ~
                                 favorability + favorability_sq +
                                 special + private + foreign + 
                                 same_state + log(firm_amount) +
                                 party + incumbency +
                                 sector + state + factor(year),
                               data = cand_data %>% filter(partisanship_market == "Hedged"),
                               family = binomial(link = "logit"),
                               cluster = ~ cmte_id + candidate_id)
  
  extensive_modGOP <- feglm(contribute ~
                              favorability + favorability_sq +
                              special + private + foreign + 
                              same_state + log(firm_amount) +
                              party + incumbency +
                              sector + state + factor(year),
                            data = cand_data %>% filter(partisanship_market == "GOP"),
                            family = binomial(link = "logit"),
                            cluster = ~ cmte_id + candidate_id)
  
  extensive_modDEM <- feglm(contribute ~
                              favorability + favorability_sq +
                              special + private + foreign + 
                              same_state + log(firm_amount) +
                              party + incumbency +
                              state + factor(year),
                            data = cand_data %>% filter(partisanship_market == "DEM"),
                            family = binomial(link = "logit"),
                            cluster = ~ cmte_id + candidate_id)
  
  saveRDS(list(
    hedged = extensive_modhedged,
    GOP = extensive_modGOP,
    DEM = extensive_modDEM
  ), paste0(PATH, "model/", dir_path, "extensive_partisan_market.RDS"))
  
  # Interaction Models
  
  extensive_mod0 <- feglm(contribute ~ 
                            favorability + favorability_sq +
                            special + private + foreign +
                            same_state + log(firm_amount) +
                            party + incumbency +
                            (favorability + favorability_sq) * private +
                            private * incumbency + 
                            private * party +
                            sector + state + factor(year),
                          data = cand_data,
                          family = binomial(link = "logit"),
                          cluster = ~ cmte_id + candidate_id)
  
  saveRDS(extensive_mod1, paste0(PATH, "model/", dir_path, "extensive_private_int.RDS"))
  
  extensive_mod1 <- feglm(contribute ~ 
                            favorability + favorability_sq +
                            special + private + foreign +
                            same_state + log(firm_amount) +
                            party + incumbency + 
                            consumer_facing + 
                            (favorability + favorability_sq) * consumer_facing +
                            consumer_facing * party +
                            sector + state + factor(year),
                          data = cand_data,
                          family = binomial(link = "logit"),
                          cluster = ~ cmte_id + candidate_id)
  
  saveRDS(extensive_mod1, paste0(PATH, "model/", dir_path, "extensive_consumer_int.RDS"))
  
  extensive_mod2 <- feglm(contribute ~ 
                            favorability + favorability_sq +
                            special + private + foreign +
                            same_state + log(firm_amount) +
                            party + incumbency + 
                            partisanship_give +
                            (favorability + favorability_sq) * partisanship_give +
                            partisanship_give * party +
                            sector + state + factor(year),
                          data = cand_data,
                          family = binomial(link = "logit"),
                          cluster = ~ cmte_id + candidate_id)
  
  saveRDS(extensive_mod2, paste0(PATH, "model/", dir_path, "extensive_partisan_give_int.RDS"))
  
  extensive_mod3 <- feglm(contribute ~ 
                            favorability + favorability_sq +
                            special + private + foreign +
                            same_state + log(firm_amount) +
                            party + incumbency + 
                            partisanship_market + 
                            (favorability + favorability_sq) * partisanship_market +
                            partisanship_market * party +
                            sector + state + factor(year),
                          data = cand_data,
                          family = binomial(link = "logit"),
                          cluster = ~ cmte_id + candidate_id)
  
  saveRDS(extensive_mod3, paste0(PATH, "model/", dir_path, "extensive_partisan_market_int.RDS"))

  extensive_mod4 <- feglm(contribute ~ 
                            favorability + favorability_sq +
                            special + private + foreign +
                            same_state + log(firm_amount) +
                            party + incumbency + 
                            partisanship_all + 
                            (favorability + favorability_sq) * partisanship_all +
                            partisanship_all * party +
                            sector + state + factor(year),
                          data = cand_data,
                          family = binomial(link = "logit"),
                          cluster = ~ cmte_id + candidate_id)
  
  saveRDS(extensive_mod4, paste0(PATH, "model/", dir_path, "extensive_partisan_all_int.RDS"))
  
  extensive_mod5 <- feglm(contribute ~ 
                            favorability + favorability_sq +
                            special + private + foreign +
                            same_state + log(firm_amount) +
                            party + incumbency + 
                            partisanship_pre + 
                            (favorability + favorability_sq) * partisanship_pre +
                            partisanship_pre * party +
                            sector + state + factor(year),
                          data = cand_data,
                          family = binomial(link = "logit"),
                          cluster = ~ cmte_id + candidate_id)

  saveRDS(extensive_mod5, paste0(PATH, "model/", dir_path, "extensive_partisan_pre_int.RDS"))
  
}


