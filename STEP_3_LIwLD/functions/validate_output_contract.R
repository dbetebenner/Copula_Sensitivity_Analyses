############################################################################
###
### Validate STEP 3 Output Contract
###
############################################################################

require(jsonlite)

validate_step3_output_contract <- function(results_dir = "results",
                                           strict = FALSE,
                                           verbose = TRUE) {
  required_files <- c(
    "phase_a_summary.csv",
    "phase_a_manifest.json",
    "phase_a_manifest.md",
    "step3_country_estimates.csv",
    "step3_uncertainty_decomposition.csv",
    "step3_bucket_probabilities.csv",
    "district_summary_grade.csv",
    "bucket_stability_summary.json",
    "step3_manifest.json",
    "step3_manifest.md",
    "run_metadata.json"
  )

  optional_files <- c(
    "phase_a_deep_dive.rds",
    "phase_a_analytic_payload.rds",
    "visualizations/panel_g_district_summary_grade.pdf",
    "visualizations/panel_g_district_summary_grade.svg",
    "visualizations/panel_g_district_summary_grade.png"
  )

  missing_required <- required_files[!file.exists(file.path(results_dir, required_files))]
  missing_optional <- optional_files[!file.exists(file.path(results_dir, optional_files))]

  checks <- list(
    missing_required = missing_required,
    missing_optional = missing_optional,
    manifest_n_subgroups = NA_integer_,
    bucket_probabilities_sum_ok = NA,
    passed = FALSE
  )

  manifest_path <- file.path(results_dir, "step3_manifest.json")
  if (file.exists(manifest_path)) {
    man <- fromJSON(manifest_path, simplifyVector = TRUE)
    checks$manifest_n_subgroups <- man$metadata$n_subgroups
  }

  bucket_path <- file.path(results_dir, "step3_bucket_probabilities.csv")
  if (file.exists(bucket_path)) {
    b <- data.table::fread(bucket_path)
    if (nrow(b) > 0) {
      k3 <- rowSums(b[, c("k3_Low", "k3_Typical", "k3_High"), with = FALSE], na.rm = TRUE)
      k5 <- rowSums(b[, c("k5_Very_Low", "k5_Low", "k5_Typical", "k5_High", "k5_Very_High"), with = FALSE], na.rm = TRUE)
      checks$bucket_probabilities_sum_ok <- all(abs(k3 - 1) < 0.01 & abs(k5 - 1) < 0.01)
    }
  }

  checks$passed <- length(missing_required) == 0 &&
    !is.na(checks$manifest_n_subgroups) &&
    checks$manifest_n_subgroups >= 1 &&
    isTRUE(checks$bucket_probabilities_sum_ok)

  if (verbose) {
    cat("STEP 3 output contract check:\n")
    cat("  Required missing:", length(checks$missing_required), "\n")
    cat("  Optional missing:", length(checks$missing_optional), "\n")
    cat("  Manifest n_subgroups:", checks$manifest_n_subgroups, "\n")
    cat("  Bucket sums OK:", checks$bucket_probabilities_sum_ok, "\n")
    cat("  Passed:", checks$passed, "\n")
  }

  out_path <- file.path(results_dir, "output_contract_check.json")
  jsonlite::write_json(checks, out_path, pretty = TRUE, auto_unbox = TRUE)

  if (strict && !checks$passed) {
    stop("STEP 3 output contract validation failed. See ", out_path)
  }

  invisible(checks)
}

cat("STEP 3 validate_output_contract.R loaded.\n")
cat("  Function: validate_step3_output_contract\n")
