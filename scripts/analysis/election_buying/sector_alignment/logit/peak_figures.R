# Two peak-location figures added in the results reorganization.
#
#  1) Peak_By_Alignment.png -- replaces the old Figure 3 (three overlapping
#     predicted-probability curves by sectoral alignment). The prose around
#     that figure argues about where each curve peaks, so show the peaks.
#     Source: peak_by_alignment.csv, from peak_by_alignment.R.
#
#  2) Asymmetric_Peak_CI_ByType.png -- the companion panel for Figure 5, the
#     incumbent location test. Same treatment as Figure 4's peak panel, but
#     split by candidate type. No new estimation: asymmetric_fullcurve_peak_ci.csv
#     already holds these peaks, from asymmetric_peak_ci.R.
#
# Visual conventions follow asymmetric_figures.R / paper/plots.R: serif,
# theme_minimal(base_size), grey10/firebrick/steelblue by alignment, solid vs
# triangle point for co- vs cross-partisan.
#
# Both figures use the DELTA-METHOD 95% intervals from the CSVs, not the
# 10,000-draw 90% simulation intervals that asymmetric_figures.R computes
# internally. The CSV convention is the one the tables report; using it here
# keeps a single convention rather than adding a third.

suppressPackageStartupMessages({ library(ggplot2); library(dplyr) })
PATH <- "/htaa/hhe/projects/election_buying/"
CSV  <- paste0(PATH, "model/sector_alignment/")
OUT  <- paste0(PATH, "paper/figures/")

palette5 <- c(Other = "grey10", GOP = "firebrick", DEM = "steelblue")
clean_theme <- function(base_size) {
  theme_minimal(base_size = base_size) +
    theme(text = element_text(family = "serif"),
          panel.grid.minor = element_blank(),
          panel.grid.major.x = element_blank(),
          panel.grid.major.y = element_line(color = "grey85", linewidth = 0.3),
          axis.line.x = element_line(color = "grey40", linewidth = 0.4),
          axis.ticks.x = element_line(color = "grey40", linewidth = 0.4))
}

# ---------------------------------------------------------------- Figure 3 --
a <- read.csv(paste0(CSV, "peak_by_alignment.csv"), stringsAsFactors = FALSE)
a$color_group <- ifelse(grepl("^GOP", a$group), "GOP",
                 ifelse(grepl("^DEM", a$group), "DEM", "Other"))
a$color_group <- factor(a$color_group, levels = c("Other", "GOP", "DEM"))
a$group <- factor(a$group, levels = c("Non-advantaged", "GOP-advantaged", "DEM-advantaged"))

p1 <- ggplot(a, aes(x = group, y = peak, color = color_group)) +
  geom_pointrange(aes(ymin = ci_low, ymax = ci_high), size = 1.0, linewidth = 1.2) +
  scale_color_manual(values = palette5, guide = "none") +
  labs(x = NULL, y = "Chance of Winning at Predicted Peak") +
  clean_theme(17) +
  theme(axis.text.x = element_text(angle = 15, hjust = 1))
ggsave(paste0(OUT, "Peak_By_Alignment.png"), p1, width = 8.5, height = 5.5, dpi = 300)
cat("wrote Peak_By_Alignment.png\n"); print(a[, c("group", "peak", "ci_low", "ci_high")], row.names = FALSE)

# --------------------------------------- Peak by candidate type (Figure) ----
# Both panels use the SAME estimator: 10,000 draws from N(beta-hat, V-hat), the
# argmax of each simulated curve taken over the favorability grid, and the
# 2.5/97.5 quantiles of those argmaxes. This is deliberate. The peak is
# -b/2c, a ratio whose denominator goes to zero as the curve flattens, and the
# incumbent curves here are close to flat. The delta method's normal
# approximation breaks down in exactly that regime: it reports a deceptively
# tight [-0.28, 2.93] for the non-advantaged incumbent curve and blows up to
# +-13 for cross-partisan GOP. The simulation estimator degrades honestly --
# when there is no interior maximum the argmax lands on a boundary and the
# interval saturates to the full range of the measure, which is the correct
# statement that the turning point is not identified.
#
# Curves with a large share of boundary draws are drawn hollow and grey and
# labelled, so no reader compares turning points that do not exist.
suppressPackageStartupMessages(library(fixest))
set.seed(123)
m  <- readRDS(paste0(CSV, "ASYM_FULLCURVE_NOFE.RDS"))
cf <- coef(m); V <- vcov(m); NM <- names(cf)
rmv <- function(n, mu, S) { p <- length(mu); t(t(matrix(rnorm(n * p), n, p) %*% chol(S)) + mu) }
D   <- rmv(10000, cf, V)
fav <- seq(-4, 4, length.out = 200)

# Term combinations copied verbatim from asymmetric_peak_ci.R's lin_/quad_*_fc
# helpers, so the simulated curves are the curves the delta-method CSV
# describes. "NonIncumbent" is represented by the Challenger level, as there.
cn <- function(k) { if (!k %in% NM) stop("missing coef: ", k); D[, match(k, NM)] }
lin_of <- function(type, dummy) {
  v <- cn("favorability")
  if (!is.null(dummy)) v <- v + cn(paste0("favorability:", dummy))
  if (type == "NonIncumbent") {
    v <- v + cn("favorability:incumbencyC")
    if (!is.null(dummy)) v <- v + cn(paste0("favorability:", dummy, ":incumbency_binNonIncumbent"))
  }
  v
}
quad_of <- function(type, dummy) {
  v <- cn("favorability_sq")
  if (!is.null(dummy)) v <- v + cn(paste0("favorability_sq:", dummy))
  if (type == "NonIncumbent") {
    v <- v + cn("incumbencyC:favorability_sq")
    if (!is.null(dummy)) v <- v + cn(paste0("favorability_sq:", dummy, ":incumbency_binNonIncumbent"))
  }
  v
}
CURVES <- c("Other", "co_partisan_GOP", "cross_partisan_GOP", "co_partisan_DEM", "cross_partisan_DEM")
rows <- list()
for (ty in c("Incumbent", "NonIncumbent")) for (cv in CURVES) {
  d   <- if (cv == "Other") NULL else cv
  lin <- lin_of(ty, d); qd <- quad_of(ty, d)
  pk  <- apply(cbind(lin, qd), 1, function(r) fav[which.max(r[1] * fav + r[2] * fav^2)])
  li <- mean(lin); qi <- mean(qd)               # fitted curve, not a draw summary
  hat <- fav[which.max(li * fav + qi * fav^2)]
  rows[[length(rows) + 1]] <- data.frame(curve = cv, type = ty, peak = hat,
    ci_low = quantile(pk, 0.025), ci_high = quantile(pk, 0.975),
    edge = mean(pk <= -4 + 1e-9 | pk >= 4 - 1e-9), stringsAsFactors = FALSE)
}
f <- do.call(rbind, rows)
f$identified <- f$edge < 0.25
cat("\n=== simulation peaks (95%), share of draws at a grid boundary ===\n")
print(f[, c("curve","type","peak","ci_low","ci_high","edge","identified")], row.names = FALSE, digits = 3)

lbl <- c(Other = "Non-advantaged",
         co_partisan_GOP = "GOP sector,\nRepublican cand.",
         cross_partisan_GOP = "GOP sector,\nDemocratic cand.",
         co_partisan_DEM = "DEM sector,\nDemocratic cand.",
         cross_partisan_DEM = "DEM sector,\nRepublican cand.")
f$label <- factor(lbl[f$curve], levels = lbl)
f$color_group <- ifelse(grepl("GOP", f$curve), "GOP", ifelse(grepl("DEM", f$curve), "DEM", "Other"))
f$color_group <- factor(f$color_group, levels = c("Other", "GOP", "DEM"))
f$type <- factor(ifelse(f$type == "Incumbent", "Incumbents", "Challengers & open seats"),
                 levels = c("Incumbents", "Challengers & open seats"))
f$shown <- ifelse(f$identified, as.character(f$color_group), "unident")
pal <- c(palette5, unident = "grey65")

ann <- data.frame(type = factor("Incumbents", levels = levels(f$type)),
                  x = 0.5, y = 5.35,
                  txt = "grey bands: curve is flat, turning point not identified")

# Unidentified curves get the interval only. Drawing a point estimate for them
# would read as "the peak is at -4" when the argmax simply falls on whichever
# boundary each draw happens to favour.
fi <- f[f$identified, ]; fu <- f[!f$identified, ]

p2 <- ggplot(mapping = aes(x = label)) +
  geom_linerange(data = fu, aes(ymin = ci_low, ymax = ci_high),
                 color = "grey70", linewidth = 3.2, alpha = 0.55) +
  geom_pointrange(data = fi, aes(y = peak, ymin = ci_low, ymax = ci_high, color = color_group),
                  size = 0.85, linewidth = 1.05) +
  geom_text(data = ann, aes(x = x, y = y, label = txt), inherit.aes = FALSE,
            hjust = 0, family = "serif", size = 3.7, color = "grey35") +
  facet_wrap(~ type, nrow = 1) +
  scale_x_discrete(drop = FALSE) +
  scale_color_manual(values = palette5, guide = "none") +
  coord_cartesian(ylim = c(-4.4, 5.9)) +
  labs(x = NULL, y = "Chance of Winning at Predicted Peak") +
  clean_theme(17) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1),
        strip.text = element_text(face = "bold"))
ggsave(paste0(OUT, "Asymmetric_Peak_CI_ByType.png"), p2, width = 11, height = 7, dpi = 300)
cat("\nwrote Asymmetric_Peak_CI_ByType.png\n")
