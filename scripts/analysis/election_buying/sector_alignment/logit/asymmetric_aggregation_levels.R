# Robustness (appendix subsec:robust3): does the candidate-type-targeting result
# survive measuring partisan alignment at finer levels of aggregation?
#
# The main analysis measures alignment at the SECTOR level (18 groups). This
# script re-estimates the same co-partisan/cross-partisan specification at two
# finer levels, using the refreshed measures:
#
#   subsector  (26 groups)  subsec_partisan / subsec_partisan_score
#   industry   (49 groups)  ind_partisan    / ind_partisan_score
#
# Hierarchy is sector -> subsector -> industry, industry being the finest.
#
# Both categorical and continuous forms are fit at each level, so the output is
# directly comparable to Table tab:asym_incumbency in the main text.
#
# Note on power: the industry-level DEM bucket is far larger than the sector
# one (192 firms / 16,727 contribution events, against 21 / 558), so DEM-side
# estimates here may be informative where the sector-level ones are not. The
# offsetting cost is that each finer group averages over fewer firms, making the
# underlying event-study measure noisier.

suppressPackageStartupMessages({ library(dplyr); library(fixest) })
PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")

.args     <- commandArgs(trailingOnly = TRUE)
DATA_NAME <- if (length(.args) >= 1) .args[1] else "cand_model_data_v2"
SUFFIX    <- if (length(.args) >= 2) .args[2] else ""
cat("Input: ", DATA_NAME, ".RDS\n", sep = "")

d <- readRDS(paste0(PATH, DATA_NAME, ".RDS"))
d$incumbency <- factor(d$incumbency, levels = c("I", "C", "O"))
d$party      <- factor(d$party, levels = c("DEMOCRAT", "REPUBLICAN"))

# Blank strings are not a category. Treat them as missing so they cannot become
# a silent fifth level in the categorical measures.
for (v in c("ind_partisan", "subsec_partisan")) {
  d[[v]][trimws(d[[v]]) == ""] <- NA_character_
}

base_controls <- "special + private + foreign + same_state + log(firm_cash) + party + incumbency"
cl <- ~ cmte_id + candidate_id

fit_level <- function(cat_var, score_var, tag) {
  cat("\n", strrep("=", 66), "\n", tag, "\n", strrep("=", 66), "\n", sep = "")
  dd <- d %>% filter(!is.na(.data[[cat_var]]), !is.na(.data[[score_var]]))

  dd$co_GOP    <- as.integer(dd$party == "REPUBLICAN" & dd[[cat_var]] == "GOP")
  dd$cross_GOP <- as.integer(dd$party == "DEMOCRAT"   & dd[[cat_var]] == "GOP")
  dd$co_DEM    <- as.integer(dd$party == "DEMOCRAT"   & dd[[cat_var]] == "DEM")
  dd$cross_DEM <- as.integer(dd$party == "REPUBLICAN" & dd[[cat_var]] == "DEM")
  s <- dd[[score_var]]
  dd$s_co_GOP    <- pmax(s, 0) * (dd$party == "REPUBLICAN")
  dd$s_cross_GOP <- pmax(s, 0) * (dd$party == "DEMOCRAT")
  dd$s_co_DEM    <- pmax(-s, 0) * (dd$party == "DEMOCRAT")
  dd$s_cross_DEM <- pmax(-s, 0) * (dd$party == "REPUBLICAN")

  cat("cell counts (categorical):\n")
  for (v in c("co_GOP","cross_GOP","co_DEM","cross_DEM")) {
    n <- sum(dd[[v]]); ev <- sum(dd$contribute[dd[[v]] == 1] == 1, na.rm = TRUE)
    cat(sprintf("  %-10s n=%9s  events=%6s  rate=%.3f%%\n", v,
                format(n, big.mark=","), format(ev, big.mark=","), 100*ev/n))
  }

  run <- function(dums, name) {
    curve <- paste(sapply(dums, function(v)
      sprintf("%s + favorability:%s + favorability_sq:%s", v, v, v)), collapse=" + ")
    inc <- paste(sapply(dums, function(v) sprintf("%s:incumbency", v)), collapse=" + ")
    f <- as.formula(paste("contribute ~", base_controls,
                          "+ favorability + favorability_sq +", curve, "+", inc,
                          "| state + year"))
    t0 <- Sys.time()
    m <- feglm(f, data = dd, family = binomial("logit"), cluster = cl)
    cat(sprintf("\n  [%s] fit %.2f min, N=%s\n", name,
                as.numeric(Sys.time()-t0, units="mins"), format(nobs(m), big.mark=",")))
    out <- paste0(OUT_DIR, "ASYM_", name, SUFFIX)
    saveRDS(m, paste0(out, ".RDS"))
    writeLines(capture.output(summary(m)), paste0(out, "_coefficients.txt"))
    cf <- coef(m); se <- se(m)
    for (v in dums[1:2]) for (lv in c("C","O")) {
      nm <- paste0("incumbency", lv, ":", v)
      if (nm %in% names(cf))
        cat(sprintf("    %-28s %8.4f (%.4f) p=%.4g\n", nm, cf[[nm]], se[[nm]],
                    2*pnorm(-abs(cf[[nm]]/se[[nm]]))))
    }
    # direct co- vs cross-partisan asymmetry test
    V <- vcov(m)
    for (lv in c("C","O")) {
      a <- paste0("incumbency",lv,":",dums[1]); b <- paste0("incumbency",lv,":",dums[2])
      if (all(c(a,b) %in% names(cf))) {
        dd2 <- cf[[a]]-cf[[b]]; s2 <- sqrt(V[a,a]+V[b,b]-2*V[a,b])
        cat(sprintf("    asymmetry %s: diff=%7.4f se=%.4f p=%.4g\n",
                    if (lv=="C") "Challenger" else "Open Seat ", dd2, s2, 2*pnorm(-abs(dd2/s2))))
      }
    }
    invisible(m)
  }
  run(c("co_GOP","cross_GOP","co_DEM","cross_DEM"), paste0(tag, "_CAT"))
  run(c("s_co_GOP","s_cross_GOP","s_co_DEM","s_cross_DEM"), paste0(tag, "_CONT"))
  rm(dd); gc(verbose = FALSE)
}

fit_level("subsec_partisan", "subsec_partisan_score", "SUBSEC")
fit_level("ind_partisan",    "ind_partisan_score",    "IND")
cat("\nDone.\n")
