############################################################################
###
### STEP 3 Figure Naming Contract
###
### Provides a single source of truth for figure filenames so Phase A,
### plot-only regeneration, and Phase C stay consistent.
###
############################################################################

get_phasea_figure_map <- function() {
  list(
    marginal_uv_density = "phasea_01_marginals_uv_density",
    objective_surface = "phasea_02a_objective_surface",
    forward_cdf_check = "phasea_02b_forward_cdf_check",
    residual_diagnostics = "phasea_02c_residual_diagnostics",
    regime_density = "phasea_03a_regime_density",
    bootstrap_median = "phasea_03b_bootstrap_median_sgpc",
    bootstrap_mean = "phasea_03c_bootstrap_mean_sgpc",
    bootstrap_combined = "phasea_03d_bootstrap_combined",
    recovery_summary = "phasea_03e_recovery_summary",
    linkage_decomposition = "phasea_03f_linkage_decomposition",
    independence_diagnostic = "phasea_04_independence_diagnostic",
    # Copula comparison figures (generated when copula$mode = "comparison")
    copula_alt_forward_cdf = "phasea_05a_copula_bestfit_forward_cdf",
    copula_alt_regime_density = "phasea_05b_copula_bestfit_regime_density",
    copula_alt_recovery_summary = "phasea_05c_copula_bestfit_recovery_summary",
    copula_comparison_panel = "phasea_05d_copula_comparison_panel",
    # 2×2 grid cells: metric × copula (individual PDFs for LaTeX composition)
    # Row 1: W1-optimised
    grid_w1_canonical_cdf     = "phasea_06a_grid_w1_canonical_cdf",
    grid_w1_canonical_regime  = "phasea_06b_grid_w1_canonical_regime",
    grid_w1_bestfit_cdf       = "phasea_06c_grid_w1_bestfit_cdf",
    grid_w1_bestfit_regime    = "phasea_06d_grid_w1_bestfit_regime",
    # Row 2: CvM-optimised
    grid_cvm_canonical_cdf    = "phasea_06e_grid_cvm_canonical_cdf",
    grid_cvm_canonical_regime = "phasea_06f_grid_cvm_canonical_regime",
    grid_cvm_bestfit_cdf      = "phasea_06g_grid_cvm_bestfit_cdf",
    grid_cvm_bestfit_regime   = "phasea_06h_grid_cvm_bestfit_regime",
    # Composed LaTeX summary grid
    metric_copula_grid        = "phasea_06_metric_copula_grid",
    # Churn diagnostic figures
    churn_decomposition       = "phasea_07a_churn_decomposition",
    marginal_comparison       = "phasea_07b_marginal_comparison",
    regime_contrast           = "phasea_07c_regime_contrast",
    churn_summary_panel       = "phasea_07d_churn_summary_panel"
  )
}

get_phasea_legacy_alias_map <- function() {
  list(
    panel_a_cdf_comparison = "phasea_02b_forward_cdf_check",
    panel_b1_objective_surface = "phasea_02a_objective_surface",
    panel_b2_residual_curve = "phasea_02c_residual_diagnostics",
    panel_c_regime_comparison = "phasea_03a_regime_density",
    panel_d_recovery_summary = "phasea_03e_recovery_summary",
    panel_e_bootstrap_median_sgpc = "phasea_03b_bootstrap_median_sgpc",
    panel_f_bootstrap_mean_sgpc = "phasea_03c_bootstrap_mean_sgpc",
    panel_g_bootstrap_sgpc_combined = "phasea_03d_bootstrap_combined",
    panel_i_independence_diagnostic = "phasea_04_independence_diagnostic"
  )
}

# Save compatibility copies using legacy names.
write_phasea_legacy_aliases <- function(output_dir,
                                        enable_alias = TRUE,
                                        formats = c("pdf", "svg", "png")) {
  if (!isTRUE(enable_alias)) return(invisible(NULL))
  if (!dir.exists(output_dir)) return(invisible(NULL))

  alias_map <- get_phasea_legacy_alias_map()

  for (legacy_name in names(alias_map)) {
    canonical_name <- alias_map[[legacy_name]]
    for (fmt in formats) {
      src <- file.path(output_dir, paste0(canonical_name, ".", fmt))
      dst <- file.path(output_dir, paste0(legacy_name, ".", fmt))
      if (file.exists(src)) {
        ok <- file.copy(src, dst, overwrite = TRUE)
        if (isTRUE(ok)) {
          cat(sprintf("  Alias: %s -> %s\n", canonical_name, legacy_name))
        }
      }
    }
  }

  invisible(NULL)
}

cat("STEP 3 figure_naming.R loaded.\n")
cat("  Functions: get_phasea_figure_map, get_phasea_legacy_alias_map,\n")
cat("             write_phasea_legacy_aliases\n")
