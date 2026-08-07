############################################################################
###
### Growth Regime Estimation (Optimizer) for STEP 3
###
### Two-stage estimation strategy:
###   Stage 1: Coarse grid search over plausible regime parameters
###   Stage 2: Local refinement via optim() (L-BFGS-B with bounds)
###
### The objective function is:
###   D(params) = distance( predict_marginal_cdf(v; params), F_obs(v) )
###
### where distance is Wasserstein-1, Cramer-von Mises, or both.
###
### Dual-metric mode ("both"):
###   Stage 1 computes F_pred once per grid point and evaluates BOTH W1
###   and CvM (negligible overhead since predict_marginal_cdf is the
###   expensive step).  Stage 2 runs optim() for each metric from its
###   own grid-best starting point.  Returns primary result in the
###   standard format plus $alt_metrics with the alternative-metric
###   optimum, enabling direct comparison within a single analysis.
###
### Author: dataimago
### Date: February 2026 (dual-metric: March 2026)
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################

#' Estimate the Growth Regime from Cross-Sectional Data
#'
#' Core estimation function. Given independent samples of prior and current
#' scores (expressed as reference percentiles) and a baseline copula kernel,
#' finds the subgroup growth regime that best predicts the observed current
#' distribution.
#'
#' @param u_sample Numeric vector. Prior-grade reference percentiles.
#' @param v_sample Numeric vector. Current-grade reference percentiles.
#' @param kernel_cache A kernel_cache object from create_kernel_cache().
#' @param regime_family Character. One of "beta", "truncexp", "truncunif".
#'   Default "beta".
#' @param distance_fn Character scalar or vector. Distance metric(s) to
#'   optimize. Accepted values: "wasserstein1", "cvm", or "both" (which
#'   expands to c("wasserstein1", "cvm")).  When a vector of length > 1,
#'   the grid search evaluates all metrics per grid point (free — the
#'   expensive predict_marginal_cdf call is shared) and Stage 2 optim is
#'   run for each metric.  The first element is the primary metric whose
#'   result is returned in the top-level fields; additional metric results
#'   are in $alt_metrics.  Default "wasserstein1".
#' @param v_grid Numeric vector. Grid for CDF evaluation. If NULL,
#'   uses seq(0.005, 0.995, length.out = 201).
#' @param u_weights Optional weights for u_sample.
#' @param v_weights Optional weights for v_sample.
#' @param grid_resolution Integer. Number of grid points per parameter
#'   dimension in coarse search. Default 30.
#' @param verbose Logical. Print progress? Default TRUE.
#' @param stratify_by_u Logical. Use stratified estimation? Default FALSE.
#' @param stratify_bins Integer. Number of U-bins for stratification.
#'
#' @return List with:
#'   \describe{
#'     \item{regime_param_hat}{Estimated parameter vector (primary metric)}
#'     \item{m_hat}{Estimated mean parameter for Beta family (if applicable)}
#'     \item{kappa_hat}{Estimated concentration for Beta family (if applicable)}
#'     \item{regime}{The estimated growth_regime object (primary metric)}
#'     \item{distance_min}{Minimum distance achieved (primary metric)}
#'     \item{distance_metric}{Which metric was used as primary}
#'     \item{convergence}{Convergence info from optim()}
#'     \item{grid_search}{data.frame of grid search results (includes columns
#'       for all evaluated metrics)}
#'     \item{F_pred}{Predicted CDF at optimum (primary metric)}
#'     \item{F_obs}{Observed CDF}
#'     \item{v_grid}{The evaluation grid used}
#'     \item{all_distances}{All distance metrics at primary optimum}
#'     \item{alt_metrics}{(present when multiple metrics optimized) Named list
#'       of full result lists, one per non-primary metric.  Each has the same
#'       fields as the top-level result (regime_param_hat, regime, distance_min,
#'       F_pred, all_distances, etc.).}
#'   }
#'
#' @export
estimate_regime <- function(
  u_sample,
  v_sample,
  kernel_cache,
  regime_family = "beta",
  distance_fn = "wasserstein1",
  v_grid = NULL,
  u_weights = NULL,
  v_weights = NULL,
  grid_resolution = 30,
  verbose = TRUE,
  stratify_by_u = FALSE,
  stratify_bins = 5
) {
  if (isTRUE(stratify_by_u)) {
    if (!exists("estimate_regime_stratified", mode = "function")) {
      stop(
        "estimate_regime_stratified() is not available; source optimize_regime_stratified.R first"
      )
    }
    return(estimate_regime_stratified(
      u_sample = u_sample,
      v_sample = v_sample,
      kernel_cache = kernel_cache,
      regime_family = regime_family,
      distance_fn = distance_fn,
      v_grid = v_grid,
      u_weights = u_weights,
      v_weights = v_weights,
      n_bins = stratify_bins,
      grid_resolution = grid_resolution,
      verbose = verbose
    ))
  }

  # Defaults
  if (is.null(v_grid)) {
    v_grid <- seq(0.005, 0.995, length.out = 201)
  }

  regime_family <- tolower(regime_family)

  # --- Resolve distance_fn into a vector of metrics to optimize -----------
  distance_fn <- tolower(distance_fn)
  if (length(distance_fn) == 1L && identical(distance_fn, "both")) {
    distance_fns <- c("wasserstein1", "cvm")
  } else {
    distance_fns <- unique(distance_fn)
  }
  primary_metric <- distance_fns[1L]
  multi_metric <- length(distance_fns) > 1L

  # Validate
  valid_metrics <- c("wasserstein1", "cvm")
  bad <- setdiff(distance_fns, valid_metrics)
  if (length(bad) > 0L) {
    stop("Unknown distance function(s): ", paste(bad, collapse = ", "))
  }

  # Compute observed CDF (once)
  F_obs <- observed_marginal_cdf(v_grid, v_sample, v_weights)

  # Helper: compute F_pred for a given parameter vector (the expensive call)
  .predict <- function(regime_params) {
    regime <- tryCatch(
      create_regime(regime_family, regime_params),
      error = function(e) NULL
    )
    if (is.null(regime)) {
      return(NULL)
    }
    predict_marginal_cdf(v_grid, u_sample, u_weights, regime, kernel_cache)
  }

  # Helper: single-metric objective for optim() Stage 2
  .make_objective <- function(metric) {
    force(metric)
    function(regime_params) {
      F_pred <- .predict(regime_params)
      if (is.null(F_pred)) {
        return(Inf)
      }
      switch(
        metric,
        wasserstein1 = wasserstein1(F_pred, F_obs, v_grid),
        cvm = cramer_von_mises(F_pred, F_obs, v_grid)
      )
    }
  }

  # ------------------------------------------------------------------
  # Stage 1: Coarse grid search — evaluate ALL requested metrics per
  # grid point, sharing the predict_marginal_cdf() call.
  # ------------------------------------------------------------------

  if (verbose) {
    metric_label <- if (multi_metric) {
      paste(distance_fns, collapse = " + ")
    } else {
      primary_metric
    }
    cat(
      "  Stage 1: Coarse grid search (",
      regime_family,
      ", metric=",
      metric_label,
      ")...\n",
      sep = ""
    )
  }

  grid_df <- .build_grid(regime_family, grid_resolution)
  param_cols <- grep("^regime_param_", names(grid_df), value = TRUE)

  # Pre-allocate distance columns
  for (m in distance_fns) {
    grid_df[[m]] <- NA_real_
  }

  if (verbose) {
    cat("    Evaluating", nrow(grid_df), "grid points...")
  }
  for (i in seq_len(nrow(grid_df))) {
    regime_params <- as.numeric(grid_df[i, param_cols])
    F_pred_i <- .predict(regime_params)
    if (is.null(F_pred_i)) {
      for (m in distance_fns) {
        grid_df[[m]][i] <- Inf
      }
    } else {
      for (m in distance_fns) {
        grid_df[[m]][i] <- switch(
          m,
          wasserstein1 = wasserstein1(F_pred_i, F_obs, v_grid),
          cvm = cramer_von_mises(F_pred_i, F_obs, v_grid)
        )
      }
    }
  }
  if (verbose) {
    cat(" done.\n")
  }

  # Backwards compat: "distance" column = primary metric
  grid_df$distance <- grid_df[[primary_metric]]

  # ------------------------------------------------------------------
  # Stage 2: Local refinement via optim() — per metric
  # ------------------------------------------------------------------

  bounds <- .get_bounds(regime_family)

  .refine <- function(metric, grid_df, verbose_label = TRUE) {
    best_idx <- which.min(grid_df[[metric]])
    params_init <- as.numeric(grid_df[best_idx, param_cols])

    if (verbose && verbose_label) {
      cat(
        "    [",
        metric,
        "] Best grid: params =",
        paste(round(params_init, 4), collapse = ", "),
        "  distance =",
        round(grid_df[[metric]][best_idx], 6),
        "\n"
      )
    }

    obj_fn <- .make_objective(metric)
    opt_result <- tryCatch(
      {
        optim(
          par = params_init,
          fn = obj_fn,
          method = "L-BFGS-B",
          lower = bounds$lower,
          upper = bounds$upper,
          control = list(maxit = 500, factr = 1e7)
        )
      },
      error = function(e) {
        warning(
          "optim failed (",
          metric,
          "): ",
          e$message,
          ". Using grid search result."
        )
        list(
          par = params_init,
          value = grid_df[[metric]][best_idx],
          convergence = -1
        )
      }
    )

    regime_param_hat <- opt_result$par
    regime_hat <- create_regime(regime_family, regime_param_hat)
    F_pred <- predict_marginal_cdf(
      v_grid,
      u_sample,
      u_weights,
      regime_hat,
      kernel_cache
    )
    all_dists <- compute_all_distances(F_pred, F_obs, v_grid)

    m_hat <- if (tolower(regime_family) == "beta") {
      regime_param_hat[1]
    } else {
      NA_real_
    }
    kappa_hat <- if (
      tolower(regime_family) == "beta" && length(regime_param_hat) > 1
    ) {
      regime_param_hat[2]
    } else {
      NA_real_
    }

    if (verbose && verbose_label) {
      cat(
        "    [",
        metric,
        "] Optimum: params =",
        paste(round(regime_param_hat, 4), collapse = ", "),
        "  distance =",
        round(opt_result$value, 6),
        "\n"
      )
      cat(
        "    [",
        metric,
        "] Regime mean SGPc:",
        round(regime_hat$mean * 100, 1),
        "  median:",
        round(regime_hat$median * 100, 1),
        "\n"
      )
    }

    list(
      regime_param_hat = regime_param_hat,
      m_hat = m_hat,
      kappa_hat = kappa_hat,
      regime = regime_hat,
      distance_min = opt_result$value,
      distance_metric = metric,
      convergence = opt_result$convergence,
      grid_search = grid_df,
      F_pred = F_pred,
      F_obs = F_obs,
      v_grid = v_grid,
      all_distances = all_dists
    )
  }

  if (verbose && multi_metric) {
    cat("  Stage 2: Local refinement (L-BFGS-B) — per metric...\n")
  }
  if (verbose && !multi_metric) {
    cat("  Stage 2: Local refinement (L-BFGS-B)...\n")
  }

  # Always refine the primary metric
  primary_result <- .refine(primary_metric, grid_df)

  if (verbose && !multi_metric) {
    cat(
      "    Optimum: params =",
      paste(round(primary_result$regime_param_hat, 4), collapse = ", "),
      "  distance =",
      round(primary_result$distance_min, 6),
      "\n"
    )
    cat(
      "    Regime mean SGPc:",
      round(primary_result$regime$mean * 100, 1),
      "\n"
    )
    cat(
      "    Regime median SGPc:",
      round(primary_result$regime$median * 100, 1),
      "\n"
    )
    cat("    Convergence:", primary_result$convergence, "\n")
  }

  # Build alt_metrics if multi-metric
  if (multi_metric) {
    alt_metrics <- list()
    for (m in distance_fns[-1L]) {
      alt_metrics[[m]] <- .refine(m, grid_df)
    }
    primary_result$alt_metrics <- alt_metrics

    # Summary comparison
    if (verbose) {
      cat("\n    --- Metric comparison (", regime_family, ") ---\n")
      cat(
        "    Primary (",
        primary_metric,
        "): median=",
        round(primary_result$regime$median * 100, 1),
        "  mean=",
        round(primary_result$regime$mean * 100, 1),
        "  W1=",
        round(primary_result$all_distances$wasserstein1, 6),
        "  CvM=",
        round(primary_result$all_distances$cramer_von_mises, 6),
        "\n",
        sep = ""
      )
      for (m in names(alt_metrics)) {
        ar <- alt_metrics[[m]]
        cat(
          "    Alt (",
          m,
          "):     median=",
          round(ar$regime$median * 100, 1),
          "  mean=",
          round(ar$regime$mean * 100, 1),
          "  W1=",
          round(ar$all_distances$wasserstein1, 6),
          "  CvM=",
          round(ar$all_distances$cramer_von_mises, 6),
          "\n",
          sep = ""
        )
      }
      median_diff <- abs(
        primary_result$regime$median -
          alt_metrics[[distance_fns[2L]]]$regime$median
      ) *
        100
      mean_diff <- abs(
        primary_result$regime$mean - alt_metrics[[distance_fns[2L]]]$regime$mean
      ) *
        100
      cat(
        "    Delta: |median|=",
        round(median_diff, 2),
        "  |mean|=",
        round(mean_diff, 2),
        " SGP points\n"
      )
    }
  }

  return(primary_result)
}


# ==========================================================================
# Internal helpers
# ==========================================================================

#' Build Parameter Grid for Coarse Search
#' @keywords internal
.build_grid <- function(family, resolution) {
  switch(
    family,
    beta = {
      mean_seq <- seq(0.25, 0.75, length.out = resolution)
      # Include kappa=1 so the U(0,1) baseline at kappa=2 is interior to Panel C.
      # This preserves a faithful visual comparison to the best-fit parameters without
      # over-expanding into extremely small-kappa regimes.
      kappa_seq <- exp(seq(log(1), log(200), length.out = resolution))
      grid <- expand.grid(regime_param_1 = mean_seq, regime_param_2 = kappa_seq)
      grid$m <- grid$regime_param_1
      grid$kappa <- grid$regime_param_2
    },
    truncexp = {
      mean_seq <- seq(0.20, 0.80, length.out = resolution * 2)
      grid <- data.frame(regime_param_1 = mean_seq)
    },
    truncunif = {
      lower_seq <- seq(0.0, 0.45, length.out = resolution)
      upper_seq <- seq(0.55, 1.0, length.out = resolution)
      grid <- expand.grid(
        regime_param_1 = lower_seq,
        regime_param_2 = upper_seq
      )
      # Remove invalid combinations (lower >= upper or unreasonably narrow)
      grid <- grid[grid$regime_param_2 > grid$regime_param_1 + 0.10, ]
    },
    stop("Unknown family: ", family)
  )
  return(grid)
}


#' Get Parameter Bounds for optim()
#' @keywords internal
.get_bounds <- function(family) {
  switch(
    family,
    beta = list(lower = c(0.05, 1.0), upper = c(0.95, 500)),
    truncexp = list(lower = 0.05, upper = 0.95),
    truncunif = list(lower = c(0.0, 0.10), upper = c(0.90, 1.0)),
    stop("Unknown family: ", family)
  )
}


#' Estimate Regime Across Multiple Families (Model Comparison)
#'
#' Runs estimate_regime() for each family and returns results sorted by
#' distance, enabling model comparison.
#'
#' @param u_sample Numeric vector. Prior-grade reference percentiles.
#' @param v_sample Numeric vector. Current-grade reference percentiles.
#' @param kernel_cache A kernel_cache object.
#' @param families Character vector. Families to compare.
#'   Default c("beta", "truncexp", "truncunif").
#' @param distance_fn Character scalar, vector, or "both". Distance metric(s).
#'   Passed through to estimate_regime(). Default "wasserstein1".
#' @param verbose Logical. Print progress? Default TRUE.
#' @param tie_tolerance Non-negative numeric scalar. If multiple families
#'   are within this distance of the minimum, prefer `preferred_family`
#'   when available. Default 0.
#' @param preferred_family Character. Family to prefer under ties.
#'   Default "beta".
#' @param ... Additional arguments passed to estimate_regime().
#'
#' @return List with:
#'   \describe{
#'     \item{results}{Named list of estimate_regime() results per family}
#'     \item{comparison}{data.frame with family, distance, median_sgpc, params}
#'     \item{best_family}{Name of best-fitting family (by primary metric)}
#'   }
#'
#' @export
compare_regime_families <- function(
  u_sample,
  v_sample,
  kernel_cache,
  families = c("beta", "truncexp", "truncunif"),
  distance_fn = "wasserstein1",
  verbose = TRUE,
  tie_tolerance = 0,
  preferred_family = "beta",
  ...
) {
  results <- list()
  comparison_rows <- list()

  for (fam in families) {
    if (verbose) {
      cat("\n--- Estimating regime family:", fam, "---\n")
    }

    results[[fam]] <- tryCatch(
      {
        estimate_regime(
          u_sample,
          v_sample,
          kernel_cache,
          regime_family = fam,
          distance_fn = distance_fn,
          verbose = verbose,
          ...
        )
      },
      error = function(e) {
        warning("Failed for family '", fam, "': ", e$message)
        NULL
      }
    )

    if (!is.null(results[[fam]])) {
      comparison_rows[[fam]] <- data.frame(
        family = fam,
        distance = results[[fam]]$distance_min,
        distance_metric = results[[fam]]$distance_metric,
        median_sgpc = results[[fam]]$regime$median * 100,
        mean_sgpc = results[[fam]]$regime$mean * 100,
        params = paste(
          round(results[[fam]]$regime_param_hat, 4),
          collapse = ", "
        ),
        w1 = results[[fam]]$all_distances$wasserstein1,
        cvm = results[[fam]]$all_distances$cramer_von_mises,
        stringsAsFactors = FALSE
      )
    }
  }

  comparison <- do.call(rbind, comparison_rows)
  comparison <- comparison[order(comparison$distance), ]

  min_dist <- min(comparison$distance, na.rm = TRUE)
  tie_cutoff <- min_dist + tie_tolerance
  tied <- comparison[comparison$distance <= tie_cutoff, ]

  preferred_idx <- which(tied$family == preferred_family)
  best_family <- if (length(preferred_idx) > 0) {
    tied$family[preferred_idx[1]]
  } else {
    comparison$family[1]
  }

  if (verbose) {
    cat("\n=== Regime Family Comparison ===\n")
    print(comparison, row.names = FALSE)
    cat("\nBest family:", best_family, "\n")
    if (tie_tolerance > 0) {
      cat("Tie tolerance:", tie_tolerance, "\n")
    }
  }

  list(
    results = results,
    comparison = comparison,
    best_family = best_family
  )
}


cat("STEP 3 optimize_regime.R loaded.\n")
cat("  Functions: estimate_regime, compare_regime_families\n")
