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

