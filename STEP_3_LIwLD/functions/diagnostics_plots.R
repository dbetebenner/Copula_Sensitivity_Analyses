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

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

format_step3_subtitle <- function(line1, line2) {
  line1 <- trimws(as.character(line1 %||% ""))
  line2 <- trimws(as.character(line2 %||% ""))
  if (!nzchar(line1)) {
    return(line2)
  }
  if (!nzchar(line2)) {
    return(line1)
  }
  paste0(line1, "\n", line2)
}

format_p_value <- function(p) {
  ifelse(is.finite(p), formatC(p, format = "e", digits = 2), "NA")
}

#' Format a STEP 3 condition + subgroup identifier into a readable plot title
#'
#' Parses a condition_id of the form "YYYY_GX_GY_CONTENT_AREA" and an optional
#' subgroup column/value pair into the format:
#'   "Content Area: YYYY_prior/Grade X -> YYYY_current/Grade Y -- Subgroup value"
#'
#' The prior year is derived by subtracting the grade span from the current year
#' (e.g. G5->G6 is a 1-year span, so year 2008 implies prior year 2007).
#'
#' @param condition_id  Character. E.g. "2008_G5_G6_MATHEMATICS".
#' @param subgroup_col  Character. E.g. "DISTRICT_NUMBER". Pass NULL to omit.
#' @param subgroup_id   Character/numeric. E.g. "0020". Pass NULL to omit.
#' @param panel_prefix  Character. Optional panel letter prefix, e.g. "A.".
#'
#' @return A single formatted character string suitable for ggplot2 \code{title}.
#' @export
format_step3_condition_label <- function(
  condition_id,
  subgroup_col = NULL,
  subgroup_id = NULL,
  panel_prefix = NULL
) {
  cid <- as.character(condition_id %||% "Unknown")

  # Parse "YYYY_GX_GY_CONTENT_AREA_POSSIBLY_MULTIWORD"
  # Expected tokens: year, grade_prior (G<n>), grade_current (G<n>), content...
  parts <- strsplit(cid, "_", fixed = TRUE)[[1]]

  year <- NA_character_
  grade_prior <- NA_character_
  grade_current <- NA_character_
  content_parts <- character(0)

  i <- 1L
  while (i <= length(parts)) {
    p <- parts[[i]]
    if (is.na(year) && grepl("^\\d{4}$", p)) {
      year <- p
    } else if (is.na(grade_prior) && grepl("^G\\d+$", p, ignore.case = TRUE)) {
      grade_prior <- sub("^[Gg]", "", p)
    } else if (
      is.na(grade_current) && grepl("^G\\d+$", p, ignore.case = TRUE)
    ) {
      grade_current <- sub("^[Gg]", "", p)
    } else {
      content_parts <- c(content_parts, p)
    }
    i <- i + 1L
  }

  # Format content area: title-case, join with space
  content_str <- if (length(content_parts) > 0) {
    tools::toTitleCase(tolower(paste(content_parts, collapse = " ")))
  } else {
    cid
  }

  # Derive prior year from current year and grade span
  # e.g. G5->G6 is span 1, so year_prior = year_current - 1
  year_current_int <- suppressWarnings(as.integer(year))
  grade_prior_int <- suppressWarnings(as.integer(grade_prior))
  grade_current_int <- suppressWarnings(as.integer(grade_current))

  year_prior_int <- if (
    !is.na(year_current_int) &&
      !is.na(grade_prior_int) &&
      !is.na(grade_current_int)
  ) {
    span <- grade_current_int - grade_prior_int
    year_current_int - max(span, 1L) # guard against 0 or negative span
  } else {
    NA_integer_
  }

  # Build the grade/year span string: "2007/Grade 5 -> 2008/Grade 6"
  grade_str <- if (!is.na(grade_prior) && !is.na(grade_current)) {
    prior_part <- if (!is.na(year_prior_int)) {
      sprintf("%d/Grade %s", year_prior_int, grade_prior)
    } else {
      sprintf("Grade %s", grade_prior)
    }
    current_part <- if (!is.na(year_current_int)) {
      sprintf("%d/Grade %s", year_current_int, grade_current)
    } else {
      sprintf("Grade %s", grade_current)
    }
    sprintf("%s \u2192 %s", prior_part, current_part)
  } else if (!is.na(grade_prior)) {
    if (!is.na(year_current_int)) {
      sprintf("%d/Grade %s", year_current_int, grade_prior)
    } else {
      sprintf("Grade %s", grade_prior)
    }
  } else {
    NULL
  }

  # Assemble condition part: "Mathematics: 2007/Grade 5 -> 2008/Grade 6"
  if (!is.null(grade_str)) {
    cond_label <- sprintf("%s: %s", content_str, grade_str)
  } else {
    cond_label <- content_str
  }

  # Build subgroup label
  sg_label <- if (
    !is.null(subgroup_col) &&
      !is.null(subgroup_id) &&
      !is.na(subgroup_col) &&
      !is.na(subgroup_id)
  ) {
    # Clean up the column name: "DISTRICT_NUMBER" -> "District"
    col_clean <- tools::toTitleCase(tolower(gsub("_", " ", subgroup_col)))
    # Strip trailing " Number" for compact display
    col_clean <- sub("\\s+Number$", "", col_clean, ignore.case = TRUE)
    sprintf("%s %s", col_clean, subgroup_id)
  } else {
    NULL
  }

  # Combine with em-dash separator
  label <- if (!is.null(sg_label)) {
    sprintf("%s \u2014 %s", cond_label, sg_label)
  } else {
    cond_label
  }

  # Optionally prepend a panel prefix
  if (!is.null(panel_prefix) && nzchar(panel_prefix)) {
    label <- sprintf("%s %s", trimws(panel_prefix), label)
  }

  label
}


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
plot_observed_vs_predicted_cdf <- function(
  est,
  title = "Observed vs Predicted CDF",
  output_dir = "results/visualizations",
  filename = "cdf_comparison"
) {
  base_df <- list(
    data.frame(v = est$v_grid, cdf = est$F_obs, source = "Observed"),
    data.frame(v = est$v_grid, cdf = est$F_pred, source = "Best-fit")
  )
  if (!is.null(est$F_uniform)) {
    base_df[[length(base_df) + 1]] <- data.frame(
      v = est$v_grid,
      cdf = est$F_uniform,
      source = "U(0,1)"
    )
  }
  if (!is.null(est$F_tamp)) {
    base_df[[length(base_df) + 1]] <- data.frame(
      v = est$v_grid,
      cdf = est$F_tamp,
      source = "Co-monotonic F\u1d64(v)"
    )
  }
  df <- do.call(rbind, base_df)

  cols <- c(
    "Observed" = STEP3_COLORS$observed,
    "Best-fit" = STEP3_COLORS$predicted,
    "U(0,1)" = STEP3_COLORS$reference,
    "Co-monotonic F\u1d64(v)" = STEP3_COLORS$comonot
  )
  ltys <- c(
    "Observed" = "solid",
    "Best-fit" = "solid",
    "U(0,1)" = "22",
    "Co-monotonic F\u1d64(v)" = "22"
  )
  lwds <- c(
    "Observed" = 0.9 * 0.75,
    "Best-fit" = 0.9 * 1.5,
    "U(0,1)" = 0.9 * 0.75,
    "Co-monotonic F\u1d64(v)" = 0.9 * 0.75
  )

  regime <- est$regime
  d <- est$all_distances
  subtitle_stats <- sprintf(
    "Regime=%s | Mean=%.1f | Median=%.1f | W1=%.4f | CvM=%.6f",
    regime$family,
    regime$mean * 100,
    regime$median * 100,
    d$wasserstein1,
    d$cramer_von_mises
  )
  if (
    !is.null(est$w1_uniform) && is.finite(est$w1_uniform) && est$w1_uniform > 0
  ) {
    red_pct <- 100 * (1 - (d$wasserstein1 / est$w1_uniform))
    subtitle_stats <- paste0(
      subtitle_stats,
      sprintf(" | W1 reduction vs U(0,1)=%.1f%%", red_pct)
    )
  }
  subtitle <- format_step3_subtitle(
    "Does the inferred regime reproduce the observed current-grade CDF?",
    subtitle_stats
  )

  p_upper <- ggplot(
    df,
    aes(x = v, y = cdf, color = source, linetype = source, linewidth = source)
  ) +
    geom_line() +
    scale_color_manual(values = cols[names(cols) %in% unique(df$source)]) +
    scale_linetype_manual(values = ltys[names(ltys) %in% unique(df$source)]) +
    scale_linewidth_manual(
      values = lwds[names(lwds) %in% unique(df$source)],
      guide = "none"
    ) +
    labs(
      title = title,
      subtitle = subtitle,
      x = NULL,
      y = "CDF",
      color = NULL,
      linetype = NULL
    ) +
    theme_publication() +
    theme(legend.position = c(0.85, 0.15), axis.text.x = element_blank())

  # Detailed residual panel (replaces the simple ribbon in the lower slot)
  residual <- est$F_pred - est$F_obs
  resid_df <- data.frame(
    v = est$v_grid,
    residual = residual,
    sign = ifelse(residual >= 0, "positive", "negative")
  )
  max_abs <- max(abs(residual), na.rm = TRUE)
  mean_abs <- mean(abs(residual), na.rm = TRUE)
  frac_in_001 <- mean(abs(residual) <= 0.01, na.rm = TRUE)
  resid_subtitle <- format_step3_subtitle(
    "Where does best-fit CDF over/under-shoot observed CDF across v?",
    sprintf(
      "max|resid|=%.4f | mean|resid|=%.4f | within \u00b10.01: %.1f%%",
      max_abs,
      mean_abs,
      100 * frac_in_001
    )
  )

  p_lower <- ggplot(resid_df, aes(x = v, y = residual)) +
    geom_segment(
      aes(xend = v, y = 0, yend = residual, color = sign),
      alpha = 0.40,
      linewidth = 0.3
    ) +
    geom_line(linewidth = 0.7, color = STEP3_COLORS$predicted) +
    geom_ref_hline(yintercept = 0) +
    geom_hline(
      yintercept = c(-0.01, 0.01),
      linetype = "dotted",
      color = "grey70"
    ) +
    geom_hline(
      yintercept = c(-0.05, 0.05),
      linetype = "dotdash",
      color = "grey80"
    ) +
    scale_color_manual(
      values = c(
        "positive" = STEP3_COLORS$predicted,
        "negative" = STEP3_COLORS$reference
      ),
      guide = "none"
    ) +
    labs(
      subtitle = resid_subtitle,
      x = "v (current-grade reference percentile)",
      y = expression(F[H](v) - F[obs](v))
    ) +
    theme_publication()

  combined <- p_upper / p_lower + plot_layout(heights = c(3, 2))

  save_plot_multi(
    combined,
    filename,
    output_dir,
    width = PLOT_WIDTH,
    height = PLOT_HEIGHT + 3
  )

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
plot_regime_shape <- function(
  regime,
  true_sgpc = NULL,
  title = "Growth Regime: Inferred vs Actual",
  output_dir = "results/visualizations",
  filename = "regime_comparison",
  bootstrap = NULL
) {
  p_grid <- seq(0.01, 0.99, length.out = 200)
  inferred_d <- regime$density(p_grid)

  df_inferred <- data.frame(
    sgpc = p_grid * 100,
    density = inferred_d,
    source = "Inferred"
  )
  df_all <- df_inferred

  if (!is.null(true_sgpc)) {
    kd <- density(true_sgpc / 100, from = 0.01, to = 0.99, bw = "SJ", n = 200)
    df_actual <- data.frame(
      sgpc = kd$x * 100,
      density = kd$y,
      source = "Actual"
    )
    df_all <- rbind(df_all, df_actual)
  }

  cols <- c("Inferred" = STEP3_COLORS$inferred, "Actual" = STEP3_COLORS$actual)

  subtitle_stats <- if (!is.null(true_sgpc)) {
    sprintf(
      "Mean (Inf/Act)=%.1f/%.1f | Median (Inf/Act)=%.1f/%.1f",
      regime$mean * 100,
      mean(true_sgpc, na.rm = TRUE),
      regime$median * 100,
      median(true_sgpc, na.rm = TRUE)
    )
  } else {
    sprintf(
      "Inferred mean=%.1f | Inferred median=%.1f",
      regime$mean * 100,
      regime$median * 100
    )
  }
  subtitle <- format_step3_subtitle(
    "How closely does recovered regime shape match the true SGPc distribution?",
    subtitle_stats
  )

  p <- ggplot(
    df_all,
    aes(x = sgpc, y = density, fill = source, color = source)
  ) +
    geom_area(alpha = 0.15, position = "identity") +
    geom_line(linewidth = 0.9) +
    geom_ref_vline(xintercept = 50) +
    geom_vline(
      xintercept = regime$mean * 100,
      linetype = "dotdash",
      color = STEP3_COLORS$inferred,
      linewidth = 0.6
    ) +
    geom_vline(
      xintercept = regime$median * 100,
      linetype = "dashed",
      color = STEP3_COLORS$inferred,
      linewidth = 0.6
    ) +
    scale_color_manual(values = cols) +
    scale_fill_manual(values = cols) +
    labs(
      title = title,
      subtitle = subtitle,
      x = "SGPc (Conditional Growth Percentile)",
      y = "Density",
      color = NULL,
      fill = NULL
    ) +
    coord_cartesian(xlim = c(0, 100)) +
    theme_publication() +
    theme(legend.position = c(0.88, 0.88))

  if (!is.null(true_sgpc)) {
    p <- p +
      geom_vline(
        xintercept = mean(true_sgpc),
        linetype = "dotdash",
        color = STEP3_COLORS$actual,
        linewidth = 0.6
      ) +
      geom_vline(
        xintercept = median(true_sgpc),
        linetype = "dashed",
        color = STEP3_COLORS$actual,
        linewidth = 0.6
      )
  }

  if (!is.null(bootstrap) && !is.null(bootstrap$ci_mean_sgpc)) {
    p <- p +
      annotate(
        "text",
        x = 2,
        y = Inf,
        hjust = 0,
        vjust = 1.6,
        size = 3,
        color = "grey35",
        label = sprintf(
          "Bootstrap mean CI: [%.1f, %.1f]",
          bootstrap$ci_mean_sgpc[1],
          bootstrap$ci_mean_sgpc[2]
        )
      )
  }

  save_plot_multi(
    p,
    filename,
    output_dir,
    width = PLOT_WIDTH,
    height = PLOT_HEIGHT
  )

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
plot_residual_curve <- function(
  est,
  output_dir = "results/visualizations",
  filename = "residual_curve",
  title = "CDF Residual Curve"
) {
  residual <- est$F_pred - est$F_obs
  df <- data.frame(
    v = est$v_grid,
    residual = residual,
    sign = ifelse(residual >= 0, "positive", "negative")
  )

  max_abs <- max(abs(residual), na.rm = TRUE)
  mean_abs <- mean(abs(residual), na.rm = TRUE)
  frac_in_001 <- mean(abs(residual) <= 0.01, na.rm = TRUE)
  subtitle <- format_step3_subtitle(
    "Where does best-fit CDF over/under-shoot observed CDF across v?",
    sprintf(
      "max|resid|=%.4f | mean|resid|=%.4f | within \u00b10.01: %.1f%%",
      max_abs,
      mean_abs,
      100 * frac_in_001
    )
  )

  p <- ggplot(df, aes(x = v, y = residual)) +
    geom_segment(
      aes(xend = v, y = 0, yend = residual, color = sign),
      alpha = 0.40,
      linewidth = 0.3
    ) +
    geom_line(linewidth = 0.8, color = STEP3_COLORS$predicted) +
    geom_ref_hline(yintercept = 0) +
    geom_hline(
      yintercept = c(-0.01, 0.01),
      linetype = "dotted",
      color = "grey70"
    ) +
    geom_hline(
      yintercept = c(-0.05, 0.05),
      linetype = "dotdash",
      color = "grey80"
    ) +
    scale_color_manual(
      values = c(
        "positive" = STEP3_COLORS$predicted,
        "negative" = STEP3_COLORS$reference
      ),
      guide = "none"
    ) +
    labs(
      title = title,
      subtitle = subtitle,
      x = "v (current-grade reference percentile)",
      y = expression(F[H](v) - F[obs](v))
    ) +
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
plot_objective_surface <- function(
  est,
  output_dir = "results/visualizations",
  filename = "objective_surface",
  title = "B1. Growth Regime Surface"
) {
  gs <- est$grid_search
  if (is.null(gs) || nrow(gs) == 0) {
    p <- ggplot() +
      annotate(
        "text",
        x = 0.5,
        y = 0.5,
        label = "No grid search data available",
        size = 4
      ) +
      theme_void()
    save_plot_multi(
      p,
      filename,
      output_dir,
      width = PLOT_WIDTH,
      height = PLOT_HEIGHT
    )
    return(invisible(p))
  }

  m_col <- if ("m" %in% names(gs)) {
    "m"
  } else if ("regime_param_1" %in% names(gs)) {
    "regime_param_1"
  } else {
    "theta1"
  }
  k_col <- if ("kappa" %in% names(gs)) {
    "kappa"
  } else if ("regime_param_2" %in% names(gs)) {
    "regime_param_2"
  } else {
    "theta2"
  }

  gs_plot <- gs[is.finite(gs$distance), ]
  if (nrow(gs_plot) == 0) {
    p <- ggplot() +
      annotate(
        "text",
        x = 0.5,
        y = 0.5,
        label = "No finite objective values",
        size = 4
      ) +
      theme_void()
    save_plot_multi(
      p,
      filename,
      output_dir,
      width = PLOT_WIDTH,
      height = PLOT_HEIGHT
    )
    return(invisible(p))
  }

  gs_plot$log10_kappa <- log10(as.numeric(gs_plot[[k_col]]))
  gs_plot$distance_log10 <- log10(pmax(gs_plot$distance, 1e-12))
  uniform_pt <- data.frame(m = 0.5, log10_kappa = log10(2), label = "U(0,1)")
  optimum_pt <- data.frame(
    m = est$m_hat,
    log10_kappa = log10(est$kappa_hat),
    label = "hat(H)[S]"
  )

  min_w1 <- min(gs_plot$distance, na.rm = TRUE)
  subtitle <- format_step3_subtitle(
    "Which (m, kappa) combination minimizes Wasserstein-1 mismatch?",
    sprintf(
      "Best m=%.3f | Best kappa=%.2f | Min W1=%.5f | U(0,1) anchor: (m=0.50, kappa=2)",
      est$m_hat,
      est$kappa_hat,
      min_w1
    )
  )

  p <- ggplot(
    gs_plot,
    aes(
      x = .data[[m_col]],
      y = .data[["log10_kappa"]],
      fill = .data[["distance_log10"]]
    )
  ) +
    geom_tile() +
    scale_fill_gradientn(
      colours = c("#FCFCF4", "#E2E4C8", "#B7BA87", "#8A9048"),
      guide = "none"
    ) +
    geom_text(
      data = optimum_pt,
      aes(x = m, y = log10_kappa, label = label),
      inherit.aes = FALSE,
      parse = TRUE,
      size = 3,
      hjust = 0.5,
      vjust = 0.5,
      color = "black"
    ) +
    geom_text(
      data = uniform_pt,
      aes(x = m, y = log10_kappa, label = label),
      inherit.aes = FALSE,
      size = 3,
      hjust = 0.5,
      vjust = 0.5,
      color = "grey35"
    ) +
    annotate(
      "text",
      x = 0.6,
      y = 2,
      label = "Color = log10 distance",
      hjust = 0,
      vjust = 0.5,
      size = 3.5,
      color = "grey25"
    ) +
    labs(
      title = title,
      subtitle = subtitle,
      x = "m (mean SGPc on 0-1 scale)",
      y = expression(log[10](kappa))
    ) +
    theme_publication()

  save_plot_multi(
    p,
    filename,
    output_dir,
    width = PLOT_WIDTH,
    height = PLOT_HEIGHT
  )
  invisible(p)
}


#' Plot Marginal U/V Density Panel (Infographic Step A)
#'
#' @param u_sample Numeric vector of prior reference percentiles (0-1).
#' @param v_sample Numeric vector of current reference percentiles (0-1).
#' @param output_dir Character directory.
#' @param filename Character base filename.
#' @param title Character title.
#'
#' @return The ggplot object (invisible)
#' @export
plot_marginal_uv_density <- function(
  u_sample,
  v_sample,
  output_dir = "results/visualizations",
  filename = "phasea_01_marginals_uv_density",
  title = "A. Independent U and V Marginals"
) {
  stopifnot(length(u_sample) > 1, length(v_sample) > 1)
  du <- density(u_sample, from = 0.001, to = 0.999, n = 300, bw = "SJ")
  dv <- density(v_sample, from = 0.001, to = 0.999, n = 300, bw = "SJ")
  df <- rbind(
    data.frame(percentile = du$x * 100, density = du$y, source = "U (prior)"),
    data.frame(percentile = dv$x * 100, density = dv$y, source = "V (current)")
  )
  cols <- c(
    "U (prior)" = STEP3_COLORS$inferred,
    "V (current)" = STEP3_COLORS$actual
  )
  ltys <- c("U (prior)" = "solid", "V (current)" = "solid")

  subtitle <- format_step3_subtitle(
    "What information is observable from unlinked cross-sectional samples?",
    sprintf(
      "n(U)=%s | n(V)=%s | Median U=%.1f | Median V=%.1f",
      format(length(u_sample), big.mark = ","),
      format(length(v_sample), big.mark = ","),
      median(u_sample, na.rm = TRUE) * 100,
      median(v_sample, na.rm = TRUE) * 100
    )
  )

  p <- ggplot(
    df,
    aes(x = percentile, y = density, color = source, linetype = source)
  ) +
    geom_line(linewidth = 0.9) +
    geom_ref_vline(xintercept = 50) +
    scale_color_manual(values = cols) +
    scale_linetype_manual(values = ltys) +
    labs(
      title = title,
      subtitle = subtitle,
      x = "Reference percentile",
      y = "Density",
      color = NULL,
      linetype = NULL
    ) +
    coord_cartesian(xlim = c(0, 100)) +
    theme_publication()

  save_plot_multi(
    p,
    filename,
    output_dir,
    width = PLOT_WIDTH,
    height = PLOT_HEIGHT
  )
  invisible(p)
}


#' Plot Independence Diagnostic Panel (Phase A / Panel I)
#'
#' @param u_sample Numeric vector of prior reference percentiles (0-1).
#' @param true_sgpc Numeric vector of true SGPc values (1-99).
#' @param n_bins Integer number of U bins for summaries.
#' @param output_dir Character directory.
#' @param filename Character base filename.
#' @param title Character title.
#'
#' @return The ggplot object (invisible)
#' @export
plot_independence_diagnostic <- function(
  u_sample,
  true_sgpc,
  n_bins = 5,
  output_dir = "results/visualizations",
  filename = "phasea_04_independence_diagnostic",
  title = "I. Independence Diagnostic: SGPc_true vs U"
) {
  stopifnot(length(u_sample) == length(true_sgpc), length(u_sample) > 2)
  n_bins <- max(3, as.integer(n_bins))

  q_breaks <- unique(as.numeric(quantile(
    u_sample,
    probs = seq(0, 1, length.out = n_bins + 1),
    na.rm = TRUE
  )))
  if (length(q_breaks) < 3) {
    q_breaks <- seq(
      min(u_sample, na.rm = TRUE),
      max(u_sample, na.rm = TRUE),
      length.out = n_bins + 1
    )
  }
  u_bin <- cut(u_sample, breaks = q_breaks, include.lowest = TRUE)
  diag_dt <- data.frame(u = u_sample, sgpc = true_sgpc, u_bin = u_bin)
  bin_sum <- aggregate(
    sgpc ~ u_bin,
    data = diag_dt,
    FUN = function(x) {
      c(mean = mean(x, na.rm = TRUE), sd = sd(x, na.rm = TRUE), n = length(x))
    }
  )
  bin_sum <- do.call(data.frame, bin_sum)
  names(bin_sum) <- c("u_bin", "mean_sgpc", "sd_sgpc", "n")
  bin_sum$se <- bin_sum$sd_sgpc / sqrt(pmax(bin_sum$n, 1))
  bin_sum$ci_lo <- bin_sum$mean_sgpc - 1.96 * bin_sum$se
  bin_sum$ci_hi <- bin_sum$mean_sgpc + 1.96 * bin_sum$se
  bin_sum$x_mid <- (q_breaks[-1] + q_breaks[-length(q_breaks)]) / 2

  rho <- suppressWarnings(cor(
    u_sample,
    true_sgpc,
    method = "spearman",
    use = "complete.obs"
  ))
  rho_test <- tryCatch(
    cor.test(u_sample, true_sgpc, method = "spearman", exact = FALSE),
    error = function(e) NULL
  )
  rho_p <- if (!is.null(rho_test)) as.numeric(rho_test$p.value) else NA_real_
  kw <- tryCatch(kruskal.test(true_sgpc ~ u_bin), error = function(e) NULL)
  kw_p <- if (!is.null(kw)) kw$p.value else NA_real_
  subtitle <- format_step3_subtitle(
    "Is true SGPc independent of prior U percentile within subgroup?",
    sprintf(
      "Spearman rho=%.3f (p=%s) | Kruskal-Wallis p=%s across %d U bins",
      rho,
      format_p_value(rho_p),
      format_p_value(kw_p),
      nrow(bin_sum)
    )
  )

  bin_rects <- data.frame(
    xmin = q_breaks[-length(q_breaks)],
    xmax = q_breaks[-1],
    ymin = -Inf,
    ymax = Inf,
    idx = seq_len(length(q_breaks) - 1)
  )

  p <- ggplot(diag_dt, aes(x = u, y = sgpc)) +
    geom_rect(
      data = bin_rects[bin_rects$idx %% 2 == 1, , drop = FALSE],
      aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
      inherit.aes = FALSE,
      fill = STEP3_COLORS$bootstrap,
      alpha = 0.06
    ) +
    geom_vline(
      xintercept = q_breaks[-c(1, length(q_breaks))],
      linetype = "dotted",
      linewidth = 0.4,
      color = "grey65"
    ) +
    geom_point(alpha = 0.2, size = 0.7, color = STEP3_COLORS$point_est) +
    geom_smooth(
      method = "loess",
      span = 0.8,
      se = FALSE,
      linewidth = 0.8,
      color = STEP3_COLORS$loess_trend
    ) +
    geom_errorbar(
      data = bin_sum,
      aes(x = x_mid, ymin = ci_lo, ymax = ci_hi),
      inherit.aes = FALSE,
      width = 0.02,
      color = STEP3_COLORS$actual
    ) +
    geom_point(
      data = bin_sum,
      aes(x = x_mid, y = mean_sgpc),
      inherit.aes = FALSE,
      size = 2.2,
      color = STEP3_COLORS$actual
    ) +
    labs(
      title = title,
      subtitle = subtitle,
      x = "U (prior reference percentile, 0-1)",
      y = "True SGPc"
    ) +
    theme_publication()

  save_plot_multi(
    p,
    filename,
    output_dir,
    width = PLOT_WIDTH,
    height = PLOT_HEIGHT
  )
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
plot_district_summary_grade <- function(
  summary_row,
  output_dir = "results/visualizations",
  filename = "panel_g_district_summary_grade"
) {
  stopifnot(nrow(summary_row) >= 1)
  sr <- summary_row[1, , drop = FALSE]

  labels <- c(
    sprintf("Dataset: %s", sr$dataset_id),
    sprintf("Condition: %s", sr$condition_id),
    sprintf("Subgroup: %s", sr$subgroup_id),
    sprintf("n = %s", sr$n_subgroup),
    sprintf("Regime family: %s", sr$regime_family),
    sprintf(
      "Mean SGPc (inf/true): %.1f / %.1f",
      sr$mean_sgpc_inferred,
      sr$mean_sgpc_true
    ),
    sprintf(
      "Median SGPc (inf/true): %.1f / %.1f",
      sr$median_sgpc_inferred,
      sr$median_sgpc_true
    ),
    sprintf("W1 (best/uniform): %.4f / %.4f", sr$w1_best, sr$w1_uniform),
    sprintf("W1 reduction: %.1f%%", sr$w1_reduction_pct),
    sprintf("Residual max |F_H - F_obs|: %.4f", sr$max_abs_residual),
    sprintf(
      "Median 95%% CI: [%.1f, %.1f]",
      sr$ci95_median_lo,
      sr$ci95_median_hi
    ),
    sprintf("K3/K5 buckets: %s / %s", sr$k3_assigned, sr$k5_assigned),
    sprintf(
      "K3/K5 consistency: %.3f / %.3f",
      sr$k3_consistency,
      sr$k5_consistency
    ),
    sprintf("Health: %s", sr$health),
    sprintf("Fit failure reason: %s", sr$fit_failure_reason),
    sprintf("Independence violation: %s", sr$flag_independence_violation),
    sprintf("Flags: %s", sr$quality_flags)
  )

  text_df <- data.frame(
    x = 1,
    y = rev(seq_along(labels)),
    label = labels
  )

  subtitle <- format_step3_subtitle(
    "Does this subgroup meet minimum quality checks for reporting inferred growth regime?",
    sprintf(
      "n=%s | W1 reduction=%.1f%% | 95%% CI width=%.1f | Independence violation=%s",
      format(sr$n_subgroup, big.mark = ","),
      sr$w1_reduction_pct,
      sr$ci95_width,
      ifelse(isTRUE(sr$flag_independence_violation), "yes", "no")
    )
  )

  p <- ggplot(text_df, aes(x = x, y = y, label = label)) +
    geom_text(hjust = 0, size = 3.8, family = "", color = "grey20") +
    scale_x_continuous(limits = c(1, 1.02), expand = c(0, 0)) +
    scale_y_continuous(
      limits = c(0.5, length(labels) + 0.8),
      expand = c(0, 0)
    ) +
    labs(
      title = "H. District Summary Grade (Model Health)",
      subtitle = subtitle
    ) +
    theme_void() +
    theme(
      plot.title = element_text(face = "bold", size = 14, hjust = 0),
      plot.margin = margin(15, 15, 15, 15),
      panel.border = element_rect(color = "grey80", fill = NA, linewidth = 0.6)
    )

  save_plot_multi(p, filename, output_dir, width = 10, height = 6)
  invisible(p)
}


#' Bootstrap Uncertainty for SGPc (Median or Mean)
#'
#' Histogram + density overlay of bootstrap draws with point estimate,
#' 95 pct CI, and optional true value markers.
#'
#' @param bootstrap List from bootstrap_regime() containing draws and CIs
#' @param measure Character: "median" or "mean"
#' @param true_sgpc Numeric vector of actual SGPc values (1-99). Used to
#'   compute the true median/mean as a reference line.
#' @param title Character. Plot title.
#' @param output_dir Character. Directory for saved plots.
#' @param filename Character. Base filename (no extension).
#'
#' @return The ggplot (invisible). Side effect: files saved.
#' @export
plot_bootstrap_sgpc <- function(
  bootstrap,
  measure = c("median", "mean"),
  true_sgpc = NULL,
  title = NULL,
  output_dir = "results/visualizations",
  filename = NULL
) {
  measure <- match.arg(measure)

  draws <- switch(
    measure,
    median = bootstrap$median_sgpc_draws,
    mean = bootstrap$mean_sgpc_draws
  )
  ci <- switch(
    measure,
    median = bootstrap$ci_median_sgpc,
    mean = bootstrap$ci_mean_sgpc
  )

  if (is.null(draws) || all(is.na(draws))) {
    p <- ggplot() +
      annotate(
        "text",
        x = 0.5,
        y = 0.5,
        label = paste0("No bootstrap ", measure, " SGPc draws available"),
        size = 4
      ) +
      theme_void()
    fname <- filename %||% paste0("panel_bootstrap_", measure, "_sgpc")
    save_plot_multi(
      p,
      fname,
      output_dir,
      width = PLOT_WIDTH,
      height = PLOT_HEIGHT
    )
    return(invisible(p))
  }

  valid <- draws[!is.na(draws)]
  measure_label <- paste0(
    toupper(substring(measure, 1, 1)),
    substring(measure, 2),
    " SGPc"
  )
  point_est <- switch(measure, median = median(valid), mean = mean(valid))

  if (is.null(title)) {
    title <- paste0("Bootstrap Uncertainty: ", measure_label)
  }
  fname <- filename %||% paste0("panel_bootstrap_", measure, "_sgpc")

  df <- data.frame(value = valid)

  true_val <- if (!is.null(true_sgpc) && length(true_sgpc) > 0) {
    switch(measure, median = median(true_sgpc), mean = mean(true_sgpc))
  } else {
    NULL
  }

  subtitle_stats <- sprintf(
    "Est=%.1f | 95%% CI=[%.1f, %.1f] | n_boot=%d (%d converged)",
    point_est,
    ci[1],
    ci[2],
    bootstrap$n_boot,
    bootstrap$n_converged
  )
  if (!is.null(true_val)) {
    subtitle_stats <- paste0(subtitle_stats, sprintf(" | True=%.1f", true_val))
  }
  subtitle <- format_step3_subtitle(
    "How much sampling uncertainty remains in inferred subgroup SGPc?",
    subtitle_stats
  )

  p <- ggplot(df, aes(x = value)) +
    geom_histogram(
      aes(y = after_stat(density)),
      bins = 30,
      fill = STEP3_COLORS$bootstrap,
      alpha = 0.3,
      color = "white",
      linewidth = 0.2
    ) +
    geom_density(linewidth = 0.9, color = STEP3_COLORS$bootstrap) +
    geom_vline(
      xintercept = point_est,
      linewidth = 0.8,
      color = STEP3_COLORS$point_est
    ) +
    geom_vline(
      xintercept = ci,
      linetype = "dashed",
      linewidth = 0.6,
      color = STEP3_COLORS$ci_line
    ) +
    annotate(
      "rect",
      xmin = ci[1],
      xmax = ci[2],
      ymin = -Inf,
      ymax = Inf,
      fill = STEP3_COLORS$bootstrap,
      alpha = 0.08
    )

  if (!is.null(true_val)) {
    p <- p +
      geom_vline(
        xintercept = true_val,
        linetype = "dotdash",
        linewidth = 0.8,
        color = STEP3_COLORS$true_value
      )
  }

  p <- p +
    labs(
      title = title,
      subtitle = subtitle,
      x = paste0(measure_label, " (bootstrap draws)"),
      y = "Density"
    ) +
    coord_cartesian(xlim = c(25, 75)) +
    theme_publication() +
    theme(legend.position = "none")

  save_plot_multi(
    p,
    fname,
    output_dir,
    width = PLOT_WIDTH,
    height = PLOT_HEIGHT
  )
  invisible(p)
}


#' Bootstrap Uncertainty — Combined Median and Mean SGPc
#'
#' Side-by-side density panels for both measures using patchwork.
#'
#' @param bootstrap List from bootstrap_regime()
#' @param true_sgpc Optional numeric vector of actual SGPc values (1-99)
#' @param title Character. Overall title.
#' @param output_dir Character. Directory for saved plots.
#' @param filename Character. Base filename.
#'
#' @return The patchwork composite (invisible).
#' @export
plot_bootstrap_sgpc_combined <- function(
  bootstrap,
  true_sgpc = NULL,
  title = "Bootstrap Uncertainty — SGPc",
  sampling_context = NULL,
  output_dir = "results/visualizations",
  filename = "panel_bootstrap_sgpc_combined"
) {
  p_median <- plot_bootstrap_sgpc_panel(bootstrap, "median", true_sgpc)
  p_mean <- plot_bootstrap_sgpc_panel(bootstrap, "mean", true_sgpc)

  med_ci <- bootstrap$ci_median_sgpc
  mean_ci <- bootstrap$ci_mean_sgpc
  subtitle <- format_step3_subtitle(
    "How much sampling uncertainty remains for inferred subgroup mean and median SGPc?",
    sprintf(
      "Median CI=[%.1f, %.1f] | Mean CI=[%.1f, %.1f] | n_boot=%d (%d converged)",
      med_ci[1],
      med_ci[2],
      mean_ci[1],
      mean_ci[2],
      bootstrap$n_boot,
      bootstrap$n_converged
    )
  )

  caption_theme <- if (!is.null(sampling_context)) {
    theme(
      plot.caption = element_text(
        size = 7,
        color = "grey50",
        hjust = 0,
        margin = margin(t = 6)
      )
    )
  } else {
    theme()
  }

  combined <- p_median | p_mean
  combined <- combined +
    plot_annotation(
      title = title,
      subtitle = subtitle,
      caption = sampling_context,
      theme = theme(
        plot.title = element_text(face = "bold", size = 14, hjust = 0)
      ) +
        caption_theme
    )

  save_plot_multi(
    combined,
    filename,
    output_dir,
    width = PLOT_WIDTH * 1.6,
    height = PLOT_HEIGHT
  )
  invisible(combined)
}


#' (Internal) Build a single bootstrap SGPc panel without saving
#' @keywords internal
plot_bootstrap_sgpc_panel <- function(bootstrap, measure, true_sgpc = NULL) {
  draws <- switch(
    measure,
    median = bootstrap$median_sgpc_draws,
    mean = bootstrap$mean_sgpc_draws
  )
  ci <- switch(
    measure,
    median = bootstrap$ci_median_sgpc,
    mean = bootstrap$ci_mean_sgpc
  )

  if (is.null(draws) || all(is.na(draws))) {
    return(
      ggplot() +
        annotate(
          "text",
          x = 0.5,
          y = 0.5,
          label = paste0("No ", measure, " draws"),
          size = 4
        ) +
        theme_void()
    )
  }

  valid <- draws[!is.na(draws)]
  measure_label <- paste0(
    toupper(substring(measure, 1, 1)),
    substring(measure, 2),
    " SGPc"
  )
  point_est <- switch(measure, median = median(valid), mean = mean(valid))

  true_val <- if (!is.null(true_sgpc) && length(true_sgpc) > 0) {
    switch(measure, median = median(true_sgpc), mean = mean(true_sgpc))
  } else {
    NULL
  }

  subtitle_stats <- sprintf(
    "Est=%.1f | 95%% CI=[%.1f, %.1f]",
    point_est,
    ci[1],
    ci[2]
  )
  if (!is.null(true_val)) {
    subtitle_stats <- paste0(subtitle_stats, sprintf(" | True=%.1f", true_val))
  }
  subtitle <- format_step3_subtitle(
    "What is bootstrap uncertainty for this SGPc functional?",
    subtitle_stats
  )

  df <- data.frame(value = valid)

  p <- ggplot(df, aes(x = value)) +
    geom_histogram(
      aes(y = after_stat(density)),
      bins = 25,
      fill = STEP3_COLORS$bootstrap,
      alpha = 0.3,
      color = "white",
      linewidth = 0.2
    ) +
    geom_density(linewidth = 0.8, color = STEP3_COLORS$bootstrap) +
    geom_vline(
      xintercept = point_est,
      linewidth = 0.7,
      color = STEP3_COLORS$point_est
    ) +
    geom_vline(
      xintercept = ci,
      linetype = "dashed",
      linewidth = 0.5,
      color = STEP3_COLORS$ci_line
    ) +
    annotate(
      "rect",
      xmin = ci[1],
      xmax = ci[2],
      ymin = -Inf,
      ymax = Inf,
      fill = STEP3_COLORS$bootstrap,
      alpha = 0.08
    )

  if (!is.null(true_val)) {
    p <- p +
      geom_vline(
        xintercept = true_val,
        linetype = "dotdash",
        linewidth = 0.7,
        color = STEP3_COLORS$true_value
      )
  }

  p +
    labs(
      title = measure_label,
      subtitle = subtitle,
      x = paste0(measure_label, " (draws)"),
      y = "Density"
    ) +
    coord_cartesian(xlim = c(25, 75)) +
    theme_publication(base_size = 9) +
    theme(legend.position = "none")
}


#' Plot Precision vs N Buckets (Phase B operating characteristics)
#'
#' @param precision_dt data.frame/data.table from phase_b_precision_by_n.csv
#' @param output_dir Character directory
#' @param filename Character base filename
#' @param title Character title
#'
#' @return patchwork object (invisible)
#' @export
plot_precision_vs_n <- function(
  precision_dt,
  output_dir = "results/visualizations",
  filename = "panel_d_recovery_by_size",
  title = "Recovery Precision vs Sample Size"
) {
  if (is.null(precision_dt) || nrow(precision_dt) == 0) {
    p <- ggplot() +
      annotate(
        "text",
        x = 0.5,
        y = 0.5,
        label = "No precision-by-N data available",
        size = 4
      ) +
      theme_void()
    save_plot_multi(
      p,
      filename,
      output_dir,
      width = PLOT_WIDTH,
      height = PLOT_HEIGHT
    )
    return(invisible(p))
  }

  dt <- as.data.frame(precision_dt, check.names = FALSE)
  dt <- dt[, !duplicated(names(dt)), drop = FALSE]

  pick_col <- function(primary) {
    if (primary %in% names(dt)) {
      return(primary)
    }
    alt <- grep(paste0("^", primary), names(dt), value = TRUE)
    if (length(alt) > 0) {
      return(alt[1])
    }
    NA_character_
  }

  n_col <- pick_col("n_bucket")
  ci95_col <- pick_col("median_ci_width_95")
  ci90_col <- pick_col("median_ci_width_90")
  median_mae_col <- pick_col("median_mae")
  mean_mae_col <- pick_col("mean_mae")

  needed <- c(n_col, ci95_col, ci90_col, median_mae_col, mean_mae_col)
  if (any(!is.finite(match(needed, names(dt))))) {
    p <- ggplot() +
      annotate(
        "text",
        x = 0.5,
        y = 0.5,
        label = "Missing precision-by-N columns",
        size = 4
      ) +
      theme_void()
    save_plot_multi(
      p,
      filename,
      output_dir,
      width = PLOT_WIDTH,
      height = PLOT_HEIGHT
    )
    return(invisible(p))
  }

  dt$n_bucket <- as.numeric(dt[[n_col]])
  dt$ci95 <- as.numeric(dt[[ci95_col]])
  dt$ci90 <- as.numeric(dt[[ci90_col]])
  dt$mae_median <- as.numeric(dt[[median_mae_col]])
  dt$mae_mean <- as.numeric(dt[[mean_mae_col]])
  dt <- dt[is.finite(dt$n_bucket), , drop = FALSE]
  dt <- dt[order(dt$n_bucket), , drop = FALSE]

  p_ci <- ggplot(dt, aes(x = n_bucket, y = ci95)) +
    geom_line(linewidth = 0.9, color = STEP3_COLORS$predicted) +
    geom_point(size = 2, color = STEP3_COLORS$predicted) +
    geom_line(
      aes(y = ci90),
      linewidth = 0.8,
      linetype = "dashed",
      color = STEP3_COLORS$actual
    ) +
    geom_point(aes(y = ci90), size = 1.7, color = STEP3_COLORS$actual) +
    scale_x_continuous(breaks = sort(unique(dt$n_bucket))) +
    labs(
      title = "CI Width vs N (Median SGPc)",
      x = "N bucket",
      y = "Empirical interval width",
      subtitle = format_step3_subtitle(
        "How quickly do uncertainty intervals contract as subgroup size increases?",
        "Solid=95% CI width | Dashed=90% CI width"
      )
    ) +
    theme_publication(base_size = 9)

  p_mae <- ggplot(dt, aes(x = n_bucket, y = mae_median)) +
    geom_line(linewidth = 0.9, color = STEP3_COLORS$point_est) +
    geom_point(size = 2, color = STEP3_COLORS$point_est) +
    geom_line(
      aes(y = mae_mean),
      linewidth = 0.8,
      linetype = "dashed",
      color = STEP3_COLORS$true_value
    ) +
    geom_point(aes(y = mae_mean), size = 1.7, color = STEP3_COLORS$true_value) +
    scale_x_continuous(breaks = sort(unique(dt$n_bucket))) +
    labs(
      title = "MAE vs N",
      x = "N bucket",
      y = "Absolute error (SGPc)",
      subtitle = format_step3_subtitle(
        "How does estimation error decline with subgroup size?",
        "Solid=median SGPc MAE | Dashed=mean SGPc MAE"
      )
    ) +
    theme_publication(base_size = 9)

  combined <- (p_ci | p_mae) +
    patchwork::plot_annotation(
      title = title,
      theme = theme(
        plot.title = element_text(face = "bold", size = 14, hjust = 0)
      )
    )

  save_plot_multi(combined, filename, output_dir, width = 12, height = 6)
  invisible(combined)
}


#' Sampling-Mode Precision Decomposition
#'
#' Three-panel diagnostic comparing paired vs independent cross-sectional
#' sampling modes. Directly quantifies the "linkage premium" — the additional
#' uncertainty incurred when prior and current cohorts are sampled from
#' different students (as in TIMSS/NAEP) rather than the same students.
#'
#' Panel layout:
#'   Left:  95% CI width vs N (paired vs independent curves)
#'   Centre: MAE vs N (paired vs independent curves)
#'   Right: Variance ratio = Var(independent) / Var(paired) by N bucket
#'
#' @param precision_dt data.table with columns: n_bucket, sampling_mode,
#'   median_ci_width_95, median_ci_width_90, median_mae, mean_mae.
#'   Must contain both "paired" and "independent" rows.
#' @param output_dir Character. Output directory.
#' @param filename Character. Base filename.
#' @param title Character. Overall title.
#'
#' @return The patchwork composite (invisible).
#' @export
plot_precision_decomposition <- function(
  precision_dt,
  output_dir = "results/visualizations",
  filename = "panel_d2_precision_decomposition",
  title = "Sampling-Mode Precision Decomposition: Paired vs Independent Cohorts"
) {
  if (is.null(precision_dt) || nrow(precision_dt) == 0) {
    p <- ggplot() +
      annotate(
        "text",
        x = 0.5,
        y = 0.5,
        label = "No precision-by-N data available",
        size = 4
      ) +
      theme_void()
    save_plot_multi(
      p,
      filename,
      output_dir,
      width = PLOT_WIDTH,
      height = PLOT_HEIGHT
    )
    return(invisible(p))
  }

  dt <- as.data.frame(precision_dt, check.names = FALSE)
  dt <- dt[, !duplicated(names(dt)), drop = FALSE]

  # Backward compat: add sampling_mode if missing
  if (!"sampling_mode" %in% names(dt)) {
    dt$sampling_mode <- "paired"
  }

  modes_present <- unique(dt$sampling_mode)
  if (!all(c("paired", "independent") %in% modes_present)) {
    p <- ggplot() +
      annotate(
        "text",
        x = 0.5,
        y = 0.5,
        label = paste0(
          "Need both paired and independent modes.\nPresent: ",
          paste(modes_present, collapse = ", ")
        ),
        size = 4
      ) +
      theme_void()
    save_plot_multi(
      p,
      filename,
      output_dir,
      width = PLOT_WIDTH,
      height = PLOT_HEIGHT
    )
    return(invisible(p))
  }

  pick_col <- function(primary) {
    if (primary %in% names(dt)) {
      return(primary)
    }
    alt <- grep(paste0("^", primary), names(dt), value = TRUE)
    if (length(alt) > 0) {
      return(alt[1])
    }
    NA_character_
  }

  n_col <- pick_col("n_bucket")
  ci95_col <- pick_col("median_ci_width_95")
  median_mae_col <- pick_col("median_mae")
  mean_mae_col <- pick_col("mean_mae")

  needed <- c(n_col, ci95_col, median_mae_col, mean_mae_col)
  if (any(!is.finite(match(needed, names(dt))))) {
    p <- ggplot() +
      annotate(
        "text",
        x = 0.5,
        y = 0.5,
        label = "Missing precision-by-N columns",
        size = 4
      ) +
      theme_void()
    save_plot_multi(
      p,
      filename,
      output_dir,
      width = PLOT_WIDTH,
      height = PLOT_HEIGHT
    )
    return(invisible(p))
  }

  dt$n_bucket <- as.numeric(dt[[n_col]])
  dt$ci95 <- as.numeric(dt[[ci95_col]])
  dt$mae_median <- as.numeric(dt[[median_mae_col]])
  dt$mae_mean <- as.numeric(dt[[mean_mae_col]])
  dt <- dt[is.finite(dt$n_bucket), , drop = FALSE]

  # Aggregate across pools to get median CI width and MAE per (n_bucket, sampling_mode)
  agg <- aggregate(
    cbind(ci95, mae_median, mae_mean) ~ n_bucket + sampling_mode,
    data = dt,
    FUN = median,
    na.rm = TRUE
  )
  agg <- agg[order(agg$n_bucket), ]

  mode_colors <- c(
    "paired" = STEP3_COLORS$predicted,
    "independent" = STEP3_COLORS$true_value
  )
  mode_labels <- c(
    "paired" = "Paired (same students)",
    "independent" = "Independent cohorts (TIMSS/NAEP)"
  )

  # ---- Panel 1: CI width vs N ----
  p_ci <- ggplot(
    agg,
    aes(x = n_bucket, y = ci95, color = sampling_mode, linetype = sampling_mode)
  ) +
    geom_line(linewidth = 0.9) +
    geom_point(size = 2.2) +
    scale_color_manual(values = mode_colors, labels = mode_labels) +
    scale_linetype_manual(
      values = c("paired" = "solid", "independent" = "dashed"),
      labels = mode_labels
    ) +
    scale_x_continuous(
      breaks = sort(unique(agg$n_bucket)),
      labels = scales::comma
    ) +
    labs(
      title = "95% CI Width vs N",
      subtitle = format_step3_subtitle(
        "How much wider is the CI when cohorts are independent?",
        "Median across pools"
      ),
      x = "N (students per cohort)",
      y = "Empirical 95% CI width (SGPc)",
      color = NULL,
      linetype = NULL
    ) +
    theme_publication(base_size = 9) +
    theme(legend.position = "bottom", legend.key.width = unit(1.5, "cm"))

  # ---- Panel 2: MAE vs N ----
  p_mae <- ggplot(
    agg,
    aes(
      x = n_bucket,
      y = mae_median,
      color = sampling_mode,
      linetype = sampling_mode
    )
  ) +
    geom_line(linewidth = 0.9) +
    geom_point(size = 2.2) +
    scale_color_manual(values = mode_colors, labels = mode_labels) +
    scale_linetype_manual(
      values = c("paired" = "solid", "independent" = "dashed"),
      labels = mode_labels
    ) +
    scale_x_continuous(
      breaks = sort(unique(agg$n_bucket)),
      labels = scales::comma
    ) +
    labs(
      title = "Median SGPc MAE vs N",
      subtitle = format_step3_subtitle(
        "How does median absolute error grow under independent sampling?",
        "Median across pools"
      ),
      x = "N (students per cohort)",
      y = "Median absolute error (SGPc)",
      color = NULL,
      linetype = NULL
    ) +
    theme_publication(base_size = 9) +
    theme(legend.position = "bottom", legend.key.width = unit(1.5, "cm"))

  # ---- Panel 3: Variance ratio (linkage premium) ----
  # Compute per-N-bucket variance ratio = Var(independent) / Var(paired)
  paired_agg <- agg[agg$sampling_mode == "paired", ]
  indep_agg <- agg[agg$sampling_mode == "independent", ]
  ratio_df <- merge(
    paired_agg[, c("n_bucket", "ci95")],
    indep_agg[, c("n_bucket", "ci95")],
    by = "n_bucket",
    suffixes = c("_paired", "_indep")
  )
  ratio_df$ci_ratio <- ratio_df$ci95_indep / pmax(ratio_df$ci95_paired, 0.01)

  p_ratio <- ggplot(ratio_df, aes(x = n_bucket, y = ci_ratio)) +
    geom_hline(yintercept = 1, linetype = "dotted", color = "grey50") +
    geom_line(linewidth = 0.9, color = STEP3_COLORS$residual) +
    geom_point(size = 2.5, color = STEP3_COLORS$residual) +
    geom_text(
      aes(label = sprintf("%.1fx", ci_ratio)),
      vjust = -1.2,
      size = 3.2,
      color = STEP3_COLORS$residual
    ) +
    scale_x_continuous(
      breaks = sort(unique(ratio_df$n_bucket)),
      labels = scales::comma
    ) +
    coord_cartesian(ylim = c(0, max(ratio_df$ci_ratio, na.rm = TRUE) * 1.3)) +
    labs(
      title = "Linkage Premium",
      subtitle = format_step3_subtitle(
        "CI width multiplier: independent / paired",
        "Ratio > 1 = cost of losing longitudinal linkage"
      ),
      x = "N (students per cohort)",
      y = "CI width ratio"
    ) +
    theme_publication(base_size = 9)

  combined <- (p_ci | p_mae | p_ratio) +
    patchwork::plot_annotation(
      title = title,
      subtitle = paste0(
        "Paired = same students in both cohorts (standard subsampling) | ",
        "Independent = different students (TIMSS/NAEP design)"
      ),
      theme = theme(
        plot.title = element_text(face = "bold", size = 13, hjust = 0),
        plot.subtitle = element_text(size = 9, color = "grey40", hjust = 0)
      )
    )

  save_plot_multi(combined, filename, output_dir, width = 16, height = 6.5)
  invisible(combined)
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
plot_recovery_summary <- function(
  est,
  true_sgpc = NULL,
  title = "Growth Regime Recovery Summary: ",
  output_dir = "results/visualizations",
  filename = "recovery_summary"
) {
  # --- Panel A: CDF overlay ---
  cdf_df <- data.frame(
    v = rep(est$v_grid, 2),
    cdf = c(est$F_obs, est$F_pred),
    source = rep(c("Observed", "Predicted"), each = length(est$v_grid))
  )
  cols_cdf <- c(
    "Observed" = STEP3_COLORS$observed,
    "Predicted" = STEP3_COLORS$predicted
  )
  ltys_cdf <- c("Observed" = "solid", "Predicted" = "dashed")

  pA <- ggplot(cdf_df, aes(x = v, y = cdf, color = source, linetype = source)) +
    geom_line(linewidth = 0.8) +
    scale_color_manual(values = cols_cdf) +
    scale_linetype_manual(values = ltys_cdf) +
    labs(
      title = "A. CDF Comparison",
      subtitle = format_step3_subtitle(
        "Does predicted CDF align with observed CDF across v?",
        sprintf(
          "W1=%.4f | CvM=%.6f",
          est$all_distances$wasserstein1,
          est$all_distances$cramer_von_mises
        )
      ),
      x = "v",
      y = "CDF",
      color = NULL,
      linetype = NULL
    ) +
    theme_publication(base_size = 9) +
    theme(legend.position = c(0.80, 0.15))

  # --- Panel B: Regime density ---
  p_grid <- seq(0.01, 0.99, length.out = 200)
  inferred_d <- est$regime$density(p_grid)
  df_B <- data.frame(
    sgpc = p_grid * 100,
    density = inferred_d,
    source = "Inferred"
  )

  if (!is.null(true_sgpc)) {
    kd <- density(true_sgpc / 100, from = 0.01, to = 0.99, bw = "SJ", n = 200)
    df_B <- rbind(
      df_B,
      data.frame(sgpc = kd$x * 100, density = kd$y, source = "Actual")
    )
  }
  cols_B <- c(
    "Inferred" = STEP3_COLORS$inferred,
    "Actual" = STEP3_COLORS$actual
  )

  pB <- ggplot(df_B, aes(x = sgpc, y = density, color = source)) +
    geom_line(linewidth = 0.8) +
    geom_vline(
      xintercept = est$regime$mean * 100,
      linetype = "dotdash",
      color = STEP3_COLORS$inferred,
      linewidth = 0.5
    ) +
    geom_vline(
      xintercept = est$regime$median * 100,
      linetype = "dashed",
      color = STEP3_COLORS$inferred,
      linewidth = 0.5
    ) +
    scale_color_manual(values = cols_B) +
    labs(
      title = "B. Regime Shape",
      subtitle = format_step3_subtitle(
        "Is the recovered latent regime shape plausible relative to truth?",
        sprintf(
          "Inferred mean=%.1f | Inferred median=%.1f",
          est$regime$mean * 100,
          est$regime$median * 100
        )
      ),
      x = "SGPc",
      y = "Density",
      color = NULL
    ) +
    theme_publication(base_size = 9) +
    theme(legend.position = c(0.80, 0.85))

  if (!is.null(true_sgpc)) {
    pB <- pB +
      geom_vline(
        xintercept = mean(true_sgpc),
        linetype = "dotdash",
        color = STEP3_COLORS$actual,
        linewidth = 0.5
      ) +
      geom_vline(
        xintercept = median(true_sgpc),
        linetype = "dashed",
        color = STEP3_COLORS$actual,
        linewidth = 0.5
      )
  }

  # --- Panel C: Q-Q plot ---
  n_qq <- min(99, length(est$v_grid))
  probs <- seq(0.01, 0.99, length.out = n_qq)
  q_obs <- quantile(est$F_obs, probs = probs, type = 1)
  q_pred <- quantile(est$F_pred, probs = probs, type = 1)
  qq_df <- data.frame(observed = q_obs, predicted = q_pred)

  qq_rmse <- sqrt(mean((qq_df$predicted - qq_df$observed)^2, na.rm = TRUE))
  pC <- ggplot(qq_df, aes(x = observed, y = predicted)) +
    geom_point(size = 1, alpha = 0.6, color = STEP3_COLORS$point_est) +
    geom_abline(
      slope = 1,
      intercept = 0,
      linetype = "dashed",
      color = "grey50"
    ) +
    labs(
      title = "C. QQ Plot",
      subtitle = format_step3_subtitle(
        "Where do predicted and observed quantiles deviate from identity?",
        sprintf("QQ RMSE=%.4f", qq_rmse)
      ),
      x = "Observed quantiles",
      y = "Predicted quantiles"
    ) +
    theme_publication(base_size = 9)

  # --- Panel D: Objective surface heatmap (mirrors plot_objective_surface) ---
  gs <- est$grid_search
  m_col <- if ("m" %in% names(gs)) {
    "m"
  } else if ("regime_param_1" %in% names(gs)) {
    "regime_param_1"
  } else {
    "theta1"
  }
  k_col <- if ("kappa" %in% names(gs)) {
    "kappa"
  } else if ("regime_param_2" %in% names(gs)) {
    "regime_param_2"
  } else {
    "theta2"
  }

  if (
    !is.null(gs) && nrow(gs) > 0 && m_col %in% names(gs) && k_col %in% names(gs)
  ) {
    gs_plot <- gs[is.finite(gs$distance), ]
  } else {
    gs_plot <- data.frame()
  }

  if (nrow(gs_plot) > 0) {
    gs_plot$log10_kappa <- log10(as.numeric(gs_plot[[k_col]]))
    gs_plot$distance_log10 <- log10(pmax(gs_plot$distance, 1e-12))
    uniform_pt <- data.frame(m = 0.5, log10_kappa = log10(2), label = "U(0,1)")
    optimum_pt <- data.frame(
      m = est$m_hat,
      log10_kappa = log10(est$kappa_hat),
      label = "hat(H)[S]"
    )
    min_w1 <- min(gs_plot$distance, na.rm = TRUE)

    pD <- ggplot(
      gs_plot,
      aes(
        x = .data[[m_col]],
        y = .data[["log10_kappa"]],
        fill = .data[["distance_log10"]]
      )
    ) +
      geom_tile() +
      scale_fill_gradientn(
        colours = c("#FCFCF4", "#E2E4C8", "#B7BA87", "#8A9048"),
        guide = "none"
      ) +
      geom_text(
        data = optimum_pt,
        aes(x = m, y = log10_kappa, label = label),
        inherit.aes = FALSE,
        parse = TRUE,
        size = 2.5,
        hjust = 0.5,
        vjust = 0.5,
        color = "black"
      ) +
      geom_text(
        data = uniform_pt,
        aes(x = m, y = log10_kappa, label = label),
        inherit.aes = FALSE,
        size = 2.5,
        hjust = 0.5,
        vjust = 0.5,
        color = "grey35"
      ) +
      annotate(
        "text",
        x = 0.6,
        y = 2,
        label = "Color = log10 distance",
        hjust = 0,
        vjust = 0.5,
        size = 2.5,
        color = "grey25"
      ) +
      labs(
        title = "D. Growth Regime Surface",
        subtitle = format_step3_subtitle(
          "Which (m, kappa) combination minimizes Wasserstein-1 mismatch?",
          sprintf(
            "Best m=%.3f | Best kappa=%.2f | Min W1=%.5f",
            est$m_hat,
            est$kappa_hat,
            min_w1
          )
        ),
        x = "m (mean SGPc on 0-1 scale)",
        y = expression(log[10](kappa))
      ) +
      theme_publication(base_size = 9)
  } else {
    pD <- ggplot() +
      annotate(
        "text",
        x = 0.5,
        y = 0.5,
        label = "Grid search data\nnot available",
        size = 4
      ) +
      theme_void()
  }

  combined <- (pA | pB) /
    (pC | pD) +
    plot_annotation(
      title = title,
      theme = theme(
        plot.title = element_text(face = "bold", size = 14, hjust = 0)
      )
    )

  save_plot_multi(
    combined,
    filename,
    output_dir,
    width = PLOT_WIDTH,
    height = 9
  )

  invisible(combined)
}


#' Phase A Linkage Premium Decomposition
#'
#' Overlays paired and independent bootstrap distributions to visualise the
#' linkage premium — the multiplicative CI inflation when moving from
#' longitudinal pairing to cross-sectional (independent cohort) sampling.
#'
#' Two-panel patchwork layout:
#'   Left:  Median SGPc bootstrap densities (paired vs independent)
#'   Right: Mean SGPc bootstrap densities (paired vs independent)
#'
#' @param boot_independent List from bootstrap_regime(pairing="independent")
#' @param boot_paired List from bootstrap_regime(pairing="paired")
#' @param true_sgpc Optional numeric vector of true SGPc values
#' @param linkage_premium Optional list with pre-computed linkage premium stats
#' @param title Character. Overall title.
#' @param output_dir Character.
#' @param filename Character.
#'
#' @return The patchwork composite (invisible).
#' @export
plot_linkage_decomposition <- function(
  boot_independent,
  boot_paired,
  true_sgpc = NULL,
  linkage_premium = NULL,
  title = "Linkage Premium Decomposition",
  sampling_context = NULL,
  output_dir = "results/visualizations",
  filename = "phasea_03f_linkage_decomposition"
) {
  # Helper: build one density panel for a given measure
  .build_panel <- function(measure) {
    draws_i <- switch(
      measure,
      median = boot_independent$median_sgpc_draws,
      mean = boot_independent$mean_sgpc_draws
    )
    draws_p <- switch(
      measure,
      median = boot_paired$median_sgpc_draws,
      mean = boot_paired$mean_sgpc_draws
    )
    ci_i <- switch(
      measure,
      median = boot_independent$ci_median_sgpc,
      mean = boot_independent$ci_mean_sgpc
    )
    ci_p <- switch(
      measure,
      median = boot_paired$ci_median_sgpc,
      mean = boot_paired$ci_mean_sgpc
    )

    valid_i <- draws_i[!is.na(draws_i)]
    valid_p <- draws_p[!is.na(draws_p)]
    if (length(valid_i) < 3 || length(valid_p) < 3) {
      return(
        ggplot() +
          annotate(
            "text",
            x = 0.5,
            y = 0.5,
            label = paste0("Insufficient ", measure, " draws"),
            size = 4
          ) +
          theme_void()
      )
    }

    measure_label <- paste0(
      toupper(substring(measure, 1, 1)),
      substring(measure, 2),
      " SGPc"
    )
    ci_w_i <- round(diff(as.numeric(ci_i)), 1)
    ci_w_p <- round(diff(as.numeric(ci_p)), 1)
    ratio <- if (ci_w_p > 0) round(ci_w_i / ci_w_p, 1) else NA

    df <- rbind(
      data.frame(
        value = valid_i,
        mode = "Independent\n(TIMSS/NAEP)",
        stringsAsFactors = FALSE
      ),
      data.frame(
        value = valid_p,
        mode = "Paired\n(longitudinal)",
        stringsAsFactors = FALSE
      )
    )

    true_val <- if (!is.null(true_sgpc) && length(true_sgpc) > 0) {
      switch(measure, median = median(true_sgpc), mean = mean(true_sgpc))
    } else {
      NULL
    }

    subtitle <- paste0(
      "Paired CI=[",
      round(ci_p[1], 1),
      ", ",
      round(ci_p[2], 1),
      "] (w=",
      ci_w_p,
      ") | Independent CI=[",
      round(ci_i[1], 1),
      ", ",
      round(ci_i[2], 1),
      "] (w=",
      ci_w_i,
      ")",
      if (!is.na(ratio)) paste0(" | Ratio: ", ratio, "x") else ""
    )

    p <- ggplot(df, aes(x = value, fill = mode, color = mode)) +
      geom_density(alpha = 0.25, linewidth = 0.8) +
      # Paired CI band
      annotate(
        "rect",
        xmin = ci_p[1],
        xmax = ci_p[2],
        ymin = -Inf,
        ymax = Inf,
        fill = STEP3_COLORS$predicted,
        alpha = 0.06
      ) +
      # Independent CI band
      annotate(
        "rect",
        xmin = ci_i[1],
        xmax = ci_i[2],
        ymin = -Inf,
        ymax = Inf,
        fill = STEP3_COLORS$true_value,
        alpha = 0.06
      ) +
      # CI boundary lines
      geom_vline(
        xintercept = as.numeric(ci_p),
        linetype = "dashed",
        linewidth = 0.5,
        color = STEP3_COLORS$predicted
      ) +
      geom_vline(
        xintercept = as.numeric(ci_i),
        linetype = "dashed",
        linewidth = 0.5,
        color = STEP3_COLORS$true_value
      ) +
      scale_fill_manual(
        values = c(
          "Independent\n(TIMSS/NAEP)" = STEP3_COLORS$true_value,
          "Paired\n(longitudinal)" = STEP3_COLORS$predicted
        )
      ) +
      scale_color_manual(
        values = c(
          "Independent\n(TIMSS/NAEP)" = STEP3_COLORS$true_value,
          "Paired\n(longitudinal)" = STEP3_COLORS$predicted
        )
      )

    if (!is.null(true_val)) {
      p <- p +
        geom_vline(
          xintercept = true_val,
          linetype = "dotdash",
          linewidth = 0.7,
          color = STEP3_COLORS$residual
        )
    }

    p +
      labs(
        title = measure_label,
        subtitle = subtitle,
        x = paste0(measure_label, " (bootstrap draws)"),
        y = "Density"
      ) +
      coord_cartesian(xlim = c(25, 75)) +
      theme_publication(base_size = 9) +
      theme(legend.position = "bottom", legend.title = element_blank())
  }

  p_median <- .build_panel("median")
  p_mean <- .build_panel("mean")

  # Summary statistics for annotation
  n_obs <- if (!is.null(linkage_premium)) linkage_premium$n_observed else "?"
  lp_med <- if (!is.null(linkage_premium)) {
    linkage_premium$median$ci_ratio
  } else {
    "?"
  }
  lp_mean <- if (!is.null(linkage_premium)) {
    linkage_premium$mean$ci_ratio
  } else {
    "?"
  }

  subtitle <- format_step3_subtitle(
    paste0(
      "At N=",
      format(n_obs, big.mark = ","),
      ": how much wider is the CI when prior/current cohorts are different students?"
    ),
    paste0(
      "Linkage premium (CI ratio): median=",
      lp_med,
      "x | mean=",
      lp_mean,
      "x"
    )
  )

  caption_theme <- if (!is.null(sampling_context)) {
    theme(
      plot.caption = element_text(
        size = 7,
        color = "grey50",
        hjust = 0,
        margin = margin(t = 6)
      )
    )
  } else {
    theme()
  }

  combined <- p_median | p_mean
  combined <- combined +
    plot_annotation(
      title = title,
      subtitle = subtitle,
      caption = sampling_context,
      theme = theme(
        plot.title = element_text(face = "bold", size = 14, hjust = 0),
        plot.subtitle = element_text(size = 10, hjust = 0, color = "grey40")
      ) +
        caption_theme
    )

  save_plot_multi(
    combined,
    filename,
    output_dir,
    width = PLOT_WIDTH * 1.6,
    height = PLOT_HEIGHT + 0.5
  )
  invisible(combined)
}


cat("STEP 3 diagnostics_plots.R loaded.\n")
############################################################################
### Copula Comparison Panel
###
### Side-by-side comparison of regime estimation under two copula choices:
### canonical (pooled) vs per-condition best-fit parametric.
### Generated by run_deep_dive.R in copula$mode = "comparison".
############################################################################

#' Copula Sensitivity Comparison Panel
#'
#' Produces a 2×2 panel:
#'   Top-left:  CDF overlay (canonical)     Top-right:  CDF overlay (best-fit)
#'   Bottom-left: Regime density (canonical) Bottom-right: Regime density (best-fit)
#' with a shared subtitle showing the copula sensitivity deltas.
#'
#' @param primary_est  Result list from estimate_regime() under canonical copula.
#' @param alt_est      Result list from estimate_regime() under best-fit copula.
#' @param true_sgpc    Numeric vector of ground-truth SGPc values.
#' @param primary_label Character label for the canonical copula.
#' @param alt_label     Character label for the best-fit copula.
#' @param sensitivity   List from copula_sensitivity with delta summaries.
#' @param title         Overall plot title.
#' @param output_dir    Directory for saving.
#' @param filename      Base filename (without extension).
plot_copula_comparison_panel <- function(
  primary_est,
  alt_est,
  true_sgpc = NULL,
  primary_label = "Canonical",
  alt_label = "Best-fit parametric",
  sensitivity = NULL,
  title = "Copula Sensitivity",
  output_dir = "results/visualizations",
  filename = "copula_comparison_panel"
) {
  # --- Panel A: CDF overlay (primary / canonical) ---
  cdf_primary <- data.frame(
    v = rep(primary_est$v_grid, 2),
    cdf = c(primary_est$F_obs, primary_est$F_pred),
    source = rep(c("Observed", "Predicted"), each = length(primary_est$v_grid))
  )
  pA <- ggplot(
    cdf_primary,
    aes(x = v, y = cdf, color = source, linetype = source)
  ) +
    geom_line(linewidth = 0.8) +
    scale_color_manual(
      values = c(
        "Observed" = STEP3_COLORS$observed,
        "Predicted" = STEP3_COLORS$predicted
      )
    ) +
    scale_linetype_manual(
      values = c("Observed" = "solid", "Predicted" = "dashed")
    ) +
    labs(
      title = primary_label,
      subtitle = sprintf(
        "W1=%.4f  CvM=%.6f",
        primary_est$all_distances$wasserstein1,
        primary_est$all_distances$cramer_von_mises
      ),
      x = "v (current percentile)",
      y = "CDF"
    ) +
    theme_publication() +
    theme(
      legend.position = "bottom",
      legend.title = element_blank(),
      plot.title = element_text(size = 10)
    )

  # --- Panel B: CDF overlay (alternative / best-fit) ---
  cdf_alt <- data.frame(
    v = rep(alt_est$v_grid, 2),
    cdf = c(alt_est$F_obs, alt_est$F_pred),
    source = rep(c("Observed", "Predicted"), each = length(alt_est$v_grid))
  )
  pB <- ggplot(
    cdf_alt,
    aes(x = v, y = cdf, color = source, linetype = source)
  ) +
    geom_line(linewidth = 0.8) +
    scale_color_manual(
      values = c(
        "Observed" = STEP3_COLORS$observed,
        "Predicted" = STEP3_COLORS$predicted
      )
    ) +
    scale_linetype_manual(
      values = c("Observed" = "solid", "Predicted" = "dashed")
    ) +
    labs(
      title = alt_label,
      subtitle = sprintf(
        "W1=%.4f  CvM=%.6f",
        alt_est$all_distances$wasserstein1,
        alt_est$all_distances$cramer_von_mises
      ),
      x = "v (current percentile)",
      y = "CDF"
    ) +
    theme_publication() +
    theme(
      legend.position = "bottom",
      legend.title = element_blank(),
      plot.title = element_text(size = 10)
    )

  # --- Panel C: Regime density (primary / canonical) ---
  p_grid <- seq(0.01, 0.99, length.out = 200)
  d_primary <- primary_est$regime$density(p_grid)
  df_regime <- data.frame(
    sgpc = rep(p_grid * 100, 2),
    density = c(d_primary, alt_est$regime$density(p_grid)),
    source = rep(c(primary_label, alt_label), each = length(p_grid))
  )

  pC <- ggplot(
    df_regime,
    aes(x = sgpc, y = density, color = source, linetype = source)
  ) +
    geom_line(linewidth = 0.9)

  # Add true SGPc kernel density if available
  if (!is.null(true_sgpc) && length(true_sgpc) > 10) {
    kd <- density(true_sgpc / 100, from = 0.01, to = 0.99, bw = "SJ", n = 200)
    df_actual <- data.frame(
      sgpc = kd$x * 100,
      density = kd$y,
      source = "Actual (truth)"
    )
    pC <- pC +
      geom_line(
        data = df_actual,
        aes(x = sgpc, y = density),
        color = STEP3_COLORS$truth %||% "grey40",
        linetype = "dotted",
        linewidth = 0.7,
        inherit.aes = FALSE
      )
  }

  pC <- pC +
    scale_color_manual(
      values = stats::setNames(
        c(STEP3_COLORS$predicted, STEP3_COLORS$alternative %||% "#E69F00"),
        c(primary_label, alt_label)
      )
    ) +
    scale_linetype_manual(
      values = stats::setNames(
        c("solid", "dashed"),
        c(primary_label, alt_label)
      )
    ) +
    labs(title = "Inferred Regime Densities", x = "SGPc", y = "Density") +
    theme_publication() +
    theme(
      legend.position = "bottom",
      legend.title = element_blank(),
      plot.title = element_text(size = 10)
    )

  # --- Panel D: Summary text box ---
  delta_txt <- if (!is.null(sensitivity)) {
    paste0(
      "Copula sensitivity delta (",
      alt_label,
      " \u2212 ",
      primary_label,
      "):\n",
      sprintf(
        "  \u0394 Median SGPc: %+.2f SGP points\n",
        sensitivity$delta_median_sgpc
      ),
      sprintf(
        "  \u0394 Mean SGPc:   %+.2f SGP points\n",
        sensitivity$delta_mean_sgpc
      ),
      sprintf(
        "\nPrimary: median=%.1f  mean=%.1f  (diff from truth: %.1f / %.1f)\n",
        sensitivity$primary_median_sgpc,
        sensitivity$primary_mean_sgpc,
        sensitivity$primary_median_diff,
        sensitivity$primary_mean_diff
      ),
      sprintf(
        "Alt:     median=%.1f  mean=%.1f  (diff from truth: %.1f / %.1f)",
        sensitivity$alt_median_sgpc,
        sensitivity$alt_mean_sgpc,
        sensitivity$alt_median_diff,
        sensitivity$alt_mean_diff
      )
    )
  } else {
    "No copula sensitivity data available."
  }
  pD <- ggplot() +
    annotate(
      "text",
      x = 0.5,
      y = 0.5,
      label = delta_txt,
      hjust = 0.5,
      vjust = 0.5,
      size = 3.2,
      family = "mono"
    ) +
    xlim(0, 1) +
    ylim(0, 1) +
    labs(title = "Copula Sensitivity Summary") +
    theme_void() +
    theme(plot.title = element_text(size = 10, hjust = 0.5))

  # --- Combine ---
  combined <- (pA | pB) /
    (pC | pD) +
    patchwork::plot_annotation(
      title = title,
      theme = theme(plot.title = element_text(size = 12, face = "bold"))
    )

  save_plot_multi(
    combined,
    filename,
    output_dir,
    width = PLOT_WIDTH * 2,
    height = PLOT_HEIGHT * 2
  )
  invisible(combined)
}


#' Plot Linkage Fraction Curve
#'
#' Shows how CI width varies as a continuous function of linkage fraction
#' (0 = fully independent, 1 = fully paired). Produces a single panel with
#' median and mean CI width curves plus the linkage premium multiplier.
#'
#' @param precision_dt data.table with columns: linkage_fraction,
#'   median_ci_width_95, mean_ci_width_95, n_bucket.
#' @param n_bucket_focus Integer. N bucket to highlight. If NULL, uses the
#'   most common n_bucket in the data.
#' @param filename Character. Base filename for saving.
#' @param output_dir Character. Directory to save into.
#' @param condition_label Optional subtitle text.
#' @return ggplot object (invisible).
plot_linkage_fraction_curve <- function(
  precision_dt,
  n_bucket_focus = NULL,
  filename = "phaseb_linkage_fraction_curve",
  output_dir = ".",
  condition_label = NULL
) {
  if (
    is.null(precision_dt) ||
      nrow(precision_dt) == 0 ||
      !"linkage_fraction" %in% names(precision_dt)
  ) {
    cat("  plot_linkage_fraction_curve: no linkage_fraction data. Skipping.\n")
    return(invisible(NULL))
  }

  dt <- data.table::copy(precision_dt)

  # Focus on a single N bucket for clearest visualisation

  if (is.null(n_bucket_focus)) {
    n_bucket_focus <- dt[, .N, by = n_bucket][which.max(N), n_bucket]
  }
  dt <- dt[n_bucket == n_bucket_focus]
  if (nrow(dt) < 2) {
    cat(
      "  plot_linkage_fraction_curve: fewer than 2 linkage fractions for N=",
      n_bucket_focus,
      ". Skipping.\n"
    )
    return(invisible(NULL))
  }

  # Aggregate across pools/conditions for each linkage_fraction
  curve_dt <- dt[,
    .(
      median_ci = mean(median_ci_width_95, na.rm = TRUE),
      mean_ci = mean(mean_ci_width_95, na.rm = TRUE),
      n_pools = .N
    ),
    by = linkage_fraction
  ][order(linkage_fraction)]

  # Compute linkage premium: CI relative to fully paired (lf=1.0)
  paired_row <- curve_dt[linkage_fraction == 1.0]
  if (
    nrow(paired_row) > 0 &&
      is.finite(paired_row$median_ci) &&
      paired_row$median_ci > 0 &&
      is.finite(paired_row$mean_ci) &&
      paired_row$mean_ci > 0
  ) {
    curve_dt[, median_premium := median_ci / paired_row$median_ci]
    curve_dt[, mean_premium := mean_ci / paired_row$mean_ci]
  }

  # Build long-form for plotting
  ci_long <- data.table::melt(
    curve_dt,
    id.vars = "linkage_fraction",
    measure.vars = c("median_ci", "mean_ci"),
    variable.name = "measure",
    value.name = "ci_width"
  )
  ci_long[,
    measure_label := fifelse(measure == "median_ci", "Median SGPc", "Mean SGPc")
  ]

  colors <- if (exists("STEP3_COLORS")) {
    c(
      "Median SGPc" = STEP3_COLORS$predicted,
      "Mean SGPc" = STEP3_COLORS$true_value
    )
  } else {
    c("Median SGPc" = "#3B9AB2", "Mean SGPc" = "#E1AF00")
  }

  p <- ggplot(
    ci_long,
    aes(x = linkage_fraction, y = ci_width, colour = measure_label)
  ) +
    geom_line(linewidth = 1.2) +
    geom_point(size = 3) +
    scale_colour_manual(values = colors) +
    scale_x_continuous(
      breaks = sort(unique(ci_long$linkage_fraction)),
      labels = function(x) sprintf("%.0f%%", x * 100),
      limits = c(-0.02, 1.02)
    ) +
    labs(
      title = paste0(
        "Linkage Fraction Curve (N = ",
        format(n_bucket_focus, big.mark = ","),
        ")"
      ),
      subtitle = format_step3_subtitle(
        "CI width as a function of cohort overlap strength",
        condition_label
      ),
      x = "Linkage Fraction (\u03bb)",
      y = "95% CI Width (SGPc points)",
      colour = "Measure"
    )

  # Apply publication theme if available
  if (exists("theme_publication", mode = "function")) {
    p <- p + theme_publication() + theme(legend.position = "bottom")
  }

  # Add premium annotation if we have the fully-paired reference
  if ("median_premium" %in% names(curve_dt)) {
    max_premium <- curve_dt[linkage_fraction == 0.0, median_premium]
    if (length(max_premium) > 0 && is.finite(max_premium)) {
      p <- p +
        annotate(
          "text",
          x = 0.0,
          y = curve_dt[linkage_fraction == 0.0, median_ci] * 1.05,
          label = sprintf("%.1f\u00d7 premium", max_premium),
          hjust = 0,
          vjust = 0,
          size = 3.5,
          fontface = "italic",
          colour = colors["Median SGPc"]
        )
    }
  }

  save_plot_multi(
    p,
    filename,
    output_dir,
    width = PLOT_WIDTH,
    height = PLOT_HEIGHT
  )
  invisible(p)
}


# ========================================================================
# Churn Diagnostic Plots
# ========================================================================

#' Plot S/L/E Churn Decomposition
#'
#' Stacked bar chart showing stayers, leavers, and entrants for both
#' the prior and current waves.  Annotated with retention rates α and β
#' and churn classification.
#'
#' @param churn_bk Output of \code{compute_churn_bookkeeping()}.
#' @param condition_label Character.  Condition label for title.
#' @param filename Character. Output filename stem.
#' @param output_dir Character.  Output directory.
#'
#' @export
plot_churn_decomposition <- function(
  churn_bk,
  condition_label = NULL,
  filename = "phasea_07a_churn_decomposition",
  output_dir = "."
) {
  cb <- churn_bk$condition
  if (is.null(cb) || nrow(cb) == 0) {
    return(invisible(NULL))
  }

  # Build long-form data for the stacked bar
  bar_dt <- data.table::data.table(
    wave = rep(c("Prior Wave", "Current Wave"), each = 2),
    group = c("Stayers", "Leavers", "Stayers", "Entrants"),
    n = c(cb$n_stayers, cb$n_leavers, cb$n_stayers, cb$n_entrants)
  )
  bar_dt[, wave := factor(wave, levels = c("Prior Wave", "Current Wave"))]
  bar_dt[, group := factor(group, levels = c("Stayers", "Leavers", "Entrants"))]

  fill_colors <- c(
    "Stayers" = "#2C7BB6",
    "Leavers" = "#D7191C",
    "Entrants" = "#FDAE61"
  )

  title_text <- "Churn Decomposition: Stayers / Leavers / Entrants"
  if (!is.null(condition_label)) {
    title_text <- paste0(title_text, "\n", condition_label)
  }

  sub_text <- sprintf(
    paste0(
      "n_S = %s  |  n_L = %s  |  n_E = %s  |  ",
      "\u03b1 = %.3f  |  \u03b2 = %.3f  |  Type: %s"
    ),
    format(cb$n_stayers, big.mark = ","),
    format(cb$n_leavers, big.mark = ","),
    format(cb$n_entrants, big.mark = ","),
    cb$alpha,
    cb$beta,
    cb$churn_type
  )

  p <- ggplot(bar_dt, aes(x = wave, y = n, fill = group)) +
    geom_col(position = "stack", width = 0.6) +
    geom_text(
      aes(label = format(n, big.mark = ",")),
      position = position_stack(vjust = 0.5),
      size = 3.5,
      color = "white",
      fontface = "bold"
    ) +
    scale_fill_manual(values = fill_colors, name = "") +
    labs(
      title = title_text,
      subtitle = sub_text,
      x = NULL,
      y = "Number of Students"
    ) +
    theme_publication() +
    theme(legend.position = "bottom")

  save_plot_multi(
    p,
    filename,
    output_dir,
    width = PLOT_WIDTH,
    height = PLOT_HEIGHT
  )
  invisible(p)
}


#' Plot Marginal Comparison: Stayer vs All-Student Distributions
#'
#' Side-by-side density plots comparing stayer-only distributions to
#' all-student distributions at both waves.  Wasserstein-1 distances
#' (Γ_U, Γ_V) annotated.  Tests compositional ignorability.
#'
#' @param marginal_comparison Output of \code{compare_marginals_stayer_vs_all()}.
#' @param condition_label Character. Condition label for title.
#' @param filename Character.  Output filename stem.
#' @param output_dir Character.  Output directory.
#'
#' @export
plot_marginal_comparison <- function(
  marginal_comparison,
  condition_label = NULL,
  filename = "phasea_07b_marginal_comparison",
  output_dir = "."
) {
  mc <- marginal_comparison
  if (is.null(mc)) {
    return(invisible(NULL))
  }

  # Prior wave densities
  prior_dt <- data.table::rbindlist(list(
    data.table::data.table(
      score = mc$prior_scores_all,
      population = "All Students"
    ),
    data.table::data.table(
      score = mc$prior_scores_stayer,
      population = "Stayers Only"
    )
  ))

  # Current wave densities
  current_dt <- data.table::rbindlist(list(
    data.table::data.table(
      score = mc$current_scores_all,
      population = "All Students"
    ),
    data.table::data.table(
      score = mc$current_scores_stayer,
      population = "Stayers Only"
    )
  ))

  pop_colors <- c("All Students" = "#D7191C", "Stayers Only" = "#2C7BB6")

  p_prior <- ggplot(
    prior_dt,
    aes(x = score, fill = population, color = population)
  ) +
    geom_density(alpha = 0.35, linewidth = 0.7) +
    scale_fill_manual(values = pop_colors) +
    scale_color_manual(values = pop_colors) +
    labs(
      title = "Prior Wave",
      subtitle = bquote(Gamma[U] == .(sprintf("%.2f", mc$gamma_prior))),
      x = "Scale Score",
      y = "Density"
    ) +
    theme_publication() +
    theme(legend.position = "bottom", legend.title = element_blank())

  p_current <- ggplot(
    current_dt,
    aes(x = score, fill = population, color = population)
  ) +
    geom_density(alpha = 0.35, linewidth = 0.7) +
    scale_fill_manual(values = pop_colors) +
    scale_color_manual(values = pop_colors) +
    labs(
      title = "Current Wave",
      subtitle = bquote(Gamma[V] == .(sprintf("%.2f", mc$gamma_current))),
      x = "Scale Score",
      y = "Density"
    ) +
    theme_publication() +
    theme(legend.position = "bottom", legend.title = element_blank())

  # Compose with patchwork
  title_text <- "Compositional Ignorability Test: Stayer vs. All-Student Marginals"
  if (!is.null(condition_label)) {
    title_text <- paste0(title_text, "\n", condition_label)
  }

  ignorable_label <- if (isTRUE(mc$compositionally_ignorable)) {
    "Compositionally ignorable (benign churn)"
  } else {
    sprintf(
      "Compositional drift detected (asymmetry ratio = %.1f)",
      mc$asymmetry_ratio %||% NA_real_
    )
  }

  combined <- (p_prior | p_current) +
    patchwork::plot_annotation(
      title = title_text,
      subtitle = ignorable_label,
      theme = theme_publication()
    )

  save_plot_multi(
    combined,
    filename,
    output_dir,
    width = PLOT_WIDTH + 2,
    height = PLOT_HEIGHT
  )
  invisible(combined)
}


#' Plot Regime Contrast: Stayer Regime vs All-Student Regime
#'
#' Overlays the inferred regime density from stayer-only data and from
#' all-student cross-sectional marginals.  Annotated with Δ_θ.
#'
#' @param regime_contrast Output of \code{estimate_regime_all_students()}.
#' @param stayer_estimate Best-fit estimate from stayer-only Phase A.
#' @param true_sgpc Optional numeric vector of true SGPc for ground truth.
#' @param condition_label Character.  Condition label for title.
#' @param filename Character.  Output filename stem.
#' @param output_dir Character.  Output directory.
#'
#' @export
plot_regime_contrast <- function(
  regime_contrast,
  stayer_estimate,
  true_sgpc = NULL,
  condition_label = NULL,
  filename = "phasea_07c_regime_contrast",
  output_dir = "."
) {
  rc <- regime_contrast
  if (is.null(rc) || is.null(rc$regime_all)) {
    return(invisible(NULL))
  }

  # Build density curves for both regimes
  x_grid <- seq(0, 1, length.out = 500)

  # Stayer regime
  stayer_regime <- stayer_estimate$regime
  stayer_density <- dbeta(
    x_grid,
    stayer_regime$params$alpha,
    stayer_regime$params$beta
  )

  # All-student regime
  all_regime <- rc$regime_all$regime
  all_density <- dbeta(x_grid, all_regime$params$alpha, all_regime$params$beta)

  density_dt <- data.table::rbindlist(list(
    data.table::data.table(
      sgpc = x_grid * 100,
      density = stayer_density,
      source = "Stayer Regime"
    ),
    data.table::data.table(
      sgpc = x_grid * 100,
      density = all_density,
      source = "All-Student Regime"
    )
  ))

  source_colors <- c(
    "Stayer Regime" = "#2C7BB6",
    "All-Student Regime" = "#D7191C"
  )

  title_text <- "Regime Contrast: Stayer vs. All-Student Inference"
  if (!is.null(condition_label)) {
    title_text <- paste0(title_text, "\n", condition_label)
  }

  sub_text <- sprintf(
    "\u0394 Median = %+.1f SGPc  |  \u0394 Mean = %+.1f SGPc",
    rc$delta_median,
    rc$delta_mean
  )

  p <- ggplot(
    density_dt,
    aes(x = sgpc, y = density, color = source, fill = source)
  ) +
    geom_line(linewidth = 1) +
    geom_area(alpha = 0.15, position = "identity") +
    scale_color_manual(values = source_colors) +
    scale_fill_manual(values = source_colors)

  # Add true distribution if available
  if (!is.null(true_sgpc) && length(true_sgpc) > 10) {
    true_dens <- density(true_sgpc, from = 0, to = 100, n = 500)
    true_dt <- data.table::data.table(sgpc = true_dens$x, density = true_dens$y)
    p <- p +
      geom_line(
        data = true_dt,
        aes(x = sgpc, y = density),
        inherit.aes = FALSE,
        color = "grey40",
        linetype = "dashed",
        linewidth = 0.8
      )
  }

  p <- p +
    labs(title = title_text, subtitle = sub_text, x = "SGPc", y = "Density") +
    theme_publication() +
    theme(legend.position = "bottom", legend.title = element_blank()) +
    coord_cartesian(xlim = c(0, 100))

  save_plot_multi(
    p,
    filename,
    output_dir,
    width = PLOT_WIDTH,
    height = PLOT_HEIGHT
  )
  invisible(p)
}


#' Plot Churn Diagnostic Summary — Composite 4-Panel Figure
#'
#' Combines the churn decomposition bar chart, marginal comparison,
#' regime contrast, and theoretical premium into a single diagnostic panel.
#'
#' @param churn_bk Churn bookkeeping output.
#' @param marginal_comparison Marginal comparison output.
#' @param regime_contrast Regime contrast output.
#' @param theoretical_premium Theoretical premium output.
#' @param stayer_estimate Best-fit estimate from stayer data.
#' @param empirical_premium List with empirical linkage premium.
#' @param true_sgpc Optional true SGPc vector.
#' @param condition_label Condition label for title.
#' @param filename Output filename stem.
#' @param output_dir Output directory.
#'
#' @export
plot_churn_summary_panel <- function(
  churn_bk,
  marginal_comparison,
  regime_contrast,
  theoretical_premium = NULL,
  stayer_estimate = NULL,
  empirical_premium = NULL,
  true_sgpc = NULL,
  condition_label = NULL,
  filename = "phasea_07d_churn_summary_panel",
  output_dir = "."
) {
  # Panel 1: Churn decomposition bar
  cb <- churn_bk$condition
  bar_dt <- data.table::data.table(
    wave = rep(c("Prior Wave", "Current Wave"), each = 2),
    group = c("Stayers", "Leavers", "Stayers", "Entrants"),
    n = c(cb$n_stayers, cb$n_leavers, cb$n_stayers, cb$n_entrants)
  )
  bar_dt[, wave := factor(wave, levels = c("Prior Wave", "Current Wave"))]
  bar_dt[, group := factor(group, levels = c("Stayers", "Leavers", "Entrants"))]
  fill_colors <- c(
    "Stayers" = "#2C7BB6",
    "Leavers" = "#D7191C",
    "Entrants" = "#FDAE61"
  )

  p1 <- ggplot(bar_dt, aes(x = wave, y = n, fill = group)) +
    geom_col(position = "stack", width = 0.6) +
    geom_text(
      aes(label = format(n, big.mark = ",")),
      position = position_stack(vjust = 0.5),
      size = 2.8,
      color = "white",
      fontface = "bold"
    ) +
    scale_fill_manual(values = fill_colors, name = "") +
    labs(
      title = sprintf(
        "A. Churn (\u03b1=%.2f, \u03b2=%.2f, %s)",
        cb$alpha,
        cb$beta,
        cb$churn_type
      ),
      x = NULL,
      y = "n"
    ) +
    theme_publication() +
    theme(legend.position = "bottom", plot.title = element_text(size = 10))

  # Panel 2: Marginal comparison (prior densities)
  mc <- marginal_comparison
  panels <- list(p1)

  if (!is.null(mc)) {
    prior_dt <- data.table::rbindlist(list(
      data.table::data.table(score = mc$prior_scores_all, pop = "All"),
      data.table::data.table(score = mc$prior_scores_stayer, pop = "Stayers")
    ))
    current_dt <- data.table::rbindlist(list(
      data.table::data.table(score = mc$current_scores_all, pop = "All"),
      data.table::data.table(score = mc$current_scores_stayer, pop = "Stayers")
    ))
    pop_cols <- c("All" = "#D7191C", "Stayers" = "#2C7BB6")

    p2 <- ggplot(current_dt, aes(x = score, fill = pop, color = pop)) +
      geom_density(alpha = 0.3, linewidth = 0.5) +
      scale_fill_manual(values = pop_cols) +
      scale_color_manual(values = pop_cols) +
      labs(
        title = sprintf(
          "B. Current Marginals (\u0393_V=%.1f)",
          mc$gamma_current
        ),
        x = "Score",
        y = "Density"
      ) +
      theme_publication() +
      theme(
        legend.position = "bottom",
        legend.title = element_blank(),
        plot.title = element_text(size = 10)
      )
    panels[[2]] <- p2
  }

  # Panel 3: Regime contrast
  if (
    !is.null(regime_contrast) &&
      !is.null(regime_contrast$regime_all) &&
      !is.null(stayer_estimate)
  ) {
    x_grid <- seq(0, 1, length.out = 300)
    sr <- stayer_estimate$regime
    ar <- regime_contrast$regime_all$regime
    dens_dt <- data.table::rbindlist(list(
      data.table::data.table(
        sgpc = x_grid * 100,
        d = dbeta(x_grid, sr$params$alpha, sr$params$beta),
        src = "Stayer"
      ),
      data.table::data.table(
        sgpc = x_grid * 100,
        d = dbeta(x_grid, ar$params$alpha, ar$params$beta),
        src = "All"
      )
    ))
    src_cols <- c("Stayer" = "#2C7BB6", "All" = "#D7191C")
    p3 <- ggplot(dens_dt, aes(x = sgpc, y = d, color = src)) +
      geom_line(linewidth = 0.8) +
      scale_color_manual(values = src_cols) +
      labs(
        title = sprintf(
          "C. Regime Contrast (\u0394 Median=%+.1f)",
          regime_contrast$delta_median
        ),
        x = "SGPc",
        y = "Density"
      ) +
      theme_publication() +
      theme(
        legend.position = "bottom",
        legend.title = element_blank(),
        plot.title = element_text(size = 10)
      ) +
      coord_cartesian(xlim = c(0, 100))
    panels[[length(panels) + 1]] <- p3
  }

  # Panel 4: Premium comparison (theoretical vs empirical)
  if (!is.null(theoretical_premium) && !is.null(empirical_premium)) {
    prem_dt <- data.table::data.table(
      type = c(
        "Empirical\n(bootstrap)",
        "Theoretical\n(mean-scale)",
        "Theoretical\n(CDF-scale)"
      ),
      value = c(
        empirical_premium$median$ci_ratio %||% NA_real_,
        theoretical_premium$mean_scale,
        theoretical_premium$cdf_scale
      )
    )
    prem_dt <- prem_dt[is.finite(value)]
    if (nrow(prem_dt) > 0) {
      p4 <- ggplot(prem_dt, aes(x = type, y = value)) +
        geom_col(fill = "#2C7BB6", width = 0.5) +
        geom_hline(yintercept = 1.0, linetype = "dashed", color = "grey50") +
        geom_text(
          aes(label = sprintf("%.2f", value)),
          vjust = -0.3,
          size = 3.2
        ) +
        labs(
          title = "D. Linkage Premium (empirical vs theoretical)",
          x = NULL,
          y = "SE Multiplier"
        ) +
        theme_publication() +
        theme(plot.title = element_text(size = 10))
      panels[[length(panels) + 1]] <- p4
    }
  }

  # Compose
  n_panels <- length(panels)
  if (n_panels == 1) {
    combined <- panels[[1]]
  } else if (n_panels == 2) {
    combined <- panels[[1]] | panels[[2]]
  } else if (n_panels == 3) {
    combined <- (panels[[1]] | panels[[2]]) / panels[[3]]
  } else {
    combined <- (panels[[1]] | panels[[2]]) / (panels[[3]] | panels[[4]])
  }

  suptitle <- "Churn Diagnostic Summary"
  if (!is.null(condition_label)) {
    suptitle <- paste0(suptitle, ": ", condition_label)
  }

  combined <- combined +
    patchwork::plot_annotation(
      title = suptitle,
      theme = theme_publication()
    )

  save_plot_multi(
    combined,
    filename,
    output_dir,
    width = PLOT_WIDTH + 2,
    height = PLOT_HEIGHT + 3
  )
  invisible(combined)
}


cat(
  "  Helpers: format_step3_subtitle, format_p_value, format_step3_condition_label\n"
)
cat("  Functions: plot_observed_vs_predicted_cdf, plot_regime_shape,\n")
cat("             plot_residual_curve, plot_objective_surface,\n")
cat("             plot_marginal_uv_density, plot_independence_diagnostic,\n")
cat("             plot_bootstrap_sgpc, plot_bootstrap_sgpc_combined,\n")
cat("             plot_linkage_decomposition, plot_linkage_fraction_curve,\n")
cat("             plot_copula_comparison_panel,\n")
cat("             plot_precision_vs_n, plot_precision_decomposition,\n")
cat("             plot_district_summary_grade, plot_recovery_summary,\n")
cat("             plot_churn_decomposition, plot_marginal_comparison,\n")
cat("             plot_regime_contrast, plot_churn_summary_panel\n")
