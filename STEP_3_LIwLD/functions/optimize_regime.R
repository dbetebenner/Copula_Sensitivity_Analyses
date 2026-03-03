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
### where distance is Wasserstein-1 or Cramer-von Mises.
###
### Author: dataimago
### Date: February 2026
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
#' @param distance_fn Character. Distance metric: "wasserstein1" or "cvm".
#'   Default "wasserstein1".
#' @param v_grid Numeric vector. Grid for CDF evaluation. If NULL,
#'   uses seq(0.005, 0.995, length.out = 201).
#' @param u_weights Optional weights for u_sample.
#' @param v_weights Optional weights for v_sample.
#' @param grid_resolution Integer. Number of grid points per parameter
#'   dimension in coarse search. Default 30.
#' @param verbose Logical. Print progress? Default TRUE.
#'
#' @return List with:
#'   \itemize{
#'     \item regime_param_hat: Estimated parameter vector
#'     \item m_hat: Estimated mean parameter for Beta family (if applicable)
#'     \item kappa_hat: Estimated concentration parameter for Beta family (if applicable)
#'     \item regime: The estimated growth_regime object
#'     \item distance_min: Minimum distance achieved
#'     \item distance_metric: Which metric was used
#'     \item convergence: Convergence info from optim()
#'     \item grid_search: data.frame of grid search results
#'     \item F_pred: Predicted CDF at optimum
#'     \item F_obs: Observed CDF
#'     \item v_grid: The evaluation grid used
#'     \item all_distances: All distance metrics at optimum
#'   }
#'
#' @export
estimate_regime <- function(u_sample, v_sample, kernel_cache,
                             regime_family = "beta",
                             distance_fn = "wasserstein1",
                             v_grid = NULL,
                             u_weights = NULL,
                             v_weights = NULL,
                             grid_resolution = 30,
                             verbose = TRUE) {

  # Defaults
  if (is.null(v_grid)) {
    v_grid <- seq(0.005, 0.995, length.out = 201)
  }

  regime_family <- tolower(regime_family)
  distance_fn <- tolower(distance_fn)

  # Compute observed CDF (once)
  F_obs <- observed_marginal_cdf(v_grid, v_sample, v_weights)

  # Define the objective function: parameter vector -> distance
  objective <- function(regime_params) {
    regime <- tryCatch(
      create_regime(regime_family, regime_params),
      error = function(e) NULL
    )
    if (is.null(regime)) return(Inf)

    F_pred <- predict_marginal_cdf(v_grid, u_sample, u_weights, regime, kernel_cache)

    d <- switch(distance_fn,
      wasserstein1 = wasserstein1(F_pred, F_obs, v_grid),
      cvm          = cramer_von_mises(F_pred, F_obs, v_grid),
      stop("Unknown distance function: ", distance_fn)
    )
    return(d)
  }

  # ------------------------------------------------------------------
  # Stage 1: Coarse grid search
  # ------------------------------------------------------------------

  if (verbose) cat("  Stage 1: Coarse grid search (", regime_family, ")...\n")

  grid_df <- .build_grid(regime_family, grid_resolution)
  param_cols <- grep("^regime_param_", names(grid_df), value = TRUE)

  if (verbose) cat("    Evaluating", nrow(grid_df), "grid points...")
  grid_df$distance <- sapply(seq_len(nrow(grid_df)), function(i) {
    regime_params <- as.numeric(grid_df[i, param_cols])
    objective(regime_params)
  })
  if (verbose) cat(" done.\n")

  best_idx <- which.min(grid_df$distance)
  params_init <- as.numeric(grid_df[best_idx, param_cols])

  if (verbose) {
    cat("    Best grid point: params =", paste(round(params_init, 4), collapse = ", "),
        "  distance =", round(grid_df$distance[best_idx], 6), "\n")
  }

  # ------------------------------------------------------------------
  # Stage 2: Local refinement via optim()
  # ------------------------------------------------------------------

  if (verbose) cat("  Stage 2: Local refinement (L-BFGS-B)...\n")

  bounds <- .get_bounds(regime_family)

  opt_result <- tryCatch({
    optim(par = params_init, fn = objective,
          method = "L-BFGS-B",
          lower = bounds$lower, upper = bounds$upper,
          control = list(maxit = 500, factr = 1e7))
  }, error = function(e) {
    warning("optim failed: ", e$message, ". Using grid search result.")
    list(par = params_init,
         value = grid_df$distance[best_idx],
         convergence = -1)
  })

  regime_param_hat <- opt_result$par

  # Build final regime and predicted CDF at optimum
  regime_hat <- create_regime(regime_family, regime_param_hat)
  F_pred <- predict_marginal_cdf(v_grid, u_sample, u_weights, regime_hat, kernel_cache)
  all_distances <- compute_all_distances(F_pred, F_obs, v_grid)

  m_hat <- if (tolower(regime_family) == "beta") regime_param_hat[1] else NA_real_
  kappa_hat <- if (tolower(regime_family) == "beta" && length(regime_param_hat) > 1) regime_param_hat[2] else NA_real_

  if (verbose) {
    cat("    Optimum: params =", paste(round(regime_param_hat, 4), collapse = ", "),
        "  distance =", round(opt_result$value, 6), "\n")
    cat("    Regime mean SGPc:", round(regime_hat$mean * 100, 1), "\n")
    cat("    Regime median SGPc:", round(regime_hat$median * 100, 1), "\n")
    cat("    Convergence:", opt_result$convergence, "\n")
  }

  list(
    regime_param_hat = regime_param_hat,
    m_hat           = m_hat,
    kappa_hat       = kappa_hat,
    regime          = regime_hat,
    distance_min    = opt_result$value,
    distance_metric = distance_fn,
    convergence     = opt_result$convergence,
    grid_search     = grid_df,
    F_pred          = F_pred,
    F_obs           = F_obs,
    v_grid          = v_grid,
    all_distances   = all_distances
  )
}


# ==========================================================================
# Internal helpers
# ==========================================================================

#' Build Parameter Grid for Coarse Search
#' @keywords internal
.build_grid <- function(family, resolution) {

  switch(family,
    beta = {
      mean_seq  <- seq(0.25, 0.75, length.out = resolution)
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
      grid <- expand.grid(regime_param_1 = lower_seq, regime_param_2 = upper_seq)
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
  switch(family,
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
#' @param distance_fn Character. Distance metric. Default "wasserstein1".
#' @param verbose Logical. Print progress? Default TRUE.
#' @param tie_tolerance Non-negative numeric scalar. If multiple families
#'   are within this distance of the minimum, prefer `preferred_family`
#'   when available. Default 0.
#' @param preferred_family Character. Family to prefer under ties.
#'   Default "beta".
#' @param ... Additional arguments passed to estimate_regime().
#'
#' @return List with:
#'   \itemize{
#'     \item results: Named list of estimate_regime() results per family
#'     \item comparison: data.frame with family, distance, median_sgpc, params
#'     \item best_family: Name of best-fitting family
#'   }
#'
#' @export
compare_regime_families <- function(u_sample, v_sample, kernel_cache,
                                     families = c("beta", "truncexp", "truncunif"),
                                     distance_fn = "wasserstein1",
                                     verbose = TRUE,
                                     tie_tolerance = 0,
                                     preferred_family = "beta",
                                     ...) {

  results <- list()
  comparison_rows <- list()

  for (fam in families) {
    if (verbose) cat("\n--- Estimating regime family:", fam, "---\n")

    results[[fam]] <- tryCatch({
      estimate_regime(u_sample, v_sample, kernel_cache,
                      regime_family = fam,
                      distance_fn = distance_fn,
                      verbose = verbose, ...)
    }, error = function(e) {
      warning("Failed for family '", fam, "': ", e$message)
      NULL
    })

    if (!is.null(results[[fam]])) {
      comparison_rows[[fam]] <- data.frame(
        family       = fam,
        distance     = results[[fam]]$distance_min,
        median_sgpc  = results[[fam]]$regime$median * 100,
        mean_sgpc    = results[[fam]]$regime$mean * 100,
        params       = paste(round(results[[fam]]$regime_param_hat, 4), collapse = ", "),
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
    results     = results,
    comparison  = comparison,
    best_family = best_family
  )
}


cat("STEP 3 optimize_regime.R loaded.\n")
cat("  Functions: estimate_regime, compare_regime_families\n")
