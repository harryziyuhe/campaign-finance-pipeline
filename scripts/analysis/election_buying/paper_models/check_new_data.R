# Verify the regenerated data in modeling/ against the data currently used by
# the paper.
#
# The author reports that four columns changed:
#   industry_partisanship, subsec_partisanship,
#   industry_partisanship_score, subsec_partisanship_score
#
# Two questions:
#   (1) are those columns present and what do they look like;
#   (2) is EVERYTHING ELSE identical, so that swapping the file in changes only
#       the industry/subsector measures and nothing else.
#
# Same approach as check_election_year_alignment.R: compare row-for-row rather
# than by summary statistics, since a summary can match while the underlying
# rows differ.

suppressPackageStartupMessages({ library(dplyr) })
PATH <- "/htaa/hhe/projects/election_buying/"

NEW_COLS <- c("industry_partisanship", "subsec_partisanship",
              "industry_partisanship_score", "subsec_partisanship_score")

compare <- function(cur_path, new_path, label) {
  cat("\n", strrep("=", 70), "\n", label, "\n", strrep("=", 70), "\n", sep = "")
  cur <- readRDS(paste0(PATH, cur_path))
  new <- readRDS(paste0(PATH, new_path))

  cat("\n-- dimensions --\n")
  cat(sprintf("  current: %s x %d\n", format(nrow(cur), big.mark=","), ncol(cur)))
  cat(sprintf("  new:     %s x %d\n", format(nrow(new), big.mark=","), ncol(new)))

  cat("\n-- column set differences --\n")
  only_cur <- setdiff(names(cur), names(new))
  only_new <- setdiff(names(new), names(cur))
  cat("  in current, not in new: ", if (length(only_cur)) paste(only_cur, collapse=", ") else "(none)", "\n")
  cat("  in new, not in current: ", if (length(only_new)) paste(only_new, collapse=", ") else "(none)", "\n")

  cat("\n-- the four named columns, present in new file? --\n")
  for (v in NEW_COLS) cat(sprintf("  %-32s %s\n", v, if (v %in% names(new)) "PRESENT" else "** ABSENT **"))

  if (nrow(cur) != nrow(new)) {
    cat("\n!! row counts differ -- cannot compare row-for-row\n"); return(invisible(NULL))
  }

  key <- c("cmte_id","candidate_id","year")
  same_order <- identical(
    paste(cur$cmte_id, cur$candidate_id, cur$year),
    paste(new$cmte_id, new$candidate_id, new$year))
  cat("\n-- row order corresponds natively: ", same_order, " --\n", sep = "")
  if (!same_order) { cat("!! order differs; aborting row-for-row comparison\n"); return(invisible(NULL)) }

  cat("\n-- per-column comparison (shared columns) --\n")
  shared <- intersect(names(cur), names(new))
  identical_cols <- character(0)
  for (cl in shared) {
    a <- cur[[cl]]; b <- new[[cl]]
    if (is.factor(a)) a <- as.character(a)
    if (is.factor(b)) b <- as.character(b)
    ne <- if (is.numeric(a) && is.numeric(b)) {
      sum(!((is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & abs(a-b) < 1e-9)))
    } else {
      sum(!((is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)))
    }
    if (ne > 0) cat(sprintf("  %-32s DIFFERS in %s rows (%.3f%%)\n",
                            cl, format(ne, big.mark=","), 100*ne/length(a)))
    else identical_cols <- c(identical_cols, cl)
  }
  cat(sprintf("\n  %d of %d shared columns are byte-identical\n", length(identical_cols), length(shared)))

  cat("\n-- distribution of the new measures --\n")
  for (v in NEW_COLS) {
    if (!v %in% names(new)) next
    x <- new[[v]]
    cat("\n  ", v, ":\n", sep = "")
    if (is.numeric(x)) {
      cat(sprintf("    numeric | mean %.4f  sd %.4f  min %.4f  max %.4f  NA %s\n",
                  mean(x, na.rm=TRUE), sd(x, na.rm=TRUE), min(x, na.rm=TRUE),
                  max(x, na.rm=TRUE), format(sum(is.na(x)), big.mark=",")))
    } else {
      tb <- sort(table(x, useNA="ifany"), decreasing=TRUE)
      print(head(tb, 8))
    }
  }
  invisible(NULL)
}

compare("cand_model_data.RDS", "modeling/cand_model_data.RDS", "FULL SAMPLE")
compare("cand_model_data_election_year.RDS", "modeling/cand_model_data_election_year.RDS",
        "ELECTION-YEAR SAMPLE")
cat("\nDone.\n")
