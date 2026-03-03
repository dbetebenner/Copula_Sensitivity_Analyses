############################################################################
###
### Diagnostic Plots for STEP 3: Growth Regime Inference
###
### Publication-quality ggplot2 visualisations comparing inferred growth
### regimes to ground truth (actual SGPc distributions from longitudinal
### data). Styled via step3_publication_style.R (Zissou1 palette,
### theme_publication, save_plot_multi).
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################

require(ggplot2)
require(patchwork)


#' Plot Observed vs Predicted CDF
#'
#' Upper: CDF overlay; lower: residual ribbon. Uses STEP 3 style bridge.
#'
#' @param est Result from estimate_regime()
#' @param title Character. Plot title.
#' @param output_dir Character. Directory for saved plots.
#' @param filename Character. Base filename (no extension).
#'
#' @return The combined ggplot (invisible). Side effect: files saved.
#' @export
plot_observed_vs_predicted_cdf <- function(est,
                                            title = "Observed vs Predicted CDF",
                                            output_dir = "results/visualizations",
                                            filename = "cdf_comparison") {

  base_df <- list(
    data.frame(v = est$v_grid, cdf = est$F_obs, source = "Observed"),
    data.frame(v = est$v_grid, cdf = est$F_pred, source = "Best-fit")
  )
  if (!is.null(est$F_uniform)) {
    base_df[[length(base_df) + 1]] <- data.frame(v = est$v_grid, cdf = est$F_uniform, source = "Uniform")
  }
  if (!is.null(est$F_tamp)) {
    base_df[[length(base_df) + 1]] <- data.frame(v = est$v_grid, cdf = est$F_tamp, source = "TAMP")
  }
  df <- do.call(rbind, base_df)

  residual_df <- data.frame(
    v        = est$v_grid,
    residual = est$F_pred - est$F_obs
  )

  cols <- c(
    "Observed" = STEP3_COLORS$observed,
    "Best-fit" = STEP3_COLORS$predicted,
    "Uniform" = STEP3_COLORS$reference,
    "TAMP" = STEP3_COLORS$actual
  )
  ltys <- c("Observed" = "solid", "Best-fit" = "solid", "Uniform" = "dashed", "TAMP" = "dotdash")

  regime <- est$regime
  d <- est$all_distances
  subtitle <- sprintf("Regime: %s | Mean SGPc: %.1f | Median SGPc: %.1f | W1: %.4f | CvM: %.6f",
                      regime$family, regime$mean * 100, regime$median * 100, d$wasserstein1, d$cramer_von_mises)
  if (!is.null(est$w1_uniform) && is.finite(est$w1_uniform) && est$w1_uniform > 0) {
    red_pct <- 100 * (1 - (d$wasserstein1 / est$w1_uniform))
    subtitle <- paste0(subtitle, sprintf(" | W1 reduction vs uniform: %.1f%%", red_pct))
  }

  p_upper <- ggplot(df, aes(x = v, y = cdf, color = source, linetype = source)) +
    geom_line(linewidth = 0.9) +
    scale_color_manual(values = cols[names(cols) %in% unique(df$source)]) +
    scale_linetype_manual(values = ltys[names(ltys) %in% unique(df$source)]) +
    labs(title = title, subtitle = subtitle,
         x = NULL, y = "CDF", color = NULL, linetype = NULL) +
    theme_publication() +
    theme(legend.position = c(0.85, 0.15),
          axis.text.x = element_blank())

  p_lower <- ggplot(residual_df, aes(x = v, y = residual)) +
    geom_ribbon(aes(ymin = pmin(residual, 0), ymax = pmax(residual, 0)),
                fill = STEP3_COLORS$residual_pos, alpha = 0.25) +
    geom_line(linewidth = 0.7, color = STEP3_COLORS$residual_pos) +
    geom_ref_hline(yintercept = 0) +
    geom_hline(yintercept = c(-0.02, 0.02), linetype = "dotted", color = "grey70") +
    labs(x = "v (current-grade reference percentile)",
         y = expression(F[H](v) - F[obs](v))) +
    theme_publication()

  combined <- p_upper / p_lower + plot_layout(heights = c(3, 1))

  save_plot_multi(combined, filename, output_dir, width = PLOT_WIDTH, height = PLOT_HEIGHT)

  invisible(combined)
}


#' Plot Inferred Regime Shape vs True SGPc Distribution
#'
#' Compares the estimated H_S density with the actual SGPc
#' distribution from longitudinal data.
#'
#' @param regime A growth_regime object (estimated)
#' @param true_sgpc Numeric vector of actual SGPc values (1-99 scale).
#'   If NULL, only the estimated regime is shown.
#' @param title Character. Plot title.
#' @param output_dir Character. Directory for saved plots.
#' @param filename Character. Base filename.
#'
#' @return The ggplot (invisible).
#' @export
plot_regime_shape <- function(regime, true_sgpc = NULL,
                               title = "Growth Regime: Inferred vs Actual",
                               output_dir = "results/visualizations",
                               filename = "regime_comparison",
                               bootstrap = NULL) {

  p_grid <- seq(0.01, 0.99, length.out = 200)
  inferred_d <- regime$density(p_grid)

  df_inferred <- data.frame(sgpc = p_grid * 100, density = inferred_d,
                             source = "Inferred")
  df_all <- df_inferred

  if (!is.null(true_sgpc)) {
    kd <- density(true_sgpc / 100, from = 0.01, to = 0.99, bw = "SJ", n = 200)
    df_actual <- data.frame(sgpc = kd$x * 100, density = kd$y, source = "Actual")
    df_all <- rbind(df_all, df_actual)
  }

  cols <- c("Inferred" = STEP3_COLORS$inferred, "Actual" = STEP3_COLORS$actual)

  subtitle <- if (!is.null(true_sgpc)) {
    sprintf("Mean (Inf/Act): %.1f / %.1f | Median (Inf/Act): %.1f / %.1f",
            regime$mean * 100, mean(true_sgpc),
            regime$median * 100, median(true_sgpc))
  } else {
    sprintf("Inferred mean: %.1f | Inferred median: %.1f",
            regime$mean * 100, regime$median * 100)
  }

  p <- ggplot(df_all, aes(x = sgpc, y = density, fill = source, color = source)) +
    geom_area(alpha = 0.15, position = "identity") +
    geom_line(linewidth = 0.9) +
    geom_ref_vline(xintercept = 50) +
    geom_vline(xintercept = regime$mean * 100, linetype = "dotdash",
               color = STEP3_COLORS$inferred, linewidth = 0.6) +
    geom_vline(xintercept = regime$median * 100, linetype = "dashed",
               color = STEP3_COLORS$inferred, linewidth = 0.6) +
    scale_color_manual(values = cols) +
    scale_fill_manual(values = cols) +
    labs(title = title, subtitle = subtitle,
         x = "SGPc (Conditional Growth Percentile)",
         y = "Density", color = NULL, fill = NULL) +
    coord_cartesian(xlim = c(0, 100)) +
    theme_publication() +
    theme(legend.position = c(0.88, 0.88))

  if (!is.null(true_sgpc)) {
    p <- p +
      geom_vline(xintercept = mean(true_sgpc), linetype = "dotdash",
                 color = STEP3_COLORS$actual, linewidth = 0.6) +
      geom_vline(xintercept = median(true_sgpc), linetype = "dashed",
                 color = STEP3_COLORS$actual, linewidth = 0.6)
  }

  if (!is.null(bootstrap) && !is.null(bootstrap$ci_mean_sgpc)) {
    p <- p +
      annotate("text",
               x = 2,
               y = Inf,
               hjust = 0,
               vjust = 1.6,
               size = 3,
               color = "grey35",
               label = sprintf("Bootstrap mean CI: [%.1f, %.1f]",
                               bootstrap$ci_mean_sgpc[1],
                               bootstrap$ci_mean_sgpc[2]))
  }

  save_plot_multi(p, filename, output_dir, width = PLOT_WIDTH, height = PLOT_HEIGHT)

  invisible(p)
}


#' Plot Residual Curve
#'
#' @param est Result from estimate_regime()
#' @param output_dir Character.
#' @param filename Character.
#'
#' @return The ggplot (invisible).
#' @export
plot_residual_curve <- function(est,
                                 output_dir = "results/visualizations",
                                 filename = "residual_curve",
                                 title = "CDF Residual Curve") {

  residual <- est$F_pred - est$F_obs
  df <- data.frame(v = est$v_grid, residual = residual,
                    sign = ifelse(residual >= 0, "positive", "negative"))

  p <- ggplot(df, aes(x = v, y = residual)) +
    geom_segment(aes(xend = v, y = 0, yend = residual, color = sign),
                 alpha = 0.35, linewidth = 0.3) +
    geom_line(linewidth = 0.8, color = STEP3_COLORS$residual_pos) +
    geom_ref_hline(yintercept = 0) +
    geom_hline(yintercept = c(-0.02, 0.02), linetype = "dotted", color = "grey70") +
    geom_hline(yintercept = c(-0.05, 0.05), linetype = "dotdash", color = "grey80") +
    scale_color_manual(values = c("positive" = STEP3_COLORS$residual_pos,
                                   "negative" = STEP3_COLORS$residual_neg),
                        guide = "none") +
    labs(title = title,
         x = "v (current-grade reference percentile)",
         y = expression(F[H](v) - F[obs](v))) +
    theme_publication()

  save_plot_multi(p, filename, output_dir, width = PLOT_WIDTH, height = 5)

  invisible(p)
}


#' Plot Objective Surface Over (m, log10(kappa))
#'
#' @param est Result from estimate_regime()
#' @param output_dir Character directory
#' @param filename Character base filename
#' @param title Character title
#'
#' @return The ggplot object (invisible)
#' @export
plot_objective_surface <- function(est,
                                   output_dir = "results/visualizations",
                                   filename = "objective_surface",
                                   title = "B1. Objective Landscape") {
  gs <- est$grid_search
  if (is.null(gs) || nrow(gs) == 0) {
    p <- ggplot() +
      annotate("text", x = 0.5, y = 0.5, label = "No grid search data available", size = 4) +
      theme_void()
    save_plot_multi(p, filename, output_dir, width = PLOT_WIDTH, height = PLOT_HEIGHT)
    return(invisible(p))
  }

  m_col <- if ("m" %in% names(gs)) "m" else if ("regime_param_1" %in% names(gs)) "regime_param_1" else "theta1"
  k_col <- if ("kappa" %in% names(gs)) "kappa" else if ("regime_param_2" %in% names(gs)) "regime_param_2" else "theta2"

  gs_plot <- gs[is.finite(gs$distance), ]
  if (nrow(gs_plot) == 0) {
    p <- ggplot() +
      annotate("text", x = 0.5, y = 0.5, label = "No finite objective values", size = 4) +
      theme_void()
    save_plot_multi(p, filename, output_dir, width = PLOT_WIDTH, height = PLOT_HEIGHT)
    return(invisible(p))
  }

  gs_plot$log10_kappa <- log10(as.numeric(gs_plot[[k_col]]))
  gs_plot$distance_log10 <- log10(pmax(gs_plot$distance, 1e-12))
  uniform_pt <- data.frame(m = 0.5, log10_kappa = log10(2))
  optimum_pt <- data.frame(m = est$m_hat, log10_kappa = log10(est$kappa_hat))

  p <- ggplot(gs_plot, aes(x = .data[[m_col]], y = .data[["log10_kappa"]], fill = .data[["distance_log10"]])) +
    geom_tile() +
    scale_fill_gradientn(colours = c("#FCFCF4", "#E2E4C8", "#B7BA87", "#8A9048")) +
    geom_point(data = optimum_pt, aes(x = m, y = log10_kappa), inherit.aes = FALSE,
               shape = 4, size = 3, stroke = 1.2, color = "black") +
    geom_point(data = uniform_pt, aes(x = m, y = log10_kappa), inherit.aes = FALSE,
               shape = 21, size = 2.5, stroke = 0.7, fill = "white", color = "grey30") +
    annotate("text", x = uniform_pt$m + 0.01, y = uniform_pt$log10_kappa + 0.08,
             label = "U(0,1)", size = 3, hjust = 0, color = "grey35") +
    labs(title = title, x = "m (mean SGPc on 0-1 scale)", y = expression(log[10](kappa)),
         fill = expression(log[10](W[1]))) +
    theme_publication()

  save_plot_multi(p, filename, output_dir, width = PLOT_WIDTH, height = PLOT_HEIGHT)
  invisible(p)
}


#' Plot District Summary Grade Panel
#'
#' @param summary_row One-row data.frame with district summary metrics
#' @param output_dir Character directory
#' @param filename Character base filename
#'
#' @return The ggplot object (invisible)
#' @export
plot_district_summary_grade <- function(summary_row,
                                        output_dir = "results/visualizations",
                                        filename = "panel_g_district_summary_grade") {
  stopifnot(nrow(summary_row) >= 1)
  sr <- summary_row[1, , drop = FALSE]

  labels <- c(
    sprintf("Dataset: %s", sr$dataset_id),
    sprintf("Condition: %s", sr$condition_id),
    sprintf("Subgroup: %s", sr$subgroup_id),
    sprintf("n = %s", sr$n_subgroup),
    sprintf("Regime family: %s", sr$regime_family),
    sprintf("Mean SGPc (inf/true): %.1f / %.1f", sr$mean_sgpc_inferred, sr$mean_sgpc_true),
    sprintf("Median SGPc (inf/true): %.1f / %.1f", sr$median_sgpc_inferred, sr$median_sgpc_true),
    sprintf("W1 (best/uniform): %.4f / %.4f", sr$w1_best, sr$w1_uniform),
    sprintf("W1 reduction: %.1f%%", sr$w1_reduction_pct),
    sprintf("Residual max |F_H - F_obs|: %.4f", sr$max_abs_residual),
    sprintf("Median 95%% CI: [%.1f, %.1f]", sr$ci95_median_lo, sr$ci95_median_hi),
    sprintf("K3/K5 buckets: %s / %s", sr$k3_assigned, sr$k5_assigned),
    sprintf("K3/K5 consistency: %.3f / %.3f", sr$k3_consistency, sr$k5_consistency),
    sprintf("Flags: %s", sr$quality_flags)
  )

  text_df <- data.frame(
    x = 1,
    y = rev(seq_along(labels)),
    label = labels
  )

  p <- ggplot(text_df, aes(x = x, y = y, label = label)) +
    geom_text(hjust = 0, size = 3.8, family = "", color = "grey20") +
    scale_x_continuous(limits = c(1, 1.02), expand = c(0, 0)) +
    scale_y_continuous(limits = c(0.5, length(labels) + 0.8), expand = c(0, 0)) +
    labs(title = "D. District Summary Grade (Model Health)") +
    theme_void() +
    theme(
      plot.title = element_text(face = "bold", size = 14, hjust = 0),
      plot.margin = margin(15, 15, 15, 15),
      panel.border = element_rect(color = "grey80", fill = NA, linewidth = 0.6)
    )

  save_plot_multi(p, filename, output_dir, width = 10, height = 6)
  invisible(p)
}


#' Multi-Panel Recovery Summary
#'
#' Four-panel diagnostic: A. CDF overlay, B. Regime density vs true,
#' C. Q-Q plot, D. Grid search landscape.
#'
#' @param est Result from estimate_regime()
#' @param true_sgpc Numeric vector of actual SGPc values (1-99). Can be NULL.
#' @param title Character. Overall title.
#' @param output_dir Character.
#' @param filename Character.
#'
#' @return The patchwork composite (invisible).
#' @export
plot_recovery_summary <- function(est, true_sgpc = NULL,
                                   title = "Growth Regime Recovery Summary",
                                   output_dir = "results/visualizations",
                                   filename = "recovery_summary") {

  # --- Panel A: CDF overlay ---
  cdf_df <- data.frame(
    v   = rep(est$v_grid, 2),
    cdf = c(est$F_obs, est$F_pred),
    source = rep(c("Observed", "Predicted"), each = length(est$v_grid))
  )
  cols_cdf <- c("Observed" = STEP3_COLORS$observed, "Predicted" = STEP3_COLORS$predicted)
  ltys_cdf <- c("Observed" = "solid", "Predicted" = "dashed")

  pA <- ggplot(cdf_df, aes(x = v, y = cdf, color = source, linetype = source)) +
    geom_line(linewidth = 0.8) +
    scale_color_manual(values = cols_cdf) +
    scale_linetype_manual(values = ltys_cdf) +
    labs(title = "A. CDF Comparison", x = "v", y = "CDF",
         color = NULL, linetype = NULL) +
    theme_publication(base_size = 9) +
    theme(legend.position = c(0.80, 0.15))

  # --- Panel B: Regime density ---
  p_grid <- seq(0.01, 0.99, length.out = 200)
  inferred_d <- est$regime$density(p_grid)
  df_B <- data.frame(sgpc = p_grid * 100, density = inferred_d, source = "Inferred")

  if (!is.null(true_sgpc)) {
    kd <- density(true_sgpc / 100, from = 0.01, to = 0.99, bw = "SJ", n = 200)
    df_B <- rbind(df_B, data.frame(sgpc = kd$x * 100, density = kd$y,
                                    source = "Actual"))
  }
  cols_B <- c("Inferred" = STEP3_COLORS$inferred, "Actual" = STEP3_COLORS$actual)

  pB <- ggplot(df_B, aes(x = sgpc, y = density, color = source)) +
    geom_line(linewidth = 0.8) +
    geom_vline(xintercept = est$regime$mean * 100, linetype = "dotdash",
               color = STEP3_COLORS$inferred, linewidth = 0.5) +
    geom_vline(xintercept = est$regime$median * 100, linetype = "dashed",
               color = STEP3_COLORS$inferred, linewidth = 0.5) +
    scale_color_manual(values = cols_B) +
    labs(title = "B. Regime Shape", x = "SGPc", y = "Density", color = NULL) +
    theme_publication(base_size = 9) +
    theme(legend.position = c(0.80, 0.85))

  if (!is.null(true_sgpc)) {
    pB <- pB +
      geom_vline(xintercept = mean(true_sgpc), linetype = "dotdash",
                 color = STEP3_COLORS$actual, linewidth = 0.5) +
      geom_vline(xintercept = median(true_sgpc), linetype = "dashed",
                 color = STEP3_COLORS$actual, linewidth = 0.5)
  }

  # --- Panel C: Q-Q plot ---
  n_qq <- min(99, length(est$v_grid))
  probs <- seq(0.01, 0.99, length.out = n_qq)
  q_obs  <- quantile(est$F_obs,  probs = probs, type = 1)
  q_pred <- quantile(est$F_pred, probs = probs, type = 1)
  qq_df <- data.frame(observed = q_obs, predicted = q_pred)

  pC <- ggplot(qq_df, aes(x = observed, y = predicted)) +
    geom_point(size = 1, alpha = 0.6, color = STEP3_COLORS$point_est) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey50") +
    labs(title = "C. Q-Q Plot", x = "Observed quantiles",
         y = "Predicted quantiles") +
    theme_publication(base_size = 9)

  # --- Panel D: Grid search landscape ---
  gs <- est$grid_search
  if (!is.null(gs) && nrow(gs) > 0 &&
      ("regime_param_1" %in% names(gs) || "theta1" %in% names(gs))) {
    valid_gs <- gs[is.finite(gs$distance), ]
    x_col <- if ("regime_param_1" %in% names(valid_gs)) "regime_param_1" else "theta1"
    y_col <- if ("regime_param_2" %in% names(valid_gs)) "regime_param_2" else if ("theta2" %in% names(valid_gs)) "theta2" else NULL
    est_params <- if (!is.null(est$regime_param_hat)) est$regime_param_hat else est$theta_hat

    if (nrow(valid_gs) > 0 && !is.null(y_col)) {
      opt_pt <- data.frame(x = est_params[1], y = est_params[2])
      pD <- ggplot(valid_gs, aes(x = .data[[x_col]], y = .data[[y_col]], color = .data[["distance"]])) +
        geom_point(size = 0.8) +
        scale_color_gradientn(colours = c(STEP3_COLORS$predicted, "#FEC44F",
                                           STEP3_COLORS$residual_pos)) +
        geom_point(data = opt_pt, aes(x = x, y = y),
                   shape = 4, size = 3, stroke = 1.5, color = "black",
                   inherit.aes = FALSE) +
        labs(title = "D. Grid Search", x = "m", y = "kappa") +
        theme_publication(base_size = 9) +
        theme(legend.position = "none")
    } else if (nrow(valid_gs) > 0) {
      opt_pt <- data.frame(param = est_params[1])
      pD <- ggplot(valid_gs, aes(x = .data[[x_col]], y = .data[["distance"]])) +
        geom_line(linewidth = 0.8, color = STEP3_COLORS$predicted) +
        geom_vline(data = opt_pt, aes(xintercept = param),
                   linetype = "dashed", color = STEP3_COLORS$residual_pos) +
        labs(title = "D. Grid Search", x = "regime parameter", y = "Distance") +
        theme_publication(base_size = 9)
    } else {
      pD <- ggplot() + annotate("text", x = 0.5, y = 0.5,
                                 label = "Grid search data\nnot available",
                                 size = 4) + theme_void()
    }
  } else {
    pD <- ggplot() + annotate("text", x = 0.5, y = 0.5,
                               label = "Grid search data\nnot available",
                               size = 4) + theme_void()
  }

  combined <- (pA | pB) / (pC | pD) +
    plot_annotation(title = title,
                    theme = theme(plot.title = element_text(face = "bold",
                                                            size = 14, hjust = 0)))

  save_plot_multi(combined, filename, output_dir, width = PLOT_WIDTH, height = 9)

  invisible(combined)
}


cat("STEP 3 diagnostics_plots.R loaded.\n")
cat("  Functions: plot_observed_vs_predicted_cdf, plot_regime_shape,\n")
cat("             plot_residual_curve, plot_objective_surface,\n")
cat("             plot_district_summary_grade, plot_recovery_summary\n")
