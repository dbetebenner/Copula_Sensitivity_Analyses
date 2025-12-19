################################################################################
### TEST EXHAUSTIVE MODE CONFIGURATION
###
### Purpose: Validate exhaustive same-cohort analysis setup before full EC2 run
###
### This script tests the exhaustive analysis configuration with a small subset
### (1 condition per dataset) to ensure everything works correctly before
### launching the full multi-day EC2 analysis.
###
### Expected runtime: ~5-10 minutes
################################################################################

# Set working directory to project root
setwd("/Users/conet/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses")

################################################################################
### CONFIGURATION FOR TEST RUN
################################################################################

# Enable exhaustive mode for ALL datasets
USE_EXHAUSTIVE_ALL_DATASETS <- TRUE

# Enable test mode (limit to small subset)
TEST_MODE <- TRUE
TEST_N_CONDITIONS_PER_DATASET <- 1  # Test with 1 condition per dataset

# Select which datasets to test (all 4 for comprehensive test)
DATASETS_TO_RUN <- c("dataset_1", "dataset_2", "dataset_3", "dataset_4")

# Run only Step 1 (copula family selection)
STEPS_TO_RUN <- 1

# Disable some features to speed up testing
N_BOOTSTRAP_GOF <- NULL  # Skip GoF testing for speed
CALCULATE_SGPC <- FALSE  # Skip SGPc calculation for speed
GENERATE_CONTOUR_PLOTS <- FALSE  # Skip plot generation for speed

# Enable parallel processing if available
USE_PARALLEL <- TRUE

# Batch mode (no pauses)
BATCH_MODE <- TRUE

################################################################################
### RUN ANALYSIS
################################################################################

cat("\n")
cat("################################################################################\n")
cat("### EXHAUSTIVE MODE TEST RUN\n")
cat("################################################################################\n")
cat("\n")
cat("Configuration:\n")
cat("  Exhaustive mode: ENABLED\n")
cat("  Test mode: ENABLED\n")
cat("  Conditions per dataset:", TEST_N_CONDITIONS_PER_DATASET, "\n")
cat("  Datasets:", paste(DATASETS_TO_RUN, collapse = ", "), "\n")
cat("  GoF testing: DISABLED (for speed)\n")
cat("  SGPc calculation: DISABLED (for speed)\n")
cat("  Contour plots: DISABLED (for speed)\n")
cat("\n")
cat("Expected outcomes:\n")
cat("  1. Each dataset should generate exhaustive conditions list\n")
cat("  2. Test mode should limit to", TEST_N_CONDITIONS_PER_DATASET, "condition(s)\n")
cat("  3. Analysis should complete successfully\n")
cat("  4. Results should be saved to STEP_1_Family_Selection/results/\n")
cat("\n")
cat("Press Enter to continue or Ctrl+C to cancel...\n")
if (!BATCH_MODE) readline()

# Source the master analysis script
source("master_analysis.R")

################################################################################
### VALIDATION CHECKS
################################################################################

cat("\n")
cat("################################################################################\n")
cat("### VALIDATION CHECKS\n")
cat("################################################################################\n")
cat("\n")

# Check if results were generated
for (dataset_id in DATASETS_TO_RUN) {
  results_file <- file.path("STEP_1_Family_Selection/results", dataset_id, 
                           "phase1_copula_family_comparison.csv")
  
  if (file.exists(results_file)) {
    results <- fread(results_file)
    n_conditions <- uniqueN(results$condition_id)
    n_families <- uniqueN(results$family)
    
    cat("✓", dataset_id, "\n")
    cat("  Results file:", results_file, "\n")
    cat("  Conditions tested:", n_conditions, "\n")
    cat("  Copula families:", n_families, "\n")
    cat("  Total rows:", nrow(results), "\n")
    
    if (n_conditions == TEST_N_CONDITIONS_PER_DATASET) {
      cat("  ✓ Correct number of conditions tested\n")
    } else {
      cat("  ⚠ Expected", TEST_N_CONDITIONS_PER_DATASET, "conditions but found", n_conditions, "\n")
    }
    cat("\n")
  } else {
    cat("✗", dataset_id, "\n")
    cat("  Results file not found:", results_file, "\n\n")
  }
}

cat("################################################################################\n")
cat("### TEST COMPLETE\n")
cat("################################################################################\n")
cat("\n")
cat("If validation checks passed, you can proceed with full exhaustive analysis\n")
cat("by setting TEST_MODE <- FALSE in master_analysis.R\n")
cat("\n")

