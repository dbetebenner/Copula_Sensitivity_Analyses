###############################################################################
###
### STEP 3 Analytic Explanation (Synthetic, Horizontal Infographic)
###
### Purpose:
###   Create a single wide mathematical infographic that explains how STEP 3
###   infers a latent growth regime H_S from unlinked cross-sectional
###   pseudo-observations (U sample, V sample).
###
### Figure flow (left -> right):
###   A) Observe unlinked U and V marginals
###   B) Forward check under random-uniform regime vs observed V CDF
###   C) Reverse-engineer regime parameters by minimizing distance
###   D) Recovered growth regime H_S
###
### Outputs are written to:
###   STEP_3_LIwLD/Figures/Analytic_Explanation/outputs/
###
### Usage:
###   source("STEP_3_LIwLD/Figures/Analytic_Explanation/step3_analytic_explanation.R")
###
###############################################################################

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
STEP3_ANALYTIC_EXPLANATION_CONFIG <- list(
  seed = 20260211,
  n_students = 3500L,          # "several thousand" synthetic students
  true_regime_mean = 0.39,     # low-growth synthetic target (mean SGPc ~39)
  true_regime_kappa = 18,      # concentration of latent growth regime
  copula_rho = 0.72,
  copula_df = 8,
  u_alpha = 2.8,               # prior-score percentile distribution shape
  u_beta = 2.4,
  boundary_buffer = 0.005,
  kernel_grid_size = 201L,
  v_grid_size = 301L,
  optimizer_grid_resolution = 16L,
  output_basename = "step3_growth_regime_analytic_infographic",
  figure_width = 16,           # >= 2x height (horizontal infographic)
  figure_height = 7,
  base_cex = 1.08,             # readability scaling for panel text
  line_width = 2.3
)


# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------
.locate_script_dir <- function() {
  script_dir <- tryCatch({
    normalizePath(dirname(sys.frame(1)$ofile), winslash = "/", mustWork = TRUE)
  }, error = function(e) {
    normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  })

  if (!file.exists(file.path(script_dir, "step3_analytic_explanation.R"))) {
    candidate <- file.path(script_dir, "STEP_3_LIwLD", "Figures", "Analytic_Explanation")
    if (file.exists(file.path(candidate, "step3_analytic_explanation.R"))) {
      script_dir <- normalizePath(candidate, winslash = "/", mustWork = TRUE)
    }
  }

  script_dir
}

# ---------------------------------------------------------------------------
# STEP 3 publication-aligned colours (Zissou anchors)
# ---------------------------------------------------------------------------
STEP3_FIG_COLORS <- list(
  prior = "#3B9AB2",          # Zissou teal
  current = "#F21A00",        # Zissou red
  observed = "black",
  uniform = "grey55",
  inferred = "#3B9AB2",
  truth = "#E1AF00",          # Zissou amber
  contour = adjustcolor("white", alpha.f = 0.45),
  border = "grey85",
  subtitle = "grey30",
  body = "grey25"
)


# ---------------------------------------------------------------------------
# Main builder
# ---------------------------------------------------------------------------
run_step3_analytic_explanation <- function(cfg = STEP3_ANALYTIC_EXPLANATION_CONFIG,
                                           verbose = TRUE) {

  script_dir <- .locate_script_dir()
  step3_dir <- normalizePath(file.path(script_dir, "..", ".."), winslash = "/", mustWork = TRUE)
  project_root <- normalizePath(file.path(step3_dir, ".."), winslash = "/", mustWork = TRUE)
  output_dir <- file.path(script_dir, "outputs")
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  if (verbose) {
    cat("\nSTEP 3 analytic explanation build started...\n")
    cat("  script_dir :", script_dir, "\n")
    cat("  step3_dir  :", step3_dir, "\n")
    cat("  output_dir :", output_dir, "\n")
  }

  # -------------------------------------------------------------------------
  # Load required functions from STEP 3 + shared exporter
  # -------------------------------------------------------------------------
  required_sources <- c(
    file.path(step3_dir, "functions", "copula_kernel_cache.R"),
    file.path(step3_dir, "functions", "regime_families.R"),
    file.path(step3_dir, "functions", "predict_v_cdf.R"),
    file.path(step3_dir, "functions", "distance_metrics.R"),
    file.path(step3_dir, "functions", "optimize_regime.R"),
    file.path(project_root, "functions", "export_plot_utils.R")
  )

  for (src in required_sources) {
    if (!file.exists(src)) stop("Required source file missing: ", src)
    source(src)
  }

  if (!requireNamespace("copula", quietly = TRUE)) {
    stop("Package 'copula' is required. Install with install.packages('copula').")
  }

  # Local kernel builder to avoid dimension dropping from pmin/pmax in the
  # shared helper when running this standalone explanation script.
  .create_kernel_cache_safe <- function(copula_obj,
                                        u_grid_size = 201L,
                                        v_grid_size = 201L,
                                        boundary_buffer = 0.005,
                                        compute_quantile = TRUE) {
    u_grid <- seq(boundary_buffer, 1 - boundary_buffer, length.out = u_grid_size)
    v_grid <- seq(boundary_buffer, 1 - boundary_buffer, length.out = v_grid_size)

    uv_pairs <- as.matrix(expand.grid(u = u_grid, v = v_grid))
    cond_vec <- as.vector(copula::cCopula(uv_pairs, copula = copula_obj, indices = 2))

    conditional_cdf <- matrix(cond_vec, nrow = u_grid_size, ncol = v_grid_size, byrow = FALSE)
    conditional_cdf[conditional_cdf < 0] <- 0
    conditional_cdf[conditional_cdf > 1] <- 1

    for (i in seq_len(u_grid_size)) {
      conditional_cdf[i, ] <- cummax(conditional_cdf[i, ])
    }

    quantile_grid <- NULL
    p_grid <- NULL

    if (isTRUE(compute_quantile)) {
      p_grid <- seq(boundary_buffer, 1 - boundary_buffer, length.out = v_grid_size)
      quantile_grid <- matrix(NA_real_, nrow = u_grid_size, ncol = length(p_grid))

      for (i in seq_len(u_grid_size)) {
        cdf_row <- conditional_cdf[i, ]
        quantile_grid[i, ] <- approx(cdf_row, v_grid, xout = p_grid, method = "linear", rule = 2)$y
      }
      quantile_grid[quantile_grid < boundary_buffer] <- boundary_buffer
      quantile_grid[quantile_grid > (1 - boundary_buffer)] <- (1 - boundary_buffer)
    }

    copula_family <- class(copula_obj)[1]
    if (inherits(copula_obj, "tCopula")) {
      copula_params <- list(rho = copula_obj@parameters[1], df = copula_obj@parameters[2])
    } else if (inherits(copula_obj, "normalCopula")) {
      copula_params <- list(rho = copula_obj@parameters[1])
    } else {
      copula_params <- list(param = copula_obj@parameters)
    }

    result <- list(
      u_grid = u_grid,
      v_grid = v_grid,
      conditional_cdf = conditional_cdf,
      quantile_grid = quantile_grid,
      p_grid = p_grid,
      u_grid_size = u_grid_size,
      v_grid_size = v_grid_size,
      boundary_buffer = boundary_buffer,
      copula_family = copula_family,
      copula_params = copula_params,
      created_at = Sys.time()
    )
    class(result) <- "kernel_cache"
    result
  }

  # -------------------------------------------------------------------------
  # 1) Build synthetic data with known low-growth regime
  # -------------------------------------------------------------------------
  set.seed(cfg$seed)

  n <- as.integer(cfg$n_students)
  u_sample <- stats::rbeta(n, shape1 = cfg$u_alpha, shape2 = cfg$u_beta)

  true_regime <- regime_beta(cfg$true_regime_mean, cfg$true_regime_kappa)
  uniform_regime <- regime_beta(0.5, 2)  # Uniform(0,1) baseline

  base_copula <- copula::tCopula(
    param = cfg$copula_rho,
    df = cfg$copula_df,
    dim = 2,
    dispstr = "un",
    df.fixed = TRUE
  )

  kernel_cache <- .create_kernel_cache_safe(
    copula_obj = base_copula,
    u_grid_size = as.integer(cfg$kernel_grid_size),
    v_grid_size = as.integer(cfg$kernel_grid_size),
    boundary_buffer = cfg$boundary_buffer,
    compute_quantile = TRUE
  )

  # Simulate latent conditional percentiles, then map to V via Q0(p|u)
  latent_p <- true_regime$quantile(stats::runif(n))
  v_linked <- kernel_conditional_quantile(p = latent_p, u = u_sample, cache = kernel_cache)

  # Mimic STEP 3 setting: we only retain independent cross-sections
  v_sample <- sample(v_linked, length(v_linked), replace = FALSE)

  # -------------------------------------------------------------------------
  # 2) Infer H_S from unlinked U and V
  # -------------------------------------------------------------------------
  v_grid <- seq(cfg$boundary_buffer, 1 - cfg$boundary_buffer, length.out = cfg$v_grid_size)

  est <- estimate_regime(
    u_sample = u_sample,
    v_sample = v_sample,
    kernel_cache = kernel_cache,
    regime_family = "beta",
    distance_fn = "wasserstein1",
    v_grid = v_grid,
    grid_resolution = as.integer(cfg$optimizer_grid_resolution),
    verbose = FALSE
  )

  F_obs <- observed_marginal_cdf(v_grid = v_grid, v_sample = v_sample)
  F_uniform <- predict_marginal_cdf(
    v_grid = v_grid,
    u_sample = u_sample,
    regime = uniform_regime,
    kernel_cache = kernel_cache
  )
  F_true <- predict_marginal_cdf(
    v_grid = v_grid,
    u_sample = u_sample,
    regime = true_regime,
    kernel_cache = kernel_cache
  )

  d_uniform <- compute_all_distances(F_uniform, F_obs, v_grid)
  d_inferred <- compute_all_distances(est$F_pred, F_obs, v_grid)
  w1_reduction_pct <- 100 * (1 - (d_inferred$wasserstein1 / d_uniform$wasserstein1))

  # -------------------------------------------------------------------------
  # 3) Save lightweight data artifacts for riffing
  # -------------------------------------------------------------------------
  summary_df <- data.frame(
    n_students = n,
    true_mean_sgpc = round(true_regime$mean * 100, 3),
    true_median_sgpc = round(true_regime$median * 100, 3),
    inferred_mean_sgpc = round(est$regime$mean * 100, 3),
    inferred_median_sgpc = round(est$regime$median * 100, 3),
    uniform_w1 = round(d_uniform$wasserstein1, 6),
    inferred_w1 = round(d_inferred$wasserstein1, 6),
    w1_reduction_pct = round(w1_reduction_pct, 2),
    copula_rho = cfg$copula_rho,
    copula_df = cfg$copula_df,
    stringsAsFactors = FALSE
  )

  summary_csv <- file.path(output_dir, paste0(cfg$output_basename, "_summary.csv"))
  utils::write.csv(summary_df, summary_csv, row.names = FALSE)

  grid_csv <- file.path(output_dir, paste0(cfg$output_basename, "_grid_search.csv"))
  utils::write.csv(est$grid_search, grid_csv, row.names = FALSE)

  data_rds <- file.path(output_dir, paste0(cfg$output_basename, "_data.rds"))
  saveRDS(
    list(
      config = cfg,
      summary = summary_df,
      u_sample = u_sample,
      v_sample = v_sample,
      v_grid = v_grid,
      F_obs = F_obs,
      F_uniform = F_uniform,
      F_true = F_true,
      est = est,
      true_regime = true_regime,
      uniform_regime = uniform_regime,
      distances = list(uniform = d_uniform, inferred = d_inferred),
      paths = list(summary_csv = summary_csv, grid_csv = grid_csv)
    ),
    file = data_rds
  )

  # -------------------------------------------------------------------------
  # 4) Build horizontal 4-panel infographic
  # -------------------------------------------------------------------------
  plot_fn <- function() {
    old_par <- par(no.readonly = TRUE)
    on.exit(par(old_par), add = TRUE)

    layout(matrix(1:4, nrow = 1), widths = c(1.15, 1.2, 1.1, 1.15))
    par(oma = c(1.25, 0.5, 4.1, 0.5), family = "sans", cex = cfg$base_cex,
        cex.main = 0.95, cex.lab = 0.94)

    # Panel A: Unlinked cross-sectional inputs
    par(mar = c(4.5, 4.6, 4.2, 0.8))
    d_u <- stats::density(u_sample, from = 0, to = 1, n = 512, bw = "SJ")
    d_v <- stats::density(v_sample, from = 0, to = 1, n = 512, bw = "SJ")
    y_max_a <- 1.20 * max(c(d_u$y, d_v$y))

    plot(d_u$x, d_u$y, type = "n", xlim = c(0, 1), ylim = c(0, y_max_a),
         xlab = "Reference percentile (u, v)",
         ylab = "Density",
         main = "A. Independent U and V")
    polygon(c(d_u$x, rev(d_u$x)), c(d_u$y, rep(0, length(d_u$y))),
            col = adjustcolor(STEP3_FIG_COLORS$prior, alpha.f = 0.20), border = NA)
    lines(d_u$x, d_u$y, lwd = cfg$line_width, col = STEP3_FIG_COLORS$prior)
    polygon(c(d_v$x, rev(d_v$x)), c(d_v$y, rep(0, length(d_v$y))),
            col = adjustcolor(STEP3_FIG_COLORS$current, alpha.f = 0.16), border = NA)
    lines(d_v$x, d_v$y, lwd = cfg$line_width, col = STEP3_FIG_COLORS$current)
    legend("topright",
           legend = c("Prior sample U", "Current sample V"),
           col = c(STEP3_FIG_COLORS$prior, STEP3_FIG_COLORS$current),
           lwd = cfg$line_width, bty = "n", cex = 0.86)
    mtext("No student-level pair IDs are available", side = 3, line = 0.3, cex = 0.80,
          col = STEP3_FIG_COLORS$subtitle)
    box(col = STEP3_FIG_COLORS$border)

    # Panel B: Forward check from random regime to observed CDF
    par(mar = c(4.5, 4.6, 4.2, 0.8))
    plot(v_grid, F_obs, type = "l", lwd = cfg$line_width, col = STEP3_FIG_COLORS$observed,
         xlim = c(0, 1), ylim = c(0, 1),
         xlab = "v (current pseudo-observation)",
         ylab = "CDF",
         main = "B. Forward check in v-space")
    lines(v_grid, F_uniform, lwd = cfg$line_width - 0.1, lty = 3, col = STEP3_FIG_COLORS$uniform)
    lines(v_grid, est$F_pred, lwd = cfg$line_width, lty = 2, col = STEP3_FIG_COLORS$inferred)
    legend("bottomright",
           legend = c("Observed F_obs(v)", "Uniform H(p)=p prediction", "Inferred H_S prediction"),
           col = c(STEP3_FIG_COLORS$observed, STEP3_FIG_COLORS$uniform, STEP3_FIG_COLORS$inferred),
           lwd = c(cfg$line_width, cfg$line_width - 0.1, cfg$line_width),
           lty = c(1, 3, 2),
           bty = "n",
           cex = 0.80)
    text(0.03, 0.96, labels = "Uniform misses.\nInference closes gap.",
         adj = c(0, 1), cex = 0.80, col = STEP3_FIG_COLORS$subtitle)
    text(0.03, 0.84, labels = "F_H(v) = E_U[ H(F_0(v | U)) ]",
         adj = c(0, 1), cex = 0.76, col = STEP3_FIG_COLORS$body)
    box(col = STEP3_FIG_COLORS$border)

    # Panel C: Reverse-engineering objective over (m, kappa)
    par(mar = c(4.5, 5.0, 4.2, 0.8))
    gs <- est$grid_search
    z_raw <- with(gs, tapply(distance, list(regime_param_2, regime_param_1), mean))
    mean_vals <- as.numeric(colnames(z_raw))
    kappa_vals <- as.numeric(rownames(z_raw))
    ord_m <- order(mean_vals)
    ord_k <- order(kappa_vals)
    mean_vals <- mean_vals[ord_m]
    kappa_vals <- kappa_vals[ord_k]
    z_raw <- z_raw[ord_k, ord_m, drop = FALSE]
    z_log <- log10(z_raw)

    image(
      x = mean_vals * 100,
      y = log10(kappa_vals),
      z = z_log,
      col = hcl.colors(90, "YlOrRd", rev = TRUE),
      xlab = "Mean of H (SGPc)",
      ylab = expression(log[10](kappa)),
      main = "C. Reverse-engineer regime",
      useRaster = TRUE
    )
    contour(
      x = mean_vals * 100,
      y = log10(kappa_vals),
      z = z_log,
      add = TRUE,
      drawlabels = FALSE,
      col = STEP3_FIG_COLORS$contour,
      lwd = 0.8
    )
    points(est$m_hat * 100, log10(est$kappa_hat),
           pch = 4, lwd = 2.2, cex = 1.2, col = "black")
    text(est$m_hat * 100, log10(est$kappa_hat),
         labels = "  optimum (m_hat, kappa_hat)", pos = 4, cex = 0.78)
    mtext("Color = log10 distance", side = 3, line = 0.2, cex = 0.72, col = "grey35")
    box(col = STEP3_FIG_COLORS$border)

    # Panel D: Inferred growth regime density
    par(mar = c(4.5, 4.6, 4.2, 0.8))
    p_grid <- seq(0.001, 0.999, length.out = 500)
    d_unif <- rep(1, length(p_grid))
    d_true <- true_regime$density(p_grid)
    d_inf <- est$regime$density(p_grid)
    y_max_d <- 1.15 * max(c(d_unif, d_true, d_inf))

    plot(p_grid * 100, d_unif, type = "l", lwd = cfg$line_width - 0.2, lty = 3, col = STEP3_FIG_COLORS$uniform,
         xlim = c(0, 100), ylim = c(0, y_max_d),
         xlab = "Latent growth percentile p (SGPc scale)",
         ylab = "Density",
         main = "D. Inferred H_S")
    polygon(c(p_grid * 100, rev(p_grid * 100)),
            c(d_inf, rep(0, length(d_inf))),
            col = adjustcolor(STEP3_FIG_COLORS$inferred, alpha.f = 0.20), border = NA)
    lines(p_grid * 100, d_inf, lwd = cfg$line_width, col = STEP3_FIG_COLORS$inferred)
    lines(p_grid * 100, d_true, lwd = cfg$line_width - 0.1, lty = 2, col = STEP3_FIG_COLORS$truth)
    abline(v = 50, lty = 3, col = "grey60")
    abline(v = true_regime$mean * 100, lty = 2, col = STEP3_FIG_COLORS$truth)
    abline(v = est$regime$mean * 100, lty = 2, col = STEP3_FIG_COLORS$inferred)
    legend("topright",
           legend = c("Uniform", "True synthetic", "Inferred"),
           col = c(STEP3_FIG_COLORS$uniform, STEP3_FIG_COLORS$truth, STEP3_FIG_COLORS$inferred),
           lty = c(3, 2, 1),
           lwd = c(cfg$line_width - 0.2, cfg$line_width - 0.1, cfg$line_width),
           bty = "n",
           cex = 0.78)
    text(2, y_max_d * 0.86,
         labels = sprintf("Recovered mean SGPc = %.1f", est$regime$mean * 100),
         adj = c(0, 1), col = STEP3_FIG_COLORS$inferred, cex = 0.78)
    box(col = STEP3_FIG_COLORS$border)

    # Outer title + subtitle + footer
    mtext(
      "STEP 3 SGPcFlow analytic explanation: from observed V to inferred growth regime",
      side = 3, outer = TRUE, line = 2.2, cex = 1.18, font = 2
    )
    mtext(
      sprintf(
        "Synthetic low-growth case (true mean SGPc %.0f), baseline t-copula kernel (rho = %.2f, df = %d)",
        true_regime$mean * 100, cfg$copula_rho, cfg$copula_df
      ),
      side = 3, outer = TRUE, line = 1.05, cex = 0.92
    )
    mtext(
      sprintf(
        "Flow A -> B -> C -> D | W1(F_obs, F_H): uniform = %.4f, inferred = %.4f (%.1f%% reduction)",
        d_uniform$wasserstein1, d_inferred$wasserstein1, w1_reduction_pct
      ),
      side = 1, outer = TRUE, line = -0.2, cex = 0.86, col = STEP3_FIG_COLORS$subtitle
    )
  }

  figure_base <- file.path(output_dir, cfg$output_basename)

  export_formats <- "pdf"
  if (requireNamespace("svglite", quietly = TRUE)) export_formats <- c(export_formats, "svg")
  if (requireNamespace("ragg", quietly = TRUE)) export_formats <- c(export_formats, "png")

  export_plot_multi_format(
    plot_expr = plot_fn,
    base_filename = figure_base,
    width = cfg$figure_width,
    height = cfg$figure_height,
    formats = export_formats,
    bg_transparent = FALSE,
    bg_color = "white",
    png_res = 220,
    png_scale = 2,
    verbose = verbose
  )

  result <- list(
    summary = summary_df,
    output_dir = output_dir,
    figure_base = figure_base,
    figure_formats = export_formats,
    data_rds = data_rds,
    summary_csv = summary_csv,
    grid_csv = grid_csv
  )

  if (verbose) {
    cat("\nSTEP 3 analytic explanation build complete.\n")
    cat("  Figure base:", figure_base, "\n")
    cat("  Data RDS   :", data_rds, "\n")
    cat("  Summary CSV:", summary_csv, "\n\n")
    print(summary_df)
    cat("\n")
  }

  invisible(result)
}


# ---------------------------------------------------------------------------
# Autorun (source-and-go)
# ---------------------------------------------------------------------------
if (isTRUE(getOption("step3.analytic_explanation.autorun", TRUE))) {
  STEP3_ANALYTIC_EXPLANATION_RESULTS <- run_step3_analytic_explanation()
}
