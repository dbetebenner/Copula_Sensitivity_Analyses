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
    "phase_a_precision_anchor.csv",
    "phase_a_manifest.json",
    "phase_a_manifest.md",
    "exports/phase_a/step3_independence_diagnostics.csv",
    "phase_b_pool_registry.csv",
    "phase_b_replicates.RData",
    "phase_b_precision_by_n.csv",
    "step3_country_estimates.csv",
    "step3_uncertainty_decomposition.csv",
    "step3_bucket_probabilities.csv",
    "phase_b_copula_sensitivity.csv",
    "phase_b_independence_sensitivity.csv",
    "district_summary_grade.csv",
    "bucket_stability_summary.json",
    "step3_manifest.json",
    "step3_manifest.md",
    "run_metadata.json",
    "uncertainty_methodology.md"
  )

  optional_files <- c(
    "phase_a_deep_dive.rds",
    "phase_a_analytic_payload.rds",
    "visualizations/panel_h_district_summary_grade.pdf",
    "visualizations/panel_h_district_summary_grade.svg",
    "visualizations/panel_h_district_summary_grade.png",
    "visualizations/panel_i_independence_diagnostic.pdf",
    "visualizations/panel_i_independence_diagnostic.svg",
    "visualizations/panel_i_independence_diagnostic.png",
    "visualizations/panel_j_sensitivity_summary.pdf",
    "visualizations/panel_j_sensitivity_summary.svg",
    "visualizations/panel_j_sensitivity_summary.png"
  )

  missing_required <- required_files[!file.exists(file.path(results_dir, required_files))]
  missing_optional <- optional_files[!file.exists(file.path(results_dir, optional_files))]

  checks <- list(
    missing_required = missing_required,
    missing_optional = missing_optional,
    manifest_n_subgroups = NA_integer_,
    bucket_probabilities_sum_ok = NA,
    phase_b_precision_schema_ok = NA,
    assumption_diagnostics_present = NA,
    weight_resample_scheme = NA_character_,
    weight_usage_check = NA,
    passed = FALSE
  )

  manifest_path <- file.path(results_dir, "step3_manifest.json")
  if (file.exists(manifest_path)) {
    man <- fromJSON(manifest_path, simplifyVector = TRUE)
    checks$manifest_n_subgroups <- man$metadata$n_subgroups
    checks$assumption_diagnostics_present <- !is.null(man$assumption_diagnostics)
    checks$weight_resample_scheme <- tryCatch(man$metadata$config$uncertainty$resample_scheme, error = function(e) NA_character_)
    if (is.null(checks$weight_resample_scheme) || length(checks$weight_resample_scheme) == 0) {
      checks$weight_resample_scheme <- NA_character_
    }
    checks$weight_usage_check <- if (!is.na(checks$weight_resample_scheme)) {
      checks$weight_resample_scheme %in% c("srs_bootstrap", "weighted_bootstrap", "replicate_weights")
    } else {
      NA
    }
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

  precision_path <- file.path(results_dir, "phase_b_precision_by_n.csv")
  if (file.exists(precision_path)) {
    p <- data.table::fread(precision_path)
    required_cols <- c(
      "pool_id", "pool_type", "span", "content", "n_bucket", "N_eff_bucket",
      "median_bias", "median_mae", "median_rmse", "median_ci_width_90", "median_ci_width_95",
      "mean_bias", "mean_mae", "mean_rmse", "mean_ci_width_90", "mean_ci_width_95"
    )
    checks$phase_b_precision_schema_ok <- all(required_cols %in% names(p)) && nrow(p) > 0
  }

  checks$passed <- length(missing_required) == 0 &&
    !is.na(checks$manifest_n_subgroups) &&
    checks$manifest_n_subgroups >= 1 &&
    isTRUE(checks$bucket_probabilities_sum_ok) &&
    isTRUE(checks$phase_b_precision_schema_ok) &&
    isTRUE(checks$assumption_diagnostics_present) &&
    isTRUE(checks$weight_usage_check)

  if (verbose) {
    cat("STEP 3 output contract check:\n")
    cat("  Required missing:", length(checks$missing_required), "\n")
    cat("  Optional missing:", length(checks$missing_optional), "\n")
    cat("  Manifest n_subgroups:", checks$manifest_n_subgroups, "\n")
    cat("  Bucket sums OK:", checks$bucket_probabilities_sum_ok, "\n")
    cat("  Phase B precision schema OK:", checks$phase_b_precision_schema_ok, "\n")
    cat("  Assumption diagnostics in manifest:", checks$assumption_diagnostics_present, "\n")
    cat("  Resample scheme:", checks$weight_resample_scheme, "\n")
    cat("  Weight-usage check:", checks$weight_usage_check, "\n")
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
