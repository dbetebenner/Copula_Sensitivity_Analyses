############################################################################
###
### STEP 3 — Phase C: Publication Panels and Manifest Export
###
### Generates publication-quality figures from Phase A and Phase B results,
### following the STEP 2 panel naming convention. Also exports final
### manifest files (JSON + Markdown).
###
### Panel Map:
###   A. Observed vs predicted CDF (Phase A showcase)
###   B. Inferred regime vs actual SGPc (Phase A showcase)
###   C. Recovery accuracy by subgroup size (Phase B)
###   D. Recovery accuracy by year span (Phase B)
###   E. Regime family comparison (Phase A)
###   F. Bootstrap uncertainty distribution (Phase A)
###   G. Summary grid combining key panels
###
### Sourced by run_step3.R (Phase C) or can be run standalone.
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################

cat("--- Phase C: Publication Panels and Manifest ---\n\n")

############################################################################
### C.0  Load Results from Phases A and B
############################################################################

# Phase A results
phase_a_path <- file.path(RESULTS_DIR, "phase_a_deep_dive.rds")
if (file.exists(phase_a_path)) {
  phase_a <- readRDS(phase_a_path)
  cat("Loaded Phase A results:", phase_a$condition_id, "\n")
} else {
  cat("WARNING: Phase A results not found. Some panels will be skipped.\n")
  phase_a <- NULL
}

# Phase B results
phase_b_csv <- file.path(RESULTS_DIR, "phase_b_systematic_summary.csv")
if (file.exists(phase_b_csv)) {
  phase_b <- fread(phase_b_csv)
  cat("Loaded Phase B results:", nrow(phase_b), "subgroups\n")
} else {
  cat("WARNING: Phase B results not found. Some panels will be skipped.\n")
  phase_b <- NULL
}

viz_dir <- file.path(RESULTS_DIR, "visualizations")
if (!dir.exists(viz_dir)) dir.create(viz_dir, recursive = TRUE)

formats <- STEP3_CONFIG$output$export_formats
cat("\n")


############################################################################
### Panel A: Observed vs Predicted CDF (Phase A showcase — already exists)
############################################################################

cat("Panel A: CDF Comparison (from Phase A)... ")
# Already generated in Phase A as panel_a_cdf_comparison.*
if (file.exists(file.path(viz_dir, "phase_a", "panel_a_cdf_comparison.pdf"))) {
  cat("exists.\n")
} else if (!is.null(phase_a)) {
  plot_observed_vs_predicted_cdf(
    phase_a$best_estimate,
    title = paste0("Observed vs Predicted — ", phase_a$condition_id),
    output_dir = viz_dir,
    filename = "panel_a_cdf_comparison"
  )
  cat("generated.\n")
} else {
  cat("skipped (no Phase A data).\n")
}


############################################################################
### Panel B: Regime Shape vs Actual SGPc (Phase A showcase — already exists)
############################################################################

cat("Panel B: Regime Shape Comparison (from Phase A)... ")
if (file.exists(file.path(viz_dir, "phase_a", "panel_b_regime_comparison.pdf"))) {
  cat("exists.\n")
} else if (!is.null(phase_a)) {
  plot_regime_shape(
    phase_a$best_estimate$regime,
    phase_a$true_sgpc,
    title = paste0("Growth Regime Recovery — ", phase_a$condition_id),
    output_dir = viz_dir,
    filename = "panel_b_regime_comparison"
  )
  cat("generated.\n")
} else {
  cat("skipped.\n")
}


############################################################################
### Panel C: Recovery Accuracy by Subgroup Size (Phase B)
############################################################################

cat("Panel C: Recovery Accuracy by Subgroup Size... ")
if (!is.null(phase_b) && nrow(phase_b) > 0) {

  pb_plot <- data.frame(
    n_subgroup = phase_b$n_subgroup,
    abs_diff   = abs(phase_b$median_diff)
  )

  pC <- ggplot(pb_plot, aes(x = n_subgroup, y = abs_diff)) +
    geom_point(size = 1.5, alpha = 0.5, color = STEP3_COLORS$point_est) +
    {if (nrow(pb_plot) > 10) geom_smooth(method = "loess", span = 0.75,
      se = FALSE, linewidth = 1.2, color = STEP3_COLORS$loess_trend)} +
    geom_hline(yintercept = 2, linetype = "dashed", color = "grey60") +
    geom_hline(yintercept = 5, linetype = "dotted", color = "grey70") +
    annotate("text", x = max(pb_plot$n_subgroup) * 0.7, y = 2.3,
             label = "2 SGP points", size = 3, color = "grey50") +
    annotate("text", x = max(pb_plot$n_subgroup) * 0.7, y = 5.3,
             label = "5 SGP points", size = 3, color = "grey60") +
    scale_x_log10() +
    labs(title = "Recovery Accuracy vs Subgroup Size",
         x = "Subgroup Size (n)", y = "|Inferred - True Median SGPc|") +
    theme_publication()

  save_plot_multi(pC, "panel_c_recovery_by_size", viz_dir)
  cat("generated.\n")

} else {
  cat("skipped (no Phase B data).\n")
}


############################################################################
### Panel D: Recovery Accuracy by Year Span (Phase B)
############################################################################

cat("Panel D: Recovery Accuracy by Year Span... ")
if (!is.null(phase_b) && nrow(phase_b) > 0 &&
    "year_span" %in% names(phase_b)) {

  pb_span <- data.frame(
    year_span = factor(paste0(phase_b$year_span, "-yr")),
    abs_diff  = abs(phase_b$median_diff)
  )

  pD <- ggplot(pb_span, aes(x = year_span, y = abs_diff)) +
    geom_boxplot(fill = alpha(STEP3_COLORS$point_est, 0.25),
                 color = STEP3_COLORS$point_est, outlier.shape = NA) +
    geom_jitter(width = 0.15, size = 1, alpha = 0.4,
                color = STEP3_COLORS$loess_trend) +
    geom_hline(yintercept = 2, linetype = "dashed", color = "grey60") +
    labs(title = "Recovery Accuracy by Year Span",
         x = "Year Span", y = "|Inferred - True Median SGPc|") +
    theme_publication()

  save_plot_multi(pD, "panel_d_recovery_by_span", viz_dir, width = 7, height = PLOT_HEIGHT)
  cat("generated.\n")

} else {
  cat("skipped.\n")
}


############################################################################
### Panel E: Regime Family Comparison (Phase A)
############################################################################

cat("Panel E: Regime Family Comparison... ")
if (!is.null(phase_a) && !is.null(phase_a$family_comparison)) {

  comp <- phase_a$family_comparison$comparison
  p_grid <- seq(0.01, 0.99, length.out = 200)

  df_list <- list()
  for (fam in comp$family) {
    fam_est <- phase_a$family_comparison$results[[fam]]
    if (!is.null(fam_est)) {
      d_vals <- fam_est$regime$density(p_grid)
      df_list[[fam]] <- data.frame(sgpc = p_grid * 100, density = d_vals,
                                    source = fam, stringsAsFactors = FALSE)
    }
  }

  if (!is.null(phase_a$true_sgpc)) {
    true_d <- density(phase_a$true_sgpc / 100, from = 0.01, to = 0.99,
                       bw = "SJ", n = 200)
    df_list[["actual"]] <- data.frame(sgpc = true_d$x * 100, density = true_d$y,
                                       source = "Actual", stringsAsFactors = FALSE)
  }

  df_fam <- do.call(rbind, df_list)

  fam_colors <- c(REGIME_FAMILY_COLORS, "Actual" = STEP3_COLORS$observed)
  fam_ltys   <- c(REGIME_FAMILY_LINETYPES, "Actual" = "solid")

  dist_labels <- paste0(comp$family, ": W1=", round(comp$distance, 4))
  subtitle_e <- paste(dist_labels, collapse = " | ")

  pE <- ggplot(df_fam, aes(x = sgpc, y = density, color = source, linetype = source)) +
    geom_line(linewidth = 0.9) +
    scale_color_manual(values = fam_colors) +
    scale_linetype_manual(values = fam_ltys) +
    geom_ref_vline(xintercept = 50) +
    labs(title = "Regime Family Comparison", subtitle = subtitle_e,
         x = "SGPc", y = "Density", color = NULL, linetype = NULL) +
    coord_cartesian(xlim = c(0, 100)) +
    theme_publication()

  save_plot_multi(pE, "panel_e_family_comparison", viz_dir)
  cat("generated.\n")

} else {
  cat("skipped.\n")
}


############################################################################
### Panel F: Bootstrap Uncertainty Distribution (Phase A)
############################################################################

cat("Panel F: Bootstrap Uncertainty... ")
if (!is.null(phase_a) && !is.null(phase_a$bootstrap)) {

  boot <- phase_a$bootstrap
  valid <- !is.na(boot$median_sgpc_draws)

  if (sum(valid) > 10) {
    boot_df <- data.frame(median_sgpc = boot$median_sgpc_draws[valid])
    true_med   <- median(phase_a$true_sgpc, na.rm = TRUE)
    point_est  <- phase_a$best_estimate$regime$median * 100
    ci         <- boot$ci_median_sgpc

    pF <- ggplot(boot_df, aes(x = median_sgpc)) +
      geom_histogram(bins = 30, fill = alpha(STEP3_COLORS$bootstrap, 0.3),
                     color = STEP3_COLORS$bootstrap) +
      geom_vline(aes(xintercept = true_med, color = "True (longitudinal)"),
                 linewidth = 0.9) +
      geom_vline(aes(xintercept = point_est, color = "Point estimate"),
                 linetype = "dashed", linewidth = 0.9) +
      geom_vline(xintercept = ci, linetype = "dotted",
                 color = STEP3_COLORS$ci_line, linewidth = 0.6) +
      scale_color_manual(
        name = NULL,
        values = c("True (longitudinal)" = STEP3_COLORS$true_value,
                   "Point estimate" = STEP3_COLORS$point_est)
      ) +
      annotate("text", x = mean(ci), y = Inf, vjust = 1.5,
               label = sprintf("95%% CI [%.1f, %.1f]", ci[1], ci[2]),
               size = 3, color = "grey40") +
      labs(title = "Bootstrap Distribution of Median SGPc",
           x = "Median SGPc (bootstrap draws)", y = "Frequency") +
      theme_publication()

    save_plot_multi(pF, "panel_f_bootstrap_uncertainty", viz_dir)
    cat("generated.\n")
  } else {
    cat("skipped (insufficient bootstrap draws).\n")
  }

} else {
  cat("skipped.\n")
}


############################################################################
### Generate step3_country_estimates.csv
############################################################################

cat("\nGenerating step3_country_estimates.csv...\n")

est_rows <- list()

if (!is.null(phase_a)) {
  regime <- phase_a$best_estimate$regime
  est_rows[["phase_a"]] <- data.frame(
    subgroup_id          = paste0(phase_a$condition_id, "__", phase_a$subgroup_id),
    dataset_id           = phase_a$dataset_id,
    condition_id         = phase_a$condition_id,
    n                    = phase_a$n_subgroup,
    regime_family        = regime$family,
    theta1               = round(phase_a$best_estimate$theta_hat[1], 4),
    theta2               = if (length(phase_a$best_estimate$theta_hat) > 1)
                             round(phase_a$best_estimate$theta_hat[2], 4) else NA_real_,
    median_sgpc          = round(regime$median * 100, 2),
    mean_sgpc            = round(regime$mean * 100, 2),
    dispersion_sd        = round(regime$sd * 100, 2),
    dispersion_iqr       = round(regime$iqr * 100, 2),
    entropy              = round(regime$entropy, 4),
    concentration        = round(regime$concentration, 2),
    distance_min         = round(phase_a$best_estimate$distance_min, 6),
    wasserstein1         = round(phase_a$best_estimate$all_distances$wasserstein1, 6),
    cvm                  = round(phase_a$best_estimate$all_distances$cramer_von_mises, 6),
    stringsAsFactors     = FALSE
  )
}

if (!is.null(phase_b) && nrow(phase_b) > 0) {
  for (i in seq_len(nrow(phase_b))) {
    row <- phase_b[i, ]
    est_rows[[paste0("pb_", i)]] <- data.frame(
      subgroup_id    = paste0(row$condition_id, "__", row$subgroup_id),
      dataset_id     = row$dataset_id,
      condition_id   = row$condition_id,
      n              = row$n_subgroup,
      regime_family  = row$regime_family,
      theta1         = row$theta1,
      theta2         = if ("theta2" %in% names(row)) row$theta2 else NA_real_,
      median_sgpc    = row$median_sgpc_inferred,
      mean_sgpc      = row$mean_sgpc_inferred,
      dispersion_sd  = NA_real_,
      dispersion_iqr = NA_real_,
      entropy        = NA_real_,
      concentration  = NA_real_,
      distance_min   = row$wasserstein1,
      wasserstein1   = row$wasserstein1,
      cvm            = row$cvm,
      stringsAsFactors = FALSE
    )
  }
}

if (length(est_rows) > 0) {
  country_est <- data.table::rbindlist(est_rows, fill = TRUE)
  fwrite(country_est, file.path(RESULTS_DIR, "step3_country_estimates.csv"))
  cat("  Saved: step3_country_estimates.csv (", nrow(country_est), " rows)\n")
} else {
  cat("  Skipped (no estimates available).\n")
}


############################################################################
### Generate step3_uncertainty_decomposition.csv
############################################################################

cat("Generating step3_uncertainty_decomposition.csv...\n")

if (!is.null(phase_a) && !is.null(phase_a$bootstrap)) {
  boot <- phase_a$bootstrap
  var_sampling <- if (!is.na(boot$se_median_sgpc)) boot$se_median_sgpc^2 else NA_real_

  # Copula uncertainty (if available in the results object)
  var_copula <- NA_real_
  if (!is.null(phase_a$copula_uncertainty)) {
    var_copula <- phase_a$copula_uncertainty$var_copula
  }

  # Regime family uncertainty from family comparison
  var_family <- NA_real_
  if (!is.null(phase_a$family_comparison) &&
      nrow(phase_a$family_comparison$comparison) > 1) {
    family_medians <- phase_a$family_comparison$comparison$median_sgpc
    var_family <- var(family_medians)
  }

  total_var <- sum(c(var_sampling, var_copula, var_family), na.rm = TRUE)

  unc_row <- data.frame(
    subgroup_id  = paste0(phase_a$condition_id, "__", phase_a$subgroup_id),
    var_sampling = round(var_sampling, 4),
    var_copula   = round(var_copula, 4),
    var_family   = round(var_family, 4),
    total_var    = round(total_var, 4),
    se_sampling  = round(boot$se_median_sgpc, 2),
    n_boot       = boot$n_boot,
    n_converged  = boot$n_converged,
    stringsAsFactors = FALSE
  )
  fwrite(unc_row, file.path(RESULTS_DIR, "step3_uncertainty_decomposition.csv"))
  cat("  Saved: step3_uncertainty_decomposition.csv\n")
} else {
  cat("  Skipped (no bootstrap results available).\n")
}


############################################################################
### Generate step3_bucket_probabilities.csv
############################################################################

cat("Generating step3_bucket_probabilities.csv...\n")

bucket_cfg_k3 <- STEP3_CONFIG$buckets$k3
bucket_cfg_k5 <- STEP3_CONFIG$buckets$k5

subgroup_results <- list()
if (!is.null(phase_a)) {
  sg_key <- paste0(phase_a$condition_id, "__", phase_a$subgroup_id)
  subgroup_results[[sg_key]] <- list(
    best_estimate = phase_a$best_estimate,
    bootstrap     = phase_a$bootstrap
  )
}

if (length(subgroup_results) > 0) {
  bucket_table <- build_bucket_table(subgroup_results,
                                      cutpoints_k3 = bucket_cfg_k3,
                                      cutpoints_k5 = bucket_cfg_k5)
  fwrite(bucket_table, file.path(RESULTS_DIR, "step3_bucket_probabilities.csv"))
  cat("  Saved: step3_bucket_probabilities.csv\n")

  # Also write stability summary as JSON
  stability <- list(
    cutpoints_k3  = bucket_cfg_k3,
    cutpoints_k5  = bucket_cfg_k5,
    n_subgroups   = nrow(bucket_table),
    mean_k3_consistency = round(mean(bucket_table$k3_consistency, na.rm = TRUE), 4),
    mean_k5_consistency = round(mean(bucket_table$k5_consistency, na.rm = TRUE), 4),
    subgroups     = lapply(seq_len(nrow(bucket_table)), function(i) {
      list(
        subgroup_id       = bucket_table$subgroup_id[i],
        k3_assigned       = bucket_table$k3_assigned[i],
        k3_consistency    = bucket_table$k3_consistency[i],
        k5_assigned       = bucket_table$k5_assigned[i],
        k5_consistency    = bucket_table$k5_consistency[i]
      )
    })
  )
  jsonlite::write_json(stability, file.path(RESULTS_DIR, "bucket_stability_summary.json"),
                        pretty = TRUE, auto_unbox = TRUE)
  cat("  Saved: bucket_stability_summary.json\n")
} else {
  cat("  Skipped (no subgroup results available).\n")
}


############################################################################
### Manifest Export
############################################################################

cat("\nExporting manifests...\n")

manifest_results <- list(
  subgroup_estimates = list(),
  bootstrap_results = if (!is.null(phase_a)) phase_a$bootstrap else NULL,
  config = STEP3_CONFIG,
  metadata = list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    n_phase_b_subgroups = if (!is.null(phase_b)) nrow(phase_b) else 0
  )
)

if (!is.null(phase_a)) {
  sg_key <- paste0(phase_a$condition_id, "__", phase_a$subgroup_id)
  manifest_results$subgroup_estimates[[sg_key]] <- phase_a$best_estimate
}

export_step3_manifest(manifest_results, output_dir = RESULTS_DIR)

cat("\n--- Phase C complete ---\n\n")
