library(lmtest)
library(ggplot2)
library(magrittr)
library(dplyr)
library(splines)
library(fixest)

# Read in Data
PATH <- "~/campaigncontributions/"
#PATH <- "S:/campaignfinance/"
MODEL_PATH <- paste0(PATH, "models/election/")
DATA_PATH <- paste0(PATH, "data/")
TABLE_PATH <- paste0(PATH, "tables/")
FIG_PATH <- paste0(PATH, "figs/")

data <- readRDS(paste0(DATA_PATH, "cand_model_data_election_year.RDS"))
baseline <- readRDS(paste0(MODEL_PATH, "extensive_baseline.RDS"))

#########################################################
#                                                       #
# Plot empirical and predictive conditional probability #
#                                                       #
#########################################################
data_subset <- data %>% 
  filter(year == 2018)

binned_plot <- data_subset %>% 
  mutate(fav_bin = cut(favorability, 20)) %>%
  group_by(fav_bin) %>%
  summarise(
    x_left  = as.numeric(sub("\\((.*),.*", "\\1", fav_bin)),
    x_right = as.numeric(sub(".*,([^]]*)\\]", "\\1", fav_bin)),
    x_mid   = (x_left + x_right) / 2,
    width   = x_right - x_left,
    p_hat   = mean(contribute),
    .groups = "drop"
  ) %>% 
  unique()

sample_data <- data.frame(
  favorability = rep(seq(-4, 4, length.out = 100),2),
  special = 0,
  private = 0,
  foreign = 0,
  same_state = 1,
  firm_amount = exp(12.449),
  party = rep(c("REPUBLICAN", "DEMOCRAT"), each = 100),
  incumbency = rep(c("I", "C"), each = 100),
  sector = rep(c("Utilities", "Healthcare"), each = 100),
  state = rep(c("CA", "WA"), each = 100),
  year = rep(c(2018, 2020), each = 100)
)

sample_data$favorability_sq <- sample_data$favorability ^ 2
pred <- predict(baseline, sample_data)[1:100]

plot_df <- data.frame(
  favorability = sample_data$favorability[1:100],
  probability = pred
)

empiric <- ggplot() +
  # (1) Empirical binned pattern — light bars in the background
  geom_rect(
    data = binned_plot,
    aes(xmin = x_left, xmax = x_right,
        ymin = 0, ymax = p_hat,
        fill = "Observed Average"),
    alpha = 0.5,
    color = NA
  ) +
  
  # (2) Smoothed empirical pattern — solid line
  geom_smooth(
    data = data_subset,
    aes(x = favorability, y = contribute, color = "Smoothed Empirical Trend"),
    method  = "gam",
    formula = y ~ s(x, bs = "cs"),
    se = FALSE,
    linewidth = 1.2
  ) +
  
  scale_color_manual(
    name = "",
    values = c(
      "Smoothed Empirical Trend" = "steelblue"
    )
  ) +
  scale_fill_manual(
    name = "",
    values = alpha("grey80", 0.5)
  ) +
  labs(
    x = "Chance of Winning",
    y = "Probability to Contribute"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    panel.grid.minor = element_blank(),
    legend.position = "bottom",
    text = element_text(family = "serif")
  )

predicted <- empiric +
  # (3) Model predicted pattern — dashed line
  geom_line(
    data = plot_df,
    aes(x = favorability, y = probability, color = "Model Prediction"),
    linewidth = 1.1,
    linetype = "dashed"
  ) +
  scale_color_manual(
    name = "",
    values = c(
      "Smoothed Empirical Trend" = "steelblue",
      "Model Prediction"    = "goldenrod3"
    )
  )

ggsave(paste0(FIG_PATH, "Conditional_Prob_Empiric_2018.png"), empiric)
ggsave(paste0(FIG_PATH, "Conditional_Prob_Predict_2018.png"), predicted)

#########################################################
#                                                       #
#           Compare Quadratic vs Spline Model           #
#                                                       #
#########################################################
baseline_spline <- readRDS(paste0(MODEL_PATH, "extensive_baseline_spline.RDS"))
S <- ns(data$favorability, df = 4)
attr_S <- attributes(S)
new_S <- ns(sample_data$favorability,
            knots = attr_S$knots,
            Boundary.knots = attr_S$Boundary.knots,
            intercept = attr_S$intercept)
colnames(new_S) <- paste0("spline", 1:4)
sample_data <- cbind(sample_data, new_S)

spline_pred <- predict(baseline_spline, sample_data)[1:100]

spline_plot_df <- data.frame(
  favorability = sample_data$favorability[1:100],
  spline_probability = spline_pred
)

predicted_spline <- predicted +
  # (4) Spline model predicted pattern — dashed line
  geom_line(
    data = spline_plot_df,
    aes(x = favorability, y = spline_probability, color = "Spline Prediction"),
    linewidth = 1.1,
    linetype = "dotdash"
  ) +
  scale_color_manual(
    name = "",
    values = c(
      "Model Prediction" = "goldenrod3",
      "Spline Prediction" = "forestgreen"
    )
  )
predicted_spline$layers <- predicted_spline$layers[-2]
ggsave(paste0(FIG_PATH, "Conditional_Prob_Spline_2018.png"), predicted_spline)

print(paste0("AIC for baseline quadratic model: ", AIC(baseline)))
print(paste0("AIC for baseline spline model: ", AIC(baseline_spline)))
print(paste0("BIC for baseline quadratic model: ", BIC(baseline)))
print(paste0("BIC for baseline spline model: ", BIC(baseline_spline)))

rm(baseline_spline)
rm(S)

#########################################################
#                                                       #
#                   Regression Tables                   #
#                                                       #
#########################################################
subset_private <- readRDS(paste0(MODEL_PATH, "extensive_private.RDS"))
subset_consumer <- readRDS(paste0(MODEL_PATH, "extensive_consumer.RDS"))

model_public <- subset_private$public
model_private <- subset_private$private
model_consumer <- subset_consumer$consumer
model_nonconsumer <- subset_consumer$nonconsumer
rm(subset_private)
rm(subset_consumer)

etable(baseline, 
       model_public, 
       model_private,
       model_consumer,
       model_nonconsumer,
       drop = c("sector", "state", "year"),
       tex = TRUE,
       file = paste0(TABLE_PATH, "baseline1.tex"))

subset_partisan_give <- readRDS(paste0(MODEL_PATH, "extensive_partisan_give.RDS"))
subset_partisan_market <- readRDS(paste0(MODEL_PATH, "extensive_partisan_market.RDS"))

model_Hedge_G <- subset_partisan_give$hedged
model_GOP_G <- subset_partisan_give$GOP
model_DEM_G <- subset_partisan_give$DEM
model_other_G <- subset_partisan_give$other
model_Hedge_M <- subset_partisan_market$hedged
model_GOP_M <- subset_partisan_market$GOP
model_DEM_M <- subset_partisan_market$DEM
rm(subset_partisan_give)
rm(subset_partisan_market)

etable(baseline, 
       model_Hedge_G,
       model_GOP_G,
       model_DEM_G,
       model_Other_G,
       model_Hedge_M, 
       model_GOP_M,
       model_DEM_M,
       drop = c("sector", "state", "year"),
       tex = TRUE,
       file = paste0(TABLE_PATH, "baseline2.tex"))

rm(baseline, model_consumer, model_nonconsumer,
   model_private, model_public,
   model_DEM_M, model_GOP_M, model_Hedge_M,
   model_Hedge_G, model_GOP_G, model_other_G)

model_private_int <- readRDS(paste0(MODEL_PATH, "extensive_private_int.RDS"))
model_consumer_int <- readRDS(paste0(MODEL_PATH, "extensive_consumer_int.RDS"))
model_partisan_G_int <- readRDS(paste0(MODEL_PATH, "extensive_partisan_give_int.RDS"))
model_partisan_M_int <- readRDS(paste0(MODEL_PATH, "extensive_partisan_market_int.RDS"))
model_partisan_all_int <- readRDS(paste0(MODEL_PATH, "extensive_partisan_all_int.RDS"))
model_partisan_pre_int <- readRDS(paste0(MODEL_PATH, "extensive_partisan_pre_int.RDS"))

etable(model_consumer_int, 
       model_partisan_G_int,
       model_partisan_M_int,
       model_partisan_all_int,
       model_partisan_pre_int,
       drop = c("sector", "state", "year"),
       tex = TRUE,
       file = paste0(TABLE_PATH, "interaction.tex"))
#########################################################
#                                                       #
#                Plot from Server Output                #
#                                                       #
#########################################################
PATH <- "S:/campaignfinance/"
FIG_PATH <- paste0(PATH, "figs/")
plots <- readRDS(paste0(FIG_PATH, "Conditional_Prob_2018.RDS"))
ggsave(paste0(FIG_PATH, "Conditional_Prob_2018_Empirics.png"), plots$empiric)
ggsave(paste0(FIG_PATH, "Conditional_Prob_2018_Quadratic.png"), plots$quadratic)
ggsave(paste0(FIG_PATH, "Conditional_Prob_2018_Spline.png"), plots$spline)

