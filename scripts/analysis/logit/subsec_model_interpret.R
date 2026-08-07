suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(splines)
  library(fixest)
})

# =============================================================================
# 0) Paths + small utilities
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

# =============================================================================
# 1) Regression tables (load-only-when-needed; remove immediately)
# =============================================================================

model_partisan_subsecB_int <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_subsector_int_base.RDS"))
model_partisan_subsecF_int <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_subsector_int_full.RDS"))
model_partisan_indB_int <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_industry_int_base.RDS"))
model_partisan_indF_int <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_industry_int_full.RDS"))
model_partisan_industryB_int <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_all_firm_industry_category_int_base.RDS"))
model_partisan_industryF_int <- readRDS2(file.path(MODEL_PATH, "extensive_partisan_all_firm_industry_category_int_full.RDS"))
etable(
  model_partisan_subsecB_int, model_partisan_subsecF_int,
  model_partisan_indB_int, model_partisan_indF_int,
  model_partisan_industryB_int, model_partisan_industryF_int,
  headers = c("Subsector", "Subsector",
              "Industry", "Industry",
              "Industry Class", "Industry Class"),
  drop = c("category", "state", "year"),
  tex = TRUE,
  file = file.path(TABLE_PATH, "interaction4.tex")
)

rm_gc(model_partisan_subsecB_int, model_partisan_subsecF_int,
      model_partisan_indB_int, model_partisan_indF_int,
      model_partisan_industryB_int, model_partisan_industryF_int)
