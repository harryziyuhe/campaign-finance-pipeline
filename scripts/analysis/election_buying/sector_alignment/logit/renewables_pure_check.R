library(dplyr)
library(fixest)
PATH <- "/htaa/hhe/projects/election_buying/"
cand_data <- readRDS(paste0(PATH, "cand_model_data.RDS"))
cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))
cand_data$party <- factor(cand_data$party, levels = c("DEMOCRAT", "REPUBLICAN"))

# TRUE-pure Renewables-based co/cross-partisan dummies (category, not singlename_partisan_pre)
cand_data$co_partisan_DEM_pure    <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$category == "Renewables")
cand_data$cross_partisan_DEM_pure <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$category == "Renewables")

# also keep GOP dummies from singlename (unaffected, for a controlled comparison)
cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre, levels = c("Other","GOP","DEM"))
cand_data$co_partisan_GOP    <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "GOP")
cand_data$cross_partisan_GOP <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "GOP")

base_controls <- "special + private + foreign + same_state + log(firm_cash) + party + incumbency"
rhs <- paste(base_controls, "favorability + favorability_sq",
             "co_partisan_GOP + favorability:co_partisan_GOP + favorability_sq:co_partisan_GOP",
             "cross_partisan_GOP + favorability:cross_partisan_GOP + favorability_sq:cross_partisan_GOP",
             "co_partisan_DEM_pure + favorability:co_partisan_DEM_pure + favorability_sq:co_partisan_DEM_pure",
             "cross_partisan_DEM_pure + favorability:cross_partisan_DEM_pure + favorability_sq:cross_partisan_DEM_pure",
             "co_partisan_DEM_pure:incumbency + cross_partisan_DEM_pure:incumbency",
             sep = " + ")
fmla <- as.formula(paste("contribute ~", rhs, "| state + year"))
mod <- feglm(fmla, data = cand_data, family = binomial(link = "logit"), cluster = ~ cmte_id + candidate_id)
saveRDS(mod, paste0(PATH, "model/sector_alignment/ASYM_INCUMBENCY_RENEWABLES_PURE.RDS"))

cf <- coef(mod); V <- vcov(mod)
get_row <- function(nm) {
  if (!nm %in% names(cf)) return(cat(sprintf("%s: MISSING\n", nm)))
  est <- cf[[nm]]; s <- sqrt(V[nm,nm])
  cat(sprintf("%-45s est=%.4f se=%.4f p=%.4g\n", nm, est, s, 2*pnorm(-abs(est/s))))
}
cat("=== Pure-Renewables DEM coefficients ===\n")
for (nm in c("co_partisan_DEM_pure","cross_partisan_DEM_pure",
             "favorability:co_partisan_DEM_pure","favorability_sq:co_partisan_DEM_pure",
             "favorability:cross_partisan_DEM_pure","favorability_sq:cross_partisan_DEM_pure",
             "incumbencyC:co_partisan_DEM_pure","incumbencyO:co_partisan_DEM_pure",
             "incumbencyC:cross_partisan_DEM_pure","incumbencyO:cross_partisan_DEM_pure")) get_row(nm)

d <- cf[["co_partisan_DEM_pure"]] - cf[["cross_partisan_DEM_pure"]]
se <- sqrt(V["co_partisan_DEM_pure","co_partisan_DEM_pure"] + V["cross_partisan_DEM_pure","cross_partisan_DEM_pure"] - 2*V["co_partisan_DEM_pure","cross_partisan_DEM_pure"])
cat(sprintf("\nLEVEL diff (co vs cross, pure Renewables): diff=%.4f se=%.4f p=%.4g\n", d, se, 2*pnorm(-abs(d/se))))
