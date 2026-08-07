suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(tidyr)
  library(fixest)  # for fixest predict/model.matrix behavior
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
FIG_PATH   <- file.path(DATA_ROOT, "outputs", "figures", "tobit")

dir.create(FIG_PATH, showWarnings = FALSE, recursive = TRUE)

readRDS2 <- function(path) {
  readRDS(path)
}

rm_gc <- function(...) {
  rm(list = as.character(substitute(list(...)))[-1], envir = parent.frame())
  invisible(gc())
}

# Safer predict wrapper for fixest models: prefer type = "response"
predict_prob <- function(model, newdata) {
  tryCatch(
    predict(model, newdata = newdata, type = "response"),
    error = function(e) predict(model, newdata = newdata)
  )
}

# Simple multivariate normal sampler (no extra packages)
rmvnorm_base <- function(n, mean, sigma) {
  p <- length(mean)
  Z <- matrix(rnorm(n * p), n, p)
  L <- chol(sigma)
  t(t(Z %*% L) + mean)
}

# =============================================================================
# 1) Common baseline row for covariates
# =============================================================================

sample_data <- data.frame(
  favorability = seq(-4, 4, length.out = 100),
  special      = 0,
  private      = 0,
  foreign      = 0,
  same_state   = 1,
  firm_cash    = exp(14),
  party        = "REPUBLICAN",
  incumbency   = "I",
  state        = "CA",
  year         = 2018,
  stringsAsFactors = FALSE
)
sample_data$favorability_sq <- sample_data$favorability^2

# =============================================================================
# 2) Interaction model: predictions, marginal effects, and peak-location CIs
# =============================================================================

plot_interaction <- function(which = c("me", "pred", "peak"), base = TRUE) {
  # normalize "which"
  valid <- c("me", "pred", "peak")
  which <- intersect(valid, tolower(which))
  if (length(which) == 0) which <- valid
  
  if (base) {
    int_model <- readRDS2(file.path(MODEL_PATH, "tobit_partisan_singlename_pre_int_base.RDS"))
  } else {
    int_model <- readRDS2(file.path(MODEL_PATH, "tobit_partisan_singlename_pre_int_full.RDS"))
  }
  
  fav_seq     <- seq(-4, 4, length.out = 200)
  part_levels <- c("GOP", "DEM", "Other")  # adjust if your factor levels differ
  
  base_row <- sample_data[1, , drop = FALSE]
  
  newdata_int <- expand.grid(
    favorability             = fav_seq,
    singlename_partisan_pre  = part_levels,
    stringsAsFactors         = FALSE
  )
  
  base_other <- base_row
  base_other$favorability <- NULL
  base_other_rep <- base_other[rep(1, nrow(newdata_int)), , drop = FALSE]
  
  newdata_int <- cbind(newdata_int, base_other_rep)
  newdata_int$favorability_sq <- newdata_int$favorability^2
  
  newdata_int$singlename_partisan_pre <- factor(
    newdata_int$singlename_partisan_pre,
    levels = part_levels
  )
  
  palette_int <- c("firebrick", "steelblue", "darkolivegreen4")
  names(palette_int) <- part_levels
  
  # ---------- Simulation setup ----------
  
  # Baseline RHS design matrix (no FE)
  X_base <- model.matrix(int_model$model, data = newdata_int, type = "rhs", as.matrix = TRUE)
  
  beta_hat <- coef(int_model$model)
  l <- length(beta_hat)
  Vc       <- int_model$vcov_cluster[1:l, 1:l, drop = FALSE]
  
  stopifnot(identical(colnames(X_base), names(beta_hat)))
  
  # Linear predictor with only RHS part (no FE) at beta_hat
  eta_lin_hat_base  <- as.numeric(X_base %*% beta_hat)
  # Full linear predictor including FE at beta_hat
  eta_full_hat_base <- as.numeric(predict(int_model$model, newdata = newdata_int, type = "link"))
  
  # Fixed-effect offset (assumed independent of favorability)
  fe_offset <- eta_full_hat_base - eta_lin_hat_base
  
  fam <- gaussian(link = "identity")
  
  set.seed(123)
  S <- 1000
  
  beta_draws <- rmvnorm_base(S, mean = beta_hat, sigma = Vc)  # S x p
  
  # ---------- 3a) Predictions (level) ----------
  
  # point predictions
  pred_hat <- fam$linkinv(eta_full_hat_base)
  
  # Draws for baseline predictions (same grid)
  eta_lin_draws_base  <- X_base %*% t(beta_draws)                    # n x S
  eta_full_draws_base <- sweep(eta_lin_draws_base, 1, fe_offset, "+")
  mu_pred_draws       <- fam$linkinv(eta_full_draws_base)            # n x S
  
  pred_df <- newdata_int %>%
    transmute(
      favorability,
      singlename_partisan_pre,
      pred = as.numeric(pred_hat)
    )
  
  # ---------- 3b) Marginal effects via finite differences ----------
  
  h <- 0.01
  
  nd_plus  <- newdata_int
  nd_minus <- newdata_int
  
  nd_plus$favorability  <- nd_plus$favorability  + h
  nd_minus$favorability <- nd_minus$favorability - h
  
  nd_plus$favorability_sq  <- nd_plus$favorability^2
  nd_minus$favorability_sq <- nd_minus$favorability^2
  
  X_plus  <- model.matrix(int_model$model, data = nd_plus,  type = "rhs", as.matrix = TRUE)
  X_minus <- model.matrix(int_model$model, data = nd_minus, type = "rhs", as.matrix = TRUE)
  
  # Sanity: RHS structure must match
  stopifnot(identical(colnames(X_plus), colnames(X_base)))
  stopifnot(identical(colnames(X_minus), colnames(X_base)))
  
  # Draws for ±h
  eta_lin_plus_draws  <- X_plus  %*% t(beta_draws)
  eta_lin_minus_draws <- X_minus %*% t(beta_draws)
  
  eta_full_plus_draws  <- sweep(eta_lin_plus_draws,  1, fe_offset, "+")
  eta_full_minus_draws <- sweep(eta_lin_minus_draws, 1, fe_offset, "+")
  
  mu_plus_draws  <- fam$linkinv(eta_full_plus_draws)
  mu_minus_draws <- fam$linkinv(eta_full_minus_draws)
  
  me_draws <- (mu_plus_draws - mu_minus_draws) / (2 * h)  # n x S
  
  # Point estimate ME using beta_hat
  eta_lin_plus_hat   <- as.numeric(X_plus  %*% beta_hat)
  eta_lin_minus_hat  <- as.numeric(X_minus %*% beta_hat)
  eta_full_plus_hat  <- eta_lin_plus_hat  + fe_offset
  eta_full_minus_hat <- eta_lin_minus_hat + fe_offset
  
  mu_plus_hat  <- fam$linkinv(eta_full_plus_hat)
  mu_minus_hat <- fam$linkinv(eta_full_minus_hat)
  
  me_hat <- (mu_plus_hat - mu_minus_hat) / (2 * h)
  
  me_ci_df <- newdata_int %>%
    transmute(
      favorability,
      singlename_partisan_pre,
      me_hat = as.numeric(me_hat),
      me_lo  = apply(me_draws, 1, quantile, probs = 0.05),
      me_hi  = apply(me_draws, 1, quantile, probs = 0.95)
    )
  
  me_ci_df$singlename_partisan_pre <- factor(
    me_ci_df$singlename_partisan_pre,
    levels = part_levels
  )
  
  # ---------- 3c) Peak-location CIs ----------
  # For each draw and each partisan group, find the x (favorability) at which
  # the predicted probability is maximal.
  
  peak_list <- lapply(part_levels, function(g) {
    idx_g   <- which(newdata_int$singlename_partisan_pre == g)
    fav_g   <- newdata_int$favorability[idx_g]
    mu_hat_g <- pred_hat[idx_g]
    
    # point estimate: argmax of predicted probability at beta_hat
    peak_hat <- fav_g[which.max(mu_hat_g)]
    
    # simulated peak locations across draws
    mu_draws_g <- mu_pred_draws[idx_g, , drop = FALSE]  # rows: favorability, cols: draws
    peak_sim   <- apply(mu_draws_g, 2, function(col) fav_g[which.max(col)])
    
    ci_peak <- quantile(peak_sim, probs = c(0.05, 0.95))
    
    data.frame(
      singlename_partisan_pre = g,
      peak_hat = peak_hat,
      peak_lo  = as.numeric(ci_peak[1]),
      peak_hi  = as.numeric(ci_peak[2])
    )
  })
  
  peak_df <- bind_rows(peak_list)
  peak_df$singlename_partisan_pre <- factor(
    peak_df$singlename_partisan_pre,
    levels = part_levels
  )
  
  # ---------- 3d) Build requested plots ----------
  
  # (1) Marginal effect plot with CI
  if ("me" %in% which) {
    me_plot <- ggplot(me_ci_df,
                      aes(
                        x = favorability,
                        y = me_hat,
                        color = singlename_partisan_pre,
                        fill  = singlename_partisan_pre
                      )) +
      geom_hline(yintercept = 0, linetype = "dotted", linewidth = 0.4) +
      geom_ribbon(
        aes(ymin = me_lo, ymax = me_hi),
        alpha = 0.18,
        color = NA
      ) +
      geom_line(linewidth = 1.05) +
      scale_color_manual(
        name   = "Contributor type",
        values = palette_int
      ) +
      scale_fill_manual(
        name   = "Contributor type",
        values = palette_int
      ) +
      labs(
        x = "Chance of Winning",
        y = "Marginal Effect of Chnance of Winning on Contribution Probability"
      ) +
      theme_minimal(base_size = 12) +
      theme(
        text = element_text(family = "serif"),
        axis.title.y = element_text(size = 10),
        legend.position   = "bottom",
        panel.grid.minor  = element_blank(),
        plot.margin       = margin(t = 10, r = 5, b = 5, l = 5)
      )
    
    if (base) {
      FILE_NAME <- "Tobit_Partisan_Int_ME_CI_Base.png"
    } else {
      FILE_NAME <- "Tobit_Partisan_Int_ME_CI_Full.png"
    }
    ggsave(
      file.path(FIG_PATH, FILE_NAME),
      me_plot,
      width  = 11,
      height = 6.3
    )
  }
  
  # (2) Prediction plot (no CI)
  if ("pred" %in% which) {
    pred_df$singlename_partisan_pre <- factor(
      pred_df$singlename_partisan_pre,
      levels = part_levels
    )
    
    pred_plot <- ggplot(pred_df,
                        aes(
                          x = favorability,
                          y = pred,
                          color = singlename_partisan_pre
                        )) +
      geom_line(linewidth = 1.05) +
      scale_color_manual(
        name   = "Contributor type",
        values = palette_int
      ) +
      labs(
        x = "Chance of Winning",
        y = "Probability of Contribution"
      ) +
      theme_minimal(base_size = 12) +
      theme(
        text = element_text(family = "serif"),
        legend.position   = "bottom",
        panel.grid.minor  = element_blank(),
        plot.margin       = margin(t = 10, r = 5, b = 5, l = 5)
      )
    
    if (base) {
      FILE_NAME <- "Tobit_Partisan_Int_Pred_Base.png"
    } else {
      FILE_NAME <- "Tobit_Partisan_Int_Pred_Full.png"
    }
    
    ggsave(
      file.path(FIG_PATH, FILE_NAME),
      pred_plot,
      width  = 8,
      height = 6.3
    )
  }
  
  # (3) Vertical peak-location CI plot
  if ("peak" %in% which) {
    peak_plot <- ggplot(peak_df,
                        aes(
                          x = singlename_partisan_pre,
                          y = peak_hat,
                          color = singlename_partisan_pre
                        )) +
      geom_pointrange(
        aes(ymin = peak_lo, ymax = peak_hi),
        size = 0.6,
        width = 1.2
      ) +
      scale_color_manual(
        name   = "Contributor type",
        values = palette_int
      ) +
      labs(
        x = "Contributor Partisanship",
        y = "Chance of Winning at Predicted Peak"
      ) +
      theme_minimal(base_size = 12) +
      theme(
        text = element_text(family = "serif"),
        axis.title.x = element_text(size = 10),
        legend.position   = "none",
        panel.grid.minor  = element_blank(),
        plot.margin       = margin(t = 10, r = 5, b = 5, l = 5)
      )
    
    if (base) {
      FILE_NAME <- "Tobit_Partisan_Int_Peak_CI_Base.png"
    } else {
      FILE_NAME <- "Tobit_Partisan_Int_Peak_CI_Full.png"
    }
    
    ggsave(
      file.path(FIG_PATH, FILE_NAME),
      peak_plot,
      width  = 2.5,
      height = 6.3
    )
  }
  
  rm_gc(int_model, fav_seq, base_row, newdata_int,
        X_base, beta_hat, Vc, eta_lin_hat_base, eta_full_hat_base, fe_offset,
        beta_draws, eta_lin_draws_base, eta_full_draws_base, mu_pred_draws,
        nd_plus, nd_minus, X_plus, X_minus,
        eta_lin_plus_draws, eta_lin_minus_draws,
        eta_full_plus_draws, eta_full_minus_draws,
        mu_plus_draws, mu_minus_draws,
        eta_lin_plus_hat, eta_lin_minus_hat,
        eta_full_plus_hat, eta_full_minus_hat,
        mu_plus_hat, mu_minus_hat,
        me_draws, me_hat, me_ci_df,
        pred_hat, pred_df,
        peak_list, peak_df)
}

# =============================================================================
# 3) Interaction model with continuous partisan score (cont): 
#    predictions, marginal effects, and peak-location CIs
# =============================================================================

plot_interaction_continuous <- function(which = c("me", "pred", "peak"),
                                        K = 1,
                                        base = TRUE) {
  # normalize "which"
  valid <- c("me", "pred", "peak")
  which <- intersect(valid, tolower(which))
  if (length(which) == 0) which <- valid
  
  if (base) {
    model_file = "tobit_partisan_singlename_score_pre_int_base.RDS"
  } else {
    model_file = "tobit_partisan_singlename_score_pre_int_full.RDS"
  }
  
  cont_model <- readRDS2(file.path(MODEL_PATH, model_file))
  
  fav_seq <- seq(-4, 4, length.out = 200)
  
  # three representative values of the continuous partisan score
  partisan_levels <- data.frame(
    level          = c("GOP", "Neutral", "DEM"),
    singlename_pre = c(-K, 0, K)
  )
  
  base_row <- sample_data[1, , drop = FALSE]
  
  newdata_cont <- expand.grid(
    favorability = fav_seq,
    level        = partisan_levels$level,
    stringsAsFactors = FALSE
  ) %>%
    left_join(partisan_levels, by = "level") %>%
    mutate(
      favorability_sq     = favorability^2,
      singlename_GOP_pre  = pmax(0, -singlename_pre),
      singlename_DEM_pre  = pmax(0,  singlename_pre)
    )
  
  # attach other covariates at baseline values
  base_other <- base_row
  base_other$favorability    <- NULL
  base_other$favorability_sq <- NULL
  
  base_other_rep <- base_other[rep(1, nrow(newdata_cont)), , drop = FALSE]
  newdata_cont  <- cbind(newdata_cont, base_other_rep)
  
  # palette and factor ordering
  level_levels <- c("GOP", "Neutral", "DEM")
  newdata_cont$level <- factor(newdata_cont$level, levels = level_levels)
  
  palette_cont <- c(
    GOP     = "firebrick",
    Neutral = "grey40",
    DEM     = "steelblue"
  )
  
  # ---------- Simulation setup ----------
  
  X_base <- model.matrix(cont_model$model, data = newdata_cont, type = "rhs", as.matrix = TRUE)
  
  beta_hat <- coef(cont_model$model)
  l <- length(beta_hat)
  Vc       <- cont_model$vcov_cluster[1:l, 1:l, drop = FALSE]
  
  stopifnot(identical(colnames(X_base), names(beta_hat)))
  
  # RHS-only linear predictor at beta_hat
  eta_lin_hat_base  <- as.numeric(X_base %*% beta_hat)
  # Full linear predictor (incl. FE) at beta_hat
  eta_full_hat_base <- as.numeric(predict(cont_model$model, newdata = newdata_cont, type = "link"))
  
  # fixed-effect offset
  fe_offset <- eta_full_hat_base - eta_lin_hat_base
  
  fam <- gaussian(link = "identity")
  
  set.seed(123)
  S <- 1000
  
  beta_draws <- rmvnorm_base(S, mean = beta_hat, sigma = Vc)  # S x p
  
  # ---------- Predictions (level) ----------
  
  pred_hat <- fam$linkinv(eta_full_hat_base)
  
  eta_lin_draws_base  <- X_base %*% t(beta_draws)
  eta_full_draws_base <- sweep(eta_lin_draws_base, 1, fe_offset, "+")
  mu_pred_draws       <- fam$linkinv(eta_full_draws_base)  # n x S
  
  pred_df <- newdata_cont %>%
    transmute(
      favorability,
      level,
      pred = as.numeric(pred_hat)
    )
  
  # ---------- Marginal effects via finite differences ----------
  
  h <- 0.01
  
  nd_plus  <- newdata_cont
  nd_minus <- newdata_cont
  
  nd_plus$favorability  <- nd_plus$favorability  + h
  nd_minus$favorability <- nd_minus$favorability - h
  
  nd_plus$favorability_sq  <- nd_plus$favorability^2
  nd_minus$favorability_sq <- nd_minus$favorability^2
  
  X_plus  <- model.matrix(cont_model$model, data = nd_plus,  type = "rhs", as.matrix = TRUE)
  X_minus <- model.matrix(cont_model$model, data = nd_minus, type = "rhs", as.matrix = TRUE)
  
  stopifnot(identical(colnames(X_plus),  colnames(X_base)))
  stopifnot(identical(colnames(X_minus), colnames(X_base)))
  
  eta_lin_plus_draws  <- X_plus  %*% t(beta_draws)
  eta_lin_minus_draws <- X_minus %*% t(beta_draws)
  
  eta_full_plus_draws  <- sweep(eta_lin_plus_draws,  1, fe_offset, "+")
  eta_full_minus_draws <- sweep(eta_lin_minus_draws, 1, fe_offset, "+")
  
  mu_plus_draws  <- fam$linkinv(eta_full_plus_draws)
  mu_minus_draws <- fam$linkinv(eta_full_minus_draws)
  
  me_draws <- (mu_plus_draws - mu_minus_draws) / (2 * h)  # n x S
  
  # point estimate ME
  eta_lin_plus_hat   <- as.numeric(X_plus  %*% beta_hat)
  eta_lin_minus_hat  <- as.numeric(X_minus %*% beta_hat)
  eta_full_plus_hat  <- eta_lin_plus_hat  + fe_offset
  eta_full_minus_hat <- eta_lin_minus_hat + fe_offset
  
  mu_plus_hat  <- fam$linkinv(eta_full_plus_hat)
  mu_minus_hat <- fam$linkinv(eta_full_minus_hat)
  
  me_hat <- (mu_plus_hat - mu_minus_hat) / (2 * h)
  
  me_ci_df <- newdata_cont %>%
    transmute(
      favorability,
      level,
      me_hat = as.numeric(me_hat),
      me_lo  = apply(me_draws, 1, quantile, probs = 0.05),
      me_hi  = apply(me_draws, 1, quantile, probs = 0.95)
    )
  
  me_ci_df$level <- factor(me_ci_df$level, levels = level_levels)
  
  # ---------- Peak-location CIs ----------
  
  peak_list <- lapply(level_levels, function(lv) {
    idx   <- which(newdata_cont$level == lv)
    fav_g <- newdata_cont$favorability[idx]
    mu_hat_g <- pred_hat[idx]
    
    peak_hat <- fav_g[which.max(mu_hat_g)]
    
    mu_draws_g <- mu_pred_draws[idx, , drop = FALSE]
    peak_sim   <- apply(mu_draws_g, 2, function(col) fav_g[which.max(col)])
    
    ci_peak <- quantile(peak_sim, probs = c(0.05, 0.95))
    
    data.frame(
      level   = lv,
      peak_hat = peak_hat,
      peak_lo  = as.numeric(ci_peak[1]),
      peak_hi  = as.numeric(ci_peak[2])
    )
  })
  
  peak_df <- bind_rows(peak_list)
  peak_df$level <- factor(peak_df$level, levels = level_levels)
  
  # ---------- Build requested plots ----------
  
  # (1) Marginal effect plot with CI
  if ("me" %in% which) {
    me_plot <- ggplot(me_ci_df,
                      aes(
                        x = favorability,
                        y = me_hat,
                        color = level,
                        fill  = level
                      )) +
      geom_hline(yintercept = 0, linetype = "dotted", linewidth = 0.4) +
      geom_ribbon(
        aes(ymin = me_lo, ymax = me_hi),
        alpha = 0.18,
        color = NA
      ) +
      geom_line(linewidth = 1.05) +
      scale_color_manual(
        name   = "Partisan score",
        values = palette_cont
      ) +
      scale_fill_manual(
        name   = "Partisan score",
        values = palette_cont
      ) +
      labs(
        x = "Chance of Winning",
        y = "Marginal Effect of Chance of Winning on Contribution Probability"
      ) +
      theme_minimal(base_size = 12) +
      theme(
        text = element_text(family = "serif"),
        axis.title.y = element_text(size = 10),
        legend.position   = "bottom",
        panel.grid.minor  = element_blank(),
        plot.margin       = margin(t = 10, r = 5, b = 5, l = 5)
      )
    
    if (base) {
      FILE_NAME <- "Tobit_Partisan_Continuous_ME_CI_Base.png"
    } else {
      FILE_NAME <- "Tobit_Partisan_Continuous_ME_CI_Full.png"
    }
    
    ggsave(
      file.path(FIG_PATH, FILE_NAME),
      me_plot,
      width  = 11,
      height = 6.3
    )
  }
  
  # (2) Prediction plot (no CI)
  if ("pred" %in% which) {
    pred_df$level <- factor(pred_df$level, levels = level_levels)
    
    pred_plot <- ggplot(pred_df,
                        aes(
                          x = favorability,
                          y = pred,
                          color = level
                        )) +
      geom_line(linewidth = 1.05) +
      scale_color_manual(
        name   = "Partisan score",
        values = palette_cont
      ) +
      labs(
        x = "Chance of Winning",
        y = "Probability of Contribution"
      ) +
      theme_minimal(base_size = 12) +
      theme(
        text = element_text(family = "serif"),
        legend.position   = "bottom",
        panel.grid.minor  = element_blank(),
        plot.margin       = margin(t = 10, r = 5, b = 5, l = 5)
      )
    
    if (base) {
      FILE_NAME <- "Tobit_Partisan_Continuous_Pred_Base.png"
    } else {
      FILE_NAME <- "Tobit_Partisan_Continuous_Pred_Full.png"
    }
    
    ggsave(
      file.path(FIG_PATH, FILE_NAME),
      pred_plot,
      width  = 8,
      height = 6.3
    )
  }
  
  # (3) Vertical peak-location CI plot
  if ("peak" %in% which) {
    peak_plot <- ggplot(peak_df,
                        aes(
                          x = level,
                          y = peak_hat,
                          color = level
                        )) +
      geom_pointrange(
        aes(ymin = peak_lo, ymax = peak_hi),
        size = 0.6,
        width = 0.15
      ) +
      scale_color_manual(
        name   = "Partisan score",
        values = palette_cont
      ) +
      labs(
        x = "Partisan Score",
        y = "Chance of Winning at Predicted Peak"
      ) +
      theme_minimal(base_size = 12) +
      theme(
        text = element_text(family = "serif"),
        axis.title.x = element_text(size = 10),
        legend.position   = "none",
        panel.grid.minor  = element_blank(),
        plot.margin       = margin(t = 10, r = 5, b = 5, l = 5)
      )
    
    if (base) {
      FILE_NAME <- "Tobit_Partisan_Continuous_Peak_CI_Base.png"
    } else {
      FILE_NAME <- "Tobit_Partisan_Continuous_Peak_CI_Full.png"
    }
    
    ggsave(
      file.path(FIG_PATH, FILE_NAME),
      peak_plot,
      width  = 2.5,
      height = 6.3
    )
  }
  
  rm_gc(cont_model, fav_seq, partisan_levels, base_row, newdata_cont,
        X_base, beta_hat, Vc, eta_lin_hat_base, eta_full_hat_base, fe_offset,
        beta_draws, eta_lin_draws_base, eta_full_draws_base, mu_pred_draws,
        nd_plus, nd_minus, X_plus, X_minus,
        eta_lin_plus_draws, eta_lin_minus_draws,
        eta_full_plus_draws, eta_full_minus_draws,
        mu_plus_draws, mu_minus_draws,
        eta_lin_plus_hat, eta_lin_minus_hat,
        eta_full_plus_hat, eta_full_minus_hat,
        mu_plus_hat, mu_minus_hat,
        me_draws, me_hat, me_ci_df,
        pred_hat, pred_df,
        peak_list, peak_df)
}

# =============================================================================
# 4) Main: run commands to generate plots
# =============================================================================

interaction_which <- c("me", "pred", "peak")
continuous_which <- c("me", "pred", "peak")

plot_interaction(interaction_which)
plot_interaction(interaction_which, base = FALSE)
plot_interaction_continuous(continuous_which)
plot_interaction_continuous(continuous_which, base = FALSE)

