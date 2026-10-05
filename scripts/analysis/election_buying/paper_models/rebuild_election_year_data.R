# Rebuild the pre-election (election-year) analysis dataset so that it differs
# from the full-sample dataset ONLY in the outcome columns.
#
# Why: cand_model_data_election_year.RDS predates the 2026-08-11 correction to
# cand_model_data.RDS (the Consumer Products reclassification documented in
# 08Robust.tex, subsec:robust6). Any covariate drift between the two files --
# especially in the sector-alignment columns, which are the paper's key
# regressor -- makes the pre-election results non-comparable to the main
# results, since the "robustness check" would be varying two things at once
# (the sample window AND the alignment measure).
#
# Construction: take the corrected full-sample file as the base for EVERY
# column, then overwrite only `contribute` / `contribute_amount` with the
# pre-Election-Day values. Dyads absent from the election-year file are dyads
# with no pre-election contribution, so they take contribute = 0, amount = 0.
#
# Output: cand_model_data_election_year_rebuilt.RDS  (the original file is left
# untouched -- RDS cleanup in this project is user-managed.)

suppressPackageStartupMessages({ library(dplyr) })

PATH <- "/htaa/hhe/projects/election_buying/"
KEY  <- c("cmte_id", "candidate_id", "year")

# All four outcome columns legitimately depend on the observation window.
# contribute_limit is included because it is the Tobit's right-censoring bound
# and varies with how many elections (primary/general) fall inside the window;
# the diagnostic confirmed all four differ between the files while every other
# column except singlename_partisan_pre is identical.
OUTCOME <- c("contribute", "contribute_amount", "contribute_count", "contribute_limit")

cat("Loading corrected full-sample data...\n")
full <- readRDS(paste0(PATH, "cand_model_data.RDS"))
cat("Loading original election-year data...\n")
ey   <- readRDS(paste0(PATH, "cand_model_data_election_year.RDS"))

stopifnot(all(KEY %in% names(full)), all(KEY %in% names(ey)),
          all(OUTCOME %in% names(full)), all(OUTCOME %in% names(ey)))

cat("\nfull rows:", nrow(full), " ey rows:", nrow(ey), "\n")

# The natural key (cmte_id, candidate_id, year) is NOT unique -- 7,126,861 rows
# span 7,123,638 distinct keys (~3,200 duplicates, e.g. candidates appearing in
# both a special and a regular election in the same cycle). A key join would
# therefore fan out. Both files have identical row counts and were produced by
# the same pipeline, so prefer an exact positional copy and only fall back to a
# join if the row order does not already correspond.
stopifnot(nrow(full) == nrow(ey))

order_matches <- identical(
  paste(full$cmte_id, full$candidate_id, full$year),
  paste(ey$cmte_id,   ey$candidate_id,   ey$year)
)
cat("\nRow order already corresponds between files:", order_matches, "\n")

out <- full
if (order_matches) {
  cat("Copying outcome columns positionally (exact, no join).\n")
  for (cl in OUTCOME) out[[cl]] <- ey[[cl]]
} else {
  cat("Row order differs; sorting both to a deterministic order before copying.\n")
  # Break key ties with additional stable columns so both sides sort identically.
  tie <- intersect(c("special", "incumbency", "party", "state"), names(full))
  ord_f <- do.call(order, c(lapply(c(KEY, tie), function(x) full[[x]])))
  ord_e <- do.call(order, c(lapply(c(KEY, tie), function(x) ey[[x]])))
  stopifnot(identical(
    paste(full$cmte_id[ord_f], full$candidate_id[ord_f], full$year[ord_f]),
    paste(ey$cmte_id[ord_e],   ey$candidate_id[ord_e],   ey$year[ord_e])
  ))
  for (cl in OUTCOME) out[[cl]][ord_f] <- ey[[cl]][ord_e]
}

cat("\n=== SANITY CHECKS ===\n")
cat("Columns identical to full-sample file: ",
    identical(sort(names(out)), sort(names(full))), "\n")
cat("Row count identical to full-sample file: ", nrow(out) == nrow(full), "\n")

# Every non-outcome column must be byte-identical to the corrected full file.
drift <- character(0)
for (cl in setdiff(names(full), OUTCOME)) {
  a <- full[[cl]]; b <- out[[cl]]
  if (is.factor(a)) a <- as.character(a)
  if (is.factor(b)) b <- as.character(b)
  same <- if (is.numeric(a) && is.numeric(b)) {
    all((is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & abs(a - b) < 1e-9))
  } else {
    all((is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b))
  }
  if (!same) drift <- c(drift, cl)
}
if (length(drift)) {
  cat("!! Non-outcome columns that DIFFER from full sample:",
      paste(drift, collapse = ", "), "\n")
} else {
  cat("All non-outcome columns identical to the corrected full-sample file. OK\n")
}

cat("\nContribution events -- full sample: ",
    format(sum(full$contribute == 1, na.rm = TRUE), big.mark = ","), "\n")
cat("Contribution events -- rebuilt pre-election: ",
    format(sum(out$contribute == 1, na.rm = TRUE), big.mark = ","), "\n")
cat("Contribution events -- original election-year file: ",
    format(sum(ey$contribute == 1, na.rm = TRUE), big.mark = ","),
    " (should equal the rebuilt count)\n")
stopifnot(sum(out$contribute == 1, na.rm = TRUE) == sum(ey$contribute == 1, na.rm = TRUE))

cat("\nAlignment measure in ORIGINAL election-year file (uncorrected):\n")
print(table(ey$singlename_partisan_pre, useNA = "ifany"))

cat("\nAlignment measure in rebuilt file (must match full sample):\n")
print(table(out$singlename_partisan_pre, useNA = "ifany"))

saveRDS(out, paste0(PATH, "cand_model_data_election_year_rebuilt.RDS"))
cat("\nWrote cand_model_data_election_year_rebuilt.RDS\n")
cat("Done.\n")
