library(dplyr)
library(fixest)

PATH <- "/htaa/hhe/projects/election_buying/"

# state and year are fixed effects in every fixest (feglm) spec below rather
# than plain RHS dummies -- build_formula() splits them into the fixest FE
# slot ("| state + year") instead of the main formula.
build_formula <- function(data,
                          use_spline = FALSE,
                          favorability_var = "favorability",
                          drop_if_constant = c("category"),
                          drop = c()) {
  # Base RHS terms (no splines). favorability_var lets the same formula
  # builder target the cycle-mean baseline ("favorability", the original
  # construction) or either date-matched variant ("favorability_entry",
  # "favorability_election_day") -- see docs/redistricting-timing-fix-log.md.
  # Splines aren't rebuilt per-variant, so use_spline stays tied to the
  # original cycle-mean spline basis.
  base_terms <- c(
    favorability_var, paste0(favorability_var, "_sq"),
    "special", "private", "foreign",
    "same_state", "log(firm_cash)",
    "party", "incumbency",
    "category"
  )

  # If using splines, replace favorability terms
  if (use_spline) {
    base_terms <- c(
      "spline1", "spline2", "spline3", "spline4",
      "special", "private", "foreign",
      "same_state", "log(firm_cash)",
      "party", "incumbency",
      "category"
    )
  }

  fe_terms <- c("state", "year")

  for (v in drop_if_constant) {
    if (v %in% names(data)) {
      if (dplyr::n_distinct(data[[v]]) <= 1L) {
        base_terms <- setdiff(base_terms, v)
        fe_terms <- setdiff(fe_terms, v)
      }
    }
  }

  # drop may still reference the old RHS spellings ("state", "factor(year)");
  # map factor(year) -> year so it also removes the FE term.
  drop_fe <- gsub("factor\\(year\\)", "year", intersect(drop, c("state", "factor(year)")))
  fe_terms <- setdiff(fe_terms, drop_fe)
  base_terms <- setdiff(base_terms, drop)

  rhs <- paste(base_terms, collapse = " + ")
  if (length(fe_terms) > 0L) {
    rhs <- paste0(rhs, " | ", paste(fe_terms, collapse = " + "))
  }

  as.formula(paste("contribute ~", rhs))
}

# Fit a single feglm model on data
fit_logit <- function(data, use_spline = FALSE, favorability_var = "favorability", drop = c()) {
  data <- droplevels(data)
  fmla <- build_formula(data, use_spline = use_spline, favorability_var = favorability_var, drop = drop)
  feglm(
    fmla,
    data = data,
    family = binomial(link = "logit"),
    cluster = ~ cmte_id + candidate_id
  )
}

# Fit models for a grouping variable and a named vector of levels -> labels
fit_group_models <- function(data, group_var, level_map, use_spline = FALSE, favorability_var = "favorability", drop = c()) {
  out <- list()
  for (lev in names(level_map)) {
    label <- level_map[[lev]]
    subset_data <- data %>% filter(.data[[group_var]] == lev)
    if (nrow(subset_data) == 0L) {
      out[[label]] <- NULL
    } else {
      out[[label]] <- fit_logit(subset_data, use_spline = use_spline, favorability_var = favorability_var, drop = drop)
    }
  }
  out
}

# Write model coefficients to a plain-text file alongside the RDS. Handles
# both a single fixest model and a named list of fixest models (as produced
# by fit_group_models()).
write_coef_txt <- function(mod, txt_path) {
  con <- file(txt_path, open = "wt")
  on.exit(close(con))
  if (inherits(mod, "fixest")) {
    writeLines(capture.output(summary(mod)), con)
  } else if (is.list(mod)) {
    for (nm in names(mod)) {
      writeLines(paste0("=== ", nm, " ==="), con)
      writeLines(capture.output(summary(mod[[nm]])), con)
      writeLines("", con)
    }
  }
}

save_model <- function(mod, out_path) {
  saveRDS(mod, out_path)
  write_coef_txt(mod, sub("\\.RDS$", "_coefficients.txt", out_path))
}

# Both samples now have real date-matched favorability columns (see
# HouseCandData.R and docs/redistricting-timing-fix-log.md), so both loop
# arms fit all three variants.
election_data <- c("", "_election_year")
election_dir <- c("all/", "election/")

for (i in seq_along(election_dir)) {
  data_path <- election_data[i]
  dir_path <- election_dir[i]

  cand_data <- readRDS(paste0(PATH, "cand_model_data", data_path, ".RDS"))

  dir.create(paste0(PATH, "model/", dir_path), showWarnings = FALSE, recursive = TRUE)

  # Factor setup
  cand_data$give_partisan <- factor(
    cand_data$give_partisan,
    levels = c("other", "Hedged", "GOP", "DEM")
  )
  cand_data$etf_partisan <- factor(
    cand_data$etf_partisan,
    levels = c("Other", "DEM", "GOP")
  )
  cand_data$singlename_partisan_pre <- factor(
    cand_data$singlename_partisan_pre,
    levels = c("Other", "GOP", "DEM")
  )
  cand_data$singlename_partisan_all <- factor(
    cand_data$singlename_partisan_all,
    levels = c("Other", "GOP", "DEM")
  )
  
  # 1. Baseline model ---------------------------------------------------------
  print("Fitting Baseline Model")
  modsimple <- fit_logit(cand_data, use_spline = FALSE, drop = c("special", "private", "foreign","same_state", "log(firm_cash)","party", "incumbency", "category", "state", "factor(year)"))
  modbase   <- fit_logit(cand_data, use_spline = FALSE)
  print("Fitting Baseline Spline Model")
  modspline <- fit_logit(cand_data, use_spline = TRUE)

  save_model(modsimple,
             paste0(PATH, "model/", dir_path, "extensive_simple.RDS"))
  save_model(modbase,
             paste0(PATH, "model/", dir_path, "extensive_baseline.RDS"))
  save_model(modspline,
             paste0(PATH, "model/", dir_path, "extensive_baseline_spline.RDS"))

  # 1b. Date-matched baseline variants (mutual robustness pair) --------------
  # entry-date: contributors anchored to their first contribution, non-
  # contributors to the Election-Day-nearest rating. election-day: everyone
  # anchored to the Election-Day-nearest rating. See docs/redistricting-
  # timing-fix-log.md for the full rationale.
  # REVERT: delete this block to restore the original single-favorability behavior.
  print("Fitting Baseline Model (entry-date favorability)")
  modbase_entry <- fit_logit(cand_data, use_spline = FALSE, favorability_var = "favorability_entry")
  print("Fitting Baseline Model (election-day favorability)")
  modbase_election_day <- fit_logit(cand_data, use_spline = FALSE, favorability_var = "favorability_election_day")

  save_model(modbase_entry,
             paste0(PATH, "model/", dir_path, "extensive_baseline_entry.RDS"))
  save_model(modbase_election_day,
             paste0(PATH, "model/", dir_path, "extensive_baseline_election_day.RDS"))

  # 2. Consumer-facing subsets -----------------------------------------------
  print("Fitting Consumer-Facing Subsets")
  consumer_models <- fit_group_models(
    cand_data,
    group_var = "consumer_facing",
    level_map = c("0" = "nonconsumer", "1" = "consumer"),
    use_spline = FALSE
  )
  save_model(consumer_models,
             paste0(PATH, "model/", dir_path, "extensive_consumer.RDS"))

  # 3. Public / private subsets ----------------------------------------------
  print("Fitting Public/Private Subsets")
  private_models <- fit_group_models(
    cand_data,
    group_var = "private",
    level_map = c("0" = "public", "1" = "private"),
    use_spline = FALSE
  )
  save_model(private_models,
             paste0(PATH, "model/", dir_path, "extensive_private.RDS"))

  # 4. Giving-pattern partisanship (give_partisan) ---------------------------
  print("Fitting Giving-Pattern Subsets")
  give_models <- fit_group_models(
    cand_data,
    group_var = "give_partisan",
    level_map = c(
      "Hedged" = "hedged",
      "GOP"    = "GOP",
      "DEM"    = "DEM",
      "other"  = "other"
    ),
    use_spline = FALSE
  )
  save_model(give_models,
             paste0(PATH, "model/", dir_path, "extensive_partisan_give.RDS"))

  # 5. Market reaction (ETF) partisanship ------------------------------------
  print("Fitting Market Reaction ETF Subsets")
  etf_models <- fit_group_models(
    cand_data,
    group_var = "etf_partisan",
    level_map = c(
      "Other"  = "other",
      "GOP"    = "GOP",
      "DEM"    = "DEM"
    ),
    use_spline = FALSE,
    drop = c("category")
  )
  save_model(etf_models,
             paste0(PATH, "model/", dir_path, "extensive_partisan_etf.RDS"))

  # 6. Single-name partisanship (pre-2010) -----------------------------------
  print("Fitting Single Name (Pre-2010) Subsets")
  singlename_pre_models <- fit_group_models(
    cand_data,
    group_var = "singlename_partisan_pre",
    level_map = c(
      "GOP"    = "GOP",
      "DEM"    = "DEM",
      "Other"  = "other"
    ),
    use_spline = FALSE,
    drop = c("category", "factor(year)")
  )
  save_model(singlename_pre_models,
             paste0(PATH, "model/", dir_path,
                    "extensive_partisan_singlename_pre.RDS"))
}
 
