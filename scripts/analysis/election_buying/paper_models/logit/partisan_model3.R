library(dplyr)
library(fixest)

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
  
  cand_data$subsec_GOP <- pmax(cand_data$subsec_partisan_score, 0)
  cand_data$subsec_DEM <- pmax(-cand_data$subsec_partisan_score, 0)
  cand_data$ind_GOP <- pmax(cand_data$ind_partisan_score, 0)
  cand_data$ind_DEM <- pmax(-cand_data$ind_partisan_score, 0)
  cand_data$ind_median_GOP <- pmax(cand_data$ind_partisan_median_score, 0)
  cand_data$ind_median_DEM <- pmax(-cand_data$ind_partisan_median_score, 0)
  cand_data$ind_avg_GOP <- pmax(cand_data$ind_partisan_avg_score, 0)
  cand_data$ind_avg_DEM <- pmax(-cand_data$ind_partisan_avg_score, 0)
  
  cand_data
}

write_coef_txt <- function(mod, txt_path) {
  con <- file(txt_path, open = "wt")
  on.exit(close(con))
  writeLines(capture.output(summary(mod)), con)
}

fit_save <- function(rhs, data, out_path,
                     cluster_fml = ~ cmte_id + candidate_id) {
  data <- droplevels(data)
  fmla <- as.formula(paste("contribute ~", rhs, "| state + year"))

  mod <- feglm(
    fmla,
    data    = data,
    family  = binomial(link = "logit"),
    cluster = cluster_fml
  )

  saveRDS(mod, out_path)
  write_coef_txt(mod, sub("\\.RDS$", "_coefficients.txt", out_path))
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
    "category",
    sep = " + "
  )
}

# --- Partisan bins (subsector) -----------------------------------------------

rhs_subsec_base <- function(fv) paste(
  base_controls(fv),
  "subsec_GOP", "subsec_DEM",
  paste0("(", fv, " + ", fv, "_sq) * subsec_GOP"),
  paste0("(", fv, " + ", fv, "_sq) * subsec_DEM"),
  sep = " + "
)

rhs_subsec_full <- function(fv) paste(
  base_controls(fv),
  "subsec_GOP", "subsec_DEM",
  paste0("(", fv, " + ", fv, "_sq) * incumbency"),
  paste0("(", fv, " + ", fv, "_sq) * subsec_GOP"),
  paste0("(", fv, " + ", fv, "_sq) * subsec_DEM"),
  "subsec_GOP * party", "subsec_GOP * incumbency",
  "subsec_DEM * party", "subsec_DEM * incumbency",
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

# --- Triple interaction: favorability x sector-alignment x candidate party --
# Added in response to a reviewer comment: the base/full specs above can't
# distinguish "GOP-sector firms are more risk-tolerant toward candidates of
# either party" from "GOP-sector firms specifically favor vulnerable
# Republicans" -- favorability x sector-alignment is estimated pooling both
# parties' candidates, with party only entering as a level control. These
# add the missing three-way term on top of the existing "full" spec (which
# already has every lower-order term) so only :party is new here.
# REVERT: delete these three functions and their MODEL_SPECS entries below
# to drop the triple-interaction check entirely.
rhs_subsec_full3 <- function(fv) paste(
  rhs_subsec_full(fv),
  paste0(fv, ":subsec_GOP:party"), paste0(fv, "_sq:subsec_GOP:party"),
  paste0(fv, ":subsec_DEM:party"), paste0(fv, "_sq:subsec_DEM:party"),
  sep = " + "
)

rhs_ind_full3 <- function(fv) paste(
  rhs_ind_full(fv),
  paste0(fv, ":ind_GOP:party"), paste0(fv, "_sq:ind_GOP:party"),
  paste0(fv, ":ind_DEM:party"), paste0(fv, "_sq:ind_DEM:party"),
  sep = " + "
)

rhs_indc_full3 <- function(fv) paste(
  rhs_indc_full(fv),
  paste0(fv, ":ind_partisan:party"), paste0(fv, "_sq:ind_partisan:party"),
  sep = " + "
)

build_model_specs <- function(fv, suffix) {
  sfx <- if (nzchar(suffix)) paste0("_", suffix) else ""
  list(
    list(name = paste0("extensive_partisan_subsector_int_base", sfx),
         rhs = rhs_subsec_base(fv), file = paste0("extensive_partisan_subsector_int_base", sfx, ".RDS")),
    list(name = paste0("extensive_partisan_subsector_int_full", sfx),
         rhs = rhs_subsec_full(fv), file = paste0("extensive_partisan_subsector_int_full", sfx, ".RDS")),
    list(name = paste0("extensive_partisan_industry_int_base", sfx),
         rhs = rhs_ind_base(fv), file = paste0("extensive_partisan_industry_int_base", sfx, ".RDS")),
    list(name = paste0("extensive_partisan_industry_int_full", sfx),
         rhs = rhs_ind_full(fv), file = paste0("extensive_partisan_industry_int_full", sfx, ".RDS")),
    list(name = paste0("extensive_partisan_all_firm_industry_category_int_base", sfx),
         rhs = rhs_indc_base(fv), file = paste0("extensive_partisan_all_firm_industry_category_int_base", sfx, ".RDS")),
    list(name = paste0("extensive_partisan_all_firm_industry_category_int_full", sfx),
         rhs = rhs_indc_full(fv), file = paste0("extensive_partisan_all_firm_industry_category_int_full", sfx, ".RDS")),
    # REVERT: remove these three to drop the triple-interaction check.
    list(name = paste0("extensive_partisan_subsector_int_full3", sfx),
         rhs = rhs_subsec_full3(fv), file = paste0("extensive_partisan_subsector_int_full3", sfx, ".RDS")),
    list(name = paste0("extensive_partisan_industry_int_full3", sfx),
         rhs = rhs_ind_full3(fv), file = paste0("extensive_partisan_industry_int_full3", sfx, ".RDS")),
    list(name = paste0("extensive_partisan_all_firm_industry_category_int_full3", sfx),
         rhs = rhs_indc_full3(fv), file = paste0("extensive_partisan_all_firm_industry_category_int_full3", sfx, ".RDS"))
  )
}

# Split-sample-by-party fits: the interpretable companion to the triple
# interaction above -- fit the same BASE spec separately for Republican- and
# Democrat-candidate observations, so the sector-alignment x favorability
# coefficient can be compared directly across the two subsamples instead of
# read off a three-way interaction coefficient. "party" (the split variable)
# is constant within each subset once split -- a single-level factor errors
# out in model.matrix() ("contrasts can be applied only to factors with 2 or
# more levels") rather than being silently dropped by fixest like a collinear
# continuous term would be, so it must be stripped from the RHS before
# fitting, not just left for fixest to notice.
# REVERT: delete this helper and its call in the main loop below.
fit_group_models <- function(rhs, data, group_var, level_map, out_prefix) {
  group_rhs <- gsub(paste0("\\s*\\+\\s*", group_var, "\\b(?!\\w)"), "", rhs, perl = TRUE)
  for (lev in names(level_map)) {
    label <- level_map[[lev]]
    subset_data <- data %>% filter(.data[[group_var]] == lev)
    if (nrow(subset_data) == 0L) next
    out_path <- paste0(out_prefix, "_", label, ".RDS")
    print(paste0("Fitting ", out_prefix, " (", label, ")"))
    fit_save(rhs = group_rhs, data = subset_data, out_path = out_path)
  }
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
    sfx <- if (nzchar(suffix)) paste0("_", suffix) else ""
    model_specs <- build_model_specs(fv, suffix)

    for (spec in model_specs) {
      print(paste0("Fitting ", spec$name))
      out_path <- paste0(PATH, "model/", dir_path, spec$file)
      fit_save(
        rhs      = spec$rhs,
        data     = cand_data,
        out_path = out_path
      )
    }

    # Split-sample-by-party check (see fit_group_models above).
    # REVERT: delete this block to drop the check.
    party_levels <- c("REPUBLICAN" = "republican_cands", "DEMOCRAT" = "democrat_cands")
    fit_group_models(rhs_subsec_base(fv), cand_data, "party", party_levels,
                      paste0(PATH, "model/", dir_path, "extensive_partisan_subsector_int_base", sfx))
    fit_group_models(rhs_ind_base(fv), cand_data, "party", party_levels,
                      paste0(PATH, "model/", dir_path, "extensive_partisan_industry_int_base", sfx))
    fit_group_models(rhs_indc_base(fv), cand_data, "party", party_levels,
                      paste0(PATH, "model/", dir_path, "extensive_partisan_all_firm_industry_category_int_base", sfx))
  }
}
