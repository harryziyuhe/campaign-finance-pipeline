# Figure: the baseline contribution curve with no functional form imposed.
#
# Chance of Winning is entered as an unordered factor (rounded to the underlying
# nine-point scale) rather than a quadratic, so nothing about the shape is
# assumed. This is the paper's most direct answer to the objection that an
# inverse-U was assumed and then recovered, and it previously appeared only as
# numbers in the text.
#
# Reads BIMODAL_FACTOR.RDS (fit by bimodality_checks.R).

suppressPackageStartupMessages({ library(fixest); library(ggplot2) })
PATH <- "/htaa/hhe/projects/election_buying/"
OUT  <- paste0(PATH, "paper/figures/")

m  <- readRDS(paste0(PATH, "model/sector_alignment/BIMODAL_FACTOR.RDS"))
cf <- coef(m); se <- se(m)

lv  <- -4:4
est <- sapply(lv, function(k) if (k == -4) 0 else {
  n <- paste0("fav_f", k); if (n %in% names(cf)) cf[[n]] else NA_real_ })
ses <- sapply(lv, function(k) if (k == -4) 0 else {
  n <- paste0("fav_f", k); if (n %in% names(se)) se[[n]] else NA_real_ })
stopifnot(!any(is.na(est)))

d <- data.frame(fav = lv, est = est, lo = est - 1.96*ses, hi = est + 1.96*ses)

p <- ggplot(d, aes(fav, est)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), fill = "grey70", alpha = 0.35) +
  geom_line(linewidth = 0.9, colour = "grey20") +
  geom_point(size = 2.4, colour = "grey20") +
  scale_x_continuous(breaks = lv) +
  labs(x = "Chance of Winning",
       y = "Fitted contribution propensity\n(log-odds vs. least favorable)",
       caption = paste("Chance of Winning entered as an unordered factor; no functional form imposed.",
                       "\nShaded band is a 95% confidence interval. Reference category is the least favorable value.")) +
  theme_minimal(base_size = 13) +
  theme(panel.grid.minor = element_blank(),
        plot.caption = element_text(hjust = 0, size = 10))

ggsave(paste0(OUT, "Nonparametric_Shape.png"), p, width = 8, height = 5, dpi = 300)
cat("wrote Nonparametric_Shape.png\n")
print(d, digits = 4)
cat("\nDone.\n")
