################################################################################
### TEST RUN: Multiple Datasets (dataset_1, dataset_2, dataset_3)
### Purpose: Verify the multi-dataset infrastructure works correctly
###          with all three datasets before running the full analysis
################################################################################

cat("====================================================================\n")
cat("TEST RUN: MULTIPLE DATASETS (dataset_1, dataset_2, dataset_3)\n")
cat("====================================================================\n\n")

# Set configuration for testing
DATASETS_TO_RUN <- c("dataset_1", "dataset_2", "dataset_3")  # Test with all three datasets
STEPS_TO_RUN <- 1                   # Just Step 1 for now
BATCH_MODE <- TRUE                 # Interactive mode to see progress
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
cat("2. Check that dataset_id = 'dataset_1', 'dataset_2', 'dataset_3' in results\n")
cat("3. Verify all 31 columns present\n")
cat("4. If successful, proceed to run the full analysis\n\n")