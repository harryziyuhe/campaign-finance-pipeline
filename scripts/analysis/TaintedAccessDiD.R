# Estimate baseline DiD models for the tainted-access scandal panels.
#
# Reads:
#   data/processed/tainted_access/firm_candidate_period_panel.parquet
#   data/processed/tainted_access/firm_period_panel.parquet
#
# Recommended panel-generation settings for the main paper specification:
#   period_unit   = "quarter"
#   period_length = 1
#   window_pre    = 8
#   window_post   = 8
#
# Rationale:
#   Quarterly periods are the best default because corporate PAC giving is lumpy.
#   Monthly panels will produce many zero cells and noisy timing. Election-cycle
#   panels are usually too coarse for checking event-time dynamics.
#
# Recommended robustness panels:
#   1. quarter, period_length = 2, window_pre = 8, window_post = 8
#      Half-year bins reduce noise and test whether results survive coarser timing.
#   2. quarter, period_length = 1, window_pre = 4, window_post = 4
#      Shorter one-year pre/post window, useful when candidate viability changes fast.
#   3. quarter, period_length = 1, window_pre = 12, window_post = 12
#      Wider three-year pre/post window, useful for pre-trend plots but more exposed
#      to unrelated campaign-cycle dynamics.
#
# The current smoke-test panels were generated with window_pre = 2,
# window_post = 2, and period_length in {1, 2}. They are useful for validating
# the workflow but too short for a persuasive pre-trend assessment.

library(arrow)
library(dplyr)
library(fixest)

PERIOD_UNIT <- "quarter"
PERIOD_LENGTH <- 1
REFERENCE_PERIOD <- -1

data_root_env <- Sys.getenv("CAMPAIGNFINANCE_DATA_ROOT", unset = "")
if (!nzchar(data_root_env)) {
    stop(
        "CAMPAIGNFINANCE_DATA_ROOT is not set. Point it at the campaign-finance-data folder ",
        "(contains data/ and outputs/), e.g. Sys.setenv(CAMPAIGNFINANCE_DATA_ROOT = ",
        "'C:/Users/<you>/Dropbox/campaign-finance-data')."
    )
}
DATA_ROOT <- normalizePath(data_root_env, mustWork = TRUE)
RELATIONSHIP_PANEL <- file.path(DATA_ROOT, "data", "processed", "tainted_access", "firm_candidate_period_panel.parquet")
FIRM_PANEL <- file.path(DATA_ROOT, "data", "processed", "tainted_access", "firm_period_panel.parquet")


# Relationship-level design: targeted withdrawal from scandal-tainted recipients.
relationship_data <- read_parquet(RELATIONSHIP_PANEL) |>
  filter(period_unit == PERIOD_UNIT) |>
  filter(period_length == PERIOD_LENGTH) |>
  filter(ever_pre_contributed_to_candidate == 1)

relationship_any <- feglm(
  any_contribution ~ did_treated_post |
    cmte_id + cand_id + relative_period,
  family = "binomial",
  #cluster = ~ scandal_id,
  data = relationship_data
)

relationship_amount <- feols(
  log1p(positive_amount) ~ did_treated_post |
    cmte_id + cand_id + relative_period,
  #cluster = ~ scandal_id + cmte_id,
  data = relationship_data
)

relationship_event_study <- feols(
  any_contribution ~ i(relative_period, treated_pair, ref = REFERENCE_PERIOD) |
    cmte_id + cand_id + relative_period,
  #cluster = ~ scandal_id + cmte_id,
  data = relationship_data
)


# Firm-level design: broader chilling, excluding the scandal-tainted candidate.
firm_data <- read_parquet(FIRM_PANEL) |>
  filter(period_unit == PERIOD_UNIT) |>
  filter(period_length == PERIOD_LENGTH) |>
  filter(pre_total_amount_all_candidates > 0)

firm_any_excluding_target <- feols(
  any_contribution_excluding_scandal_cand ~ did_exposed_post |
    scandal_id^cmte_id + scandal_id^relative_period,
  cluster = ~ scandal_id + cmte_id,
  data = firm_data
)

firm_amount_excluding_target <- feols(
  log1p(positive_amount_excluding_scandal_cand) ~ did_exposed_post |
    scandal_id^cmte_id + scandal_id^relative_period,
  cluster = ~ scandal_id + cmte_id,
  data = firm_data
)

firm_event_study <- feols(
  log1p(positive_amount_excluding_scandal_cand) ~
    i(relative_period, exposed_firm, ref = REFERENCE_PERIOD) |
    scandal_id^cmte_id + scandal_id^relative_period,
  cluster = ~ scandal_id + cmte_id,
  data = firm_data
)


# Print compact model tables and event-study plots in the interactive device.
etable(
  relationship_any,
  relationship_amount,
  relationship_event_study
)

etable(
  firm_any_excluding_target,
  firm_amount_excluding_target,
  firm_event_study
)

iplot(relationship_event_study)
iplot(firm_event_study)
