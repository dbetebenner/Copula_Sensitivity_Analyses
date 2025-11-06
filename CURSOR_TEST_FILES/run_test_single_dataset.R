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
cat("   - Single dataset: dataset_1/\n")
cat("   - Combined results: dataset_all/\n")
cat("2. Check CSV: dataset_1/phase1_copula_family_comparison_dataset_1.csv\n")
cat("   - Verify dataset_id = 'dataset_1' in all rows\n")
cat("3. Verify all 34 columns present in CSV:\n")
cat("   - 3 dataset identifiers\n")
cat("   - 7 scaling/transition metadata columns\n")
cat("   - 7 condition identifiers (including year_span, year_prior, year_current)\n")
cat("   - 14 copula results and parameters\n")
cat("   - 3 calculated metrics (best_aic, best_bic, delta_aic_vs_best)\n")
cat("4. If successful, proceed to run with all 3 datasets\n\n")

