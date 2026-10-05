library(dplyr)

PATH <- "/htaa/hhe/projects/election_buying/"
cand_data <- readRDS(paste0(PATH, "cand_model_data.RDS"))
cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre, levels = c("Other", "GOP", "DEM"))

# ---------------------------------------------------------------------------
# Wrinkle #1: is score_cross_DEM/score_co_DEM being driven by weak, diffuse
# near-zero-negative-score sectors (e.g. Consumer Products) rather than
# genuinely DEM-leaning sectors (Renewables)?
# ---------------------------------------------------------------------------
cat("=== current (post-fix) score_pre distribution by category, DEM-leaning (score<0) side ===\n")
by_cat <- cand_data %>%
  filter(!is.na(category)) %>%
  group_by(category) %>%
  summarise(
    score = first(singlename_score_pre),
    partisan_label = first(as.character(singlename_partisan_pre)),
    n = n(),
    n_firms = n_distinct(cmte_id),
    .groups = "drop"
  ) %>%
  filter(score < 0) %>%
  arrange(score)
print(as.data.frame(by_cat), row.names = FALSE)

cat("\n=== leverage decomposition: sum(|score| * n) by category, DEM side ===\n")
cat("(this approximates each category's contribution to the score_co_DEM/score_cross_DEM coefficient)\n")
by_cat_lev <- by_cat %>%
  mutate(leverage = abs(score) * n) %>%
  arrange(desc(leverage)) %>%
  mutate(pct_of_total = 100 * leverage / sum(leverage))
print(as.data.frame(by_cat_lev), row.names = FALSE)

cat("\n=== restricting continuous DEM variables to categorically-DEM sectors only ===\n")
cand_data$score_co_DEM_all    <- pmax(-cand_data$singlename_score_pre, 0) * (cand_data$party == "DEMOCRAT")
cand_data$score_cross_DEM_all <- pmax(-cand_data$singlename_score_pre, 0) * (cand_data$party == "REPUBLICAN")
cand_data$score_co_DEM_restricted    <- cand_data$score_co_DEM_all    * (cand_data$singlename_partisan_pre == "DEM")
cand_data$score_cross_DEM_restricted <- cand_data$score_cross_DEM_all * (cand_data$singlename_partisan_pre == "DEM")

cat("N with score_co_DEM_all > 0:          ", sum(cand_data$score_co_DEM_all > 0), "\n")
cat("N with score_co_DEM_restricted > 0:   ", sum(cand_data$score_co_DEM_restricted > 0), "\n")
cat("N with score_cross_DEM_all > 0:       ", sum(cand_data$score_cross_DEM_all > 0), "\n")
cat("N with score_cross_DEM_restricted > 0:", sum(cand_data$score_cross_DEM_restricted > 0), "\n")

cat("\nCategories contributing to score_co_DEM_all>0 but NOT categorically DEM:\n")
leak <- cand_data %>%
  filter(score_co_DEM_all > 0, singlename_partisan_pre != "DEM") %>%
  count(category, sort = TRUE)
print(as.data.frame(leak), row.names = FALSE)

# ---------------------------------------------------------------------------
# Wrinkle #2: what composes the thin cross_partisan_GOP x NonIncumbent x
# contribute=1 cell (648 events)? Concentrated in a few firms/candidates, or
# diffuse?
# ---------------------------------------------------------------------------
cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))
cand_data$cross_partisan_GOP <- as.integer(cand_data$party == "DEMOCRAT" & cand_data$singlename_partisan_pre == "GOP")

cell <- cand_data %>% filter(cross_partisan_GOP == 1, incumbency != "I", contribute == 1)
cat("\n=== Wrinkle #2: cross_partisan_GOP x NonIncumbent x contribute=1 cell (n=", nrow(cell), ") ===\n")
cat("n distinct firms:     ", n_distinct(cell$cmte_id), "of", n_distinct(cand_data$cmte_id[cand_data$cross_partisan_GOP==1]), "eligible\n")
cat("n distinct candidates:", n_distinct(cell$candidate_id), "\n")
cat("n distinct years:     ", n_distinct(cell$year), "\n")

cat("\nTop firms by event count in this cell:\n")
print(as.data.frame(cell %>% count(cmte_id, sort = TRUE) %>% head(15)), row.names = FALSE)

cat("\nEvent count by favorability level in this cell:\n")
print(as.data.frame(cell %>% count(favorability, sort = TRUE)), row.names = FALSE)

cat("\nEvent count by category (firm sector) in this cell:\n")
print(as.data.frame(cell %>% count(category, sort = TRUE)), row.names = FALSE)

cat("\nEvent count by year in this cell:\n")
print(as.data.frame(cell %>% count(year, sort = TRUE)), row.names = FALSE)

# ---------------------------------------------------------------------------
# Direct test: does the score_cross_DEM/score_co_DEM finding survive when
# restricted to categorically-DEM sectors only (i.e., essentially Renewables)?
# ---------------------------------------------------------------------------
library(fixest)
cand_data$party <- factor(cand_data$party, levels = c("DEMOCRAT", "REPUBLICAN"))
cand_data$co_partisan_GOP    <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "GOP")
cand_data$cross_partisan_GOP <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "GOP")
singlename_GOP_pre <- pmax(cand_data$singlename_score_pre, 0)
cand_data$score_co_GOP    <- singlename_GOP_pre * (cand_data$party == "REPUBLICAN")
cand_data$score_cross_GOP <- singlename_GOP_pre * (cand_data$party == "DEMOCRAT")
cand_data$score_co_DEM_restricted    <- cand_data$score_co_DEM_all    * as.integer(cand_data$singlename_partisan_pre == "DEM")
cand_data$score_cross_DEM_restricted <- cand_data$score_cross_DEM_all * as.integer(cand_data$singlename_partisan_pre == "DEM")

cat("\nN with score_co_DEM_all > 0:          ", sum(cand_data$score_co_DEM_all > 0, na.rm = TRUE), "\n")
cat("N with score_co_DEM_restricted > 0:   ", sum(cand_data$score_co_DEM_restricted > 0, na.rm = TRUE), "\n")
cat("N with score_cross_DEM_all > 0:       ", sum(cand_data$score_cross_DEM_all > 0, na.rm = TRUE), "\n")
cat("N with score_cross_DEM_restricted > 0:", sum(cand_data$score_cross_DEM_restricted > 0, na.rm = TRUE), "\n")

base_controls <- "special + private + foreign + same_state + log(firm_cash) + party + incumbency"
rhs_restricted <- paste(
  base_controls,
  "favorability + favorability_sq",
  "co_partisan_GOP + favorability:co_partisan_GOP + favorability_sq:co_partisan_GOP",
  "cross_partisan_GOP + favorability:cross_partisan_GOP + favorability_sq:cross_partisan_GOP",
  "score_co_DEM_restricted + favorability:score_co_DEM_restricted + favorability_sq:score_co_DEM_restricted",
  "score_cross_DEM_restricted + favorability:score_cross_DEM_restricted + favorability_sq:score_cross_DEM_restricted",
  "score_co_DEM_restricted:incumbency + score_cross_DEM_restricted:incumbency",
  sep = " + "
)
fmla <- as.formula(paste("contribute ~", rhs_restricted, "| state + year"))
cat("\nFitting DEM-restricted-to-categorical-DEM continuous model...\n")
mod_r <- feglm(fmla, data = cand_data, family = binomial(link = "logit"), cluster = ~ cmte_id + candidate_id)
cf <- coef(mod_r); V <- vcov(mod_r)
get_row <- function(nm) {
  if (!nm %in% names(cf)) return(sprintf("%s: MISSING", nm))
  est <- cf[[nm]]; s <- sqrt(V[nm, nm])
  sprintf("%-45s est=%.4f se=%.4f p=%.4g", nm, est, s, 2 * pnorm(-abs(est / s)))
}
cat("\n=== DEM-restricted-to-categorical-DEM results (should collapse toward the clean categorical estimate) ===\n")
for (nm in c("score_co_DEM_restricted", "score_cross_DEM_restricted",
             "favorability:score_co_DEM_restricted", "favorability_sq:score_co_DEM_restricted",
             "favorability:score_cross_DEM_restricted", "favorability_sq:score_cross_DEM_restricted",
             "incumbencyC:score_co_DEM_restricted", "incumbencyO:score_co_DEM_restricted",
             "incumbencyC:score_cross_DEM_restricted", "incumbencyO:score_cross_DEM_restricted")) {
  cat(get_row(nm), "\n")
}
