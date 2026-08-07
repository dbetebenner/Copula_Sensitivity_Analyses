############################################################################
### EC2 ANALYSIS RUNNER
### Wrapper script for running copula analyses on EC2
###
### Usage:
###   1. Copy this script and dataset_configs_local.R to EC2
###   2. Set RUN_MODE below to control which phase to run
###   3. Run: Rscript run_ec2_analysis.R
###
### Phases:
###   "test_plots"  - Run test_contour_plots.R to validate visualization pipeline
###   "test_master" - Run master_analysis.R on small subset (2 conditions/dataset)
###   "full_run"    - Run master_analysis.R on all conditions (production)
############################################################################

############################################################################
### CONFIGURATION - SET THIS BEFORE RUNNING
############################################################################

# RUN_MODE options:
#   "test_plots"  - Quick test of visualization pipeline (5-10 min)
#   "test_master" - Test master script on subset (30-60 min)
#   "full_run"    - Full production run on all data (4-8 hours)

RUN_MODE <- "test_master" # <-- CHANGE THIS FOR EACH PHASE

############################################################################
### EXECUTION LOGIC
############################################################################

cat("\n")
cat("====================================================================\n")
cat("EC2 COPULA SENSITIVITY ANALYSIS\n")
cat("====================================================================\n")
cat("Run mode:", RUN_MODE, "\n")
cat("Time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("====================================================================\n\n")

# Validate we're in the project root
if (!file.exists("master_analysis.R") || !file.exists("dataset_configs.R")) {
  stop(
    "ERROR: Must run from project root directory (Copula_Sensitivity_Analyses/)"
  )
}

# Check for confidential config
if (!file.exists("dataset_configs_local.R")) {
  cat("WARNING: dataset_configs_local.R not found!\n")
  cat("  State identifiers will show as 'CONFIDENTIAL'\n")
  cat("  Copy this file from your local machine if needed.\n\n")
}

if (RUN_MODE == "test_plots") {
  ############################################################################
  ### PHASE 1: TEST VISUALIZATION PIPELINE
  ############################################################################

  cat("PHASE 1: Testing visualization pipeline\n")
  cat("Running: STEP_1_Family_Selection/test_contour_plots.R\n\n")

  source("STEP_1_Family_Selection/test_contour_plots.R")

  cat("\n")
  cat("====================================================================\n")
  cat("PHASE 1 COMPLETE\n")
  cat("Review plots in: STEP_1_Family_Selection/results/test/contour_plots/\n")
  cat("If successful, change RUN_MODE to 'test_master' and re-run\n")
  cat("====================================================================\n")
} else if (RUN_MODE == "test_master") {
  ############################################################################
  ### PHASE 2: TEST MASTER ANALYSIS ON SUBSET
  ############################################################################

  cat("PHASE 2: Testing master analysis on small subset\n")
  cat("This validates the full pipeline before production run\n\n")

  # Pre-set configuration for test mode
  TEST_MODE <- TRUE
  TEST_N_CONDITIONS_PER_DATASET <- 2 # 2 conditions per dataset = 8 total
  STEPS_TO_RUN <- 1 # Step 1 only
  BATCH_MODE <- TRUE # No interactive prompts
  EC2_MODE <- TRUE # Force EC2 optimizations
  SKIP_COMPLETED <- FALSE # Re-run even if results exist

  cat("Configuration:\n")
  cat("  TEST_MODE:", TEST_MODE, "\n")
  cat("  TEST_N_CONDITIONS_PER_DATASET:", TEST_N_CONDITIONS_PER_DATASET, "\n")
  cat("  STEPS_TO_RUN:", STEPS_TO_RUN, "\n")
  cat("  Expected runtime: 30-60 minutes\n\n")

  source("master_analysis.R")

  cat("\n")
  cat("====================================================================\n")
  cat("PHASE 2 COMPLETE\n")
  cat("Review results in: STEP_1_Family_Selection/results/\n")
  cat("If successful, change RUN_MODE to 'full_run' and re-run\n")
  cat("====================================================================\n")
} else if (RUN_MODE == "full_run") {
  ############################################################################
  ### PHASE 3: FULL PRODUCTION RUN
  ############################################################################

  cat("PHASE 3: Full production run on ALL conditions\n")
  cat("This will take several hours - ensure stable connection\n\n")

  # Pre-set configuration for full run
  TEST_MODE <- FALSE # Full analysis
  STEPS_TO_RUN <- 1 # Step 1 only
  BATCH_MODE <- TRUE # No interactive prompts
  EC2_MODE <- TRUE # Force EC2 optimizations
  SKIP_COMPLETED <- FALSE # Process all conditions
  USE_EXHAUSTIVE_ALL_DATASETS <- FALSE # Strategic subset (~16 conditions/dataset)

  # For exhaustive analysis (all year/grade combinations), uncomment:
  # USE_EXHAUSTIVE_ALL_DATASETS <- TRUE  # ~250-300 conditions/dataset

  cat("Configuration:\n")
  cat("  TEST_MODE:", TEST_MODE, "\n")
  cat("  USE_EXHAUSTIVE_ALL_DATASETS:", USE_EXHAUSTIVE_ALL_DATASETS, "\n")
  cat("  STEPS_TO_RUN:", STEPS_TO_RUN, "\n")
  cat("  DATASETS: All 4 datasets\n")
  cat("  Expected runtime: 4-8 hours (strategic), 8-16 hours (exhaustive)\n\n")

  cat("Starting in 10 seconds... (Ctrl+C to cancel)\n")
  Sys.sleep(10)

  source("master_analysis.R")

  cat("\n")
  cat("====================================================================\n")
  cat("PHASE 3 (FULL RUN) COMPLETE\n")
  cat("Results saved to: STEP_1_Family_Selection/results/\n")
  cat("Combined results: STEP_1_Family_Selection/results/dataset_all/\n")
  cat("====================================================================\n")
} else {
  stop("Invalid RUN_MODE. Use: 'test_plots', 'test_master', or 'full_run'")
}

cat("\nDone!\n")
