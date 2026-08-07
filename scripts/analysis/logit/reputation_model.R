library(dplyr)
library(fixest)

data_root_env <- Sys.getenv("CAMPAIGNFINANCE_DATA_ROOT", unset = "")
if (!nzchar(data_root_env)) {
    stop(
        "CAMPAIGNFINANCE_DATA_ROOT is not set. Point it at the campaign-finance-data folder ",
        "(contains data/ and outputs/), e.g. Sys.setenv(CAMPAIGNFINANCE_DATA_ROOT = ",
        "'C:/Users/<you>/Dropbox/campaign-finance-data')."
    )
}
DATA_ROOT <- normalizePath(data_root_env, mustWork = TRUE)
MODEL_PATH <- paste0(file.path(DATA_ROOT, "outputs", "models"), "/")
DATA_PATH <- paste0(file.path(DATA_ROOT, "data", "processed", "modeling"), "/")
# REVERT: to fit only the pre-election-year sample as before, set
# election_data <- c("_election_year") and election_dir <- c("election/").
# Both samples now have real date-matched favorability columns (see
# HouseCandData.R and docs/redistricting-timing-fix-log.md).
election_data <- c("", "_election_year")
election_dir <- c("all/", "election/")

# =============================================================================
# 1) Helpers
# =============================================================================

prep_cand_data <- function(cand_data) {
  cand_data$give_partisan <- factor(cand_data$give_partisan,
                                    levels = c("other", "Hedged", "GOP", "DEM"))
  cand_data$etf_partisan <- factor(cand_data$etf_partisan,
                                   levels = c("Hedged", "DEM", "GOP"))
  cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre,
                                              levels = c("Other", "Hedged", "GOP", "DEM"))
  cand_data$singlename_partisan_all <- factor(cand_data$singlename_partisan_all,
                                              levels = c("Other", "Hedged", "GOP", "DEM"))
  
  cand_data$etf_GOP_all <- pmax(cand_data$etf_score_all, 0)
  cand_data$etf_DEM_all <- pmax(-cand_data$etf_score_all, 0)
  cand_data$etf_GOP_pre <- pmax(cand_data$etf_score_pre, 0)
  cand_data$etf_DEM_pre <- pmax(-cand_data$etf_score_pre, 0)
  
  cand_data$singlename_GOP_all <- pmax(cand_data$singlename_score_all, 0)
  cand_data$singlename_DEM_all <- pmax(-cand_data$singlename_score_all, 0)
  cand_data$singlename_GOP_pre <- pmax(cand_data$singlename_score_pre, 0)
  cand_data$singlename_DEM_pre <- pmax(-cand_data$singlename_score_pre, 0)
  
  cand_data
}

fit_save <- function(rhs, data, out_path,
                     cluster_fml = ~ cmte_id + candidate_id) {
  data <- droplevels(data)
  fmla <- as.formula(paste("contribute ~", rhs))

  mod <- feglm(
    fmla,
    data    = data,
    family  = binomial(link = "logit"),
    cluster = cluster_fml
  )

  saveRDS(mod, out_path)
  invisible(mod)
}

# =============================================================================
# 2) Model specifications
# =============================================================================
# REVERT: to restore the original single-cycle-mean-favorability behavior,
# set FAVORABILITY_VARS <- c(favorability = "favorability") below. See
# docs/redistricting-timing-fix-log.md for the rationale behind the other two.
FAVORABILITY_VARS <- c(
  favorability  = "favorability",
  entry         = "favorability_entry",
  election_day  = "favorability_election_day"
)

base_controls <- function(fv) {
  paste(
    fv, paste0(fv, "_sq"),
    "special + private + foreign",
    "same_state + log(firm_cash)",
    "party + incumbency",
    "category + state + factor(year)",
    sep = " + "
  )
}

# Private x favorability / incumbency / party interaction models
rhs_private_base <- function(fv) paste(
  base_controls(fv),
  paste0("(", fv, " + ", fv, "_sq) * private"),
  sep = " + "
)

rhs_private_full <- function(fv) paste(
  base_controls(fv),
  paste0("(", fv, " + ", fv, "_sq) * incumbency"),
  paste0("(", fv, " + ", fv, "_sq) * private"),
  "private * incumbency",
  "private * party",
  sep = " + "
)

# Consumer-facing x favorability / incumbency / party interaction models
rhs_consumer_base <- function(fv) paste(
  base_controls(fv),
  "consumer_facing",
  paste0("(", fv, " + ", fv, "_sq) * consumer_facing"),
  sep = " + "
)

rhs_consumer_full <- function(fv) paste(
  base_controls(fv),
  "consumer_facing",
  paste0("(", fv, " + ", fv, "_sq) * incumbency"),
  paste0("(", fv, " + ", fv, "_sq) * consumer_facing"),
  "consumer_facing * party",
  "consumer_facing * incumbency",
  sep = " + "
)

build_model_specs <- function(fv, suffix) {
  sfx <- if (nzchar(suffix)) paste0("_", suffix) else ""
  list(
    list(name = paste0("extensive_private_int_base", sfx),
         rhs = rhs_private_base(fv), file = paste0("extensive_private_int_base", sfx, ".RDS")),
    list(name = paste0("extensive_private_int_full", sfx),
         rhs = rhs_private_full(fv), file = paste0("extensive_private_int_full", sfx, ".RDS")),
    list(name = paste0("extensive_consumer_int_base", sfx),
         rhs = rhs_consumer_base(fv), file = paste0("extensive_consumer_int_base", sfx, ".RDS")),
    list(name = paste0("extensive_consumer_int_full", sfx),
         rhs = rhs_consumer_full(fv), file = paste0("extensive_consumer_int_full", sfx, ".RDS"))
  )
}

# =============================================================================
# 3) Main loop
# =============================================================================

for (i in seq_along(election_dir)) {
  data_path <- election_data[i]
  dir_path  <- election_dir[i]

  # Load + prep data
  cand_data <- readRDS(paste0(DATA_PATH, "cand_model_data", data_path, ".RDS"))
  cand_data <- prep_cand_data(cand_data)

  # Ensure output directory exists
  dir.create(paste0(MODEL_PATH, dir_path), showWarnings = FALSE, recursive = TRUE)

  # Fit all interaction models for this dataset variant, once per
  # favorability construction (REVERT: loop over just "favorability" to
  # restore original behavior).
  for (fv_name in names(FAVORABILITY_VARS)) {
    fv <- FAVORABILITY_VARS[[fv_name]]
    suffix <- if (fv_name == "favorability") "" else fv_name
    model_specs <- build_model_specs(fv, suffix)

    for (spec in model_specs) {
      print(paste0("Fitting ", spec$name))
      out_path <- paste0(MODEL_PATH, dir_path, spec$file)
      fit_save(
        rhs      = spec$rhs,
        data     = cand_data,
        out_path = out_path
      )
    }
  }
}

