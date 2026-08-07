# Installs the R packages used across scripts/aggregate/ and scripts/analysis/
# (excluding scripts/analysis/archive/, which is dead/historical code). Run
# once per machine before the R side of the pipeline:
#   Rscript scripts/setup_r_packages.R

required_packages <- c(
    "arrow",
    "dplyr",
    "tidyr",
    "splines",
    "stringr",
    "magrittr",
    "fixest",
    "ggplot2",
    "lmtest",
    "sandwich",
    "stargazer",
    "survival"
)

missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]

if (length(missing_packages) > 0) {
    install.packages(missing_packages)
} else {
    message("All required R packages are already installed.")
}
