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
### Project: Copula Sensitivity Analyses — STEP 3 (LIw_LD)
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

  plot_fn <- function() {
    par(mar = c(5, 5, 3, 1))

    abs_diff <- abs(phase_b$median_diff)
    sizes <- phase_b$n_subgroup

    plot(sizes, abs_diff, pch = 16, cex = 0.8,
         col = adjustcolor("#2171B5", 0.5),
         xlab = "Subgroup Size (n)",
         ylab = "|Inferred - True Median SGPc|",
         main = "Recovery Accuracy vs Subgroup Size",
         log = "x")

    # Loess trend
    if (nrow(phase_b) > 10) {
      lo <- loess(abs_diff ~ log(sizes), span = 0.75)
      x_pred <- seq(min(log(sizes)), max(log(sizes)), length.out = 100)
      y_pred <- predict(lo, x_pred)
      lines(exp(x_pred), y_pred, lwd = 2.5, col = "#CB181D")
    }

    # Reference lines
    abline(h = 2, lty = 2, col = "grey60")
    abline(h = 5, lty = 3, col = "grey70")
    text(max(sizes) * 0.7, 2.3, "2 SGP points", cex = 0.7, col = "grey50")
    text(max(sizes) * 0.7, 5.3, "5 SGP points", cex = 0.7, col = "grey60")
  }

  base_path <- file.path(viz_dir, "panel_c_recovery_by_size")
  if (exists("export_plot_multi_format")) {
    export_plot_multi_format(plot_fn, base_filename = base_path,
                              width = 8, height = 6, formats = formats)
  } else {
    pdf(paste0(base_path, ".pdf"), width = 8, height = 6)
    plot_fn()
    dev.off()
  }
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

  plot_fn <- function() {
    par(mar = c(5, 5, 3, 1))

    spans <- sort(unique(phase_b$year_span))
    bp_data <- lapply(spans, function(s) abs(phase_b$median_diff[phase_b$year_span == s]))

    boxplot(bp_data, names = paste0(spans, "-yr"),
            col = adjustcolor("#2171B5", 0.3),
            border = "#2171B5",
            xlab = "Year Span",
            ylab = "|Inferred - True Median SGPc|",
            main = "Recovery Accuracy by Year Span",
            outline = FALSE)

    # Overlay jittered points
    for (i in seq_along(spans)) {
      n_pts <- length(bp_data[[i]])
      jitter_x <- i + runif(n_pts, -0.15, 0.15)
      points(jitter_x, bp_data[[i]], pch = 16, cex = 0.5,
             col = adjustcolor("#CB181D", 0.4))
    }

    abline(h = 2, lty = 2, col = "grey60")
  }

  base_path <- file.path(viz_dir, "panel_d_recovery_by_span")
  if (exists("export_plot_multi_format")) {
    export_plot_multi_format(plot_fn, base_filename = base_path,
                              width = 7, height = 6, formats = formats)
  } else {
    pdf(paste0(base_path, ".pdf"), width = 7, height = 6)
    plot_fn()
    dev.off()
  }
  cat("generated.\n")

} else {
  cat("skipped.\n")
}


############################################################################
### Panel E: Regime Family Comparison (Phase A)
############################################################################

cat("Panel E: Regime Family Comparison... ")
if (!is.null(phase_a) && !is.null(phase_a$family_comparison)) {

  plot_fn <- function() {
    par(mar = c(5, 5, 3, 1))
    comp <- phase_a$family_comparison$comparison
    p_grid <- seq(0.01, 0.99, length.out = 200)

    # Get densities for each family
    cols <- c(beta = "#2171B5", truncexp = "#E6550D", truncunif = "#31A354")
    ltys <- c(beta = 1, truncexp = 2, truncunif = 4)
    y_max <- 0

    densities <- list()
    for (fam in comp$family) {
      est <- phase_a$family_comparison$results[[fam]]
      if (!is.null(est)) {
        d <- est$regime$density(p_grid)
        densities[[fam]] <- d
        y_max <- max(y_max, max(d, na.rm = TRUE))
      }
    }

    # True SGPc density
    if (!is.null(phase_a$true_sgpc)) {
      true_d <- density(phase_a$true_sgpc / 100, from = 0.01, to = 0.99, bw = "SJ")
      y_max <- max(y_max, max(true_d$y))
    }

    plot(NULL, xlim = c(0, 100), ylim = c(0, y_max * 1.2),
         xlab = "SGPc", ylab = "Density",
         main = "Regime Family Comparison")

    for (fam in names(densities)) {
      lines(p_grid * 100, densities[[fam]], lwd = 2,
            col = cols[fam], lty = ltys[fam])
    }

    if (!is.null(phase_a$true_sgpc)) {
      lines(true_d$x * 100, true_d$y, lwd = 2.5, col = "grey30")
    }

    legend_labels <- c("Actual (longitudinal)", names(densities))
    legend_cols <- c("grey30", cols[names(densities)])
    legend_ltys <- c(1, ltys[names(densities)])
    legend("topright", legend = legend_labels, col = legend_cols,
           lty = legend_ltys, lwd = 2, bty = "n", cex = 0.8)

    # Add distance annotations
    for (i in seq_len(nrow(comp))) {
      text(85, y_max * (1.1 - 0.08 * i),
           paste0(comp$family[i], ": W1=", round(comp$distance[i], 4)),
           cex = 0.7, col = cols[comp$family[i]], adj = 0)
    }
  }

  base_path <- file.path(viz_dir, "panel_e_family_comparison")
  if (exists("export_plot_multi_format")) {
    export_plot_multi_format(plot_fn, base_filename = base_path,
                              width = 8, height = 6, formats = formats)
  } else {
    pdf(paste0(base_path, ".pdf"), width = 8, height = 6)
    plot_fn()
    dev.off()
  }
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
    plot_fn <- function() {
      par(mar = c(5, 5, 3, 1))

      hist(boot$median_sgpc_draws[valid], breaks = 30,
           col = adjustcolor("#2171B5", 0.3), border = "#2171B5",
           xlab = "Median SGPc (bootstrap draws)",
           ylab = "Frequency",
           main = "Bootstrap Distribution of Median SGPc")

      # True value
      true_med <- median(phase_a$true_sgpc, na.rm = TRUE)
      abline(v = true_med, lwd = 2, col = "#E6550D")

      # Point estimate
      abline(v = phase_a$best_estimate$regime$median * 100, lwd = 2,
             col = "#2171B5", lty = 2)

      # CI
      ci <- boot$ci_median_sgpc
      abline(v = ci, lwd = 1, col = "grey50", lty = 3)

      legend("topright",
             legend = c("Point estimate", "True (longitudinal)",
                        paste0("95% CI [", round(ci[1], 1), ", ", round(ci[2], 1), "]")),
             col = c("#2171B5", "#E6550D", "grey50"),
             lty = c(2, 1, 3), lwd = c(2, 2, 1), bty = "n", cex = 0.8)
    }

    base_path <- file.path(viz_dir, "panel_f_bootstrap_uncertainty")
    if (exists("export_plot_multi_format")) {
      export_plot_multi_format(plot_fn, base_filename = base_path,
                                width = 8, height = 6, formats = formats)
    } else {
      pdf(paste0(base_path, ".pdf"), width = 8, height = 6)
      plot_fn()
      dev.off()
    }
    cat("generated.\n")
  } else {
    cat("skipped (insufficient bootstrap draws).\n")
  }

} else {
  cat("skipped.\n")
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

# Add Phase A as a subgroup estimate
if (!is.null(phase_a)) {
  sg_key <- paste0(phase_a$condition_id, "__", phase_a$subgroup_id)
  manifest_results$subgroup_estimates[[sg_key]] <- phase_a$best_estimate
}

export_step3_manifest(manifest_results, output_dir = RESULTS_DIR)

cat("\n--- Phase C complete ---\n\n")
