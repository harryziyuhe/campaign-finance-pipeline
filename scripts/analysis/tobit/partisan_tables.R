suppressPackageStartupMessages({
  library(dplyr)
  library(stargazer)
})
# =============================================================================

data_root_env <- Sys.getenv("CAMPAIGNFINANCE_DATA_ROOT", unset = "")
if (!nzchar(data_root_env)) {
    stop(
        "CAMPAIGNFINANCE_DATA_ROOT is not set. Point it at the campaign-finance-data folder ",
        "(contains data/ and outputs/), e.g. Sys.setenv(CAMPAIGNFINANCE_DATA_ROOT = ",
        "'C:/Users/<you>/Dropbox/campaign-finance-data')."
    )
}
DATA_ROOT  <- normalizePath(data_root_env, mustWork = TRUE)
MODEL_PATH <- file.path(DATA_ROOT, "outputs", "models", "election")
DATA_PATH  <- file.path(DATA_ROOT, "data", "processed", "modeling")
TABLE_PATH <- file.path(DATA_ROOT, "outputs", "tables")
FIG_PATH   <- file.path(DATA_ROOT, "outputs", "figures")

dir.create(TABLE_PATH, showWarnings = FALSE, recursive = TRUE)
dir.create(FIG_PATH,   showWarnings = FALSE, recursive = TRUE)

# Load one object, use it, then remove it
readRDS2 <- function(path) {
  obj <- readRDS(path)
  obj
}

rm_gc <- function(...) {
  rm(list = as.character(substitute(list(...)))[-1], envir = parent.frame())
  invisible(gc())
}

get_cluster_se <- function(x) {
  cf <- coef(x$model)
  vc <- x$vcov_cluster
  
  if (nrow(vc) < length(cf)) {
    stop("Some coefficients are missing from vcov_cluster.")
  }
  
  vc <- vc[1:length(cf), 1:length(cf), drop = FALSE]
  sqrt(diag(vc))
}

# =============================================================================
# 1) Main Interaction Models
# =============================================================================

model_partisan_SNB_int <- readRDS2(file.path(MODEL_PATH, "tobit_partisan_singlename_pre_int_base.RDS"))
model_partisan_SNF_int <- readRDS2(file.path(MODEL_PATH, "tobit_partisan_singlename_pre_int_full.RDS"))
model_partisan_SNCB_int <- readRDS2(file.path(MODEL_PATH, "tobit_partisan_singlename_score_pre_int_base.RDS"))
model_partisan_SNCF_int <- readRDS2(file.path(MODEL_PATH, "tobit_partisan_singlename_score_pre_int_full.RDS"))

m1 <- model_partisan_SNB_int$model
m2 <- model_partisan_SNF_int$model
m3 <- model_partisan_SNCB_int$model
m4 <- model_partisan_SNCF_int$model

se_list <- list(
  get_cluster_se(model_partisan_SNB_int),
  get_cluster_se(model_partisan_SNF_int),
  get_cluster_se(model_partisan_SNCB_int),
  get_cluster_se(model_partisan_SNCF_int)
)

stargazer(
  m1, m2, m3, m4,
  se = se_list,
  type = "latex",
  out = file.path(TABLE_PATH, "tobit_interaction01.tex"),
  columns.labels = c("Continuous", "Categorical"),
  column.separate = c(2, 2),
  dep.var.caption = "",
  dep.var.labels.include = FALSE,
  omit = c("category", "state", "year"),
  omit.stat = c("ll", "aic"),
  digits = 3
)

rm_gc(model_partisan_SNB_int, model_partisan_SNF_int,
      model_partisan_SNCB_int, model_partisan_SNCF_int)

# =============================================================================
# 2) Industry Interaction Models
# =============================================================================

model_partisan_indB_int <- readRDS2(file.path(MODEL_PATH, "tobit_partisan_industry_int_base.RDS"))
model_partisan_indF_int <- readRDS2(file.path(MODEL_PATH, "tobit_partisan_industry_int_full.RDS"))
model_partisan_industryB_int <- readRDS2(file.path(MODEL_PATH, "tobit_partisan_all_firm_industry_category_int_base.RDS"))
model_partisan_industryF_int <- readRDS2(file.path(MODEL_PATH, "tobit_partisan_all_firm_industry_category_int_full.RDS"))

m1 <- model_partisan_indB_int$model
m2 <- model_partisan_indF_int$model
m3 <- model_partisan_industryB_int$model
m4 <- model_partisan_industryF_int$model

se_list <- list(
  get_cluster_se(model_partisan_indB_int),
  get_cluster_se(model_partisan_indF_int),
  get_cluster_se(model_partisan_industryB_int),
  get_cluster_se(model_partisan_industryF_int)
)

stargazer(
  m1, m2, m3, m4,
  se = se_list,
  type = "latex",
  out = file.path(TABLE_PATH, "tobit_interaction02.tex"),
  columns.labels = c("Industry", "Industry Class"),
  column.separate = c(2, 2),
  dep.var.caption = "",
  dep.var.labels.include = FALSE,
  omit = c("category", "state", "year"),
  omit.stat = c("ll", "aic"),
  digits = 3
)

rm_gc(model_partisan_indB_int, model_partisan_indF_int,
      model_partisan_industryB_int, model_partisan_industryF_int)

# =============================================================================
# 2) Prior Giving Interaction Models
# =============================================================================

model_partisan_giveB_int <- readRDS2(file.path(MODEL_PATH, "tobit_partisan_give_int_base.RDS"))
model_partisan_giveF_int <- readRDS2(file.path(MODEL_PATH, "tobit_partisan_give_int_full.RDS"))

m1 <- model_partisan_giveB_int$model
m2 <- model_partisan_giveF_int$model

se_list <- list(
  get_cluster_se(model_partisan_giveB_int),
  get_cluster_se(model_partisan_giveF_int)
)

stargazer(
  m1, m2,
  se = se_list,
  type = "latex",
  out = file.path(TABLE_PATH, "tobit_interaction03.tex"),
  dep.var.caption = "",
  dep.var.labels.include = FALSE,
  omit = c("category", "state", "year"),
  omit.stat = c("ll", "aic"),
  digits = 3
)

rm_gc(model_partisan_giveB_int, model_partisan_giveF_int)
