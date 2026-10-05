# Generate LaTeX table bodies directly from saved model objects, so main-text
# and appendix tables cannot drift from the estimates they report.
#
# Motivation: several published tables in this paper were found (2026-08-23/24)
# to contain hand-transcribed values that no longer matched the fits on disk.
# Anything this script emits is read from the model object at build time.
#
# Usage:  Rscript scripts/paper_models/make_tables.R
# Writes: paper/generated/<name>.tex   (input with \input{generated/<name>})

suppressPackageStartupMessages({ library(fixest); library(gtools) })
PATH <- "/htaa/hhe/projects/election_buying/"
MOD  <- paste0(PATH, "model/sector_alignment/")
OUT  <- paste0(PATH, "paper/generated/")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# ---- helpers -----------------------------------------------------------------
stars <- function(p) if (is.na(p)) "" else if (p < 0.01) "$^{***}$" else
                      if (p < 0.05) "$^{**}$" else if (p < 0.1) "$^{*}$" else ""

fmt <- function(x, dollar = FALSE) {
  if (is.na(x)) return("")
  neg <- x < 0; a <- abs(x)
  s <- if (dollar) formatC(a, format = "f", digits = 1, big.mark = "{,}")
       else        formatC(a, format = "f", digits = 4)
  paste0(if (neg) "$-$" else "", s)
}

# Pull estimate/se/p for a model, handling both feglm and the Tobit
# list(model=, vcov_cluster=) convention used by the tobit scripts.
grab <- function(obj) {
  if (inherits(obj, "fixest")) {
    list(cf = coef(obj), se = se(obj), p = pvalue(obj))
  } else {
    ct <- lmtest::coeftest(obj$model, vcov. = obj$vcov_cluster)
    list(cf = ct[, 1], se = ct[, 2], p = ct[, 4])
  }
}

# rows: list of list(label=, terms=c(colA_term, colB_term))
emit <- function(rows, models, file, dollar = FALSE, colsep = "  & ") {
  gs <- lapply(models, function(m) grab(readRDS(paste0(MOD, m))))
  out <- character(0)
  for (r in rows) {
    # Header rows are emitted as ordinary rows with empty trailing cells rather
    # than \multicolumn. These files are \input inside a tabular, and TeX will
    # not accept \multicolumn as the first token of an \input'd file in an
    # alignment (the cell template has already started, so \omit is misplaced).
    # A left-aligned label with empty cells renders identically here.
    if (!is.null(r$header)) {
      out <- c(out, paste0("  \\textit{", r$header, "}",
                           strrep(colsep, length(models)), " \\\\"))
      next
    }
    est <- ses <- character(length(models))
    found_any <- FALSE
    for (i in seq_along(models)) {
      g <- gs[[i]]
      # fixest orders interaction terms according to how the formula was written,
      # so the same conceptual term can appear as "a:b" or "b:a" across models
      # fit by different scripts. Try every permutation of the colon-separated
      # parts before giving up.
      tm <- r$terms[i]
      hit <- NA_character_
      if (!is.na(tm)) {
        parts <- strsplit(tm, ":", fixed = TRUE)[[1]]
        cands <- if (length(parts) == 1) tm else
          apply(gtools::permutations(length(parts), length(parts)), 1,
                function(ix) paste(parts[ix], collapse = ":"))
        m <- cands[cands %in% names(g$cf)]
        if (length(m)) hit <- m[1]
      }
      if (is.na(hit)) { est[i] <- ""; ses[i] <- ""; next }
      found_any <- TRUE
      est[i] <- paste0(fmt(g$cf[[hit]], dollar), stars(g$p[[hit]]))
      ses[i] <- paste0("(", sub("^\\$-\\$", "", fmt(g$se[[hit]], dollar)), ")")
    }
    # A row that matched in NO model is a spec error, not an intentional blank.
    if (!found_any) stop("term not found in any model for row: ", r$label,
                         " (looked for: ", paste(r$terms, collapse=" / "), ")")
    out <- c(out,
             paste0("  ", r$label, colsep, paste(est, collapse = colsep), " \\\\"),
             paste0("  ", strrep(" ", 0), colsep, paste(ses, collapse = colsep), " \\\\"))
  }
  # These fragments are \input inside a tabular. LaTeX will not accept an
  # \hline immediately after an \input there (the \noalign lands mid-cell and
  # errors), so the fragment carries its own closing rule and tight spacer row
  # and the calling table continues straight into its fit-statistic rows.
  # The trailing %% suppresses the final newline. Verified against a minimal
  # example; do not move the \hline back into the caller.
  out <- c(out, "  \\hline \\\\[-1.8ex]%")
  writeLines(out, paste0(OUT, file))
  cat("wrote", file, "-", length(rows), "rows\n")
}

D <- c("co_partisan_GOP", "cross_partisan_GOP", "co_partisan_DEM", "cross_partisan_DEM")
S <- c("score_co_GOP", "score_cross_GOP", "score_co_DEM", "score_cross_DEM")
lab <- c("GOP co-partisan", "GOP cross-partisan", "DEM co-partisan", "DEM cross-partisan")

# ---- Table: full curve-shape. GOP block for main text, everything for appendix -
# Each row carries BOTH term names: categorical first, continuous second, in the
# order emit() receives the models. The main-text table passes one model and so
# uses only the categorical name; the appendix table passes both and gets a
# column per measure.
fc_rows <- function(which_d) {
  pair <- function(pre, i) if (nzchar(pre)) c(paste0(pre, D[i]), paste0(pre, S[i])) else c(D[i], S[i])
  rows <- list(list(header = "Incumbent reference"))
  for (i in which_d) {
    rows <- c(rows, list(
      list(label = lab[i],                                              terms = pair("", i)),
      list(label = sprintf("Chance of Winning $\\times$ %s", lab[i]),   terms = pair("favorability:", i)),
      list(label = sprintf("Chance of Winning$^2$ $\\times$ %s", lab[i]), terms = pair("favorability_sq:", i))))
  }
  rows <- c(rows, list(list(header = "Additional Non-Incumbent shift")))
  for (i in which_d) {
    rows <- c(rows, list(
      list(label = sprintf("%s $\\times$ Non-Incumbent", lab[i]),
           terms = pair("incumbency_binNonIncumbent:", i)),
      list(label = sprintf("Chance of Winning $\\times$ %s $\\times$ Non-Inc.", lab[i]),
           terms = pair("favorability:incumbency_binNonIncumbent:", i)),
      list(label = sprintf("Chance of Winning$^2$ $\\times$ %s $\\times$ Non-Inc.", lab[i]),
           terms = pair("favorability_sq:incumbency_binNonIncumbent:", i))))
  }
  rows
}
emit(fc_rows(1:2), "ASYM_FULLCURVE_NOFE.RDS", "fullcurve_main.tex")   # GOP only, categorical

# The appendix version carries all four alignment categories on both measures.
# At 24 coefficient rows (48 typeset lines) it does not fit on one page -- the
# single-measure version already overran by ~104pt -- so it is emitted as two
# panels, split at the block boundary fc_rows() already marks with a header.
FC_MODELS <- c("ASYM_FULLCURVE_NOFE.RDS", "ASYM_FULLCURVE_CONTINUOUS.RDS")
fc_all <- fc_rows(1:4)
hdr <- which(sapply(fc_all, function(r) !is.null(r$header)))
stopifnot(length(hdr) == 2, hdr[1] == 1)
# Drop the header rows themselves; each panel gets its own column heading.
emit(fc_all[setdiff(seq(hdr[1], hdr[2] - 1), hdr)], FC_MODELS, "fullcurve_full_a.tex")
emit(fc_all[setdiff(seq(hdr[2], length(fc_all)), hdr)], FC_MODELS, "fullcurve_full_b.tex")

# ---- Table: Tobit. Targeting block for main text, everything for appendix ----
tob_models <- c("ASYM_TOBIT_INCUMBENCY_CATEGORICAL.RDS",
                "ASYM_TOBIT_INCUMBENCY_CONTINUOUS.RDS")
targ_rows <- list()
for (i in 1:4) for (lv in c("C","O")) {
  nm <- if (lv=="C") "Challenger" else "Open Seat"
  targ_rows <- c(targ_rows, list(list(
    label = sprintf("%s $\\times$ %s", lab[i], nm),
    terms = c(paste0("incumbency", lv, ":", D[i]), paste0("incumbency", lv, ":", S[i])))))
}
emit(targ_rows, tob_models, "tobit_main.tex", dollar = TRUE)

curve_rows <- list(list(header = "Baseline curve"),
  list(label="Chance of Winning",     terms=c("favorability","favorability")),
  list(label="Chance of Winning$^2$", terms=c("favorability_sq","favorability_sq")),
  list(header = "Alignment level and curve terms"))
for (i in 1:4) curve_rows <- c(curve_rows, list(
  list(label=lab[i], terms=c(D[i], S[i])),
  list(label=sprintf("Chance of Winning $\\times$ %s", lab[i]),
       terms=c(paste0("favorability:",D[i]), paste0("favorability:",S[i]))),
  list(label=sprintf("Chance of Winning$^2$ $\\times$ %s", lab[i]),
       terms=c(paste0("favorability_sq:",D[i]), paste0("favorability_sq:",S[i])))))
emit(c(curve_rows, list(list(header="Candidate-type targeting")), targ_rows),
     tob_models, "tobit_full.tex", dollar = TRUE)

cat("\nDone.\n")
