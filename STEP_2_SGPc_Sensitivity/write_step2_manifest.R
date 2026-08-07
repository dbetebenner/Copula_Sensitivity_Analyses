############################################################################
### STEP 2.6: Write Consolidated STEP_2 Manifest
###
### Purpose: After all STEP_2 sub-steps (2.1 through 2.5), read every
###          relevant output from disk and write a single consolidated
###          sgpc_sensitivity_manifest.json for reporting and downstream
###          use (STEP_3, STEP_4).
###
### Inputs:  All optional; reads from STEP_2 results and optional STEP_1
###          manifest. Handles missing files without failing.
###
### Output:  STEP_2_SGPc_Sensitivity/results/sgpc_sensitivity_manifest.json
###
### Author: dataimago
### Date: February 2026
############################################################################

require(data.table)
require(jsonlite)

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

RESULTS_DIR <- "STEP_2_SGPc_Sensitivity/results"
STEP1_MANIFEST <- "STEP_1_Family_Selection/results/dataset_all/analysis_manifest.json"

# ---------------------------------------------------------------------------
# Infer which sub-steps completed from existing files
# ---------------------------------------------------------------------------
key_comparisons_file <- file.path(RESULTS_DIR, "sgpc_key_comparisons.csv")
sensitivity_summary_file <- file.path(
  RESULTS_DIR,
  "sgpc_sensitivity_summary.csv"
)
by_stratum_file <- file.path(RESULTS_DIR, "sgpc_by_stratum.csv")
by_year_span_file <- file.path(RESULTS_DIR, "sgpc_by_year_span.csv")
by_content_area_file <- file.path(RESULTS_DIR, "sgpc_by_content_area.csv")
canonical_stratum_file <- file.path(
  RESULTS_DIR,
  "canonical_validation_by_stratum.csv"
)
canonical_family_file <- file.path(
  RESULTS_DIR,
  "canonical_family_distribution_by_stratum.csv"
)

step_2_1_done <- length(list.files(
  RESULTS_DIR,
  pattern = "^sgpc_all_variants_dataset_.*\\.rds$"
)) >
  0
step_2_1b_done <- file.exists(canonical_stratum_file)
step_2_2_done <- file.exists(key_comparisons_file)

substeps_completed <- character(0)
if (step_2_1_done) {
  substeps_completed <- c(substeps_completed, "2.1")
}
if (step_2_1b_done) {
  substeps_completed <- c(substeps_completed, "2.1b")
}
if (step_2_2_done) {
  substeps_completed <- c(substeps_completed, "2.2")
}
if (
  file.exists(file.path(
    RESULTS_DIR,
    "visualizations",
    "scatter_emp_vs_best.pdf"
  ))
) {
  substeps_completed <- c(substeps_completed, "2.3")
}
if (file.exists(file.path(RESULTS_DIR, "SGPC_SENSITIVITY_REPORT.md"))) {
  substeps_completed <- c(substeps_completed, "2.4")
}
if (
  file.exists(file.path(RESULTS_DIR, "visualizations", "sgpc_summary_grid.pdf"))
) {
  substeps_completed <- c(substeps_completed, "2.5")
}

rds_files <- list.files(
  RESULTS_DIR,
  pattern = "^sgpc_all_variants_dataset_.*\\.rds$"
)
datasets_processed <- gsub("^sgpc_all_variants_|\\.rds$", "", rds_files)

# ---------------------------------------------------------------------------
# STEP_1 manifest (provenance)
# ---------------------------------------------------------------------------
step1_manifest_version <- NA_character_
step1_generated_at <- NA_character_
if (file.exists(STEP1_MANIFEST)) {
  tryCatch(
    {
      step1 <- fromJSON(STEP1_MANIFEST)
      step1_manifest_version <- step1$metadata$manifest_version %||%
        NA_character_
      step1_generated_at <- step1$metadata$generated_at %||% NA_character_
    },
    error = function(e) NULL
  )
}

# ---------------------------------------------------------------------------
# Sensitivity summary (from 2.2)
# ---------------------------------------------------------------------------
sensitivity_summary <- list(
  key_comparisons = list(),
  key_findings = character(0),
  note = "Run steps 2.1 and 2.2 to populate."
)

if (file.exists(key_comparisons_file)) {
  key_stats <- fread(key_comparisons_file)
  # Convert to list of records for JSON
  key_comparisons_list <- lapply(seq_len(nrow(key_stats)), function(i) {
    as.list(key_stats[i, ])
  })
  sensitivity_summary$key_comparisons <- key_comparisons_list
  sensitivity_summary$note <- NULL

  emp_best <- key_stats[comparison == "Empirical vs Best-fit", ]
  emp_canon <- key_stats[comparison == "Empirical vs Canonical", ]
  emp_gauss <- key_stats[comparison == "Empirical vs Gaussian", ]
  emp_como <- key_stats[comparison == "Empirical vs Comonotonic", ]

  sensitivity_summary$key_findings <- character(0)
  if (nrow(emp_best) > 0) {
    sensitivity_summary$key_findings <- c(
      sensitivity_summary$key_findings,
      sprintf(
        "Empirical vs best-fit parametric: r=%.3f, MAD=%.1f percentile points",
        emp_best$correlation[1],
        emp_best$mad[1]
      )
    )
  }
  if (nrow(emp_canon) > 0) {
    sensitivity_summary$key_findings <- c(
      sensitivity_summary$key_findings,
      sprintf(
        "Empirical vs canonical averaged: r=%.3f, MAD=%.1f percentile points",
        emp_canon$correlation[1],
        emp_canon$mad[1]
      )
    )
  }
  if (nrow(emp_gauss) > 0) {
    sensitivity_summary$key_findings <- c(
      sensitivity_summary$key_findings,
      sprintf(
        "Impact of mis-specification (Gaussian): MAD=%.1f percentile points",
        emp_gauss$mad[1]
      )
    )
  }
  if (nrow(emp_como) > 0) {
    sensitivity_summary$key_findings <- c(
      sensitivity_summary$key_findings,
      sprintf(
        "TAMP comonotonic assumption: MAD=%.1f percentile points",
        emp_como$mad[1]
      )
    )
  }
}

# ---------------------------------------------------------------------------
# Canonical validation (from 2.1b)
# ---------------------------------------------------------------------------
canonical_validation <- list(
  per_stratum = list(),
  global_verdict = NA_character_,
  strata_t_not_majority = character(0),
  note = "Run step 2.1b to populate."
)

if (file.exists(canonical_stratum_file)) {
  canon_dt <- fread(canonical_stratum_file)
  canonical_validation$per_stratum <- lapply(
    seq_len(nrow(canon_dt)),
    function(i) {
      as.list(canon_dt[i, ])
    }
  )
  canonical_validation$note <- NULL

  # Global verdict: same criteria as canonical_validation.R
  # (ratio < 1.5 and mean correlation > 0.99)
  global_mad_canon <- mean(canon_dt$mad_canonical_mean, na.rm = TRUE)
  global_mad_best <- mean(canon_dt$mad_best_mean, na.rm = TRUE)
  global_cor <- mean(canon_dt$cor_canonical_mean, na.rm = TRUE)
  ratio <- if (global_mad_best > 0) {
    global_mad_canon / global_mad_best
  } else {
    NA_real_
  }
  is_validated <- !is.na(ratio) &&
    ratio < 1.5 &&
    !is.na(global_cor) &&
    global_cor > 0.99
  canonical_validation$global_verdict <- if (is_validated) {
    "VALIDATED"
  } else {
    "REVIEW NEEDED"
  }
  canonical_validation$global_mad_canonical <- round(global_mad_canon, 2)
  canonical_validation$global_mad_best <- round(global_mad_best, 2)
  canonical_validation$global_correlation <- round(global_cor, 4)
  canonical_validation$canonical_ratio <- round(ratio, 3)
}

if (file.exists(canonical_family_file)) {
  family_dt <- fread(canonical_family_file)
  t_minority <- family_dt[!(t_majority %in% TRUE), ]
  if (nrow(t_minority) > 0) {
    canonical_validation$strata_t_not_majority <- t_minority$stratum_id
  }
}

# ---------------------------------------------------------------------------
# Variant rankings (from 2.2 by_stratum)
# ---------------------------------------------------------------------------
variant_rankings <- list(
  by_stratum = list(),
  by_year_span = list(),
  by_content_area = list(),
  note = "Run step 2.2 to populate."
)

if (file.exists(by_stratum_file)) {
  by_stratum_dt <- fread(by_stratum_file)
  variant_rankings$by_stratum <- lapply(
    seq_len(nrow(by_stratum_dt)),
    function(i) {
      as.list(by_stratum_dt[i, ])
    }
  )
  variant_rankings$note <- NULL
}
if (file.exists(by_year_span_file)) {
  by_ys <- fread(by_year_span_file)
  variant_rankings$by_year_span <- lapply(seq_len(nrow(by_ys)), function(i) {
    as.list(by_ys[i, ])
  })
}
if (file.exists(by_content_area_file)) {
  by_ca <- fread(by_content_area_file)
  variant_rankings$by_content_area <- lapply(seq_len(nrow(by_ca)), function(i) {
    as.list(by_ca[i, ])
  })
}

# ---------------------------------------------------------------------------
# Metadata: n_observations, n_conditions, year_spans, content_areas
# ---------------------------------------------------------------------------
n_observations <- NA_integer_
n_conditions <- NA_integer_
year_spans <- list()
content_areas <- list()

if (length(rds_files) > 0) {
  tryCatch(
    {
      first_rds <- readRDS(file.path(RESULTS_DIR, rds_files[1]))
      n_observations <- nrow(first_rds)
      n_conditions <- uniqueN(first_rds$condition_id)
      year_spans <- as.list(sort(unique(first_rds$year_span)))
      content_areas <- as.list(sort(unique(first_rds$content_area)))
      for (f in rds_files[-1]) {
        d <- readRDS(file.path(RESULTS_DIR, f))
        n_observations <- n_observations + nrow(d)
        n_conditions <- n_conditions + uniqueN(d$condition_id)
      }
    },
    error = function(e) NULL
  )
}
if (is.na(n_observations) && file.exists(key_comparisons_file)) {
  tryCatch(
    {
      k <- fread(key_comparisons_file)
      if (nrow(k) > 0 && "n_obs" %in% names(k)) n_observations <- k$n_obs[1]
    },
    error = function(e) NULL
  )
}

metadata <- list(
  manifest_version = "1.0",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  step1_manifest_version = step1_manifest_version,
  step1_generated_at = step1_generated_at,
  n_observations = n_observations,
  n_conditions = n_conditions,
  n_datasets = length(datasets_processed),
  datasets_processed = as.list(datasets_processed),
  year_spans = year_spans,
  content_areas = content_areas,
  substeps_completed = as.list(substeps_completed)
)

# ---------------------------------------------------------------------------
# Recommendations for downstream
# ---------------------------------------------------------------------------
recommendations_for_downstream <- list(
  step3_liwld = "For STEP_3 (LIwLD), use canonical parameters from STEP_1; acceptable MAD range from this manifest's sensitivity_summary and canonical_validation.",
  step4_timss = "For STEP_4 (TIMSS), use canonical copula from STEP_1 (canonical_copula_parameters.csv) and see canonical_validation.global_verdict and canonical_validation.per_stratum for deployment guidance."
)

# ---------------------------------------------------------------------------
# Files produced (fixed list with descriptions)
# ---------------------------------------------------------------------------
files_produced <- list(
  list(
    file = "sgpc_all_variants_dataset_*.rds",
    description = "Per-dataset SGPc variant results (Step 2.1)"
  ),
  list(
    file = "canonical_family_distribution_by_stratum.csv",
    description = "Per-stratum AIC-best family distribution (Step 2.1b)"
  ),
  list(
    file = "canonical_validation_by_stratum.csv",
    description = "Per-stratum canonical MAD/correlation (Step 2.1b)"
  ),
  list(
    file = "canonical_validation_by_condition.csv",
    description = "Per-condition canonical validation detail (Step 2.1b)"
  ),
  list(
    file = "canonical_validation_report.md",
    description = "Canonical validation narrative report (Step 2.1b)"
  ),
  list(
    file = "sgpc_key_comparisons.csv",
    description = "Key variant comparisons (Step 2.2)"
  ),
  list(
    file = "sgpc_sensitivity_summary.csv",
    description = "Summary statistics (Step 2.2)"
  ),
  list(
    file = "sgpc_by_stratum.csv",
    description = "Per-stratum MAD/correlation (Step 2.2)"
  ),
  list(file = "sgpc_by_year_span.csv", description = "By year-span (Step 2.2)"),
  list(
    file = "sgpc_by_content_area.csv",
    description = "By content area (Step 2.2)"
  ),
  list(
    file = "sgpc_correlation_matrix.csv",
    description = "Variant correlation matrix (Step 2.2)"
  ),
  list(
    file = "sgpc_pairwise_differences.csv",
    description = "Pairwise MAD/RMSD (Step 2.2)"
  ),
  list(
    file = "sgpc_sensitivity_manifest.json",
    description = "This consolidated manifest (Step 2.6)"
  ),
  list(
    file = "SGPC_SENSITIVITY_REPORT.md",
    description = "Narrative report (Step 2.4)"
  ),
  list(
    file = "visualizations/*.{pdf,svg,png}",
    description = "Plots (Steps 2.3, 2.5)"
  )
)

# Optionally mark which exist
existing <- list.files(RESULTS_DIR, recursive = TRUE)
vis_dir <- file.path(RESULTS_DIR, "visualizations")
has_vis <- dir.exists(vis_dir) &&
  length(list.files(vis_dir, pattern = "[.](pdf|svg|png)$")) > 0
for (i in seq_along(files_produced)) {
  fp <- files_produced[[i]]
  f <- fp$file
  if (identical(f, "visualizations/*.{pdf,svg,png}")) {
    files_produced[[i]]$exists <- has_vis
  } else if (grepl("[*]", f, fixed = TRUE)) {
    pat <- gsub("*", ".*", f, fixed = TRUE)
    pat <- gsub(".", "[.]", pat, fixed = TRUE)
    files_produced[[i]]$exists <- any(grepl(pat, existing))
  } else {
    files_produced[[i]]$exists <- file.exists(file.path(RESULTS_DIR, f))
  }
}

# ---------------------------------------------------------------------------
# Build and write manifest
# ---------------------------------------------------------------------------
manifest <- list(
  metadata = metadata,
  sensitivity_summary = sensitivity_summary,
  canonical_validation = canonical_validation,
  variant_rankings = variant_rankings,
  recommendations_for_downstream = recommendations_for_downstream,
  files_produced = files_produced
)

out_path <- file.path(RESULTS_DIR, "sgpc_sensitivity_manifest.json")
if (!dir.exists(RESULTS_DIR)) {
  dir.create(RESULTS_DIR, recursive = TRUE, showWarnings = FALSE)
}

write_json(manifest, out_path, pretty = TRUE, auto_unbox = TRUE)
cat("STEP 2.6: Consolidated manifest written to", out_path, "\n")
