library(dplyr)
library(fixest)
library(car)

PATH <- "/htaa/hhe/projects/election_buying/"
cand_data <- readRDS(paste0(PATH, "cand_model_data.RDS"))

cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre, levels = c("Other", "GOP", "DEM"))
cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))
cand_data$co_partisan_snp <- dplyr::case_when(
  cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "GOP" ~ 1,
  cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "DEM" ~ 1,
  TRUE ~ 0
)

base_controls <- "favorability + favorability_sq + special + private + foreign + same_state + log(firm_cash)"

run_poolability_test <- function(party_val, label) {
  cat("\n=====", label, "=====\n")
  d <- cand_data %>% filter(party == party_val) %>% droplevels()

  # Unrestricted: full 3-level incumbency (I ref) x (fv+fv_sq) x co_partisan_snp
  fmla <- as.formula(paste("contribute ~", base_controls,
    "+ (favorability + favorability_sq) * co_partisan_snp * incumbency | state + year"))
  mod <- feglm(fmla, data = d, family = binomial(link="logit"), cluster = ~cmte_id + candidate_id)
  cat("Unrestricted model coefficient names:\n")
  print(names(coef(mod)))

  # Joint test: does Challenger's curve (baseline + aligned-shift) equal Open-seat's curve?
  hyp <- c(
    "favorability:incumbencyC = favorability:incumbencyO",
    "favorability_sq:incumbencyC = favorability_sq:incumbencyO",
    "favorability:co_partisan_snp:incumbencyC = favorability:co_partisan_snp:incumbencyO",
    "favorability_sq:co_partisan_snp:incumbencyC = favorability_sq:co_partisan_snp:incumbencyO"
  )
  cat("\nJoint Wald test: Challenger curve == Open-seat curve (baseline + aligned-shift)\n")
  print(linearHypothesis(mod, hyp, test = "Chisq"))

  cat("\nSub-test: just the ALIGNED-shift pieces equal across C vs O\n")
  hyp2 <- c(
    "favorability:co_partisan_snp:incumbencyC = favorability:co_partisan_snp:incumbencyO",
    "favorability_sq:co_partisan_snp:incumbencyC = favorability_sq:co_partisan_snp:incumbencyO"
  )
  print(linearHypothesis(mod, hyp2, test = "Chisq"))

  cat("\nSub-test: just the BASELINE (non-aligned) curve equal across C vs O\n")
  hyp3 <- c(
    "favorability:incumbencyC = favorability:incumbencyO",
    "favorability_sq:incumbencyC = favorability_sq:incumbencyO"
  )
  print(linearHypothesis(mod, hyp3, test = "Chisq"))
}

run_poolability_test("REPUBLICAN", "Republican")
run_poolability_test("DEMOCRAT", "Democrat")
