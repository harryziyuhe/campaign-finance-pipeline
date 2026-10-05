# Robustness (appendix subsec:robust4) re-estimated on the co-partisan/cross-partisan
# design, replacing the superseded symmetric specification.
#
# Alignment measure here is the CONTRIBUTION-BASED (prior-giving) classification
# `give_partisan`, not the market-implied one. It is a validation check rather
# than a preferred measure, since it is derived from political behavior and so
# cannot be treated as exogenous to the outcome.
#
# Design mirrors scripts/sector_alignment/logit/asymmetric_pooled_nofe.R so the
# coefficients are directly comparable to the main tables:
#   co_partisan_GOP_give    = 1{candidate R, firm prior-giving GOP-aligned}
#   cross_partisan_GOP_give = 1{candidate D, firm prior-giving GOP-aligned}
#   co_partisan_DEM_give    = 1{candidate D, firm prior-giving DEM-aligned}
#   cross_partisan_DEM_give = 1{candidate R, firm prior-giving DEM-aligned}
#   hedged                  = 1{firm splits giving roughly evenly between parties}
# Reference category is the non-exposed group.
#
# `hedged` is deliberately NOT split into co-/cross-partisan: a firm classified
# as bipartisan has no favored party, so the distinction is undefined for it.
# That is itself the theoretically interesting case -- if partisan direction is
# the signature of election-oriented giving, hedged firms should show the
# access-oriented profile toward every candidate type.

suppressPackageStartupMessages({ library(dplyr); library(fixest) })

PATH <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")

.args     <- commandArgs(trailingOnly = TRUE)
DATA_NAME <- if (length(.args) >= 1) .args[1] else "cand_model_data"
SUFFIX    <- if (length(.args) >= 2) .args[2] else ""
cat("Input data: ", DATA_NAME, ".RDS\n", sep = "")

d <- readRDS(paste0(PATH, DATA_NAME, ".RDS"))
d <- d %>% filter(!is.na(give_partisan))
d$incumbency <- factor(d$incumbency, levels = c("I", "C", "O"))
d$party      <- factor(d$party, levels = c("DEMOCRAT", "REPUBLICAN"))

d$co_partisan_GOP_give    <- as.integer(d$party == "REPUBLICAN" & d$give_partisan == "GOP")
d$cross_partisan_GOP_give <- as.integer(d$party == "DEMOCRAT"   & d$give_partisan == "GOP")
d$co_partisan_DEM_give    <- as.integer(d$party == "DEMOCRAT"   & d$give_partisan == "DEM")
d$cross_partisan_DEM_give <- as.integer(d$party == "REPUBLICAN" & d$give_partisan == "DEM")
d$hedged                  <- as.integer(d$give_partisan == "Hedged")

cat("\n=== cell counts ===\n")
for (v in c("co_partisan_GOP_give","cross_partisan_GOP_give",
            "co_partisan_DEM_give","cross_partisan_DEM_give","hedged")) {
  n <- sum(d[[v]], na.rm = TRUE)
  ev <- sum(d$contribute[d[[v]] == 1] == 1, na.rm = TRUE)
  cat(sprintf("  %-26s n=%8d  events=%6d  rate=%.3f%%\n", v, n, ev, 100*ev/n))
}
cat("\n  by candidate type (aligned dummies only):\n")
print(d %>% filter(co_partisan_GOP_give == 1 | cross_partisan_GOP_give == 1) %>%
        mutate(rel = ifelse(co_partisan_GOP_give == 1, "co", "cross"),
               typ = ifelse(incumbency == "I", "Inc", "NonInc")) %>%
        group_by(rel, typ) %>%
        summarise(dyads = n(), events = sum(contribute == 1, na.rm = TRUE), .groups = "drop") %>%
        as.data.frame())

base_controls <- "special + private + foreign + same_state + log(firm_cash) + party + incumbency"
cluster_fml <- ~ cmte_id + candidate_id
DUMS <- c("co_partisan_GOP_give","cross_partisan_GOP_give",
          "co_partisan_DEM_give","cross_partisan_DEM_give","hedged")

curve_terms <- paste(sapply(DUMS, function(v)
  sprintf("%s + favorability:%s + favorability_sq:%s", v, v, v)), collapse = " + ")
inc_terms   <- paste(sapply(DUMS, function(v) sprintf("%s:incumbency", v)), collapse = " + ")

fit_save <- function(rhs, out_name) {
  out_name <- paste0(out_name, SUFFIX)
  cat(sprintf("\nFitting %s...\n", out_name))
  t0 <- Sys.time()
  mod <- feglm(as.formula(paste("contribute ~", rhs, "| state + year")),
               data = d, family = binomial("logit"), cluster = cluster_fml)
  cat(sprintf("  fit time: %.2f min\n", as.numeric(Sys.time() - t0, units = "mins")))
  saveRDS(mod, paste0(OUT_DIR, out_name, ".RDS"))
  writeLines(capture.output(summary(mod)), paste0(OUT_DIR, out_name, "_coefficients.txt"))
  mod
}

rhs_base <- paste(base_controls, "favorability + favorability_sq", curve_terms, sep = " + ")
m_base <- fit_save(rhs_base, "ASYM_GIVE_BASE")

rhs_inc <- paste(rhs_base, inc_terms, sep = " + ")
m_inc <- fit_save(rhs_inc, "ASYM_GIVE_INCUMBENCY")

cat("\n=== candidate-type targeting (incumbency-interacted model) ===\n")
cf <- coef(m_inc); se <- se(m_inc)
for (v in DUMS) for (lv in c("C","O")) {
  nm <- paste0("incumbency", lv, ":", v)
  if (nm %in% names(cf)) {
    p <- 2*pnorm(-abs(cf[[nm]]/se[[nm]]))
    cat(sprintf("  %-42s %8.4f (%.4f)  p=%.4g\n", nm, cf[[nm]], se[[nm]], p))
  }
}

# Direct co- vs cross-partisan asymmetry test within the model.
diff_test <- function(mod, a, b) {
  cf <- coef(mod); V <- vcov(mod)
  if (!all(c(a,b) %in% names(cf))) return(invisible(NULL))
  dd <- cf[[a]] - cf[[b]]
  s <- sqrt(V[a,a] + V[b,b] - 2*V[a,b])
  cat(sprintf("  %-46s vs %-46s diff=%8.4f se=%.4f p=%.4g\n", a, b, dd, s, 2*pnorm(-abs(dd/s))))
}
cat("\n=== direct asymmetry tests (co vs cross, same candidate type) ===\n")
for (lv in c("C","O")) {
  diff_test(m_inc, paste0("incumbency",lv,":co_partisan_GOP_give"),
                   paste0("incumbency",lv,":cross_partisan_GOP_give"))
}
cat("\nDone.\n")
