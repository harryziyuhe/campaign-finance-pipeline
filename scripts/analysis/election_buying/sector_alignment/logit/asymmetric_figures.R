library(fixest)
library(ggplot2)
library(dplyr)
library(tidyr)

# =============================================================================
# Predicted-probability figures for the new asymmetric (co-partisan vs.
# cross-partisan) battery -- task #15, docs/theory_revision_handoff.md §10.
# Follows the SAME visual conventions as "paper/plots.R" (the
# existing paper figures) for a consistent look: theme_minimal(base_size=25),
# serif font, simulate-from-coefficient-vcov CIs via a base-R multivariate
# normal sampler (rmvnorm_base), peak location taken as the argmax of each
# simulated draw's curve (matches plots.R's peak_plot logic exactly, so the
# new figures' CI methodology is identical to the existing ones', not a
# different ad hoc approach).
#
# Color = sector alignment (GOP=firebrick, Other=grey10, DEM=steelblue);
# linetype = whether the candidate's own party matches the firm's aligned
# party (solid = co-partisan, dashed = cross-partisan) -- this directly
# visualizes the reviewer's asymmetry question (reviewer_comments.md #1):
# does a GOP-sector firm's curve for Republican targets (solid, firebrick)
# look different from its curve for Democratic targets (dashed, firebrick)?
# =============================================================================
PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "paper/figures/")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

rmvnorm_base <- function(n, mean, sigma) {
  p <- length(mean)
  Z <- matrix(rnorm(n * p), n, p)
  L <- chol(sigma)
  t(t(Z %*% L) + mean)
}

sample_data <- data.frame(
  favorability = 0, special = 0, private = 0, foreign = 0, same_state = 1,
  firm_cash = exp(12), state = "FL", year = 2012, stringsAsFactors = FALSE
)
sample_data$favorability_sq <- sample_data$favorability^2
fav_seq <- seq(-4, 4, length.out = 200)

palette5 <- c(Other = "grey10", GOP = "firebrick", DEM = "steelblue")

# curve_spec: which dummy/score variable to set to 1, and which candidate
# party to use for that row (drives the "party" additive control + which of
# co_/cross_ the dummy represents).
CATEGORICAL_CURVES <- tribble(
  ~curve,      ~color_group, ~partisan_type, ~party,        ~dummy,
  "Other",     "Other",      "co-partisan",  "REPUBLICAN",  NA_character_,
  "GOP co-partisan",  "GOP", "co-partisan",  "REPUBLICAN",  "co_partisan_GOP",
  "GOP cross-partisan","GOP","cross-partisan","DEMOCRAT",   "cross_partisan_GOP",
  "DEM co-partisan",  "DEM", "co-partisan",  "DEMOCRAT",    "co_partisan_DEM",
  "DEM cross-partisan","DEM","cross-partisan","REPUBLICAN", "cross_partisan_DEM"
)
CONTINUOUS_CURVES <- CATEGORICAL_CURVES
CONTINUOUS_CURVES$dummy <- c(NA, "score_co_GOP", "score_cross_GOP", "score_co_DEM", "score_cross_DEM")

build_newdata <- function(curve_spec, incumbency_val = NULL) {
  grid <- expand.grid(favorability = fav_seq, curve = curve_spec$curve, stringsAsFactors = FALSE) %>%
    left_join(curve_spec, by = "curve") %>%
    mutate(favorability_sq = favorability^2)
  base_other <- sample_data
  base_other$favorability <- NULL; base_other$favorability_sq <- NULL
  grid <- cbind(grid, base_other[rep(1, nrow(grid)), , drop = FALSE])
  if (!is.null(incumbency_val)) grid$incumbency <- incumbency_val
  for (v in unique(na.omit(curve_spec$dummy))) grid[[v]] <- 0
  for (i in seq_len(nrow(grid))) {
    if (!is.na(grid$dummy[i])) grid[[grid$dummy[i]]][i] <- 1
  }
  grid$party <- factor(grid$party, levels = c("DEMOCRAT", "REPUBLICAN"))
  if ("incumbency" %in% names(grid)) grid$incumbency <- factor(grid$incumbency, levels = c("I", "C", "O"))
  grid
}

simulate_pred <- function(model, newdata, S = 10000, seed = 123) {
  X_base <- model.matrix(model, data = newdata, type = "rhs", as.matrix = TRUE)
  beta_hat <- coef(model); Vc <- vcov(model)
  eta_lin_hat  <- as.numeric(X_base %*% beta_hat)
  eta_full_hat <- as.numeric(predict(model, newdata = newdata, type = "link"))
  fe_offset <- eta_full_hat - eta_lin_hat
  fam <- model$family
  set.seed(seed)
  beta_draws <- rmvnorm_base(S, mean = beta_hat, sigma = Vc)
  pred_hat <- fam$linkinv(eta_full_hat)
  eta_lin_draws  <- X_base %*% t(beta_draws)
  eta_full_draws <- sweep(eta_lin_draws, 1, fe_offset, "+")
  mu_draws <- fam$linkinv(eta_full_draws)
  list(pred_hat = pred_hat, mu_draws = mu_draws)
}

make_pred_df <- function(model, newdata, group_col = "curve") {
  sim <- simulate_pred(model, newdata)
  newdata %>%
    transmute(favorability, curve = .data[[group_col]], color_group, partisan_type,
              pred = as.numeric(sim$pred_hat)) %>%
    cbind(lower = apply(sim$mu_draws, 1, quantile, probs = 0.025)) %>%
    cbind(upper = apply(sim$mu_draws, 1, quantile, probs = 0.975)) -> pred_df
  attr(pred_df, "mu_draws") <- sim$mu_draws
  pred_df
}

make_peak_df <- function(pred_df, newdata) {
  curves <- unique(newdata$curve)
  mu_draws <- attr(pred_df, "mu_draws")
  peak_list <- lapply(curves, function(cv) {
    idx <- which(newdata$curve == cv)
    fav_g <- newdata$favorability[idx]
    mu_hat_g <- pred_df$pred[idx]
    peak_hat <- fav_g[which.max(mu_hat_g)]
    peak_sim <- apply(mu_draws[idx, , drop = FALSE], 2, function(col) fav_g[which.max(col)])
    # 95% to match every other interval the paper reports. The peak CIs here are
    # simulation-based; see the note in Section 5.3 on why the delta method is not
    # used for peak locations that may sit near a flat region of the curve.
    ci <- quantile(peak_sim, probs = c(0.025, 0.975))
    data.frame(curve = cv, peak_hat = peak_hat, peak_lo = ci[1], peak_hi = ci[2])
  })
  bind_rows(peak_list) %>%
    left_join(newdata %>% distinct(curve, color_group, partisan_type), by = "curve")
}

# Clean, light theme: horizontal gridlines only (thin, light grey), no vertical
# gridlines, no minor gridlines -- the heavy theme_minimal() default grid was
# flagged as "especially bad" and is replaced throughout.
clean_theme <- function(base_size) {
  theme_minimal(base_size = base_size) +
    theme(text = element_text(family = "serif"),
          panel.grid.minor = element_blank(),
          panel.grid.major.x = element_blank(),
          panel.grid.major.y = element_line(color = "grey85", linewidth = 0.3),
          axis.line.x = element_line(color = "grey40", linewidth = 0.4),
          axis.ticks.x = element_line(color = "grey40", linewidth = 0.4))
}

plot_pred <- function(pred_df, facet = NULL, title_note = "", free_y = FALSE) {
  pred_df$color_group <- factor(pred_df$color_group, levels = c("Other", "GOP", "DEM"))
  p <- ggplot(pred_df, aes(x = favorability, y = pred, color = color_group, linetype = partisan_type)) +
    geom_line(linewidth = 1.3) +
    scale_color_manual(name = "Sector alignment", values = palette5) +
    scale_linetype_manual(name = "Candidate's party", values = c(`co-partisan` = "solid", `cross-partisan` = "dotted")) +
    labs(x = "Chance of Winning", y = "Pr(Contribution)", caption = title_note) +
    clean_theme(22) +
    theme(legend.position = "bottom", legend.box = "vertical",
          plot.margin = margin(t = 10, r = 15, b = 5, l = 5))
  if (!is.null(facet)) p <- p + facet_wrap(as.formula(paste("~", facet)), scales = if (free_y) "free_y" else "fixed")
  p
}

plot_peak <- function(peak_df) {
  peak_df$color_group <- factor(peak_df$color_group, levels = c("Other", "GOP", "DEM"))
  peak_df$curve <- factor(peak_df$curve, levels = peak_df$curve)
  ggplot(peak_df, aes(x = curve, y = peak_hat, color = color_group, shape = partisan_type)) +
    geom_pointrange(aes(ymin = peak_lo, ymax = peak_hi), size = 0.9, linewidth = 1.1) +
    scale_color_manual(name = "Sector alignment", values = palette5) +
    scale_shape_manual(name = "Candidate's party", values = c(`co-partisan` = 16, `cross-partisan` = 17)) +
    labs(x = NULL, y = "Chance of Winning at Predicted Peak") +
    clean_theme(16) +
    theme(axis.text.x = element_text(angle = 35, hjust = 1),
          legend.position = "none",
          panel.grid.major.x = element_blank())
}

# =============================================================================
# 1) Table 2 analog: baseline (no incumbency split) -- categorical + continuous
# =============================================================================
mod_cat <- readRDS(paste0(PATH, "model/sector_alignment/ASYM_BASE_CATEGORICAL.RDS"))
nd_cat <- build_newdata(CATEGORICAL_CURVES)
nd_cat$incumbency <- factor("I", levels = c("I", "C", "O"))
pred_cat <- make_pred_df(mod_cat, nd_cat)
peak_cat <- make_peak_df(pred_cat, nd_cat)

ggsave(paste0(OUT_DIR, "Asymmetric_Pred_Base_Categorical.png"),
       plot_pred(pred_cat), width = 9, height = 7, dpi = 300)
ggsave(paste0(OUT_DIR, "Asymmetric_Peak_CI_Base_Categorical.png"),
       plot_peak(peak_cat), width = 5.5, height = 9.5, dpi = 300)

mod_cont <- readRDS(paste0(PATH, "model/sector_alignment/ASYM_BASE_CONTINUOUS.RDS"))
nd_cont <- build_newdata(CONTINUOUS_CURVES)
nd_cont$incumbency <- factor("I", levels = c("I", "C", "O"))
pred_cont <- make_pred_df(mod_cont, nd_cont)
peak_cont <- make_peak_df(pred_cont, nd_cont)

ggsave(paste0(OUT_DIR, "Asymmetric_Pred_Base_Continuous.png"),
       plot_pred(pred_cont),
       width = 9, height = 7, dpi = 300)
ggsave(paste0(OUT_DIR, "Asymmetric_Peak_CI_Base_Continuous.png"),
       plot_peak(peak_cont), width = 5.5, height = 9.5, dpi = 300)

# =============================================================================
# 2) Table 4: full curve-shape, faceted by candidate type (categorical only,
#    for legibility -- continuous DEM side is contaminated per wrinkle #1)
# =============================================================================
mod_fc <- readRDS(paste0(PATH, "model/sector_alignment/ASYM_FULLCURVE_NOFE.RDS"))

build_newdata_fc <- function(curve_spec, type) {
  grid <- build_newdata(curve_spec)
  grid$incumbency <- factor(if (type == "Incumbent") "I" else "C", levels = c("I", "C", "O"))  # Challenger as representative NonIncumbent
  if (type == "NonIncumbent") {
    for (v in unique(na.omit(curve_spec$dummy))) {
      bin_v <- paste0(v, ":incumbency_binNonIncumbent")
      # handled via incumbency_bin column directly below
    }
  }
  grid$incumbency_bin <- factor(if (type == "Incumbent") "Incumbent" else "NonIncumbent",
                                 levels = c("Incumbent", "NonIncumbent"))
  grid
}

nd_I  <- build_newdata_fc(CATEGORICAL_CURVES, "Incumbent")
nd_NI <- build_newdata_fc(CATEGORICAL_CURVES, "NonIncumbent")
nd_I$facet_type <- "Incumbent"; nd_NI$facet_type <- "Non-Incumbent"
nd_both <- rbind(nd_I, nd_NI)

pred_fc <- make_pred_df(mod_fc, nd_both)
pred_fc$facet_type <- nd_both$facet_type

# Incumbents only. For incumbents the diagnostic question is WHERE along the
# electoral-risk range support sits, which is what this curve shows; the
# non-incumbent panel's first-order question is one of level, answered by the
# level test and the pointwise odds ratios rather than by curve shape, so it is
# not carried here.
pred_fc_I <- pred_fc[pred_fc$facet_type == "Incumbent", ]
peak_fc_I <- make_peak_df(pred_fc_I, nd_cat)
ggsave(paste0(OUT_DIR, "Asymmetric_Pred_ByType_Categorical.png"),
       plot_pred(pred_fc_I),
       width = 9, height = 7, dpi = 300)
ggsave(paste0(OUT_DIR, "Asymmetric_Peak_ByType_Categorical.png"),
       plot_peak(peak_fc_I), width = 5.5, height = 9.5, dpi = 300)
# =============================================================================
# 3) Coefficient plot ("forest plot") for the headline candidate-type-
#    targeting result (Table 2 / tab:asym_incumbency) -- a visual complement
#    to the large regression table, since the point of that table is really
#    just 8 coefficients per measure. Terms plotted on the log-odds scale;
#    categorical and continuous measures are NOT on the same scale, so they
#    get separate facets with independent x-axes rather than being overlaid.
# =============================================================================
mod_inc_cat  <- readRDS(paste0(PATH, "model/sector_alignment/ASYM_INCUMBENCY_CATEGORICAL.RDS"))
mod_inc_cont <- readRDS(paste0(PATH, "model/sector_alignment/ASYM_INCUMBENCY_CONTINUOUS.RDS"))

COEF_TERMS <- tribble(
  ~term_label,                         ~color_group, ~partisan_type,   ~cand_type,   ~term_cat,                          ~term_cont,
  "GOP, Challenger",                   "GOP",        "co-partisan",    "Challenger", "incumbencyC:co_partisan_GOP",      "incumbencyC:score_co_GOP",
  "GOP, Open Seat",                    "GOP",        "co-partisan",    "Open Seat",  "incumbencyO:co_partisan_GOP",      "incumbencyO:score_co_GOP",
  "GOP, Challenger",                   "GOP",        "cross-partisan", "Challenger", "incumbencyC:cross_partisan_GOP",   "incumbencyC:score_cross_GOP",
  "GOP, Open Seat",                    "GOP",        "cross-partisan", "Open Seat",  "incumbencyO:cross_partisan_GOP",   "incumbencyO:score_cross_GOP",
  "DEM, Challenger",                   "DEM",        "co-partisan",    "Challenger", "incumbencyC:co_partisan_DEM",      "incumbencyC:score_co_DEM",
  "DEM, Open Seat",                    "DEM",        "co-partisan",    "Open Seat",  "incumbencyO:co_partisan_DEM",      "incumbencyO:score_co_DEM",
  "DEM, Challenger",                   "DEM",        "cross-partisan", "Challenger", "incumbencyC:cross_partisan_DEM",   "incumbencyC:score_cross_DEM",
  "DEM, Open Seat",                    "DEM",        "cross-partisan", "Open Seat",  "incumbencyO:cross_partisan_DEM",   "incumbencyO:score_cross_DEM"
)

extract_coefs <- function(model, terms_df, term_col, measure_label) {
  cf <- coef(model); V <- vcov(model)
  terms_df %>%
    rowwise() %>%
    mutate(
      term = .data[[term_col]],
      est = cf[[term]],
      se  = sqrt(V[term, term]),
      ci_low  = est - 1.96 * se,
      ci_high = est + 1.96 * se,
      measure = measure_label
    ) %>%
    ungroup()
}

coef_df <- bind_rows(
  extract_coefs(mod_inc_cat,  COEF_TERMS, "term_cat",  "Categorical measure"),
  extract_coefs(mod_inc_cont, COEF_TERMS, "term_cont", "Continuous measure")
)
coef_df$color_group <- factor(coef_df$color_group, levels = c("GOP", "DEM"))
coef_df$row_label <- paste(coef_df$cand_type, coef_df$partisan_type, sep = " -- ")
coef_df$row_label <- factor(coef_df$row_label, levels = rev(unique(coef_df$row_label)))
coef_df$measure <- factor(coef_df$measure, levels = c("Categorical measure", "Continuous measure"))

coef_plot <- ggplot(coef_df, aes(x = est, y = row_label, color = color_group, shape = partisan_type)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey50", linewidth = 0.5) +
  geom_pointrange(aes(xmin = ci_low, xmax = ci_high), size = 0.8, linewidth = 1.1,
                   position = position_dodge(width = 0.5)) +
  facet_wrap(~measure, scales = "free_x") +
  scale_color_manual(name = "Sector alignment", values = c(GOP = "firebrick", DEM = "steelblue")) +
  scale_shape_manual(name = "Candidate's party", values = c(`co-partisan` = 16, `cross-partisan` = 17)) +
  labs(x = "Coefficient (relative to Incumbent), 95% CI", y = NULL) +
  clean_theme(15) +
  theme(legend.position = "bottom", legend.box = "vertical",
        panel.grid.major.y = element_blank(),
        panel.grid.major.x = element_line(color = "grey85", linewidth = 0.3),
        strip.text = element_text(face = "bold"))

ggsave(paste0(OUT_DIR, "Asymmetric_Coefplot_Incumbency.png"), coef_plot, width = 11, height = 6.5, dpi = 300)

cat("Figures written to", OUT_DIR, "\n")
cat(list.files(OUT_DIR, pattern = "^Asymmetric"), sep = "\n")
