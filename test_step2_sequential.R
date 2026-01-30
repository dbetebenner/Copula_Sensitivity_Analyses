############################################################################
### TEST SCRIPT: STEP 2 Sequential Execution
###
### Purpose: Test the new sequential STEP_2 implementation with individual
###          experiment selection capability
###
### Usage Examples:
###   # Test experiment 1 only
###   source("test_step2_sequential.R")
###
###   # Test all experiments (modify EXPERIMENT_TO_RUN_STEP2 below)
###   EXPERIMENT_TO_RUN_STEP2 <- NULL
###   source("test_step2_sequential.R")
############################################################################

cat("====================================================================\n")
cat("STEP 2 SEQUENTIAL EXECUTION TEST\n")
cat("====================================================================\n\n")

# Configuration
STEPS_TO_RUN <- c(2)                    # Run only STEP_2
USE_PARALLEL_STEP2 <- FALSE             # Force sequential mode
DATASETS_TO_RUN <- "dataset_4"          # Use dataset_4 (fastest for testing)

# Select which experiment(s) to test
# Options:
#   NULL = all 4 experiments (~3-6 hours sequential)
#   c("exp_1_grade_span") = experiment 1 only (~30-60 min)
#   c("exp_2_sample_size") = experiment 2 only (~30-60 min)
#   c("exp_3_content_area") = experiment 3 only (~30-60 min)
#   c("exp_4_cohort") = experiment 4 only (~30-60 min)
EXPERIMENT_TO_RUN_STEP2 <- c("exp_1_grade_span")

# Optional: Reduce bootstrap for faster testing
N_BOOTSTRAP <- 25  # Default is 50, use 25 for quick tests

# Optional: Skip completed experiments
SKIP_COMPLETED_STEP2 <- FALSE

cat("Test Configuration:\n")
cat("  Dataset:", DATASETS_TO_RUN, "\n")
cat("  Mode: SEQUENTIAL\n")
cat("  Bootstrap iterations:", N_BOOTSTRAP, "\n")
if (!is.null(EXPERIMENT_TO_RUN_STEP2)) {
  cat("  Experiments to run:", paste(EXPERIMENT_TO_RUN_STEP2, collapse = ", "), "\n")
} else {
  cat("  Experiments to run: ALL (1-4)\n")
}
cat("  Skip completed:", SKIP_COMPLETED_STEP2, "\n\n")

cat("Starting master_analysis.R...\n")
cat("====================================================================\n\n")

# Run master analysis with configuration
source("master_analysis.R")

cat("\n====================================================================\n")
cat("TEST COMPLETE\n")
cat("====================================================================\n")
cat("\nCheck results in:\n")
cat("  STEP_2_Copula_Sensitivity_Analyses/results/\n\n")
