############################################################################
### I-Spline ECDF Fitting Functions
### Reusable functions for monotone smooth ECDF estimation
############################################################################

require(splines2)

#' Fit I-Spline Coefficients to ECDF
#' 
#' Uses non-negative least squares to fit I-spline basis to empirical CDF
#' 
#' @param basis_matrix I-spline basis matrix
#' @param ecdf_values Empirical CDF values to fit
#' 
#' @return Vector of non-negative coefficients
fit_ispline_ecdf <- function(basis_matrix, ecdf_values) {
  
  n_basis <- ncol(basis_matrix)
  
  # Objective: minimize ||basis * coef - ecdf_values||^2
  # Constraint: coef >= 0 (ensures monotonicity for I-splines)
  
  objective <- function(coef) {
    fitted <- basis_matrix %*% coef
    sum((fitted - ecdf_values)^2)
  }
  
  # Initial guess: uniform weights
  init_coef <- rep(1/n_basis, n_basis)
  
  # Optimize with non-negative constraints using L-BFGS-B
  result <- optim(par = init_coef,
                  fn = objective,
                  method = "L-BFGS-B",
                  lower = rep(0, n_basis),
                  upper = rep(Inf, n_basis))
  
  return(result$par)
}


#' Create Fixed Reference Framework for I-Spline ECDF
#' 
#' Establishes fixed boundaries and knots from full dataset to be used
#' across all bootstrap samples
#' 
#' IMPORTANT UPDATE: Default increased from 4 to 9 interior knots to ensure
#' pseudo-observations are truly Uniform(0,1) and preserve tail dependence.
#' Previous default (4 knots) caused:
#' - K-S test failures (p < 0.001) - pseudo-observations not uniform
#' - Frank copula to falsely win over t-copula (ΔAIC = 2,423)
#' - Distortion of tail dependence structure (64.9% of Frank's advantage in tails)
#' 
#' See debug_frank_dominance.R for diagnostic evidence.
#' For Phase 1 (family selection), use empirical ranks instead (see copula_bootstrap.R).
#' For Phase 2 (applications), this improved default or create_ispline_framework_enhanced()
#' with tail_aware=TRUE should be used.
#' 
#' @param scale_scores Vector of scale scores
#' @param knot_percentiles Percentiles at which to place knots (default: 9 knots at 10%, 20%, ..., 90%)
#' @param n_eval Number of evaluation points for grid (default 500)
#' 
#' @return List containing boundaries, knots, x_grid, and fitted baseline ECDF
create_ispline_framework <- function(scale_scores,
                                    knot_percentiles = seq(0.1, 0.9, by = 0.1),  # 9 knots (was 4)
                                    n_eval = 500) {
  
  # Remove NAs
  scale_scores <- scale_scores[!is.na(scale_scores)]
  
  # Establish boundaries
  boundary_min <- min(scale_scores)
  boundary_max <- max(scale_scores)
  
  # Fixed knot locations at specified percentiles
  knot_locations <- quantile(scale_scores, probs = knot_percentiles)
  
  # Create evaluation grid
  x_grid <- seq(boundary_min, boundary_max, length.out = n_eval)
  
  # Create empirical CDF
  ecdf_full <- ecdf(scale_scores)
  y_ecdf_full <- ecdf_full(x_grid)
  
  # Create I-spline basis matrix
  ispline_basis <- iSpline(x_grid,
                           knots = knot_locations,
                           Boundary.knots = c(boundary_min, boundary_max),
                           degree = 3,
                           intercept = TRUE)
  
  # Fit baseline I-spline
  coef_full <- fit_ispline_ecdf(ispline_basis, y_ecdf_full)
  y_full_smooth <- as.vector(ispline_basis %*% coef_full)
  
  # Create function for evaluation at arbitrary points
  smooth_ecdf_full <- function(x) {
    basis_x <- iSpline(x,
                       knots = knot_locations,
                       Boundary.knots = c(boundary_min, boundary_max),
                       degree = 3,
                       intercept = TRUE)
    as.vector(basis_x %*% coef_full)
  }
  
  return(list(
    boundary_min = boundary_min,
    boundary_max = boundary_max,
    knot_locations = knot_locations,
    knot_percentiles = knot_percentiles,
    x_grid = x_grid,
    coef_full = coef_full,
    y_full_smooth = y_full_smooth,
    smooth_ecdf_full = smooth_ecdf_full,
    n_observations = length(scale_scores)
  ))
}


#' Fit I-Spline ECDF to Sample Data Using Fixed Knots
#' 
#' Fits I-spline to sample data using pre-defined knot structure
#' 
#' @param sample_data Vector of sample scale scores
#' @param knot_locations Fixed knot locations (from reference framework)
#' @param boundaries Vector c(min, max) boundaries (from reference framework)
#' @param x_eval Evaluation grid (from reference framework)
#' 
#' @return List with fitted coefficients and smooth ECDF function
fit_ispline_sample <- function(sample_data,
                               knot_locations,
                               boundaries,
                               x_eval) {
  
  # Create I-spline basis for evaluation grid
  basis_eval <- iSpline(x_eval,
                        knots = knot_locations,
                        Boundary.knots = boundaries,
                        degree = 3,
                        intercept = TRUE)
  
  # Create ECDF for this sample
  ecdf_sample <- ecdf(sample_data)
  y_ecdf_sample <- ecdf_sample(x_eval)
  
  # Fit I-spline using fixed knot structure
  coef_sample <- fit_ispline_ecdf(basis_eval, y_ecdf_sample)
  
  # Create function for evaluation at arbitrary points
  smooth_ecdf_sample <- function(x) {
    basis_x <- iSpline(x,
                       knots = knot_locations,
                       Boundary.knots = boundaries,
                       degree = 3,
                       intercept = TRUE)
    as.vector(basis_x %*% coef_sample)
  }
  
  return(list(
    coef = coef_sample,
    smooth_ecdf = smooth_ecdf_sample,
    y_smooth = as.vector(basis_eval %*% coef_sample)
  ))
}


#' Create Bootstrap I-Spline ECDFs (Univariate)
#' 
#' Generate bootstrap samples and fit I-splines using fixed knot structure
#' 
#' @param data Vector of scale scores (full dataset)
#' @param n_sample Sample size for each bootstrap
#' @param n_bootstrap Number of bootstrap resamples
#' @param framework I-spline framework from create_ispline_framework()
#' @param with_replacement TRUE = standard bootstrap, FALSE = sampling without replacement
#' 
#' @return List of bootstrap ECDF functions
bootstrap_ispline_ecdfs <- function(data,
                                   n_sample,
                                   n_bootstrap,
                                   framework,
                                   with_replacement = TRUE) {
  
  bootstrap_ecdfs <- vector("list", n_bootstrap)
  
  for (i in 1:n_bootstrap) {
    # Sample with or without replacement
    sample_data <- sample(data, size = n_sample, replace = with_replacement)
    
    # Fit I-spline using fixed framework
    fit <- fit_ispline_sample(
      sample_data = sample_data,
      knot_locations = framework$knot_locations,
      boundaries = c(framework$boundary_min, framework$boundary_max),
      x_eval = framework$x_grid
    )
    
    bootstrap_ecdfs[[i]] <- fit$smooth_ecdf
  }
  
  return(bootstrap_ecdfs)
}


################################################################################
### ENHANCED SMOOTHING METHODS (Based on ChatGPT Q-spline discussion)
################################################################################

#' Fit Q-Spline (Quantile Function) with I-splines
#' 
#' Fits a monotone smooth quantile function Q(p) = F^(-1)(p) directly.
#' This provides trivial invertibility and is more stable for simulation.
#' 
#' @param scale_scores Vector of scores
#' @param knot_probs Quantile probabilities for knot placement (default: seq(0.1, 0.9, 0.1))
#' @param n_eval Number of evaluation points
#' @param min_derivative Minimum derivative to ensure strict monotonicity (default 1e-6)
#' 
#' @return List with quantile function, CDF function, and diagnostics
fit_qspline <- function(scale_scores,
                       knot_probs = seq(0.1, 0.9, by = 0.1),
                       n_eval = 500,
                       min_derivative = 1e-6) {
  
  # Remove NAs and sort
  x_sorted <- sort(scale_scores[!is.na(scale_scores)])
  n <- length(x_sorted)
  
  # Plotting positions (probability values) - mid-ranks
  p_vals <- (1:n - 0.5) / n
  
  # Create I-spline basis on probability scale [0,1]
  qspline_basis <- iSpline(p_vals,
                           knots = knot_probs,
                           Boundary.knots = c(0, 1),
                           degree = 3,
                           intercept = TRUE)
  
  # Fit Q(p) = x using constrained LS with minimum derivative
  n_basis <- ncol(qspline_basis)
  
  objective <- function(coef) {
    fitted <- qspline_basis %*% coef
    sum((fitted - x_sorted)^2)
  }
  
  init_coef <- rep(1/n_basis, n_basis)
  
  result <- optim(par = init_coef,
                  fn = objective,
                  method = "L-BFGS-B",
                  lower = rep(min_derivative, n_basis),
                  upper = rep(Inf, n_basis))
  
  coef_q <- result$par
  
  # Quantile function: p → x
  quantile_function <- function(p) {
    # Constrain p to [0, 1]
    p <- pmax(1e-10, pmin(1 - 1e-10, p))
    basis_p <- iSpline(p,
                      knots = knot_probs,
                      Boundary.knots = c(0, 1),
                      degree = 3,
                      intercept = TRUE)
    as.vector(basis_p %*% coef_q)
  }
  
  # CDF function: x → p (pre-tabulate for efficiency)
  x_min <- min(x_sorted)
  x_max <- max(x_sorted)
  x_grid <- seq(x_min, x_max, length.out = n_eval)
  p_grid <- seq(0, 1, length.out = n_eval)
  x_from_p <- quantile_function(p_grid)
  
  # Use approxfun with monotone constraint
  cdf_function <- approxfun(x_from_p, p_grid, 
                            yleft = 0, yright = 1, 
                            rule = 2, ties = "ordered")
  
  return(list(
    quantile_function = quantile_function,  # Q(p): [0,1] → scores
    cdf_function = cdf_function,           # F(x): scores → [0,1]
    coef = coef_q,
    knot_probs = knot_probs,
    n_knots = length(knot_probs),
    method = "qspline",
    x_range = c(x_min, x_max),
    convergence = result$convergence
  ))
}


#' Select Smoothing by PIT Uniformity
#' 
#' Tests different knot configurations and selects based on 
#' Cramér-von Mises distance to Uniform(0,1). This directly
#' targets what copulas need - proper transformation to [0,1].
#' 
#' @param scale_scores Vector of scores
#' @param knot_configs List of knot percentile configurations to test
#' @param use_tail_aware If TRUE, add extra tail knots to each configuration
#' 
#' @return List with best configuration and all results
select_smoothing_by_pit <- function(scale_scores,
                                   knot_configs = list(
                                     c(0.5),
                                     c(0.33, 0.67),
                                     c(0.25, 0.5, 0.75),
                                     c(0.2, 0.4, 0.6, 0.8),
                                     seq(0.1, 0.9, 0.1)
                                   ),
                                   use_tail_aware = FALSE) {
  
  n <- length(scale_scores)
  
  # Function to compute CvM statistic for PIT ~ Uniform[0,1]
  cvm_uniform <- function(u) {
    u_sorted <- sort(u)
    i <- 1:length(u)
    # Cramér-von Mises statistic
    cvm <- (1/(12*length(u))) + sum((u_sorted - (2*i - 1)/(2*length(u)))^2)
    return(cvm)
  }
  
  # Anderson-Darling statistic
  ad_uniform <- function(u) {
    u_sorted <- sort(u)
    n_u <- length(u)
    i <- 1:n_u
    ad <- -n_u - sum((2*i - 1) * (log(u_sorted) + log(1 - rev(u_sorted)))) / n_u
    return(ad)
  }
  
  results <- list()
  
  for (i in seq_along(knot_configs)) {
    knots <- knot_configs[[i]]
    
    # Add tail knots if requested
    if (use_tail_aware) {
      tail_lower <- c(0.01, 0.05, 0.10)
      tail_upper <- c(0.90, 0.95, 0.99)
      knots <- unique(sort(c(tail_lower[tail_lower < min(knots)],
                            knots,
                            tail_upper[tail_upper > max(knots)])))
    }
    
    # Fit I-spline with these knots
    framework <- tryCatch({
      create_ispline_framework(scale_scores, 
                              knot_percentiles = knots)
    }, error = function(e) {
      return(NULL)
    })
    
    if (is.null(framework)) {
      next
    }
    
    # Transform to PITs
    pit_values <- framework$smooth_ecdf_full(scale_scores)
    pit_values <- pmax(1e-10, pmin(1 - 1e-10, pit_values))
    
    # Compute uniformity statistics
    cvm_stat <- cvm_uniform(pit_values)
    ad_stat <- ad_uniform(pit_values)
    
    # Kolmogorov-Smirnov
    ks_result <- ks.test(pit_values, "punif", 0, 1)
    
    results[[i]] <- list(
      knots = knots,
      n_knots = length(knots),
      cvm = cvm_stat,
      ad = ad_stat,
      ks_statistic = ks_result$statistic,
      ks_pvalue = ks_result$p.value,
      framework = framework
    )
  }
  
  # Remove NULL results
  results <- results[!sapply(results, is.null)]
  
  if (length(results) == 0) {
    stop("All knot configurations failed")
  }
  
  # Select best by CvM (smaller is better)
  cvm_values <- sapply(results, function(x) x$cvm)
  best_idx <- which.min(cvm_values)
  
  return(list(
    best = results[[best_idx]],
    all_results = results,
    selection_criterion = "CvM_to_Uniform",
    cvm_values = cvm_values
  ))
}


#' Fit Mid-Rank PIT (No Smoothing Baseline)
#' 
#' Uses simple mid-rank transformation (rank - 0.5) / n with no smoothing.
#' This is the critical baseline for assessing smoothing sensitivity.
#' 
#' @param scale_scores Vector of scores
#' @param x_eval Optional evaluation points
#' 
#' @return List with PIT function and evaluations
fit_midrank_pit <- function(scale_scores, x_eval = NULL) {
  
  scale_scores <- scale_scores[!is.na(scale_scores)]
  n <- length(scale_scores)
  
  # Mid-rank transformation function
  pit_function <- function(x) {
    ranks <- sapply(x, function(xi) sum(scale_scores <= xi))
    (ranks - 0.5) / n
  }
  
  # Evaluate if x_eval provided
  if (!is.null(x_eval)) {
    y_eval <- pit_function(x_eval)
  } else {
    x_eval <- sort(unique(scale_scores))
    y_eval <- pit_function(x_eval)
  }
  
  return(list(
    pit_function = pit_function,
    x_eval = x_eval,
    y_eval = y_eval,
    method = "mid_ranks",
    n_obs = n
  ))
}


#' Create I-Spline Framework with Enhanced Options
#' 
#' Enhanced version of create_ispline_framework with tail-aware knot placement
#' and strict monotonicity options.
#' 
#' @param scale_scores Vector of scale scores
#' @param knot_percentiles Percentiles at which to place knots
#' @param tail_aware If TRUE, add extra knots near 0 and 1 for better tail behavior
#' @param min_derivative Minimum derivative for strict monotonicity (default 1e-6)
#' @param n_eval Number of evaluation points for grid
#' 
#' @return List containing enhanced framework
create_ispline_framework_enhanced <- function(scale_scores,
                                             knot_percentiles = c(0.20, 0.40, 0.60, 0.80),
                                             tail_aware = TRUE,
                                             min_derivative = 1e-6,
                                             n_eval = 500) {
  
  # Remove NAs
  scale_scores <- scale_scores[!is.na(scale_scores)]
  
  # Add tail knots if requested
  if (tail_aware) {
    tail_knots_lower <- c(0.01, 0.05, 0.10)
    tail_knots_upper <- c(0.90, 0.95, 0.99)
    
    # Only add tail knots that don't overlap with existing knots
    knot_percentiles <- unique(sort(c(
      tail_knots_lower[tail_knots_lower < min(knot_percentiles)],
      knot_percentiles,
      tail_knots_upper[tail_knots_upper > max(knot_percentiles)]
    )))
  }
  
  # Establish boundaries
  boundary_min <- min(scale_scores)
  boundary_max <- max(scale_scores)
  
  # Fixed knot locations at specified percentiles
  knot_locations <- quantile(scale_scores, probs = knot_percentiles)
  
  # Create evaluation grid
  x_grid <- seq(boundary_min, boundary_max, length.out = n_eval)
  
  # Create empirical CDF
  ecdf_full <- ecdf(scale_scores)
  y_ecdf_full <- ecdf_full(x_grid)
  
  # Create I-spline basis matrix
  ispline_basis <- iSpline(x_grid,
                           knots = knot_locations,
                           Boundary.knots = c(boundary_min, boundary_max),
                           degree = 3,
                           intercept = TRUE)
  
  # Fit baseline I-spline with minimum derivative
  n_basis <- ncol(ispline_basis)
  
  objective <- function(coef) {
    fitted <- ispline_basis %*% coef
    sum((fitted - y_ecdf_full)^2)
  }
  
  init_coef <- rep(1/n_basis, n_basis)
  
  result <- optim(par = init_coef,
                  fn = objective,
                  method = "L-BFGS-B",
                  lower = rep(min_derivative, n_basis),
                  upper = rep(Inf, n_basis))
  
  coef_full <- result$par
  y_full_smooth <- as.vector(ispline_basis %*% coef_full)
  
  # Create function for evaluation at arbitrary points
  smooth_ecdf_full <- function(x) {
    basis_x <- iSpline(x,
                       knots = knot_locations,
                       Boundary.knots = c(boundary_min, boundary_max),
                       degree = 3,
                       intercept = TRUE)
    as.vector(basis_x %*% coef_full)
  }
  
  return(list(
    boundary_min = boundary_min,
    boundary_max = boundary_max,
    knot_locations = knot_locations,
    knot_percentiles = knot_percentiles,
    x_grid = x_grid,
    coef_full = coef_full,
    y_full_smooth = y_full_smooth,
    smooth_ecdf_full = smooth_ecdf_full,
    n_observations = length(scale_scores),
    tail_aware = tail_aware,
    min_derivative = min_derivative,
    n_knots = length(knot_locations)
  ))
}


################################################################################
### UTILITY FUNCTIONS
################################################################################

#' Print I-Spline Framework Summary
#' 
#' Display summary information about an I-spline framework
#' 
#' @param framework I-spline framework object
#' @param label Optional label for the framework (e.g., "Prior Grade 4")
print_ispline_framework <- function(framework, label = NULL) {
  
  if (!is.null(label)) {
    cat("=== I-Spline Framework:", label, "===\n")
  } else {
    cat("=== I-Spline Framework ===\n")
  }
  
  cat("Observations:", framework$n_observations, "\n")
  cat("Boundaries: [", framework$boundary_min, ",", 
      framework$boundary_max, "]\n")
  cat("Knots at percentiles:", 
      paste0(framework$knot_percentiles * 100, "%", collapse = ", "), "\n")
  cat("Knot locations:", paste(round(framework$knot_locations, 2), collapse = ", "), "\n")
  cat("Number of knots:", length(framework$knot_locations), "\n")
  cat("Evaluation grid:", length(framework$x_grid), "points\n")
  
  if (!is.null(framework$tail_aware)) {
    cat("Tail-aware knots:", framework$tail_aware, "\n")
  }
  if (!is.null(framework$min_derivative)) {
    cat("Min derivative (epsilon):", framework$min_derivative, "\n")
  }
  
  cat("\n")
}
