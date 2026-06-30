library(shiny)
library(dplyr)
library(tidyr)
library(readr)
library(ggplot2)
library(plotly)

# ============================================================
# DATA SOURCE CONFIGURATION
# ------------------------------------------------------------
# `server_link` is the base location where the pre-modeled ESTIMATES are hosted.
# The app reads each country's file from:
#
#   server_link + "Gates_Indicator_Comparison/estimates/" + Country + "/combined_results.csv"
#
# IMPORTANT: this is the DATA location, which is NOT the same as the URL where
# the app is deployed. The app is served to users at
#   https://sites.stat.washington.edu/indicatorcomparison/
# (configured by the UW Stats reverse proxy), but it pulls its data from a
# SEPARATE internal server location. This mirrors sae4health, which is served at
#   https://sites.stat.washington.edu/sae4health/
# yet reads its DHS_survey_dat from a different internal link.
#
# Set `server_link` to that internal data URL via the INDICATOR_SERVER_LINK
# environment variable at deploy time (get the value from UW Stats IT -- see
# email_to_Asa.md). It can also be a local folder for development (read from disk
# instead of over http); load_country_data() detects which automatically.
#
# The unset default below is a local Dropbox mirror for development only.
# ============================================================
server_link <- Sys.getenv(
  "INDICATOR_SERVER_LINK",
  # Development fallback (local data mirror). Production sets INDICATOR_SERVER_LINK
  # to the internal estimates URL provided by UW Stats IT.
  unset = "/Users/victoriaknutson/Library/CloudStorage/Dropbox/GATES/Gates-results/estimates"
)

# Subfolder (under server_link) that holds the pre-modeled estimates.
estimates_subdir <- "Gates_Indicator_Comparison/estimates"

# Countries with pre-modeled estimates
available_countries <- c(
  "Burkina Faso",
  "Congo Democratic Republic",
  "Ethiopia",
  "Kenya",
  "Malawi",
  "Mali",
  "Mozambique",
  "Nigeria",
  "Rwanda",
  "Senegal",
  "Sierra Leone",
  "South Africa",
  "Tanzania",
  "Zambia"
)

# ------------------------------------------------------------
# Build the full path to a country's estimates file.
# Trailing slash on server_link is optional (handled here).
# Country names are URL-encoded so spaces (e.g. "Burkina Faso") work over http.
# ------------------------------------------------------------
build_country_path <- function(server_link, country) {
  base <- sub("/+$", "", server_link)
  is_remote <- grepl("^https?://", base, ignore.case = TRUE)
  country_seg <- if (is_remote) {
    utils::URLencode(country, reserved = TRUE)
  } else {
    country
  }
  paste0(base, "/", estimates_subdir, "/", country_seg, "/combined_results.csv")
}

# ------------------------------------------------------------
# Load a country's combined_results.csv from the server (http) or local disk.
# Returns list(data = <tibble or NULL>, error = <message or NULL>).
# ------------------------------------------------------------
load_country_data <- function(server_link, country) {
  path <- build_country_path(server_link, country)
  is_remote <- grepl("^https?://", path, ignore.case = TRUE)

  if (!is_remote && !file.exists(path)) {
    return(list(data = NULL, error = paste0("File not found:\n", path)))
  }

  tryCatch({
    con <- if (is_remote) url(path) else path
    df  <- readr::read_csv(con, show_col_types = FALSE)
    list(data = df, error = NULL)
  }, error = function(e) {
    list(data = NULL, error = paste0(
      "Could not load estimates for ", country, ".\n",
      "Path: ", path, "\n",
      "Error: ", conditionMessage(e)
    ))
  })
}

# ------------------------------------------------------------
# Indicator label lookup.
# Uses a vendored copy of surveyPrev::indicatorList (data/indicatorList.csv)
# so descriptions work on the server without installing the heavy surveyPrev
# package. Falls back to surveyPrev if the vendored file is missing, then to
# the raw indicator ID.
# ------------------------------------------------------------
.indicator_lookup <- local({
  f <- file.path("data", "indicatorList.csv")
  if (file.exists(f)) {
    tryCatch(readr::read_csv(f, show_col_types = FALSE), error = function(e) NULL)
  } else {
    NULL
  }
})

get_indicator_label <- function(indicator_id) {
  desc <- NULL

  if (!is.null(.indicator_lookup)) {
    desc <- .indicator_lookup$Description[.indicator_lookup$ID == indicator_id]
  }

  if ((length(desc) == 0 || is.na(desc[1])) &&
      requireNamespace("surveyPrev", quietly = TRUE)) {
    desc <- surveyPrev::indicatorList$Description[
      surveyPrev::indicatorList$ID == indicator_id
    ]
  }

  if (length(desc) > 0 && !is.na(desc[1]) && nchar(trimws(desc[1])) > 0) {
    label <- trimws(desc[1])
    if (nchar(label) > 100) label <- paste0(substr(label, 1, 97), "...")
    return(label)
  }

  indicator_id
}
