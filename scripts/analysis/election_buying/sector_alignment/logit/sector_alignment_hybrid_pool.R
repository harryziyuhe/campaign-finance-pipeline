library(dplyr)
library(fixest)

PATH <- "/htaa/hhe/projects/election_buying/"
cand_data <- readRDS(paste0(PATH, "cand_model_data.RDS"))

cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre, levels = c("Other", "GOP", "DEM"))
cand_data$incumbency <- factor(cand_data$incumbency, levels = c("I", "C", "O"))
cand_data$incumbency_bin <- factor(ifelse(cand_data$incumbency == "I", "Incumbent", "NonIncumbent"),
                                    levels = c("Incumbent", "NonIncumbent"))
cand_data$co_partisan_snp <- dplyr::case_when(
  cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "GOP" ~ 1,
  cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "DEM" ~ 1,
  TRUE ~ 0
)

base_controls <- "favorability + favorability_sq + special + private + foreign + same_state + log(firm_cash)"

fit_hybrid <- function(party_val, label) {
  cat("\n=====", label, "=====\n")
  d <- cand_data %>% filter(party == party_val) %>% droplevels()

  rhs <- paste(
    base_controls,
    "favorability:incumbency + favorability_sq:incumbency",
    "co_partisan_snp + favorability:co_partisan_snp + favorability_sq:co_partisan_snp",
    "co_partisan_snp:incumbency_bin + favorability:co_partisan_snp:incumbency_bin + favorability_sq:co_partisan_snp:incumbency_bin",
    "incumbency",
    sep = " + "
  )
  fmla <- as.formula(paste("contribute ~", rhs, "| state + year"))
  mod <- feglm(fmla, data = d, family = binomial(link="logit"), cluster = ~cmte_id + candidate_id)
  print(summary(mod))

  cf <- coef(mod); V <- vcov(mod)
  # Pooled NonIncumbent (Challenger+Open-seat) aligned peak shift
  b1 <- cf[["favorability"]]; b2 <- cf[["favorability_sq"]]
  b3 <- cf[["favorability:co_partisan_snp"]]; b4 <- cf[["favorability_sq:co_partisan_snp"]]
  bC1 <- cf[["favorability:incumbencyC"]]; bC2 <- cf[["favorability_sq:incumbencyC"]]
  bO1 <- cf[["favorability:incumbencyO"]]; bO2 <- cf[["favorability_sq:incumbencyO"]]
  bNI1 <- cf[["favorability:co_partisan_snp:incumbency_binNonIncumbent"]]
  bNI2 <- cf[["favorability_sq:co_partisan_snp:incumbency_binNonIncumbent"]]

  cat(sprintf("\nPooled NonIncumbent aligned-shift terms: fv:co_partisan_snp:NonIncumbent=%.4f (further shift beyond I-level aligned shift), fv_sq version=%.4f\n", bNI1, bNI2))

  # Peak for Challenger, baseline (non-aligned): -( b1+bC1 )/(2*(b2+bC2))
  # Peak for Challenger, aligned: -( b1+bC1+b3+bNI1 )/(2*(b2+bC2+b4+bNI2))
  peak_fn <- function(lin, quad) -lin/(2*quad)
  peakC0 <- peak_fn(b1+bC1, b2+bC2)
  peakC1 <- peak_fn(b1+bC1+b3+bNI1, b2+bC2+b4+bNI2)
  peakO0 <- peak_fn(b1+bO1, b2+bO2)
  peakO1 <- peak_fn(b1+bO1+b3+bNI1, b2+bO2+b4+bNI2)
  cat(sprintf("Challenger: peak0=%.3f peak1=%.3f diff=%.3f\n", peakC0, peakC1, peakC1-peakC0))
  cat(sprintf("Open-seat:  peak0=%.3f peak1=%.3f diff=%.3f\n", peakO0, peakO1, peakO1-peakO0))

  # Delta method SE for the pooled NonIncumbent aligned-shift terms themselves (the parameter of interest)
  se_bNI1 <- sqrt(V["favorability:co_partisan_snp:incumbency_binNonIncumbent","favorability:co_partisan_snp:incumbency_binNonIncumbent"])
  se_bNI2 <- sqrt(V["favorability_sq:co_partisan_snp:incumbency_binNonIncumbent","favorability_sq:co_partisan_snp:incumbency_binNonIncumbent"])
  cat(sprintf("fv:co_partisan_snp:NonIncumbent  z=%.3f p=%.4g\n", bNI1/se_bNI1, 2*pnorm(-abs(bNI1/se_bNI1))))
  cat(sprintf("fv_sq:co_partisan_snp:NonIncumbent z=%.3f p=%.4g\n", bNI2/se_bNI2, 2*pnorm(-abs(bNI2/se_bNI2))))
}

fit_hybrid("REPUBLICAN", "Republican")
fit_hybrid("DEMOCRAT", "Democrat")
