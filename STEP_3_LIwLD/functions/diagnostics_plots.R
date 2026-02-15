############################################################################
###
### Diagnostic Plots for STEP 3: Growth Regime Inference
###
### Publication-quality visualisations comparing inferred growth regimes
### to ground truth (actual SGPc distributions from longitudinal data).
###
### Uses export_plot_multi_format() from shared functions for PDF/SVG/PNG.
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIw_LD)
###
############################################################################


#' Plot Observed vs Predicted CDF
#'
#' Overlay of observed current-grade CDF and the predicted CDF under
#' the estimated growth regime. The residual (difference) is shown
#' in a lower panel.
#'
#' @param est Result from estimate_regime()
#' @param title Character. Plot title.
#' @param output_dir Character. Directory for saved plots.
#' @param filename Character. Base filename (no extension). Default "cdf_comparison".
#' @param export_formats Character vector. Default c("pdf", "svg", "png").
#'
#' @return Invisible NULL. Side effect: plots saved to output_dir.
#'
#' @export
plot_observed_vs_predicted_cdf <- function(est,
                                            title = "Observed vs Predicted CDF",
                                            output_dir = "results/visualizations",
                                            filename = "cdf_comparison",
                                            export_formats = c("pdf", "svg", "png")) {

  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  plot_fn <- function() {
    layout(matrix(1:2, ncol = 1), heights = c(3, 1))

    # --- Upper panel: CDF overlay ---
    par(mar = c(1, 4.5, 3, 1))
    plot(est$v_grid, est$F_obs, type = "l", lwd = 2, col = "grey30",
         xlab = "", ylab = "CDF",
         main = title, ylim = c(0, 1))
    lines(est$v_grid, est$F_pred, lwd = 2, col = "#2171B5", lty = 2)

    legend("bottomright",
           legend = c("Observed", "Predicted"),
           col = c("grey30", "#2171B5"),
           lty = c(1, 2), lwd = 2, bty = "n", cex = 0.9)

    # Annotate with regime summary
    regime <- est$regime
    d <- est$all_distances
    info_text <- paste0(
      "Regime: ", regime$family,
      " | Median SGPc: ", round(regime$median * 100, 1),
      " | W1: ", round(d$wasserstein1, 4),
      " | CvM: ", round(d$cramer_von_mises, 6)
    )
    mtext(info_text, side = 1, line = -0.5, cex = 0.7, col = "grey40")

    # --- Lower panel: residual ---
    par(mar = c(4.5, 4.5, 0.5, 1))
    residual <- est$F_pred - est$F_obs
    plot(est$v_grid, residual, type = "l", lwd = 1.5, col = "#CB181D",
         xlab = "v (current-grade reference percentile)",
         ylab = expression(F[theta](v) - F[obs](v)),
         ylim = c(-max(abs(residual)) * 1.3, max(abs(residual)) * 1.3))
    abline(h = 0, lty = 3, col = "grey50")
    abline(h = c(-0.02, 0.02), lty = 2, col = "grey70")
  }

  # Export using shared utility if available
  base_path <- file.path(output_dir, filename)
  if (exists("export_plot_multi_format")) {
    export_plot_multi_format(plot_fn, base_filename = base_path,
                              width = 8, height = 7, formats = export_formats)
  } else {
    pdf(paste0(base_path, ".pdf"), width = 8, height = 7)
    plot_fn()
    dev.off()
  }

  invisible(NULL)
}


#' Plot Inferred Regime Shape vs True SGPc Distribution
#'
#' Compares the estimated growth regime H_theta (density on [0,1]) with
#' the actual distribution of SGPc values computed from longitudinal data.
#' This is the key validation plot for STEP 3.
#'
#' @param regime A growth_regime object (estimated)
#' @param true_sgpc Numeric vector of actual SGPc values (1-99 scale) from
#'   longitudinal data. If NULL, only the estimated regime is shown.
#' @param title Character. Plot title.
#' @param output_dir Character. Directory for saved plots.
#' @param filename Character. Base filename. Default "regime_comparison".
#' @param export_formats Character vector. Default c("pdf", "svg", "png").
#'
#' @return Invisible NULL.
#'
#' @export
plot_regime_shape <- function(regime, true_sgpc = NULL,
                               title = "Growth Regime: Inferred vs Actual",
                               output_dir = "results/visualizations",
                               filename = "regime_comparison",
                               export_formats = c("pdf", "svg", "png")) {

  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  plot_fn <- function() {
    p_grid <- seq(0.01, 0.99, length.out = 200)

    # Inferred density
    inferred_density <- regime$density(p_grid)

    y_max <- max(inferred_density, na.rm = TRUE) * 1.3
    if (!is.null(true_sgpc)) {
      true_density <- density(true_sgpc / 100, from = 0.01, to = 0.99,
                               bw = "SJ", n = 200)
      y_max <- max(y_max, max(true_density$y) * 1.3)
    }

    par(mar = c(5, 4.5, 3, 1))
    plot(p_grid * 100, inferred_density, type = "l", lwd = 2.5,
         col = "#2171B5",
         xlab = "SGPc (Conditional Growth Percentile)",
         ylab = "Density",
         main = title,
         ylim = c(0, y_max),
         xlim = c(0, 100))

    # Add shading under inferred curve
    polygon(c(p_grid * 100, rev(p_grid * 100)),
            c(inferred_density, rep(0, length(p_grid))),
            col = adjustcolor("#2171B5", alpha.f = 0.15), border = NA)

    if (!is.null(true_sgpc)) {
      lines(true_density$x * 100, true_density$y, lwd = 2.5,
            col = "#E6550D", lty = 1)
      polygon(c(true_density$x * 100, rev(true_density$x * 100)),
              c(true_density$y, rep(0, length(true_density$y))),
              col = adjustcolor("#E6550D", alpha.f = 0.10), border = NA)

      legend("topright",
             legend = c(paste0("Inferred (", regime$family, ")"),
                        "Actual (longitudinal)"),
             col = c("#2171B5", "#E6550D"),
             lwd = 2.5, lty = c(1, 1), bty = "n", cex = 0.9)

      # Summary statistics
      info <- paste0(
        "Inferred median: ", round(regime$median * 100, 1),
        " | Actual median: ", round(median(true_sgpc), 1),
        " | Diff: ", round(regime$median * 100 - median(true_sgpc), 1)
      )
      mtext(info, side = 1, line = 3.5, cex = 0.7, col = "grey40")
    } else {
      legend("topright",
             legend = paste0("Inferred (", regime$family, ")"),
             col = "#2171B5", lwd = 2.5, bty = "n", cex = 0.9)
    }

    # Reference lines
    abline(v = 50, lty = 3, col = "grey50")
    abline(v = regime$median * 100, lty = 2, col = "#2171B5")
  }

  base_path <- file.path(output_dir, filename)
  if (exists("export_plot_multi_format")) {
    export_plot_multi_format(plot_fn, base_filename = base_path,
                              width = 8, height = 6, formats = export_formats)
  } else {
    pdf(paste0(base_path, ".pdf"), width = 8, height = 6)
    plot_fn()
    dev.off()
  }

  invisible(NULL)
}


#' Plot Residual Curve
#'
#' Simple residual plot: F_theta(v) - F_obs(v).
#'
#' @param est Result from estimate_regime()
#' @param output_dir Character.
#' @param filename Character. Default "residual_curve".
#' @param export_formats Character vector.
#'
#' @return Invisible NULL.
#'
#' @export
plot_residual_curve <- function(est,
                                 output_dir = "results/visualizations",
                                 filename = "residual_curve",
                                 export_formats = c("pdf", "svg", "png")) {

  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  plot_fn <- function() {
    residual <- est$F_pred - est$F_obs
    par(mar = c(5, 4.5, 3, 1))
    plot(est$v_grid, residual, type = "l", lwd = 2, col = "#CB181D",
         xlab = "v (current-grade reference percentile)",
         ylab = expression(F[theta](v) - F[obs](v)),
         main = "CDF Residual Curve")
    abline(h = 0, lty = 1, col = "grey50")
    abline(h = c(-0.02, 0.02), lty = 2, col = "grey70")
    abline(h = c(-0.05, 0.05), lty = 3, col = "grey80")

    # Shade positive/negative regions
    pos <- residual > 0
    neg <- residual < 0
    if (any(pos)) {
      segments(est$v_grid[pos], 0, est$v_grid[pos], residual[pos],
               col = adjustcolor("#CB181D", 0.3))
    }
    if (any(neg)) {
      segments(est$v_grid[neg], 0, est$v_grid[neg], residual[neg],
               col = adjustcolor("#2171B5", 0.3))
    }
  }

  base_path <- file.path(output_dir, filename)
  if (exists("export_plot_multi_format")) {
    export_plot_multi_format(plot_fn, base_filename = base_path,
                              width = 8, height = 5, formats = export_formats)
  } else {
    pdf(paste0(base_path, ".pdf"), width = 8, height = 5)
    plot_fn()
    dev.off()
  }

  invisible(NULL)
}


#' Multi-Panel Recovery Summary
#'
#' Four-panel diagnostic combining:
#'   A. Observed vs predicted CDF
#'   B. Inferred regime density vs true SGPc histogram
#'   C. Q-Q plot (predicted vs observed quantiles)
#'   D. Grid search landscape (distance vs parameter)
#'
#' @param est Result from estimate_regime()
#' @param true_sgpc Numeric vector of actual SGPc values (1-99). Can be NULL.
#' @param title Character. Overall title.
#' @param output_dir Character.
#' @param filename Character. Default "recovery_summary".
#' @param export_formats Character vector.
#'
#' @return Invisible NULL.
#'
#' @export
plot_recovery_summary <- function(est, true_sgpc = NULL,
                                   title = "Growth Regime Recovery Summary",
                                   output_dir = "results/visualizations",
                                   filename = "recovery_summary",
                                   export_formats = c("pdf", "svg", "png")) {

  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  plot_fn <- function() {
    par(mfrow = c(2, 2), mar = c(4, 4, 2.5, 1), oma = c(0, 0, 2, 0))

    # --- Panel A: CDF overlay ---
    plot(est$v_grid, est$F_obs, type = "l", lwd = 2, col = "grey30",
         xlab = "v", ylab = "CDF", main = "A. CDF Comparison")
    lines(est$v_grid, est$F_pred, lwd = 2, col = "#2171B5", lty = 2)
    legend("bottomright", legend = c("Observed", "Predicted"),
           col = c("grey30", "#2171B5"), lty = c(1, 2), lwd = 2,
           bty = "n", cex = 0.75)

    # --- Panel B: Regime density vs true SGPc ---
    p_grid <- seq(0.01, 0.99, length.out = 200)
    inferred_d <- est$regime$density(p_grid)
    y_max <- max(inferred_d) * 1.3

    if (!is.null(true_sgpc)) {
      true_d <- density(true_sgpc / 100, from = 0.01, to = 0.99, bw = "SJ")
      y_max <- max(y_max, max(true_d$y) * 1.3)
    }

    plot(p_grid * 100, inferred_d, type = "l", lwd = 2, col = "#2171B5",
         xlab = "SGPc", ylab = "Density", main = "B. Regime Shape",
         ylim = c(0, y_max))
    if (!is.null(true_sgpc)) {
      lines(true_d$x * 100, true_d$y, lwd = 2, col = "#E6550D")
      legend("topright", legend = c("Inferred", "Actual"),
             col = c("#2171B5", "#E6550D"), lwd = 2, bty = "n", cex = 0.75)
    }

    # --- Panel C: Q-Q plot ---
    n_qq <- min(99, length(est$v_grid))
    probs <- seq(0.01, 0.99, length.out = n_qq)
    q_obs  <- quantile(est$F_obs, probs = probs, type = 1)
    q_pred <- quantile(est$F_pred, probs = probs, type = 1)
    plot(q_obs, q_pred, pch = 16, cex = 0.6, col = "#2171B5",
         xlab = "Observed quantiles", ylab = "Predicted quantiles",
         main = "C. Q-Q Plot")
    abline(0, 1, lty = 2, col = "grey50")

    # --- Panel D: Grid search landscape ---
    gs <- est$grid_search
    if (!is.null(gs) && nrow(gs) > 0 && "theta1" %in% names(gs)) {
      valid_gs <- gs[is.finite(gs$distance), ]
      if (nrow(valid_gs) > 0) {
        col_pal <- colorRampPalette(c("#2171B5", "#FEC44F", "#CB181D"))(100)
        d_range <- range(valid_gs$distance)
        d_scaled <- (valid_gs$distance - d_range[1]) / max(diff(d_range), 1e-10)
        d_idx <- pmax(1, pmin(100, round(d_scaled * 99) + 1))

        if ("theta2" %in% names(valid_gs)) {
          plot(valid_gs$theta1, valid_gs$theta2, pch = 15, cex = 0.5,
               col = col_pal[d_idx],
               xlab = "theta1 (mean)", ylab = "theta2 (kappa)",
               main = "D. Grid Search Landscape")
          points(est$theta_hat[1], est$theta_hat[2],
                 pch = 4, cex = 2, lwd = 2, col = "black")
        } else {
          plot(valid_gs$theta1, valid_gs$distance, type = "l", lwd = 2,
               col = "#2171B5",
               xlab = "theta (mean)", ylab = "Distance",
               main = "D. Grid Search Landscape")
          abline(v = est$theta_hat[1], lty = 2, col = "red")
        }
      } else {
        plot.new()
        text(0.5, 0.5, "Grid search data\nnot available", cex = 1.1)
      }
    } else {
      plot.new()
      text(0.5, 0.5, "Grid search data\nnot available", cex = 1.1)
    }

    mtext(title, outer = TRUE, cex = 1.1, font = 2)
  }

  base_path <- file.path(output_dir, filename)
  if (exists("export_plot_multi_format")) {
    export_plot_multi_format(plot_fn, base_filename = base_path,
                              width = 10, height = 9, formats = export_formats)
  } else {
    pdf(paste0(base_path, ".pdf"), width = 10, height = 9)
    plot_fn()
    dev.off()
  }

  invisible(NULL)
}


cat("STEP 3 diagnostics_plots.R loaded.\n")
cat("  Functions: plot_observed_vs_predicted_cdf, plot_regime_shape,\n")
cat("             plot_residual_curve, plot_recovery_summary\n")
