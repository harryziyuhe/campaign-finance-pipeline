# Build the working datasets: corrected Consumer Products classification from the
# current data, refreshed industry/subsector measures from modeling/.
#
# Why this is needed. The regenerated files in modeling/ carry updated
# industry and subsector partisanship measures, but they also revert the
# Consumer Products correction: they classify 70,771 Consumer Products dyads as
# Democratic-advantaged, which is the misclassification documented and fixed in
# 08Robust.tex (subsec:robust6). Using them as-is would silently more than
# double the DEM bucket (64,874 -> 135,645) and change every DEM-side result.
#
# Construction: take the corrected file as the base for every column, then
# overwrite ONLY the four industry/subsector columns from modeling/.
#
#   from modeling/:  ind_partisan, ind_partisan_score,
#                    subsec_partisan (new column), subsec_partisan_score
#   from base:       everything else, including singlename_partisan_pre
#
# Bases differ by sample:
#   full sample   -> cand_model_data.RDS                    (corrected)
#   pre-election  -> cand_model_data_election_year_rebuilt.RDS
#                    (corrected covariates + pre-Election-Day outcomes; the
#                     ORIGINAL cand_model_data_election_year.RDS was never
#                     corrected and must not be used as a base)
#
# Outputs are written under new names; nothing existing is overwritten.

suppressPackageStartupMessages({ library(dplyr) })
PATH <- "/htaa/hhe/projects/election_buying/"
COLS <- c("ind_partisan", "ind_partisan_score", "subsec_partisan", "subsec_partisan_score")

same_col <- function(a, b) {
  if (is.factor(a)) a <- as.character(a); if (is.factor(b)) b <- as.character(b)
  if (is.numeric(a) && is.numeric(b))
    all((is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & abs(a - b) < 1e-9))
  else all((is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b))
}

cat("=== checking the four columns agree across the two modeling/ files ===\n")
m1 <- readRDS(paste0(PATH, "modeling/cand_model_data.RDS"))
m2 <- readRDS(paste0(PATH, "modeling/cand_model_data_election_year.RDS"))
stopifnot(nrow(m1) == nrow(m2))
for (cl in COLS) cat(sprintf("  %-24s identical across modeling files: %s\n", cl, same_col(m1[[cl]], m2[[cl]])))
rm(m2); gc(verbose = FALSE)

build <- function(base_file, out_file, label) {
  cat("\n", strrep("=", 68), "\n", label, "\n", strrep("=", 68), "\n", sep = "")
  base <- readRDS(paste0(PATH, base_file))
  cat("base:", base_file, "-", format(nrow(base), big.mark = ","), "rows,", ncol(base), "cols\n")

  stopifnot(nrow(base) == nrow(m1))
  ord_ok <- identical(paste(base$cmte_id, base$candidate_id, base$year),
                      paste(m1$cmte_id,  m1$candidate_id,  m1$year))
  cat("row order corresponds with modeling/ file:", ord_ok, "\n")
  stopifnot(ord_ok)   # positional copy is only valid if this holds

  out <- base
  for (cl in COLS) out[[cl]] <- m1[[cl]]

  cat("\n-- verification --\n")
  # 1. the four columns now match the modeling/ source exactly
  for (cl in COLS) stopifnot(same_col(out[[cl]], m1[[cl]]))
  cat("  all four target columns match modeling/ source\n")
  # 2. every other shared column is untouched from the base
  drift <- character(0)
  for (cl in setdiff(names(base), COLS))
    if (!same_col(out[[cl]], base[[cl]])) drift <- c(drift, cl)
  if (length(drift)) stop("non-target columns changed: ", paste(drift, collapse = ", "))
  cat("  every other column identical to the corrected base\n")
  # 3. the Consumer Products correction survived
  cp <- out %>% filter(category == "Consumer Products") %>% count(singlename_partisan_pre)
  dem_n <- sum(out$singlename_partisan_pre == "DEM", na.rm = TRUE)
  cat("  Consumer Products classified DEM:", sum(cp$n[cp$singlename_partisan_pre == "DEM"], 0), "(want 0)\n")
  cat("  total DEM dyads:", format(dem_n, big.mark = ","), "(want 64,874)\n")
  stopifnot(dem_n == 64874, !any(cp$singlename_partisan_pre == "DEM", na.rm = TRUE))

  cat("\noutput:", out_file, "-", format(nrow(out), big.mark = ","), "rows,", ncol(out), "cols\n")
  cat("contribution events:", format(sum(out$contribute == 1, na.rm = TRUE), big.mark = ","), "\n")
  saveRDS(out, paste0(PATH, out_file))
  rm(out, base); gc(verbose = FALSE)
}

build("cand_model_data.RDS", "cand_model_data_v2.RDS", "FULL SAMPLE")
build("cand_model_data_election_year_rebuilt.RDS", "cand_model_data_election_year_v2.RDS",
      "PRE-ELECTION SAMPLE")

cat("\nDone.\n")
