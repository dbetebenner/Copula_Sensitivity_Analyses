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
N_BOOTSTRAP_GOF <- 100              # Use 100 bootstraps for GoF testing

cat("Configuration:\n")
cat("  Datasets:", paste(DATASETS_TO_RUN, collapse = ", "), "\n")
cat("  Steps:", paste(STEPS_TO_RUN, collapse = ", "), "\n")
cat("  Batch mode:", BATCH_MODE, "\n")
cat("  Skip completed:", SKIP_COMPLETED, "\n")
cat("  GoF bootstraps:", N_BOOTSTRAP_GOF, "\n")

# Performance notes for different environments
if (exists("IS_EC2", envir = .GlobalEnv) && IS_EC2) {
  cat("\n")
  cat("Running on EC2 - Expected completion time:\n")
  cat("  c8g.12xlarge (46 cores): ~1.5-2 hours (N=1000 bootstraps)\n")
  cat("  c8g.8xlarge (30 cores): ~2-2.5 hours (N=1000 bootstraps)\n")
} else {
  cat("\n")
  cat("Running locally - Expected completion time:\n")
  cat("  M2 MacBook (11 cores): ~15-20 hours (N=1000 bootstraps)\n")
  cat("  Consider using EC2 for production runs\n")
}
cat("\n")

cat("Starting test run...\n\n")

# Run the master analysis
source("master_analysis.R")

cat("\n====================================================================\n")
cat("TEST RUN COMPLETE\n")
cat("====================================================================\n\n")

cat("Next steps:\n")
cat("1. Review output in STEP_1_Family_Selection/results/\n")
cat("   - Individual datasets: dataset_1/, dataset_2/, dataset_3/\n")
cat("   - Combined results: dataset_all/\n")
cat("2. Check combined CSV: dataset_all/phase1_copula_family_comparison_all_datasets.csv\n")
cat("   - Verify dataset_id = 'dataset_1', 'dataset_2', 'dataset_3' in results\n")
cat("3. Verify all 34 columns present in CSV:\n")
cat("   - 3 dataset identifiers (dataset_id, dataset_name, anonymized_state)\n")
cat("   - 7 scaling/transition metadata columns\n")
cat("   - 7 condition identifiers (including year_span, year_prior, year_current)\n")
cat("   - 14 copula results and parameters\n")
cat("   - 3 calculated metrics (best_aic, best_bic, delta_aic_vs_best)\n")
cat("   Note: aic_weight (35th column) is added by phase1_analysis.R\n")
cat("4. If successful, proceed to run the full analysis\n\n")