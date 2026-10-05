PATH <- "/htaa/hhe/projects/election_buying/"
DIR <- paste0(PATH, "model/sector_alignment/")

stars <- function(p) if (is.na(p)) "" else if (p < 0.01) "$^{***}$" else if (p < 0.05) "$^{**}$" else if (p < 0.1) "$^{*}$" else ""
fmt <- function(x, digits = 1) formatC(x, format = "f", digits = digits, big.mark = ",")

row2 <- function(objs, terms, digits = 1) {
  est_line <- character(2); se_line <- character(2)
  for (i in 1:2) {
    cf <- coef(objs[[i]]$model); V <- objs[[i]]$vcov
    t <- terms[i]
    if (is.na(t) || !(t %in% names(cf))) { est_line[i] <- ""; se_line[i] <- ""; next }
    b <- cf[[t]]; s <- sqrt(V[t, t]); p <- 2 * pnorm(-abs(b / s))
    est_line[i] <- paste0(fmt(b, digits), stars(p))
    se_line[i]  <- paste0("(", fmt(s, digits), ")")
  }
  list(est = paste(est_line, collapse = " & "), se = paste(se_line, collapse = " & "))
}

print_table <- function(label_term_pairs, objs, digits = 1) {
  for (nm in names(label_term_pairs)) {
    r <- row2(objs, label_term_pairs[[nm]], digits)
    cat(sprintf("  %-45s & %s \\\\\n", nm, r$est))
    cat(sprintf("  %-45s & %s \\\\\n", "", r$se))
  }
}

rows2 <- list(
  "Chance of Winning" = c("favorability", "favorability"),
  "Chance of Winning$^2$" = c("favorability_sq", "favorability_sq"),
  "GOP co-partisan" = c("co_partisan_GOP", "score_co_GOP"),
  "GOP cross-partisan" = c("cross_partisan_GOP", "score_cross_GOP"),
  "DEM co-partisan" = c("co_partisan_DEM", "score_co_DEM"),
  "DEM cross-partisan" = c("cross_partisan_DEM", "score_cross_DEM"),
  "Chance of Winning $\\times$ GOP co-partisan" = c("favorability:co_partisan_GOP", "favorability:score_co_GOP"),
  "Chance of Winning$^2$ $\\times$ GOP co-partisan" = c("favorability_sq:co_partisan_GOP", "favorability_sq:score_co_GOP"),
  "Chance of Winning $\\times$ GOP cross-partisan" = c("favorability:cross_partisan_GOP", "favorability:score_cross_GOP"),
  "Chance of Winning$^2$ $\\times$ GOP cross-partisan" = c("favorability_sq:cross_partisan_GOP", "favorability_sq:score_cross_GOP"),
  "Chance of Winning $\\times$ DEM co-partisan" = c("favorability:co_partisan_DEM", "favorability:score_co_DEM"),
  "Chance of Winning$^2$ $\\times$ DEM co-partisan" = c("favorability_sq:co_partisan_DEM", "favorability_sq:score_co_DEM"),
  "Chance of Winning $\\times$ DEM cross-partisan" = c("favorability:cross_partisan_DEM", "favorability:score_cross_DEM"),
  "Chance of Winning$^2$ $\\times$ DEM cross-partisan" = c("favorability_sq:cross_partisan_DEM", "favorability_sq:score_cross_DEM")
)
extra3 <- list(
  "GOP co-partisan $\\times$ Challenger" = c("incumbencyC:co_partisan_GOP", "incumbencyC:score_co_GOP"),
  "GOP co-partisan $\\times$ Open Seat" = c("incumbencyO:co_partisan_GOP", "incumbencyO:score_co_GOP"),
  "GOP cross-partisan $\\times$ Challenger" = c("incumbencyC:cross_partisan_GOP", "incumbencyC:score_cross_GOP"),
  "GOP cross-partisan $\\times$ Open Seat" = c("incumbencyO:cross_partisan_GOP", "incumbencyO:score_cross_GOP"),
  "DEM co-partisan $\\times$ Challenger" = c("incumbencyC:co_partisan_DEM", "incumbencyC:score_co_DEM"),
  "DEM co-partisan $\\times$ Open Seat" = c("incumbencyO:co_partisan_DEM", "incumbencyO:score_co_DEM"),
  "DEM cross-partisan $\\times$ Challenger" = c("incumbencyC:cross_partisan_DEM", "incumbencyC:score_cross_DEM"),
  "DEM cross-partisan $\\times$ Open Seat" = c("incumbencyO:cross_partisan_DEM", "incumbencyO:score_cross_DEM")
)

cat("Loading base categorical...\n")
b_cat <- readRDS(paste0(DIR, "ASYM_TOBIT_BASE_CATEGORICAL.RDS")); b_cat$model <- b_cat$model; b_cat$vcov <- b_cat$vcov_cluster
cat("Loading base continuous...\n")
b_cont <- readRDS(paste0(DIR, "ASYM_TOBIT_BASE_CONTINUOUS.RDS")); b_cont$vcov <- b_cont$vcov_cluster
cat("\n========== TABLE 5 baseline (dollar) ==========\n")
print_table(rows2, list(b_cat, b_cont))
cat("N =", length(residuals(b_cat$model)), "\n")
rm(b_cat, b_cont); gc()

cat("Loading incumbency categorical...\n")
i_cat <- readRDS(paste0(DIR, "ASYM_TOBIT_INCUMBENCY_CATEGORICAL.RDS")); i_cat$vcov <- i_cat$vcov_cluster
cat("Loading incumbency continuous...\n")
i_cont <- readRDS(paste0(DIR, "ASYM_TOBIT_INCUMBENCY_CONTINUOUS.RDS")); i_cont$vcov <- i_cont$vcov_cluster
cat("\n========== TABLE 5 incumbency-interacted (dollar) ==========\n")
print_table(rows2, list(i_cat, i_cont))
cat("-- candidate-type-targeting --\n")
print_table(extra3, list(i_cat, i_cont))
cat("N =", length(residuals(i_cat$model)), "\n")
