library(fixest)
library(ggplot2)
library(dplyr)

# =============================================================================
# Presentation-only variant of Asymmetric_Coefplot_Incumbency.png (produced by
# asymmetric_figures.R) showing ONLY the categorical measure, single panel, no
# free-x facet split against the continuous measure -- easier to talk through
# on a slide than the two-facet paper version. Same terms/model/CI logic as
# the paper figure; just drops the continuous-measure facet.
# =============================================================================
PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "paper/figures/")
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

COEF_TERMS <- tribble(
  ~term_label,                         ~color_group, ~partisan_type,   ~cand_type,   ~term_cat,
  "GOP, Challenger",                   "GOP",        "co-partisan",    "Challenger", "incumbencyC:co_partisan_GOP",
  "GOP, Open Seat",                    "GOP",        "co-partisan",    "Open Seat",  "incumbencyO:co_partisan_GOP",
  "GOP, Challenger",                   "GOP",        "cross-partisan", "Challenger", "incumbencyC:cross_partisan_GOP",
  "GOP, Open Seat",                    "GOP",        "cross-partisan", "Open Seat",  "incumbencyO:cross_partisan_GOP",
  "DEM, Challenger",                   "DEM",        "co-partisan",    "Challenger", "incumbencyC:co_partisan_DEM",
  "DEM, Open Seat",                    "DEM",        "co-partisan",    "Open Seat",  "incumbencyO:co_partisan_DEM",
  "DEM, Challenger",                   "DEM",        "cross-partisan", "Challenger", "incumbencyC:cross_partisan_DEM",
  "DEM, Open Seat",                    "DEM",        "cross-partisan", "Open Seat",  "incumbencyO:cross_partisan_DEM"
)

mod_inc_cat <- readRDS(paste0(PATH, "model/sector_alignment/ASYM_INCUMBENCY_CATEGORICAL.RDS"))

cf <- coef(mod_inc_cat); V <- vcov(mod_inc_cat)
coef_df <- COEF_TERMS %>%
  rowwise() %>%
  mutate(term = term_cat,
         est = cf[[term]],
         se  = sqrt(V[term, term]),
         ci_low  = est - 1.96 * se,
         ci_high = est + 1.96 * se) %>%
  ungroup()

coef_df$color_group <- factor(coef_df$color_group, levels = c("GOP", "DEM"))
coef_df$row_label <- paste(coef_df$cand_type, coef_df$partisan_type, sep = " -- ")
coef_df$row_label <- factor(coef_df$row_label, levels = rev(unique(coef_df$row_label)))

coef_plot_cat <- ggplot(coef_df, aes(x = est, y = row_label, color = color_group, shape = partisan_type)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey50", linewidth = 0.5) +
  geom_pointrange(aes(xmin = ci_low, xmax = ci_high), size = 1.0, linewidth = 1.3,
                   position = position_dodge(width = 0.5)) +
  scale_color_manual(name = "Sector alignment", values = c(GOP = "firebrick", DEM = "steelblue")) +
  scale_shape_manual(name = "Candidate's party", values = c(`co-partisan` = 16, `cross-partisan` = 17)) +
  labs(x = "Coefficient (relative to Incumbent), 95% CI", y = NULL) +
  clean_theme(19) +
  theme(legend.position = "bottom", legend.box = "vertical",
        panel.grid.major.y = element_blank(),
        panel.grid.major.x = element_line(color = "grey85", linewidth = 0.3))

ggsave(paste0(OUT_DIR, "Asymmetric_Coefplot_Incumbency_Categorical.png"),
       coef_plot_cat, width = 10, height = 7, dpi = 300)

cat("Wrote", paste0(OUT_DIR, "Asymmetric_Coefplot_Incumbency_Categorical.png"), "\n")
