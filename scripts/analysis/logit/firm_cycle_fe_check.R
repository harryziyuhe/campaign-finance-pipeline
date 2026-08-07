#
# Firm x cycle fixed-effects robustness check for the baseline inverse-U
# (Hypothesis 1 only -- NOT the sector-alignment heterogeneity results,
# since sector alignment is firm-time-invariant and would be perfectly
# collinear with firm, let alone firm x cycle, fixed effects).
#
# Motivation (reviewer comment on theory-data aggregation, discussed in
# conversation -- not yet written into docs/redistricting-timing-fix-log.md
# as of this script, see that file for the fuller writeup):
#   The theory (Appendix A) is a per-candidate, independent decision rule --
#   no budget constraint, no portfolio. Real firms have a finite PAC budget
#   allocated across many candidates in a cycle. Standard constrained-
#   optimization logic says a budget-constrained firm's per-candidate choice
#   still satisfies an independent threshold rule, just with a shared
#   "shadow price" of the budget constraint added to every candidate's cost
#   *within that firm-cycle*. Firm x cycle fixed effects net exactly that
#   out. If the inverse-U survives, the per-candidate margin is real net of
#   whatever budget pressure a firm faced that cycle -- direct evidence
#   against "the peak is just where portfolio mass happens to sit."
#
# Firm-cycle-invariant controls (private, foreign, log(firm_cash), category,
# factor(year)) are dropped from the RHS: they'd be perfectly collinear with
# the firm x cycle FE and fixest would just auto-drop them with a NOTE --
# removed explicitly here for a cleaner formula and log output. "state" moves
# into the FE slot too (more efficient than a plain RHS factor); it varies at
# the candidate level so isn't absorbed by cmte_id^year.
#
# NOTE: cand_model_data.RDS has no column literally called "cycle" -- it's
# renamed to "year" early in HouseCandData.R and "cycle" itself isn't kept in
# the final select(). Use cmte_id^year, not cmte_id^cycle (the latter fails
# with "variable 'cycle' ... not in the data set").
#
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
election_data <- c("", "_election_year")
election_dir  <- c("all/", "election/")

FAVORABILITY_VARS <- c(
  favorability  = "favorability",
  entry         = "favorability_entry",
  election_day  = "favorability_election_day"
)

fit_firm_cycle_fe <- function(fv, data) {
  fmla <- as.formula(paste0(
    "contribute ~ ", fv, " + ", fv, "_sq + special + same_state + party + incumbency",
    " | cmte_id^year + state"
  ))
  feglm(
    fmla,
    data    = droplevels(data),
    family  = binomial(link = "logit"),
    cluster = ~ cmte_id + candidate_id
  )
}

for (i in seq_along(election_dir)) {
  data_path <- election_data[i]
  dir_path  <- election_dir[i]

  cand_data <- readRDS(paste0(DATA_PATH, "cand_model_data", data_path, ".RDS"))

  dir.create(paste0(MODEL_PATH, dir_path), showWarnings = FALSE, recursive = TRUE)

  for (fv_name in names(FAVORABILITY_VARS)) {
    fv <- FAVORABILITY_VARS[[fv_name]]
    sfx <- if (fv_name == "favorability") "" else paste0("_", fv_name)
    print(paste0("Fitting firm x cycle FE baseline (", fv_name, ")"))
    mod <- fit_firm_cycle_fe(fv, cand_data)
    saveRDS(mod, paste0(MODEL_PATH, dir_path, "extensive_baseline_firmcycleFE", sfx, ".RDS"))
  }
}
