# Do the MOST strongly Republican-aligned industries rescue their own endangered
suppressPackageStartupMessages(library(gtools))
# incumbents, even though the Republican-advantaged bucket as a whole does not?
#
# Hypothesis 2a predicts that partisan-advantaged firms concentrate support on
# co-partisan incumbents whose seats are at risk. The paper finds no such
# concentration for the Republican-advantaged sector as a whole. One reading is
# that the mechanism is real but diluted: the sector-level bucket contains firms
# whose partisan stake is modest, and averaging over them could wash out
# behaviour present in the most intensely aligned industries. Oil and gas is the
# natural test case -- it gives to Republicans at more than five times its
# Democratic rate, and at roughly sixteen times among non-incumbents.
#
# Design: split the Republican-advantaged industries into a STRONG group and the
# remainder, and let each have its own full curve by candidate type. Then compute
# the same quantity the paper reports for Cell 1 -- the odds of an aligned firm
# supporting a co-partisan INCUMBENT relative to a non-advantaged firm facing the
# same candidate -- across the electoral-risk range. Concentration on endangered
# co-partisan incumbents would appear as an odds ratio above one at low
# favorability, declining as the seat becomes safe.

suppressPackageStartupMessages({ library(dplyr); library(fixest) })
PATH <- "/htaa/hhe/projects/election_buying/"
OUT  <- paste0(PATH, "model/sector_alignment/")

d <- readRDS(paste0(PATH, "cand_model_data_v2.RDS"))
d$ind_partisan[trimws(d$ind_partisan) == ""] <- NA_character_
d <- d %>% filter(!is.na(ind_partisan), !is.na(industry))
d$incumbency <- factor(d$incumbency, levels = c("I","C","O"))
d$party <- factor(d$party, levels = c("DEMOCRAT","REPUBLICAN"))
d$incumbency_bin <- factor(ifelse(d$incumbency == "I", "Incumbent", "NonIncumbent"),
                           levels = c("Incumbent","NonIncumbent"))

STRONG <- c("Oil & Gas", "Oil & Gas Related Equipment and Services", "Metals & Mining")
cat("=== strongly-aligned industries ===\n")
print(d %>% filter(industry %in% STRONG) %>% group_by(industry) %>%
      summarise(firms = n_distinct(cmte_id), dyads = n(),
                ev_R = sum(contribute == 1 & party == "REPUBLICAN", na.rm = TRUE),
                ev_D = sum(contribute == 1 & party == "DEMOCRAT", na.rm = TRUE),
                .groups = "drop") %>% as.data.frame())

d$grp <- ifelse(d$industry %in% STRONG, "STRONG",
         ifelse(d$ind_partisan == "GOP", "OTHERGOP", "REF"))
d$co_STRONG    <- as.integer(d$party == "REPUBLICAN" & d$grp == "STRONG")
d$cross_STRONG <- as.integer(d$party == "DEMOCRAT"   & d$grp == "STRONG")
d$co_OGOP      <- as.integer(d$party == "REPUBLICAN" & d$grp == "OTHERGOP")
d$cross_OGOP   <- as.integer(d$party == "DEMOCRAT"   & d$grp == "OTHERGOP")

cat("\n=== incumbent cell counts ===\n")
print(d %>% filter(incumbency_bin == "Incumbent") %>%
      group_by(grp, party) %>%
      summarise(dyads = n(), events = sum(contribute == 1, na.rm = TRUE),
                rate = round(100*mean(contribute == 1, na.rm = TRUE), 3), .groups = "drop") %>%
      as.data.frame())

DUMS <- c("co_STRONG","cross_STRONG","co_OGOP","cross_OGOP")
curve <- paste(sapply(DUMS, function(v)
  sprintf("(favorability + favorability_sq) * %s * incumbency_bin", v)), collapse = " + ")
rhs <- paste("special + private + foreign + same_state + log(firm_cash) + party + incumbency",
             "(favorability + favorability_sq) * incumbency_bin", curve, sep = " + ")

cat("\nfitting...\n")
m <- feglm(as.formula(paste("contribute ~", rhs, "| state + year")),
           data = d, family = binomial("logit"), cluster = ~ cmte_id + candidate_id)
saveRDS(m, paste0(OUT, "STRONG_GOP_RESCUE.RDS"))
writeLines(capture.output(summary(m)), paste0(OUT, "STRONG_GOP_RESCUE_coefficients.txt"))
cat("N =", format(nobs(m), big.mark = ","), "\n")

cf <- coef(m); V <- vcov(m)
pick <- function(k, parts) {
  cands <- apply(gtools::permutations(length(parts), length(parts)), 1,
                 function(ix) paste(parts[ix], collapse = ":"))
  hit <- cands[cands %in% names(k)]
  if (!length(hit)) stop("none of: ", paste(cands, collapse = " | "))
  k[[hit[1]]]
}
# Cell 1: co-partisan INCUMBENT vs non-advantaged incumbent (incumbent is the
# reference level of incumbency_bin, so only the base dummy terms enter).
cell1 <- function(dum) function(k) function(f) {
  pick(k, dum) + pick(k, c("favorability", dum))*f + pick(k, c("favorability_sq", dum))*f^2
}
dm <- function(fn, f, eps = 1e-6) {
  val <- fn(cf)(f); g <- numeric(length(cf))
  for (i in seq_along(cf)) { u<-cf; u[i]<-u[i]+eps; l<-cf; l[i]<-l[i]-eps
    g[i] <- (fn(u)(f) - fn(l)(f))/(2*eps) }
  c(val, sqrt(as.numeric(t(g) %*% V %*% g)))
}
for (lbl in c("co_STRONG","co_OGOP")) {
  cat("\n=== Cell 1 (co-partisan incumbents):", lbl, "vs non-advantaged ===\n")
  for (f in c(-4,-3,-2,-1,0,1,2,3,4)) {
    r <- dm(cell1(lbl), f)
    cat(sprintf("  f=%+d  OR=%5.2f  p=%.4g\n", f, exp(r[1]), 2*pnorm(-abs(r[1]/r[2]))))
  }
}
cat("\nDone.\n")
