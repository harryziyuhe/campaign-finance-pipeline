# LaTeX fragment for the contribution-amount companion to Figure
# Amount_Cell_Direct.png, matching the format of tab:cell_direct_inc /
# tab:cell_direct_noninc: alignment groups down the rows, Chance of Winning
# across the columns, one panel per candidate type.
#
# Entries are DOLLAR differences, not odds ratios. Because the latent scale of
# a gaussian Tobit is dollars, the aligned-minus-non-advantaged contrast is
# read directly in dollars and the reference value is 0, not 1.
#
# Written from amount_cell_direct.csv (produced by amount_bytype_figures.R) so
# the table and the figure cannot diverge.
suppressPackageStartupMessages(library(dplyr))
PATH <- "/htaa/hhe/projects/election_buying/"
OUT  <- paste0(PATH, "model/sector_alignment/")
GEN  <- paste0(PATH, "paper/generated/")
dir.create(GEN, showWarnings = FALSE, recursive = TRUE)

A <- read.csv(paste0(OUT, "amount_cell_direct.csv"), stringsAsFactors = FALSE)
COLS <- c(-4, -2, 0, 2, 4)
stars <- function(p) if (is.na(p)) "" else if (p < 0.01) "$^{***}$" else
                      if (p < 0.05) "$^{**}$" else if (p < 0.1) "$^{*}$" else ""
money <- function(x, p) {
  s <- formatC(abs(round(x)), format = "d", big.mark = "{,}")
  paste0(if (x < 0) "$-$\\$" else "\\$", s, stars(p))
}

emit_panel <- function(ty, dummies, labels) {
  lines <- character(0)
  for (i in seq_along(dummies)) {
    d <- A[A$dummy == dummies[i] & A$type == ty, ]
    d <- d[match(COLS, d$favorability), ]
    stopifnot(!any(is.na(d$diff)))
    lines <- c(lines, paste0("  ", labels[i], " & ",
                             paste(mapply(money, d$diff, d$p), collapse = " & "), " \\\\"))
  }
  lines
}

co  <- c("co_partisan_GOP", "co_partisan_DEM")
cr  <- c("cross_partisan_GOP", "cross_partisan_DEM")
lab <- c("GOP", "DEM")

# Panel headers are plain left-aligned labels with empty trailing cells, NOT
# \multicolumn: TeX rejects \multicolumn as the first token of an \input'd
# file inside an alignment (the cell template has already started, so the
# implied \omit is misplaced). Same constraint make_tables.R documents.
# The fragment also carries its own closing \hline, because an \hline placed
# immediately after the \input in the caller fails for the same reason.
hdr <- function(t) paste0("  \\textit{", t, "} & & & & & \\\\")
body <- c(
  hdr("Panel A. Incumbents"),
  emit_panel("Incumbent", co, lab),
  "  \\\\[-1.8ex]",
  hdr("Panel B. Challengers and open seats"),
  emit_panel("NonIncumbent", co, lab),
  "  \\hline",
  "  \\hline \\\\[-1.8ex]%")
writeLines(body, paste0(GEN, "amount_cell_direct.tex"))
cat("wrote generated/amount_cell_direct.tex\n\n")
writeLines(body)

# Cross-partisan rows kept separate: not used in the main-text table, but
# reported here so the placebo cells are available if wanted.
cat("\n--- cross-partisan (not in the fragment) ---\n")
for (ty in c("Incumbent", "NonIncumbent")) {
  cat(" ", ty, "\n"); writeLines(emit_panel(ty, cr, lab))
}
