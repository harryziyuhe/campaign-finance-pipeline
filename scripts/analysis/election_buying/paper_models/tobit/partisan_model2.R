library(dplyr)
library(survival)
library(sandwich)
library(lmtest)

# =============================================================================
# 0) Configuration
# =============================================================================
PATH <- "/htaa/hhe/projects/election_buying/"

# REVERT: to fit only the pre-election-year sample as before, set
# election_data <- c("_election_year") and election_dir <- c("election/").
# Both samples now have real date-matched favorability columns (see
# HouseCandData.R and docs/redistricting-timing-fix-log.md).
election_data <- c("", "_election_year")
election_dir  <- c("all/", "election/")

# =============================================================================
# 1) Helpers
# =============================================================================

prep_cand_data <- function(cand_data) {
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
  
  cand_data$ind_partisan <- factor(
    cand_data$ind_partisan,
    levels = c("OTHER", "GOP", "DEM")
  )
  
  cand_data$etf_GOP_all <- pmax(cand_data$etf_score_all, 0)
  cand_data$etf_DEM_all <- pmax(-cand_data$etf_score_all, 0)
  cand_data$etf_GOP_pre <- pmax(cand_data$etf_score_pre, 0)
  cand_data$etf_DEM_pre <- pmax(-cand_data$etf_score_pre, 0)
  
  cand_data$singlename_GOP_all <- pmax(cand_data$singlename_score_all, 0)
  cand_data$singlename_DEM_all <- pmax(-cand_data$singlename_score_all, 0)
  cand_data$singlename_GOP_pre <- pmax(cand_data$singlename_score_pre, 0)
  cand_data$singlename_DEM_pre <- pmax(-cand_data$singlename_score_pre, 0)
  
  cand_data$ind_GOP <- pmax(cand_data$ind_partisan_score, 0)
  cand_data$ind_DEM <- pmax(-cand_data$ind_partisan_score, 0)
  
  cand_data
}

fit_tobit_clustered <- function(rhs, data, out_path,
                                cluster_vars = c("cmte_id", "candidate_id")) {
  data <- data |>
    filter(contribute_limit > 0) |>
    mutate(
      y1 = case_when(
        contribute_amount <= 0 ~ NA_real_,
        contribute_amount >= contribute_limit ~ contribute_limit,
        TRUE ~ contribute_amount
      ),
      y2 = case_when(
        contribute_amount <= 0 ~ 0,
        contribute_amount >= contribute_limit ~ NA_real_,
        TRUE ~ contribute_amount
      )
    ) |>
    droplevels()
  
  fmla <- as.formula(
    paste0("Surv(y1, y2, type = 'interval2') ~ ", rhs)
  )
  
  mod <- survreg(
    fmla,
    data = data,
    dist = "gaussian"
  )
  
  v_cl <- sandwich::vcovCL(
    mod,
    cluster = data[, cluster_vars, drop = FALSE]
  )

  saveRDS(
    list(
      model = mod,
      vcov_cluster = v_cl,
      cluster_vars = cluster_vars
    ),
    out_path
  )

  coef_path <- sub("\\.RDS$", "_coefficients.txt", out_path)
  con <- file(coef_path, open = "wt")
  writeLines(capture.output(lmtest::coeftest(mod, vcov. = v_cl)), con)
  close(con)

  invisible(list(model = mod, vcov_cluster = v_cl))
}

# =============================================================================
# 2) Model specifications
# =============================================================================
# REVERT: to restore the original single-cycle-mean-favorability behavior,
# set FAVORABILITY_VARS <- c(favorability = "favorability") below. The Tobit
# scripts use favorability_weighted (contribution-amount-weighted average
# across a dyad's events) rather than the entry/election-day pair, since this
# is the intensive-margin model -- see docs/redistricting-timing-fix-log.md.
FAVORABILITY_VARS <- c(
  favorability = "favorability",
  weighted     = "favorability_weighted"
)

base_controls <- function(fv) {
  paste(
    fv, paste0(fv, "_sq"),
    "special + private + foreign",
    "same_state + log(firm_cash)",
    "party + incumbency",
    "state + factor(year)",
    sep = " + "
  )
}

# --- Giving pattern partisanship (give_partisan) -----------------------------

rhs_give_base <- function(fv) paste(
  base_controls(fv),
  "give_partisan",
  paste0("(", fv, " + ", fv, "_sq) * give_partisan"),
  sep = " + "
)

rhs_give_full <- function(fv) paste(
  base_controls(fv),
  "give_partisan",
  paste0("(", fv, " + ", fv, "_sq) * incumbency"),
  paste0("(", fv, " + ", fv, "_sq) * give_partisan"),
  "give_partisan * party",
  "give_partisan * incumbency",
  sep = " + "
)

# --- Partisan bins (industry) -----------------------------------------------

rhs_ind_base <- function(fv) paste(
  base_controls(fv),
  "ind_GOP", "ind_DEM",
  paste0("(", fv, " + ", fv, "_sq) * ind_GOP"),
  paste0("(", fv, " + ", fv, "_sq) * ind_DEM"),
  sep = " + "
)

rhs_ind_full <- function(fv) paste(
  base_controls(fv),
  "ind_GOP", "ind_DEM",
  paste0("(", fv, " + ", fv, "_sq) * incumbency"),
  paste0("(", fv, " + ", fv, "_sq) * ind_GOP"),
  paste0("(", fv, " + ", fv, "_sq) * ind_DEM"),
  "ind_GOP * party", "ind_GOP * incumbency",
  "ind_DEM * party", "ind_DEM * incumbency",
  sep = " + "
)

# --- Partisan bins (industry all firms class) --------------------------------

rhs_indc_base <- function(fv) paste(
  base_controls(fv),
  "ind_partisan",
  paste0("(", fv, " + ", fv, "_sq) * ind_partisan"),
  sep = " + "
)

rhs_indc_full <- function(fv) paste(
  base_controls(fv),
  "ind_partisan",
  paste0("(", fv, " + ", fv, "_sq) * incumbency"),
  paste0("(", fv, " + ", fv, "_sq) * ind_partisan"),
  "ind_partisan * party", "ind_partisan * incumbency",
  sep = " + "
)

build_model_specs <- function(fv, suffix) {
  sfx <- if (nzchar(suffix)) paste0("_", suffix) else ""
  list(
    list(name = paste0("tobit_partisan_give_int_base", sfx),
         rhs = rhs_give_base(fv), file = paste0("tobit_partisan_give_int_base", sfx, ".RDS")),
    list(name = paste0("tobit_partisan_give_int_full", sfx),
         rhs = rhs_give_full(fv), file = paste0("tobit_partisan_give_int_full", sfx, ".RDS")),
    list(name = paste0("tobit_partisan_industry_int_base", sfx),
         rhs = rhs_ind_base(fv), file = paste0("tobit_partisan_industry_int_base", sfx, ".RDS")),
    list(name = paste0("tobit_partisan_industry_int_full", sfx),
         rhs = rhs_ind_full(fv), file = paste0("tobit_partisan_industry_int_full", sfx, ".RDS")),
    list(name = paste0("tobit_partisan_all_firm_industry_category_int_base", sfx),
         rhs = rhs_indc_base(fv), file = paste0("tobit_partisan_all_firm_industry_category_int_base", sfx, ".RDS")),
    list(name = paste0("tobit_partisan_all_firm_industry_category_int_full", sfx),
         rhs = rhs_indc_full(fv), file = paste0("tobit_partisan_all_firm_industry_category_int_full", sfx, ".RDS"))
  )
}

# =============================================================================
# 3) Main loop
# =============================================================================

for (i in seq_along(election_dir)) {
  data_path <- election_data[i]
  dir_path  <- election_dir[i]

  cand_data <- readRDS(paste0(PATH, "cand_model_data", data_path, ".RDS"))
  cand_data <- prep_cand_data(cand_data)

  dir.create(paste0(PATH, "model/", dir_path),
             showWarnings = FALSE, recursive = TRUE)

  # REVERT: loop over just "favorability" to restore original behavior.
  for (fv_name in names(FAVORABILITY_VARS)) {
    fv <- FAVORABILITY_VARS[[fv_name]]
    suffix <- if (fv_name == "favorability") "" else fv_name
    model_specs <- build_model_specs(fv, suffix)

    for (spec in model_specs) {
      print(paste0("Fitting ", spec$name))
      out_path <- paste0(PATH, "model/", dir_path, spec$file)
      fit_tobit_clustered(
        rhs      = spec$rhs,
        data     = cand_data,
        out_path = out_path
      )
    }
  }
}
