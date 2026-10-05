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
         rhs = rhs_sncp_full(fv), file = paste0("extensive_partisan_singlename_score_pre_int_full", sfx, ".RDS"))
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
      fit_save(
        rhs      = spec$rhs,
        data     = cand_data,
        out_path = out_path
      )
    }
  }
}
