# Coefficient plot replacing Table 6 (tab:asym_fullcurve), the full curve-shape
# specification. The table reports 12 hand-read numbers whose point is a
# comparison; a forest plot makes the comparison directly visible.
#
# The design goal is to show the BASELINE curve and the ALIGNMENT interactions
# in the same frame, which the table does not do -- the table's baseline curve
# is summarised as a one-line "fully interacted" footer and its coefficients
# never appear.
#
# Two things the table's parameterisation obscures, both fixed here:
#
#  1. The baseline curve in this model is fully interacted with incumbency AND
#     party, so "the baseline" is six different curves, not one. Each alignment
#     dummy attaches to a specific candidate party (co_partisan_GOP is a
#     Republican candidate, cross_partisan_GOP a Democratic one, and so on), so
#     each interaction is plotted against the baseline it actually modifies.
#     Omitting the party terms here silently substitutes the Democratic-
#     candidate baseline for the Republican one and reverses the sign of the
#     quadratic; that error is the reason this script builds contrast vectors
#     explicitly rather than summing coefficient names by hand.
#
#  2. The table splits non-incumbents into an "Incumbent reference" row and an
#     "Additional Non-Incumbent shift" row, so the non-incumbent effect is the
#     sum of two rows the reader must add. Here the non-incumbent panel plots
#     that TOTAL directly, with its own standard error from the full
#     covariance matrix rather than from adding two published SEs.
suppressPackageStartupMessages({ library(ggplot2); library(dplyr); library(fixest) })

PATH <- "/htaa/hhe/projects/election_buying/"
FIG  <- paste0(PATH, "paper/figures/")
OUT  <- paste0(PATH, "model/sector_alignment/")

mod <- readRDS(paste0(OUT, "ASYM_FULLCURVE_NOFE.RDS"))
cf  <- coef(mod); V <- vcov(mod); NM <- names(cf)

# fixest orders interaction parts by how the formula was written; resolve each
# wanted term to the name the model actually carries, and stop if it has none.
resolve <- function(nm) {
  p <- strsplit(nm, ":")[[1]]
  hit <- NM[vapply(NM, function(k) setequal(strsplit(k, ":")[[1]], p), logical(1))]
  if (!length(hit)) stop("missing coef: ", nm)
  hit[1]
}
# est/se for a sum of coefficients, from the full vcov (not from adding SEs).
combo <- function(terms) {
  idx <- vapply(terms, resolve, character(1))
  c_vec <- numeric(length(cf)); names(c_vec) <- NM
  for (i in idx) c_vec[i] <- c_vec[i] + 1
  est <- sum(c_vec * cf)
  se  <- sqrt(as.numeric(t(c_vec) %*% V %*% c_vec))
  c(est = est, se = se)
}

NONINC <- "incumbencyC"   # Challenger represents non-incumbents, as elsewhere

baseline_terms <- function(party, type, which) {
  base <- if (which == "lin") "favorability" else "favorability_sq"
  tt <- base
  if (party == "REP") tt <- c(tt, paste0(base, ":partyREPUBLICAN"))
  if (type == "NonIncumbent") {
    tt <- c(tt, paste0(base, ":", NONINC))
    if (party == "REP") tt <- c(tt, paste0(base, ":", NONINC, ":partyREPUBLICAN"))
  }
  tt
}
align_terms <- function(dummy, type, which) {
  pre <- switch(which, level = "", lin = "favorability:", quad = "favorability_sq:")
  tt <- paste0(pre, dummy)
  if (type == "NonIncumbent")
    tt <- c(tt, if (which == "level") paste0(dummy, ":incumbency_binNonIncumbent")
                else paste0(pre, dummy, ":incumbency_binNonIncumbent"))
  tt
}

# Each alignment dummy is defined on a specific candidate party.
DUMMIES <- tribble(
  ~dummy,                ~label,                      ~grp,   ~ptype,           ~party,
  "co_partisan_GOP",     "GOP sector, Rep. cand.",    "GOP",  "co-partisan",    "REP",
  "cross_partisan_GOP",  "GOP sector, Dem. cand.",    "GOP",  "cross-partisan", "DEM",
  "co_partisan_DEM",     "DEM sector, Dem. cand.",    "DEM",  "co-partisan",    "DEM",
  "cross_partisan_DEM",  "DEM sector, Rep. cand.",    "DEM",  "cross-partisan", "REP"
)

rows <- list()
for (ty in c("Incumbent", "NonIncumbent")) {
  for (w in c("lin", "quad")) for (pty in c("REP", "DEM")) {
    r <- combo(baseline_terms(pty, ty, w))
    rows[[length(rows) + 1]] <- data.frame(
      block = "Baseline curve", grp = "Other", ptype = "baseline",
      label = sprintf("Non-advantaged, %s cand.", if (pty == "REP") "Rep." else "Dem."),
      type = ty, term = w, est = r[["est"]], se = r[["se"]], stringsAsFactors = FALSE)
  }
  for (i in seq_len(nrow(DUMMIES))) for (w in c("level", "lin", "quad")) {
    d <- DUMMIES[i, ]
    r <- combo(align_terms(d$dummy, ty, w))
    rows[[length(rows) + 1]] <- data.frame(
      block = "Alignment effect", grp = d$grp, ptype = d$ptype, label = d$label,
      type = ty, term = w, est = r[["est"]], se = r[["se"]], stringsAsFactors = FALSE)
  }
}
D <- do.call(rbind, rows)
D$ci_lo <- D$est - 1.96 * D$se
D$ci_hi <- D$est + 1.96 * D$se
D$p <- 2 * pnorm(-abs(D$est / D$se))
write.csv(D, paste0(OUT, "fullcurve_coefplot.csv"), row.names = FALSE)
cat("=== plotted quantities ===\n")
print(D[, c("block","label","type","term","est","se","ci_lo","ci_hi","p")],
      row.names = FALSE, digits = 3)

# ---- plot -------------------------------------------------------------------
D$term <- factor(D$term, levels = c("level", "lin", "quad"),
                 labels = c("Level", "Chance of Winning",
                            "Chance of Winning²"))
D$type <- factor(ifelse(D$type == "Incumbent", "Incumbents", "Challengers & open seats"),
                 levels = c("Incumbents", "Challengers & open seats"))
ORDER <- c("Non-advantaged, Rep. cand.", "Non-advantaged, Dem. cand.",
           DUMMIES$label)
D$label <- factor(D$label, levels = rev(ORDER))
D$grp <- factor(D$grp, levels = c("Other", "GOP", "DEM"))

pal <- c(Other = "grey15", GOP = "firebrick", DEM = "steelblue")
shp <- c(baseline = 15, `co-partisan` = 16, `cross-partisan` = 17)

p <- ggplot(D, aes(x = est, y = label, color = grp, shape = ptype)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey55", linewidth = 0.45) +
  geom_hline(yintercept = 4.5, color = "grey75", linewidth = 0.4) +
  geom_errorbarh(aes(xmin = ci_lo, xmax = ci_hi), height = 0, linewidth = 0.85) +
  geom_point(size = 2.5) +
  facet_grid(type ~ term, scales = "free_x") +
  scale_color_manual(values = pal, guide = "none") +
  scale_shape_manual(values = shp, guide = "none") +
  labs(x = "Coefficient (log-odds)", y = NULL) +
  theme_minimal(base_size = 12) +
  theme(text = element_text(family = "serif"),
        panel.grid.minor = element_blank(),
        panel.grid.major.y = element_blank(),
        panel.grid.major.x = element_line(color = "grey88", linewidth = 0.3),
        axis.line.x = element_line(color = "grey40", linewidth = 0.4),
        axis.ticks.x = element_line(color = "grey40", linewidth = 0.4),
        strip.text = element_text(face = "bold"),
        panel.spacing.x = unit(0.9, "lines"))
# Sized so the figure is legible after LaTeX scales it to \linewidth (about
# 6.5in): a 12in-wide render shrinks to ~54% and the axis labels become
# unreadable in print.
ggsave(paste0(FIG, "Fullcurve_Coefplot.png"), p, width = 9.2, height = 6.6, dpi = 300)
cat("\nwrote Fullcurve_Coefplot.png\n")
