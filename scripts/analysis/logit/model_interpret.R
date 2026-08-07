suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(splines)
  library(fixest)
})

# =============================================================================
# 0) Paths + small utilities
# =============================================================================

data_root_env <- Sys.getenv("CAMPAIGNFINANCE_DATA_ROOT", unset = "")
if (!nzchar(data_root_env)) {
    stop(
        "CAMPAIGNFINANCE_DATA_ROOT is not set. Point it at the campaign-finance-data folder ",
        "(contains data/ and outputs/), e.g. Sys.setenv(CAMPAIGNFINANCE_DATA_ROOT = ",
        "'C:/Users/<you>/Dropbox/campaign-finance-data')."
    )
}
DATA_ROOT  <- normalizePath(data_root_env, mustWork = TRUE)
MODEL_PATH <- file.path(DATA_ROOT, "outputs", "models", "election")
DATA_PATH  <- file.path(DATA_ROOT, "data", "processed", "modeling")
TABLE_PATH <- file.path(DATA_ROOT, "outputs", "tables")
FIG_PATH   <- file.path(DATA_ROOT, "outputs", "figures")

dir.create(TABLE_PATH, showWarnings = FALSE, recursive = TRUE)
dir.create(FIG_PATH,   showWarnings = FALSE, recursive = TRUE)

# Load one object, use it, then remove it
readRDS2 <- function(path) {
  obj <- readRDS(path)
  obj
}

rm_gc <- function(...) {
  rm(list = as.character(substitute(list(...)))[-1], envir = parent.frame())
  invisible(gc())
}

# Safer predict wrapper: allow explicit type if you want response probs
predict_prob <- function(model, newdata) {
  # For fixest feglm, predict() defaults depend on version.
  # If you want probabilities, safest is type="response" when available.
  tryCatch(
    predict(model, newdata = newdata, type = "response"),
    error = function(e) predict(model, newdata = newdata) # fallback
  )
}

# =============================================================================
# 1) Plot empirical + predicted conditional probability (2018 only)
# =============================================================================

# Load data once; keep only columns used in this section to reduce memory.
data <- readRDS2(file.path(DATA_PATH, "cand_model_data_election_year.RDS"))

# If your RDS is huge, aggressively narrow columns before any filtering.
# (Adjust names if your dataset differs.)
needed_cols <- c(
  "year", "favorability", "contribute",
  "special", "private", "foreign", "same_state",
  "firm_cash", "party", "incumbency", "category", "state"
)
needed_cols <- intersect(needed_cols, names(data))
data <- data[, needed_cols, drop = FALSE]

# Filter with base subsetting (often fewer copies than piping)
idx2018 <- which(data$year == 2018)
data_subset <- data[idx2018, , drop = FALSE]

# Binned empirical averages (avoid unique(); summarise already collapses)
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
  )

# Make newdata for predictions. Keep minimal columns needed by the model.
# Note: firm_cash is used as log(firm_cash) in model, so firm_cash should be on original scale.
sample_data <- data.frame(
  favorability = seq(-4, 4, length.out = 100),
  special = 0,
  private = 0,
  foreign = 0,
  same_state = 1,
  firm_cash = exp(12),
  party = "DEMOCRAT",
  incumbency = "O",
  category = "Defense",
  state = "CA",
  year = 2018,
  stringsAsFactors = FALSE
)
sample_data$favorability_sq <- sample_data$favorability^2

# Load baseline model only when needed
baseline <- readRDS2(file.path(MODEL_PATH, "extensive_baseline.RDS"))
pred <- predict_prob(baseline, sample_data)

plot_df <- data.frame(
  favorability = sample_data$favorability,
  probability  = pred
)

empiric <- ggplot() +
  geom_rect(
    data = binned_plot,
    aes(xmin = x_left, xmax = x_right, ymin = 0, ymax = p_hat, fill = "Observed Average"),
    alpha = 0.5, color = NA
  ) +
  geom_smooth(
    data = data_subset,
    aes(x = favorability, y = contribute, color = "Smoothed Empirical Trend"),
    method = "gam",
    formula = y ~ s(x, bs = "cs"),
    se = FALSE,
    linewidth = 1.1
  ) +
  scale_fill_manual(name = "", values = c("Observed Average" = "grey80")) +
  scale_color_manual(name = "", values = c("Smoothed Empirical Trend" = "steelblue")) +
  labs(x = "Chance of Winning", y = "Probability to Contribute") +
  theme_minimal(base_size = 13) +
  theme(panel.grid.minor = element_blank(),
        legend.position = "bottom",
        text = element_text(family = "serif"))

predicted <- empiric +
  geom_line(
    data = plot_df,
    aes(x = favorability, y = probability, color = "Model Prediction"),
    linewidth = 1.05,
    linetype  = "dashed"
  ) +
  scale_color_manual(
    name = "",
    values = c("Smoothed Empirical Trend" = "steelblue",
               "Model Prediction"        = "goldenrod3")
  )

ggsave(file.path(FIG_PATH, "Conditional_Prob_Empiric_2018.png"), empiric, width = 7, height = 4.5)
ggsave(file.path(FIG_PATH, "Conditional_Prob_Predict_2018.png"), predicted, width = 7, height = 4.5)

# Free large objects from plotting section (baseline can be large)
rm_gc(binned_plot, plot_df, empiric, predicted, pred, sample_data, idx2018)

# =============================================================================
# 2) Compare quadratic vs spline baseline (minimal memory spline basis)
# =============================================================================

baseline_spline <- readRDS2(file.path(MODEL_PATH, "extensive_baseline_spline.RDS"))

# Do NOT build spline basis on full data frame; only use the numeric vector.
fav_vec <- data$favorability
S <- ns(fav_vec, df = 4)
attr_S <- attributes(S)

# Create spline terms only for sample points (100 rows)
fav_new <- seq(-4, 4, length.out = 100)
new_S <- ns(
  fav_new,
  knots = attr_S$knots,
  Boundary.knots = attr_S$Boundary.knots,
  intercept = attr_S$intercept
)
colnames(new_S) <- paste0("spline", 1:4)

# Recreate minimal newdata consistent with spline model
sample_spline <- data.frame(
  favorability = fav_new,
  special = 0,
  private = 0,
  foreign = 0,
  same_state = 1,
  firm_cash = exp(12),
  party = "DEMOCRAT",
  incumbency = "O",
  category = "Defense",
  state = "CA",
  year = 2018,
  stringsAsFactors = FALSE
)

sample_spline <- cbind(sample_spline, new_S)

spline_pred <- predict_prob(baseline_spline, sample_spline)

spline_plot_df <- data.frame(
  favorability = fav_new,
  spline_probability = spline_pred
)

# Rebuild a lightweight predicted plot (don’t re-use the previous large ggplot object)
predicted_spline <- ggplot() +
  geom_line(
    data = data.frame(favorability = fav_new, probability = predict_prob(baseline, data.frame(
      favorability = fav_new,
      favorability_sq = fav_new^2,
      special = 0, private = 0, foreign = 0, same_state = 1,
      firm_cash = exp(12), party = "DEMOCRAT", incumbency = "O",
      category = "Defense", state = "CA", year = 2018,
      stringsAsFactors = FALSE
    ))),
    aes(x = favorability, y = probability, color = "Quadratic Prediction"),
    linewidth = 1.05,
    linetype = "dashed"
  ) +
  geom_line(
    data = spline_plot_df,
    aes(x = favorability, y = spline_probability, color = "Spline Prediction"),
    linewidth = 1.05,
    linetype  = "dotdash"
  ) +
  labs(x = "Chance of Winning", y = "Probability to Contribute") +
  scale_color_manual(name = "", values = c("Quadratic Prediction" = "goldenrod3",
                                           "Spline Prediction"    = "forestgreen")) +
  theme_minimal(base_size = 13) +
  theme(panel.grid.minor = element_blank(),
        legend.position = "bottom",
        text = element_text(family = "serif"))

ggsave(file.path(FIG_PATH, "Conditional_Prob_Spline_2018.png"), predicted_spline, width = 7, height = 4.5)

cat("AIC baseline quadratic:", AIC(baseline), "\n")
cat("AIC baseline spline:",    AIC(baseline_spline), "\n")
cat("BIC baseline quadratic:", BIC(baseline), "\n")
cat("BIC baseline spline:",    BIC(baseline_spline), "\n")

rm_gc(baseline_spline, S, attr_S, new_S, sample_spline, spline_pred, spline_plot_df, predicted_spline, fav_vec, fav_new)

# =============================================================================
# 3) Regression tables (load-only-when-needed; remove immediately)
# =============================================================================

# ---- Baseline + consumer/private subsets ----
subset_private  <- readRDS2(file.path(MODEL_PATH, "extensive_private.RDS"))
subset_consumer <- readRDS2(file.path(MODEL_PATH, "extensive_consumer.RDS"))

model_public      <- subset_private$public
model_private     <- subset_private$private
model_consumer    <- subset_consumer$consumer
model_nonconsumer <- subset_consumer$nonconsumer

etable(
  baseline,
  model_public,
  model_private,
  model_consumer,
  model_nonconsumer,
  drop = c("category", "state", "year"),
  tex  = TRUE,
  file = file.path(TABLE_PATH, "baseline1.tex")
)

rm_gc(subset_private, subset_consumer,
      model_public, model_private, model_consumer, model_nonconsumer)

# ---- Baseline + partisanship subsets ----
subset_partisan_give   <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_give.RDS"))
subset_partisan_etf    <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_etf.RDS"))
subset_partisan_sn_pre <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_singlename_pre.RDS"))

model_Hedge_G <- subset_partisan_give$hedged
model_GOP_G   <- subset_partisan_give$GOP
model_DEM_G   <- subset_partisan_give$DEM
model_other_G <- subset_partisan_give$other

# FIX: use subset_partisan_etf (not subset_partisan_market)
model_other_E <- subset_partisan_etf$other
model_GOP_E   <- subset_partisan_etf$GOP
model_DEM_E   <- subset_partisan_etf$DEM

model_GOP_SNP   <- subset_partisan_sn_pre$GOP
model_DEM_SNP   <- subset_partisan_sn_pre$DEM
model_other_SNP <- subset_partisan_sn_pre$other

etable(
  baseline,
  model_Hedge_G, model_GOP_G, model_DEM_G, model_other_G,
  model_other_E, model_GOP_E, model_DEM_E,
  model_other_SNP, model_GOP_SNP, model_DEM_SNP,
  drop = c("category", "state", "year"),
  tex  = TRUE,
  file = file.path(TABLE_PATH, "baseline2.tex")
)

rm_gc(subset_partisan_give, subset_partisan_etf, subset_partisan_sn_pre, subset_partisan_sn_all,
      model_Hedge_G, model_GOP_G, model_DEM_G, model_other_G,
      model_other_E, model_GOP_E, model_DEM_E,
      model_GOP_SNP, model_DEM_SNP, model_other_SNP)

# ---- Interaction tables: private/consumer ----
model_privateB_int  <- readRDS2(file.path(MODEL_PATH, "extensive_private_int_base.RDS"))
model_privateF_int  <- readRDS2(file.path(MODEL_PATH, "extensive_private_int_full.RDS"))
model_consumerB_int <- readRDS2(file.path(MODEL_PATH, "extensive_consumer_int_base.RDS"))
model_consumerF_int <- readRDS2(file.path(MODEL_PATH, "extensive_consumer_int_full.RDS"))

etable(
  model_privateB_int, model_privateF_int,
  model_consumerB_int, model_consumerF_int,
  drop = c("category", "state", "year"),
  headers = c("Public", "Public", "Consumer", "Consumer"),
  tex  = TRUE,
  file = file.path(TABLE_PATH, "interaction1.tex")
)

rm_gc(model_privateB_int, model_privateF_int, model_consumerB_int, model_consumerF_int)

# ---- Interaction tables: give/ETF (base + full) ----
model_partisan_GB_int  <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_give_int_base.RDS"))
model_partisan_GF_int  <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_give_int_full.RDS"))
model_partisan_EB_int  <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_etf_int_base.RDS"))
model_partisan_EF_int  <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_etf_int_full.RDS"))
model_partisan_EPB_int <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_etfpre_int_base.RDS"))
model_partisan_EPF_int <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_etfpre_int_full.RDS"))

etable(
  model_partisan_GB_int, model_partisan_GF_int,
  model_partisan_EB_int, model_partisan_EF_int,
  model_partisan_EPB_int, model_partisan_EPF_int,
  drop = c("category", "state", "year"),
  headers = c("Giving Class", "Giving Class",
              "ETF Class", "ETF Class",
              "ETF Pre Score", "ETF Pre Score"),
  tex  = TRUE,
  file = file.path(TABLE_PATH, "interaction2.tex")
)

rm_gc(model_partisan_GB_int, model_partisan_GF_int,
      model_partisan_EB_int, model_partisan_EF_int,
      model_partisan_EPB_int, model_partisan_EPF_int,
      model_partisan_EAB_int, model_partisan_EAF_int)

# ---- Interaction tables: single-name variants ----
model_partisan_SNPB_int  <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_singlename_pre_int_base.RDS"))
model_partisan_SNPF_int  <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_singlename_pre_int_full.RDS"))
model_partisan_SNCPB_int <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_singlename_score_pre_int_base.RDS"))
model_partisan_SNCPF_int <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_singlename_score_pre_int_full.RDS"))

etable(
  model_partisan_SNPB_int, model_partisan_SNPF_int,
  model_partisan_SNCPB_int, model_partisan_SNCPF_int,
  drop = c("category", "state", "year"),
  headers = c("SN Pre Class", "SN Pre Class",
              "SN Pre Score", "SN Pre Score"),
  tex  = TRUE,
  file = file.path(TABLE_PATH, "interaction3.tex")
)

rm_gc(model_partisan_SNPB_int, model_partisan_SNPF_int,
      model_partisan_SNAB_int, model_partisan_SNAF_int,
      model_partisan_SNCPB_int, model_partisan_SNCPF_int,
      model_partisan_SNCAB_int, model_partisan_SNCAF_int)

# Finally drop the big data frame + baseline model if you no longer need them
rm_gc(data, data_subset, baseline)
