############################################################################
###
### STEP 3 — Enhanced Publication Panels
###
### New and revised figures for the STEP 3 sensitivity argument.
### Designed to be sourced after run_step3.R Phase C data loading,
### or standalone (with auto-detection).
###
### Panel Map (new/revised):
###   K1. Cross-condition validation scatter (inferred vs true median SGPc)
###   K2. Error decomposition panel (Error 1 vs Error 2)
###   D*. Revised Panel D: Precision vs N with NAEP/TIMSS zones
###   K3. Transition kernel visualization Q_0(p|u)
###   K4. Precision operating heatmap (year_span x N_bucket)
###   J*. Revised Panel J: Sensitivity with density overlays
###   H*. Revised Panel H: Visual scorecard
###   K5. Pool-type comparison panel
###   K6. Bias direction panel
###   E*. Revised Panel E: Recovery by span with content area facets
###
### Author: dataimago / Claude
### Date: March 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################

cat("\n=== Enhanced Publication Panels ===\n\n")

############################################################################
### Standalone Mode Setup
############################################################################

if (!exists("RESULTS_DIR")) {
  if (grepl("STEP_3_LIwLD$", getwd())) {
    STEP3_ROOT <- getwd()
  } else if (file.exists("STEP_3_LIwLD")) {
    STEP3_ROOT <- file.path(getwd(), "STEP_3_LIwLD")
  } else {
    stop("Cannot determine STEP3_ROOT. Run from STEP_3_LIwLD directory or project root.")
  }

  require(data.table)
  require(ggplot2)
  require(patchwork)
  require(wesanderson)
  require(scales)

  source(file.path(STEP3_ROOT, "functions/step3_publication_style.R"))
  fn_path <- file.path(STEP3_ROOT, "functions/figure_naming.R")
  if (file.exists(fn_path)) source(fn_path)
  dp_path <- file.path(STEP3_ROOT, "functions/diagnostics_plots.R")
  if (file.exists(dp_path)) source(dp_path)
  source(file.path(STEP3_ROOT, "config_step3.R"))

  RESULTS_DIR <- file.path(STEP3_ROOT, "results")
  cat("Running enhanced panels in standalone mode from:", STEP3_ROOT, "\n\n")
}

############################################################################
### Load all data sources
############################################################################

# Phase A
phase_a_path <- file.path(RESULTS_DIR, "phase_a_deep_dive.rds")
if (file.exists(phase_a_path) && !exists("phase_a")) {
  phase_a <- readRDS(phase_a_path)
  cat("Loaded Phase A results:", phase_a$condition_id, "\n")
}

# Phase B systematic summary
phase_b_csv <- file.path(RESULTS_DIR, "phase_b_systematic_summary.csv")
if (file.exists(phase_b_csv) && !exists("phase_b")) {
  phase_b <- fread(phase_b_csv)
  cat("Loaded Phase B systematic summary:", nrow(phase_b), "rows\n")
}

# Phase B precision by N
phase_b_precision_csv <- file.path(RESULTS_DIR, "phase_b_precision_by_n.csv")
if (file.exists(phase_b_precision_csv) && !exists("phase_b_precision")) {
  phase_b_precision <- fread(phase_b_precision_csv)
}

# Phase B sensitivity
phase_b_copula_csv <- file.path(RESULTS_DIR, "phase_b_copula_sensitivity.csv")
if (file.exists(phase_b_copula_csv) && !exists("phase_b_copula")) {
  phase_b_copula <- fread(phase_b_copula_csv)
}
phase_b_indep_csv <- file.path(RESULTS_DIR, "phase_b_independence_sensitivity.csv")
if (file.exists(phase_b_indep_csv) && !exists("phase_b_indep")) {
  phase_b_indep <- fread(phase_b_indep_csv)
}

# Phase B pool registry
phase_b_pool_csv <- file.path(RESULTS_DIR, "phase_b_pool_registry.csv")
if (file.exists(phase_b_pool_csv) && !exists("phase_b_pool_registry")) {
  phase_b_pool_registry <- fread(phase_b_pool_csv)
}

# Phase A exports
kernel_slices_csv <- file.path(RESULTS_DIR, "exports/phase_a/step3_kernel_slices.csv")
quantile_slices_csv <- file.path(RESULTS_DIR, "exports/phase_a/step3_quantile_slices.csv")

# District summary grade
dsg_csv <- file.path(RESULTS_DIR, "district_summary_grade.csv")
if (file.exists(dsg_csv)) {
  dsg <- fread(dsg_csv)
}

viz_dir <- file.path(RESULTS_DIR, "visualizations")
enhanced_dir <- file.path(viz_dir, "enhanced")
if (!dir.exists(enhanced_dir)) dir.create(enhanced_dir, recursive = TRUE)

cat("\n")


############################################################################
###
### K1. Cross-Condition Validation Scatter
###     Inferred vs True Median SGPc across all Phase B subgroups
###
############################################################################

cat("K1: Cross-Condition Validation Scatter (median + mean)... ")
if (exists("phase_b") && nrow(phase_b) > 0) {

  pb <- copy(phase_b)
  if (!"content_area" %in% names(pb)) pb[, content_area := "Unknown"]
  pb[, pool_type := fifelse(grepl("CLUSTER", subgroup_id), "Cluster", "District")]

  # Shared axis range: union of both median and mean columns so both panels
  # use identical axes and are directly comparable.
  rng_all <- range(c(pb$median_sgpc_inferred, pb$median_sgpc_true,
                     pb$mean_sgpc_inferred,   pb$mean_sgpc_true),
                   na.rm = TRUE)
  rng <- c(floor(rng_all[1] / 5) * 5, ceiling(rng_all[2] / 5) * 5)

  # ── Helper: build one K1 scatter panel ───────────────────────────────────
  # x_col / y_col : column names for true / inferred SGPc
  # diff_col      : column of signed differences (inferred − true)
  # stat_label    : short label for the summarising statistic ("Median"/"Mean")
  # ttl / sub     : title / subtitle strings
  make_k1_panel <- function(pb, x_col, y_col, diff_col, stat_label, ttl, sub) {

    mae_val  <- round(mean(abs(pb[[diff_col]]), na.rm = TRUE), 2)
    corr_val <- round(cor(pb[[x_col]], pb[[y_col]], use = "complete.obs"), 3)
    n_obs    <- nrow(pb)
    n_range  <- paste0(
      "N range: ", scales::comma(min(pb$n_subgroup, na.rm = TRUE)),
      "\u2013", scales::comma(max(pb$n_subgroup, na.rm = TRUE))
    )

    ggplot(pb, aes(x = .data[[x_col]], y = .data[[y_col]])) +
      # Reference lines
      geom_abline(intercept =  0, slope = 1, linetype = "dashed",
                  color = "grey50", linewidth = 0.6) +
      geom_abline(intercept =  2, slope = 1, linetype = "dotted",
                  color = "grey70", linewidth = 0.4) +
      geom_abline(intercept = -2, slope = 1, linetype = "dotted",
                  color = "grey70", linewidth = 0.4) +
      # Points: colour = content area, shape = pool type, SIZE = subgroup N
      geom_point(aes(color = content_area, shape = pool_type,
                     size  = n_subgroup),
                 alpha = 0.80) +
      # Colour scale
      scale_color_manual(
        values = c("WRITING"     = ZISSOU1_BASE[1],
                   "READING"     = ZISSOU1_BASE[4],
                   "MATHEMATICS" = ZISSOU1_BASE[5],
                   "Unknown"     = "grey50"),
        name = "Content Area"
      ) +
      scale_shape_manual(
        values = c("District" = 16, "Cluster" = 17),
        name = "Pool Type"
      ) +
      # Size scale: log10-transformed so large districts don't dominate visually
      scale_size_continuous(
        trans  = "log10",
        range  = c(1.5, 7),
        labels = scales::comma,
        name   = "Subgroup N"
      ) +
      # Stats annotation (top-left)
      annotate("text",
               x     = rng[1] + 1,
               y     = rng[2] - 0.5,
               label = sprintf(
                 "n = %d subgroups\nMAE(%s) = %.2f SGPc\nr = %.3f\n%s",
                 n_obs, stat_label, mae_val, corr_val, n_range
               ),
               hjust = 0, vjust = 1, size = 3.0,
               color = "grey30", fontface = "italic") +
      coord_fixed(xlim = rng, ylim = rng) +
      labs(title    = ttl,
           subtitle = sub,
           x = sprintf("True %s SGPc (from longitudinal pairs)", stat_label),
           y = sprintf("Inferred %s SGPc (from unlinked cross-sections)", stat_label)) +
      theme_publication() +
      theme(legend.position        = c(0.85, 0.22),
            legend.background      = element_rect(fill      = alpha("white", 0.9),
                                                   color     = "grey60",
                                                   linewidth = 0.4),
            legend.key.size        = unit(0.45, "cm"),
            legend.text            = element_text(size = 7.5),
            legend.title           = element_text(size = 8, face = "bold"),
            legend.spacing.y       = unit(0.15, "cm"))
  }

  # ── Median panel ─────────────────────────────────────────────────────────
  p_k1_median <- make_k1_panel(
    pb         = pb,
    x_col      = "median_sgpc_true",
    y_col      = "median_sgpc_inferred",
    diff_col   = "median_diff",
    stat_label = "Median",
    ttl = "Cross-Condition Validation: Inferred vs True Median SGPc",
    sub = paste0(
      "Does SGPcFlow recover true subgroup growth (median) across diverse conditions?\n",
      "Dashed = identity; dotted = \u00b12 SGPc envelope; point size \u221d subgroup N"
    )
  )

  # ── Mean panel ───────────────────────────────────────────────────────────
  p_k1_mean <- make_k1_panel(
    pb         = pb,
    x_col      = "mean_sgpc_true",
    y_col      = "mean_sgpc_inferred",
    diff_col   = "mean_diff",
    stat_label = "Mean",
    ttl = "Cross-Condition Validation: Inferred vs True Mean SGPc",
    sub = paste0(
      "Does SGPcFlow recover true subgroup growth (mean) across diverse conditions?\n",
      "Dashed = identity; dotted = \u00b12 SGPc envelope; point size \u221d subgroup N"
    )
  )

  # ── Combined stacked panel ────────────────────────────────────────────────
  p_k1_combined <- (p_k1_median / p_k1_mean) +
    plot_annotation(
      title    = "Cross-Condition Validation: Inferred vs True SGPc",
      subtitle = paste0(
        "Top: median-based recovery  |  Bottom: mean-based recovery.\n",
        "Mean is more stable for smaller subgroups; agreement between rows ",
        "indicates distributional robustness.  Point size \u221d subgroup N."
      ),
      theme = theme(
        plot.title    = element_text(face = "bold", size = 14),
        plot.subtitle = element_text(size = 11, color = "grey30")
      )
    )

  save_plot_multi(p_k1_median,   "panel_k1_median_validation_scatter",   enhanced_dir, width = 8,  height = 8)
  save_plot_multi(p_k1_mean,     "panel_k1_mean_validation_scatter",     enhanced_dir, width = 8,  height = 8)
  save_plot_multi(p_k1_combined, "panel_k1_combined_validation_scatter", enhanced_dir, width = 8,  height = 15)
  cat("generated.\n")
} else {
  cat("skipped (no Phase B data).\n")
}


############################################################################
###
### K2. Error Decomposition Panel
###     Stacked/waterfall showing Error 1 (sampling) + Error 2 (bridge)
###
############################################################################

cat("K2: Error Decomposition Panel... ")
if (exists("phase_b_precision") && nrow(phase_b_precision) > 0 && exists("phase_a")) {

  # Error 2 (bridge cost) from Phase A
  bridge_cost <- abs(phase_a$best_estimate$regime$median * 100 -
                       median(phase_a$true_sgpc, na.rm = TRUE))

  # Error 1 (sampling MAE) by N bucket — averaged across all pools
  sampling_by_n <- phase_b_precision[, .(
    sampling_mae = mean(median_mae, na.rm = TRUE)
  ), by = n_bucket][order(n_bucket)]

  # Combined (RSS)
  sampling_by_n[, bridge_mae := bridge_cost]
  sampling_by_n[, combined_rss := sqrt(sampling_mae^2 + bridge_mae^2)]
  sampling_by_n[, combined_add := sampling_mae + bridge_mae]

  # Long format for stacking
  df_decomp <- rbind(
    data.frame(n_bucket = sampling_by_n$n_bucket,
               component = "Error 2: Bridge/Inference",
               value = sampling_by_n$bridge_mae),
    data.frame(n_bucket = sampling_by_n$n_bucket,
               component = "Error 1: Sampling",
               value = sampling_by_n$sampling_mae)
  )
  df_decomp$component <- factor(df_decomp$component,
                                  levels = c("Error 1: Sampling", "Error 2: Bridge/Inference"))

  # Combined overlay
  df_combined <- data.frame(
    n_bucket = sampling_by_n$n_bucket,
    rss = sampling_by_n$combined_rss,
    additive = sampling_by_n$combined_add
  )

  p_k2 <- ggplot() +
    # Stacked bars
    geom_col(data = df_decomp,
             aes(x = factor(format(n_bucket, big.mark = ",")),
                 y = value, fill = component),
             width = 0.6) +
    # RSS combined line
    geom_point(data = df_combined,
               aes(x = factor(format(n_bucket, big.mark = ",")),
                   y = rss),
               shape = 18, size = 4, color = "grey20") +
    geom_line(data = df_combined,
              aes(x = factor(format(n_bucket, big.mark = ",")),
                  y = rss, group = 1),
              linetype = "solid", linewidth = 0.7, color = "grey20") +
    # Additive envelope (conservative)
    geom_point(data = df_combined,
               aes(x = factor(format(n_bucket, big.mark = ",")),
                   y = additive),
               shape = 1, size = 3.5, color = "grey45") +
    geom_line(data = df_combined,
              aes(x = factor(format(n_bucket, big.mark = ",")),
                  y = additive, group = 1),
              linetype = "dashed", linewidth = 0.5, color = "grey45") +
    # 2 SGPc reference line
    geom_hline(yintercept = 2, linetype = "dotted", color = ZISSOU1_BASE[5], linewidth = 0.5) +
    annotate("text", x = 5.3, y = 2.1, label = "2 SGPc", color = ZISSOU1_BASE[5],
             size = 3, hjust = 1, fontface = "italic") +
    # NAEP zone
    annotate("rect", xmin = 1.5, xmax = 2.5, ymin = -Inf, ymax = Inf,
             fill = alpha(ZISSOU1_BASE[3], 0.1)) +
    annotate("text", x = 2, y = max(df_combined$additive) * 0.95,
             label = "NAEP\nrange", color = ZISSOU1_BASE[3],
             size = 2.8, fontface = "italic") +
    # Scales
    scale_fill_manual(values = c("Error 1: Sampling" = ZISSOU1_BASE[4],
                                  "Error 2: Bridge/Inference" = ZISSOU1_BASE[1]),
                       name = NULL) +
    labs(
      title = "Error Decomposition: Bridge Cost + Sampling Cost",
      subtitle = paste0(
        "How does total inference error partition between model choices and sample size?\n",
        sprintf("Bridge cost (Phase A): %.2f SGPc | Diamonds = RSS combined | Circles = additive envelope",
                bridge_cost)
      ),
      x = "Sample Size (N)",
      y = "Median Absolute Error (SGPc points)"
    ) +
    theme_publication() +
    theme(legend.position = "top")

  save_plot_multi(p_k2, "panel_k2_error_decomposition", enhanced_dir, width = 10, height = 7)
  cat("generated.\n")
} else {
  cat("skipped.\n")
}


############################################################################
###
### D*. Revised Panel D: Precision vs N with NAEP/TIMSS Zones
###
############################################################################

cat("D* (revised): Precision vs N with NAEP/TIMSS zones... ")
if (exists("phase_b_precision") && nrow(phase_b_precision) > 0) {

  # Reference zone colours — chosen to be clearly distinct from the Zissou1
  # teal (#3B9AB2) and amber (#E1AF00) used for the District / Cluster data
  # lines and IQR ribbons.
  D_NAEP_COLOR  <- "#B5654A"   # dusty terracotta  (warm, reddish-brown)
  D_TIMSS_COLOR <- "#4E8B62"   # muted sage green  (cool, earthy)

  # Aggregate by pool_type and n_bucket
  prec_agg <- phase_b_precision[, .(
    median_mae = mean(median_mae, na.rm = TRUE),
    mae_q25    = quantile(median_mae, 0.25, na.rm = TRUE),
    mae_q75    = quantile(median_mae, 0.75, na.rm = TRUE),
    mae_q10    = quantile(median_mae, 0.10, na.rm = TRUE),
    mae_q90    = quantile(median_mae, 0.90, na.rm = TRUE),
    ci_width   = mean(median_ci_width_95, na.rm = TRUE),
    ci_q25     = quantile(median_ci_width_95, 0.25, na.rm = TRUE),
    ci_q75     = quantile(median_ci_width_95, 0.75, na.rm = TRUE),
    n_pools    = .N
  ), by = .(n_bucket, pool_type)]
  prec_agg[, pool_type := fifelse(grepl("cluster", pool_type, ignore.case = TRUE), "Cluster", "District")]

  # y positions for zone labels (just below the top of each panel)
  mae_label_y <- max(prec_agg$mae_q90, na.rm = TRUE) * 0.95
  ci_label_y  <- max(prec_agg$ci_q75,  na.rm = TRUE) * 0.95

  # --- Left panel: MAE ---
  p_mae <- ggplot(prec_agg, aes(x = n_bucket, y = median_mae, color = pool_type)) +
    # NAEP zone — terracotta background
    annotate("rect", xmin = 3000, xmax = 4000, ymin = -Inf, ymax = Inf,
             fill = alpha(D_NAEP_COLOR, 0.12)) +
    annotate("text", x = 3500, y = mae_label_y,
             label = "NAEP", color = D_NAEP_COLOR, size = 3, fontface = "bold") +
    # TIMSS zone — sage-green background
    # xmax = 8,000: above the cross-country mean (~6,600) but below the largest
    # national samplers (e.g. Australia ~10,000); covers the bulk of the 45
    # grade-8 systems.  Design minimum = 4,000 per country.
    annotate("rect", xmin = 4000, xmax = 8000, ymin = -Inf, ymax = Inf,
             fill = alpha(D_TIMSS_COLOR, 0.10)) +
    annotate("text", x = 6000, y = mae_label_y,
             label = "TIMSS", color = D_TIMSS_COLOR, size = 3, fontface = "bold") +
    # IQR ribbon
    geom_ribbon(aes(ymin = mae_q25, ymax = mae_q75, fill = pool_type),
                alpha = 0.15, color = NA) +
    # 90% ribbon
    geom_ribbon(aes(ymin = mae_q10, ymax = mae_q90, fill = pool_type),
                alpha = 0.07, color = NA) +
    # Line + points
    geom_line(linewidth = 0.9) +
    geom_point(size = 2.5) +
    # 2 SGPc reference
    geom_hline(yintercept = 2, linetype = "dashed", color = "grey60", linewidth = 0.4) +
    scale_color_manual(values = c("District" = ZISSOU1_BASE[1],
                                   "Cluster" = ZISSOU1_BASE[4]),
                        name = "Pool Type") +
    scale_fill_manual(values = c("District" = ZISSOU1_BASE[1],
                                  "Cluster" = ZISSOU1_BASE[4]),
                       guide = "none") +
    scale_x_continuous(labels = scales::comma, breaks = c(1000, 2500, 5000, 7500, 10000)) +
    labs(title = "Accuracy: Median Absolute Error by Sample Size",
         subtitle = "How close is the cross-sectional inference to the longitudinal ground truth?\nIQR (dark band) and 10th\u201390th percentile (light band) across pools",
         x = "Sample Size (N)", y = "Accuracy — Median Absolute Error (SGPc)") +
    theme_publication(base_size = 9) +
    theme(legend.position = c(0.83, 0.82))

  # --- Right panel: CI width ---
  p_ci <- ggplot(prec_agg, aes(x = n_bucket, y = ci_width, color = pool_type)) +
    # NAEP zone — same terracotta
    annotate("rect", xmin = 3000, xmax = 4000, ymin = -Inf, ymax = Inf,
             fill = alpha(D_NAEP_COLOR, 0.12)) +
    annotate("text", x = 3500, y = ci_label_y,
             label = "NAEP", color = D_NAEP_COLOR, size = 3, fontface = "bold") +
    # TIMSS zone — same sage-green
    annotate("rect", xmin = 4000, xmax = 8000, ymin = -Inf, ymax = Inf,
             fill = alpha(D_TIMSS_COLOR, 0.10)) +
    annotate("text", x = 6000, y = ci_label_y,
             label = "TIMSS", color = D_TIMSS_COLOR, size = 3, fontface = "bold") +
    geom_ribbon(aes(ymin = ci_q25, ymax = ci_q75, fill = pool_type),
                alpha = 0.15, color = NA) +
    geom_line(linewidth = 0.9) +
    geom_point(size = 2.5) +
    scale_color_manual(values = c("District" = ZISSOU1_BASE[1],
                                   "Cluster" = ZISSOU1_BASE[4]),
                        name = "Pool Type") +
    scale_fill_manual(values = c("District" = ZISSOU1_BASE[1],
                                  "Cluster" = ZISSOU1_BASE[4]),
                       guide = "none") +
    scale_x_continuous(labels = scales::comma, breaks = c(1000, 2500, 5000, 7500, 10000)) +
    labs(title = "Precision: Bootstrap 95% CI Width by Sample Size",
         subtitle = "How repeatable is the estimate across independent cross-sectional draws?\nIQR across pools; shaded zones mark NAEP and TIMSS sample-size ranges",
         x = "Sample Size (N)", y = "Precision — Bootstrap 95% CI Width (SGPc)") +
    theme_publication(base_size = 9) +
    theme(legend.position = c(0.83, 0.82))

  p_d_rev <- p_mae | p_ci
  p_d_rev <- p_d_rev + plot_annotation(
    title = "Recovery Accuracy and Precision vs Sample Size",
    subtitle = paste0(
      "Left: accuracy (how close to truth \u2014 MAE); ",
      "Right: precision (how consistent across samples \u2014 95% CI width).\n",
      "Error 1 (sampling) drives both curves upward as N falls; ",
      "shaded zones mark operational N ranges for NAEP and TIMSS."
    ),
    theme = theme(plot.title = element_text(face = "bold", size = 14),
                  plot.subtitle = element_text(size = 11, color = "grey30"))
  )

  save_plot_multi(p_d_rev, "panel_d_revised_precision_vs_n", enhanced_dir, width = 14, height = 7)
  cat("generated.\n")
} else {
  cat("skipped.\n")
}


############################################################################
###
### K3a. Transition Kernel — Three-Slice Conditional Quantile Curves
###      (fixed: geom_step, thinner lines, correct legend labels)
###
############################################################################

cat("K3a: Transition Kernel (slice curves)... ")
if (file.exists(quantile_slices_csv)) {
  qs <- fread(quantile_slices_csv)

  slice_info <- unique(qs[, .(slice, u)])[order(u)]

  # Reduce to transition points only: keep rows where Q0 changes value.
  # The exported data is a step function on a dense p-grid; retaining every
  # row causes geom_step to draw correct risers but geom_line to produce the
  # dense vertical-bar artefact visible in the uploaded image.
  qs_steps <- qs[, .SD[c(1L, which(diff(Q0) != 0) + 1L)], by = slice]

  p_k3a <- ggplot(qs_steps, aes(x = p, y = Q0,
                                  color = factor(round(u, 3)),
                                  group = slice)) +
    # Identity reference  (p = v: "no kernel effect")
    geom_abline(intercept = 0, slope = 1, linetype = "dashed",
                color = "grey50", linewidth = 0.45) +
    # geom_step is the geometrically correct choice for a discrete-grid
    # inverse CDF; it draws a horizontal tread then a vertical riser at
    # each step, rather than interpolating diagonally between grid nodes.
    geom_step(linewidth = 0.35, alpha = 0.90, direction = "hv") +
    scale_color_manual(
      values = ZISSOU1_RAMP(nrow(slice_info)),
      # Labels as prior quantile values (not percentages) per user request
      labels = sprintf("%.2f", slice_info$u),
      name = "Prior Quantile u"
    ) +
    coord_cartesian(xlim = c(0, 1), ylim = c(0, 1)) +
    labs(
      title = expression(paste("Transition Kernel: Conditional Quantile Curves ",
                               Q[0](p~"|"~u))),
      subtitle = paste0(
        "How does the copula kernel map latent growth quantile (p) to current quantile (v)?\n",
        "Dashed = identity (p = v); curves show copula-mediated regression to the mean"
      ),
      x = "Latent Growth Quantile p  (= SGPc / 100)",
      y = "Current Reference Quantile v"
    ) +
    theme_publication() +
    theme(legend.position = c(0.16, 0.76))

  save_plot_multi(p_k3a, "panel_k3a_kernel_slices", enhanced_dir, width = 9, height = 8)
  cat("generated.\n")
} else {
  cat("skipped (no quantile slices data).\n")
}


############################################################################
###
### K3b. Transition Kernel — Full 2D Surface
###
### Computes F_0(v|u) = ∂C_0(u,v)/∂u analytically from the Phase A
### baseline t-copula (rho = 0.88, df = 19) on a dense (u, v) grid.
### Overlays iso-growth contour lines at Q_0(p|u) for p in
### {0.10, 0.25, 0.50, 0.75, 0.90} — these are the curves along which
### every student arrives at the same current quantile v regardless of
### prior standing u.  The TAMP diagonal (V = U) is shown for reference.
###
############################################################################

cat("K3b: Transition Kernel (full surface)... ")
{
  # Copula parameters from phase_a_manifest.json (Phase A baseline condition)
  K3B_RHO <- 0.88
  K3B_DF  <- 19L

  # Analytical conditional CDF of a t-copula:
  #   F_0(v | u) = t_{df+1}(
  #       [ t_df^{-1}(v)  -  rho * t_df^{-1}(u) ]
  #       / sqrt( (1 - rho^2) * (df + t_df^{-1}(u)^2) / (df + 1) )
  #   )
  cond_cdf_t <- function(v, u, rho = K3B_RHO, df = K3B_DF) {
    u_q   <- qt(pmax(pmin(u, 1 - 1e-9), 1e-9), df = df)
    v_q   <- qt(pmax(pmin(v, 1 - 1e-9), 1e-9), df = df)
    denom <- sqrt((1 - rho^2) * (df + u_q^2) / (df + 1))
    pt((v_q - rho * u_q) / denom, df = df + 1)
  }

  # Inverse: Q_0(p | u) — used for iso-growth contour lines
  cond_quant_t <- function(p, u, rho = K3B_RHO, df = K3B_DF) {
    u_q   <- qt(pmax(pmin(u, 1 - 1e-9), 1e-9), df = df)
    t_q   <- qt(pmax(pmin(p, 1 - 1e-9), 1e-9), df = df + 1)
    denom <- sqrt((1 - rho^2) * (df + u_q^2) / (df + 1))
    v_q   <- t_q * denom + rho * u_q
    pt(v_q, df = df)
  }

  # ---- Surface grid: F_0(v|u) on 101 x 101 points ----
  surf_n  <- 101L
  u_seq   <- seq(0.01, 0.99, length.out = surf_n)
  v_seq   <- seq(0.01, 0.99, length.out = surf_n)
  surf_grid <- CJ(u = u_seq, v = v_seq)   # data.table cross-join
  surf_grid[, F0 := cond_cdf_t(v, u)]

  # ---- Iso-growth contour lines: Q_0(p|u) for 5 p levels ----
  iso_p   <- c(0.10, 0.25, 0.50, 0.75, 0.90)
  iso_n   <- 201L
  u_iso   <- seq(0.01, 0.99, length.out = iso_n)
  iso_list <- lapply(iso_p, function(p_val) {
    data.frame(
      u       = u_iso,
      v       = cond_quant_t(p_val, u_iso),
      p_label = sprintf("p = %.2f", p_val)
    )
  })
  iso_df <- do.call(rbind, iso_list)
  iso_df$p_label <- factor(iso_df$p_label,
                            levels = sprintf("p = %.2f", sort(iso_p)))

  # Iso-growth line colours: same Zissou1 ramp used in K3a
  iso_colors <- setNames(ZISSOU1_RAMP(length(iso_p)),
                          sprintf("p = %.2f", sort(iso_p)))

  # ---- Build the surface plot ----
  p_k3b <- ggplot() +
    # Heatmap: F_0(v|u) — the conditional CDF surface
    geom_tile(data = surf_grid,
              aes(x = u, y = v, fill = F0)) +
    # Colour scale: diverging through 0.5 so the conditional median
    # (F_0 = 0.5) falls on the neutral midpoint; the two arms show
    # where the kernel assigns mass above/below the conditional median.
    scale_fill_gradientn(
      colors = c(ZISSOU1_BASE[5], "white", ZISSOU1_BASE[1]),
      values = c(0, 0.5, 1),
      limits = c(0, 1),
      name   = expression(F[0](v~"|"~u)),
      guide  = guide_colorbar(barheight = 10, barwidth = 0.8)
    ) +
    # TAMP reference: under comonotonicity V = U (rank preservation)
    geom_abline(intercept = 0, slope = 1,
                linetype = "dashed", color = "grey25",
                linewidth = 0.55) +
    annotate("text", x = 0.88, y = 0.82,
             label = "TAMP\n(V = U)",
             color = "grey25", size = 3, fontface = "italic",
             angle = 45, vjust = 0) +
    # Iso-growth contour lines: Q_0(p|u)
    # Each line traces the path of students with a fixed latent growth
    # quantile p across all prior standings u.
    geom_line(data = iso_df,
              aes(x = u, y = v, color = p_label, group = p_label),
              linewidth = 0.70, alpha = 0.90) +
    scale_color_manual(values = iso_colors,
                        name   = "Iso-growth\ncontour  Q\u2080(p|u)") +
    coord_cartesian(xlim = c(0, 1), ylim = c(0, 1), expand = FALSE) +
    labs(
      title    = expression(paste("Transition Kernel Surface: ", F[0](v~"|"~u))),
      subtitle = paste0(
        "Heatmap = conditional CDF of the t-copula kernel; red = low, white = 0.5, teal = high.\n",
        "Coloured lines = iso-growth contours Q\u2080(p|u): students with the same latent growth",
        " quantile p\n",
        "arrive at the same current quantile v.  Dashed line = TAMP comonotonic reference (V = U)."
      ),
      x = "Prior Reference Quantile  u",
      y = "Current Reference Quantile  v"
    ) +
    theme_publication() +
    theme(legend.position = "right",
          panel.border     = element_rect(fill = NA, color = "grey60"))

  save_plot_multi(p_k3b, "panel_k3b_kernel_surface", enhanced_dir, width = 10, height = 9)
  cat("generated.\n")
}


############################################################################
###
### K4. Precision Operating Heatmap: (year_span x N_bucket)
###
############################################################################

cat("K4: Precision Operating Heatmap... ")
if (exists("phase_b_precision") && nrow(phase_b_precision) > 0 &&
    "span" %in% names(phase_b_precision)) {

  # Aggregate by (span, n_bucket)
  heat_dt <- phase_b_precision[, .(
    median_mae     = round(mean(median_mae, na.rm = TRUE), 2),
    ci_width_95    = round(mean(median_ci_width_95, na.rm = TRUE), 2),
    n_pools        = .N
  ), by = .(span, n_bucket)]

  heat_dt[, span_label := paste0(span, "-yr")]
  heat_dt[, n_label := format(n_bucket, big.mark = ",")]

  # Determine ordering
  heat_dt[, span_label := factor(span_label, levels = sort(unique(span_label)))]
  heat_dt[, n_label := factor(n_label,
                                levels = format(sort(unique(n_bucket)), big.mark = ","))]

  # Sequential single-hue scale: all values are in the excellent range.
  # Light teal = lowest error (best precision); deep teal = highest error
  # (still operationally acceptable).  A diverging alarm palette would
  # misrepresent the finding — the entire table is in the "good" register.
  K4_SCALE_COLORS <- colorRampPalette(c("#D6EEF5", ZISSOU1_BASE[1], "#1A5B72"))(100)

  # Text contrast: dark grey is legible on both the light and dark ends of
  # the sequential scale, whereas white would vanish on the lightest tiles.
  K4_TEXT_COLOR <- "grey15"

  # Top panel — ACCURACY: how close is the inferred estimate to the truth?
  # Median MAE = E[|inferred median SGPc - true median SGPc|].
  # This answers: "Is the method getting the right answer on average?"
  p_k4_mae <- ggplot(heat_dt, aes(x = n_label, y = span_label, fill = median_mae)) +
    geom_tile(color = "white", linewidth = 0.8) +
    geom_text(aes(label = sprintf("%.2f", median_mae)),
              color = K4_TEXT_COLOR, fontface = "bold", size = 4) +
    scale_fill_gradientn(
      colors = K4_SCALE_COLORS,
      name = "Median MAE\n(SGPc)",
      limits = c(0, NA)
    ) +
    labs(
      title = "Accuracy: Median Absolute Error (inferred vs true median SGPc)",
      subtitle = paste0(
        "How close is the cross-sectional inference to the longitudinal ground truth?\n",
        "All cells are operationally excellent; lighter = closer to truth."
      ),
      x = "Sample Size (N)", y = "Year Span"
    ) +
    theme_publication() +
    theme(panel.grid = element_blank(),
          axis.text.x = element_text(angle = 0))

  # Bottom panel — PRECISION: how consistent is the estimate across repeated samples?
  # 95% CI width = bootstrap confidence interval width for the median SGPc estimate.
  # This answers: "If we drew a new sample, how stable would our estimate be?"
  p_k4_ci <- ggplot(heat_dt, aes(x = n_label, y = span_label, fill = ci_width_95)) +
    geom_tile(color = "white", linewidth = 0.8) +
    geom_text(aes(label = sprintf("%.2f", ci_width_95)),
              color = K4_TEXT_COLOR, fontface = "bold", size = 4) +
    scale_fill_gradientn(
      colors = K4_SCALE_COLORS,
      name = "95% CI Width\n(SGPc)",
      limits = c(0, NA)
    ) +
    labs(
      title = "Precision: Bootstrap 95% CI Width for inferred median SGPc",
      subtitle = paste0(
        "How repeatable is the estimate across independent cross-sectional draws of the same subgroup?\n",
        "Narrower CI = higher precision; lighter = more consistent estimates across resamples."
      ),
      x = "Sample Size (N)", y = "Year Span"
    ) +
    theme_publication() +
    theme(panel.grid = element_blank(),
          axis.text.x = element_text(angle = 0))

  p_k4 <- p_k4_mae / p_k4_ci
  p_k4 <- p_k4 + plot_annotation(
    title = "Recovery Accuracy and Precision Operating Heatmaps",
    subtitle = paste0(
      "Top: accuracy (how close to truth); Bottom: precision (how consistent across samples).\n",
      "Single-hue scale throughout \u2014 gradient encodes relative degree only,",
      " not a pass/fail threshold; all cells are operationally acceptable."
    ),
    theme = theme(plot.title = element_text(face = "bold", size = 14),
                  plot.subtitle = element_text(size = 11, color = "grey30"))
  )

  save_plot_multi(p_k4, "panel_k4_precision_heatmap", enhanced_dir, width = 10, height = 10)
  cat("generated.\n")
} else {
  cat("skipped (no span column or no precision data).\n")
}


############################################################################
###
### J*. Revised Panel J: Sensitivity with Density Overlays
###
############################################################################

cat("J* (revised): Sensitivity Summary with density overlays... ")
if (exists("phase_b_copula") && nrow(phase_b_copula) > 0) {

  # --- Left panel: Copula parameter sensitivity ---
  cop_mean  <- round(mean(phase_b_copula$delta_median_vs_base, na.rm = TRUE), 2)
  cop_sd    <- round(sd(phase_b_copula$delta_median_vs_base, na.rm = TRUE), 2)
  cop_amean <- round(mean(abs(phase_b_copula$delta_median_vs_base), na.rm = TRUE), 2)
  n_cop     <- nrow(phase_b_copula)

  p_j1 <- ggplot(phase_b_copula, aes(x = delta_median_vs_base)) +
    geom_histogram(aes(y = after_stat(density)),
                   bins = 15, fill = alpha(STEP3_COLORS$predicted, 0.3),
                   color = STEP3_COLORS$predicted, linewidth = 0.4) +
    geom_density(color = STEP3_COLORS$predicted, linewidth = 0.9) +
    # Mean and ±1 SD bands
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey50", linewidth = 0.5) +
    geom_vline(xintercept = cop_mean, linetype = "solid", color = STEP3_COLORS$predicted, linewidth = 0.7) +
    geom_vline(xintercept = cop_mean + cop_sd, linetype = "dotted", color = STEP3_COLORS$predicted, linewidth = 0.5) +
    geom_vline(xintercept = cop_mean - cop_sd, linetype = "dotted", color = STEP3_COLORS$predicted, linewidth = 0.5) +
    # Rug plot for individual observations
    geom_rug(sides = "b", color = STEP3_COLORS$predicted, alpha = 0.6, linewidth = 0.5) +
    # Annotation
    annotate("text", x = Inf, y = Inf,
             label = sprintf("n = %d\nmean = %.2f\nSD = %.2f\nmean|delta| = %.2f",
                             n_cop, cop_mean, cop_sd, cop_amean),
             hjust = 1.1, vjust = 1.3, size = 3, color = "grey30", fontface = "italic") +
    labs(
      title = "Copula Parameter Sensitivity",
      subtitle = "How sensitive is median SGPc to plausible copula-parameter shifts?\nSolid = mean; dotted = \u00b11 SD",
      x = expression(Delta ~ "median SGPc vs baseline"),
      y = "Density"
    ) +
    theme_publication(base_size = 9)

  # --- Right panel: Independence stratification sensitivity ---
  ind_mean  <- round(mean(phase_b_indep$delta_median, na.rm = TRUE), 2)
  ind_sd    <- round(sd(phase_b_indep$delta_median, na.rm = TRUE), 2)
  ind_amean <- round(mean(abs(phase_b_indep$delta_median), na.rm = TRUE), 2)
  n_ind     <- nrow(phase_b_indep)
  n_k3_changed <- sum(phase_b_indep$k3_changed, na.rm = TRUE)

  p_j2 <- ggplot(phase_b_indep, aes(x = delta_median)) +
    geom_histogram(aes(y = after_stat(density)),
                   bins = 15, fill = alpha(STEP3_COLORS$actual, 0.3),
                   color = STEP3_COLORS$actual, linewidth = 0.4) +
    geom_density(color = STEP3_COLORS$actual, linewidth = 0.9) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey50", linewidth = 0.5) +
    geom_vline(xintercept = ind_mean, linetype = "solid", color = STEP3_COLORS$actual, linewidth = 0.7) +
    geom_vline(xintercept = ind_mean + ind_sd, linetype = "dotted", color = STEP3_COLORS$actual, linewidth = 0.5) +
    geom_vline(xintercept = ind_mean - ind_sd, linetype = "dotted", color = STEP3_COLORS$actual, linewidth = 0.5) +
    geom_rug(sides = "b", color = STEP3_COLORS$actual, alpha = 0.6, linewidth = 0.5) +
    # Mark bucket-change cases
    geom_rug(data = phase_b_indep[k3_changed == TRUE],
             aes(x = delta_median), sides = "b",
             color = ZISSOU1_BASE[5], alpha = 0.9, linewidth = 1.0) +
    annotate("text", x = Inf, y = Inf,
             label = sprintf("n = %d\nmean = %.2f\nSD = %.2f\nmean|delta| = %.2f\nbucket changed: %d/%d",
                             n_ind, ind_mean, ind_sd, ind_amean, n_k3_changed, n_ind),
             hjust = 1.1, vjust = 1.3, size = 3, color = "grey30", fontface = "italic") +
    labs(
      title = "Independence Stratification Sensitivity",
      subtitle = paste0(
        "How much does relaxing P\u209b \u22a5 U shift subgroup estimates?\n",
        "Red rug marks = subgroups where K3 bucket assignment changed"
      ),
      x = expression(Delta ~ "median SGPc (stratified - pooled)"),
      y = "Density"
    ) +
    theme_publication(base_size = 9)

  p_j_rev <- p_j1 | p_j2
  p_j_rev <- p_j_rev + plot_annotation(
    title = "Sensitivity Summary: Model Assumption Stress Tests",
    subtitle = "Are STEP 3 subgroup estimates robust to copula-parameter and independence-assumption perturbations?",
    theme = theme(plot.title = element_text(face = "bold", size = 14),
                  plot.subtitle = element_text(size = 11, color = "grey30"))
  )

  save_plot_multi(p_j_rev, "panel_j_revised_sensitivity", enhanced_dir, width = 14, height = 7)
  cat("generated.\n")
} else {
  cat("skipped.\n")
}


############################################################################
###
### H*. Revised Panel H: Visual Scorecard
###
############################################################################

cat("H* (revised): Visual Scorecard... ")
if (exists("dsg") && nrow(dsg) > 0) {

  row <- dsg[1]

  # Build metric data frame for visual encoding
  metrics <- data.frame(
    metric = c("Mean SGPc\n(Inf / True)",
               "Median SGPc\n(Inf / True)",
               "W1 Reduction\nvs Uniform",
               "Max |Residual|",
               "95% CI Width",
               "Bootstrap\nConvergence",
               "K3 Bucket\nConsistency"),
    value = c(
      row$mean_sgpc_inferred,
      row$median_sgpc_inferred,
      row$w1_reduction_pct,
      row$max_abs_residual * 100,  # scale to percentage
      row$ci95_width,
      ifelse(is.na(row$bootstrap_n), NA_real_,
             row$bootstrap_converged / row$bootstrap_n * 100),
      row$k3_consistency * 100
    ),
    reference = c(
      row$mean_sgpc_true,
      row$median_sgpc_true,
      70,      # 70% reduction is "good"
      1,       # 1% max residual
      10,      # 10 SGPc CI width
      90,      # 90% convergence
      70       # 70% consistency
    ),
    display = c(
      sprintf("%.1f / %.1f", row$mean_sgpc_inferred, row$mean_sgpc_true),
      sprintf("%.1f / %.1f", row$median_sgpc_inferred, row$median_sgpc_true),
      sprintf("%.1f%%", row$w1_reduction_pct),
      sprintf("%.4f", row$max_abs_residual),
      sprintf("%.1f", row$ci95_width),
      sprintf("%d / %d", row$bootstrap_converged, row$bootstrap_n),
      sprintf("%.1f%%", row$k3_consistency * 100)
    ),
    stringsAsFactors = FALSE
  )

  # Traffic light: green/yellow/red
  metrics$status <- c(
    ifelse(abs(row$mean_sgpc_inferred - row$mean_sgpc_true) < 2, "good",
           ifelse(abs(row$mean_sgpc_inferred - row$mean_sgpc_true) < 5, "warn", "bad")),
    ifelse(abs(row$median_sgpc_inferred - row$median_sgpc_true) < 2, "good",
           ifelse(abs(row$median_sgpc_inferred - row$median_sgpc_true) < 5, "warn", "bad")),
    ifelse(row$w1_reduction_pct > 70, "good",
           ifelse(row$w1_reduction_pct > 40, "warn", "bad")),
    ifelse(row$max_abs_residual < 0.02, "good",
           ifelse(row$max_abs_residual < 0.05, "warn", "bad")),
    ifelse(row$ci95_width < 10, "good",
           ifelse(row$ci95_width < 15, "warn", "bad")),
    ifelse(!is.na(row$bootstrap_converged) &&
             row$bootstrap_converged / row$bootstrap_n > 0.90, "good",
           ifelse(!is.na(row$bootstrap_converged) &&
                    row$bootstrap_converged / row$bootstrap_n > 0.80, "warn", "bad")),
    ifelse(row$k3_consistency > 0.70, "good",
           ifelse(row$k3_consistency > 0.50, "warn", "bad"))
  )

  status_colors <- c("good" = "#4CAF50", "warn" = ZISSOU1_BASE[4], "bad" = ZISSOU1_BASE[5])
  metrics$metric <- factor(metrics$metric, levels = rev(metrics$metric))

  # Build the condition label
  cond_label <- if (exists("format_step3_condition_label")) {
    format_step3_condition_label(row$condition_id, row$subgroup_col, row$subgroup_value, "H.")
  } else {
    paste0("H. ", row$condition_id, " — ", row$subgroup_value)
  }

  p_h_rev <- ggplot(metrics, aes(y = metric)) +
    # Status indicator tiles
    geom_tile(aes(x = 0.5, fill = status), width = 0.3, height = 0.8) +
    # Value labels
    geom_text(aes(x = 1.2, label = display), hjust = 0, size = 3.8, fontface = "bold") +
    # Overall health indicator
    annotate("label", x = 2.5, y = 4,
             label = toupper(row$health),
             fill = status_colors[row$health],
             color = "white", fontface = "bold", size = 6,
             label.padding = unit(0.6, "lines"),
             label.r = unit(0.3, "lines")) +
    annotate("text", x = 2.5, y = 3,
             label = sprintf("n = %s | %s\n%s",
                             format(row$n_subgroup, big.mark = ","),
                             row$regime_family,
                             row$k3_assigned),
             size = 3, color = "grey40") +
    # Flags
    annotate("text", x = 2.5, y = 1.5,
             label = paste0("Flags: ", gsub("\\|", ", ", row$quality_flags)),
             size = 2.8, color = "grey50", fontface = "italic") +
    scale_fill_manual(values = status_colors, guide = "none") +
    scale_x_continuous(limits = c(0, 3.5)) +
    labs(
      title = cond_label,
      subtitle = "Does this subgroup meet minimum quality thresholds for reporting inferred growth regime?",
      x = NULL, y = NULL
    ) +
    theme_publication() +
    theme(panel.grid = element_blank(),
          axis.text.x = element_blank(),
          axis.ticks = element_blank(),
          panel.border = element_blank())

  save_plot_multi(p_h_rev, "panel_h_revised_scorecard", enhanced_dir, width = 10, height = 7)
  cat("generated.\n")
} else {
  cat("skipped.\n")
}


############################################################################
###
### K5. Pool-Type Comparison Panel
###
############################################################################

cat("K5: Pool-Type Comparison... ")
if (exists("phase_b_precision") && nrow(phase_b_precision) > 0) {

  prec_pt <- copy(phase_b_precision)
  prec_pt[, pool_type := fifelse(grepl("cluster", pool_type, ignore.case = TRUE),
                                   "Cluster", "District")]

  # Compute summary by pool_type and n_bucket
  pt_summary <- prec_pt[, .(
    median_mae   = mean(median_mae, na.rm = TRUE),
    median_bias  = mean(median_bias, na.rm = TRUE),
    ci_width     = mean(median_ci_width_95, na.rm = TRUE),
    n_pools      = .N
  ), by = .(pool_type, n_bucket)]

  # Faceted comparison: MAE by pool type
  p_k5 <- ggplot(prec_pt, aes(x = factor(format(n_bucket, big.mark = ",")),
                                 y = median_mae, fill = pool_type)) +
    geom_boxplot(outlier.size = 1, alpha = 0.6, width = 0.6,
                 position = position_dodge(width = 0.7)) +
    geom_hline(yintercept = 2, linetype = "dashed", color = "grey60", linewidth = 0.4) +
    scale_fill_manual(values = c("District" = ZISSOU1_BASE[1],
                                  "Cluster" = ZISSOU1_BASE[4]),
                       name = "Pool Type") +
    labs(
      title = "Pool-Type Comparison: District vs Growth-Stratified Cluster Pools",
      subtitle = paste0(
        "Do growth-stratified cluster pools show systematically different precision?\n",
        "Boxplots show MAE distribution across pools within each (type \u00d7 N) cell"
      ),
      x = "Sample Size (N)",
      y = "Median MAE (SGPc)"
    ) +
    theme_publication() +
    theme(legend.position = "top")

  save_plot_multi(p_k5, "panel_k5_pool_type_comparison", enhanced_dir, width = 10, height = 7)
  cat("generated.\n")
} else {
  cat("skipped.\n")
}


############################################################################
###
### K6. Bias Direction Panel
###
############################################################################

cat("K6: Bias Direction Panel... ")
if (exists("phase_b_precision") && nrow(phase_b_precision) > 0) {

  prec_bias <- copy(phase_b_precision)
  prec_bias[, pool_type := fifelse(grepl("cluster", pool_type, ignore.case = TRUE),
                                     "Cluster", "District")]

  # Extract cluster stratum from pool_id
  prec_bias[, stratum := fifelse(
    grepl("CLUSTER_LOW", pool_id), "Low Growth",
    fifelse(grepl("CLUSTER_TYPICAL", pool_id), "Typical Growth",
            fifelse(grepl("CLUSTER_HIGH", pool_id), "High Growth", "District"))
  )]
  prec_bias[, stratum := factor(stratum, levels = c("Low Growth", "Typical Growth",
                                                      "High Growth", "District"))]

  p_k6 <- ggplot(prec_bias, aes(x = factor(format(n_bucket, big.mark = ",")),
                                   y = median_bias, color = stratum)) +
    geom_hline(yintercept = 0, linetype = "solid", color = "grey60", linewidth = 0.5) +
    geom_hline(yintercept = c(-2, 2), linetype = "dashed", color = "grey75", linewidth = 0.3) +
    geom_jitter(width = 0.15, size = 2, alpha = 0.7) +
    # Summary points (mean bias per stratum x N)
    stat_summary(fun = mean, geom = "point", size = 4, shape = 18,
                 position = position_dodge(width = 0.3)) +
    stat_summary(fun = mean, geom = "line", aes(group = stratum),
                 linewidth = 0.7, alpha = 0.5,
                 position = position_dodge(width = 0.3)) +
    scale_color_manual(
      values = c("Low Growth" = ZISSOU1_BASE[5],
                 "Typical Growth" = ZISSOU1_BASE[3],
                 "High Growth" = ZISSOU1_BASE[1],
                 "District" = "grey40"),
      name = "Pool Stratum"
    ) +
    labs(
      title = "Bias Direction by Pool Stratum and Sample Size",
      subtitle = paste0(
        "Does the method systematically over- or under-estimate growth for specific subgroups?\n",
        "Diamonds = mean bias per stratum; jitter = individual pool \u00d7 N cells"
      ),
      x = "Sample Size (N)",
      y = "Median Bias (SGPc points; negative = under-estimate)"
    ) +
    theme_publication() +
    theme(legend.position = c(0.85, 0.20))

  save_plot_multi(p_k6, "panel_k6_bias_direction", enhanced_dir, width = 10, height = 7)
  cat("generated.\n")
} else {
  cat("skipped.\n")
}


############################################################################
###
### E*. Revised Panel E: Recovery by Span with Content Area Facets
###
############################################################################

cat("E* (revised): Recovery by Span — median and mean sub-panels... ")
if (exists("phase_b") && nrow(phase_b) > 0 && "year_span" %in% names(phase_b)) {

  pb_e <- copy(phase_b)
  pb_e[, pool_type   := fifelse(grepl("CLUSTER", subgroup_id), "Cluster", "District")]
  pb_e[, span_label  := factor(paste0(year_span, "-yr"))]
  # Absolute errors for both summarising statistics
  pb_e[, abs_diff_med  := abs(median_diff)]   # |inferred median − true median|
  pb_e[, abs_diff_mean := abs(mean_diff)]     # |inferred mean   − true mean  |

  # Helper: build per-span x content_area annotation table
  make_span_summary <- function(dt, col) {
    dt[, .(
      med_abs  = round(median(get(col), na.rm = TRUE), 2),
      mean_abs = round(mean(get(col),   na.rm = TRUE), 2),
      n        = .N
    ), by = .(span_label, content_area)]
  }

  sum_med  <- make_span_summary(pb_e, "abs_diff_med")
  sum_mean <- make_span_summary(pb_e, "abs_diff_mean")

  # Shared y-axis limits derived from the median column so both panels are
  # directly comparable.  coord_cartesian() is used (not scale limits) so the
  # violin density is computed on the full data before clipping.
  e_y_max  <- max(pb_e$abs_diff_med, na.rm = TRUE) * 1.08   # 8% headroom above max
  e_y_min  <- -0.55                                          # room for annotation at y = -0.35
  e_y_lims <- c(e_y_min, e_y_max)

  # Helper: shared violin + jitter + diamond scaffold
  # y_col   : string name of the column to plot on y
  # sum_dt  : pre-computed summary for annotation
  # y_label : y-axis label string
  # ttl     : sub-panel title
  # sub     : sub-panel subtitle
  # y_lims  : numeric(2) passed to coord_cartesian(ylim = ...)
  make_e_panel <- function(dt, y_col, sum_dt, y_label, ttl, sub, y_lims = NULL) {
    p <- ggplot(dt, aes(x = span_label, y = .data[[y_col]])) +
      geom_violin(fill  = alpha(STEP3_COLORS$predicted, 0.12),
                  color = STEP3_COLORS$predicted, linewidth = 0.4,
                  trim = TRUE, scale = "width") +
      geom_jitter(aes(color = pool_type, shape = pool_type),
                  width = 0.12, size = 2.2, alpha = 0.7) +
      # Diamond marks the median of the absolute-error distribution
      stat_summary(fun = median, geom = "point",
                   shape = 18, size = 4, color = "grey20") +
      geom_hline(yintercept = 2, linetype = "dashed",
                 color = "grey60", linewidth = 0.4) +
      # Bottom annotation: mean |error| (MAE) and N per cell
      geom_text(data = sum_dt,
                aes(x = span_label, y = -0.35,
                    label = sprintf("MAE=%.2f (n=%d)", mean_abs, n)),
                size = 2.8, color = "grey40", fontface = "italic",
                inherit.aes = FALSE) +
      facet_wrap(~ content_area, nrow = 1) +
      scale_color_manual(values = c("District" = ZISSOU1_BASE[1],
                                     "Cluster"  = ZISSOU1_BASE[4]),
                          name = "Pool Type") +
      scale_shape_manual(values = c("District" = 16, "Cluster" = 17),
                          name = "Pool Type") +
      labs(title    = ttl,
           subtitle = sub,
           x = "Year Span",
           y = y_label) +
      theme_publication() +
      theme(legend.position = "top")
    # Apply shared y limits if supplied
    if (!is.null(y_lims)) p <- p + coord_cartesian(ylim = y_lims)
    p
  }

  # --- Median sub-panel ---
  p_e_median <- make_e_panel(
    dt      = pb_e,
    y_col   = "abs_diff_med",
    sum_dt  = sum_med,
    y_label = "Accuracy \u2014 |Inferred \u2212 True Median SGPc|",
    ttl     = "Median-Based Recovery Accuracy by Year Span and Content Area",
    sub     = paste0(
      "y = |inferred median SGPc \u2212 true median SGPc|  ",
      "(median of the subgroup distribution)\n",
      "Diamonds = median |error| across subgroups; dashed line = 2 SGPc reference"
    ),
    y_lims  = e_y_lims
  )

  # --- Mean sub-panel ---
  p_e_mean <- make_e_panel(
    dt      = pb_e,
    y_col   = "abs_diff_mean",
    sum_dt  = sum_mean,
    y_label = "Accuracy \u2014 |Inferred \u2212 True Mean SGPc|",
    ttl     = "Mean-Based Recovery Accuracy by Year Span and Content Area",
    sub     = paste0(
      "y = |inferred mean SGPc \u2212 true mean SGPc|  ",
      "(mean has lower variance than median for small subgroups)\n",
      "Diamonds = median |error| across subgroups; dashed line = 2 SGPc reference"
    ),
    y_lims  = e_y_lims
  )

  # --- Combined stacked panel ---
  p_e_combined <- (p_e_median / p_e_mean) +
    plot_annotation(
      title    = "Recovery Accuracy by Year Span and Content Area",
      subtitle = paste0(
        "Top: median-based absolute error  |  ",
        "Bottom: mean-based absolute error.\n",
        "Mean SGPc is more stable for small subgroups; ",
        "both summaries should agree for well-behaved distributions."
      ),
      theme = theme(
        plot.title    = element_text(face = "bold", size = 14),
        plot.subtitle = element_text(size = 11, color = "grey30")
      )
    )

  save_plot_multi(p_e_median,   "panel_e_median_recovery_by_span",   enhanced_dir, width = 12, height = 7)
  save_plot_multi(p_e_mean,     "panel_e_mean_recovery_by_span",     enhanced_dir, width = 12, height = 7)
  save_plot_multi(p_e_combined, "panel_e_combined_recovery_by_span", enhanced_dir, width = 12, height = 13)
  cat("generated.\n")
} else {
  cat("skipped.\n")
}


############################################################################
### Summary
############################################################################

cat("\n=== Enhanced panels complete ===\n")
cat("Output directory:", enhanced_dir, "\n\n")

# List generated files
if (dir.exists(enhanced_dir)) {
  files <- list.files(enhanced_dir, pattern = "\\.(pdf|svg|png)$")
  cat(sprintf("Generated %d files:\n", length(files)))
  for (f in sort(unique(sub("\\.[^.]+$", "", files)))) {
    cat(sprintf("  %s (.pdf/.svg/.png)\n", f))
  }
}
