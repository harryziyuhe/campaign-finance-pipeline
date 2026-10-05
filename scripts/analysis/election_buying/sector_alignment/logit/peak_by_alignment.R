# Figure 3 replacement: peak location (and CI) by sectoral partisan alignment.
#
# The old Figure 3 drew three predicted-probability curves -- GOP-advantaged,
# DEM-advantaged, and non-advantaged -- against chance of winning. The claim
# the surrounding prose actually makes is about where each curve peaks, so
# plot the three peaks with CIs directly instead of asking the reader to read
# turning points off three overlapping curves.
#
# Specification matches the baseline battery in asymmetric_pooled_nofe.R:
# same controls, same state + year FE, same two-way clustering. The only
# change is that the quadratic is interacted with the three-level alignment
# group rather than with the co-/cross-partisan dummies.

suppressPackageStartupMessages({ library(dplyr); library(fixest) })
PATH <- "/htaa/hhe/projects/election_buying/"
OUT  <- paste0(PATH, "model/sector_alignment/")
source(paste0(PATH, "scripts/sector_alignment/logit/peak_helpers.R"))

d <- readRDS(paste0(PATH, "cand_model_data_v2.RDS"))
d$singlename_partisan_pre[trimws(d$singlename_partisan_pre) == ""] <- NA_character_
d <- d %>% filter(!is.na(singlename_partisan_pre))
d$align <- factor(d$singlename_partisan_pre, levels = c("Other", "GOP", "DEM"))
d$incumbency <- factor(d$incumbency, levels = c("I", "C", "O"))
d$party      <- factor(d$party, levels = c("DEMOCRAT", "REPUBLICAN"))

cat("=== group sizes ===\n")
print(d %>% group_by(align) %>%
      summarise(firms = n_distinct(cmte_id), dyads = n(),
                events = sum(contribute == 1, na.rm = TRUE),
                rate = round(100 * mean(contribute == 1, na.rm = TRUE), 3),
                .groups = "drop") %>% as.data.frame())

base_controls <- "special + private + foreign + same_state + log(firm_cash) + party + incumbency"
rhs <- paste(base_controls, "(favorability + favorability_sq) * align", sep = " + ")

cat("\nfitting three-group baseline...\n")
t0 <- Sys.time()
m <- feglm(as.formula(paste("contribute ~", rhs, "| state + year")),
           data = d, family = binomial("logit"), cluster = ~ cmte_id + candidate_id)
cat(sprintf("  fit time: %.2f min\n", as.numeric(Sys.time() - t0, units = "mins")))
saveRDS(m, paste0(OUT, "PEAK_BY_ALIGNMENT.RDS"))
writeLines(capture.output(summary(m)), paste0(OUT, "PEAK_BY_ALIGNMENT_coefficients.txt"))
cat("N =", format(nobs(m), big.mark = ","), "\n")

cf <- coef(m); V <- vcov(m)
curves <- list(
  `Non-advantaged`  = list(lin = "favorability",
                           quad = "favorability_sq"),
  `GOP-advantaged`  = list(lin = c("favorability", "favorability:alignGOP"),
                           quad = c("favorability_sq", "favorability_sq:alignGOP")),
  `DEM-advantaged`  = list(lin = c("favorability", "favorability:alignDEM"),
                           quad = c("favorability_sq", "favorability_sq:alignDEM"))
)
rows <- lapply(names(curves), function(nm) {
  r <- peak_for_curve(cf, V, curves[[nm]]$lin, curves[[nm]]$quad)
  data.frame(group = nm, peak = as.numeric(r[["est"]]), se = as.numeric(r[["se"]]),
             ci_low = as.numeric(r[["ci_low"]]), ci_high = as.numeric(r[["ci_high"]]),
             flag = r[["flag"]], stringsAsFactors = FALSE)
})
tab <- do.call(rbind, rows)
write.csv(tab, paste0(OUT, "peak_by_alignment.csv"), row.names = FALSE)
cat("\n=== peak location by sectoral alignment (delta method, 95% CI) ===\n")
print(tab, row.names = FALSE, digits = 4)

# Pairwise: is each advantaged group's peak different from non-advantaged?
# Test the difference directly -- never compare two marginal CIs for overlap.
cat("\n=== peak difference vs non-advantaged ===\n")
for (nm in c("GOP-advantaged", "DEM-advantaged")) {
  lin_a <- curves[[nm]]$lin; quad_a <- curves[[nm]]$quad
  dfn <- function(cf) {
    peak_fn(sum(sapply(lin_a, function(t) g(cf, t))), sum(sapply(quad_a, function(t) g(cf, t)))) -
    peak_fn(g(cf, "favorability"), g(cf, "favorability_sq"))
  }
  r <- delta_method(cf, V, dfn)
  cat(sprintf("  %-16s diff=%+.3f  se=%.3f  p=%.4g\n",
              nm, r[["est"]], r[["se"]], 2 * pnorm(-abs(r[["est"]] / r[["se"]]))))
}
cat("\nDone.\n")
