################################################################################
### TEST SCRIPT FOR STEP 2 ENHANCEMENTS
### Quick validation that new components work correctly
### 
### USAGE: source("STEP_2_Transformation_Validation/test_enhancements.R")
###        (from workspace root)
################################################################################

cat("====================================================================\n")
cat("TESTING STEP 2 ENHANCEMENTS\n")
cat("====================================================================\n\n")

# Determine if we're in workspace root or STEP_2 directory
if (file.exists("functions/transformation_diagnostics.R")) {
  # We're in workspace root
  source("functions/transformation_diagnostics.R")
  source("STEP_2_Transformation_Validation/methods/bernstein_cdf.R")
  source("STEP_2_Transformation_Validation/methods/csem_aware_smoother.R")
} else if (file.exists("../functions/transformation_diagnostics.R")) {
  # We're in STEP_2_Transformation_Validation directory
  source("../functions/transformation_diagnostics.R")
  source("methods/bernstein_cdf.R")
  source("methods/csem_aware_smoother.R")
} else {
  stop("Cannot find functions directory. Please run from workspace root or STEP_2_Transformation_Validation directory.")
}

cat("  ✓ Functions loaded\n\n")

# Generate test data
cat("Generating test data...\n")
set.seed(42)
n <- 1000
test_scores <- rnorm(n, mean = 500, sd = 100)
test_scores <- pmax(300, pmin(700, test_scores))  # Truncate to [300, 700]

cat(sprintf("  ✓ Generated %d test scores\n", n))
cat(sprintf("  Range: [%.1f, %.1f]\n\n", min(test_scores), max(test_scores)))

################################################################################
### TEST 1: Bernstein CDF
################################################################################

cat("--------------------------------------------------------------------\n")
cat("TEST 1: Bernstein CDF Smoother\n")
cat("--------------------------------------------------------------------\n")

test1_result <- tryCatch({
  
  # Fit Bernstein CDF
  cat("  Fitting Bernstein CDF with auto-tuning...\n")
  bern_fit <- fit_bernstein_cdf(test_scores, degree = NULL, tune_by_cv = TRUE)
  
  cat(sprintf("  ✓ Fit successful (degree = %d)\n", bern_fit$degree))
  
  # Test forward function
  cat("  Testing forward function F(x)...\n")
  test_x <- quantile(test_scores, probs = c(0.1, 0.5, 0.9))
  U_test <- bern_fit$F(test_x)
  cat(sprintf("    F(%.1f) = %.4f\n", test_x[1], U_test[1]))
  cat(sprintf("    F(%.1f) = %.4f\n", test_x[2], U_test[2]))
  cat(sprintf("    F(%.1f) = %.4f\n", test_x[3], U_test[3]))
  
  # Test inverse function
  cat("  Testing inverse function F^{-1}(p)...\n")
  test_p <- c(0.1, 0.5, 0.9)
  X_test <- bern_fit$F_inv(test_p)
  cat(sprintf("    F^{-1}(%.1f) = %.1f\n", test_p[1], X_test[1]))
  cat(sprintf("    F^{-1}(%.1f) = %.1f\n", test_p[2], X_test[2]))
  cat(sprintf("    F^{-1}(%.1f) = %.1f\n", test_p[3], X_test[3]))
  
  # Test round-trip accuracy
  cat("  Testing round-trip accuracy...\n")
  U_forward <- bern_fit$F(test_scores)
  X_roundtrip <- bern_fit$F_inv(U_forward)
  roundtrip_error <- mean(abs(X_roundtrip - test_scores))
  cat(sprintf("    Mean absolute error: %.6f\n", roundtrip_error))
  
  # Test diagnostics
  cat("  Running diagnostic checks...\n")
  diag <- diagnose_bernstein_fit(test_scores, bern_fit)
  cat(sprintf("    MAE: %.6f\n", diag$mae))
  cat(sprintf("    RMSE: %.6f\n", diag$rmse))
  cat(sprintf("    Monotone: %s\n", diag$is_monotone))
  cat(sprintf("    Boundary OK: %s\n", diag$boundary_ok))
  
  list(success = TRUE, fit = bern_fit, diagnostics = diag)
  
}, error = function(e) {
  cat("  ✗ ERROR:", e$message, "\n")
  list(success = FALSE, error = e$message)
})

if (test1_result$success) {
  cat("\n  ✓✓✓ TEST 1 PASSED ✓✓✓\n\n")
} else {
  cat("\n  ✗✗✗ TEST 1 FAILED ✗✗✗\n\n")
}

################################################################################
### TEST 2: Tail Calibration Diagnostic
################################################################################

cat("--------------------------------------------------------------------\n")
cat("TEST 2: Tail Calibration Diagnostic\n")
cat("--------------------------------------------------------------------\n")

test2_result <- tryCatch({
  
  # Create empirical and smoothed pseudo-observations
  cat("  Creating pseudo-observations...\n")
  ecdf_emp <- ecdf(test_scores)
  U_empirical <- ecdf_emp(test_scores)
  
  # Use Bernstein from Test 1
  if (test1_result$success) {
    U_smoothed <- test1_result$fit$F(test_scores)
  } else {
    # Fallback: use kernel smoothing
    bw <- bw.nrd0(test_scores)
    U_smoothed <- sapply(test_scores, function(x) {
      mean(pnorm((x - test_scores) / bw))
    })
  }
  
  cat("  Running tail calibration check...\n")
  tail_cal <- tail_calibration_check(U_empirical, U_smoothed)
  
  cat(sprintf("    Tail error (lower): %.6f\n", tail_cal$tail_error_lower))
  cat(sprintf("    Tail error (upper): %.6f\n", tail_cal$tail_error_upper))
  cat(sprintf("    Tail error (total): %.6f\n", tail_cal$tail_error_total))
  cat(sprintf("    Grade: %s\n", tail_cal$grade))
  cat(sprintf("    Passes Tier 1: %s\n", tail_cal$passes_tier1))
  cat(sprintf("    Passes Tier 2: %s\n", tail_cal$passes_tier2))
  
  # Test plotting function
  cat("  Testing plotting function...\n")
  pdf(file = tempfile(fileext = ".pdf"))
  plot_tail_calibration(tail_cal, "Test Method")
  dev.off()
  cat("    ✓ Plot generated successfully\n")
  
  list(success = TRUE, tail_cal = tail_cal)
  
}, error = function(e) {
  cat("  ✗ ERROR:", e$message, "\n")
  list(success = FALSE, error = e$message)
})

if (test2_result$success) {
  cat("\n  ✓✓✓ TEST 2 PASSED ✓✓✓\n\n")
} else {
  cat("\n  ✗✗✗ TEST 2 FAILED ✗✗✗\n\n")
}

################################################################################
### TEST 3: Bootstrap Parameter Stability
################################################################################

cat("--------------------------------------------------------------------\n")
cat("TEST 3: Bootstrap Parameter Stability\n")
cat("--------------------------------------------------------------------\n")

test3_result <- tryCatch({
  
  # Create bivariate pseudo-observations
  cat("  Creating bivariate pseudo-observations...\n")
  # Simulate correlated uniform margins
  rho <- 0.7
  Z1 <- rnorm(n)
  Z2 <- rho * Z1 + sqrt(1 - rho^2) * rnorm(n)
  U_prior <- pnorm(Z1)
  U_current <- pnorm(Z2)
  
  cat("  Running bootstrap stability (10 reps for speed)...\n")
  stability <- bootstrap_parameter_stability(
    U_prior = U_prior,
    U_current = U_current,
    copula_family = "t",
    n_bootstrap = 10,  # Reduced for testing
    parallel = FALSE
  )
  
  if (stability$success) {
    cat(sprintf("    True τ: %.4f\n", stability$true_tau))
    cat(sprintf("    Bootstrap τ SD: %.4f\n", stability$tau_sd))
    cat(sprintf("    Bootstrap τ CV: %.2f%%\n", stability$tau_cv))
    cat(sprintf("    Grade: %s\n", stability$grade))
    cat(sprintf("    Success rate: %.1f%%\n", stability$success_rate * 100))
    
    # Test plotting function
    cat("  Testing plotting function...\n")
    pdf(file = tempfile(fileext = ".pdf"))
    plot_stability_fan(stability, "Test Method")
    dev.off()
    cat("    ✓ Plot generated successfully\n")
    
    list(success = TRUE, stability = stability)
  } else {
    cat("  ✗ Bootstrap failed:", stability$message, "\n")
    list(success = FALSE, error = stability$message)
  }
  
}, error = function(e) {
  cat("  ✗ ERROR:", e$message, "\n")
  list(success = FALSE, error = e$message)
})

if (test3_result$success) {
  cat("\n  ✓✓✓ TEST 3 PASSED ✓✓✓\n\n")
} else {
  cat("\n  ✗✗✗ TEST 3 FAILED ✗✗✗\n\n")
}

################################################################################
### TEST 4: CSEM-Aware Smoother
################################################################################

cat("--------------------------------------------------------------------\n")
cat("TEST 4: CSEM-Aware Smoother\n")
cat("--------------------------------------------------------------------\n")

test4_result <- tryCatch({
  
  # Create discrete/heaped scores
  cat("  Creating heaped test data...\n")
  discrete_scores <- round(rnorm(n, mean = 500, sd = 100) / 10) * 10
  discrete_scores <- pmax(300, pmin(700, discrete_scores))
  
  cat(sprintf("    N unique: %d (%.1f%% ties)\n", 
              length(unique(discrete_scores)),
              (1 - length(unique(discrete_scores)) / n) * 100))
  
  # Test detection
  cat("  Testing heaping detection...\n")
  needs_csem <- needs_csem_smoothing(discrete_scores)
  cat(sprintf("    Needs CSEM: %s\n", needs_csem$needs_csem))
  cat(sprintf("    Discretization ratio: %.2f%%\n", 
              needs_csem$diagnostics$discretization_ratio * 100))
  cat(sprintf("    Median gap: %.1f\n", needs_csem$diagnostics$median_gap))
  
  # Fit CSEM-aware smoother
  cat("  Fitting CSEM-aware smoother...\n")
  csem <- estimate_csem(discrete_scores)
  cat(sprintf("    Estimated CSEM: %.2f\n", csem))
  
  csem_fit <- fit_csem_aware(discrete_scores, csem = csem)
  cat(sprintf("    ✓ Fit successful\n"))
  
  # Test forward/inverse
  cat("  Testing forward/inverse functions...\n")
  test_x <- quantile(discrete_scores, probs = c(0.1, 0.5, 0.9))
  U_test <- csem_fit$F(test_x)
  X_test <- csem_fit$F_inv(U_test)
  roundtrip_error <- mean(abs(X_test - test_x))
  cat(sprintf("    Round-trip error: %.6f\n", roundtrip_error))
  
  list(success = TRUE, fit = csem_fit, needs_csem = needs_csem)
  
}, error = function(e) {
  cat("  ✗ ERROR:", e$message, "\n")
  list(success = FALSE, error = e$message)
})

if (test4_result$success) {
  cat("\n  ✓✓✓ TEST 4 PASSED ✓✓✓\n\n")
} else {
  cat("\n  ✗✗✗ TEST 4 FAILED ✗✗✗\n\n")
}

################################################################################
### SUMMARY
################################################################################

cat("====================================================================\n")
cat("TEST SUMMARY\n")
cat("====================================================================\n\n")

tests_passed <- sum(c(
  test1_result$success,
  test2_result$success,
  test3_result$success,
  test4_result$success
))

cat(sprintf("Tests passed: %d / 4\n\n", tests_passed))

if (test1_result$success) cat("  ✓ Bernstein CDF\n") else cat("  ✗ Bernstein CDF\n")
if (test2_result$success) cat("  ✓ Tail Calibration\n") else cat("  ✗ Tail Calibration\n")
if (test3_result$success) cat("  ✓ Bootstrap Stability\n") else cat("  ✗ Bootstrap Stability\n")
if (test4_result$success) cat("  ✓ CSEM-Aware Smoother\n") else cat("  ✗ CSEM-Aware Smoother\n")

cat("\n")

if (tests_passed == 4) {
  cat("====================================================================\n")
  cat("ALL TESTS PASSED! ✓✓✓\n")
  cat("Step 2 enhancements are ready for use.\n")
  cat("====================================================================\n\n")
  cat("Next steps:\n")
  cat("1. Run Experiment 5 with real data\n")
  cat("2. Run Experiment 6 (operational fitness)\n")
  cat("3. Review enhanced diagnostics in CSV output\n")
  cat("4. Generate updated visualizations\n\n")
} else {
  cat("====================================================================\n")
  cat("SOME TESTS FAILED ✗✗✗\n")
  cat("Please review error messages above.\n")
  cat("====================================================================\n\n")
}

cat("Test script complete.\n")
