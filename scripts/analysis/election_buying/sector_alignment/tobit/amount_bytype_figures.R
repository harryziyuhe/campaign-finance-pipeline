# Two candidate figures for the contribution-amount (Tobit) section, both from
# ASYM_TOBIT_FULLCURVE_CATEGORICAL. Produces both so they can be compared on
# the evidence rather than chosen in advance; the paper is not modified here.
#
#  A) Amount_Cell_Direct.png -- the dollar-scale analog of Cell_Direct_Effects.
#     At each Chance of Winning, the predicted difference in latent
#     contribution amount between an aligned firm and a non-advantaged firm
#     facing the SAME candidate. Because the latent scale of a gaussian Tobit
#     is dollars, this difference is read directly in dollars; no odds ratio
#     and no exponentiation is involved.
#
#  B) Amount_Peak_ByType.png -- the dollar-scale analog of
#     Asymmetric_Peak_CI_ByType. Where each amount curve reaches its maximum,
#     by candidate type.
#
# Peak intervals use the simulation estimator (10,000 draws, argmax of each
# simulated curve), matching the convention the extensive-margin by-type
# figure settled on, because the peak is a ratio whose denominator goes to
# zero as a curve flattens and the delta method is unreliable there.
suppressPackageStartupMessages({ library(ggplot2); library(dplyr) })

PATH <- "/htaa/hhe/projects/election_buying/"
OUT  <- paste0(PATH, "model/sector_alignment/")
FIG  <- paste0(PATH, "paper/figures/")
source(paste0(PATH, "scripts/sector_alignment/logit/peak_helpers.R"))

obj <- readRDS(paste0(OUT, "ASYM_TOBIT_FULLCURVE_CATEGORICAL.RDS"))
cf  <- coef(obj$model)
V   <- align_vcov(cf, obj$vcov_cluster)          # drops the Log(scale) row/col
stopifnot(length(cf) == nrow(V))

# survreg orders interaction parts by how the formula was written, which need
# not match the logit model's order. Resolve each wanted term to the name the
# model actually carries, and fail loudly if it carries none.
resolve <- function(nm) {
  p <- strsplit(nm, ":")[[1]]
  hit <- names(cf)[sapply(names(cf), function(k) setequal(strsplit(k, ":")[[1]], p))]
  if (!length(hit)) stop("missing coef: ", nm)
  hit[1]
}
gg <- function(cf, nm) cf[[resolve(nm)]]

CURVES <- c("co_partisan_GOP", "cross_partisan_GOP", "co_partisan_DEM", "cross_partisan_DEM")
FAV <- seq(-4, 4, length.out = 200)

# ---- A) dollar difference vs non-advantaged, same candidate type ------------
# lvl/lin/quad of the ALIGNED-minus-BASELINE contrast. The baseline curve
# cancels: what is left is exactly the alignment dummy's own terms.
parts <- function(dummy, type) {
  lvl  <- function(cf) gg(cf, dummy)
  lin  <- function(cf) gg(cf, paste0("favorability:", dummy))
  qd   <- function(cf) gg(cf, paste0("favorability_sq:", dummy))
  if (type == "NonIncumbent") {
    lvl0 <- lvl; lin0 <- lin; qd0 <- qd
    lvl <- function(cf) lvl0(cf) + gg(cf, paste0(dummy, ":incumbency_binNonIncumbent"))
    lin <- function(cf) lin0(cf) + gg(cf, paste0("favorability:", dummy, ":incumbency_binNonIncumbent"))
    qd  <- function(cf) qd0(cf)  + gg(cf, paste0("favorability_sq:", dummy, ":incumbency_binNonIncumbent"))
  }
  list(lvl = lvl, lin = lin, quad = qd)
}

GRID <- c(-4, -3, -2, -1, 0, 1, 2, 3, 4)
rows <- list()
for (ty in c("Incumbent", "NonIncumbent")) for (dm in CURVES) {
  p <- parts(dm, ty)
  for (f in GRID) {
    r <- delta_method(cf, V, function(cf) p$lvl(cf) + p$lin(cf) * f + p$quad(cf) * f^2)
    rows[[length(rows) + 1]] <- data.frame(
      dummy = dm, type = ty, favorability = f,
      diff = r[["est"]], se = r[["se"]], lo = r[["ci_low"]], hi = r[["ci_high"]],
      p = 2 * pnorm(-abs(r[["est"]] / r[["se"]])), stringsAsFactors = FALSE)
  }
}
A <- do.call(rbind, rows)
write.csv(A, paste0(OUT, "amount_cell_direct.csv"), row.names = FALSE)
cat("=== A) dollar difference vs non-advantaged, same candidate type ===\n")
print(A[A$dummy %in% c("co_partisan_GOP", "co_partisan_DEM"),
        c("dummy","type","favorability","diff","lo","hi","p")], row.names = FALSE, digits = 4)

# ---- B) peak location by candidate type, simulation -------------------------
set.seed(123)
rmv <- function(n, mu, S) { p <- length(mu); t(t(matrix(rnorm(n * p), n, p) %*% chol(S)) + mu) }
Vs <- V + diag(1e-10, nrow(V))                    # guard chol() on a near-singular clustered vcov
DR <- rmv(10000, cf, Vs)
colnames(DR) <- names(cf)
cn <- function(k) DR[, resolve(k)]

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
prows <- list()
for (ty in c("Incumbent", "NonIncumbent")) for (cv in c("Other", CURVES)) {
  dmy <- if (cv == "Other") NULL else cv
  lin <- lin_of(ty, dmy); qd <- quad_of(ty, dmy)
  pk  <- apply(cbind(lin, qd), 1, function(r) FAV[which.max(r[1] * FAV + r[2] * FAV^2)])
  li <- mean(lin); qi <- mean(qd)
  prows[[length(prows) + 1]] <- data.frame(
    curve = cv, type = ty, peak = FAV[which.max(li * FAV + qi * FAV^2)],
    ci_low = quantile(pk, 0.025), ci_high = quantile(pk, 0.975),
    edge = mean(pk <= -4 + 1e-9 | pk >= 4 - 1e-9), stringsAsFactors = FALSE)
}
B <- do.call(rbind, prows)
B$identified <- B$edge < 0.25
write.csv(B, paste0(OUT, "amount_peak_bytype.csv"), row.names = FALSE)
cat("\n=== B) amount-curve peak by candidate type (simulation, 95%) ===\n")
print(B, row.names = FALSE, digits = 3)

# ---- plotting ---------------------------------------------------------------
palette5 <- c(Other = "grey10", GOP = "firebrick", DEM = "steelblue")
clean_theme <- function(base_size) {
  theme_minimal(base_size = base_size) +
    theme(text = element_text(family = "serif"),
          panel.grid.minor = element_blank(),
          panel.grid.major.x = element_blank(),
          panel.grid.major.y = element_line(color = "grey85", linewidth = 0.3),
          axis.line.x = element_line(color = "grey40", linewidth = 0.4),
          axis.ticks.x = element_line(color = "grey40", linewidth = 0.4),
          strip.text = element_text(face = "bold"))
}

# A: co-partisan only, the two cells the location argument turns on, exactly
# as Cell_Direct_Effects does on the extensive margin.
Ap <- A[A$dummy %in% c("co_partisan_GOP", "co_partisan_DEM"), ]
Ap$party <- ifelse(grepl("GOP", Ap$dummy), "GOP", "DEM")
Ap$panel <- factor(ifelse(Ap$type == "Incumbent",
                          "Co-partisan incumbents", "Co-partisan non-incumbents"),
                   levels = c("Co-partisan incumbents", "Co-partisan non-incumbents"))
pA <- ggplot(Ap, aes(x = favorability, y = diff, color = party, fill = party)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50", linewidth = 0.5) +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.15, color = NA) +
  geom_line(linewidth = 1.3) + geom_point(size = 2) +
  facet_wrap(~panel) +
  scale_color_manual(name = "Sector alignment", values = c(GOP = "firebrick", DEM = "steelblue")) +
  scale_fill_manual(name = "Sector alignment", values = c(GOP = "firebrick", DEM = "steelblue")) +
  scale_y_continuous(labels = function(x) paste0("$", format(x, big.mark = ",", trim = TRUE))) +
  labs(x = "Chance of Winning",
       y = "Difference in contribution amount\n(aligned vs. non-advantaged, same candidate type)") +
  clean_theme(15) +
  theme(legend.position = "bottom", strip.text = element_text(face = "bold", size = rel(0.85)))
ggsave(paste0(FIG, "Amount_Cell_Direct.png"), pA, width = 9.5, height = 6.5, dpi = 300)
cat("\nwrote Amount_Cell_Direct.png\n")

lbl <- c(Other = "Non-advantaged",
         co_partisan_GOP = "GOP sector,\nRepublican cand.",
         cross_partisan_GOP = "GOP sector,\nDemocratic cand.",
         co_partisan_DEM = "DEM sector,\nDemocratic cand.",
         cross_partisan_DEM = "DEM sector,\nRepublican cand.")
B$label <- factor(lbl[B$curve], levels = lbl)
B$color_group <- factor(ifelse(grepl("GOP", B$curve), "GOP",
                        ifelse(grepl("DEM", B$curve), "DEM", "Other")),
                        levels = c("Other", "GOP", "DEM"))
B$type <- factor(ifelse(B$type == "Incumbent", "Incumbents", "Challengers & open seats"),
                 levels = c("Incumbents", "Challengers & open seats"))
bi <- B[B$identified, ]; bu <- B[!B$identified, ]
pB <- ggplot(mapping = aes(x = label)) +
  geom_linerange(data = bu, aes(ymin = ci_low, ymax = ci_high),
                 color = "grey70", linewidth = 3.2, alpha = 0.55) +
  geom_pointrange(data = bi, aes(y = peak, ymin = ci_low, ymax = ci_high, color = color_group),
                  size = 0.85, linewidth = 1.05) +
  facet_wrap(~ type, nrow = 1) +
  scale_x_discrete(drop = FALSE) +
  scale_color_manual(values = palette5, guide = "none") +
  coord_cartesian(ylim = c(-4.4, 4.4)) +
  labs(x = NULL, y = "Chance of Winning at Predicted Peak (amount)") +
  clean_theme(17) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1))
ggsave(paste0(FIG, "Amount_Peak_ByType.png"), pB, width = 11, height = 7, dpi = 300)
cat("wrote Amount_Peak_ByType.png\n")
cat("\nDone.\n")
