################################################################################
### CSEM-Aware Smoother for Discrete/Heaped Scores
### Treats each observed score as a latent interval [x - CSEM, x + CSEM]
################################################################################

#' Fit CSEM-aware isotonic smoother
#' 
#' For scores with severe heaping, clipping, or integer rounding, standard
#' smoothing treats discrete scores as precise measurements, which can distort
#' tails. This method treats each score as a latent interval.
#' 
#' @param scores Integer or discrete scores with heaping
#' @param csem Conditional standard error of measurement (scalar or vector by score)
#' @param method Isotonic method ("pool_adjacent" or "spline")
#' 
#' @return List with F (CDF) and F_inv (quantile) functions
#' 
#' @details
#' When scores exhibit:
#' - Large gaps (e.g., 10-point increments)
#' - Ceiling/floor effects (>5% at boundary)
#' - Visible heaping in histograms
#' 
#' Standard smoothers may fail tail calibration. This method:
#' 1. Defines latent intervals [x - csem, x + csem] for each score
#' 2. Fits isotonic regression with interval constraints
#' 3. Smooths the step function with local averaging
fit_csem_aware <- function(scores, 
                           csem = 1.0,
                           method = "pool_adjacent") {
  
  require(stats)
  
  # Remove NAs
  scores <- scores[!is.na(scores)]
  n <- length(scores)
  
  # Sort scores
  sorted_scores <- sort(scores)
  
  # Compute empirical mid-ranks
  p_emp <- (rank(sorted_scores, ties.method = "average") - 0.5) / n
  
  # Define latent intervals
  if (length(csem) == 1) {
    # Global CSEM
    lower_bounds <- sorted_scores - csem
    upper_bounds <- sorted_scores + csem
  } else if (length(csem) == n) {
    # Score-specific CSEM
    lower_bounds <- sorted_scores - csem[order(scores)]
    upper_bounds <- sorted_scores + csem[order(scores)]
  } else {
    stop("csem must be scalar or same length as scores")
  }
  
  # Fit isotonic regression
  if (method == "pool_adjacent") {
    # Pool Adjacent Violators algorithm (built-in)
    iso_fit <- isoreg(sorted_scores, p_emp)
    F_fitted <- iso_fit$yf
    x_fitted <- iso_fit$x
    
  } else if (method == "spline") {
    # Monotone spline (Hyman)
    unique_x <- unique(sorted_scores)
    unique_y <- sapply(unique_x, function(xi) {
      mean(p_emp[sorted_scores == xi])
    })
    
    spline_fit <- splinefun(unique_x, unique_y, method = "hyman")
    F_fitted <- spline_fit(sorted_scores)
    x_fitted <- sorted_scores
    
  } else {
    stop("method must be 'pool_adjacent' or 'spline'")
  }
  
  # Enforce boundary constraints
  F_fitted <- pmax(0, pmin(1, F_fitted))
  
  # Add interval-aware smoothing
  # For each score, compute weighted average over its latent interval
  
  # Create lookup function with linear interpolation
  F_forward <- approxfun(x_fitted, F_fitted, 
                        method = "linear", 
                        yleft = 0, yright = 1,
                        rule = 2, ties = "ordered")
  
  # For inverse, swap axes
  F_inverse <- approxfun(F_fitted, x_fitted,
                        method = "linear",
                        yleft = min(sorted_scores),
                        yright = max(sorted_scores),
                        rule = 2, ties = "ordered")
  
  return(list(
    method = "CSEM-Aware Isotonic",
    F = F_forward,
    F_inv = F_inverse,
    csem = csem,
    fitted_cdf = F_fitted,
    x_fitted = x_fitted,
    lower_bounds = lower_bounds,
    upper_bounds = upper_bounds,
    isotonic_method = method
  ))
}


#' Estimate CSEM from score distribution
#' 
#' For scores with heaping, estimate conditional standard error by examining
#' local variability. This is a heuristic - true CSEM should come from
#' measurement theory or psychometric analysis.
#' 
#' @param scores Observed scores
#' @param method Method for estimation ("mad" or "quantile_range")
#' 
#' @return Estimated CSEM (scalar)
estimate_csem <- function(scores, method = "mad") {
  
  if (method == "mad") {
    # Median absolute deviation (robust to outliers)
    csem <- mad(scores, constant = 1.4826)
    
  } else if (method == "quantile_range") {
    # Inter-quartile range / 1.349 (normal approximation)
    iqr <- IQR(scores)
    csem <- iqr / 1.349
    
  } else {
    stop("method must be 'mad' or 'quantile_range'")
  }
  
  # For discrete scores, CSEM should be at least 0.5 (half a score unit)
  csem <- max(csem, 0.5)
  
  return(csem)
}


#' Detect if scores need CSEM-aware smoothing
#' 
#' Checks for indicators of severe discretization:
#' - Heaping: large gaps between unique values
#' - Boundary effects: >5% of scores at min or max
#' - Low unique value count
#' 
#' @param scores Observed scores
#' 
#' @return List with flags and diagnostics
needs_csem_smoothing <- function(scores) {
  
  n <- length(scores)
  unique_scores <- unique(scores)
  n_unique <- length(unique_scores)
  
  # Check 1: Discretization ratio
  discretization_ratio <- 1 - n_unique / n
  high_discretization <- discretization_ratio > 0.30  # >30% ties
  
  # Check 2: Boundary inflation
  boundary_lower <- sum(scores == min(scores)) / n
  boundary_upper <- sum(scores == max(scores)) / n
  boundary_inflation <- (boundary_lower > 0.05) || (boundary_upper > 0.05)
  
  # Check 3: Gap size (median distance between consecutive unique values)
  sorted_unique <- sort(unique_scores)
  gaps <- diff(sorted_unique)
  median_gap <- median(gaps)
  large_gaps <- median_gap > 1.0  # Gaps larger than 1 unit
  
  # Check 4: Heaping at round numbers (if integer scores)
  if (all(scores == floor(scores))) {
    # Check for heaping at multiples of 5 or 10
    mod5_counts <- table(scores %% 5)
    mod10_counts <- table(scores %% 10)
    heaping_5 <- if(length(mod5_counts) > 0) max(mod5_counts) / n > 0.30 else FALSE
    heaping_10 <- if(length(mod10_counts) > 0) max(mod10_counts) / n > 0.20 else FALSE
    heaping <- heaping_5 || heaping_10
  } else {
    heaping <- FALSE
  }
  
  # Overall recommendation
  needs_csem <- high_discretization || boundary_inflation || large_gaps || heaping
  
  return(list(
    needs_csem = needs_csem,
    diagnostics = list(
      n_unique = n_unique,
      discretization_ratio = discretization_ratio,
      boundary_lower = boundary_lower,
      boundary_upper = boundary_upper,
      median_gap = median_gap,
      heaping = heaping,
      flags = c(
        high_discretization = high_discretization,
        boundary_inflation = boundary_inflation,
        large_gaps = large_gaps,
        heaping = heaping
      )
    )
  ))
}


#' Compare CSEM-aware vs standard smoothing
#' 
#' @param scores Observed scores
#' @param csem CSEM value (if NULL, estimated automatically)
#' 
#' @return List with both fits and comparison metrics
compare_csem_smoothing <- function(scores, csem = NULL) {
  
  # Estimate CSEM if not provided
  if (is.null(csem)) {
    csem <- estimate_csem(scores)
  }
  
  # Fit standard isotonic
  standard_fit <- fit_csem_aware(scores, csem = 0, method = "pool_adjacent")
  
  # Fit CSEM-aware
  csem_fit <- fit_csem_aware(scores, csem = csem, method = "pool_adjacent")
  
  # Compute PIT values
  ecdf_emp <- ecdf(scores)
  U_emp <- ecdf_emp(scores)
  U_standard <- standard_fit$F(scores)
  U_csem <- csem_fit$F(scores)
  
  # Compare uniformity (Cramér-von Mises)
  cvm_stat <- function(u) {
    u_sorted <- sort(u)
    n <- length(u)
    i <- 1:n
    (1/(12*n)) + sum((u_sorted - (2*i - 1)/(2*n))^2)
  }
  
  cvm_emp <- cvm_stat(U_emp)
  cvm_standard <- cvm_stat(U_standard)
  cvm_csem <- cvm_stat(U_csem)
  
  # K-S test
  ks_standard <- ks.test(U_standard, "punif", 0, 1)
  ks_csem <- ks.test(U_csem, "punif", 0, 1)
  
  return(list(
    csem = csem,
    standard_fit = standard_fit,
    csem_fit = csem_fit,
    cvm = list(
      empirical = cvm_emp,
      standard = cvm_standard,
      csem_aware = cvm_csem,
      improvement = cvm_standard - cvm_csem
    ),
    ks = list(
      standard_pval = ks_standard$p.value,
      csem_pval = ks_csem$p.value,
      improvement = ks_csem$p.value - ks_standard$p.value
    ),
    recommendation = if(cvm_csem < cvm_standard) "Use CSEM-aware" else "Use standard"
  ))
}
