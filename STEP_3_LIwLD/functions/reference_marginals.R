############################################################################
###
### Reference Marginals for STEP 3: Growth Regime Inference
###
### Provides weighted ECDF and inverse CDF functions using a fixed
### reference population (e.g., state-level scores). This is critical
### because subgroup-specific ECDFs would erase distribution shifts.
###
### Key functions:
###   - create_reference_ecdf(): Build weighted ECDF from reference data
###   - reference_cdf(): Map raw scores to reference percentiles
###   - reference_quantile(): Map reference percentiles back to scores
###   - apply_reference_marginals(): Apply reference to a subgroup sample
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################

require(data.table)


#' Create Reference ECDF from a Population
#'
#' Builds a weighted empirical CDF with monotone interpolation and stable
#' tails. The resulting object supports both forward (score -> percentile)
#' and inverse (percentile -> score) transformations.
#'
#' @param scores Numeric vector of raw scores from the reference population
#' @param weights Optional numeric vector of weights (e.g., survey weights).
#'   If NULL, equal weights are used.
#' @param n_grid Integer. Number of grid points for interpolation. Default 1000.
#' @param tail_buffer Numeric. Small buffer applied at distribution tails
#'   to avoid exact 0 or 1. Default 1e-6.
#'
#' @return List with class "reference_ecdf":
#'   \itemize{
#'     \item cdf_fn: Function mapping scores to (0,1)
#'     \item quantile_fn: Function mapping (0,1) to scores
#'     \item score_grid: Numeric vector of score grid points
#'     \item cdf_grid: Numeric vector of CDF values at score_grid
#'     \item n_obs: Number of observations in reference
#'     \item score_range: c(min, max) of reference scores
#'     \item weighted: Logical indicating if weights were used
#'   }
#'
#' @details
#' Uses monotone interpolation (stats::approxfun with method "linear" and
#' rule = 2 for extrapolation) to create smooth CDF and quantile functions.
#' The CDF is clamped to (tail_buffer, 1 - tail_buffer) to avoid boundary
#' issues in downstream copula operations.
#'
#' @examples
#' \dontrun{
#' # State-level reference for Grade 4 Mathematics
#' ref <- create_reference_ecdf(state_data$SCALE_SCORE)
#'
#' # District scores as state percentiles
#' u_district <- reference_cdf(district_scores, ref)
#' }
#'
#' @export
create_reference_ecdf <- function(scores, weights = NULL, n_grid = 1000,
                                   tail_buffer = 1e-6) {

  # Input validation
  if (!is.numeric(scores) || length(scores) < 10) {
    stop("scores must be a numeric vector with at least 10 observations")
  }

  scores <- scores[!is.na(scores)]
  n_obs <- length(scores)
  if (n_obs < 10) stop("Fewer than 10 non-NA scores in reference")

  weighted <- !is.null(weights)
  if (weighted) {
    weights <- weights[!is.na(scores)]
    if (length(weights) != n_obs) stop("weights must match non-NA scores length")
    if (any(weights < 0)) stop("weights must be non-negative")
    weights <- weights / sum(weights)  # Normalise
  } else {
    weights <- rep(1 / n_obs, n_obs)
  }

  # Sort scores and weights together

  ord <- order(scores)
  scores_sorted <- scores[ord]
  weights_sorted <- weights[ord]

  # Cumulative weights -> ECDF values (midpoint convention for ties)
  cum_w <- cumsum(weights_sorted)
  # Shift by half-weight for each observation to handle ties smoothly
  cdf_values <- cum_w - weights_sorted / 2

  # Clamp to (tail_buffer, 1 - tail_buffer)
  cdf_values <- pmax(tail_buffer, pmin(1 - tail_buffer, cdf_values))

  # De-duplicate tied scores (take mean CDF for identical scores)
  score_unique <- unique(scores_sorted)
  if (length(score_unique) < length(scores_sorted)) {
    cdf_unique <- tapply(cdf_values, match(scores_sorted, score_unique), mean)
    cdf_unique <- as.numeric(cdf_unique)
  } else {
    cdf_unique <- cdf_values
  }

  # Create fine grid for interpolation
  score_range <- range(score_unique)
  score_grid <- seq(score_range[1], score_range[2], length.out = n_grid)
  cdf_grid <- approx(score_unique, cdf_unique, xout = score_grid,
                      method = "linear", rule = 2)$y
  cdf_grid <- pmax(tail_buffer, pmin(1 - tail_buffer, cdf_grid))

  # Ensure monotonicity
  cdf_grid <- cummax(cdf_grid)

  # Forward function: score -> CDF
  cdf_fn <- approxfun(score_grid, cdf_grid, method = "linear", rule = 2)

  # Inverse function: CDF -> score (quantile)
  # Need strictly increasing CDF for inverse; add tiny jitter to ties
  cdf_strict <- cdf_grid
  eps <- 1e-12
  for (i in 2:length(cdf_strict)) {
    if (cdf_strict[i] <= cdf_strict[i - 1]) {
      cdf_strict[i] <- cdf_strict[i - 1] + eps
    }
  }
  quantile_fn <- approxfun(cdf_strict, score_grid, method = "linear", rule = 2)

  result <- list(
    cdf_fn       = cdf_fn,
    quantile_fn  = quantile_fn,
    score_grid   = score_grid,
    cdf_grid     = cdf_grid,
    n_obs        = n_obs,
    score_range  = score_range,
    weighted     = weighted,
    tail_buffer  = tail_buffer
  )
  class(result) <- "reference_ecdf"
  return(result)
}


#' Map Scores to Reference Percentiles
#'
#' Applies the reference ECDF to convert raw scores to (0,1) percentiles.
#'
#' @param scores Numeric vector of raw scores
#' @param ref A reference_ecdf object from create_reference_ecdf()
#'
#' @return Numeric vector of reference percentiles in (0,1)
#'
#' @export
reference_cdf <- function(scores, ref) {
  if (!inherits(ref, "reference_ecdf")) {
    stop("ref must be a reference_ecdf object")
  }
  u <- ref$cdf_fn(scores)
  # Clamp to valid range
  u <- pmax(ref$tail_buffer, pmin(1 - ref$tail_buffer, u))
  return(u)
}


#' Map Reference Percentiles Back to Scores
#'
#' Applies the inverse reference CDF to convert (0,1) percentiles back
#' to the raw score scale.
#'
#' @param p Numeric vector of percentiles in (0,1)
#' @param ref A reference_ecdf object from create_reference_ecdf()
#'
#' @return Numeric vector of raw scores
#'
#' @export
reference_quantile <- function(p, ref) {
  if (!inherits(ref, "reference_ecdf")) {
    stop("ref must be a reference_ecdf object")
  }
  p <- pmax(ref$tail_buffer, pmin(1 - ref$tail_buffer, p))
  return(ref$quantile_fn(p))
}


#' Apply Reference Marginals to a Subgroup Sample
#'
#' Given a subgroup's raw prior and current scores (not necessarily paired),
#' returns reference-scaled pseudo-observations for use in STEP 3 inference.
#'
#' @param prior_scores Numeric vector of prior (e.g., Grade 4) scores
#' @param current_scores Numeric vector of current (e.g., Grade 8) scores
#' @param ref_prior reference_ecdf object for prior grade
#' @param ref_current reference_ecdf object for current grade
#'
#' @return List with:
#'   \itemize{
#'     \item u: Reference percentiles for prior scores
#'     \item v: Reference percentiles for current scores
#'     \item n_prior: Number of prior scores
#'     \item n_current: Number of current scores
#'   }
#'
#' @export
apply_reference_marginals <- function(prior_scores, current_scores,
                                       ref_prior, ref_current) {

  u <- reference_cdf(prior_scores, ref_prior)
  v <- reference_cdf(current_scores, ref_current)

  list(
    u         = u,
    v         = v,
    n_prior   = length(u),
    n_current = length(v)
  )
}


#' Build Reference Marginals from Full State Data for a Condition
#'
#' Convenience function that extracts state-level prior and current score
#' distributions for a given condition and builds reference ECDFs.
#'
#' @param state_data data.table of full state longitudinal data
#' @param condition_meta List with year_prior, year_current, grade_prior,
#'   grade_current, content_area (from parse_condition_id())
#'
#' @return List with ref_prior and ref_current (reference_ecdf objects)
#'
#' @export
build_condition_reference <- function(state_data, condition_meta) {

  # Extract prior scores: all students in the state at grade_prior / year_prior
  prior_mask <- state_data$GRADE == condition_meta$grade_prior &
                state_data$YEAR == condition_meta$year_prior &
                state_data$CONTENT_AREA == condition_meta$content_area &
                !is.na(state_data$SCALE_SCORE)
  prior_scores <- state_data$SCALE_SCORE[prior_mask]

  # Extract current scores: all students at grade_current / year_current
  current_mask <- state_data$GRADE == condition_meta$grade_current &
                  state_data$YEAR == condition_meta$year_current &
                  state_data$CONTENT_AREA == condition_meta$content_area &
                  !is.na(state_data$SCALE_SCORE)
  current_scores <- state_data$SCALE_SCORE[current_mask]

  if (length(prior_scores) < 50) {
    warning("Small reference for prior: n = ", length(prior_scores))
  }
  if (length(current_scores) < 50) {
    warning("Small reference for current: n = ", length(current_scores))
  }

  list(
    ref_prior   = create_reference_ecdf(prior_scores),
    ref_current = create_reference_ecdf(current_scores),
    n_prior     = length(prior_scores),
    n_current   = length(current_scores)
  )
}


#' Build Reference Marginals from Longitudinal Pairs
#'
#' Builds prior- and current-grade reference ECDFs from matched pairs rather
#' than from the full cross-sectional population.  This ensures the marginal
#' transformations are consistent with the copula (which was estimated from
#' the same paired population in Step 1).
#'
#' @param pairs data.table of longitudinal pairs with columns
#'   SCALE_SCORE_PRIOR and SCALE_SCORE_CURRENT.
#'
#' @return List with ref_prior and ref_current (reference_ecdf objects),
#'   plus n_prior and n_current counts.
#'
#' @export
build_pairs_reference <- function(pairs) {

  prior_scores   <- pairs$SCALE_SCORE_PRIOR[!is.na(pairs$SCALE_SCORE_PRIOR)]
  current_scores <- pairs$SCALE_SCORE_CURRENT[!is.na(pairs$SCALE_SCORE_CURRENT)]

  if (length(prior_scores) < 50) {
    warning("Small reference for prior: n = ", length(prior_scores))
  }
  if (length(current_scores) < 50) {
    warning("Small reference for current: n = ", length(current_scores))
  }

  list(
    ref_prior   = create_reference_ecdf(prior_scores),
    ref_current = create_reference_ecdf(current_scores),
    n_prior     = length(prior_scores),
    n_current   = length(current_scores)
  )
}


cat("STEP 3 reference_marginals.R loaded.\n")
cat("  Functions: create_reference_ecdf, reference_cdf, reference_quantile,\n")
cat("             apply_reference_marginals, build_condition_reference,\n")
cat("             build_pairs_reference\n")
