cand_data <- cand_data %>% 
  mutate(contribute_amount_adj = pmin(contribute_amount, 10000)) %>% 
  drop_na(singlename_score_pre) %>% 
  mutate(singlename_GOP = pmax(singlename_score_pre, 0),
         singlename_DEM = pmax(-singlename_score_pre, 0),
         subsec_GOP = pmax(subsec_partisan_score, 0),
         subsec_DEM = pmax(-subsec_partisan_score, 0),
         contribute_prop = contribute_amount / log(firm_cash),
         singlename_partisan_pre = factor(singlename_partisan_pre, levels = c("Other", "GOP", "DEM")))

ggplot() +
  #geom_point() +
  geom_smooth(data = cand_data %>% filter(singlename_score_pre > 0.4), aes(x = favorability, y = contribute_prop), color = "red")+
  geom_smooth(data = cand_data %>% filter(singlename_score_pre < -0.4), aes(x = favorability, y = contribute_prop), color = "blue")+
  geom_smooth(data = cand_data %>% filter(abs(singlename_score_pre) <= 0.4), aes(x = favorability, y = contribute_prop), color = "black")


ggplot() +
  geom_smooth(data = cand_data, aes(x = favorability, y = contribute_prop, color = category), method = "loess")

model <- feols(contribute_amount_adj ~ favorability + favorability_sq + favorability * singlename_GOP + 
                 favorability * singlename_DEM  + incumbency * (singlename_GOP + singlename_DEM) +
                 party + incumbency + same_state + foreign + special | year + state, 
               data = cand_data,
               cluster ~ candidate_id + cmte_id)

model <- feols(contribute_amount_adj ~ favorability + favorability_sq + favorability * subsec_GOP + 
                 favorability * subsec_DEM  + incumbency * (subsec_GOP + subsec_DEM) +
                 party + incumbency + same_state + foreign + special | year + state, 
               data = cand_data,
               cluster ~ candidate_id + cmte_id)

model <- feols(contribute_amount_adj ~ favorability_sq + favorability * singlename_partisan_pre +
                 party + incumbency + same_state + foreign + special + party * singlename_partisan_pre +
                 incumbency * singlename_partisan_pre | year + state, 
               data = cand_data,
               cluster ~ candidate_id + cmte_id)
