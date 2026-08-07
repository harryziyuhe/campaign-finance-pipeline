library(lmtest)
library(ggplot2)
library(magrittr)
library(tidyr)
library(dplyr)

MODEL_PATH <- "S:/campaignfinance/models/election/"
DATA_PATH <- "S:/campaignfinance/data/"

data <- readRDS(paste0(DATA_PATH, "cand_model_data_election_year.RDS"))

baseline = readRDS(paste0(MODEL_PATH, "extensive_baseline.RDS"))
summary(baseline)

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

ggplot(plot_df) +
  geom_line(aes(x = favorability, y = probability))

data %>% 
  filter(year == 2018) %>%
  mutate(fav_bin = cut(favorability, 20)) %>%
  group_by(fav_bin) %>%
  summarize(p_hat = mean(contribute),
            x_mid = (min(favorability) + max(favorability))/2) %>%
  ggplot(aes(x = x_mid, y = p_hat)) +
  geom_line() +
  geom_point() +
  labs(
    title = "Binned Average P(Y = 1 | X)",
    x = "Favorability",
    y = "Share Contributing"
  )

partisan = readRDS(paste0(MODEL_PATH, "extensive_partisan.RDS"))
summary(partisan$hedged)
summary(partisan$leanrep)
summary(partisan$strongrep)

partisan_int = readRDS(paste0(MODEL_PATH, "extensive_partisan_int.RDS"))
summary(partisan_int)


df18 <- data %>% filter(year == 2018)

# Binned averages: use equal-count bins (cut_number) so bins are comparable
binned_plot <- df18 %>%
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

ggplot() +
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
    data = df18,
    aes(x = favorability, y = contribute, color = "Smoothed Empirical Trend"),
    method  = "gam",
    formula = y ~ s(x, bs = "cs"),
    se = FALSE,
    linewidth = 1.2
  ) +
  
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
ggsave("S:/campaignfinance/figs/Conditional_Contribution_Prob_2018.png")

df_subset <- data %>% filter(year == 2018)
binned_plot <- df_subset %>%
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

ggplot() +
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
    data = df_subset,
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
ggsave("S:/campaignfinance/figs/Conditional_Contribution_Prob.png")

