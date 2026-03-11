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
    independence_diagnostic = "phasea_04_independence_diagnostic"
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
