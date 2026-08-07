library(dplyr)
library(fixest)

# =============================================================================
# 0) Configuration
# =============================================================================
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
    "state + factor(year)",
    sep = " + "
  )
}

# --- Partisan bins (pre) -----------------------------------------------------

rhs_snp_base <- function(fv) paste(
  base_controls(fv),
  "singlename_partisan_pre",
  paste0("(", fv, " + ", fv, "_sq) * singlename_partisan_pre"),
  sep = " + "
)

rhs_snp_full <- function(fv) paste(
  base_controls(fv),
  "singlename_partisan_pre",
  paste0("(", fv, " + ", fv, "_sq) * incumbency"),
  paste0("(", fv, " + ", fv, "_sq) * singlename_partisan_pre"),
  "singlename_partisan_pre * party",
  "singlename_partisan_pre * incumbency",
  sep = " + "
)

# --- Continuous scores (pre) -------------------------------------------------

rhs_sncp_base <- function(fv) paste(
  base_controls(fv),
  "singlename_GOP_pre + singlename_DEM_pre",
  paste0("(", fv, " + ", fv, "_sq) * singlename_GOP_pre"),
  paste0("(", fv, " + ", fv, "_sq) * singlename_DEM_pre"),
  sep = " + "
)

rhs_sncp_full <- function(fv) paste(
  base_controls(fv),
  "singlename_GOP_pre + singlename_DEM_pre",
  paste0("(", fv, " + ", fv, "_sq) * singlename_GOP_pre"),
  paste0("(", fv, " + ", fv, "_sq) * singlename_DEM_pre"),
  paste0("(", fv, " + ", fv, "_sq) * incumbency"),
  "singlename_GOP_pre * party + singlename_GOP_pre * incumbency",
  "singlename_DEM_pre * party + singlename_DEM_pre * incumbency",
  sep = " + "
)

# --- Triple interaction: favorability x singlename partisanship x party ----
# This is the measure that actually feeds the paper's Table 1-3 (continuous
# hinge-split GOP/DEM scores + categorical bins) -- added here, not in
# partisan_model3.R's subsector/industry measures, per correction. Same
# reviewer comment as before: favorability x singlename-partisanship is
# estimated pooling both parties' candidates, with party only a level
# control, so it can't distinguish "these firms are more risk-tolerant
# toward candidates of either party" from "these firms specifically favor
# vulnerable candidates of their own party." Adds the missing three-way term
# on top of the existing "full" spec (already has every lower-order term).
# REVERT: delete these two functions and their MODEL_SPECS entries below to
# drop the triple-interaction check entirely.
rhs_snp_full3 <- function(fv) paste(
  rhs_snp_full(fv),
  paste0(fv, ":singlename_partisan_pre:party"), paste0(fv, "_sq:singlename_partisan_pre:party"),
  sep = " + "
)

rhs_sncp_full3 <- function(fv) paste(
  rhs_sncp_full(fv),
  paste0(fv, ":singlename_GOP_pre:party"), paste0(fv, "_sq:singlename_GOP_pre:party"),
  paste0(fv, ":singlename_DEM_pre:party"), paste0(fv, "_sq:singlename_DEM_pre:party"),
  sep = " + "
)

build_model_specs <- function(fv, suffix) {
  sfx <- if (nzchar(suffix)) paste0("_", suffix) else ""
  list(
    list(name = paste0("extensive_partisan_singlename_pre_int_base", sfx),
         rhs = rhs_snp_base(fv), file = paste0("extensive_partisan_singlename_pre_int_base", sfx, ".RDS")),
    list(name = paste0("extensive_partisan_singlename_pre_int_full", sfx),
         rhs = rhs_snp_full(fv), file = paste0("extensive_partisan_singlename_pre_int_full", sfx, ".RDS")),
    list(name = paste0("extensive_partisan_singlename_score_pre_int_base", sfx),
         rhs = rhs_sncp_base(fv), file = paste0("extensive_partisan_singlename_score_pre_int_base", sfx, ".RDS")),
    list(name = paste0("extensive_partisan_singlename_score_pre_int_full", sfx),
         rhs = rhs_sncp_full(fv), file = paste0("extensive_partisan_singlename_score_pre_int_full", sfx, ".RDS")),
    # REVERT: remove these two to drop the triple-interaction check.
    list(name = paste0("extensive_partisan_singlename_pre_int_full3", sfx),
         rhs = rhs_snp_full3(fv), file = paste0("extensive_partisan_singlename_pre_int_full3", sfx, ".RDS")),
    list(name = paste0("extensive_partisan_singlename_score_pre_int_full3", sfx),
         rhs = rhs_sncp_full3(fv), file = paste0("extensive_partisan_singlename_score_pre_int_full3", sfx, ".RDS"))
  )
}

# Split-sample-by-party fits: the interpretable companion to the triple
# interaction above -- fit the BASE spec separately for Republican- and
# Democrat-candidate observations. "party" is constant within each subset
# once split, so fixest will drop it from that fit with a NOTE -- expected,
# not an error.
# REVERT: delete this helper and its call in the main loop below.
fit_group_models <- function(rhs, data, group_var, level_map, out_prefix) {
  for (lev in names(level_map)) {
    label <- level_map[[lev]]
    subset_data <- data %>% filter(.data[[group_var]] == lev)
    if (nrow(subset_data) == 0L) next
    out_path <- paste0(out_prefix, "_", label, ".RDS")
    print(paste0("Fitting ", out_prefix, " (", label, ")"))
    fit_save(rhs = rhs, data = subset_data, out_path = out_path)
  }
}

# =============================================================================
# 3) Main loop
# =============================================================================

for (i in seq_along(election_dir)) {
  data_path <- election_data[i]
  dir_path  <- election_dir[i]

  cand_data <- readRDS(paste0(DATA_PATH, "cand_model_data", data_path, ".RDS"))
  cand_data <- prep_cand_data(cand_data)

  dir.create(paste0(MODEL_PATH, dir_path),
             showWarnings = FALSE, recursive = TRUE)

  # REVERT: loop over just "favorability" to restore original behavior.
  for (fv_name in names(FAVORABILITY_VARS)) {
    fv <- FAVORABILITY_VARS[[fv_name]]
    suffix <- if (fv_name == "favorability") "" else fv_name
    sfx <- if (nzchar(suffix)) paste0("_", suffix) else ""
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

    # Split-sample-by-party check (see fit_group_models above).
    # REVERT: delete this block to drop the check.
    party_levels <- c("REPUBLICAN" = "republican_cands", "DEMOCRAT" = "democrat_cands")
    fit_group_models(rhs_snp_base(fv), cand_data, "party", party_levels,
                      paste0(MODEL_PATH, dir_path, "extensive_partisan_singlename_pre_int_base", sfx))
    fit_group_models(rhs_sncp_base(fv), cand_data, "party", party_levels,
                      paste0(MODEL_PATH, dir_path, "extensive_partisan_singlename_score_pre_int_base", sfx))
  }
}
