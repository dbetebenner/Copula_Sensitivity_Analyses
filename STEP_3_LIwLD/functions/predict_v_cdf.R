############################################################################
###
### Predicted V-Marginal CDF for STEP 3: Growth Regime Inference
###
### Implements the key analytic identity that removes Monte Carlo noise:
###
###   F_H(v) = E[ H( F_0(v | U) ) ]
###          ~= sum_i  w_i * H( F_0(v | u_i) )  /  sum_i w_i
###
### where {u_i, w_i} is the prior-grade sample (expressed as reference
### percentiles) and H is the growth regime CDF.
###
### This is the analytic predicted CDF of current-grade scores under a
### candidate growth regime, given the prior-grade distribution and a
### baseline copula kernel.
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################


#' Predict Marginal CDF of Current Scores Under a Growth Regime
#'
#' The core analytic computation. For each v on a grid, computes:
#'
#'   F_H(v) = (1/sum(w)) * sum_i  w_i * H( F_0(v | u_i) )
#'
#' This is exact (no simulation) when P is independent of U within
#' the subgroup.
#'
#' @param v_grid Numeric vector. Grid of current-grade pseudo-observation
#'   values in (0,1) at which to evaluate the predicted CDF.
#' @param u_sample Numeric vector. Prior-grade pseudo-observations for the
#'   subgroup (reference-scaled via reference_marginals).
#' @param weights Optional numeric vector of weights for u_sample.
#'   If NULL, equal weights are used.
#' @param regime A growth_regime object (from regime_families.R).
#' @param kernel_cache A kernel_cache object (from copula_kernel_cache.R).
#'
#' @return Numeric vector of predicted CDF values F_H(v_grid).
#'   Same length as v_grid, values in [0,1].
#'
#' @details
#' Computational complexity: O(n_u * n_v) where n_u = length(u_sample)
#' and n_v = length(v_grid). Typical use: n_u ~ 200-1000, n_v ~ 201.
#' Runtime: sub-second for most configurations.
#'
#' The computation proceeds as follows for each v in v_grid:
#' 1. Evaluate F_0(v | u_i) for all u_i via kernel_conditional_cdf()
#' 2. Apply H() to each value (the growth regime CDF)
#' 3. Take weighted average
#'
#' @export
predict_marginal_cdf <- function(v_grid, u_sample, weights = NULL,
                                  regime, kernel_cache) {

  # Input validation
  if (!inherits(regime, "growth_regime")) {
    stop("regime must be a growth_regime object")
  }
  if (!inherits(kernel_cache, "kernel_cache")) {
    stop("kernel_cache must be a kernel_cache object")
  }

  n_u <- length(u_sample)
  n_v <- length(v_grid)

  if (n_u == 0) stop("u_sample is empty")
  if (n_v == 0) return(numeric(0))

  # Default weights
  if (is.null(weights)) {
    weights <- rep(1, n_u)
  }
  if (length(weights) != n_u) stop("weights must match u_sample length")
  w_sum <- sum(weights)

  # Preallocate result
  F_H <- numeric(n_v)

  # For each v, compute the weighted average of H(F_0(v|u_i))
  for (j in seq_len(n_v)) {
    v_j <- rep(v_grid[j], n_u)

    # F_0(v | u_i) for all u_i
    f0_vals <- kernel_conditional_cdf(v = v_j, u = u_sample, cache = kernel_cache)

    # H(F_0(v | u_i))
    h_vals <- regime$cdf(f0_vals)

    # Weighted average
    F_H[j] <- sum(weights * h_vals) / w_sum
  }

  # Enforce monotonicity (should be automatic but guards against numerical noise)
  F_H <- cummax(F_H)

  # Clamp to [0, 1]
  F_H <- pmax(0, pmin(1, F_H))

  return(F_H)
}


#' Compute Observed Marginal CDF from a Sample
#'
#' Creates the empirical CDF of observed current-grade pseudo-observations,
#' evaluated on the same grid as the predicted CDF for direct comparison.
#'
#' @param v_grid Numeric vector. Grid points at which to evaluate the ECDF.
#' @param v_sample Numeric vector. Observed current-grade pseudo-observations.
#' @param weights Optional numeric vector of weights for v_sample.
#'
#' @return Numeric vector of observed CDF values at v_grid. Same length as v_grid.
#'
#' @export
observed_marginal_cdf <- function(v_grid, v_sample, weights = NULL) {

  n_v <- length(v_sample)
  if (n_v == 0) stop("v_sample is empty")

  if (is.null(weights)) {
    # Standard ECDF
    ecdf_fn <- ecdf(v_sample)
    return(ecdf_fn(v_grid))
  }

  # Weighted ECDF
  ord <- order(v_sample)
  v_sorted <- v_sample[ord]
  w_sorted <- weights[ord]
  w_cum <- cumsum(w_sorted) / sum(w_sorted)

  # Evaluate on grid via step function
  result <- approx(v_sorted, w_cum, xout = v_grid,
                    method = "constant", rule = 2, f = 0)$y
  return(result)
}


#' Predict Conditional CDF for an Individual
#'
#' Computes F_H(v | u) = H( F_0(v | u) ) for a single
#' individual with prior percentile u. This is the modified conditional
#' CDF under the growth regime.
#'
#' @param v Numeric vector of current-grade values to evaluate
#' @param u Numeric scalar. Prior-grade pseudo-observation for one individual.
#' @param regime A growth_regime object
#' @param kernel_cache A kernel_cache object
#'
#' @return Numeric vector of F_H(v | u) values
#'
#' @export
predict_conditional_cdf <- function(v, u, regime, kernel_cache) {

  u_vec <- rep(u, length(v))
  f0_vals <- kernel_conditional_cdf(v = v, u = u_vec, cache = kernel_cache)
  regime$cdf(f0_vals)
}


#' Predict marginal CDF using a list of stratified regimes
#'
#' @param v_grid Numeric vector of evaluation points.
#' @param u_sample Numeric vector of prior percentiles.
#' @param regime_list Named list of growth_regime objects keyed by bin level.
#' @param u_bins Factor/character vector assigning each u_sample to a bin.
#' @param kernel_cache kernel_cache object.
#' @param weights Optional numeric weights over u_sample.
#'
#' @return Numeric vector of predicted CDF values on v_grid.
#' @export
predict_marginal_cdf_stratified <- function(v_grid, u_sample, regime_list, u_bins,
                                            kernel_cache, weights = NULL) {
  if (is.null(weights)) weights <- rep(1, length(u_sample))
  stopifnot(length(u_sample) == length(u_bins), length(weights) == length(u_sample))
  lvls <- unique(as.character(u_bins))
  F_total <- rep(0, length(v_grid))
  w_total <- sum(weights)

  for (lv in lvls) {
    idx <- which(as.character(u_bins) == lv)
    if (length(idx) == 0 || is.null(regime_list[[lv]])) next
    w_bin <- sum(weights[idx])
    F_bin <- predict_marginal_cdf(
      v_grid = v_grid,
      u_sample = u_sample[idx],
      weights = weights[idx],
      regime = regime_list[[lv]],
      kernel_cache = kernel_cache
    )
    F_total <- F_total + (w_bin / w_total) * F_bin
  }
  F_total
}


cat("STEP 3 predict_v_cdf.R loaded.\n")
cat("  Functions: predict_marginal_cdf, observed_marginal_cdf,\n")
cat("             predict_conditional_cdf, predict_marginal_cdf_stratified\n")
