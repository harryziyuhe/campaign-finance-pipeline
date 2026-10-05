# Which subsectors carry the DEM label, and does any of them behave like
# Renewables?
#
# Context: at the industry level the DEM bucket gains a great deal of power but
# also produces a well-powered, wrong-signed cross-partisan result, which looks
# like classification leakage rather than behavior. Restricting to industries
# whose parent sector is DEM-classified would collapse the bucket back to
# Renewables alone, so that is not a useful test. Instead, profile each
# DEM-labelled subsector on its own and ask whether any of them shows the
# behavioral signature Renewables shows.
#
# The signature of interest, taken from what Renewables does at sector level:
#   (a) giving tilted toward Democratic candidates over Republican ones;
#   (b) that tilt concentrated among non-incumbents rather than incumbents.
#
# Raw rates are reported alongside a within-group tilt ratio, because groups
# differ enormously in overall giving propensity and raw cross-group comparisons
# are confounded by that (see the project's standing caution on rate ratios).

suppressPackageStartupMessages({ library(dplyr) })
PATH <- "/htaa/hhe/projects/election_buying/"

d <- readRDS(paste0(PATH, "cand_model_data_v2.RDS"))
d <- d %>%
  filter(!is.na(subsec_partisan), trimws(subsec_partisan) != "") %>%
  mutate(cand   = ifelse(party == "REPUBLICAN", "R", "D"),
         ctype  = ifelse(incumbency == "I", "Inc", "NonInc"))

cat("=== subsectors carrying each partisan label ===\n")
lab <- d %>% group_by(subsec_partisan, subsector) %>%
  summarise(firms = n_distinct(cmte_id), dyads = n(),
            events = sum(contribute == 1, na.rm = TRUE),
            score = round(mean(subsec_partisan_score, na.rm = TRUE), 3), .groups = "drop") %>%
  arrange(subsec_partisan, desc(dyads))
print(as.data.frame(lab %>% filter(subsec_partisan == "DEM")), row.names = FALSE)

cat("\n=== profile of each DEM-labelled subsector ===\n")
cat("rate_D / rate_R  = giving rate to Democratic vs Republican candidates\n")
cat("tilt             = rate_D / rate_R  (>1 means tilted Democratic)\n")
cat("tilt_NonInc      = same ratio computed among non-incumbents only\n\n")

dem_subs <- lab %>% filter(subsec_partisan == "DEM") %>% pull(subsector)

prof <- function(sub_name, dat) {
  s <- dat %>% filter(subsector == sub_name)
  r <- function(x) if (nrow(x) == 0) NA_real_ else 100*mean(x$contribute == 1, na.rm = TRUE)
  rD  <- r(s %>% filter(cand == "D")); rR <- r(s %>% filter(cand == "R"))
  rDn <- r(s %>% filter(cand == "D", ctype == "NonInc"))
  rRn <- r(s %>% filter(cand == "R", ctype == "NonInc"))
  evD <- sum(s$contribute[s$cand == "D"] == 1, na.rm = TRUE)
  evR <- sum(s$contribute[s$cand == "R"] == 1, na.rm = TRUE)
  evDn <- sum(s$contribute[s$cand == "D" & s$ctype == "NonInc"] == 1, na.rm = TRUE)
  data.frame(subsector = substr(sub_name, 1, 34),
             firms = n_distinct(s$cmte_id), events = evD + evR,
             rate_D = round(rD, 3), rate_R = round(rR, 3),
             tilt = round(rD / rR, 2),
             ev_D = evD, ev_R = evR,
             tilt_NonInc = round(rDn / rRn, 2), ev_D_NonInc = evDn)
}
out <- do.call(rbind, lapply(dem_subs, prof, dat = d))
print(out[order(-out$events), ], row.names = FALSE)

cat("\n=== benchmark: Renewables at the sector level ===\n")
dr <- readRDS(paste0(PATH, "cand_model_data_v2.RDS")) %>%
  filter(category == "Renewables") %>%
  mutate(cand = ifelse(party == "REPUBLICAN", "R", "D"),
         ctype = ifelse(incumbency == "I", "Inc", "NonInc"))
r <- function(x) 100*mean(x$contribute == 1, na.rm = TRUE)
cat(sprintf("  firms %d | rate_D %.3f%% | rate_R %.3f%% | tilt %.2f | ev_D %d | ev_R %d\n",
            n_distinct(dr$cmte_id), r(dr %>% filter(cand=="D")), r(dr %>% filter(cand=="R")),
            r(dr %>% filter(cand=="D"))/r(dr %>% filter(cand=="R")),
            sum(dr$contribute[dr$cand=="D"]==1, na.rm=TRUE),
            sum(dr$contribute[dr$cand=="R"]==1, na.rm=TRUE)))
cat(sprintf("  non-incumbents only: tilt %.2f | ev_D %d\n",
            r(dr %>% filter(cand=="D", ctype=="NonInc"))/r(dr %>% filter(cand=="R", ctype=="NonInc")),
            sum(dr$contribute[dr$cand=="D" & dr$ctype=="NonInc"]==1, na.rm=TRUE)))

cat("\n=== for reference: GOP-labelled subsectors, same statistics ===\n")
gop_subs <- lab %>% filter(subsec_partisan == "GOP") %>% arrange(desc(dyads)) %>% head(8) %>% pull(subsector)
print(do.call(rbind, lapply(gop_subs, prof, dat = d)), row.names = FALSE)

cat("\nDone.\n")
