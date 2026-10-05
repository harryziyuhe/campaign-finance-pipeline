library(fixest)

PATH <- "/htaa/hhe/projects/election_buying/"
DIR <- paste0(PATH, "model/sector_alignment/")

stars <- function(p) if (is.na(p)) "" else if (p < 0.01) "$^{***}$" else if (p < 0.05) "$^{**}$" else if (p < 0.1) "$^{*}$" else ""
fmt <- function(x, digits = 4) formatC(x, format = "f", digits = digits, big.mark = ",")

row2 <- function(models, terms, digits = 4, mult = 1) {
  # models: list of fixest model objects (or NULL for blank column); terms: coef name per model (or NA to blank)
  est_line <- character(length(models)); se_line <- character(length(models))
  for (i in seq_along(models)) {
    m <- models[[i]]; t <- terms[i]
    if (is.null(m) || is.na(t) || !(t %in% names(coef(m)))) {
      est_line[i] <- ""; se_line[i] <- ""
    } else {
      b <- coef(m)[[t]] * mult; s <- sqrt(vcov(m)[t, t]) * mult
      p <- 2 * pnorm(-abs(coef(m)[[t]] / sqrt(vcov(m)[t, t])))
      est_line[i] <- paste0(fmt(b, digits), stars(p))
      se_line[i]  <- paste0("(", fmt(s, digits), ")")
    }
  }
  list(est = paste(est_line, collapse = " & "), se = paste(se_line, collapse = " & "))
}

print_table <- function(label_term_pairs, models, digits = 4, mult = 1) {
  for (nm in names(label_term_pairs)) {
    terms <- label_term_pairs[[nm]]
    r <- row2(models, terms, digits, mult)
    cat(sprintf("  %-45s & %s \\\\\n", nm, r$est))
    cat(sprintf("  %-45s & %s \\\\\n", "", r$se))
  }
}

# =============================================================================
# Table 2 analog: baseline categorical + continuous
# =============================================================================
cat("\n\n========== TABLE 2 ANALOG (baseline) ==========\n")
m_cat <- readRDS(paste0(DIR, "ASYM_BASE_CATEGORICAL.RDS"))
m_cont <- readRDS(paste0(DIR, "ASYM_BASE_CONTINUOUS.RDS"))
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
print_table(rows2, list(m_cat, m_cont))
cat("N =", nobs(m_cat), "/", nobs(m_cont), "\n")

# Direct asymmetry test (baseline)
cat("\n-- direct asymmetry diffs (baseline) --\n")
diff_row <- function(m, a, b) {
  cf <- coef(m); V <- vcov(m)
  d <- cf[[a]] - cf[[b]]; se <- sqrt(V[a,a]+V[b,b]-2*V[a,b])
  cat(sprintf("%s vs %s: diff=%.4f se=%.4f p=%.4g\n", a, b, d, se, 2*pnorm(-abs(d/se))))
}
diff_row(m_cat, "favorability:co_partisan_GOP", "favorability:cross_partisan_GOP")
diff_row(m_cont, "favorability:score_co_GOP", "favorability:score_cross_GOP")

# =============================================================================
# Table 3 analog: incumbency-interacted categorical + continuous
# =============================================================================
cat("\n\n========== TABLE 3 ANALOG (incumbency-interacted) -- HEADLINE ==========\n")
m_cat_i <- readRDS(paste0(DIR, "ASYM_INCUMBENCY_CATEGORICAL.RDS"))
m_cont_i <- readRDS(paste0(DIR, "ASYM_INCUMBENCY_CONTINUOUS.RDS"))
rows3 <- rows2
rows3[["Incumbent $\\times$ GOP co-partisan (ref: Incumbent)"]] <- NULL
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
print_table(rows3, list(m_cat_i, m_cont_i))
cat("-- candidate-type-targeting (headline) --\n")
print_table(extra3, list(m_cat_i, m_cont_i))
cat("N =", nobs(m_cat_i), "/", nobs(m_cont_i), "\n")

# =============================================================================
# Table 5 analog: Tobit baseline + incumbency, categorical + continuous
# =============================================================================
cat("\n\n========== TABLE 5 ANALOG (Tobit) ==========\n")
t_base_cat <- readRDS(paste0(DIR, "ASYM_TOBIT_BASE_CATEGORICAL.RDS"))$model
t_base_cont <- readRDS(paste0(DIR, "ASYM_TOBIT_BASE_CONTINUOUS.RDS"))$model
t_inc_cat <- readRDS(paste0(DIR, "ASYM_TOBIT_INCUMBENCY_CATEGORICAL.RDS"))$model
t_inc_cont <- readRDS(paste0(DIR, "ASYM_TOBIT_INCUMBENCY_CONTINUOUS.RDS"))$model
cat("-- baseline (dollar scale) --\n")
print_table(rows2, list(t_base_cat, t_base_cont), digits = 1)
cat("-- incumbency-interacted (dollar scale) --\n")
print_table(extra3, list(t_inc_cat, t_inc_cont), digits = 1)
cat("N =", nobs(t_base_cat), "/", nobs(t_inc_cat), "\n")

# =============================================================================
# Table 4: full curve-shape, categorical only
# =============================================================================
cat("\n\n========== TABLE 4 (full curve-shape, categorical) -- SUPPORT ==========\n")
m_fc <- readRDS(paste0(DIR, "ASYM_FULLCURVE_NOFE.RDS"))
rows4 <- list(
  "GOP co-partisan (Incumbent ref.)" = "co_partisan_GOP",
  "Chance of Winning $\\times$ GOP co-partisan" = "favorability:co_partisan_GOP",
  "Chance of Winning$^2$ $\\times$ GOP co-partisan" = "favorability_sq:co_partisan_GOP",
  "GOP cross-partisan (Incumbent ref.)" = "cross_partisan_GOP",
  "Chance of Winning $\\times$ GOP cross-partisan" = "favorability:cross_partisan_GOP",
  "Chance of Winning$^2$ $\\times$ GOP cross-partisan" = "favorability_sq:cross_partisan_GOP",
  "GOP co-partisan $\\times$ Non-Incumbent" = "co_partisan_GOP:incumbency_binNonIncumbent",
  "Chance of Winning $\\times$ GOP co-partisan $\\times$ Non-Inc." = "favorability:co_partisan_GOP:incumbency_binNonIncumbent",
  "Chance of Winning$^2$ $\\times$ GOP co-partisan $\\times$ Non-Inc." = "favorability_sq:co_partisan_GOP:incumbency_binNonIncumbent",
  "GOP cross-partisan $\\times$ Non-Incumbent" = "cross_partisan_GOP:incumbency_binNonIncumbent",
  "Chance of Winning $\\times$ GOP cross-partisan $\\times$ Non-Inc." = "favorability:cross_partisan_GOP:incumbency_binNonIncumbent",
  "Chance of Winning$^2$ $\\times$ GOP cross-partisan $\\times$ Non-Inc." = "favorability_sq:cross_partisan_GOP:incumbency_binNonIncumbent",
  "DEM co-partisan (Incumbent ref.)" = "co_partisan_DEM",
  "Chance of Winning $\\times$ DEM co-partisan" = "favorability:co_partisan_DEM",
  "Chance of Winning$^2$ $\\times$ DEM co-partisan" = "favorability_sq:co_partisan_DEM",
  "DEM cross-partisan (Incumbent ref.)" = "cross_partisan_DEM",
  "Chance of Winning $\\times$ DEM cross-partisan" = "favorability:cross_partisan_DEM",
  "Chance of Winning$^2$ $\\times$ DEM cross-partisan" = "favorability_sq:cross_partisan_DEM",
  "DEM co-partisan $\\times$ Non-Incumbent" = "co_partisan_DEM:incumbency_binNonIncumbent",
  "Chance of Winning $\\times$ DEM co-partisan $\\times$ Non-Inc." = "favorability:co_partisan_DEM:incumbency_binNonIncumbent",
  "Chance of Winning$^2$ $\\times$ DEM co-partisan $\\times$ Non-Inc." = "favorability_sq:co_partisan_DEM:incumbency_binNonIncumbent",
  "DEM cross-partisan $\\times$ Non-Incumbent" = "cross_partisan_DEM:incumbency_binNonIncumbent",
  "Chance of Winning $\\times$ DEM cross-partisan $\\times$ Non-Inc." = "favorability:cross_partisan_DEM:incumbency_binNonIncumbent",
  "Chance of Winning$^2$ $\\times$ DEM cross-partisan $\\times$ Non-Inc." = "favorability_sq:cross_partisan_DEM:incumbency_binNonIncumbent"
)
for (nm in names(rows4)) {
  r <- row2(list(m_fc), rows4[[nm]])
  cat(sprintf("  %-55s & %s \\\\\n", nm, r$est))
  cat(sprintf("  %-55s & %s \\\\\n", "", r$se))
}
cat("N =", nobs(m_fc), "\n")
