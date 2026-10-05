library(ggplot2)
library(dplyr)

PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "paper/figures/")
results <- read.csv(paste0(PATH, "model/sector_alignment/cell_direct_effects.csv"))

# Keep only the two cells the paper's location tests actually turn on:
# Cell 1 (co-partisan incumbents, the H2a test) and Cell 3 (co-partisan
# non-incumbents, the H2b test). Cell 2 (cross-partisan incumbents) carried no
# prediction and sat between the two panels the reader is meant to compare;
# Cell 4 is a clean null on the level test, so its location describes nothing.
# Both are dropped explicitly -- without this they fall through the labelling
# below as NA and are silently plotted as extra unlabelled panels.
results <- results[grepl("Cell [13]", results$cell), ]
stopifnot(nrow(results) > 0, !any(grepl("Cell [24]", results$cell)))

results$cell_short <- case_when(
  grepl("Cell 1", results$cell) ~ "Co-partisan incumbents",
  grepl("Cell 3", results$cell) ~ "Co-partisan non-incumbents"
)
results$cell_short <- factor(results$cell_short, levels = c(
  "Co-partisan incumbents", "Co-partisan non-incumbents"))
stopifnot(!any(is.na(results$cell_short)))
results$party <- ifelse(grepl("GOP", results$cell), "GOP", "DEM")

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

p <- ggplot(results, aes(x = favorability, y = or, color = party, fill = party)) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "grey50", linewidth = 0.5) +
  geom_ribbon(aes(ymin = or_lo, ymax = or_hi), alpha = 0.15, color = NA) +
  geom_line(linewidth = 1.3) +
  geom_point(size = 2) +
  facet_wrap(~cell_short) +
  scale_color_manual(name = "Sector alignment", values = c(GOP = "firebrick", DEM = "steelblue")) +
  scale_fill_manual(name = "Sector alignment", values = c(GOP = "firebrick", DEM = "steelblue")) +
  scale_y_log10(limits = c(0.05, 40), oob = scales::squish, breaks = c(0.1, 0.3, 1, 3, 10, 30)) +
  labs(x = "Chance of Winning", y = "Odds Ratio (aligned vs. non-advantaged,\nsame candidate type, log scale)") +
  clean_theme(15) +
  theme(legend.position = "bottom", strip.text = element_text(face = "bold", size = rel(0.85)))

ggsave(paste0(OUT_DIR, "Cell_Direct_Effects.png"), p, width = 9.5, height = 6.5, dpi = 300)
cat("Figure written.\n")
