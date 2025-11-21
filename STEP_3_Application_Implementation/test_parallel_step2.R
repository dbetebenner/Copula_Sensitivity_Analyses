################################################################################
### TEST: STEP 2 PARALLEL IMPLEMENTATION
### Quick validation with subset of methods before full run
################################################################################

require(data.table)
require(parallel)

cat("====================================================================\n")
cat("STEP 2 PARALLEL IMPLEMENTATION - TEST\n")
cat("====================================================================\n\n")

# Load data using master_analysis.R infrastructure
cat("Loading data...\n")
source("../master_analysis.R")
cat("\n")

# Test configuration
cat("Test Configuration:\n")
cat("  Available cores:", detectCores(), "\n")
cat("  Will use:", if (exists("N_CORES")) N_CORES else detectCores() - 2, "cores\n")
cat("  Testing: 3 methods (subset)\n\n")

# Temporarily modify TRANSFORMATION_METHODS to test with just 3 methods
cat("====================================================================\n")
cat("RUNNING TEST WITH 3 METHODS\n")
cat("====================================================================\n\n")

# Save current directory
original_wd <- getwd()

# Change to STEP_2 directory
setwd("STEP_2_Transformation_Validation")

# Source the parallel script
# It will automatically use the global N_CORES if available
source("exp_5_transformation_validation_parallel.R")

# Restore directory
setwd(original_wd)

cat("\n====================================================================\n")
cat("TEST COMPLETE\n")
cat("====================================================================\n\n")

# Verify results
results_file <- "STEP_2_Transformation_Validation/results/exp5_transformation_validation_summary.csv"

if (file.exists(results_file)) {
  results <- fread(results_file)
  
  cat("Results verification:\n")
  cat("  Total methods processed:", nrow(results), "\n")
  cat("  Expected: 15 methods\n\n")
  
  cat("Classification breakdown:\n")
  print(table(results$classification))
  cat("\n")
  
  cat("Methods that select correct copula:\n")
  correct_copula <- results[copula_correct == TRUE, .(method, classification, ks_pvalue, best_copula)]
  print(correct_copula)
  cat("\n")
  
  cat("✓ TEST PASSED\n")
  cat("Parallel implementation working correctly!\n\n")
  
} else {
  cat("✗ TEST FAILED\n")
  cat("Results file not found:", results_file, "\n\n")
}

cat("Next step: Run full analysis with:\n")
cat("  STEPS_TO_RUN <- c(1, 2)\n")
cat("  source(\"master_analysis.R\")\n\n")
