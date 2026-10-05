library(dplyr)
library(fixest)

# =============================================================================
# 0) Configuration
# =============================================================================
# Tests the 2x2 election-buying / access-buying hypothesis competition (see
# docs/theory_revision_handoff.md) using ONLY the three sector-level
# partisan-alignment measures the user asked for:
#   - singlename_partisan_pre (categorical: Other/GOP/DEM, extremity-
#     thresholded version of singlename_score_pre)
#   - singlename_score_pre    (continuous; built by aggregating individual-
#     donor lean temporally first, then cross-sectionally within sector)
#   - etf_score_pre           (continuous; built via a synthetic per-sector
#     ETF, aggregating cross-sectionally first, then temporally)
# All three are confirmed sector-level (constant within subindustry, by
# design -- confirmed with the user 2026-08-03), NOT firm-level heterogeneity.
# singlename and etf are independent constructions expected to agree on
# strongly-aligned sectors and disagree on weak ones (a robustness check of
# each other, per the user). No other heterogeneity measure (category,
# subsector, industry, consumer_facing, etc.) is used anywhere in this
# script.
#
# Design mirrors docs/theory_revision_handoff.md's already-vetted
# methodology (delta-method peak tests, don't pool Challenger+Open-seat,
# print raw cell counts before trusting a coefficient, etc.) but swaps the
# ad hoc firm_lean/category grouping used in that session for the dataset's
# own singlename_partisan_pre / singlename_score_pre / etf_score_pre.
#
# For each alignment measure, and separately for each candidate party
# (Republican/Democrat) and candidate type (Incumbent/Challenger/Open-seat),
# we fit: contribute ~ (favorability + favorability_sq) * alignment +
# controls | state + year. Restricting to a single party subsample makes
# "alignment" directly a co-partisanship-intensity measure (aligned firms
# giving to their own party's candidates of this type) without needing a
# separate co_partisan dummy crossed in -- same logic as
# scripts/logit/singlename_triple_interaction.R's co_partisan construction,
# just evaluated within one-party slices for interpretability of the
# delta-method peak-shift test (see docs/theory_revision_handoff.md §4.1).
PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# =============================================================================
# 1) Data prep
# =============================================================================

prep_cand_data <- function(cand_data) {
  cand_data$singlename_partisan_pre <- factor(
    cand_data$singlename_partisan_pre,
    levels = c("Other", "GOP", "DEM")
  )
  cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))

  cand_data$singlename_GOP_pre <- pmax(cand_data$singlename_score_pre, 0)
  cand_data$singlename_DEM_pre <- pmax(-cand_data$singlename_score_pre, 0)
  cand_data$etf_GOP_pre <- pmax(cand_data$etf_score_pre, 0)
  cand_data$etf_DEM_pre <- pmax(-cand_data$etf_score_pre, 0)

  # Co-partisanship per measure: does the firm's revealed sector lean match
  # this particular candidate's party? Firms in a sector with no clear lean
  # ("Other") are never co-partisan.
  cand_data$co_partisan_snp <- dplyr::case_when(
    cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "GOP" ~ 1,
    cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "DEM" ~ 1,
    TRUE ~ 0
  )
  cand_data$co_partisan_sncp <- dplyr::case_when(
    cand_data$party == "REPUBLICAN" & cand_data$singlename_GOP_pre > 0 ~ 1,
    cand_data$party == "DEMOCRAT"   & cand_data$singlename_DEM_pre > 0 ~ 1,
    TRUE ~ 0
  )
  cand_data$co_partisan_etf <- dplyr::case_when(
    cand_data$party == "REPUBLICAN" & cand_data$etf_GOP_pre > 0 ~ 1,
    cand_data$party == "DEMOCRAT"   & cand_data$etf_DEM_pre > 0 ~ 1,
    TRUE ~ 0
  )

  # Party-matched continuous alignment intensity (0 if the candidate's party
  # doesn't match the direction the score points) -- used for the continuous
  # robustness checks, evaluated within single-party subsamples below.
  cand_data$snp_align <- dplyr::if_else(
    cand_data$party == "REPUBLICAN", cand_data$singlename_GOP_pre, cand_data$singlename_DEM_pre
  )
  cand_data$etf_align <- dplyr::if_else(
    cand_data$party == "REPUBLICAN", cand_data$etf_GOP_pre, cand_data$etf_DEM_pre
  )

  cand_data
}

# =============================================================================
# 2) Helpers
# =============================================================================

write_coef_txt <- function(mod, txt_path) {
  con <- file(txt_path, open = "wt")
  on.exit(close(con))
  writeLines(capture.output(summary(mod)), con)
}

fit_save <- function(rhs, data, out_path, cluster_fml = ~ cmte_id + candidate_id) {
  data <- droplevels(data)
  fmla <- as.formula(paste("contribute ~", rhs, "| state + year"))
  mod <- feglm(fmla, data = data, family = binomial(link = "logit"), cluster = cluster_fml)
  saveRDS(mod, out_path)
  write_coef_txt(mod, sub("\\.RDS$", "_coefficients.txt", out_path))
  invisible(mod)
}

# Print raw n dyads / n contribute events for a subsample before trusting any
# coefficient fit on it (docs/theory_revision_handoff.md §4.4 discipline).
print_cell_counts <- function(data, label) {
  n <- nrow(data)
  events <- sum(data$contribute, na.rm = TRUE)
  n_firms <- length(unique(data$cmte_id))
  cat(sprintf("  [%s] n_dyads=%d  n_events=%d  n_firms=%d  rate=%.4f%%\n",
              label, n, events, n_firms, 100 * events / n))
}

base_controls <- function(include_party = TRUE) {
  ctrl <- c("favorability", "favorability_sq", "special", "private", "foreign",
            "same_state", "log(firm_cash)")
  if (include_party) ctrl <- c(ctrl, "party")
  paste(ctrl, collapse = " + ")
}

CAND_TYPES <- c(Incumbent = "I", Challenger = "C", `Open-seat` = "O")
PARTIES <- c(Republican = "REPUBLICAN", Democrat = "DEMOCRAT")

# =============================================================================
# 3) Primary battery: within-party x within-candidate-type models
# =============================================================================
# Model A (categorical): contribute ~ (fv+fv_sq)*co_partisan_snp + controls
# Model B (singlename continuous): contribute ~ (fv+fv_sq)*snp_align + controls
# Model C (etf continuous): contribute ~ (fv+fv_sq)*etf_align + controls
# Fit separately per party (so "aligned" always means co-partisan with THIS
# subsample's party) and per candidate type (per the "don't pool Challenger +
# Open-seat" trap -- docs §3.3/§4.3).

run_primary_battery <- function(cand_data) {
  for (party_name in names(PARTIES)) {
    party_val <- PARTIES[[party_name]]
    party_data <- cand_data %>% filter(party == party_val)

    for (type_name in names(CAND_TYPES)) {
      type_val <- CAND_TYPES[[type_name]]
      sub_data <- party_data %>% filter(incumbency == type_val)

      label <- paste0(party_name, "_", type_name)
      cat(sprintf("\n--- %s ---\n", label))
      print_cell_counts(sub_data %>% filter(co_partisan_snp == 1), paste0(label, " aligned(snp)"))
      print_cell_counts(sub_data %>% filter(co_partisan_snp == 0), paste0(label, " baseline(snp)"))

      # Model A: categorical alignment (singlename_partisan_pre-based)
      rhs_a <- paste(base_controls(include_party = FALSE),
                     "(favorability + favorability_sq) * co_partisan_snp",
                     sep = " + ")
      tryCatch({
        fit_save(rhs_a, sub_data, paste0(OUT_DIR, "A_categorical_", label, ".RDS"))
        cat(sprintf("  Fitted Model A (categorical) for %s\n", label))
      }, error = function(e) cat(sprintf("  MODEL A FAILED for %s: %s\n", label, conditionMessage(e))))

      # Model B: continuous singlename_score_pre alignment
      rhs_b <- paste(base_controls(include_party = FALSE),
                     "(favorability + favorability_sq) * snp_align",
                     sep = " + ")
      tryCatch({
        fit_save(rhs_b, sub_data, paste0(OUT_DIR, "B_singlename_", label, ".RDS"))
        cat(sprintf("  Fitted Model B (singlename continuous) for %s\n", label))
      }, error = function(e) cat(sprintf("  MODEL B FAILED for %s: %s\n", label, conditionMessage(e))))

      # Model C: continuous etf_score_pre alignment
      rhs_c <- paste(base_controls(include_party = FALSE),
                     "(favorability + favorability_sq) * etf_align",
                     sep = " + ")
      tryCatch({
        fit_save(rhs_c, sub_data, paste0(OUT_DIR, "C_etf_", label, ".RDS"))
        cat(sprintf("  Fitted Model C (etf continuous) for %s\n", label))
      }, error = function(e) cat(sprintf("  MODEL C FAILED for %s: %s\n", label, conditionMessage(e))))
    }
  }
}

# =============================================================================
# 4) H2 pooled models (main co-partisan support effect, not split by
#    candidate type -- incumbency stays a control here)
# =============================================================================

run_h2_pooled <- function(cand_data) {
  for (party_name in names(PARTIES)) {
    party_val <- PARTIES[[party_name]]
    party_data <- cand_data %>% filter(party == party_val)
    label <- paste0(party_name, "_pooled")
    cat(sprintf("\n--- H2 pooled %s ---\n", label))
    print_cell_counts(party_data %>% filter(co_partisan_snp == 1), paste0(label, " aligned(snp)"))
    print_cell_counts(party_data %>% filter(co_partisan_snp == 0), paste0(label, " baseline(snp)"))

    rhs_a <- paste(base_controls(include_party = FALSE), "incumbency",
                   "(favorability + favorability_sq) * co_partisan_snp",
                   sep = " + ")
    tryCatch({
      fit_save(rhs_a, party_data, paste0(OUT_DIR, "H2_A_categorical_", label, ".RDS"))
      cat(sprintf("  Fitted H2 Model A for %s\n", label))
    }, error = function(e) cat(sprintf("  H2 MODEL A FAILED for %s: %s\n", label, conditionMessage(e))))

    rhs_b <- paste(base_controls(include_party = FALSE), "incumbency",
                   "(favorability + favorability_sq) * snp_align",
                   sep = " + ")
    tryCatch({
      fit_save(rhs_b, party_data, paste0(OUT_DIR, "H2_B_singlename_", label, ".RDS"))
      cat(sprintf("  Fitted H2 Model B for %s\n", label))
    }, error = function(e) cat(sprintf("  H2 MODEL B FAILED for %s: %s\n", label, conditionMessage(e))))

    rhs_c <- paste(base_controls(include_party = FALSE), "incumbency",
                   "(favorability + favorability_sq) * etf_align",
                   sep = " + ")
    tryCatch({
      fit_save(rhs_c, party_data, paste0(OUT_DIR, "H2_C_etf_", label, ".RDS"))
      cat(sprintf("  Fitted H2 Model C for %s\n", label))
    }, error = function(e) cat(sprintf("  H2 MODEL C FAILED for %s: %s\n", label, conditionMessage(e))))
  }
}

# =============================================================================
# 5) Confirmatory triple-interaction: favorability x alignment x
#    incumbency-binary (Incumbent vs NonIncumbent), within party. Internal-
#    consistency cross-check paralleling docs §3.3 -- NOT a substitute for
#    the separate-by-candidate-type models above (§3.3's pooling trap: don't
#    read a single NonIncumbent curve as if Challenger and Open-seat share
#    one peak). Reported alongside, not instead of, the primary battery.
# =============================================================================

run_triple_interaction <- function(cand_data) {
  cand_data$incumbency_bin <- factor(
    ifelse(cand_data$incumbency == "I", "Incumbent", "NonIncumbent"),
    levels = c("Incumbent", "NonIncumbent")
  )

  for (party_name in names(PARTIES)) {
    party_val <- PARTIES[[party_name]]
    party_data <- cand_data %>% filter(party == party_val)
    label <- paste0(party_name, "_triple")
    cat(sprintf("\n--- Triple interaction %s ---\n", label))

    rhs_a <- paste(base_controls(include_party = FALSE),
                   "(favorability + favorability_sq) * co_partisan_snp * incumbency_bin",
                   sep = " + ")
    tryCatch({
      fit_save(rhs_a, party_data, paste0(OUT_DIR, "TRIPLE_A_categorical_", label, ".RDS"))
      cat(sprintf("  Fitted TRIPLE Model A for %s\n", label))
    }, error = function(e) cat(sprintf("  TRIPLE MODEL A FAILED for %s: %s\n", label, conditionMessage(e))))

    rhs_b <- paste(base_controls(include_party = FALSE),
                   "(favorability + favorability_sq) * snp_align * incumbency_bin",
                   sep = " + ")
    tryCatch({
      fit_save(rhs_b, party_data, paste0(OUT_DIR, "TRIPLE_B_singlename_", label, ".RDS"))
      cat(sprintf("  Fitted TRIPLE Model B for %s\n", label))
    }, error = function(e) cat(sprintf("  TRIPLE MODEL B FAILED for %s: %s\n", label, conditionMessage(e))))

    rhs_c <- paste(base_controls(include_party = FALSE),
                   "(favorability + favorability_sq) * etf_align * incumbency_bin",
                   sep = " + ")
    tryCatch({
      fit_save(rhs_c, party_data, paste0(OUT_DIR, "TRIPLE_C_etf_", label, ".RDS"))
      cat(sprintf("  Fitted TRIPLE Model C for %s\n", label))
    }, error = function(e) cat(sprintf("  TRIPLE MODEL C FAILED for %s: %s\n", label, conditionMessage(e))))
  }
}

# =============================================================================
# 6) H1 pooled concavity baseline (general, not conditional on alignment)
# =============================================================================

run_h1_baseline <- function(cand_data) {
  cat("\n--- H1 pooled baseline concavity ---\n")
  rhs <- paste(base_controls(include_party = TRUE), "incumbency", sep = " + ")
  fit_save(rhs, cand_data, paste0(OUT_DIR, "H1_baseline_pooled.RDS"))
  cat("  Fitted H1 baseline\n")
}

# =============================================================================
# 7) Main
# =============================================================================

cand_data <- readRDS(paste0(PATH, "cand_model_data.RDS"))
cand_data <- prep_cand_data(cand_data)

run_h1_baseline(cand_data)
run_h2_pooled(cand_data)
run_primary_battery(cand_data)
run_triple_interaction(cand_data)

cat("\nAll models fit and saved to", OUT_DIR, "\n")
