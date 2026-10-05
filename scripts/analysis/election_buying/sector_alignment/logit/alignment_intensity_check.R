# Check the strong-GOP incumbent finding two ways before it is trusted.
#
# The binary STRONG/OTHER split found that the most Republican-aligned
# industries are LESS likely than non-advantaged firms to support an endangered
# co-partisan incumbent (OR 0.43 at the weakest favorability), and slightly more
# likely to support a safe one. Two things must hold before that means anything.
#
# (1) INTENSITY. If the pattern is about alignment rather than about oil and gas
#     specifically, it should scale with the alignment score rather than appear
#     only in a hand-picked group. Replace the binary split with the continuous
#     industry score and evaluate the co-partisan incumbent curve at several
#     score levels.
#
# (2) SUPPORT. The OR at favorability -4 is only meaningful if incumbent dyads
#     actually exist there. Incumbents are usually favored, so the low end of the
#     range may be sparse, and a curve evaluated in a region with almost no
#     contribution events is extrapolation rather than estimation. Print the
#     density of incumbent dyads and events across the range.

suppressPackageStartupMessages({ library(dplyr); library(fixest); library(gtools) })
PATH <- "/htaa/hhe/projects/election_buying/"
OUT  <- paste0(PATH, "model/sector_alignment/")

d <- readRDS(paste0(PATH, "cand_model_data_v2.RDS"))
d$ind_partisan[trimws(d$ind_partisan) == ""] <- NA_character_
d <- d %>% filter(!is.na(ind_partisan), !is.na(ind_partisan_score))
d$incumbency <- factor(d$incumbency, levels = c("I","C","O"))
d$party <- factor(d$party, levels = c("DEMOCRAT","REPUBLICAN"))
d$incumbency_bin <- factor(ifelse(d$incumbency == "I","Incumbent","NonIncumbent"),
                           levels = c("Incumbent","NonIncumbent"))

# ---------------- (2) support at the low end, for incumbents -----------------
cat("=== SUPPORT: incumbent dyads and contribution events by favorability ===\n")
sup <- d %>% filter(incumbency_bin == "Incumbent") %>%
  mutate(bin = cut(favorability, breaks = c(-4.01,-3,-2,-1,0,1,2,3,4.01),
                   labels = c("[-4,-3]","(-3,-2]","(-2,-1]","(-1,0]","(0,1]","(1,2]","(2,3]","(3,4]"))) %>%
  group_by(bin) %>%
  summarise(dyads = n(), events = sum(contribute == 1, na.rm = TRUE),
            rate = round(100*mean(contribute == 1, na.rm = TRUE), 3), .groups = "drop")
print(as.data.frame(sup), row.names = FALSE)

cat("\n  Republican incumbents only, low end:\n")
print(as.data.frame(d %>% filter(incumbency_bin == "Incumbent", party == "REPUBLICAN",
                                 favorability <= -2) %>%
  mutate(bin = cut(favorability, c(-4.01,-3,-2), labels = c("[-4,-3]","(-3,-2]"))) %>%
  group_by(bin) %>% summarise(dyads = n(), events = sum(contribute == 1, na.rm = TRUE),
                              .groups = "drop")), row.names = FALSE)

# ---------------- (1) continuous alignment intensity -------------------------
s <- d$ind_partisan_score
d$sco_co    <- pmax(s, 0) * (d$party == "REPUBLICAN")   # GOP-side, co-partisan
d$sco_cross <- pmax(s, 0) * (d$party == "DEMOCRAT")
d$sdm_co    <- pmax(-s, 0) * (d$party == "DEMOCRAT")
d$sdm_cross <- pmax(-s, 0) * (d$party == "REPUBLICAN")

DUMS <- c("sco_co","sco_cross","sdm_co","sdm_cross")
curve <- paste(sapply(DUMS, function(v)
  sprintf("(favorability + favorability_sq) * %s * incumbency_bin", v)), collapse = " + ")
rhs <- paste("special + private + foreign + same_state + log(firm_cash) + party + incumbency",
             "(favorability + favorability_sq) * incumbency_bin", curve, sep = " + ")

cat("\nfitting continuous-intensity model...\n")
m <- feglm(as.formula(paste("contribute ~", rhs, "| state + year")),
           data = d, family = binomial("logit"), cluster = ~ cmte_id + candidate_id)
saveRDS(m, paste0(OUT, "ALIGN_INTENSITY.RDS"))
writeLines(capture.output(summary(m)), paste0(OUT, "ALIGN_INTENSITY_coefficients.txt"))
cat("N =", format(nobs(m), big.mark = ","), "\n")

cf <- coef(m); V <- vcov(m)
pick <- function(k, parts) {
  cands <- apply(permutations(length(parts), length(parts)), 1,
                 function(ix) paste(parts[ix], collapse = ":"))
  hit <- cands[cands %in% names(k)]
  if (!length(hit)) stop("none of: ", paste(cands, collapse = " | "))
  k[[hit[1]]]
}
# co-partisan INCUMBENT log-odds difference from a non-advantaged firm (score 0),
# at alignment intensity `sc` and favorability `f`. Incumbent is the reference
# level of incumbency_bin, so only the base score terms enter.
fn <- function(k) function(f, sc)
  sc * ( pick(k,"sco_co") + pick(k,c("favorability","sco_co"))*f +
         pick(k,c("favorability_sq","sco_co"))*f^2 )
dm <- function(f, sc, eps = 1e-6) {
  val <- fn(cf)(f, sc); g <- numeric(length(cf))
  for (i in seq_along(cf)) { u<-cf; u[i]<-u[i]+eps; l<-cf; l[i]<-l[i]-eps
    g[i] <- (fn(u)(f,sc) - fn(l)(f,sc))/(2*eps) }
  c(val, sqrt(as.numeric(t(g) %*% V %*% g)))
}
cat("\n=== co-partisan INCUMBENT odds ratio vs non-advantaged, by alignment intensity ===\n")
cat("    (score 0.25 = weakly aligned industry; 1.00 = most aligned)\n\n")
cat(sprintf("  %-6s", "f"));  for (sc in c(0.25,0.50,0.75,1.00)) cat(sprintf("  score=%.2f   ", sc)); cat("\n")
for (f in c(-4,-3,-2,-1,0,1,2,3,4)) {
  cat(sprintf("  %+-6d", f))
  for (sc in c(0.25,0.50,0.75,1.00)) {
    r <- dm(f, sc)
    cat(sprintf("  %5.2f%-6s", exp(r[1]),
                if (2*pnorm(-abs(r[1]/r[2])) < 0.05) "*" else ""))
  }
  cat("\n")
}
cat("\nDone.\n")
