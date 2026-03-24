###############################################################################
###
### step3_extract_pairs.R  — Extract longitudinal pair data for Margins scatter
###
### Loads a large Copula_Sensitivity .Rdata file, extracts a specific
### grade-pair cohort, classifies every student as stayer / leaver / entrant,
### and writes a compact intermediate CSV consumed by step3_export_data.R.
###
### Run ONCE (or when you change the cohort specification).
### Not called automatically by step3_build_pstricks.R because the .Rdata
### files are large and this step only needs to run when the source changes.
###
### Usage:
###   source("step3_extract_pairs.R")          # from Margins/ directory
###   source("step3_extract_pairs.R")          # or via step3_build_pstricks.R
###
###############################################################################

cat("\n=== Step 3 – Extract Longitudinal Pairs ===\n\n")

require(data.table)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

script_file <- sub("^--file=", "", commandArgs(trailingOnly = FALSE)[
  grep("^--file=", commandArgs(trailingOnly = FALSE))][1])
margins_dir <- if (!is.na(script_file) && nzchar(script_file)) {
  normalizePath(dirname(script_file), winslash = "/", mustWork = TRUE)
} else {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

# Path to longitudinal_pairs helper (copied into Margins/ or sourced from uploads)
lp_file <- file.path(margins_dir, "longitudinal_pairs.R")
if (!file.exists(lp_file)) {
  stop("Cannot find longitudinal_pairs.R at:\n  ", lp_file,
       "\n  Copy it to the Margins/ directory first.")
}
source(lp_file)

data_dir <- file.path(margins_dir, "data")
if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)


# ---------------------------------------------------------------------------
# Configuration — CHANGE THESE to select a different cohort
# ---------------------------------------------------------------------------

# Path to the .Rdata file (relative to the project root)
rdata_path <- file.path(
  normalizePath(file.path(margins_dir, "../../../../Data"), mustWork = TRUE),
  "Copula_Sensitivity_Data_Set_1.Rdata"
)

# Cohort specification
config <- list(
  dataset_id    = "dataset_1",
  grade_prior   = 5,
  grade_current = 6,
  year_prior    = "2008",         # year_current derived: 2008 + (6-5) = 2009
  content_prior = "MATHEMATICS",
  content_current = NULL,         # same as content_prior
  min_valid_score = 200
)

# Output intermediate file
output_csv <- file.path(data_dir, "longitudinal_pairs.csv")

cat("  .Rdata     :", rdata_path, "\n")
cat("  Cohort     : Grade", config$grade_prior, "->", config$grade_current,
    config$content_prior, config$year_prior, "\n")
cat("  Output CSV :", output_csv, "\n\n")


# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------

cat("Loading .Rdata file (this may take a moment)...\n")
load_env <- new.env()
load(rdata_path, envir = load_env)

# The object name matches the file stem
obj_name <- ls(load_env)[1]
DATA <- load_env[[obj_name]]
cat("  Loaded", obj_name, ":", format(nrow(DATA), big.mark = ","), "rows\n")

# Ensure GRADE is numeric for the pairing function
if (is.character(DATA$GRADE)) {
  DATA[, GRADE := as.integer(GRADE)]
}

# Derive current year
year_current <- as.character(as.numeric(config$year_prior) +
                             (config$grade_current - config$grade_prior))


# ---------------------------------------------------------------------------
# Extract prior-year and current-year cohorts
# ---------------------------------------------------------------------------

cat("\nExtracting cohorts...\n")

prior_cohort <- DATA[GRADE == config$grade_prior &
                     YEAR == config$year_prior &
                     CONTENT_AREA == config$content_prior &
                     !is.na(SCALE_SCORE) &
                     SCALE_SCORE >= config$min_valid_score,
                     .(ID, SCALE_SCORE_PRIOR = SCALE_SCORE,
                       DISTRICT_NUMBER, SCHOOL_NUMBER)]

current_cohort <- DATA[GRADE == config$grade_current &
                       YEAR == year_current &
                       CONTENT_AREA == config$content_prior &
                       !is.na(SCALE_SCORE) &
                       SCALE_SCORE >= config$min_valid_score,
                       .(ID, SCALE_SCORE_CURRENT = SCALE_SCORE,
                         DISTRICT_NUMBER, SCHOOL_NUMBER)]

cat("  Prior  (Grade", config$grade_prior, config$year_prior, "):",
    format(nrow(prior_cohort), big.mark = ","), "students\n")
cat("  Current (Grade", config$grade_current, year_current, "):",
    format(nrow(current_cohort), big.mark = ","), "students\n")

# Free the big object
rm(DATA, load_env)
gc(verbose = FALSE)


# ---------------------------------------------------------------------------
# Classify: stayers / leavers / entrants
# ---------------------------------------------------------------------------

cat("\nClassifying stayers / leavers / entrants...\n")

# Stayers: present in both years (inner join)
stayers <- merge(prior_cohort, current_cohort[, .(ID, SCALE_SCORE_CURRENT)],
                 by = "ID")
stayers[, TYPE := "stayer"]

# Leavers: in prior only (no current match)
leaver_ids <- setdiff(prior_cohort$ID, current_cohort$ID)
leavers <- prior_cohort[ID %in% leaver_ids]
leavers[, `:=`(SCALE_SCORE_CURRENT = NA_real_, TYPE = "leaver")]

# Entrants: in current only (no prior match)
entrant_ids <- setdiff(current_cohort$ID, prior_cohort$ID)
entrants <- current_cohort[ID %in% entrant_ids]
entrants[, `:=`(SCALE_SCORE_PRIOR = NA_real_, TYPE = "entrant")]

# Combine
pairs_all <- rbindlist(list(stayers, leavers, entrants),
                       use.names = TRUE, fill = TRUE)

cat("  Stayers  :", format(nrow(stayers),  big.mark = ","), "\n")
cat("  Leavers  :", format(nrow(leavers),  big.mark = ","), "\n")
cat("  Entrants :", format(nrow(entrants), big.mark = ","), "\n")
cat("  Total    :", format(nrow(pairs_all), big.mark = ","), "\n")

match_rate <- round(100 * nrow(stayers) / max(nrow(prior_cohort), nrow(current_cohort)), 1)
cat("  Match rate:", match_rate, "%\n")


# ---------------------------------------------------------------------------
# Add metadata columns
# ---------------------------------------------------------------------------

pairs_all[, `:=`(
  GRADE_PRIOR   = config$grade_prior,
  GRADE_CURRENT = config$grade_current,
  YEAR_PRIOR    = config$year_prior,
  YEAR_CURRENT  = year_current,
  CONTENT_AREA  = config$content_prior
)]


# ---------------------------------------------------------------------------
# Write intermediate CSV
# ---------------------------------------------------------------------------

cat("\nWriting intermediate CSV...\n")
fwrite(pairs_all, output_csv)

cat("  ", output_csv, "\n")
cat("  ", format(file.size(output_csv), big.mark = ","), "bytes\n")

# Quick district distribution for the target subgroup
cat("\nDistrict '0020' summary:\n")
d0020 <- pairs_all[DISTRICT_NUMBER == "0020"]
cat("  Stayers :", sum(d0020$TYPE == "stayer"), "\n")
cat("  Leavers :", sum(d0020$TYPE == "leaver"), "\n")
cat("  Entrants:", sum(d0020$TYPE == "entrant"), "\n")

cat("\n=== Extraction complete ===\n")
