library(fixest)

# =============================================================================
# Rigor layer on top of scripts/logit/sector_alignment_partisan.R's saved
# models. Implements the same delta-method peak-shift test as
# docs/theory_revision_handoff.md §3.1/§4.1 (never compare two marginal CIs
# for overlap -- compute the SE of the DIFFERENCE via the joint gradient and
# vcov), applied to the sector-level singlename_partisan_pre /
# singlename_score_pre / etf_score_pre measures instead of the old ad hoc
# firm_lean/category grouping.
#
# Peak location is only reported for Challenger and Open-seat models
# (well-identified curvature). For Incumbent models we report the raw
# favorability_sq level and interaction coefficients directly, NOT a peak
# ratio -- dividing by a near-zero, noisily-estimated curvature is unstable
# (docs §4.2).
# =============================================================================
PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")

CAND_TYPES <- c("Incumbent", "Challenger", "Open-seat")
PARTIES <- c("Republican", "Democrat")

safe_read <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(readRDS(path), error = function(e) NULL)
}

# ---- Delta-method peak-shift for the categorical (co_partisan_snp) model --
# peak0 = -b1/(2 b2)                     [baseline, co_partisan_snp = 0]
# peak1 = -(b1+b3)/(2*(b2+b4))           [aligned,  co_partisan_snp = 1]
# diff  = peak1 - peak0, SE via joint gradient against vcov(mod).
peak_shift_test <- function(mod, int_suffix = ":co_partisan_snp") {
  cf <- coef(mod)
  V  <- vcov(mod)

  fv_name    <- "favorability"
  fvsq_name  <- "favorability_sq"
  fvint_name   <- paste0(fv_name, int_suffix)
  fvsqint_name <- paste0(fvsq_name, int_suffix)

  needed <- c(fv_name, fvsq_name, fvint_name, fvsqint_name)
  if (!all(needed %in% names(cf))) {
    return(list(error = paste("missing coefficients:",
                               paste(setdiff(needed, names(cf)), collapse = ", "))))
  }

  b1 <- cf[[fv_name]]; b2 <- cf[[fvsq_name]]
  b3 <- cf[[fvint_name]]; b4 <- cf[[fvsqint_name]]

  peak0 <- -b1 / (2 * b2)
  peak1 <- -(b1 + b3) / (2 * (b2 + b4))
  diff  <- peak1 - peak0

  g <- setNames(numeric(length(cf)), names(cf))
  g[fv_name]      <- -1 / (2 * (b2 + b4)) - (-1 / (2 * b2))
  g[fvsq_name]    <- (b1 + b3) / (2 * (b2 + b4)^2) - (b1 / (2 * b2^2))
  g[fvint_name]   <- -1 / (2 * (b2 + b4))
  g[fvsqint_name] <- (b1 + b3) / (2 * (b2 + b4)^2)

  se_diff <- sqrt(as.numeric(t(g) %*% V %*% g))
  z <- diff / se_diff
  p <- 2 * pnorm(-abs(z))

  list(peak0 = peak0, peak1 = peak1, diff = diff, se = se_diff, z = z, p = p)
}

# ---- Raw curvature report for Incumbent models (no peak ratio, §4.2) ------
incumbent_report <- function(mod, int_suffix = ":co_partisan_snp") {
  cf <- coef(mod); se <- se(mod)
  fvsq_name <- "favorability_sq"
  fvsqint_name <- paste0(fvsq_name, int_suffix)
  fvint_name <- paste0("favorability", int_suffix)
  get_row <- function(nm) {
    if (!nm %in% names(cf)) return(c(est = NA, se = NA, p = NA))
    est <- cf[[nm]]; s <- se[[nm]]
    c(est = est, se = s, p = 2 * pnorm(-abs(est / s)))
  }
  list(
    fvsq_base    = get_row(fvsq_name),
    fvsq_aligned = get_row(fvsqint_name),
    fv_base      = get_row("favorability"),
    fv_aligned   = get_row(fvint_name)
  )
}

# ---- Continuous robustness: fv_sq x alignment-score coefficient -----------
continuous_report <- function(mod, score_name) {
  cf <- coef(mod); se <- se(mod)
  fvsqint <- paste0("favorability_sq:", score_name)
  fvint   <- paste0("favorability:", score_name)
  get_row <- function(nm) {
    if (!nm %in% names(cf)) return(c(est = NA, se = NA, p = NA))
    est <- cf[[nm]]; s <- se[[nm]]
    c(est = est, se = s, p = 2 * pnorm(-abs(est / s)))
  }
  list(fvsq_int = get_row(fvsqint), fv_int = get_row(fvint),
       level = get_row(score_name))
}

# ---- H2 main-effect (co-partisan support) report ---------------------------
h2_report <- function(mod) {
  cf <- coef(mod); se <- se(mod)
  get_row <- function(nm) {
    if (!nm %in% names(cf)) return(c(est = NA, se = NA, p = NA))
    est <- cf[[nm]]; s <- se[[nm]]
    c(est = est, se = s, p = 2 * pnorm(-abs(est / s)))
  }
  get_row("co_partisan_snp")
}

fmt_row <- function(x) sprintf("est=%.4f se=%.4f p=%.4g", x["est"], x["se"], x["p"])

# =============================================================================
# Run the report
# =============================================================================

results <- character(0)
add <- function(...) results <<- c(results, sprintf(...))

add("=============================================================")
add("H2: co-partisan support (pooled main effect, co_partisan_snp)")
add("=============================================================")
for (party in PARTIES) {
  mod <- safe_read(paste0(OUT_DIR, "H2_A_categorical_", party, "_pooled.RDS"))
  if (is.null(mod)) { add("%s: model missing", party); next }
  row <- h2_report(mod)
  add("%s aligned firms, main co_partisan_snp effect: %s", party, fmt_row(row))
}

add("")
add("=============================================================")
add("H3/H4: peak-shift by candidate type (categorical measure)")
add("=============================================================")
for (party in PARTIES) {
  for (type in CAND_TYPES) {
    label <- paste0(party, "_", gsub("-", "", type))
    path <- paste0(OUT_DIR, "A_categorical_", party, "_", type, ".RDS")
    mod <- safe_read(path)
    if (is.null(mod)) { add("%s / %s: model missing (%s)", party, type, path); next }

    if (type == "Incumbent") {
      rep <- incumbent_report(mod)
      add("%s / %s (curvature only, no peak ratio -- §4.2):", party, type)
      add("  favorability_sq [baseline]: %s", fmt_row(rep$fvsq_base))
      add("  favorability_sq [x aligned]: %s", fmt_row(rep$fvsq_aligned))
    } else {
      pk <- peak_shift_test(mod)
      if (!is.null(pk$error)) { add("%s / %s: %s", party, type, pk$error); next }
      add("%s / %s: peak0=%.3f peak1=%.3f diff=%.3f se=%.3f z=%.3f p=%.4g",
          party, type, pk$peak0, pk$peak1, pk$diff, pk$se, pk$z, pk$p)
    }
  }
}

add("")
add("=============================================================")
add("Continuous robustness: singlename_score_pre (Model B) and")
add("etf_score_pre (Model C) -- fv_sq x alignment-score coefficient")
add("=============================================================")
for (party in PARTIES) {
  for (type in CAND_TYPES) {
    for (spec in list(list(prefix = "B_singlename_", score = "snp_align", label = "singlename"),
                       list(prefix = "C_etf_", score = "etf_align", label = "etf"))) {
      path <- paste0(OUT_DIR, spec$prefix, party, "_", type, ".RDS")
      mod <- safe_read(path)
      if (is.null(mod)) { add("%s / %s / %s: model missing", party, type, spec$label); next }
      rep <- continuous_report(mod, spec$score)
      add("%s / %s / %s: fv_sq:score %s | fv:score %s", party, type, spec$label,
          fmt_row(rep$fvsq_int), fmt_row(rep$fv_int))
    }
  }
}

add("")
add("=============================================================")
add("Confirmatory triple interaction (favorability x aligned x")
add("incumbency-binary), categorical measure")
add("=============================================================")
for (party in PARTIES) {
  path <- paste0(OUT_DIR, "TRIPLE_A_categorical_", party, "_triple.RDS")
  mod <- safe_read(path)
  if (is.null(mod)) { add("%s: model missing", party); next }
  cf <- coef(mod); se <- se(mod)
  get_row <- function(nm) {
    if (!nm %in% names(cf)) return(NULL)
    est <- cf[[nm]]; s <- se[[nm]]
    sprintf("%s: est=%.4f se=%.4f p=%.4g", nm, est, s, 2 * pnorm(-abs(est / s)))
  }
  targets <- names(cf)[grepl("favorability_sq.*co_partisan_snp", names(cf))]
  add("%s triple-interaction terms:", party)
  for (t in targets) {
    r <- get_row(t)
    if (!is.null(r)) add("  %s", r)
  }
}

add("")
add("=============================================================")
add("H1 pooled baseline concavity")
add("=============================================================")
mod <- safe_read(paste0(OUT_DIR, "H1_baseline_pooled.RDS"))
if (!is.null(mod)) {
  cf <- coef(mod); se <- se(mod)
  add("favorability_sq: est=%.5f se=%.5f p=%.4g", cf[["favorability_sq"]], se[["favorability_sq"]],
      2 * pnorm(-abs(cf[["favorability_sq"]] / se[["favorability_sq"]])))
}

writeLines(results)
writeLines(results, paste0(OUT_DIR, "RESULTS_SUMMARY.txt"))
cat("\nWrote", paste0(OUT_DIR, "RESULTS_SUMMARY.txt"), "\n")
