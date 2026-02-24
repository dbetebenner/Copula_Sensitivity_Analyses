############################################################################
###
### Manifest Export for STEP 3: Growth Regime Inference
###
### Generates AI-consumable JSON and human-readable Markdown manifests,
### following the pattern established by STEP 1 and STEP 2.
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################

require(jsonlite)


#' Export STEP 3 Manifest (JSON + Markdown)
#'
#' Writes summary results from STEP 3 growth regime inference to both
#' machine-readable JSON and human-readable Markdown formats.
#'
#' @param results List. Combined results from STEP 3 estimation. Expected
#'   structure:
#'   \itemize{
#'     \item subgroup_estimates: List of per-subgroup estimate_regime() results
#'     \item bootstrap_results: Optional bootstrap results
#'     \item copula_uncertainty_results: Optional copula uncertainty results
#'     \item config: Configuration used for the run
#'     \item metadata: List with timestamp, git_hash, seed, etc.
#'   }
#' @param output_dir Character. Directory for manifest files. Default "results".
#' @param prefix Character. Filename prefix. Default "step3".
#' @param verbose Logical. Default TRUE.
#'
#' @return Invisible list with paths to JSON and MD files.
#'
#' @export
export_step3_manifest <- function(results,
                                   output_dir = "results",
                                   prefix = "step3",
                                   verbose = TRUE) {

  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  # Build manifest structure
  manifest <- list(
    metadata = list(
      generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
      step         = "STEP_3_LIwLD",
      description  = "Growth regime inference from cross-sectional data",
      n_subgroups  = length(results$subgroup_estimates),
      config       = results$config
    )
  )

  # Subgroup summaries
  subgroup_summaries <- lapply(names(results$subgroup_estimates), function(sg_id) {
    est <- results$subgroup_estimates[[sg_id]]
    if (is.null(est)) return(NULL)

    list(
      subgroup_id    = sg_id,
      regime_family  = est$regime$family,
      theta_hat      = est$theta_hat,
      median_sgpc    = round(est$regime$median * 100, 2),
      mean_sgpc      = round(est$regime$mean * 100, 2),
      dispersion_sd  = if (!is.null(est$regime$sd))  round(est$regime$sd * 100, 2) else NA,
      dispersion_iqr = if (!is.null(est$regime$iqr)) round(est$regime$iqr * 100, 2) else NA,
      entropy        = if (!is.null(est$regime$entropy)) round(est$regime$entropy, 4) else NA,
      concentration  = if (!is.null(est$regime$concentration)) round(est$regime$concentration, 2) else NA,
      distance_min   = round(est$distance_min, 6),
      distances      = lapply(est$all_distances, function(x) round(x, 6)),
      convergence    = est$convergence
    )
  })
  subgroup_summaries <- Filter(Negate(is.null), subgroup_summaries)
  manifest$subgroup_estimates <- subgroup_summaries

  # Bootstrap summary (if available)
  if (!is.null(results$bootstrap_results)) {
    boot <- results$bootstrap_results
    manifest$uncertainty <- list(
      sampling = list(
        n_boot          = boot$n_boot,
        n_converged     = boot$n_converged,
        ci_median_sgpc  = as.numeric(boot$ci_median_sgpc),
        se_median_sgpc  = round(boot$se_median_sgpc, 2)
      )
    )
  }

  # Copula uncertainty (if available)
  if (!is.null(results$copula_uncertainty_results)) {
    cop_unc <- results$copula_uncertainty_results
    manifest$uncertainty$copula <- list(
      var_copula      = round(cop_unc$var_copula, 4),
      n_draws         = length(cop_unc$median_sgpc_draws),
      median_sgpc_range = round(range(cop_unc$median_sgpc_draws, na.rm = TRUE), 2)
    )
  }

  # Run metadata
  if (!is.null(results$metadata)) {
    manifest$run_metadata <- results$metadata
  }

  # --- Write JSON ---
  json_path <- file.path(output_dir, paste0(prefix, "_manifest.json"))
  write_json(manifest, json_path, pretty = TRUE, auto_unbox = TRUE)

  # --- Write Markdown ---
  md_path <- file.path(output_dir, paste0(prefix, "_manifest.md"))
  md_lines <- c(
    "# STEP 3: Growth Regime Inference Results",
    "",
    paste0("**Generated:** ", manifest$metadata$generated_at),
    paste0("**Subgroups analysed:** ", manifest$metadata$n_subgroups),
    "",
    "---",
    "",
    "## Subgroup Estimates",
    ""
  )

  for (sg in subgroup_summaries) {
    md_lines <- c(md_lines,
      paste0("### ", sg$subgroup_id),
      paste0("- **Regime family:** ", sg$regime_family),
      paste0("- **Parameters:** ", paste(round(sg$theta_hat, 4), collapse = ", ")),
      paste0("- **Median SGPc:** ", sg$median_sgpc),
      paste0("- **Mean SGPc:** ", sg$mean_sgpc),
      paste0("- **Wasserstein-1:** ", sg$distances$wasserstein1),
      paste0("- **CvM:** ", sg$distances$cramer_von_mises),
      ""
    )
  }

  if (!is.null(results$bootstrap_results)) {
    boot <- results$bootstrap_results
    md_lines <- c(md_lines,
      "---",
      "",
      "## Uncertainty Quantification",
      "",
      "### Sampling Uncertainty (Bootstrap)",
      paste0("- **Replicates:** ", boot$n_boot,
             " (converged: ", boot$n_converged, ")"),
      paste0("- **Median SGPc 95% CI:** [",
             round(boot$ci_median_sgpc[1], 1), ", ",
             round(boot$ci_median_sgpc[2], 1), "]"),
      paste0("- **SE:** ", round(boot$se_median_sgpc, 2)),
      ""
    )
  }

  md_lines <- c(md_lines,
    "---",
    "",
    "## Output Files",
    "",
    "| File | Description |",
    "|------|-------------|",
    "| `step3_country_estimates.csv` | Subgroup estimates with dispersion and entropy |",
    "| `step3_uncertainty_decomposition.csv` | Variance decomposition (sampling, copula, family) |",
    "| `step3_bucket_probabilities.csv` | K=3 and K=5 bucket membership probabilities |",
    "| `bucket_stability_summary.json` | Classification consistency summary |",
    "| `step3_manifest.json` | This manifest (machine-readable) |",
    "| `step3_manifest.md` | This manifest (human-readable) |",
    "| `run_metadata.json` | Reproducibility metadata |",
    "",
    "---",
    "",
    "## How to Use These Results",
    "",
    "```r",
    '# Load manifest',
    'library(jsonlite)',
    paste0('manifest <- fromJSON("', json_path, '")'),
    '',
    '# Access subgroup estimates',
    'manifest$subgroup_estimates[[1]]$median_sgpc',
    "```",
    ""
  )

  writeLines(md_lines, md_path)

  if (verbose) {
    cat("Manifest exported:\n")
    cat("  JSON:", json_path, "\n")
    cat("  MD:  ", md_path, "\n")
  }

  invisible(list(json = json_path, md = md_path))
}


#' Export Run Metadata
#'
#' Writes a run_metadata.json file capturing the computational environment
#' and configuration for reproducibility.
#'
#' @param config List. STEP 3 configuration.
#' @param output_dir Character. Default "results".
#' @param seed Integer. RNG seed used. Default NULL.
#'
#' @return Invisible path to metadata file.
#'
#' @export
export_run_metadata <- function(config, output_dir = "results", seed = NULL) {

  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  metadata <- list(
    timestamp    = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    r_version    = paste(R.version$major, R.version$minor, sep = "."),
    platform     = R.version$platform,
    packages     = list(
      copula     = as.character(packageVersion("copula")),
      data.table = as.character(packageVersion("data.table")),
      jsonlite   = as.character(packageVersion("jsonlite"))
    ),
    rng_seed     = seed,
    config       = config
  )

  # Attempt git hash
  git_hash <- tryCatch({
    system("git rev-parse --short HEAD", intern = TRUE, ignore.stderr = TRUE)
  }, error = function(e) "unknown")
  metadata$git_hash <- git_hash

  path <- file.path(output_dir, "run_metadata.json")
  write_json(metadata, path, pretty = TRUE, auto_unbox = TRUE)

  invisible(path)
}


cat("STEP 3 manifest_export.R loaded.\n")
cat("  Functions: export_step3_manifest, export_run_metadata\n")
