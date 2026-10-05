suppressPackageStartupMessages({ library(dplyr); library(fixest) })

# =============================================================================
# Reviewer comment: "control for control of Congress, and for the expectation
# that control of Congress would flip."
#
# Three things are done here, in order:
#
#   (A) LITERAL READING. Both quantities are constant within an election cycle,
#       so the year fixed effects already in every model absorb them exactly.
#       Spec A adds them as regressors and shows fixest drops them for
#       collinearity with the year FE. This is the demonstration for the
#       response letter: the control is already in the paper.
#
#   (B) MEASURE. Build an ex ante expectation of partisan control from the
#       SAME Inside Elections ratings used for Chance of Winning, so no new
#       data source is required. For each district-year, map the race rating
#       to Pr(Democrat wins); sum across districts for expected Democratic
#       seats; compare to 218 for Pr(Democratic majority); combine with the
#       pre-election House majority for Pr(control flips).
#
#   (C) SUBSTANTIVE READING. The interesting version of the comment is not a
#       level control but a MODERATOR: do partisan-advantaged firms behave
#       differently when the majority is actually in play? Spec C interacts
#       the full alignment block with a majority-in-play indicator and runs a
#       joint Wald test on that block (per the house convention of testing
#       poolability rather than asserting a split).
#
# CAVEAT carried into the write-up: the panel has 7 cycles and 3 of them are
# majority-in-play, so this moderator has ~7 effective observations. SEs are
# clustered by firm and candidate as everywhere else, which does NOT absorb
# cycle-level correlation. Read Spec C as descriptive, not as a powered test.
# =============================================================================
PATH    <- "/htaa/hhe/projects/election_buying/"
OUT_DIR <- paste0(PATH, "model/sector_alignment/")

.args     <- commandArgs(trailingOnly = TRUE)
DATA_NAME <- if (length(.args) >= 1) .args[1] else "cand_model_data_v2"
SUFFIX    <- if (length(.args) >= 2) .args[2] else ""

cat("Input data: ", DATA_NAME, ".RDS\n\n", sep = "")
cand_data <- readRDS(paste0(PATH, DATA_NAME, ".RDS"))

# ---------------------------------------------------------------- (B) measure
# rating is race-level and signed: +4 = Solid Democrat, -4 = Solid Republican.
races <- cand_data %>% distinct(year, state, district, rating) %>% filter(!is.na(rating))
stopifnot(nrow(races %>% count(year, state, district) %>% filter(n > 1)) == 0)

# |rating| -> Pr(favored candidate wins); Inside Elections category anchors
#   0 toss-up .50 | 1 tilt .60 | 2 lean .75 | 3 likely .90 | 4 solid .97
p_fav  <- approxfun(c(0, 1, 2, 3, 4), c(.50, .60, .75, .90, .97), rule = 2)
races  <- races %>% mutate(p_dem = ifelse(rating >= 0, p_fav(abs(rating)), 1 - p_fav(abs(rating))))

# pre-election House majority, by cycle
house_pre <- c(`2010` = "DEM", `2012` = "GOP", `2014` = "GOP", `2016` = "GOP",
               `2018` = "GOP", `2020` = "DEM", `2022` = "DEM")

cyc <- races %>%
  group_by(year) %>%
  summarise(districts = n(), exp_dem = sum(p_dem),
            sd_ind = sqrt(sum(p_dem * (1 - p_dem))), .groups = "drop") %>%
  mutate(exp_dem_seats = exp_dem * 435 / districts,
         # independent-district sd understates true seat variance because a
         # common national swing correlates districts. Inflate with a national
         # component so Pr() is not absurdly confident at the tails; results
         # below are reported for BOTH the raw and inflated versions.
         sd_natl   = sqrt(sd_ind^2 + 15^2),
         pr_dem_maj_ind  = pnorm((exp_dem_seats - 217.5) / sd_ind),
         pr_dem_maj_natl = pnorm((exp_dem_seats - 217.5) / sd_natl),
         pre = house_pre[as.character(year)],
         pr_flip_ind  = ifelse(pre == "DEM", 1 - pr_dem_maj_ind,  pr_dem_maj_ind),
         pr_flip_natl = ifelse(pre == "DEM", 1 - pr_dem_maj_natl, pr_dem_maj_natl),
         majority_in_play = as.integer(pr_flip_natl > 0.25))

cat("=== (B) ex ante expectation of House control, by cycle ===\n")
print(as.data.frame(cyc %>% select(year, exp_dem_seats, sd_ind, sd_natl,
                                   pr_dem_maj_ind, pr_dem_maj_natl,
                                   pre, pr_flip_ind, pr_flip_natl, majority_in_play)),
      digits = 4)
write.csv(cyc, paste0(OUT_DIR, "congress_control_measure", SUFFIX, ".csv"), row.names = FALSE)

cand_data <- cand_data %>%
  left_join(cyc %>% select(year, exp_dem_seats, pr_flip = pr_flip_natl, majority_in_play),
            by = "year")

# ------------------------------------------------------------ shared recoding
cand_data$singlename_partisan_pre <- factor(cand_data$singlename_partisan_pre, levels = c("Other", "GOP", "DEM"))
cand_data$incumbency     <- factor(cand_data$incumbency, levels = c("I", "C", "O"))
cand_data$incumbency_bin <- factor(ifelse(cand_data$incumbency == "I", "Incumbent", "NonIncumbent"),
                                   levels = c("Incumbent", "NonIncumbent"))
cand_data$party <- factor(cand_data$party, levels = c("DEMOCRAT", "REPUBLICAN"))

cand_data$co_partisan_GOP    <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "GOP")
cand_data$cross_partisan_GOP <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "GOP")
cand_data$co_partisan_DEM    <- as.integer(cand_data$party == "DEMOCRAT"   & cand_data$singlename_partisan_pre == "DEM")
cand_data$cross_partisan_DEM <- as.integer(cand_data$party == "REPUBLICAN" & cand_data$singlename_partisan_pre == "DEM")

DUMMIES <- c("co_partisan_GOP", "cross_partisan_GOP", "co_partisan_DEM", "cross_partisan_DEM")

cat("\n=== dyads by cycle type and alignment ===\n")
print(cand_data %>% group_by(majority_in_play) %>%
      summarise(dyads = n(), contribs = sum(contribute == 1, na.rm = TRUE),
                gop_co = sum(co_partisan_GOP, na.rm = TRUE), dem_co = sum(co_partisan_DEM, na.rm = TRUE), .groups = "drop"))
cat("\n-- thin-cell check: co-partisan NON-incumbent contributions by cycle type --\n")
print(cand_data %>% filter(incumbency_bin == "NonIncumbent", contribute == 1) %>%
      group_by(majority_in_play) %>%
      summarise(gop_co = sum(co_partisan_GOP, na.rm = TRUE), dem_co = sum(co_partisan_DEM, na.rm = TRUE), .groups = "drop"))

base_controls <- "special + private + foreign + same_state + log(firm_cash)"
align_block <- paste(unlist(lapply(DUMMIES, function(d) c(
  d, paste0("favorability:", d), paste0("favorability_sq:", d),
  paste0(d, ":incumbency_bin"),
  paste0("favorability:", d, ":incumbency_bin"),
  paste0("favorability_sq:", d, ":incumbency_bin")))), collapse = " + ")
base_curve <- "favorability * incumbency * party + favorability_sq * incumbency * party"

# ------------------------------------------------- (A) literal reading: absorbed
cat("\n", strrep("=", 70), "\n(A) LITERAL READING: add the cycle-level controls to the paper's model\n",
    strrep("=", 70), "\n", sep = "")
fmlaA <- as.formula(paste("contribute ~", base_controls, "+ exp_dem_seats + pr_flip +",
                          base_curve, "+", align_block, "| state + year"))
t0 <- Sys.time()
modA <- feglm(fmlaA, data = cand_data, family = binomial(link = "logit"),
              cluster = ~ cmte_id + candidate_id)
cat("fit time (A):", round(as.numeric(Sys.time() - t0, units = "mins"), 2), "min\n")
cfA <- names(coef(modA))
cat("\nexp_dem_seats retained in the fit? ", "exp_dem_seats" %in% cfA, "\n", sep = "")
cat("pr_flip retained in the fit?       ", "pr_flip" %in% cfA, "\n", sep = "")
cat("--> if FALSE, both are collinear with the year FE and the paper already controls for them.\n")
if (!is.null(modA$collin.var)) { cat("\nfixest-reported collinear variables removed:\n"); print(modA$collin.var) }
saveRDS(modA, paste0(OUT_DIR, "CONGRESS_CONTROL_LEVELS", SUFFIX, ".RDS"))
writeLines(capture.output(summary(modA)),
           paste0(OUT_DIR, "CONGRESS_CONTROL_LEVELS", SUFFIX, "_coefficients.txt"))
rm(modA); gc(verbose = FALSE)

# ------------------------------------- (C) substantive reading: as a moderator
cat("\n", strrep("=", 70), "\n(C) SUBSTANTIVE READING: alignment block x majority-in-play\n",
    strrep("=", 70), "\n", sep = "")
mip_block <- paste(unlist(lapply(DUMMIES, function(d) c(
  paste0(d, ":majority_in_play"),
  paste0("favorability:", d, ":majority_in_play"),
  paste0("favorability_sq:", d, ":majority_in_play"),
  paste0(d, ":incumbency_bin:majority_in_play"),
  paste0("favorability:", d, ":incumbency_bin:majority_in_play"),
  paste0("favorability_sq:", d, ":incumbency_bin:majority_in_play")))), collapse = " + ")
# let the BASELINE curve differ by cycle type too, so a cycle-type difference in
# the common curve cannot load onto the alignment interactions
base_curve_mip <- paste("favorability * incumbency * party * majority_in_play",
                        "favorability_sq * incumbency * party * majority_in_play", sep = " + ")
fmlaC <- as.formula(paste("contribute ~", base_controls, "+", base_curve_mip, "+",
                          align_block, "+", mip_block, "| state + year"))
t0 <- Sys.time()
modC <- feglm(fmlaC, data = cand_data, family = binomial(link = "logit"),
              cluster = ~ cmte_id + candidate_id)
cat("fit time (C):", round(as.numeric(Sys.time() - t0, units = "mins"), 2), "min\n")
saveRDS(modC, paste0(OUT_DIR, "CONGRESS_CONTROL_MODERATOR", SUFFIX, ".RDS"))
writeLines(capture.output(summary(modC)),
           paste0(OUT_DIR, "CONGRESS_CONTROL_MODERATOR", SUFFIX, "_coefficients.txt"))

cf <- coef(modC); V <- vcov(modC)
# fixest may order interaction components either way; match on component sets
find_coef <- function(parts) {
  target <- sort(parts)
  hit <- names(cf)[vapply(strsplit(names(cf), ":", fixed = TRUE),
                          function(p) identical(sort(p), target), logical(1))]
  if (length(hit) == 1) hit else NA_character_
}
expand <- function(d, with_fav = NULL, noninc = FALSE, mip = FALSE) {
  parts <- d
  if (!is.null(with_fav)) parts <- c(with_fav, parts)
  if (noninc) parts <- c(parts, "incumbency_binNonIncumbent")
  if (mip)    parts <- c(parts, "majority_in_play")
  find_coef(parts)
}

cat("\n--- joint Wald test: does ANY alignment term differ by cycle type? ---\n")
mip_names <- unique(na.omit(unlist(lapply(DUMMIES, function(d)
  c(expand(d, mip = TRUE), expand(d, "favorability", mip = TRUE),
    expand(d, "favorability_sq", mip = TRUE),
    expand(d, noninc = TRUE, mip = TRUE),
    expand(d, "favorability", noninc = TRUE, mip = TRUE),
    expand(d, "favorability_sq", noninc = TRUE, mip = TRUE))))))
cat("terms in the tested block:", length(mip_names), "\n")
wald_block <- function(nms) {
  nms <- nms[nms %in% names(cf)]
  if (!length(nms)) return(invisible(cat("  (no estimable terms)\n")))
  b <- cf[nms]; Vb <- V[nms, nms, drop = FALSE]
  st <- tryCatch(as.numeric(t(b) %*% solve(Vb) %*% b), error = function(e) NA_real_)
  cat(sprintf("  chi2 = %.2f on %d df, p = %.4g\n", st, length(nms), pchisq(st, length(nms), lower.tail = FALSE)))
}
wald_block(mip_names)

cat("\n--- same test, restricted to the GOP co-partisan block (the headline result) ---\n")
wald_block(na.omit(c(expand("co_partisan_GOP", mip = TRUE),
                     expand("co_partisan_GOP", "favorability", mip = TRUE),
                     expand("co_partisan_GOP", "favorability_sq", mip = TRUE),
                     expand("co_partisan_GOP", noninc = TRUE, mip = TRUE),
                     expand("co_partisan_GOP", "favorability", noninc = TRUE, mip = TRUE),
                     expand("co_partisan_GOP", "favorability_sq", noninc = TRUE, mip = TRUE))))

# ------ co-partisan odds ratios vs non-advantaged, by cycle type and type ----
delta_method <- function(fn, eps = 1e-6) {
  val <- fn(cf); grad <- numeric(length(cf))
  for (i in seq_along(cf)) {
    up <- cf; up[i] <- up[i] + eps; dn <- cf; dn[i] <- dn[i] - eps
    grad[i] <- (fn(up) - fn(dn)) / (2 * eps)
  }
  se <- sqrt(as.numeric(t(grad) %*% V %*% grad))
  c(est = val, se = se)
}
log_or_fn <- function(d, type, mip) function(k) {
  gg <- function(nm) if (!is.na(nm) && nm %in% names(k)) k[[nm]] else 0
  lvl  <- gg(expand(d)); lin <- gg(expand(d, "favorability")); qd <- gg(expand(d, "favorability_sq"))
  if (type == "NonIncumbent") {
    lvl <- lvl + gg(expand(d, noninc = TRUE))
    lin <- lin + gg(expand(d, "favorability", noninc = TRUE))
    qd  <- qd  + gg(expand(d, "favorability_sq", noninc = TRUE))
  }
  if (mip == 1) {
    lvl <- lvl + gg(expand(d, mip = TRUE))
    lin <- lin + gg(expand(d, "favorability", mip = TRUE))
    qd  <- qd  + gg(expand(d, "favorability_sq", mip = TRUE))
    if (type == "NonIncumbent") {
      lvl <- lvl + gg(expand(d, noninc = TRUE, mip = TRUE))
      lin <- lin + gg(expand(d, "favorability", noninc = TRUE, mip = TRUE))
      qd  <- qd  + gg(expand(d, "favorability_sq", noninc = TRUE, mip = TRUE))
    }
  }
  function(f) lvl + lin * f + qd * f^2
}

GRID <- c(-4, -2, 0, 2, 4)
rows <- list()
for (d in c("co_partisan_GOP", "co_partisan_DEM"))
  for (type in c("Incumbent", "NonIncumbent"))
    for (mip in c(0, 1))
      for (f in GRID) {
        r <- delta_method(function(k) log_or_fn(d, type, mip)(k)(f))
        rows[[length(rows) + 1]] <- data.frame(
          dummy = d, type = type, majority_in_play = mip, favorability = f,
          or = exp(r["est"]), or_lo = exp(r["est"] - 1.96 * r["se"]),
          or_hi = exp(r["est"] + 1.96 * r["se"]),
          p = 2 * pnorm(-abs(r["est"] / r["se"])), row.names = NULL)
      }
res <- do.call(rbind, rows)
cat("\n--- odds of support vs a non-advantaged firm facing the same candidate ---\n")
for (d in unique(res$dummy)) for (ty in unique(res$type)) {
  cat(sprintf("\n[%s / %s]\n", d, ty))
  sub <- res %>% filter(dummy == d, type == ty)
  for (mip in c(0, 1)) {
    s <- sub %>% filter(majority_in_play == mip) %>% arrange(favorability)
    cat(sprintf("  majority %-8s: ", ifelse(mip == 1, "IN PLAY", "safe")))
    cat(paste(sprintf("%+d: %.2f%s", s$favorability, s$or,
                      ifelse(s$p < .01, "***", ifelse(s$p < .05, "**", ifelse(s$p < .1, "*", "")))),
              collapse = "  "), "\n")
  }
}
write.csv(res, paste0(OUT_DIR, "congress_control_odds", SUFFIX, ".csv"), row.names = FALSE)
cat("\nDone.\n")
