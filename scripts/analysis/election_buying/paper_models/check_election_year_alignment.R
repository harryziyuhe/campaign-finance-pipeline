# Diagnostic: does cand_model_data_election_year.RDS carry the SAME firm/sector
# alignment columns as the (corrected) full-sample cand_model_data.RDS?
#
# Motivation: cand_model_data.RDS was modified 2026-08-11 (the Consumer Products
# reclassification documented in 08Robust.tex, subsec:robust6), while
# cand_model_data_election_year.RDS still carries an 2026-08-03 mtime -- i.e.
# predating that correction. If the alignment columns differ, every
# "pre-election robustness" result estimated on the election-year file is using a
# superseded alignment measure, and would not be comparable to the main results.
#
# The two files SHOULD differ only in the outcome columns (whether/how much a
# firm contributed, restricted to pre-Election-Day giving).

suppressPackageStartupMessages({ library(dplyr) })

PATH <- "/htaa/hhe/projects/election_buying/"

cat("Loading full-sample data...\n")
full <- readRDS(paste0(PATH, "cand_model_data.RDS"))
cat("Loading election-year data...\n")
ey   <- readRDS(paste0(PATH, "cand_model_data_election_year.RDS"))

cat("\n=== DIMENSIONS ===\n")
cat("full: ", nrow(full), " x ", ncol(full), "\n")
cat("ey:   ", nrow(ey),   " x ", ncol(ey),   "\n")

cat("\n=== COLUMN SETS ===\n")
cat("in full not in ey: ", paste(setdiff(names(full), names(ey)), collapse=", "), "\n")
cat("in ey not in full: ", paste(setdiff(names(ey), names(full)), collapse=", "), "\n")

key <- c("cmte_id", "candidate_id", "year")
cat("\n=== KEY UNIQUENESS ===\n")
cat("full rows / distinct keys: ", nrow(full), " / ",
    nrow(distinct(full[, key])), "\n")
cat("ey   rows / distinct keys: ", nrow(ey), " / ",
    nrow(distinct(ey[, key])), "\n")

# Align both on the shared key so columns are compared row-for-row.
common <- intersect(names(full), names(ey))
f2 <- full[, common]; e2 <- ey[, common]
f2 <- f2[order(f2$cmte_id, f2$candidate_id, f2$year), ]
e2 <- e2[order(e2$cmte_id, e2$candidate_id, e2$year), ]

same_keys <- identical(
  paste(f2$cmte_id, f2$candidate_id, f2$year),
  paste(e2$cmte_id, e2$candidate_id, e2$year)
)
cat("\nRow keys identical after sorting: ", same_keys, "\n")

cat("\n=== PER-COLUMN DIFFERENCES (on the aligned rows) ===\n")
if (same_keys) {
  for (cl in common) {
    a <- f2[[cl]]; b <- e2[[cl]]
    if (is.factor(a)) a <- as.character(a)
    if (is.factor(b)) b <- as.character(b)
    ne <- if (is.numeric(a) && is.numeric(b)) {
      sum(!( (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & abs(a-b) < 1e-9) ))
    } else {
      sum(!( (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b) ))
    }
    if (ne > 0) cat(sprintf("  %-32s differs in %s rows (%.3f%%)\n",
                            cl, format(ne, big.mark=","), 100*ne/length(a)))
  }
  cat("(columns not listed are identical)\n")
} else {
  cat("!! Key sets differ -- cannot do a row-for-row comparison.\n")
  cat("full-only keys: ",
      length(setdiff(paste(f2$cmte_id,f2$candidate_id,f2$year),
                     paste(e2$cmte_id,e2$candidate_id,e2$year))), "\n")
  cat("ey-only keys:   ",
      length(setdiff(paste(e2$cmte_id,e2$candidate_id,e2$year),
                     paste(f2$cmte_id,f2$candidate_id,f2$year))), "\n")
}

cat("\n=== ALIGNMENT MEASURE CROSSTABS ===\n")
cat("\n-- full: singlename_partisan_pre --\n")
print(table(full$singlename_partisan_pre, useNA = "ifany"))
cat("\n-- ey:   singlename_partisan_pre --\n")
print(table(ey$singlename_partisan_pre, useNA = "ifany"))

cat("\n-- Consumer Products specifically (the corrected sector) --\n")
cat("full:\n");
print(full %>% filter(category == "Consumer Products") %>%
        count(singlename_partisan_pre) %>% as.data.frame())
cat("ey:\n");
print(ey %>% filter(category == "Consumer Products") %>%
        count(singlename_partisan_pre) %>% as.data.frame())

cat("\n=== OUTCOME COLUMNS (expected to differ) ===\n")
cat("full contribute==1: ", format(sum(full$contribute == 1, na.rm=TRUE), big.mark=","), "\n")
cat("ey   contribute==1: ", format(sum(ey$contribute   == 1, na.rm=TRUE), big.mark=","), "\n")

cat("\nDone.\n")
