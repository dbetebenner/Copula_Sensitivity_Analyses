############################################################################
###
### Distance Metrics for STEP 3: Growth Regime Inference
###
### Compares predicted CDF F_theta(v) to observed CDF F_obs(v).
### Used as objective functions in the optimizer.
###
### Metrics:
###   - Wasserstein-1 (Earth mover's distance): good interpretability
###   - Cramer-von Mises (integrated squared error): numerically stable
###   - Kolmogorov-Smirnov (supremum): diagnostic, not for optimization
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################


#' Wasserstein-1 Distance Between Two CDFs
#'
#' The L1 distance between CDFs, also known as the Earth Mover's Distance
#' on [0,1]. Interpretable as "average percentile mass that must move."
#'
#'   W_1 = integral_0^1 | F_pred(v) - F_obs(v) | dv
#'
#' Approximated via trapezoidal rule on the provided grid.
#'
#' @param F_pred Numeric vector. Predicted CDF values on a grid.
#' @param F_obs Numeric vector. Observed CDF values on the same grid.
#' @param grid Numeric vector. Grid points (must match F_pred and F_obs length).
#'
#' @return Numeric scalar: W_1 distance in [0, 1].
#'
#' @export
wasserstein1 <- function(F_pred, F_obs, grid) {

  n <- length(grid)
  if (length(F_pred) != n || length(F_obs) != n) {
    stop("F_pred, F_obs, and grid must have the same length")
  }

  abs_diff <- abs(F_pred - F_obs)

  # Trapezoidal integration
  dv <- diff(grid)
  integral <- sum(dv * (abs_diff[-n] + abs_diff[-1]) / 2)

  return(integral)
}


#' Cramer-von Mises Distance Between Two CDFs
#'
#' Integrated squared CDF difference:
#'
#'   CvM = integral_0^1 ( F_pred(v) - F_obs(v) )^2 dv
#'
#' Numerically stable and differentiable, making it suitable for optimisation.
#'
#' @param F_pred Numeric vector. Predicted CDF values on a grid.
#' @param F_obs Numeric vector. Observed CDF values on the same grid.
#' @param grid Numeric vector. Grid points.
#'
#' @return Numeric scalar: CvM distance (>= 0).
#'
#' @export
cramer_von_mises <- function(F_pred, F_obs, grid) {

  n <- length(grid)
  if (length(F_pred) != n || length(F_obs) != n) {
    stop("F_pred, F_obs, and grid must have the same length")
  }

  sq_diff <- (F_pred - F_obs)^2

  # Trapezoidal integration
  dv <- diff(grid)
  integral <- sum(dv * (sq_diff[-n] + sq_diff[-1]) / 2)

  return(integral)
}


#' Kolmogorov-Smirnov Distance Between Two CDFs
#'
#' Supremum of absolute CDF differences:
#'
#'   KS = sup_v | F_pred(v) - F_obs(v) |
#'
#' Useful as a diagnostic but not ideal as an optimiser objective
#' (non-smooth).
#'
#' @param F_pred Numeric vector. Predicted CDF values on a grid.
#' @param F_obs Numeric vector. Observed CDF values on the same grid.
#' @param grid Numeric vector. Grid points (used for location of max).
#'
#' @return List with:
#'   \itemize{
#'     \item distance: Numeric scalar KS distance
#'     \item location: The v value where the maximum difference occurs
#'   }
#'
#' @export
ks_distance <- function(F_pred, F_obs, grid) {

  n <- length(grid)
  if (length(F_pred) != n || length(F_obs) != n) {
    stop("F_pred, F_obs, and grid must have the same length")
  }

  abs_diff <- abs(F_pred - F_obs)
  idx_max <- which.max(abs_diff)


  list(
    distance = abs_diff[idx_max],
    location = grid[idx_max]
  )
}


#' Tail-Weighted Cramer-von Mises Distance
#'
#' CvM with higher weight in tails, useful when tail fit matters more
#' than interior fit (e.g., for policy classification at extremes).
#'
#'   TW-CvM = integral_0^1 w(v) * ( F_pred(v) - F_obs(v) )^2 dv
#'
#' where w(v) = 1 / (v * (1-v)) normalised to integrate to 1.
#' This is the Anderson-Darling weight function.
#'
#' @param F_pred Numeric vector. Predicted CDF values on a grid.
#' @param F_obs Numeric vector. Observed CDF values on the same grid.
#' @param grid Numeric vector. Grid points.
#'
#' @return Numeric scalar: tail-weighted CvM distance.
#'
#' @export
tail_weighted_cvm <- function(F_pred, F_obs, grid) {

  n <- length(grid)
  if (length(F_pred) != n || length(F_obs) != n) {
    stop("F_pred, F_obs, and grid must have the same length")
  }

  # Anderson-Darling weight: 1/(v*(1-v)), clamped to avoid Inf at boundaries
  v_clamped <- pmax(0.01, pmin(0.99, grid))
  w <- 1 / (v_clamped * (1 - v_clamped))

  # Normalise weights
  dv <- diff(grid)
  w_integral <- sum(dv * (w[-n] + w[-1]) / 2)
  w_normed <- w / w_integral

  sq_diff <- (F_pred - F_obs)^2
  weighted_sq <- sq_diff * w_normed

  integral <- sum(dv * (weighted_sq[-n] + weighted_sq[-1]) / 2)
  return(integral)
}


#' Compute All Distance Metrics
#'
#' Convenience function that computes all metrics at once for reporting.
#'
#' @param F_pred Numeric vector. Predicted CDF values.
#' @param F_obs Numeric vector. Observed CDF values.
#' @param grid Numeric vector. Grid points.
#'
#' @return Named list of distance values.
#'
#' @export
compute_all_distances <- function(F_pred, F_obs, grid) {

  ks <- ks_distance(F_pred, F_obs, grid)

  list(
    wasserstein1     = wasserstein1(F_pred, F_obs, grid),
    cramer_von_mises = cramer_von_mises(F_pred, F_obs, grid),
    ks_distance      = ks$distance,
    ks_location      = ks$location,
    tail_weighted_cvm = tail_weighted_cvm(F_pred, F_obs, grid)
  )
}


cat("STEP 3 distance_metrics.R loaded.\n")
cat("  Functions: wasserstein1, cramer_von_mises, ks_distance,\n")
cat("             tail_weighted_cvm, compute_all_distances\n")
