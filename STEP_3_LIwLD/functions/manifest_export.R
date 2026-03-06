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
      regime_param_hat = est$regime_param_hat,
      m_hat          = est$m_hat,
      kappa_hat      = est$kappa_hat,
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

  if (!is.null(results$assumption_diagnostics)) {
    manifest$assumption_diagnostics <- results$assumption_diagnostics
  }

  if (!is.null(results$sensitivity)) {
    manifest$sensitivity <- results$sensitivity
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
      paste0("- **Parameters:** ", paste(round(sg$regime_param_hat, 4), collapse = ", ")),
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
    "| `district_summary_grade.csv` | District-level model-health summary artifact |",
    "| `step3_country_estimates.csv` | Subgroup estimates with dispersion and entropy |",
    "| `step3_uncertainty_decomposition.csv` | Variance decomposition (sampling, copula, family) |",
    "| `step3_bucket_probabilities.csv` | K=3 and K=5 bucket membership probabilities |",
    "| `phase_b_copula_sensitivity.csv` | Phase B2 sensitivity to copula parameter variants |",
    "| `phase_b_independence_sensitivity.csv` | Phase B3 sensitivity to stratified-by-U regimes |",
    "| `phase_b_pool_registry.csv` | Phase B pooled-source registry with eligibility metadata |",
    "| `phase_b_replicates.RData` | Phase B replicate-level operating-characteristics artifact |",
    "| `phase_b_precision_by_n.csv` | Phase B precision operating characteristics by N bucket |",
    "| `phase_a_analytic_payload.rds` | Notation-aligned figure payload for Step 3 Phase A |",
    "| `phase_a_precision_anchor.csv` | Phase A baseline N0/SE0/CI-width anchor for scaling narrative |",
    "| `exports/phase_a/*.csv` | Tidy figure-data exports (CDF, objective, density, fit, bootstrap, independence) |",
    "| `output_contract_check.json` | Output contract validation report |",
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

#' Export Phase A Deep-Dive Manifest (JSON + Markdown)
#'
#' Writes a comprehensive, Phase A-specific manifest capturing the condition,
#' subgroup, true vs inferred SGPc summaries, family comparison, uncertainty,
#' and key output artifacts.
#'
#' @param phase_a_results List. Object saved by step3_validation_deep_dive.R.
#' @param output_dir Character. Directory for manifest files. Default "results".
#' @param prefix Character. Filename prefix. Default "phase_a".
#' @param verbose Logical. Default TRUE.
#'
#' @return Invisible list with paths to JSON and MD files.
#'
#' @export
export_phase_a_manifest <- function(phase_a_results,
                                    output_dir = "results",
                                    prefix = "phase_a",
                                    verbose = TRUE) {

  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  best_est <- phase_a_results$best_estimate
  true_sgpc <- phase_a_results$true_sgpc
  boot <- phase_a_results$bootstrap
  fam_comp <- phase_a_results$family_comparison$comparison

  true_mean <- mean(true_sgpc, na.rm = TRUE)
  true_median <- median(true_sgpc, na.rm = TRUE)
  inferred_mean <- best_est$regime$mean * 100
  inferred_median <- best_est$regime$median * 100

  manifest <- list(
    metadata = list(
      generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
      step = "STEP_3_LIwLD_PHASE_A",
      description = "Single-condition deep-dive validation manifest"
    ),
    condition = list(
      dataset_id = phase_a_results$dataset_id,
      condition_id = phase_a_results$condition_id,
      condition_meta = phase_a_results$condition_meta,
      subgroup_id = phase_a_results$subgroup_id,
      subgroup_col = phase_a_results$subgroup_col,
      n_subgroup = phase_a_results$n_subgroup,
      references = phase_a_results$references,
      copula_used = phase_a_results$copula_used
    ),
    estimation = list(
      best_family = phase_a_results$best_family,
      best_params = as.numeric(best_est$regime_param_hat),
      m_hat = best_est$m_hat,
      kappa_hat = best_est$kappa_hat,
      distance_metric = best_est$distance_metric,
      distance_min = best_est$distance_min,
      distances = best_est$all_distances
    ),
    sgpc_summary = list(
      inferred = list(
        mean = round(inferred_mean, 2),
        median = round(inferred_median, 2)
      ),
      true = list(
        mean = round(true_mean, 2),
        median = round(true_median, 2)
      ),
      differences = list(
        mean_diff = round(inferred_mean - true_mean, 2),
        median_diff = round(inferred_median - true_median, 2)
      )
    ),
    assumption_diagnostics = list(
      flag_independence_violation = isTRUE(phase_a_results$flag_independence_violation),
      spearman_rho = if (!is.null(phase_a_results$independence_diagnostics)) {
        as.numeric(phase_a_results$independence_diagnostics[phase_a_results$independence_diagnostics$metric == "spearman_rho", "value"][1])
      } else {
        NA_real_
      },
      kruskal_p_value = if (!is.null(phase_a_results$independence_diagnostics)) {
        as.numeric(phase_a_results$independence_diagnostics[phase_a_results$independence_diagnostics$metric == "kruskal_p_value", "value"][1])
      } else {
        NA_real_
      }
    ),
    uncertainty = list(
      sampling = list(
        n_boot = boot$n_boot,
        n_converged = boot$n_converged,
        ci_median_sgpc = as.numeric(boot$ci_median_sgpc),
        ci_mean_sgpc = as.numeric(boot$ci_mean_sgpc),
        se_median_sgpc = as.numeric(boot$se_median_sgpc)
      )
    ),
    family_comparison = fam_comp,
    output_files = list(
      phase_a_rds = file.path(output_dir, "phase_a_deep_dive.rds"),
      phase_a_analytic_payload = file.path(output_dir, "phase_a_analytic_payload.rds"),
      phase_a_summary_csv = file.path(output_dir, "phase_a_summary.csv"),
      phase_a_precision_anchor_csv = file.path(output_dir, "phase_a_precision_anchor.csv"),
      independence_diagnostics_csv = file.path(output_dir, "exports", "phase_a", "step3_independence_diagnostics.csv"),
      phasea_01_marginals = file.path(output_dir, "visualizations", "phase_a", "phasea_01_marginals_uv_density.pdf"),
      phasea_02a_objective = file.path(output_dir, "visualizations", "phase_a", "phasea_02a_objective_surface.pdf"),
      phasea_02b_cdf = file.path(output_dir, "visualizations", "phase_a", "phasea_02b_forward_cdf_check.pdf"),
      phasea_02c_residual = file.path(output_dir, "visualizations", "phase_a", "phasea_02c_residual_diagnostics.pdf"),
      phasea_03a_regime = file.path(output_dir, "visualizations", "phase_a", "phasea_03a_regime_density.pdf"),
      phasea_03e_recovery = file.path(output_dir, "visualizations", "phase_a", "phasea_03e_recovery_summary.pdf"),
      phasea_04_independence = file.path(output_dir, "visualizations", "phase_a", "phasea_04_independence_diagnostic.pdf")
    ),
    config = phase_a_results$config
  )

  json_path <- file.path(output_dir, paste0(prefix, "_manifest.json"))
  write_json(manifest, json_path, pretty = TRUE, auto_unbox = TRUE)

  md_path <- file.path(output_dir, paste0(prefix, "_manifest.md"))
  md_lines <- c(
    "# STEP 3 Phase A Deep-Dive Manifest",
    "",
    paste0("**Generated:** ", manifest$metadata$generated_at),
    "",
    "## Condition and Subgroup",
    "",
    paste0("- **Dataset:** ", manifest$condition$dataset_id),
    paste0("- **Condition:** ", manifest$condition$condition_id),
    paste0("- **Subgroup:** ", manifest$condition$subgroup_col, " = ", manifest$condition$subgroup_id),
    paste0("- **Subgroup n:** ", manifest$condition$n_subgroup),
    paste0("- **Baseline copula:** ", manifest$condition$copula_used$family),
    "",
    "## Canonical Choices",
    "",
    "- Canonical baseline copula (STEP 1 template)",
    "- Canonical stochastically fitted growth regime (STEP 3 selection policy)",
    "",
    "## Estimation Summary",
    "",
    paste0("- **Best family:** ", manifest$estimation$best_family),
    paste0("- **Parameters:** ", paste(round(manifest$estimation$best_params, 4), collapse = ", ")),
    paste0("- **Distance metric:** ", manifest$estimation$distance_metric),
    paste0("- **Distance minimum:** ", round(manifest$estimation$distance_min, 6)),
    "",
    "## SGPc Summary",
    "",
    paste0("- **Inferred mean SGPc:** ", manifest$sgpc_summary$inferred$mean),
    paste0("- **True mean SGPc:** ", manifest$sgpc_summary$true$mean),
    paste0("- **Mean difference:** ", manifest$sgpc_summary$differences$mean_diff),
    paste0("- **Inferred median SGPc:** ", manifest$sgpc_summary$inferred$median),
    paste0("- **True median SGPc:** ", manifest$sgpc_summary$true$median),
    paste0("- **Median difference:** ", manifest$sgpc_summary$differences$median_diff),
    "",
    "## Assumption Diagnostics (P ⟂ U)",
    "",
    paste0("- **Flag independence violation:** ", manifest$assumption_diagnostics$flag_independence_violation),
    paste0("- **Spearman rho(U,SGPc_true):** ", round(manifest$assumption_diagnostics$spearman_rho, 4)),
    paste0("- **Kruskal-Wallis p-value:** ", signif(manifest$assumption_diagnostics$kruskal_p_value, 4)),
    "",
    "## Uncertainty (Bootstrap)",
    "",
    paste0("- **Replicates:** ", manifest$uncertainty$sampling$n_boot,
           " (converged: ", manifest$uncertainty$sampling$n_converged, ")"),
    paste0("- **Mean SGPc 95% CI:** [",
           round(manifest$uncertainty$sampling$ci_mean_sgpc[1], 1), ", ",
           round(manifest$uncertainty$sampling$ci_mean_sgpc[2], 1), "]"),
    paste0("- **Median SGPc 95% CI:** [",
           round(manifest$uncertainty$sampling$ci_median_sgpc[1], 1), ", ",
           round(manifest$uncertainty$sampling$ci_median_sgpc[2], 1), "]"),
    paste0("- **Median SGPc SE:** ", round(manifest$uncertainty$sampling$se_median_sgpc, 2)),
    "",
    "## Family Comparison",
    "",
    "| Family | Distance | Mean SGPc | Median SGPc | Params |",
    "|--------|----------|-----------|-------------|--------|"
  )

  for (i in seq_len(nrow(fam_comp))) {
    md_lines <- c(md_lines, paste0(
      "| ", fam_comp$family[i],
      " | ", round(fam_comp$distance[i], 6),
      " | ", round(fam_comp$mean_sgpc[i], 2),
      " | ", round(fam_comp$median_sgpc[i], 2),
      " | ", fam_comp$params[i], " |"
    ))
  }

  md_lines <- c(md_lines,
    "",
    "## Output Files",
    "",
    "| File | Description |",
    "|------|-------------|",
    "| `phase_a_deep_dive.rds` | Full Phase A results object |",
    "| `phase_a_analytic_payload.rds` | Notation-aligned payload for figure assembly |",
    "| `exports/phase_a/step3_independence_diagnostics.csv` | Independence diagnostics and U-bin summaries |",
    "| `phase_a_summary.csv` | One-row summary for reporting |",
    "| `phase_a_manifest.json` | Machine-readable Phase A manifest |",
    "| `phase_a_manifest.md` | Human-readable Phase A manifest |",
    "| `visualizations/phase_a/panel_*.{pdf,svg,png}` | Phase A diagnostic panels |",
    ""
  )

  writeLines(md_lines, md_path)

  if (verbose) {
    cat("Phase A manifest exported:\n")
    cat("  JSON:", json_path, "\n")
    cat("  MD:  ", md_path, "\n")
  }

  invisible(list(json = json_path, md = md_path))
}


cat("STEP 3 manifest_export.R loaded.\n")
cat("  Functions: export_step3_manifest, export_phase_a_manifest, export_run_metadata\n")
