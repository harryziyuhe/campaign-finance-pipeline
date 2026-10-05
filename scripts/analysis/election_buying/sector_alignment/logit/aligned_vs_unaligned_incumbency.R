library(fixest)
library(ggplot2)
library(dplyr)

# =============================================================================
# Replacement/companion for Asymmetric_Coefplot_Incumbency_Categorical.png.
#
# The coefficient plot shows the raw incumbency x alignment interaction terms
# (incumbencyC:co_partisan_GOP etc.). Those are difference-in-differences: to
# read one you must mentally add back incumbencyC (-2.45) and co_partisan_GOP
# (+0.20). Nothing on that axis is a claim.
#
# This figure plots the claim instead: how much more likely is an ALIGNED firm
# to contribute than an UNALIGNED firm, to the SAME candidate? Because the
# reference sector category is "Other" (unaligned), that is exactly
#
#   L'beta  where  L = 1 on  <dummy>
#                    + FAV_ANCHOR      on  favorability:<dummy>
#                    + FAV_ANCHOR^2    on  favorability_sq:<dummy>
#                    + 1 on incumbency{C,O}:<dummy>   (0 for incumbents)
#
# for <dummy> in {co,cross}_partisan_{GOP,DEM}. Holding the candidate fixed and
# swapping the firm, everything else in the model -- candidate party, the
# favorability level itself, controls, state and year FE -- cancels, so the
# contrast is a single odds ratio against a benchmark that can be stated in
# words ("same as a firm with no sector stake in the race").
#
# CHOICE OF FAVORABILITY ANCHOR (matters a lot -- see below). The favorability
# interactions do NOT cancel, so the contrast is a function of favorability and
# some anchor must be chosen. We use favorability = 0, which makes each point
# here EXACTLY the corresponding Table 3 coefficient combination -- figure and
# table then report the same estimand.
#
# The alternative, averaging over the estimation sample, is NOT used, and the
# reason is specific to this variable: favorability is censored at +/-4 and 81%
# of the sample sits at exactly one endpoint or the other (37.3% at -4, 43.9%
# at +4), so mean(favorability^2) = 13.96, nowhere near mean(favorability)^2 =
# 0.07. The sample-average contrast therefore puts weight ~14 on the
# favorability_sq:<dummy> terms, which is precisely where the quadratic is
# extrapolating hardest and is least well identified. For co_partisan_DEM
# (327 incumbent contributions) that alone moved the estimate 0.879 -> 0.490
# and the SE 0.205 -> 0.401, flipping p from 1.8e-05 to 0.22.
#
# Caveat that belongs in any writeup: favorability = 0 is the scale midpoint but
# only ~2.6% of the sample lies within +/-0.5 of it. The qualitative pattern the
# figure is for -- aligned firms above the unaligned benchmark, and more so off
# incumbency -- holds at the anchor, at the sample average and at the median.
#
# NOTE ON ADJUSTMENT: this must be the model-adjusted contrast. Raw rate ratios
# have the right shape (rising off incumbency in both blocs) but the DEM-
# aligned levels sit well below 1, because aligned and unaligned firms are not
# comparable populations -- log(firm_cash) alone carries a coefficient of 0.97
# and the DEM-aligned bloc is ~14k firm-candidate pairs of much smaller firms
# against ~1.2M unaligned pairs. A raw-rate version of this slide would
# contradict the claim on the DEM side. Hence the caption.
# =============================================================================
PATH    <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "paper/figures/")
MOD     <- paste0(PATH, "model/sector_alignment/ASYM_INCUMBENCY_CATEGORICAL.RDS")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

clean_theme <- function(base_size) {
  theme_minimal(base_size = base_size) +
    theme(text = element_text(family = "serif"),
          panel.grid.minor = element_blank(),
          panel.grid.major.x = element_blank(),
          panel.grid.major.y = element_line(color = "grey85", linewidth = 0.3),
          axis.line.x = element_line(color = "grey40", linewidth = 0.4),
          axis.ticks.x = element_line(color = "grey40", linewidth = 0.4))
}

# --- model: only coef/vcov/estimation-sample indices are needed --------------
mod <- readRDS(MOD)
cf  <- coef(mod)
V   <- vcov(mod)
keep <- mod$obs_selection$obsRemoved   # negative indices of dropped obs
rm(mod); invisible(gc())

# --- estimation-sample favorability moments and cell counts ------------------
cand_data <- readRDS(paste0(PATH, "cand_model_data.RDS"))
cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre,
                                            levels = c("Other", "GOP", "DEM"))
cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "O", "C"))
cand_data$party      <- factor(cand_data$party, levels = c("DEMOCRAT", "REPUBLICAN"))
est_sample <- if (length(keep)) cand_data[keep, ] else cand_data
stopifnot(nrow(est_sample) == 6800325)

# Anchor for the favorability interactions (see header). 0 == Table 3 estimand.
FAV_ANCHOR <- 0

fav_bar   <- mean(est_sample$favorability, na.rm = TRUE)
favsq_bar <- mean(est_sample$favorability^2, na.rm = TRUE)
cat(sprintf("estimation sample: n=%d  mean(fav)=%.4f  mean(fav^2)=%.4f\n",
            nrow(est_sample), fav_bar, favsq_bar))
cat(sprintf("share of sample at |favorability|=4: %.3f   within +/-0.5 of 0: %.3f\n",
            mean(abs(est_sample$favorability) == 4, na.rm = TRUE),
            mean(abs(est_sample$favorability) < 0.5, na.rm = TRUE)))
cat(sprintf("contrasts evaluated at favorability = %g\n", FAV_ANCHOR))

est_sample$dummy <- with(est_sample, case_when(
  singlename_partisan_pre == "GOP" & party == "REPUBLICAN" ~ "co_partisan_GOP",
  singlename_partisan_pre == "GOP" & party == "DEMOCRAT"   ~ "cross_partisan_GOP",
  singlename_partisan_pre == "DEM" & party == "DEMOCRAT"   ~ "co_partisan_DEM",
  singlename_partisan_pre == "DEM" & party == "REPUBLICAN" ~ "cross_partisan_DEM",
  TRUE ~ NA_character_))
counts <- est_sample %>% filter(!is.na(dummy)) %>%
  group_by(dummy, incumbency) %>%
  summarise(n = n(), events = sum(contribute), .groups = "drop")

# --- contrast grid ----------------------------------------------------------
CELLS <- tribble(
  ~dummy,                ~bloc,         ~ptype,
  "co_partisan_GOP",     "GOP-aligned", "Co-partisan",
  "cross_partisan_GOP",  "GOP-aligned", "Cross-partisan",
  "co_partisan_DEM",     "DEM-aligned", "Co-partisan",
  "cross_partisan_DEM",  "DEM-aligned", "Cross-partisan"
)
INC <- tribble(
  ~incumbency, ~inc_label,
  "I",         "Incumbent",
  "O",         "Open seat",
  "C",         "Challenger"
)

# L'beta for "aligned firm vs. unaligned firm, same candidate", by cell x status
contrast <- function(dummy, inc) {
  L <- setNames(numeric(length(cf)), names(cf))
  L[dummy]                                   <- 1
  L[paste0("favorability:", dummy)]          <- FAV_ANCHOR
  L[paste0("favorability_sq:", dummy)]       <- FAV_ANCHOR^2
  if (inc != "I") L[paste0("incumbency", inc, ":", dummy)] <- 1
  stopifnot(!any(is.na(L)))
  est <- sum(L * cf)
  se  <- sqrt(drop(t(L) %*% V %*% L))
  c(est = est, se = se)
}

grid <- tidyr::crossing(CELLS, INC)
cc   <- t(mapply(contrast, grid$dummy, grid$incumbency))
plot_df <- grid %>%
  mutate(est = cc[, "est"], se = cc[, "se"]) %>%
  mutate(or       = exp(est),
         or_low   = exp(est - 1.96 * se),
         or_high  = exp(est + 1.96 * se),
         z        = est / se,
         p        = 2 * pnorm(-abs(z))) %>%
  left_join(counts, by = c("dummy", "incumbency")) %>%
  mutate(inc_label = factor(inc_label, levels = INC$inc_label),
         bloc      = factor(bloc, levels = c("GOP-aligned", "DEM-aligned")),
         ptype     = factor(ptype, levels = c("Co-partisan", "Cross-partisan")),
         series    = interaction(bloc, ptype, sep = " / "))

cat("\n=== aligned vs. unaligned firm, same candidate (odds ratio) ===\n")
print(as.data.frame(plot_df %>% select(bloc, ptype, inc_label, n, events,
                                       est, se, or, or_low, or_high, p)),
      digits = 4)
write.csv(plot_df %>% select(bloc, ptype, incumbency, inc_label, n, events,
                             est, se, or, or_low, or_high, z, p),
          paste0(OUT_DIR, "Aligned_vs_Unaligned_Incumbency.csv"), row.names = FALSE)

# --- figure -----------------------------------------------------------------
BREAKS <- c(0.125, 0.25, 0.5, 1, 2, 4)
BRLABS <- c("0.13×", "0.25×", "0.5×", "1×", "2×", "4×")
dodge  <- position_dodge(width = 0.36)

p_fig <- ggplot(plot_df, aes(x = inc_label, y = or, color = bloc,
                             shape = ptype, group = series)) +
  geom_hline(yintercept = 1, color = "grey35", linewidth = 0.6) +
  # No connecting lines: incumbency is an unordered categorical contrast, and
  # the interpolated segments read as a trend that is not being estimated.
  geom_pointrange(aes(ymin = or_low, ymax = or_high), position = dodge,
                  size = 0.85, linewidth = 1.2, fill = "white", stroke = 1.2) +
  # the reference line is labelled on a secondary axis rather than in-panel:
  # the incumbent points sit right at 1.0, so an in-panel label collides.
  scale_y_continuous(trans = "log2", breaks = BREAKS, labels = BRLABS,
                     sec.axis = dup_axis(breaks = 1, name = NULL,
                                         labels = "same as an\nunaligned firm")) +
  scale_color_manual(name = "Firm's sector",
                     values = c(`GOP-aligned` = "firebrick",
                                `DEM-aligned` = "steelblue")) +
  # solid marker = co-partisan (the claim); hollow = cross-partisan (contrast)
  scale_shape_manual(name = "Candidate",
                     values = c(`Co-partisan` = 16, `Cross-partisan` = 21)) +
  guides(color = guide_legend(order = 1, override.aes = list(shape = 16)),
         shape = guide_legend(order = 2, override.aes = list(color = "grey25"))) +
  # No in-figure caption: the anchor, clustering and thin-cell counts belong in
  # the LaTeX/slide caption instead. Wording to reuse there --
  #   "Candidate held fixed, firm swapped; adjusted for firm size, home state and
  #    state x year FE, evaluated at favorability = 0. 95% CI, SEs clustered by
  #    committee and candidate. DEM-aligned non-incumbent cells rest on 12
  #    (open seat) and 7 (challenger) contributions."
  labs(x = NULL,
       y = "Odds of contributing vs.\nan unaligned firm") +
  clean_theme(17) +
  theme(legend.position = "bottom", legend.box = "vertical",
        legend.spacing.y = unit(0, "pt"),
        plot.margin = margin(10, 12, 8, 10),
        axis.title.y = element_text(margin = margin(r = 8)),
        axis.text.y.right = element_text(size = 11.5, color = "grey35",
                                         hjust = 0, lineheight = 0.9),
        panel.grid.major.x = element_blank())

ggsave(paste0(OUT_DIR, "Aligned_vs_Unaligned_Incumbency.png"),
       p_fig, width = 10.5, height = 7.5, dpi = 300)
cat("\nWrote", paste0(OUT_DIR, "Aligned_vs_Unaligned_Incumbency.png"), "\n")
cat("Wrote", paste0(OUT_DIR, "Aligned_vs_Unaligned_Incumbency.csv"), "\n")
