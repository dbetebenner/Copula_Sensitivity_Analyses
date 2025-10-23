################################################################################
### TEST RUN: Single Dataset (dataset_1)
### Purpose: Verify the multi-dataset infrastructure works correctly
###          with a single dataset before running all three
################################################################################

cat("====================================================================\n")
cat("TEST RUN: SINGLE DATASET (dataset_1)\n")
cat("====================================================================\n\n")

# Set configuration for testing
DATASETS_TO_RUN <- c("dataset_1")  # Test with just first dataset
STEPS_TO_RUN <- 1                   # Just Step 1 for now
BATCH_MODE <- FALSE                 # Interactive mode to see progress
SKIP_COMPLETED <- FALSE             # Force fresh run

cat("Configuration:\n")
cat("  Datasets:", paste(DATASETS_TO_RUN, collapse = ", "), "\n")
cat("  Steps:", paste(STEPS_TO_RUN, collapse = ", "), "\n")
cat("  Batch mode:", BATCH_MODE, "\n")
cat("  Skip completed:", SKIP_COMPLETED, "\n\n")

cat("Starting test run...\n\n")

# Run the master analysis
source("master_analysis.R")

cat("\n====================================================================\n")
cat("TEST RUN COMPLETE\n")
cat("====================================================================\n\n")

cat("Next steps:\n")
cat("1. Review output in STEP_1_Family_Selection/results/\n")
cat("2. Check that dataset_id = 'dataset_1' in results\n")
cat("3. Verify all 31 columns present\n")
cat("4. If successful, proceed to run with all 3 datasets\n\n")

