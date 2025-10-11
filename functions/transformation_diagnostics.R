############################################################################
### TRANSFORMATION DIAGNOSTICS FRAMEWORK
### Comprehensive diagnostics for evaluating marginal transformation quality
### in copula analysis
############################################################################

require(data.table)

#' Compute Uniformity Diagnostics for Pseudo-Observations
#' 
#' Tests whether transformed pseudo-observations U, V follow Uniform(0,1).
#' This is CRITICAL for valid copula inference.
#' 
#' @param U Vector of transformed prior scores (pseudo-observations)
#' @param V Vector of transformed current scores (pseudo-observations)
#' 
#' @return List with uniformity metrics
compute_uniformity_diagnostics <- function(U, V) {
  
  # Helper: Cramér-von Mises statistic
  cvm_stat <- function(u) {
    u_sorted <- sort(u)
    n <- length(u)
    i <- 1:n
    (1/(12*n)) + sum((u_sorted - (2*i - 1)/(2*n))^2)
  }
  
  # Helper: Anderson-Darling statistic
  ad_stat <- function(u) {
    u_sorted <- sort(u)
    n <- length(u)
    i <- 1:n
    -n - sum((2*i - 1) * (log(u_sorted) + log(1 - rev(u_sorted)))) / n
  }
  
  # Test U
  ks_U <- ks.test(U, "punif", 0, 1)
  cvm_U <- cvm_stat(U)
  ad_U <- ad_stat(U)
  
  # Test V
  ks_V <- ks.test(V, "punif", 0, 1)
  cvm_V <- cvm_stat(V)
  ad_V <- ad_stat(V)
  
  # Combined assessment
  combined_ks_pval <- min(ks_U$p.value, ks_V$p.value)
  
  # Discretization check
  n_unique_U <- length(unique(U))
  n_unique_V <- length(unique(V))
  tie_prop_U <- 1 - n_unique_U / length(U)
  tie_prop_V <- 1 - n_unique_V / length(V)
  
  # Moment checks (should match Uniform(0,1))
  skewness <- function(x) {
    n <- length(x)
    m3 <- sum((x - mean(x))^3) / n
    s3 <- (sum((x - mean(x))^2) / n)^(3/2)
    m3 / s3
  }
  
  return(list(
    # K-S tests
    ks_U_stat = ks_U$statistic,
    ks_U_pval = ks_U$p.value,
    ks_V_stat = ks_V$statistic,
    ks_V_pval = ks_V$p.value,
    combined_ks_pval = combined_ks_pval,
    
    # CvM tests
    cvm_U = cvm_U,
    cvm_V = cvm_V,
    
    # Anderson-Darling tests
    ad_U = ad_U,
    ad_V = ad_V,
    
    # Moments (Uniform(0,1) has mean=0.5, sd=0.289, skew=0)
    mean_U = mean(U),
    mean_V = mean(V),
    sd_U = sd(U),
    sd_V = sd(V),
    skew_U = skewness(U),
    skew_V = skewness(V),
    
    # Discretization
    n_unique_U = n_unique_U,
    n_unique_V = n_unique_V,
    tie_proportion_U = tie_prop_U,
    tie_proportion_V = tie_prop_V,
    
    # Overall pass/fail (liberal: p > 0.01)
    passes_ks_liberal = combined_ks_pval > 0.01,
    passes_ks_standard = combined_ks_pval > 0.05
  ))
}


#' Compute Dependence Diagnostics
#' 
#' Measures how well the transformation preserves dependence structure
#' compared to empirical baseline.
#' 
#' @param U Transformed prior scores
#' @param V Transformed current scores
#' @param empirical_baseline Results from baseline method (empirical ranks)
#' 
#' @return List with dependence metrics
compute_dependence_diagnostics <- function(U, V, empirical_baseline = NULL) {
  
  # Kendall's tau
  tau <- cor(U, V, method = "kendall")
  
  # Spearman's rho
  rho <- cor(U, V, method = "spearman")
  
  # Pearson correlation on pseudo-observations
  pearson_UV <- cor(U, V, method = "pearson")
  
  result <- list(
    kendall_tau = tau,
    spearman_rho = rho,
    pearson_corr = pearson_UV
  )
  
  # If baseline provided, compute bias and relative error
  if (!is.null(empirical_baseline)) {
    tau_baseline <- empirical_baseline$kendall_tau
    rho_baseline <- empirical_baseline$spearman_rho
    
    result$tau_bias = tau - tau_baseline
    result$tau_relative_error = (tau - tau_baseline) / tau_baseline
    result$rho_bias = rho - rho_baseline
    result$rho_relative_error = (rho - rho_baseline) / rho_baseline
    
    # Pass/fail (±5% tolerance on tau)
    result$preserves_dependence = abs(result$tau_relative_error) < 0.05
  }
  
  return(result)
}


#' Compute Tail Structure Diagnostics
#' 
#' Measures concentration in tails and compares to empirical baseline.
#' Critical for tail dependence copulas (t, Clayton, Gumbel).
#' 
#' @param U Transformed prior scores
#' @param V Transformed current scores
#' @param empirical_baseline Results from baseline method
#' 
#' @return List with tail metrics
compute_tail_diagnostics <- function(U, V, empirical_baseline = NULL) {
  
  # Concentration ratios at different thresholds
  lower_01 <- sum(U < 0.01 & V < 0.01) / length(U)
  lower_05 <- sum(U < 0.05 & V < 0.05) / length(U)
  lower_10 <- sum(U < 0.10 & V < 0.10) / length(U)
  
  upper_90 <- sum(U > 0.90 & V > 0.90) / length(U)
  upper_95 <- sum(U > 0.95 & V > 0.95) / length(U)
  upper_99 <- sum(U > 0.99 & V > 0.99) / length(U)
  
  # Chi-plot values (exceedance correlation)
  compute_chi <- function(u, v, threshold) {
    u_exceed <- u > threshold
    v_exceed <- v > threshold
    both_exceed <- u_exceed & v_exceed
    
    if (sum(both_exceed) < 10) return(NA)
    
    # Conditional probability P(V > threshold | U > threshold)
    sum(both_exceed) / sum(u_exceed)
  }
  
  chi_90 <- compute_chi(U, V, 0.90)
  chi_95 <- compute_chi(U, V, 0.95)
  chi_99 <- compute_chi(U, V, 0.99)
  
  result <- list(
    # Concentration ratios
    lower_01 = lower_01,
    lower_05 = lower_05,
    lower_10 = lower_10,
    upper_90 = upper_90,
    upper_95 = upper_95,
    upper_99 = upper_99,
    
    # Chi values
    chi_90 = chi_90,
    chi_95 = chi_95,
    chi_99 = chi_99
  )
  
  # If baseline provided, compute distortion
  if (!is.null(empirical_baseline)) {
    result$tail_distortion_lower = abs(lower_10 - empirical_baseline$lower_10)
    result$tail_distortion_upper = abs(upper_90 - empirical_baseline$upper_90)
    
    # Pass/fail (±20% tolerance on concentration ratios)
    result$preserves_tail_lower = result$tail_distortion_lower < (0.20 * empirical_baseline$lower_10)
    result$preserves_tail_upper = result$tail_distortion_upper < (0.20 * empirical_baseline$upper_90)
  }
  
  return(result)
}


#' Compute Practical Utility Metrics
#' 
#' Assesses computational cost, invertibility, and numerical stability.
#' 
#' @param framework Transformation framework object
#' @param n_test Number of test evaluations for timing (default 1000)
#' 
#' @return List with utility metrics
compute_utility_diagnostics <- function(framework, n_test = 1000) {
  
  # Check if invertible
  has_inverse <- !is.null(framework$quantile_function) || 
                 !is.null(framework$inverse_function)
  
  # Timing test
  if (!is.null(framework$cdf_function)) {
    test_vals <- runif(n_test, 
                      min = framework$x_range[1], 
                      max = framework$x_range[2])
    
    timing <- system.time({
      framework$cdf_function(test_vals)
    })
    
    time_per_1000 <- timing["elapsed"]
  } else if (!is.null(framework$smooth_ecdf_full)) {
    test_vals <- runif(n_test,
                      min = framework$boundary_min,
                      max = framework$boundary_max)
    
    timing <- system.time({
      framework$smooth_ecdf_full(test_vals)
    })
    
    time_per_1000 <- timing["elapsed"]
  } else {
    time_per_1000 <- NA
  }
  
  return(list(
    is_invertible = has_inverse,
    time_per_1000_evals = time_per_1000,
    method = ifelse(!is.null(framework$method), framework$method, "unknown"),
    n_knots = ifelse(!is.null(framework$n_knots), framework$n_knots, 
                    ifelse(!is.null(framework$knot_locations), 
                          length(framework$knot_locations), NA))
  ))
}


#' Classify Transformation Method Quality
#' 
#' Applies acceptance criteria to determine if method is suitable for Phase 2.
#' 
#' @param uniformity Uniformity diagnostics
#' @param dependence Dependence diagnostics
#' @param tail Tail diagnostics
#' @param copula_results Copula fit results
#' @param empirical_best_family Best family from empirical ranks (gold standard)
#' 
#' @return List with classification and tier scores
classify_transformation_method <- function(uniformity,
                                          dependence,
                                          tail,
                                          copula_results,
                                          empirical_best_family) {
  
  # Tier 1: Critical (Must Pass)
  tier1_copula_correct <- (copula_results$best_family == empirical_best_family)
  tier1_tau_preserved <- (!is.null(dependence$tau_bias) && 
                          abs(dependence$tau_bias) < 0.035)
  tier1_tail_preserved <- (!is.null(tail$tail_distortion_lower) && 
                           !is.null(tail$tail_distortion_upper) &&
                           tail$tail_distortion_lower < 0.012 &&
                           tail$tail_distortion_upper < 0.012)
  
  tier1_pass <- tier1_copula_correct && tier1_tau_preserved && tier1_tail_preserved
  
  # Tier 2: Important (Should Pass)
  tier2_ks_liberal <- uniformity$passes_ks_liberal  # p > 0.01
  tier2_cvm_acceptable <- (uniformity$cvm_U < 0.05 && uniformity$cvm_V < 0.05)
  tier2_no_excessive_ties <- (uniformity$tie_proportion_U < 0.05 && 
                               uniformity$tie_proportion_V < 0.05)
  
  tier2_pass <- tier2_ks_liberal && tier2_cvm_acceptable && tier2_no_excessive_ties
  
  # Tier 3: Nice to Have
  tier3_ks_standard <- uniformity$passes_ks_standard  # p > 0.05
  # Invertibility and timing checked separately in utility metrics
  
  # Overall classification
  if (tier1_pass && tier2_pass && tier3_ks_standard) {
    classification <- "EXCELLENT"
    use_in_phase2 <- TRUE
  } else if (tier1_pass && tier2_pass) {
    classification <- "ACCEPTABLE"
    use_in_phase2 <- TRUE
  } else if (tier1_pass) {
    classification <- "MARGINAL"
    use_in_phase2 <- FALSE  # Can be considered with caution
  } else {
    classification <- "UNACCEPTABLE"
    use_in_phase2 <- FALSE
  }
  
  return(list(
    classification = classification,
    use_in_phase2 = use_in_phase2,
    
    # Detailed tier results
    tier1_pass = tier1_pass,
    tier1_copula_correct = tier1_copula_correct,
    tier1_tau_preserved = tier1_tau_preserved,
    tier1_tail_preserved = tier1_tail_preserved,
    
    tier2_pass = tier2_pass,
    tier2_ks_liberal = tier2_ks_liberal,
    tier2_cvm_acceptable = tier2_cvm_acceptable,
    tier2_no_excessive_ties = tier2_no_excessive_ties,
    
    tier3_ks_standard = tier3_ks_standard,
    
    # For debugging
    details = list(
      copula_selected = copula_results$best_family,
      copula_expected = empirical_best_family,
      tau_bias = dependence$tau_bias,
      tail_distortion_lower = tail$tail_distortion_lower,
      tail_distortion_upper = tail$tail_distortion_upper,
      ks_pvalue = uniformity$combined_ks_pval
    )
  ))
}


#' Compare Method to Empirical Baseline
#' 
#' Comprehensive comparison of a transformation method against the gold standard
#' (empirical ranks).
#' 
#' @param method_results Full diagnostics for the method
#' @param empirical_results Full diagnostics for empirical ranks
#' 
#' @return Data.table with comparison metrics
compare_to_empirical_baseline <- function(method_results, empirical_results) {
  
  comparison <- data.table(
    metric = character(),
    method_value = numeric(),
    empirical_value = numeric(),
    difference = numeric(),
    relative_error = numeric(),
    acceptable = logical()
  )
  
  # Key metrics to compare
  metrics_to_compare <- list(
    list(name = "Kendall Tau", 
         method_val = method_results$dependence$kendall_tau,
         empirical_val = empirical_results$dependence$kendall_tau,
         tolerance = 0.035),
    
    list(name = "K-S p-value (U)",
         method_val = method_results$uniformity$ks_U_pval,
         empirical_val = empirical_results$uniformity$ks_U_pval,
         tolerance = NA),
    
    list(name = "Lower Tail (10%)",
         method_val = method_results$tail$lower_10,
         empirical_val = empirical_results$tail$lower_10,
         tolerance = 0.012),
    
    list(name = "Upper Tail (90%)",
         method_val = method_results$tail$upper_90,
         empirical_val = empirical_results$tail$upper_90,
         tolerance = 0.012)
  )
  
  for (m in metrics_to_compare) {
    diff <- m$method_val - m$empirical_val
    rel_err <- if (!is.na(m$empirical_val) && m$empirical_val != 0) {
      diff / m$empirical_val
    } else {
      NA
    }
    
    acceptable <- if (!is.na(m$tolerance)) {
      abs(diff) < m$tolerance
    } else {
      NA
    }
    
    comparison <- rbind(comparison, data.table(
      metric = m$name,
      method_value = m$method_val,
      empirical_value = m$empirical_val,
      difference = diff,
      relative_error = rel_err,
      acceptable = acceptable
    ))
  }
  
  return(comparison)
}


#' Generate Transformation Method Report
#' 
#' Creates a comprehensive text report summarizing method quality.
#' 
#' @param method_name Name of the transformation method
#' @param all_diagnostics List containing all diagnostic results
#' @param output_file Optional file path to save report
#' 
#' @return Character vector with report lines
generate_method_report <- function(method_name, all_diagnostics, output_file = NULL) {
  
  report <- c(
    "====================================================================",
    paste("TRANSFORMATION METHOD REPORT:", method_name),
    "====================================================================",
    "",
    "CLASSIFICATION:",
    paste("  Overall:", all_diagnostics$classification$classification),
    paste("  Suitable for Phase 2:", all_diagnostics$classification$use_in_phase2),
    "",
    "TIER 1 (CRITICAL):",
    paste("  Selects correct copula:", all_diagnostics$classification$tier1_copula_correct),
    paste("  Preserves tau:", all_diagnostics$classification$tier1_tau_preserved),
    paste("  Preserves tails:", all_diagnostics$classification$tier1_tail_preserved),
    "",
    "TIER 2 (IMPORTANT):",
    paste("  Passes K-S (liberal):", all_diagnostics$classification$tier2_ks_liberal),
    paste("  CvM acceptable:", all_diagnostics$classification$tier2_cvm_acceptable),
    paste("  No excessive ties:", all_diagnostics$classification$tier2_no_excessive_ties),
    "",
    "UNIFORMITY:",
    sprintf("  K-S test U: stat=%.4f, p=%.4f", 
            all_diagnostics$uniformity$ks_U_stat,
            all_diagnostics$uniformity$ks_U_pval),
    sprintf("  K-S test V: stat=%.4f, p=%.4f",
            all_diagnostics$uniformity$ks_V_stat,
            all_diagnostics$uniformity$ks_V_pval),
    sprintf("  CvM U: %.6f, V: %.6f",
            all_diagnostics$uniformity$cvm_U,
            all_diagnostics$uniformity$cvm_V),
    "",
    "DEPENDENCE:",
    sprintf("  Kendall tau: %.4f (bias: %.4f)",
            all_diagnostics$dependence$kendall_tau,
            ifelse(!is.null(all_diagnostics$dependence$tau_bias),
                   all_diagnostics$dependence$tau_bias, NA)),
    "",
    "TAIL STRUCTURE:",
    sprintf("  Lower 10%%: %.4f (distortion: %.4f)",
            all_diagnostics$tail$lower_10,
            ifelse(!is.null(all_diagnostics$tail$tail_distortion_lower),
                   all_diagnostics$tail$tail_distortion_lower, NA)),
    sprintf("  Upper 90%%: %.4f (distortion: %.4f)",
            all_diagnostics$tail$upper_90,
            ifelse(!is.null(all_diagnostics$tail$tail_distortion_upper),
                   all_diagnostics$tail$tail_distortion_upper, NA)),
    "",
    "===================================================================="
  )
  
  if (!is.null(output_file)) {
    writeLines(report, output_file)
  }
  
  return(report)
}


################################################################################
### ENHANCED COPULA-AWARE DIAGNOSTICS
### Phase 2 additions: Tail calibration and parameter stability
################################################################################

#' Tail Rank-Weight Calibration
#' 
#' Compares empirical vs smoothed PIT tail mass using conditional exceedance curves.
#' This is CRITICAL for copulas with tail dependence (t, Clayton, Gumbel).
#' 
#' @param U_empirical Empirical PIT values (from ECDF)
#' @param U_smoothed Smoothed PIT values (from candidate method)
#' @param tail_quantiles Quantiles to check (default: c(0.01, 0.05, 0.10))
#' 
#' @return List with calibration metrics and plotting data
tail_calibration_check <- function(U_empirical, 
                                   U_smoothed,
                                   tail_quantiles = c(0.01, 0.05, 0.10)) {
  
  # Lower tail calibration at key quantiles
  lower_tail_emp <- sapply(tail_quantiles, function(q) mean(U_empirical <= q))
  lower_tail_smooth <- sapply(tail_quantiles, function(q) mean(U_smoothed <= q))
  
  # Upper tail calibration at key quantiles
  upper_tail_emp <- sapply(tail_quantiles, function(q) mean(U_empirical >= (1 - q)))
  upper_tail_smooth <- sapply(tail_quantiles, function(q) mean(U_smoothed >= (1 - q)))
  
  # Conditional exceedance curves (fine grid)
  q_grid <- seq(0.001, 0.20, by = 0.001)
  lower_curve_emp <- sapply(q_grid, function(q) mean(U_empirical <= q))
  lower_curve_smooth <- sapply(q_grid, function(q) mean(U_smoothed <= q))
  
  upper_curve_emp <- sapply(q_grid, function(q) mean(U_empirical >= (1 - q)))
  upper_curve_smooth <- sapply(q_grid, function(q) mean(U_smoothed >= (1 - q)))
  
  # Compute tail calibration error (L1 distance)
  tail_error_lower <- mean(abs(lower_curve_smooth - lower_curve_emp))
  tail_error_upper <- mean(abs(upper_curve_smooth - upper_curve_emp))
  tail_error_total <- (tail_error_lower + tail_error_upper) / 2
  
  # Max error (L-infinity)
  tail_max_error_lower <- max(abs(lower_curve_smooth - lower_curve_emp))
  tail_max_error_upper <- max(abs(upper_curve_smooth - upper_curve_emp))
  tail_max_error <- max(tail_max_error_lower, tail_max_error_upper)
  
  # Pass/fail criteria
  # Tier 1: tail_error < 0.02 (2% average deviation)
  # Tier 2: tail_error < 0.05 (5% average deviation)
  passes_tier1 <- tail_error_total < 0.02
  passes_tier2 <- tail_error_total < 0.05
  
  return(list(
    # Summary metrics
    tail_error_lower = tail_error_lower,
    tail_error_upper = tail_error_upper,
    tail_error_total = tail_error_total,
    tail_max_error = tail_max_error,
    
    # Key quantiles
    quantiles = tail_quantiles,
    lower_tail_emp = lower_tail_emp,
    lower_tail_smooth = lower_tail_smooth,
    upper_tail_emp = upper_tail_emp,
    upper_tail_smooth = upper_tail_smooth,
    
    # Full curves for plotting
    curves = list(
      q_grid = q_grid,
      lower_emp = lower_curve_emp,
      lower_smooth = lower_curve_smooth,
      upper_emp = upper_curve_emp,
      upper_smooth = upper_curve_smooth
    ),
    
    # Pass/fail
    passes_tier1 = passes_tier1,
    passes_tier2 = passes_tier2,
    grade = ifelse(passes_tier1, "PASS", 
                   ifelse(passes_tier2, "MARGINAL", "FAIL"))
  ))
}


#' Plot tail calibration curves
#' 
#' @param tail_cal Result from tail_calibration_check()
#' @param method_name Name of method for plot title
#' @param add_to_existing If TRUE, add to existing plot (default: FALSE)
plot_tail_calibration <- function(tail_cal, method_name, add_to_existing = FALSE) {
  
  if (!add_to_existing) {
    par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
  }
  
  # Lower tail
  plot(tail_cal$curves$q_grid, tail_cal$curves$lower_emp,
       type = "l", lwd = 2, col = "black",
       xlab = "Quantile q", ylab = "P(U ≤ q)",
       main = paste(method_name, "- Lower Tail"),
       ylim = c(0, max(tail_cal$curves$q_grid) * 1.1))
  lines(tail_cal$curves$q_grid, tail_cal$curves$lower_smooth,
        lwd = 2, col = "red", lty = 2)
  abline(0, 1, col = "gray", lty = 3)  # Perfect calibration
  legend("topleft", 
         legend = c("Empirical", "Smoothed", "Perfect"),
         col = c("black", "red", "gray"), 
         lwd = 2, lty = c(1, 2, 3),
         cex = 0.8)
  
  # Add error annotation
  text(max(tail_cal$curves$q_grid) * 0.7, 
       max(tail_cal$curves$q_grid) * 0.3,
       sprintf("L1 error: %.4f\nGrade: %s", 
               tail_cal$tail_error_lower,
               tail_cal$grade),
       cex = 0.8, col = ifelse(tail_cal$passes_tier1, "darkgreen", "darkred"))
  
  grid()
  
  # Upper tail
  plot(tail_cal$curves$q_grid, tail_cal$curves$upper_emp,
       type = "l", lwd = 2, col = "black",
       xlab = "Quantile q", ylab = "P(U ≥ 1-q)",
       main = paste(method_name, "- Upper Tail"),
       ylim = c(0, max(tail_cal$curves$q_grid) * 1.1))
  lines(tail_cal$curves$q_grid, tail_cal$curves$upper_smooth,
        lwd = 2, col = "red", lty = 2)
  abline(0, 1, col = "gray", lty = 3)
  legend("topleft", 
         legend = c("Empirical", "Smoothed", "Perfect"),
         col = c("black", "red", "gray"), 
         lwd = 2, lty = c(1, 2, 3),
         cex = 0.8)
  
  text(max(tail_cal$curves$q_grid) * 0.7, 
       max(tail_cal$curves$q_grid) * 0.3,
       sprintf("L1 error: %.4f\nGrade: %s", 
               tail_cal$tail_error_upper,
               tail_cal$grade),
       cex = 0.8, col = ifelse(tail_cal$passes_tier1, "darkgreen", "darkred"))
  
  grid()
}


#' Bootstrap Copula Parameter Stability
#' 
#' Re-estimates copula on resampled (U,V) pairs to measure parameter dispersion.
#' Stable parameters indicate the transformation preserves copula structure.
#' 
#' @param U_prior PIT values for prior grade
#' @param U_current PIT values for current grade
#' @param copula_family Copula family to test ("t", "gaussian", "clayton", etc.)
#' @param n_bootstrap Number of bootstrap replications (default: 200)
#' @param parallel If TRUE, use parallel processing (default: FALSE)
#' 
#' @return List with stability metrics
bootstrap_parameter_stability <- function(U_prior,
                                          U_current,
                                          copula_family = "t",
                                          n_bootstrap = 200,
                                          parallel = FALSE) {
  
  require(copula)
  
  n <- length(U_prior)
  
  # Fit copula on original data
  true_fit <- tryCatch({
    fit_copula_from_uniform(U_prior, U_current, copula_family)
  }, error = function(e) {
    return(NULL)
  })
  
  if (is.null(true_fit)) {
    return(list(
      success = FALSE,
      message = "Failed to fit copula on original data"
    ))
  }
  
  true_tau <- true_fit$kendall_tau
  true_nu <- if (copula_family == "t" && !is.null(true_fit$df)) true_fit$df else NA
  
  # Bootstrap function
  bootstrap_once <- function(i) {
    # Resample with replacement
    boot_idx <- sample(1:n, size = n, replace = TRUE)
    U_prior_boot <- U_prior[boot_idx]
    U_current_boot <- U_current[boot_idx]
    
    # Refit copula
    tryCatch({
      boot_fit <- fit_copula_from_uniform(U_prior_boot, U_current_boot, copula_family)
      list(
        tau = boot_fit$kendall_tau,
        nu = if (copula_family == "t" && !is.null(boot_fit$df)) boot_fit$df else NA,
        success = TRUE
      )
    }, error = function(e) {
      list(tau = NA, nu = NA, success = FALSE)
    })
  }
  
  # Run bootstrap
  if (parallel && require(parallel)) {
    boot_results <- mclapply(1:n_bootstrap, bootstrap_once, mc.cores = 4)
  } else {
    boot_results <- lapply(1:n_bootstrap, bootstrap_once)
  }
  
  # Extract results
  boot_tau <- sapply(boot_results, function(x) x$tau)
  boot_nu <- sapply(boot_results, function(x) x$nu)
  successes <- sapply(boot_results, function(x) x$success)
  
  # Remove failures
  boot_tau <- boot_tau[!is.na(boot_tau)]
  boot_nu <- boot_nu[!is.na(boot_nu)]
  
  if (length(boot_tau) < 10) {
    return(list(
      success = FALSE,
      message = "Too many bootstrap failures (< 10 successes)"
    ))
  }
  
  # Stability metrics
  tau_sd <- sd(boot_tau)
  tau_iqr <- IQR(boot_tau)
  tau_cv <- (tau_sd / abs(true_tau)) * 100  # Coefficient of variation (%)
  
  nu_sd <- if (copula_family == "t" && length(boot_nu) > 0) sd(boot_nu) else NA
  nu_iqr <- if (copula_family == "t" && length(boot_nu) > 0) IQR(boot_nu) else NA
  nu_cv <- if (copula_family == "t" && !is.na(true_nu) && true_nu > 0) {
    (nu_sd / true_nu) * 100
  } else {
    NA
  }
  
  # Pass/fail criteria
  # Tier 1: CV < 5% (very stable)
  # Tier 2: CV < 10% (stable)
  passes_tier1 <- tau_cv < 5
  passes_tier2 <- tau_cv < 10
  
  return(list(
    success = TRUE,
    copula_family = copula_family,
    
    # True parameters
    true_tau = true_tau,
    true_nu = true_nu,
    
    # Bootstrap distributions
    boot_tau = boot_tau,
    boot_nu = boot_nu,
    
    # Tau stability
    tau_sd = tau_sd,
    tau_iqr = tau_iqr,
    tau_cv = tau_cv,
    tau_ci = quantile(boot_tau, probs = c(0.025, 0.975)),
    
    # Nu stability (if t-copula)
    nu_sd = nu_sd,
    nu_iqr = nu_iqr,
    nu_cv = nu_cv,
    nu_ci = if (length(boot_nu) > 0) quantile(boot_nu, probs = c(0.025, 0.975)) else c(NA, NA),
    
    # Summary
    n_successes = length(boot_tau),
    n_failures = n_bootstrap - length(boot_tau),
    success_rate = length(boot_tau) / n_bootstrap,
    
    # Pass/fail
    passes_tier1 = passes_tier1,
    passes_tier2 = passes_tier2,
    grade = ifelse(passes_tier1, "PASS",
                   ifelse(passes_tier2, "MARGINAL", "FAIL"))
  ))
}


#' Helper function to fit copula from uniform margins
#' (Assumes copula package with fitCopula available)
fit_copula_from_uniform <- function(U, V, family = "t") {
  
  require(copula)
  
  # Create pseudo-observations matrix
  pseudo_obs <- cbind(U, V)
  
  # Remove any boundary values that might cause issues
  valid_idx <- (U > 1e-6 & U < 1 - 1e-6) & (V > 1e-6 & V < 1 - 1e-6)
  pseudo_obs <- pseudo_obs[valid_idx, ]
  
  if (nrow(pseudo_obs) < 50) {
    stop("Too few valid observations after boundary removal")
  }
  
  # Select copula family
  if (family == "t") {
    cop <- tCopula(dim = 2)
  } else if (family == "gaussian" || family == "normal") {
    cop <- normalCopula(dim = 2)
  } else if (family == "clayton") {
    cop <- claytonCopula(dim = 2)
  } else if (family == "gumbel") {
    cop <- gumbelCopula(dim = 2)
  } else if (family == "frank") {
    cop <- frankCopula(dim = 2)
  } else {
    stop(paste("Unsupported copula family:", family))
  }
  
  # Fit copula
  fit <- fitCopula(cop, pseudo_obs, method = "mpl")
  
  # Extract parameters
  result <- list(
    family = family,
    parameters = coef(fit),
    kendall_tau = cor(U, V, method = "kendall"),
    loglik = logLik(fit),
    AIC = AIC(fit)
  )
  
  # Add df for t-copula
  if (family == "t") {
    result$df <- coef(fit)[2]  # Second parameter is df
  }
  
  return(result)
}


#' Plot bootstrap stability distributions
#' 
#' @param stability Result from bootstrap_parameter_stability()
#' @param method_name Name of method for plot title
plot_stability_fan <- function(stability, method_name) {
  
  if (!stability$success) {
    plot.new()
    text(0.5, 0.5, "Bootstrap stability analysis failed", cex = 1.5)
    return(invisible(NULL))
  }
  
  # Determine layout based on copula family
  if (stability$copula_family == "t" && !is.na(stability$true_nu)) {
    par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
  } else {
    par(mfrow = c(1, 1), mar = c(4, 4, 3, 1))
  }
  
  # Tau stability histogram
  hist(stability$boot_tau, 
       breaks = 30,
       col = "lightblue", 
       border = "black",
       main = paste(method_name, "- τ Stability"),
       xlab = "Kendall's τ (bootstrap)",
       freq = FALSE)
  
  # Add true value line
  abline(v = stability$true_tau, col = "red", lwd = 2, lty = 2)
  
  # Add confidence interval
  abline(v = stability$tau_ci, col = "darkgreen", lwd = 1, lty = 3)
  
  # Add legend
  legend("topright", 
         legend = c(
           paste("True τ =", round(stability$true_tau, 4)),
           paste("SD =", round(stability$tau_sd, 4)),
           paste("CV =", round(stability$tau_cv, 2), "%"),
           paste("Grade:", stability$grade)
         ),
         bg = "white",
         cex = 0.8)
  
  # Nu stability histogram (if t-copula)
  if (stability$copula_family == "t" && !is.na(stability$true_nu)) {
    hist(stability$boot_nu, 
         breaks = 30,
         col = "lightcoral", 
         border = "black",
         main = paste(method_name, "- ν (df) Stability"),
         xlab = "Degrees of freedom (bootstrap)",
         freq = FALSE)
    
    abline(v = stability$true_nu, col = "red", lwd = 2, lty = 2)
    abline(v = stability$nu_ci, col = "darkgreen", lwd = 1, lty = 3)
    
    legend("topright",
           legend = c(
             paste("True ν =", round(stability$true_nu, 2)),
             paste("SD =", round(stability$nu_sd, 2)),
             paste("CV =", round(stability$nu_cv, 2), "%")
           ),
           bg = "white",
           cex = 0.8)
  }
}

