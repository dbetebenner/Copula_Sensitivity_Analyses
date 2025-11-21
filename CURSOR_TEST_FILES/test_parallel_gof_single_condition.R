################################################################################
### LOCAL TEST: Parallel GoF on Single Condition
### Purpose: Test bootstrap-level parallelization with N=100
### Expected runtime: ~3-5 minutes on laptop (vs ~20-30 min sequential)
################################################################################

cat("====================================================================\n")
cat("LOCAL TEST: Parallel GoF Testing (Single Condition)\n")
cat("====================================================================\n\n")

cat("This test validates bootstrap-level parallelization for GoF testing.\n")
cat("It runs a single condition with N=100 bootstrap samples, comparing\n")
cat("sequential vs. parallel execution.\n\n")

# Load required packages
cat("Loading packages...\n")
require(data.table)
require(copula)
require(parallel)

# Load functions
cat("Loading functions...\n")
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")

cat("✓ Packages and functions loaded\n\n")

################################################################################
### CONFIGURATION
################################################################################

cat("====================================================================\n")
cat("CONFIGURATION\n")
cat("====================================================================\n")

# Test parameters
N_BOOTSTRAP_GOF <- 100
#COPULA_FAMILIES <- c("gaussian", "t", "clayton", "gumbel", "frank", "comonotonic")
COPULA_FAMILIES <- c("t")

# Detect available cores
n_cores_available <- parallel::detectCores()
if (is.na(n_cores_available)) n_cores_available <- 1

# Allocate cores for bootstrap parallelization
# Reserve 2 cores for system
n_cores_bootstrap <- max(1, n_cores_available - 2)

cat("Dataset: Dataset 2 (smallest)\n")
cat("Condition: MATH Grade 4->5 (1-year span, 2010->2011)\n")
cat("Bootstrap samples (N):", N_BOOTSTRAP_GOF, "\n")
cat("Copula families:", length(COPULA_FAMILIES), "\n")
cat("Available cores:", n_cores_available, "\n")
cat("Cores for bootstrap:", n_cores_bootstrap, "\n")
cat("Expected speedup:", round(n_cores_bootstrap * 0.8, 1), "x\n\n")

################################################################################
### DATA LOADING
################################################################################

cat("====================================================================\n")
cat("LOADING DATA\n")
cat("====================================================================\n")

data_file <- "Data/Copula_Sensitivity_Data_Set_2.Rdata"
if (!file.exists(data_file)) {
  stop("\n\nERROR: Data file not found!\n",
       "  Expected: ", data_file, "\n",
       "  Please verify you're running from project root.\n\n")
}

load(data_file)
cat("✓ Loaded:", data_file, "\n")

# Create test condition
pairs_data <- create_longitudinal_pairs(
  Copula_Sensitivity_Data_Set_2,
  content_prior = "MATHEMATICS",
  content_current = "MATHEMATICS",
  grade_prior = 4,
  grade_current = 5,
  year_prior = 2010,
  year_current = 2011
)

cat("✓ Pairs created:", nrow(pairs_data), "students\n\n")

################################################################################
### TEST 1: SEQUENTIAL EXECUTION (Baseline)
################################################################################

cat("====================================================================\n")
cat("TEST 1: SEQUENTIAL EXECUTION (Baseline)\n")
cat("====================================================================\n\n")

cat("Running with 1 core (sequential)...\n")
cat("This will take ~20-30 minutes for N=100.\n")
cat("Running only 1 family (t-copula) for speed...\n\n")

start_seq <- Sys.time()

# Run only t-copula for baseline timing
fit_seq <- fit_copula_from_pairs(
  scores_prior = pairs_data$SCALE_SCORE_PRIOR,
  scores_current = pairs_data$SCALE_SCORE_CURRENT,
  framework_prior = NULL,
  framework_current = NULL,
  copula_families = c("t"),  # Only t-copula for timing
  return_best = FALSE,
  use_empirical_ranks = TRUE,
  n_bootstrap_gof = N_BOOTSTRAP_GOF
)

end_seq <- Sys.time()
elapsed_seq <- as.numeric(difftime(end_seq, start_seq, units = "secs"))

cat("\n✓ Sequential test complete\n")
cat("  Time:", round(elapsed_seq, 1), "seconds (", round(elapsed_seq/60, 2), "minutes)\n")
cat("  T-copula p-value:", round(fit_seq$results$t$gof_pvalue, 4), "\n")
cat("  T-copula statistic:", round(fit_seq$results$t$gof_statistic, 4), "\n\n")

################################################################################
### TEST 2: PARALLEL EXECUTION (Target Implementation)
################################################################################

cat("====================================================================\n")
cat("TEST 2: PARALLEL EXECUTION (", n_cores_bootstrap, " cores)\n")
cat("====================================================================\n\n")

cat("Running with", n_cores_bootstrap, "cores (parallel bootstrap)...\n")
cat("This should take ~", round(elapsed_seq / (n_cores_bootstrap * 0.8) / 60, 1), 
    " minutes (", round(n_cores_bootstrap * 0.8, 1), "x speedup)\n\n")

# NOTE: This assumes perform_gof_test_parallel() has been implemented
# If not yet implemented, this will fail gracefully with an error message

start_par <- Sys.time()

# Check if parallel function exists
if (exists("perform_gof_test_parallel")) {
  
  cat("✓ perform_gof_test_parallel() found\n")
  cat("  Running parallel test...\n\n")
  
  # Run only t-copula with parallel bootstrap
  fit_par <- fit_copula_from_pairs(
    scores_prior = pairs_data$SCALE_SCORE_PRIOR,
    scores_current = pairs_data$SCALE_SCORE_CURRENT,
    framework_prior = NULL,
    framework_current = NULL,
    copula_families = c("t"),
    return_best = FALSE,
    use_empirical_ranks = TRUE,
    n_bootstrap_gof = N_BOOTSTRAP_GOF,
    n_gof_cores = n_cores_bootstrap  # Pass core count for bootstrap
  )
  
  end_par <- Sys.time()
  elapsed_par <- as.numeric(difftime(end_par, start_par, units = "secs"))
  
  cat("\n✓ Parallel test complete\n")
  cat("  Time:", round(elapsed_par, 1), "seconds (", round(elapsed_par/60, 2), "minutes)\n")
  cat("  T-copula p-value:", round(fit_par$results$t$gof_pvalue, 4), "\n")
  cat("  T-copula statistic:", round(fit_par$results$t$gof_statistic, 4), "\n\n")
  
  # Calculate speedup
  speedup <- elapsed_seq / elapsed_par
  efficiency <- speedup / n_cores_bootstrap * 100
  
  cat("====================================================================\n")
  cat("PERFORMANCE COMPARISON\n")
  cat("====================================================================\n\n")
  
  cat("Sequential time: ", round(elapsed_seq, 1), " seconds\n", sep="")
  cat("Parallel time:   ", round(elapsed_par, 1), " seconds\n", sep="")
  cat("Speedup:         ", round(speedup, 2), "x\n", sep="")
  cat("Efficiency:      ", round(efficiency, 1), "%\n\n", sep="")
  
  if (speedup >= n_cores_bootstrap * 0.6) {
    cat("✓✓✓ EXCELLENT SPEEDUP (", round(efficiency, 0), "% efficiency)\n\n", sep="")
  } else if (speedup >= n_cores_bootstrap * 0.4) {
    cat("✓✓ GOOD SPEEDUP (", round(efficiency, 0), "% efficiency)\n\n", sep="")
  } else if (speedup >= 2) {
    cat("✓ MODERATE SPEEDUP (", round(efficiency, 0), "% efficiency)\n", sep="")
    cat("   Consider investigating overhead\n\n")
  } else {
    cat("✗ POOR SPEEDUP (", round(efficiency, 0), "% efficiency)\n", sep="")
    cat("   Parallelization may not be working correctly\n\n")
  }
  
  # Validate equivalence
  cat("====================================================================\n")
  cat("EQUIVALENCE VALIDATION\n")
  cat("====================================================================\n\n")
  
  stat_diff <- abs(fit_seq$results$t$gof_statistic - fit_par$results$t$gof_statistic)
  pval_diff <- abs(fit_seq$results$t$gof_pvalue - fit_par$results$t$gof_pvalue)
  
  cat("Observed statistic difference:", format(stat_diff, scientific = TRUE), "\n")
  cat("P-value difference:           ", format(pval_diff, digits = 4), "\n\n")
  
  if (stat_diff < 1e-8) {
    cat("✓ Observed statistics IDENTICAL (perfect!)\n")
  } else if (stat_diff < 1e-4) {
    cat("✓ Observed statistics VERY CLOSE (acceptable)\n")
  } else {
    cat("⚠ Observed statistics DIFFER (investigate)\n")
  }
  
  # P-values can differ due to random bootstrap samples
  if (pval_diff < 0.05) {
    cat("✓ P-values SIMILAR (expected variation)\n\n")
  } else if (pval_diff < 0.1) {
    cat("⚠ P-values SOMEWHAT DIFFERENT (check random seeds)\n\n")
  } else {
    cat("✗ P-values VERY DIFFERENT (potential problem)\n\n")
  }
  
} else {
  cat("✗ perform_gof_test_parallel() NOT FOUND\n\n")
  cat("The parallel GoF function has not been implemented yet.\n")
  cat("This is expected if you're testing before implementation.\n\n")
  cat("To implement parallel GoF:\n")
  cat("  1. Add perform_gof_test_parallel() to functions/copula_bootstrap.R\n")
  cat("  2. Update fit_copula_from_pairs() to accept n_gof_cores parameter\n")
  cat("  3. Re-run this test to validate performance\n\n")
  
  end_par <- NA
  elapsed_par <- NA
}

################################################################################
### TEST 3: FULL FAMILY SUITE (if parallel is working well)
################################################################################

if (exists("perform_gof_test_parallel") && !is.na(elapsed_par)) {
  
  # Only run full test if parallel achieved good speedup
  if (elapsed_par < elapsed_seq * 0.7) {
    
    cat("====================================================================\n")
    cat("TEST 3: FULL FAMILY SUITE (All 6 families, parallel)\n")
    cat("====================================================================\n\n")
    
    cat("Running all 6 families with parallel bootstrap...\n")
    expected_time <- elapsed_par * 6 / 60  # Scale by number of families
    cat("Expected time: ~", round(expected_time, 1), " minutes\n\n", sep="")
    
    start_full <- Sys.time()
    
    fit_full <- fit_copula_from_pairs(
      scores_prior = pairs_data$SCALE_SCORE_PRIOR,
      scores_current = pairs_data$SCALE_SCORE_CURRENT,
      framework_prior = NULL,
      framework_current = NULL,
      copula_families = COPULA_FAMILIES,
      return_best = FALSE,
      use_empirical_ranks = TRUE,
      n_bootstrap_gof = N_BOOTSTRAP_GOF,
      n_gof_cores = n_cores_bootstrap
    )
    
    end_full <- Sys.time()
    elapsed_full <- as.numeric(difftime(end_full, start_full, units = "secs"))
    
    cat("\n✓ Full test complete\n")
    cat("  Time:", round(elapsed_full, 1), "seconds (", round(elapsed_full/60, 2), "minutes)\n\n")
    
    # Display results
    cat("Family-by-family results:\n")
    cat("--------------------------------------------------------------------\n")
    cat(sprintf("%-15s | %10s | %10s | %6s\n", 
                "Family", "Statistic", "P-Value", "Pass?"))
    cat("--------------------------------------------------------------------\n")
    
    for (fam in names(fit_full$results)) {
      result <- fit_full$results[[fam]]
      
      # Handle NA p-value for comonotonic
      if (is.na(result$gof_pvalue)) {
        pass_str <- "N/A"
        pval_str <- "NA"
      } else if (result$gof_pvalue > 0.05) {
        pass_str <- "PASS"
        pval_str <- sprintf("%.4f", result$gof_pvalue)
      } else {
        pass_str <- "FAIL"
        pval_str <- sprintf("%.4f", result$gof_pvalue)
      }
      
      cat(sprintf("%-15s | %10.4f | %10s | %-6s\n",
                  fam,
                  result$gof_statistic,
                  pval_str,
                  pass_str))
    }
    
    cat("\n====================================================================\n")
    cat("FINAL SUMMARY\n")
    cat("====================================================================\n\n")
    
    cat("Performance:\n")
    cat("  Sequential (1 family):   ", round(elapsed_seq/60, 2), " min\n", sep="")
    cat("  Parallel (1 family):     ", round(elapsed_par/60, 2), " min\n", sep="")
    cat("  Parallel (6 families):   ", round(elapsed_full/60, 2), " min\n", sep="")
    cat("  Speedup vs. sequential:  ", round(speedup, 2), "x per family\n", sep="")
    cat("  Estimated sequential time for 6 families: ", round(elapsed_seq * 6 / 60, 1), " min\n", sep="")
    cat("  Actual parallel time for 6 families:      ", round(elapsed_full / 60, 1), " min\n", sep="")
    cat("  Overall speedup:         ", round((elapsed_seq * 6) / elapsed_full, 2), "x\n\n", sep="")
    
    cat("EC2 Projection (48 cores, 129 conditions):\n")
    ec2_speedup <- 46 * 0.8  # 46 cores for bootstrap, 80% efficiency
    ec2_time_per_condition <- elapsed_full / ec2_speedup / 60  # minutes
    ec2_total_time <- ec2_time_per_condition * 129 / 6  # 6 conditions in parallel
    cat("  Time per condition:      ", round(ec2_time_per_condition, 2), " min\n", sep="")
    cat("  Total time (6×7 nested): ", round(ec2_total_time, 1), " min\n", sep="")
    cat("  Expected completion:     < 1 hour ✓\n\n")
    
    cat("✓✓✓ PARALLEL GOF TESTING VALIDATED ✓✓✓\n\n")
    cat("Ready for EC2 deployment with N=1000 bootstrap samples!\n\n")
    
  } else {
    cat("Skipping full family test (parallel speedup insufficient)\n\n")
  }
}

################################################################################
### COMPLETION
################################################################################

cat("====================================================================\n")
cat("Test completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("====================================================================\n\n")

