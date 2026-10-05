library(arrow)
library(dplyr)
library(tidyr)
library(splines)
library(stringr)

get_ticker <- function(x) {
  sapply(strsplit(x, "\\."), `[`, 1)
}

# Raises a clear error if `df` is missing expected columns or has too few
# rows. Called right after reading HouseData.py's output and right before
# writing the final model-input RDS, so a silent upstream schema change or an
# empty-result join surfaces as one clear error at the pipeline stage
# boundary, not a confusing downstream failure in an analysis script.
validate_frame <- function(df, required_columns, name, min_rows = 1) {
    missing <- setdiff(required_columns, names(df))
    if (length(missing) > 0) {
        stop(sprintf("%s: missing expected columns: %s", name, paste(missing, collapse = ", ")))
    }
    if (nrow(df) < min_rows) {
        stop(sprintf("%s: expected at least %d row(s), got %d", name, min_rows, nrow(df)))
    }
}

# CAMPAIGNFINANCE_DATA_ROOT points at the campaign-finance-data folder (contains
# data/ and outputs/), which now lives separately from the scripts (e.g. in
# Dropbox). Required, no fallback -- the script's own location has no
# structural relationship to where the data lives once scripts and data are
# split into separate locations, so a derived-from-getwd()/--file= fallback
# could only ever produce a confusing wrong-path error instead of a clear one.
data_root_env <- Sys.getenv("CAMPAIGNFINANCE_DATA_ROOT", unset = "")
if (!nzchar(data_root_env)) {
    stop(
        "CAMPAIGNFINANCE_DATA_ROOT is not set. Point it at the campaign-finance-data folder ",
        "(contains data/ and outputs/), e.g. Sys.setenv(CAMPAIGNFINANCE_DATA_ROOT = ",
        "'C:/Users/<you>/Dropbox/campaign-finance-data')."
    )
}
DATA_ROOT <- normalizePath(data_root_env, mustWork = TRUE)
HOUSE_PROCESSED_PATH <- file.path(DATA_ROOT, "data", "processed", "house")
MODELING_PROCESSED_PATH <- file.path(DATA_ROOT, "data", "processed", "modeling")
EXTERNAL_PATH <- file.path(DATA_ROOT, "data", "external")

# REVERTED (2026-08): the datematch/entry-measure pipeline
# (contribution_favorability.py / merge_contribution_ratings.py) is built on
# Inside Elections snapshots, some of which were found corrupted for odd
# years (silently overwritten with duplicate current-ratings content during
# a 2026-07-26 re-scrape). Reverted to the original cycle-mean-only
# construction until the odd-year archive is restored. To go back to the
# datematch pipeline once that's resolved: change source_file back to
# paste0("house_firm_cand", election, "_datematch.parquet"), re-add
# rename(rating = rating_cyclemean), and restore the rating_entry/
# rating_weighted/rating_election_day select() columns and the
# favorability_entry/favorability_election_day/favorability_weighted
# mutate() block below (see git history / this comment block for the
# exact prior code).
#
# BUG FIX (unrelated to the datematch work): readline() does not read stdin
# at all under Rscript -- it silently returns "" regardless of what's piped
# in, so `echo y | Rscript HouseCandData.R` always behaved as "N". Kept the
# original interactive prompt for RStudio/interactive use, but Rscript runs
# now take the answer as a command-line arg instead: `Rscript HouseCandData.R Y`.
if (interactive()) {
    answer <- readline("Election Year Data? (Y/N)")
} else {
    cli_args <- commandArgs(trailingOnly = TRUE)
    answer <- if (length(cli_args) > 0) cli_args[[1]] else "N"
}
election = ifelse(toupper(answer) == "Y", "_election_year", "")

source_file <- paste0("house_firm_cand", election, ".parquet")
cand_data <- read_parquet(file.path(HOUSE_PROCESSED_PATH, source_file))
validate_frame(
    cand_data,
    c("cmte_id", "cycle", "candidate_id", "party", "TRBC_Econ_Sector", "TRBC_ID",
      "hq_state", "hq", "ric", "incumbent_party", "total_amount", "contribute",
      "total_amount_leadership", "contribute_leadership",
      "total_amount_combined", "contribute_combined"),
    name = source_file
)

consumer <- read.csv(file.path(EXTERNAL_PATH, "other", "industry_consumer.csv"))
partisan_giving <- read.csv(file.path(EXTERNAL_PATH, "other", "industry_partisan_giving.csv"))
partisan_market <- read.csv(file.path(EXTERNAL_PATH, "other", "industry_partisan_market.csv"))

state_dict <- data.frame(
    hq_state = toupper(c(state.name, "District of Columbia")),
    hq_state_abb = c(state.abb, "DC")
)

cand_data <- cand_data %>%
    filter(!is.na(TRBC_Econ_Sector)) %>%
    filter(party %in% c("DEMOCRAT", "REPUBLICAN")) %>%
    mutate(
        activity_id = str_split_fixed(TRBC_ID, "'", 3)[, 2],
        private = as.numeric(is.na(ric)),
        democrat = ifelse(party == "DEMOCRAT", 1, -1),
        certainty = uncertainty,
        incumbent_party = toupper(incumbent_party),
        same_party = as.numeric(incumbent_party == party),
        same_party = replace_na(same_party, 0),
        firm_cash = pmax(ttl_receipts, firm_amount),
        prior_amount = pmax(prior_amount, 0),
        total_amount = pmin(total_amount, 10000),
        upper_limit = pmax(10000 - prior_amount, total_amount),
        year = cycle
    ) %>%
    left_join(state_dict, by = "hq_state") %>%
    mutate(
        same_state = as.numeric(hq_state_abb == state),
        same_state = replace_na(same_state, 0),
        race = paste0(state, district),
        foreign = as.numeric(hq != "United States of America"),
        foreign = replace_na(foreign, 0)
    )

consumer$activity_id <- as.character(consumer$activity_id)
partisan_giving <- partisan_giving %>%
    select(year, subsector, give_partisan)
partisan_market <- partisan_market %>%
    select(industry, category,
partisan_market <- partisan_market %>%
    select(industry, category,
           etf_partisan, singlename_partisan_pre, singlename_partisan_all,
           etf_score_pre, etf_score_all, singlename_score_pre, singlename_score_all,
           subsec_partisan_score, subsec_partisan, ind_partisan, ind_partisan_score)
           subsec_partisan_score, subsec_partisan, ind_partisan, ind_partisan_score)


cand_data <- cand_data %>%
    left_join(consumer, by = "activity_id") %>%
    left_join(partisan_giving, by = c("year", "subsector")) %>% 
    left_join(partisan_market, by = c("industry"))

cand_data <- cand_data %>%
    select(c(
        cmte_id, year, corporation, private, foreign, sector,
        subsector, industry_group, industry, activity, category,
        consumer_facing, state, district, open, special, rating,
        certainty,
        same_state, candidate, candidate_id, democrat, incumbent_challenge,
        same_party, party, firm_amount, firm_candidates, firm_cash, give_partisan,
        etf_partisan, singlename_partisan_pre, singlename_partisan_all,
        etf_score_pre, etf_score_all, singlename_score_pre, singlename_score_all,
        subsec_partisan_score, subsec_partisan, ind_partisan, ind_partisan_score,
        contribute, total_amount, total_count, upper_limit,
        contribute_leadership, total_amount_leadership, total_count_leadership,
        contribute_combined, total_amount_combined, total_count_combined
    ))

cand_data <- cand_data %>%
    mutate(
        # cycle-mean construction (the original/standard measure)
        favorability = rating * democrat,
        favorability_sq = favorability^2,
        favorability_cu = favorability^3
    )
# Create natural cubic spline basis for favorability
spline_basis <- ns(cand_data$favorability, df = 4)
colnames(spline_basis) <- paste0("spline_", 1:4)
cand_data <- cbind(cand_data, spline_basis)

# Renamed explicitly by name (not positionally). Only these columns actually
# change name; everything else passes through unchanged. The
# industry/subindustry swap goes through a temporary name first to avoid any
# ambiguity about simultaneous vs. sequential rename evaluation.
cand_data <- cand_data %>%
    rename(subindustry_tmp = industry) %>%
    rename(industry = industry_group) %>%
    rename(subindustry = subindustry_tmp) %>%
    rename(
        incumbency = incumbent_challenge,
        contribute_amount = total_amount,
        contribute_count = total_count,
        contribute_limit = upper_limit,
        # Leadership-PAC and combined (principal + leadership) measures are
        # intentionally left uncensored here: the $10,000 cap/upper_limit
        # logic above encodes the per-election FEC limit on contributions to
        # a candidate's principal campaign committee, which does not apply
        # to PAC-to-PAC leadership PAC contributions.
        contribute_amount_leadership = total_amount_leadership,
        contribute_count_leadership = total_count_leadership,
        contribute_amount_combined = total_amount_combined,
        contribute_count_combined = total_count_combined,
        favorability_cb = favorability_cu,
        spline1 = spline_1, spline2 = spline_2, spline3 = spline_3, spline4 = spline_4
    )

output_name <- paste0("cand_model_data", election, ".RDS")
validate_frame(
    cand_data,
    c("cmte_id", "year", "candidate_id", "party", "democrat", "favorability",
      "contribute", "contribute_amount", "contribute_count", "contribute_limit",
      "contribute_leadership", "contribute_amount_leadership", "contribute_count_leadership",
      "contribute_combined", "contribute_amount_combined", "contribute_count_combined"),
    name = output_name
)
saveRDS(cand_data, file.path(MODELING_PROCESSED_PATH, output_name))
