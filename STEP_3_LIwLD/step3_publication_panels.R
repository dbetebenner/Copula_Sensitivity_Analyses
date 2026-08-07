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
###   B1. Objective growth regime landscape over (m, kappa) (Phase A showcase)
###   B2. Residual diagnostics in v-space (Phase A showcase)
###   C. Inferred regime vs actual SGPc (Phase A showcase)
###   D. Precision operating curves by N bucket (Phase B)
###   E. Recovery accuracy by year span (Phase B)
###   F. Regime family comparison (Phase A)
###   G. Bootstrap uncertainty distribution (Phase A)
###   H. District summary grade panel
###   I. Independence diagnostic (Phase A)
###   J. Sensitivity summary (Phase B2/B3)
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
### C.0a Standalone Mode Setup (if not run via run_step3.R)
############################################################################

# Check if we're running standalone (RESULTS_DIR not defined)
if (!exists("RESULTS_DIR")) {
  # Determine STEP3_ROOT based on current working directory
  if (grepl("STEP_3_LIwLD$", getwd())) {
    STEP3_ROOT <- getwd()
  } else if (file.exists("STEP_3_LIwLD")) {
    STEP3_ROOT <- file.path(getwd(), "STEP_3_LIwLD")
  } else {
    stop(
      "Cannot determine STEP3_ROOT. Please run from STEP_3_LIwLD directory or project root."
    )
  }

  # Load required packages
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop("Package 'data.table' required")
  }
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Package 'ggplot2' required")
  }
  if (!requireNamespace("patchwork", quietly = TRUE)) {
    stop("Package 'patchwork' required")
  }
  if (!requireNamespace("wesanderson", quietly = TRUE)) {
    stop("Package 'wesanderson' required")
  }

  require(data.table)
  require(ggplot2)
  require(patchwork)
  require(wesanderson)

  # Source required function files
  source(file.path(STEP3_ROOT, "functions/step3_publication_style.R"))
  source(file.path(STEP3_ROOT, "functions/figure_naming.R"))
  source(file.path(STEP3_ROOT, "functions/diagnostics_plots.R"))
  source(file.path(STEP3_ROOT, "functions/bucket_classification.R"))
  source(file.path(STEP3_ROOT, "functions/manifest_export.R"))
  source(file.path(STEP3_ROOT, "config_step3.R"))

  # Set paths
  RESULTS_DIR <- file.path(STEP3_ROOT, "results")

  cat("Running in standalone mode from:", STEP3_ROOT, "\n\n")
}

############################################################################
### C.0b  Load Results from Phases A and B
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

phase_b_copula_csv <- file.path(RESULTS_DIR, "phase_b_copula_sensitivity.csv")
phase_b_copula <- if (file.exists(phase_b_copula_csv)) {
  fread(phase_b_copula_csv)
} else {
  data.table()
}
phase_b_indep_csv <- file.path(
  RESULTS_DIR,
  "phase_b_independence_sensitivity.csv"
)
phase_b_indep <- if (file.exists(phase_b_indep_csv)) {
  fread(phase_b_indep_csv)
} else {
  data.table()
}
phase_b_precision_csv <- file.path(RESULTS_DIR, "phase_b_precision_by_n.csv")
phase_b_precision <- if (file.exists(phase_b_precision_csv)) {
  fread(phase_b_precision_csv)
} else {
  data.table()
}
phase_b_pool_registry_csv <- file.path(RESULTS_DIR, "phase_b_pool_registry.csv")
phase_b_pool_registry <- if (file.exists(phase_b_pool_registry_csv)) {
  fread(phase_b_pool_registry_csv)
} else {
  data.table()
}

viz_dir <- file.path(RESULTS_DIR, "visualizations")
if (!dir.exists(viz_dir)) {
  dir.create(viz_dir, recursive = TRUE)
}

formats <- STEP3_CONFIG$output$export_formats
cat("\n")


############################################################################
### Panel A: Observed vs Predicted CDF (Phase A showcase)
############################################################################

cat("Panel A: CDF Comparison... ")
# Already generated in Phase A as panel_a_cdf_comparison.*
if (file.exists(file.path(viz_dir, "phase_a", "panel_a_cdf_comparison.pdf"))) {
  cat("exists.\n")
} else if (!is.null(phase_a)) {
  plot_observed_vs_predicted_cdf(
    phase_a$best_estimate,
    title = format_step3_condition_label(
      phase_a$condition_id,
      phase_a$subgroup_col,
      phase_a$subgroup_id,
      "A."
    ),
    output_dir = file.path(viz_dir, "phase_a"),
    filename = "panel_a_cdf_comparison"
  )
  cat("generated.\n")
} else {
  cat("skipped (no Phase A data).\n")
}


############################################################################
### Panel B1: Growth Regime Surface (Phase A showcase)
############################################################################

cat("Panel B1: Growth Regime Surface... ")
if (
  file.exists(file.path(viz_dir, "phase_a", "panel_b1_objective_surface.pdf"))
) {
  cat("exists.\n")
} else if (!is.null(phase_a)) {
  plot_objective_surface(
    phase_a$best_estimate,
    title = format_step3_condition_label(
      phase_a$condition_id,
      phase_a$subgroup_col,
      phase_a$subgroup_id,
      "Growth Regime Surface"
    ),
    output_dir = file.path(viz_dir, "phase_a"),
    filename = "panel_b1_objective_surface"
  )
  cat("generated.\n")
} else {
  cat("skipped.\n")
}


############################################################################
### Panel A: CDF Comparison (with integrated residual panel)
###   Note: plot_observed_vs_predicted_cdf now includes the detailed residual
###   panel below the CDF overlay; panel_b2_residual_curve is no longer generated
###   as a separate file.
############################################################################
############################################################################
### Panel C: Regime Shape vs Actual SGPc (Phase A showcase)
############################################################################

cat("Panel C: Regime Shape Comparison... ")
if (
  file.exists(file.path(viz_dir, "phase_a", "panel_c_regime_comparison.pdf"))
) {
  cat("exists.\n")
} else if (!is.null(phase_a)) {
  plot_regime_shape(
    phase_a$best_estimate$regime,
    phase_a$true_sgpc,
    title = format_step3_condition_label(
      phase_a$condition_id,
      phase_a$subgroup_col,
      phase_a$subgroup_id,
      "C."
    ),
    output_dir = file.path(viz_dir, "phase_a"),
    filename = "panel_c_regime_comparison",
    bootstrap = phase_a$bootstrap
  )
  cat("generated.\n")
} else {
  cat("skipped.\n")
}


############################################################################
### Panel D: Recovery Accuracy by Subgroup Size (Phase B)
############################################################################

cat("Panel D: Recovery Precision vs N Buckets... ")
if (!is.null(phase_b_precision) && nrow(phase_b_precision) > 0) {
  precision_plot_dt <- phase_b_precision[,
    .(
      n_bucket,
      median_ci_width_90 = mean(median_ci_width_90, na.rm = TRUE),
      median_ci_width_95 = mean(median_ci_width_95, na.rm = TRUE),
      median_mae = mean(median_mae, na.rm = TRUE),
      mean_mae = mean(mean_mae, na.rm = TRUE)
    ),
    by = .(n_bucket)
  ]
  precision_plot_dt <- precision_plot_dt[order(n_bucket)]
  plot_precision_vs_n(
    precision_dt = precision_plot_dt,
    output_dir = viz_dir,
    filename = "panel_d_recovery_by_size",
    title = "Recovery Precision vs Sample Size"
  )
  cat("generated.\n")
} else {
  cat("skipped (no precision-by-N data).\n")
}


############################################################################
### Panel D2: Sampling-Mode Precision Decomposition (Phase B)
###
### Requires both "paired" and "independent" sampling modes in precision data.
### Compares CI widths and MAE by mode to quantify the "linkage premium" —
### the additional uncertainty from independent cohorts (TIMSS/NAEP design).
############################################################################

cat("Panel D2: Sampling-Mode Precision Decomposition... ")
if (
  !is.null(phase_b_precision) &&
    nrow(phase_b_precision) > 0 &&
    "sampling_mode" %in% names(phase_b_precision) &&
    all(c("paired", "independent") %in% phase_b_precision$sampling_mode)
) {
  # Aggregate across pools but preserve sampling_mode dimension
  decomp_plot_dt <- phase_b_precision[,
    .(
      median_ci_width_90 = mean(median_ci_width_90, na.rm = TRUE),
      median_ci_width_95 = mean(median_ci_width_95, na.rm = TRUE),
      median_mae = mean(median_mae, na.rm = TRUE),
      mean_mae = mean(mean_mae, na.rm = TRUE)
    ),
    by = .(n_bucket, sampling_mode)
  ]
  decomp_plot_dt <- decomp_plot_dt[order(n_bucket, sampling_mode)]

  plot_precision_decomposition(
    precision_dt = decomp_plot_dt,
    output_dir = viz_dir,
    filename = "panel_d2_precision_decomposition",
    title = "Sampling-Mode Precision Decomposition: Paired vs Independent Cohorts"
  )
  cat("generated.\n")
} else {
  cat("skipped (need both paired and independent sampling modes).\n")
}


############################################################################
### Panel D3: Linkage Fraction Curve (Phase B)
###
### Shows CI width as a continuous function of linkage fraction (0-1).
### Requires linkage_fraction column with at least 3 distinct values.
############################################################################

cat("Panel D3: Linkage Fraction Curve... ")
if (
  !is.null(phase_b_precision) &&
    nrow(phase_b_precision) > 0 &&
    "linkage_fraction" %in% names(phase_b_precision) &&
    length(unique(phase_b_precision$linkage_fraction)) >= 3
) {
  plot_linkage_fraction_curve(
    precision_dt = phase_b_precision,
    n_bucket_focus = NULL, # auto-select most common
    filename = "panel_d3_linkage_fraction_curve",
    output_dir = viz_dir,
    condition_label = NULL
  )
  cat("generated.\n")
} else {
  n_lf <- if (
    !is.null(phase_b_precision) &&
      "linkage_fraction" %in% names(phase_b_precision)
  ) {
    length(unique(phase_b_precision$linkage_fraction))
  } else {
    0
  }
  cat(sprintf("skipped (need >= 3 linkage fractions, have %d).\n", n_lf))
}


############################################################################
### Panel D4: Churn Bookkeeping Summary (Phase B)
############################################################################

cat("Panel D4: Churn Bookkeeping... ")
churn_file <- file.path(RESULTS_DIR, "phase_b_churn_bookkeeping.csv")
if (file.exists(churn_file)) {
  phase_b_churn <- data.table::fread(churn_file)
  if (nrow(phase_b_churn) > 0) {
    # Condition-level summary table (pools with pool_type == "condition")
    cond_churn <- phase_b_churn[pool_type == "condition"]
    if (nrow(cond_churn) > 0) {
      tryCatch(
        {
          # Heatmap-style summary: alpha/beta by condition
          churn_long <- data.table::melt(
            cond_churn,
            id.vars = c("condition_id", "year_span", "content_area"),
            measure.vars = c("alpha", "beta"),
            variable.name = "rate_type",
            value.name = "retention"
          )
          churn_long[,
            rate_label := fifelse(
              rate_type == "alpha",
              "Prior (\u03b1)",
              "Current (\u03b2)"
            )
          ]
          churn_long[,
            condition_short := paste0(content_area, " ", year_span, "yr")
          ]

          p_churn <- ggplot(
            churn_long,
            aes(x = rate_label, y = condition_short, fill = retention)
          ) +
            geom_tile(color = "white", linewidth = 0.5) +
            geom_text(aes(label = sprintf("%.3f", retention)), size = 3.2) +
            scale_fill_gradient2(
              low = "#D7191C",
              mid = "#FFFFBF",
              high = "#1A9850",
              midpoint = 0.85,
              limits = c(0.5, 1.0),
              name = "Retention Rate"
            ) +
            labs(
              title = "Churn Bookkeeping: Retention Rates by Condition",
              subtitle = paste0(
                "n_conditions = ",
                nrow(cond_churn),
                " | churn types: ",
                paste(unique(cond_churn$churn_type), collapse = ", ")
              ),
              x = NULL,
              y = NULL
            ) +
            theme_publication() +
            theme(legend.position = "right")

          save_plot_multi(
            p_churn,
            "panel_d4_churn_bookkeeping",
            viz_dir,
            width = PLOT_WIDTH,
            height = max(5, nrow(cond_churn) * 0.6 + 3)
          )
          cat("generated.\n")
        },
        error = function(e) {
          cat(sprintf("WARNING: %s\n", e$message))
        }
      )
    } else {
      cat("skipped (no condition-level rows).\n")
    }
  } else {
    cat("skipped (empty churn file).\n")
  }
} else {
  cat("skipped (no churn bookkeeping file).\n")
}


############################################################################
### Panel E: Recovery Accuracy by Year Span (Phase B)
############################################################################

cat("Panel E: Recovery Accuracy by Year Span... ")
if (!is.null(phase_b) && nrow(phase_b) > 0 && "year_span" %in% names(phase_b)) {
  pb_span <- data.frame(
    year_span = factor(paste0(phase_b$year_span, "-yr")),
    abs_diff = abs(phase_b$median_diff)
  )

  pD <- ggplot(pb_span, aes(x = year_span, y = abs_diff)) +
    geom_boxplot(
      fill = alpha(STEP3_COLORS$point_est, 0.25),
      color = STEP3_COLORS$point_est,
      outlier.shape = NA
    ) +
    geom_jitter(
      width = 0.15,
      size = 1,
      alpha = 0.4,
      color = STEP3_COLORS$loess_trend
    ) +
    geom_hline(yintercept = 2, linetype = "dashed", color = "grey60") +
    labs(
      title = "Recovery Accuracy by Year Span",
      subtitle = "Does recovery error worsen as elapsed year span increases?\nStatistic: |inferred - true median SGPc| distribution by span",
      x = "Year Span",
      y = "|Inferred - True Median SGPc|"
    ) +
    theme_publication()

  save_plot_multi(
    pD,
    "panel_e_recovery_by_span",
    viz_dir,
    width = 7,
    height = PLOT_HEIGHT
  )
  cat("generated.\n")
} else {
  cat("skipped.\n")
}


############################################################################
### Panel F: Regime Family Comparison (Phase A)
############################################################################

cat("Panel F: Regime Family Comparison... ")
if (!is.null(phase_a) && !is.null(phase_a$family_comparison)) {
  comp <- phase_a$family_comparison$comparison
  p_grid <- seq(0.01, 0.99, length.out = 200)

  df_list <- list()
  for (fam in comp$family) {
    fam_est <- phase_a$family_comparison$results[[fam]]
    if (!is.null(fam_est)) {
      d_vals <- fam_est$regime$density(p_grid)
      df_list[[fam]] <- data.frame(
        sgpc = p_grid * 100,
        density = d_vals,
        source = fam,
        stringsAsFactors = FALSE
      )
    }
  }

  if (!is.null(phase_a$true_sgpc)) {
    true_d <- density(
      phase_a$true_sgpc / 100,
      from = 0.01,
      to = 0.99,
      bw = "SJ",
      n = 200
    )
    df_list[["actual"]] <- data.frame(
      sgpc = true_d$x * 100,
      density = true_d$y,
      source = "Actual",
      stringsAsFactors = FALSE
    )
  }

  df_fam <- do.call(rbind, df_list)

  fam_colors <- c(REGIME_FAMILY_COLORS, "Actual" = STEP3_COLORS$observed)
  fam_ltys <- c(REGIME_FAMILY_LINETYPES, "Actual" = "solid")

  dist_labels <- paste0(comp$family, ": W1=", round(comp$distance, 4))
  subtitle_e <- paste0(
    "Does regime family choice materially change recovered growth distribution?\n",
    "Statistics: ",
    paste(dist_labels, collapse = " | ")
  )

  pE <- ggplot(
    df_fam,
    aes(x = sgpc, y = density, color = source, linetype = source)
  ) +
    geom_line(linewidth = 0.9) +
    scale_color_manual(values = fam_colors) +
    scale_linetype_manual(values = fam_ltys) +
    geom_ref_vline(xintercept = 50) +
    labs(
      title = "Regime Family Comparison",
      subtitle = subtitle_e,
      x = "SGPc",
      y = "Density",
      color = NULL,
      linetype = NULL
    ) +
    coord_cartesian(xlim = c(0, 100)) +
    theme_publication()

  save_plot_multi(pE, "panel_f_family_comparison", viz_dir)
  cat("generated.\n")
} else {
  cat("skipped.\n")
}


############################################################################
### Panel G: Bootstrap Uncertainty Distribution (Phase A)
############################################################################

cat("Panel G: Bootstrap Uncertainty... ")
if (!is.null(phase_a) && !is.null(phase_a$bootstrap)) {
  if (sum(!is.na(phase_a$bootstrap$median_sgpc_draws)) > 10) {
    plot_bootstrap_sgpc_combined(
      bootstrap = phase_a$bootstrap,
      true_sgpc = phase_a$true_sgpc,
      title = format_step3_condition_label(
        phase_a$condition_id,
        phase_a$subgroup_col,
        phase_a$subgroup_id,
        "G."
      ),
      output_dir = file.path(viz_dir, "phase_a"),
      filename = "panel_g_bootstrap_uncertainty"
    )
    cat("generated.\n")
  } else {
    cat("skipped (insufficient bootstrap draws).\n")
  }
} else {
  cat("skipped.\n")
}


############################################################################
### Panel G2: Linkage Premium Decomposition (Phase A)
###
### Overlays paired and independent bootstrap distributions to show
### the CI widening from cross-sectional (independent cohort) sampling.
### This is the single-N counterpart to Phase B's Panel D2.
############################################################################

cat("Panel G2: Linkage Premium Decomposition... ")
if (
  !is.null(phase_a) &&
    !is.null(phase_a$bootstrap_paired) &&
    !is.null(phase_a$bootstrap) &&
    sum(!is.na(phase_a$bootstrap$median_sgpc_draws)) > 10 &&
    sum(!is.na(phase_a$bootstrap_paired$median_sgpc_draws)) > 10
) {
  plot_linkage_decomposition(
    boot_independent = phase_a$bootstrap,
    boot_paired = phase_a$bootstrap_paired,
    true_sgpc = phase_a$true_sgpc,
    linkage_premium = phase_a$linkage_premium,
    title = format_step3_condition_label(
      phase_a$condition_id,
      phase_a$subgroup_col,
      phase_a$subgroup_id,
      "G2. Linkage Premium"
    ),
    output_dir = file.path(viz_dir, "phase_a"),
    filename = "panel_g2_linkage_decomposition"
  )
  cat("generated.\n")
} else {
  cat("skipped (need both paired and independent bootstrap).\n")
}


############################################################################
### Panel I: Independence Diagnostic (Phase A)
############################################################################

cat("Panel I: Independence Diagnostic... ")
if (
  !is.null(phase_a) && !is.null(phase_a$u_sample) && !is.null(phase_a$true_sgpc)
) {
  plot_independence_diagnostic(
    u_sample = phase_a$u_sample,
    true_sgpc = phase_a$true_sgpc,
    n_bins = STEP3_CONFIG$assumptions$independence$u_bins,
    output_dir = file.path(viz_dir, "phase_a"),
    filename = "panel_i_independence_diagnostic",
    title = format_step3_condition_label(
      phase_a$condition_id,
      phase_a$subgroup_col,
      phase_a$subgroup_id,
      "I."
    )
  )
  cat("generated.\n")
} else {
  cat("skipped.\n")
}


############################################################################
### Panel J: Sensitivity Summary (Phase B2/B3)
############################################################################

cat("Panel J: Sensitivity Summary... ")
if (nrow(phase_b_copula) > 0 || nrow(phase_b_indep) > 0) {
  p_list <- list()
  if (nrow(phase_b_copula) > 0) {
    p1 <- ggplot(phase_b_copula, aes(x = delta_median_vs_base)) +
      geom_histogram(
        bins = 30,
        fill = alpha(STEP3_COLORS$predicted, 0.35),
        color = STEP3_COLORS$predicted
      ) +
      geom_ref_vline(xintercept = 0) +
      labs(
        title = "Copula parameter sensitivity",
        subtitle = paste0(
          "How sensitive is median SGPc to plausible copula-parameter shifts?\n",
          "Statistic: distribution of delta median SGPc relative to baseline"
        ),
        x = "Delta median SGPc vs baseline",
        y = "Count"
      ) +
      theme_publication(base_size = 9)
    p_list[[length(p_list) + 1]] <- p1
  }
  if (nrow(phase_b_indep) > 0) {
    p2 <- ggplot(phase_b_indep, aes(x = delta_median)) +
      geom_histogram(
        bins = 30,
        fill = alpha(STEP3_COLORS$actual, 0.35),
        color = STEP3_COLORS$actual
      ) +
      geom_ref_vline(xintercept = 0) +
      labs(
        title = "Independence stratification sensitivity",
        subtitle = paste0(
          "How much does relaxing a single pooled independence assumption shift results?\n",
          "Statistic: distribution of delta median SGPc (stratified - pooled)"
        ),
        x = "Delta median SGPc (stratified - single)",
        y = "Count"
      ) +
      theme_publication(base_size = 9)
    p_list[[length(p_list) + 1]] <- p2
  }
  if (length(p_list) == 1) {
    pJ <- p_list[[1]]
  } else {
    pJ <- p_list[[1]] | p_list[[2]]
  }
  pJ <- pJ +
    patchwork::plot_annotation(
      title = "Sensitivity Summary",
      subtitle = paste0(
        "Are STEP 3 subgroup estimates robust to key modeling assumptions?\n",
        "Statistics: histogrammed deltas around zero for copula and independence perturbations"
      )
    )
  save_plot_multi(
    pJ,
    "panel_j_sensitivity_summary",
    viz_dir,
    width = 12,
    height = 6
  )
  cat("generated.\n")
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
  best_params <- if (!is.null(phase_a$best_estimate$regime_param_hat)) {
    phase_a$best_estimate$regime_param_hat
  } else {
    phase_a$best_estimate$theta_hat
  }
  m_hat <- if (!is.null(phase_a$best_estimate$m_hat)) {
    phase_a$best_estimate$m_hat
  } else {
    best_params[1]
  }
  kappa_hat <- if (
    !is.null(phase_a$best_estimate$kappa_hat) && length(best_params) > 1
  ) {
    phase_a$best_estimate$kappa_hat
  } else if (length(best_params) > 1) {
    best_params[2]
  } else {
    NA_real_
  }
  est_rows[["phase_a"]] <- data.frame(
    subgroup_id = paste0(phase_a$condition_id, "__", phase_a$subgroup_id),
    dataset_id = phase_a$dataset_id,
    condition_id = phase_a$condition_id,
    n = phase_a$n_subgroup,
    regime_family = regime$family,
    regime_param_1 = round(best_params[1], 4),
    regime_param_2 = if (length(best_params) > 1) {
      round(best_params[2], 4)
    } else {
      NA_real_
    },
    m_hat = round(m_hat, 4),
    kappa_hat = round(kappa_hat, 4),
    median_sgpc = round(regime$median * 100, 2),
    mean_sgpc = round(regime$mean * 100, 2),
    dispersion_sd = round(regime$sd * 100, 2),
    dispersion_iqr = round(regime$iqr * 100, 2),
    entropy = round(regime$entropy, 4),
    concentration = round(regime$concentration, 2),
    distance_min = round(phase_a$best_estimate$distance_min, 6),
    wasserstein1 = round(phase_a$best_estimate$all_distances$wasserstein1, 6),
    cvm = round(phase_a$best_estimate$all_distances$cramer_von_mises, 6),
    stringsAsFactors = FALSE
  )
}

if (!is.null(phase_b) && nrow(phase_b) > 0) {
  for (i in seq_len(nrow(phase_b))) {
    row <- phase_b[i, ]
    est_rows[[paste0("pb_", i)]] <- data.frame(
      subgroup_id = paste0(row$condition_id, "__", row$subgroup_id),
      dataset_id = row$dataset_id,
      condition_id = row$condition_id,
      n = row$n_subgroup,
      regime_family = row$regime_family,
      regime_param_1 = if ("regime_param_1" %in% names(row)) {
        row$regime_param_1
      } else {
        row$theta1
      },
      regime_param_2 = if ("regime_param_2" %in% names(row)) {
        row$regime_param_2
      } else if ("theta2" %in% names(row)) {
        row$theta2
      } else {
        NA_real_
      },
      m_hat = if ("m_hat" %in% names(row)) {
        row$m_hat
      } else if ("regime_param_1" %in% names(row)) {
        row$regime_param_1
      } else {
        row$theta1
      },
      kappa_hat = if ("kappa_hat" %in% names(row)) {
        row$kappa_hat
      } else if ("regime_param_2" %in% names(row)) {
        row$regime_param_2
      } else if ("theta2" %in% names(row)) {
        row$theta2
      } else {
        NA_real_
      },
      median_sgpc = row$median_sgpc_inferred,
      mean_sgpc = row$mean_sgpc_inferred,
      dispersion_sd = NA_real_,
      dispersion_iqr = NA_real_,
      entropy = NA_real_,
      concentration = NA_real_,
      distance_min = row$wasserstein1,
      wasserstein1 = row$wasserstein1,
      cvm = row$cvm,
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
  var_sampling <- if (!is.na(boot$se_median_sgpc)) {
    boot$se_median_sgpc^2
  } else {
    NA_real_
  }

  # Copula uncertainty (if available in the results object)
  var_copula <- NA_real_
  if (!is.null(phase_a$copula_uncertainty)) {
    var_copula <- phase_a$copula_uncertainty$var_copula
  }

  # Regime family uncertainty from family comparison
  var_family <- NA_real_
  if (
    !is.null(phase_a$family_comparison) &&
      nrow(phase_a$family_comparison$comparison) > 1
  ) {
    family_medians <- phase_a$family_comparison$comparison$median_sgpc
    var_family <- var(family_medians)
  }

  total_var <- sum(c(var_sampling, var_copula, var_family), na.rm = TRUE)

  unc_row <- data.frame(
    subgroup_id = paste0(phase_a$condition_id, "__", phase_a$subgroup_id),
    var_sampling = round(var_sampling, 4),
    var_copula = round(var_copula, 4),
    var_family = round(var_family, 4),
    total_var = round(total_var, 4),
    se_sampling = round(boot$se_median_sgpc, 2),
    n_boot = boot$n_boot,
    n_converged = boot$n_converged,
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
    bootstrap = phase_a$bootstrap
  )
}

if (length(subgroup_results) > 0) {
  bucket_table <- build_bucket_table(
    subgroup_results,
    cutpoints_k3 = bucket_cfg_k3,
    cutpoints_k5 = bucket_cfg_k5
  )
  fwrite(bucket_table, file.path(RESULTS_DIR, "step3_bucket_probabilities.csv"))
  cat("  Saved: step3_bucket_probabilities.csv\n")

  # Also write stability summary as JSON
  stability <- list(
    cutpoints_k3 = bucket_cfg_k3,
    cutpoints_k5 = bucket_cfg_k5,
    n_subgroups = nrow(bucket_table),
    mean_k3_consistency = round(
      mean(bucket_table$k3_consistency, na.rm = TRUE),
      4
    ),
    mean_k5_consistency = round(
      mean(bucket_table$k5_consistency, na.rm = TRUE),
      4
    ),
    subgroups = lapply(seq_len(nrow(bucket_table)), function(i) {
      list(
        subgroup_id = bucket_table$subgroup_id[i],
        k3_assigned = bucket_table$k3_assigned[i],
        k3_consistency = bucket_table$k3_consistency[i],
        k5_assigned = bucket_table$k5_assigned[i],
        k5_consistency = bucket_table$k5_consistency[i]
      )
    })
  )
  jsonlite::write_json(
    stability,
    file.path(RESULTS_DIR, "bucket_stability_summary.json"),
    pretty = TRUE,
    auto_unbox = TRUE
  )
  cat("  Saved: bucket_stability_summary.json\n")
} else {
  cat("  Skipped (no subgroup results available).\n")
}


############################################################################
### Generate district_summary_grade.csv + Panel H
############################################################################

cat("Generating district summary grade artifact...\n")

if (!is.null(phase_a)) {
  sg_key <- paste0(phase_a$condition_id, "__", phase_a$subgroup_id)
  fit_path <- file.path(
    RESULTS_DIR,
    "exports",
    "phase_a",
    "step3_fit_metrics.csv"
  )
  fit_dt <- if (file.exists(fit_path)) fread(fit_path) else data.table()

  bucket_path <- file.path(RESULTS_DIR, "step3_bucket_probabilities.csv")
  bucket_dt <- if (file.exists(bucket_path)) {
    fread(bucket_path)
  } else {
    data.table()
  }
  bucket_row <- if (nrow(bucket_dt) > 0) {
    bucket_dt[subgroup_id == sg_key][1]
  } else {
    NULL
  }

  fit_row <- if (nrow(fit_dt) > 0) fit_dt[subgroup_id == sg_key][1] else NULL
  if (is.null(fit_row) || nrow(fit_row) == 0) {
    fit_row <- data.table(
      subgroup_id = sg_key,
      w1_uniform = NA_real_,
      w1_best = phase_a$best_estimate$all_distances$wasserstein1,
      w1_reduction_pct = NA_real_,
      cvm = phase_a$best_estimate$all_distances$cramer_von_mises,
      max_abs_residual = max(
        abs(phase_a$best_estimate$F_pred - phase_a$best_estimate$F_obs),
        na.rm = TRUE
      ),
      mean_abs_residual = mean(
        abs(phase_a$best_estimate$F_pred - phase_a$best_estimate$F_obs),
        na.rm = TRUE
      )
    )
  }

  boot <- phase_a$bootstrap
  ci_lo <- if (!is.null(boot)) boot$ci_median_sgpc[1] else NA_real_
  ci_hi <- if (!is.null(boot)) boot$ci_median_sgpc[2] else NA_real_
  ci_width <- if (is.finite(ci_lo) && is.finite(ci_hi)) {
    ci_hi - ci_lo
  } else {
    NA_real_
  }

  quality_flags <- character(0)
  if (phase_a$n_subgroup < 200) {
    quality_flags <- c(quality_flags, "small_n")
  }
  if (
    !is.null(phase_a$best_estimate$convergence) &&
      phase_a$best_estimate$convergence != 0
  ) {
    quality_flags <- c(quality_flags, "optimizer_warning")
  }
  if (is.finite(ci_width) && ci_width > 12) {
    quality_flags <- c(quality_flags, "wide_ci")
  }
  if (is.finite(fit_row$max_abs_residual) && fit_row$max_abs_residual > 0.05) {
    quality_flags <- c(quality_flags, "high_residual")
  }
  if (
    !is.null(boot) &&
      !is.na(boot$n_boot) &&
      !is.na(boot$n_converged) &&
      boot$n_converged < (0.85 * boot$n_boot)
  ) {
    quality_flags <- c(quality_flags, "bootstrap_instability")
  }
  if (isTRUE(phase_a$flag_independence_violation)) {
    quality_flags <- c(quality_flags, "independence_violation")
  }
  if (length(quality_flags) == 0) {
    quality_flags <- "none"
  }
  health <- "good"
  if (
    "independence_violation" %in%
      quality_flags ||
      "high_residual" %in% quality_flags ||
      "bootstrap_instability" %in% quality_flags
  ) {
    health <- "bad"
  } else if (
    "wide_ci" %in% quality_flags || "optimizer_warning" %in% quality_flags
  ) {
    health <- "warn"
  }
  fit_failure_reason <- if (
    !is.null(phase_a$best_estimate$convergence) &&
      phase_a$best_estimate$convergence != 0
  ) {
    "optimizer_nonzero_convergence"
  } else if ("high_residual" %in% quality_flags) {
    "kernel_or_family_mismatch"
  } else {
    "none"
  }

  summary_grade <- data.frame(
    subgroup_id = sg_key,
    dataset_id = phase_a$dataset_id,
    condition_id = phase_a$condition_id,
    subgroup_col = phase_a$subgroup_col,
    subgroup_value = phase_a$subgroup_id,
    n_subgroup = phase_a$n_subgroup,
    regime_family = phase_a$best_family,
    mean_sgpc_inferred = round(phase_a$best_estimate$regime$mean * 100, 2),
    mean_sgpc_true = round(mean(phase_a$true_sgpc, na.rm = TRUE), 2),
    median_sgpc_inferred = round(phase_a$best_estimate$regime$median * 100, 2),
    median_sgpc_true = round(median(phase_a$true_sgpc, na.rm = TRUE), 2),
    w1_best = round(fit_row$w1_best, 6),
    w1_uniform = round(fit_row$w1_uniform, 6),
    w1_reduction_pct = round(fit_row$w1_reduction_pct, 2),
    cvm = round(fit_row$cvm, 6),
    max_abs_residual = round(fit_row$max_abs_residual, 6),
    mean_abs_residual = round(fit_row$mean_abs_residual, 6),
    n_effective = phase_a$n_subgroup,
    ci95_median_lo = round(ci_lo, 2),
    ci95_median_hi = round(ci_hi, 2),
    ci95_width = round(ci_width, 2),
    bootstrap_n = if (!is.null(boot)) boot$n_boot else NA_integer_,
    bootstrap_converged = if (!is.null(boot)) boot$n_converged else NA_integer_,
    flag_independence_violation = isTRUE(phase_a$flag_independence_violation),
    k3_assigned = if (!is.null(bucket_row) && nrow(bucket_row) > 0) {
      as.character(bucket_row$k3_assigned)
    } else {
      NA_character_
    },
    k3_consistency = if (!is.null(bucket_row) && nrow(bucket_row) > 0) {
      as.numeric(bucket_row$k3_consistency)
    } else {
      NA_real_
    },
    k5_assigned = if (!is.null(bucket_row) && nrow(bucket_row) > 0) {
      as.character(bucket_row$k5_assigned)
    } else {
      NA_character_
    },
    k5_consistency = if (!is.null(bucket_row) && nrow(bucket_row) > 0) {
      as.numeric(bucket_row$k5_consistency)
    } else {
      NA_real_
    },
    health = health,
    fit_failure_reason = fit_failure_reason,
    quality_flags = paste(quality_flags, collapse = "|"),
    stringsAsFactors = FALSE
  )

  fwrite(summary_grade, file.path(RESULTS_DIR, "district_summary_grade.csv"))
  plot_district_summary_grade(
    summary_row = summary_grade,
    output_dir = viz_dir,
    filename = "panel_h_district_summary_grade"
  )
  cat("  Saved: district_summary_grade.csv\n")
  cat("  Saved: panel_h_district_summary_grade.{pdf,svg,png}\n")
} else {
  cat("  Skipped (no Phase A deep-dive results).\n")
}


############################################################################
### Manifest Export
############################################################################

cat("\nExporting manifests...\n")

# ---------------------------------------------------------------------------
# C.M1  Assemble Phase B systematic summary
#   - Precision operating table keyed by (year_span x n_bucket) — the primary
#     Phase B scientific deliverable.
#   - Overview: conditions, year spans, content areas, pool types, reps.
# ---------------------------------------------------------------------------
phase_b_systematic_summary <- NULL
if (nrow(phase_b_precision) > 0) {
  # Cross-tab precision by (year_span x n_bucket) if year_span column present
  precision_by_n_span <- NULL
  if (
    "year_span" %in%
      names(phase_b_precision) &&
      "span" %in% names(phase_b_precision)
  ) {
    span_col <- "span"
  } else if ("year_span" %in% names(phase_b_precision)) {
    span_col <- "year_span"
  } else {
    span_col <- NULL
  }

  if (!is.null(span_col)) {
    tmp <- phase_b_precision[,
      .(
        median_ci_width_95 = round(mean(median_ci_width_95, na.rm = TRUE), 4),
        median_mae = round(mean(median_mae, na.rm = TRUE), 4),
        mean_mae = round(mean(mean_mae, na.rm = TRUE), 4),
        median_bias = round(mean(median_bias, na.rm = TRUE), 4),
        convergence_rate = round(
          sum(n_converged, na.rm = TRUE) /
            pmax(sum(n_reps, na.rm = TRUE), 1L),
          4
        ),
        n_pools = .N
      ),
      by = c(span_col, "n_bucket")
    ][order(get(span_col), n_bucket)]
    # Normalise column name to year_span for manifest consumers
    if (span_col != "year_span") {
      setnames(tmp, span_col, "year_span")
    }
    precision_by_n_span <- lapply(seq_len(nrow(tmp)), function(i) {
      as.list(tmp[i])
    })
  }

  # Year-span effect: mean |bias| per span
  year_span_finding <- NULL
  if (!is.null(precision_by_n_span)) {
    span_vals <- sapply(precision_by_n_span, `[[`, "year_span")
    mae_vals <- sapply(precision_by_n_span, `[[`, "median_mae")
    yf <- tapply(mae_vals, span_vals, mean, na.rm = TRUE)
    year_span_finding <- as.list(round(yf, 4))
  }

  # Overview
  n_pools_total <- nrow(phase_b_pool_registry)
  pool_types_used <- if (n_pools_total > 0) {
    unique(phase_b_pool_registry$pool_type)
  } else {
    character(0)
  }
  year_spans_tested <- sort(unique(phase_b_precision[[
    if (is.null(span_col)) "n_bucket" else span_col
  ]]))
  if (!is.null(span_col)) {
    year_spans_tested <- sort(unique(phase_b_precision[[span_col]]))
  }
  n_buckets_tested <- sort(unique(phase_b_precision$n_bucket))

  overall_conv_rate <- if (sum(phase_b_precision$n_reps, na.rm = TRUE) > 0) {
    round(
      sum(phase_b_precision$n_converged, na.rm = TRUE) /
        sum(phase_b_precision$n_reps, na.rm = TRUE),
      4
    )
  } else {
    NA_real_
  }

  # Content areas and subgroup-condition count from systematic summary csv
  phase_b_sys_csv_path <- file.path(
    RESULTS_DIR,
    "phase_b_systematic_summary.csv"
  )
  n_conditions <- NA_integer_
  n_sg_conditions <- NA_integer_
  content_areas_run <- character(0)
  if (file.exists(phase_b_sys_csv_path)) {
    pb_sys_dt <- tryCatch(fread(phase_b_sys_csv_path), error = function(e) NULL)
    if (!is.null(pb_sys_dt) && nrow(pb_sys_dt) > 0) {
      n_sg_conditions <- nrow(pb_sys_dt)
      if ("condition_id" %in% names(pb_sys_dt)) {
        n_conditions <- length(unique(pb_sys_dt$condition_id))
      }
      if ("content_area" %in% names(pb_sys_dt)) {
        content_areas_run <- sort(unique(pb_sys_dt$content_area))
      }
    }
  }

  # ---- Linkage premium: sampling-mode decomposition (paired vs independent) ----
  linkage_premium <- NULL
  has_sampling_mode <- "sampling_mode" %in%
    names(phase_b_precision) &&
    all(c("paired", "independent") %in% phase_b_precision$sampling_mode)

  if (has_sampling_mode) {
    cat("  Assembling linkage premium decomposition for manifest...\n")

    # Precision by (year_span x n_bucket x sampling_mode) — full cross-tab
    precision_by_n_span_mode <- NULL
    if (!is.null(span_col)) {
      tmp_mode <- phase_b_precision[,
        .(
          median_ci_width_95 = round(mean(median_ci_width_95, na.rm = TRUE), 4),
          median_mae = round(mean(median_mae, na.rm = TRUE), 4),
          mean_mae = round(mean(mean_mae, na.rm = TRUE), 4),
          median_bias = round(mean(median_bias, na.rm = TRUE), 4),
          convergence_rate = round(
            sum(n_converged, na.rm = TRUE) /
              pmax(sum(n_reps, na.rm = TRUE), 1L),
            4
          ),
          n_pools = .N
        ),
        by = c(span_col, "n_bucket", "sampling_mode")
      ][order(get(span_col), n_bucket, sampling_mode)]
      if (span_col != "year_span") {
        setnames(tmp_mode, span_col, "year_span")
      }
      precision_by_n_span_mode <- lapply(seq_len(nrow(tmp_mode)), function(i) {
        as.list(tmp_mode[i])
      })
    }

    # Linkage premium ratio by n_bucket: CI_independent / CI_paired
    lp_wide <- phase_b_precision[,
      .(
        median_ci_width_95 = round(mean(median_ci_width_95, na.rm = TRUE), 4),
        median_mae = round(mean(median_mae, na.rm = TRUE), 4)
      ),
      by = .(n_bucket, sampling_mode)
    ][order(n_bucket, sampling_mode)]

    lp_paired <- lp_wide[sampling_mode == "paired"]
    lp_indep <- lp_wide[sampling_mode == "independent"]

    # Validate n_bucket alignment before merge
    paired_buckets <- sort(lp_paired$n_bucket)
    indep_buckets <- sort(lp_indep$n_bucket)
    if (!identical(paired_buckets, indep_buckets)) {
      cat(
        "    WARNING: n_bucket mismatch between paired and independent modes.\n"
      )
      cat("      paired:      ", paste(paired_buckets, collapse = ", "), "\n")
      cat("      independent: ", paste(indep_buckets, collapse = ", "), "\n")
    }

    lp_merged <- merge(
      lp_paired,
      lp_indep,
      by = "n_bucket",
      suffixes = c("_paired", "_independent"),
      all = TRUE
    )

    # Safe ratio computation: guard against zero/NA denominators
    lp_merged[,
      ci_ratio := ifelse(
        is.finite(median_ci_width_95_paired) & median_ci_width_95_paired > 0,
        round(median_ci_width_95_independent / median_ci_width_95_paired, 2),
        NA_real_
      )
    ]
    lp_merged[,
      mae_ratio := ifelse(
        is.finite(median_mae_paired) & median_mae_paired > 0,
        round(median_mae_independent / median_mae_paired, 2),
        NA_real_
      )
    ]

    if (nrow(lp_merged) == 0) {
      cat("    WARNING: linkage premium merge produced 0 rows; skipping.\n")
      linkage_premium <- NULL
    } else {
      # Only compute means from finite ratio values
      finite_ci <- lp_merged$ci_ratio[is.finite(lp_merged$ci_ratio)]
      finite_mae <- lp_merged$mae_ratio[is.finite(lp_merged$mae_ratio)]

      linkage_premium <- list(
        description = paste0(
          "Linkage premium: the multiplicative factor by which uncertainty increases ",
          "when moving from paired (longitudinal) to independent (cross-sectional) ",
          "cohort sampling, as encountered in TIMSS and NAEP."
        ),
        sampling_modes = sort(unique(lp_wide$sampling_mode)),
        precision_by_n_span_mode = precision_by_n_span_mode,
        premium_by_n_bucket = lapply(seq_len(nrow(lp_merged)), function(i) {
          list(
            n_bucket = lp_merged$n_bucket[i],
            ci_width_95_paired = lp_merged$median_ci_width_95_paired[i],
            ci_width_95_independent = lp_merged$median_ci_width_95_independent[
              i
            ],
            ci_ratio = lp_merged$ci_ratio[i],
            mae_paired = lp_merged$median_mae_paired[i],
            mae_independent = lp_merged$median_mae_independent[i],
            mae_ratio = lp_merged$mae_ratio[i]
          )
        }),
        mean_ci_ratio = if (length(finite_ci) > 0) {
          round(mean(finite_ci), 2)
        } else {
          NA_real_
        },
        mean_mae_ratio = if (length(finite_mae) > 0) {
          round(mean(finite_mae), 2)
        } else {
          NA_real_
        }
      )

      cat(
        "    Mean CI ratio (independent / paired):",
        linkage_premium$mean_ci_ratio,
        "\n"
      )
      cat("    Mean MAE ratio:", linkage_premium$mean_mae_ratio, "\n")

      # Append linkage_fraction curve data when partial fractions are available
      if (
        "linkage_fraction" %in%
          names(phase_b_precision) &&
          length(unique(phase_b_precision$linkage_fraction)) >= 3
      ) {
        lf_curve <- phase_b_precision[,
          .(
            median_ci_width_95 = round(
              mean(median_ci_width_95, na.rm = TRUE),
              4
            ),
            mean_ci_width_95 = round(mean(mean_ci_width_95, na.rm = TRUE), 4),
            median_mae = round(mean(median_mae, na.rm = TRUE), 4),
            n_pools = .N
          ),
          by = .(n_bucket, linkage_fraction)
        ][order(n_bucket, -linkage_fraction)]

        linkage_premium$linkage_fraction_curve <- lapply(
          seq_len(nrow(lf_curve)),
          function(i) as.list(lf_curve[i])
        )
        linkage_premium$linkage_fraction_description <- paste0(
          "CI width as a continuous function of cohort overlap strength. ",
          "linkage_fraction = 1.0 is fully paired (longitudinal), 0.0 is fully ",
          "independent (cross-sectional). Intermediate values simulate designs ",
          "with partial cohort overlap."
        )
        cat(
          "    Linkage fraction curve: ",
          length(unique(lf_curve$linkage_fraction)),
          " fractions x ",
          length(unique(lf_curve$n_bucket)),
          " N-buckets\n"
        )
      }
    }
  }

  phase_b_systematic_summary <- list(
    overview = list(
      n_conditions = n_conditions,
      n_subgroup_conditions = n_sg_conditions,
      n_pools = n_pools_total,
      pool_types = pool_types_used,
      year_spans = year_spans_tested,
      content_areas = content_areas_run,
      n_buckets = n_buckets_tested,
      outer_reps = STEP3_CONFIG$systematic$outer_reps,
      overall_convergence_rate = overall_conv_rate,
      sampling_modes = if (has_sampling_mode) {
        sort(unique(phase_b_precision$sampling_mode))
      } else {
        c("paired")
      },
      linkage_fractions = if (
        "linkage_fraction" %in% names(phase_b_precision)
      ) {
        sort(unique(phase_b_precision$linkage_fraction), decreasing = TRUE)
      } else {
        c(1.0)
      }
    ),
    precision_by_n_span = precision_by_n_span,
    year_span_finding = year_span_finding,
    linkage_premium = linkage_premium,
    # Flat precision by n_bucket only (backward compat)
    precision_by_n = as.list(phase_b_precision[,
      .(
        median_ci_width_95 = round(mean(median_ci_width_95, na.rm = TRUE), 4),
        median_mae = round(mean(median_mae, na.rm = TRUE), 4)
      ),
      by = n_bucket
    ][order(n_bucket)])
  )
}

# ---------------------------------------------------------------------------
# C.M2  Error source decomposition object
#   Error 1 (sampling):  Phase B precision CIs — degradation with falling N
#   Error 2 (inference): Phase A inferred-vs-true at full pool N
# ---------------------------------------------------------------------------
error_sources <- NULL
if (!is.null(phase_a)) {
  inferred_median <- phase_a$best_estimate$regime$median * 100
  inferred_mean <- phase_a$best_estimate$regime$mean * 100
  true_median <- median(phase_a$true_sgpc, na.rm = TRUE)
  true_mean <- mean(phase_a$true_sgpc, na.rm = TRUE)

  # Variance decomposition: var_sampling from bootstrap, var_copula if available
  var_sampling <- var_copula <- pct_sampling <- pct_copula <- NA_real_
  if (
    !is.null(phase_a$bootstrap) && !is.null(phase_a$bootstrap$se_median_sgpc)
  ) {
    var_sampling <- phase_a$bootstrap$se_median_sgpc^2
  }
  if (
    !is.null(phase_a$copula_uncertainty) &&
      !is.null(phase_a$copula_uncertainty$var_copula)
  ) {
    var_copula <- phase_a$copula_uncertainty$var_copula
    total_var <- var_sampling + var_copula
    if (is.finite(total_var) && total_var > 0) {
      pct_sampling <- round(var_sampling / total_var * 100, 1)
      pct_copula <- round(var_copula / total_var * 100, 1)
    }
  }

  error_sources <- list(
    inference = list(
      description = "Error 2: bias at full subgroup N from copula/regime misspecification",
      inferred_median = round(inferred_median, 2),
      true_median = round(true_median, 2),
      median_error = round(inferred_median - true_median, 2),
      inferred_mean = round(inferred_mean, 2),
      true_mean = round(true_mean, 2),
      mean_error = round(inferred_mean - true_mean, 2),
      n_subgroup = phase_a$n_subgroup
    ),
    sampling = list(
      description = "Error 1: sampling noise from cross-sectional N; characterised by Phase B",
      phase_b_available = !is.null(phase_b_systematic_summary),
      naep_reference_n = list(
        min = 3000L,
        max = 4000L,
        note = "NAEP state-level typical range"
      ),
      timss_reference_n = list(
        min = 4000L,
        note = "TIMSS country-level minimum"
      ),
      linkage_premium_available = !is.null(phase_b_systematic_summary) &&
        !is.null(phase_b_systematic_summary$linkage_premium),
      linkage_premium_note = paste0(
        "Error 1 decomposes into two sub-components: ",
        "(1a) subsampling variability (paired mode) and ",
        "(1b) additional cohort-mismatch uncertainty from independent sampling ",
        "(TIMSS/NAEP cross-sectional design). The linkage premium ",
        "quantifies the multiplicative cost of (1b); see ",
        "phase_b_systematic$linkage_premium for per-N ratios."
      ),
      linkage_fraction_note = paste0(
        "The linkage_fraction parameter (0.0 to 1.0) maps the continuous ",
        "space between fully independent (0.0) and fully paired (1.0) cohort ",
        "designs. Partial overlap designs (e.g., some schools retained across ",
        "NAEP cycles) correspond to intermediate fractions. See ",
        "phase_b_systematic$linkage_premium$linkage_fraction_curve for the ",
        "full CI width curve."
      )
    ),
    variance_decomposition = if (!is.na(var_sampling)) {
      list(
        var_sampling = round(var_sampling, 4),
        var_copula = if (!is.na(var_copula)) round(var_copula, 4) else NA_real_,
        pct_sampling = pct_sampling,
        pct_copula = pct_copula,
        note = "var_sampling from bootstrap SE²; var_copula from n_copula_draws uncertainty draws"
      )
    } else {
      NULL
    }
  )
}

# ---------------------------------------------------------------------------
# C.M3  Bucket classification summary
# ---------------------------------------------------------------------------
bucket_classification <- NULL
bucket_summary_path <- file.path(RESULTS_DIR, "bucket_stability_summary.json")
if (file.exists(bucket_summary_path)) {
  bucket_classification <- tryCatch(
    jsonlite::fromJSON(bucket_summary_path, simplifyVector = FALSE),
    error = function(e) {
      cat(
        "WARNING: could not load bucket_stability_summary.json:",
        conditionMessage(e),
        "\n"
      )
      NULL
    }
  )
}

# ---------------------------------------------------------------------------
# C.M4  Phase B subgroup-level summaries (all conditions)
#   These supplement the single Phase A subgroup in subgroup_estimates.
# ---------------------------------------------------------------------------
phase_b_subgroup_estimates <- list()
# phase_b_sys_csv_path was set in C.M1; reuse it here
if (!exists("phase_b_sys_csv_path")) {
  phase_b_sys_csv_path <- file.path(
    RESULTS_DIR,
    "phase_b_systematic_summary.csv"
  )
}
if (file.exists(phase_b_sys_csv_path)) {
  pb_sys_dt2 <- tryCatch(fread(phase_b_sys_csv_path), error = function(e) NULL)
  if (!is.null(pb_sys_dt2) && nrow(pb_sys_dt2) > 0) {
    for (i in seq_len(nrow(pb_sys_dt2))) {
      row <- pb_sys_dt2[i]
      sg_key <- paste0("phaseb__", row$condition_id, "__", row$subgroup_id)
      phase_b_subgroup_estimates[[sg_key]] <- list(
        source = "phase_b",
        condition_id = row$condition_id,
        subgroup_id = row$subgroup_id,
        year_span = row$year_span,
        content_area = row$content_area,
        dataset_id = row$dataset_id,
        n_subgroup = row$n_subgroup,
        regime_family = row$regime_family,
        regime_param_hat = c(row$regime_param_1, row$regime_param_2),
        m_hat = row$m_hat,
        kappa_hat = row$kappa_hat,
        median_sgpc = round(row$median_sgpc_inferred, 2),
        mean_sgpc = round(row$mean_sgpc_inferred, 2),
        true_median = round(row$median_sgpc_true, 2),
        true_mean = round(row$mean_sgpc_true, 2),
        median_diff = round(row$median_diff, 2),
        mean_diff = round(row$mean_diff, 2),
        distance_min = round(row$wasserstein1, 6),
        distances = list(
          wasserstein1 = round(row$wasserstein1, 6),
          cramer_von_mises = round(row$cvm, 6)
        ),
        convergence = 1L
      )
    }
  }
}

# ---------------------------------------------------------------------------
# C.M5  Assemble full manifest_results
# ---------------------------------------------------------------------------
manifest_results <- list(
  subgroup_estimates = phase_b_subgroup_estimates, # Phase B conditions (populated above)
  bootstrap_results = if (!is.null(phase_a)) phase_a$bootstrap else NULL,
  assumption_diagnostics = if (!is.null(phase_a)) {
    phase_a$independence_diagnostics
  } else {
    NULL
  },
  phase_b_systematic = phase_b_systematic_summary,
  error_sources = error_sources,
  bucket_classification = bucket_classification,
  sensitivity = list(
    precision_by_n = if (nrow(phase_b_precision) > 0) {
      list(
        n_rows = nrow(phase_b_precision),
        n_buckets = sort(unique(phase_b_precision$n_bucket)),
        median_ci95_by_bucket = as.list(phase_b_precision[,
          .(
            median_ci_width_95 = round(
              mean(median_ci_width_95, na.rm = TRUE),
              4
            )
          ),
          by = n_bucket
        ][order(n_bucket)]),
        median_mae_by_bucket = as.list(phase_b_precision[,
          .(
            median_mae = round(mean(median_mae, na.rm = TRUE), 4)
          ),
          by = n_bucket
        ][order(n_bucket)])
      )
    } else {
      NULL
    },
    copula_param_range = if (nrow(phase_b_copula) > 0) {
      list(
        rho = range(phase_b_copula$rho, na.rm = TRUE),
        df = range(phase_b_copula$df, na.rm = TRUE)
      )
    } else {
      NULL
    },
    independence_stratified = if (nrow(phase_b_indep) > 0) {
      list(
        n_rows = nrow(phase_b_indep),
        mean_delta_median = round(
          mean(phase_b_indep$delta_median, na.rm = TRUE),
          4
        ),
        mean_delta_mean = round(mean(phase_b_indep$delta_mean, na.rm = TRUE), 4)
      )
    } else {
      NULL
    }
  ),
  config = STEP3_CONFIG,
  metadata = list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    n_phase_b_subgroups = if (!is.null(phase_b)) nrow(phase_b) else 0L,
    n_phase_b_pools = nrow(phase_b_pool_registry),
    n_phase_b_precision_rows = nrow(phase_b_precision),
    n_phase_b_sg_conditions = length(phase_b_subgroup_estimates)
  )
)

# Add Phase A subgroup to estimates (primary showcase)
if (!is.null(phase_a)) {
  sg_key <- paste0(phase_a$condition_id, "__", phase_a$subgroup_id)
  manifest_results$subgroup_estimates[[sg_key]] <- phase_a$best_estimate
}

export_step3_manifest(manifest_results, output_dir = RESULTS_DIR)

cat("Running output contract validation...\n")
validate_step3_output_contract(
  results_dir = RESULTS_DIR,
  strict = FALSE,
  verbose = TRUE
)

cat("\n--- Phase C complete ---\n\n")
