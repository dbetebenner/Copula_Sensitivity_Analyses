################################################################################
### Bernstein/Empirical-Beta CDF Smoother
### Shape-safe smoothing on [0,1] using Bernstein polynomials
################################################################################

#' Fit Bernstein CDF smoother
#' 
#' Uses Bernstein polynomials to create a smooth, monotone CDF approximation.
#' Bernstein polynomials provide excellent shape preservation and boundary behavior.
#' 
#' @param scores Numeric vector of observed scores
#' @param degree Bernstein polynomial degree (default: auto-tuned by CV)
#' @param tune_by_cv If TRUE, auto-tune degree by cross-validation (default: TRUE)
#' @param n_eval Number of evaluation points for lookup table (default: 1000)
#' 
#' @return List with F (CDF), F_inv (quantile), and method metadata
#' 
#' @details
#' Bernstein polynomials B_k^n(x) = choose(n,k) * x^k * (1-x)^(n-k) provide
#' a shape-preserving basis for approximating cumulative distribution functions.
#' 
#' The CDF is approximated as F(x) = sum_{k=0}^{n} β_k * B_k^n((x-min)/(max-min))
#' where β_k are constrained to be monotone: 0 = β_0 <= β_1 <= ... <= β_n = 1.
#' 
#' This ensures the fitted CDF is monotone, has proper boundaries (0 and 1),
#' and maintains smooth tail behavior.
fit_bernstein_cdf <- function(scores, 
                               degree = NULL,
                               tune_by_cv = TRUE,
                               n_eval = 1000) {
  
  # Remove NAs
  scores <- scores[!is.na(scores)]
  n <- length(scores)
  
  # Normalize scores to [0, 1]
  score_min <- min(scores)
  score_max <- max(scores)
  score_range <- score_max - score_min
  
  if (score_range < 1e-10) {
    stop("Scores have zero variance - cannot fit Bernstein CDF")
  }
  
  scores_norm <- (scores - score_min) / score_range
  
  # Auto-tune degree if requested
  if (is.null(degree) && tune_by_cv) {
    degree <- tune_bernstein_degree(scores_norm, n)
  } else if (is.null(degree)) {
    # Default: sqrt(n) but capped at 100 for computational efficiency
    degree <- min(ceiling(sqrt(n)), 100)
  }
  
  # Compute empirical CDF on fine grid
  ecdf_fun <- ecdf(scores_norm)
  x_grid <- seq(0, 1, length.out = n_eval)
  F_emp <- ecdf_fun(x_grid)
  
  # Construct Bernstein basis matrix
  # B_k^n(x) = choose(n, k) * x^k * (1-x)^(n-k)
  basis <- sapply(0:degree, function(k) {
    choose(degree, k) * x_grid^k * (1 - x_grid)^(degree - k)
  })
  
  # Fit monotone coefficients using isotonic regression
  # This is simpler and faster than constrained QP
  
  # Method 1: Simple projection - fit unconstrained, then project to monotone
  # Solve: min ||F_emp - B*β||^2 (unconstrained)
  coefs_unconstrained <- qr.solve(basis, F_emp)
  
  # Project to monotone space: 0 <= β_0 <= β_1 <= ... <= β_n <= 1
  coefs <- coefs_unconstrained
  coefs[1] <- max(0, min(coefs[1], 1))  # First coef in [0, 1]
  
  for (i in 2:(degree + 1)) {
    # Enforce β_i >= β_{i-1}
    coefs[i] <- max(coefs[i-1], coefs[i])
    # Enforce β_i <= 1
    coefs[i] <- min(coefs[i], 1)
  }
  
  # Ensure boundary conditions
  coefs[1] <- 0
  coefs[degree + 1] <- 1
  
  # Compute fitted values on grid
  F_fitted <- basis %*% coefs
  F_fitted <- pmax(0, pmin(1, F_fitted))  # Clamp to [0, 1]
  
  # Create forward function F(x) using lookup table
  # Interpolate on normalized scale, then denormalize
  F_forward <- function(x) {
    x_norm <- (x - score_min) / score_range
    x_norm <- pmax(0, pmin(1, x_norm))  # Clamp to [0, 1]
    
    # Linear interpolation on pre-computed grid
    approx(x_grid, F_fitted, xout = x_norm, 
           yleft = 0, yright = 1, rule = 2)$y
  }
  
  # Create inverse function F_inv(p) using lookup table
  # Find x where F(x) = p
  F_inverse <- function(p) {
    p <- pmax(0, pmin(1, p))  # Clamp to [0, 1]
    
    # Inverse interpolation: swap x and y axes
    x_norm <- approx(F_fitted, x_grid, xout = p,
                     yleft = 0, yright = 1, rule = 2)$y
    
    # Denormalize
    score_min + x_norm * score_range
  }
  
  return(list(
    method = "Bernstein CDF (Empirical-Beta)",
    F = F_forward,
    F_inv = F_inverse,
    degree = degree,
    coefs = coefs,
    score_range = c(score_min, score_max),
    x_grid = x_grid,
    F_fitted = as.vector(F_fitted),
    n_params = degree + 1
  ))
}


#' Tune Bernstein degree by cross-validation
#' 
#' @param scores_norm Normalized scores in [0, 1]
#' @param n Sample size
#' @param degree_candidates Candidate degrees to test
#' @param n_folds Number of CV folds (default: 5)
#' 
#' @return Optimal degree
tune_bernstein_degree <- function(scores_norm,
                                   n,
                                   degree_candidates = NULL,
                                   n_folds = 5) {
  
  # Default candidates based on sample size
  if (is.null(degree_candidates)) {
    sqrt_n <- ceiling(sqrt(n))
    degree_candidates <- unique(c(
      ceiling(sqrt_n / 2),   # Conservative
      sqrt_n,                # Default
      ceiling(sqrt_n * 1.5), # Flexible
      ceiling(sqrt_n * 2)    # Very flexible
    ))
    # Cap at 100 for computational efficiency
    degree_candidates <- degree_candidates[degree_candidates <= 100]
  }
  
  # Skip CV for small samples
  if (n < 100) {
    return(min(degree_candidates))
  }
  
  # Create folds
  fold_ids <- sample(rep(1:n_folds, length.out = n))
  
  # Evaluate each candidate
  cv_scores <- sapply(degree_candidates, function(d) {
    
    fold_errors <- sapply(1:n_folds, function(fold) {
      
      # Split data
      train_idx <- fold_ids != fold
      test_idx <- fold_ids == fold
      
      if (sum(test_idx) < 10) return(NA)  # Skip small test sets
      
      # Fit on training data
      tryCatch({
        fit <- fit_bernstein_cdf(scores_norm[train_idx] * 100,  # Denormalize temporarily
                                degree = d, 
                                tune_by_cv = FALSE)
        
        # Evaluate PIT uniformity on test data
        U_test <- fit$F(scores_norm[test_idx] * 100)
        
        # Cramér-von Mises distance to U(0,1)
        U_sorted <- sort(U_test)
        n_test <- length(U_test)
        i <- 1:n_test
        cvm <- (1/(12*n_test)) + sum((U_sorted - (2*i - 1)/(2*n_test))^2)
        
        return(cvm)
      }, error = function(e) {
        return(NA)
      })
    })
    
    # Return mean CV error (ignore NAs)
    mean(fold_errors, na.rm = TRUE)
  })
  
  # Handle case where all CV scores are NA
  if (all(is.na(cv_scores))) {
    return(ceiling(sqrt(n)))
  }
  
  # Select degree with minimum CV error
  best_idx <- which.min(cv_scores)
  best_degree <- degree_candidates[best_idx]
  
  return(best_degree)
}


#' Diagnostic function to compare Bernstein fit to empirical CDF
#' 
#' @param scores Original scores
#' @param bernstein_fit Result from fit_bernstein_cdf()
#' 
#' @return List with fit quality metrics
diagnose_bernstein_fit <- function(scores, bernstein_fit) {
  
  # Compute empirical CDF
  ecdf_fun <- ecdf(scores)
  
  # Evaluate on fine grid
  x_eval <- seq(min(scores), max(scores), length.out = 1000)
  F_emp <- ecdf_fun(x_eval)
  F_fitted <- bernstein_fit$F(x_eval)
  
  # Compute error metrics
  mae <- mean(abs(F_fitted - F_emp))
  rmse <- sqrt(mean((F_fitted - F_emp)^2))
  max_error <- max(abs(F_fitted - F_emp))
  
  # Check monotonicity (should be perfect)
  is_monotone <- all(diff(F_fitted) >= -1e-10)  # Allow tiny numerical errors
  
  # Check boundary conditions
  F_min <- bernstein_fit$F(min(scores))
  F_max <- bernstein_fit$F(max(scores))
  boundary_ok <- (F_min < 0.01) && (F_max > 0.99)
  
  return(list(
    mae = mae,
    rmse = rmse,
    max_error = max_error,
    is_monotone = is_monotone,
    boundary_ok = boundary_ok,
    degree = bernstein_fit$degree,
    n_params = bernstein_fit$n_params
  ))
}
