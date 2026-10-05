library(dplyr)
library(survival)
library(sandwich)
library(lmtest)

# =============================================================================
# 0) Configuration
# =============================================================================
# Tobit (intensive-margin) counterpart of
# scripts/logit/singlename_triple_interaction.R -- see that file for the
# full rationale. BASE adds favorability x measure x co-partisanship (a
# three-way "*" expansion); FULL adds favorability x measure, favorability x
# incumbency, favorability x measure x co-partisanship, and measure x
# incumbency x co-partisanship (NOT interacted with favorability), with
# incumbent as the releveled reference category. Same RHS builders; survreg
# has no fixest-style FE mechanism, so state/year stay as plain RHS terms
# here (as in the other scripts/tobit/*.R files) instead of being split into
# a fixed-effects slot.
PATH <- "/htaa/hhe/projects/election_buying/"

election_data <- c("", "_election_year")
election_dir  <- c("all/", "election/")

# =============================================================================
# 1) Helpers
# =============================================================================

prep_cand_data <- function(cand_data) {
  cand_data$singlename_partisan_pre <- factor(
    cand_data$singlename_partisan_pre,
    levels = c("Other", "GOP", "DEM")
  )

  cand_data$singlename_GOP_pre <- pmax(cand_data$singlename_score_pre, 0)
  cand_data$singlename_DEM_pre <- pmax(-cand_data$singlename_score_pre, 0)

  # Co-partisanship: does the firm's revealed pre-period lean match this
  # candidate's own party? Firms with no clear lean ("Other", i.e. score 0)
  # count as not co-partisan.
  cand_data$co_partisan <- dplyr::case_when(
    cand_data$party == "REPUBLICAN" & cand_data$singlename_GOP_pre > 0 ~ 1,
    cand_data$party == "DEMOCRAT"   & cand_data$singlename_DEM_pre > 0 ~ 1,
    TRUE ~ 0
  )

  # incumbency is coded "C" (challenger) / "I" (incumbent) / "O" (open
  # seat); relevel so incumbent is the reference category instead of the
  # default alphabetical "C".
  cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))

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

  coef_path <- sub("\\.RDS$", "_coefficients.txt", out_path)
  con <- file(coef_path, open = "wt")
  writeLines(capture.output(lmtest::coeftest(mod, vcov. = v_cl)), con)
  close(con)

  invisible(list(model = mod, vcov_cluster = v_cl))
}

# =============================================================================
# 2) Model specifications
# =============================================================================
# The Tobit scripts use favorability_weighted (contribution-amount-weighted
# average across a dyad's events) rather than the entry/election-day pair,
# since this is the intensive-margin model -- see
# docs/redistricting-timing-fix-log.md and scripts/tobit/partisan_model1.R.
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

# FULL3 drops the plain `incumbency` term from base_controls() -- it enters
# instead via the (fv + fv_sq) * incumbency term below, which already
# supplies its main effect.
base_controls_no_incumbency <- function(fv) {
  gsub("\\s*\\+\\s*incumbency\\b(?!\\w)", "", base_controls(fv), perl = TRUE)
}

# --- Categorical measure (singlename_partisan_pre) x co-partisanship -------

# BASE3: favorability x singlename_partisan_pre x co_partisan (a full
# three-way "*" expansion, which also supplies the necessary lower-order
# terms: measure main effect, co_partisan main effect, fv:measure,
# fv:co_partisan, and measure:co_partisan). incumbency stays a plain control
# from base_controls() -- no incumbency-related interactions here, those are
# FULL-only.
rhs_snp_base3 <- function(fv) paste(
  base_controls(fv),
  paste0("(", fv, " + ", fv, "_sq) * singlename_partisan_pre * co_partisan"),
  sep = " + "
)

# FULL3: exactly four interactions --
#   (1) favorability x singlename_partisan_pre
#   (2) favorability x incumbency
#   (3) favorability x singlename_partisan_pre x co_partisan
#   (4) singlename_partisan_pre x incumbency x co_partisan (NOT interacted
#       with favorability -- this term captures whether the baseline
#       measure effect, not the favorability slope, differs by
#       incumbency/co-partisanship)
# (1)+(3) is one three-way "*" expansion; (2) is a plain two-way "*"; (4) is
# a separate three-way "*" among the non-favorability variables. Together
# these also supply the necessary lower-order terms (measure:co_partisan,
# measure:incumbency, incumbency:co_partisan, etc.) without introducing an
# fv:incumbency:co_partisan term.
rhs_snp_full3 <- function(fv) paste(
  base_controls_no_incumbency(fv),
  paste0("(", fv, " + ", fv, "_sq) * singlename_partisan_pre * co_partisan"),
  paste0("(", fv, " + ", fv, "_sq) * incumbency"),
  "singlename_partisan_pre * incumbency * co_partisan",
  sep = " + "
)

# --- Continuous measure (singlename_GOP_pre / singlename_DEM_pre) ----------

rhs_sncp_base3 <- function(fv) paste(
  base_controls(fv),
  paste0("(", fv, " + ", fv, "_sq) * singlename_GOP_pre * co_partisan"),
  paste0("(", fv, " + ", fv, "_sq) * singlename_DEM_pre * co_partisan"),
  sep = " + "
)

rhs_sncp_full3 <- function(fv) paste(
  base_controls_no_incumbency(fv),
  paste0("(", fv, " + ", fv, "_sq) * singlename_GOP_pre * co_partisan"),
  paste0("(", fv, " + ", fv, "_sq) * singlename_DEM_pre * co_partisan"),
  paste0("(", fv, " + ", fv, "_sq) * incumbency"),
  "singlename_GOP_pre * incumbency * co_partisan",
  "singlename_DEM_pre * incumbency * co_partisan",
  sep = " + "
)

build_model_specs <- function(fv, suffix) {
  sfx <- if (nzchar(suffix)) paste0("_", suffix) else ""
  list(
    list(name = paste0("tobit_partisan_singlename_pre_int_base3", sfx),
         rhs = rhs_snp_base3(fv), file = paste0("tobit_partisan_singlename_pre_int_base3", sfx, ".RDS")),
    list(name = paste0("tobit_partisan_singlename_pre_int_full3", sfx),
         rhs = rhs_snp_full3(fv), file = paste0("tobit_partisan_singlename_pre_int_full3", sfx, ".RDS")),
    list(name = paste0("tobit_partisan_singlename_score_pre_int_base3", sfx),
         rhs = rhs_sncp_base3(fv), file = paste0("tobit_partisan_singlename_score_pre_int_base3", sfx, ".RDS")),
    list(name = paste0("tobit_partisan_singlename_score_pre_int_full3", sfx),
         rhs = rhs_sncp_full3(fv), file = paste0("tobit_partisan_singlename_score_pre_int_full3", sfx, ".RDS"))
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
