################################################################################
### FULL EXHAUSTIVE SAME-COHORT ANALYSIS (EC2)
###
### Purpose: Run complete exhaustive analysis across all datasets to establish
###          copula stability across time spans (1-4 years)
###
### Prerequisites:
###   1. Test mode validated successfully (run test_exhaustive_mode.R first)
###   2. EC2 instance running (recommended: c6i.16xlarge or larger)
###   3. All data files available on EC2
###
### Expected runtime: ~2-4 hours per dataset × 4 datasets = 8-16 hours total
### Expected conditions: ~250-300 per dataset × 4 datasets = ~1000-1200 total
################################################################################

# Set working directory to project root
setwd("/path/to/Copula_Sensitivity_Analyses") # UPDATE THIS PATH ON EC2

################################################################################
### CONFIGURATION FOR FULL EXHAUSTIVE RUN
################################################################################

# Enable exhaustive mode for ALL datasets
USE_EXHAUSTIVE_ALL_DATASETS <- TRUE

# DISABLE test mode (run full analysis)
TEST_MODE <- FALSE

# Run all datasets
DATASETS_TO_RUN <- c("dataset_1", "dataset_2", "dataset_3", "dataset_4")

# Run only Step 1 (copula family selection)
STEPS_TO_RUN <- 1

# Enable key features
N_BOOTSTRAP_GOF <- 100 # Include GoF testing
CALCULATE_SGPC <- TRUE # Calculate copula-based SGPs
GENERATE_CONTOUR_PLOTS <- TRUE # Generate visualizations

# EC2 settings (auto-detected)
# These will be set automatically by master_analysis.R on EC2
# USE_PARALLEL <- TRUE  (auto-detected)
# BATCH_MODE <- TRUE    (auto-detected)
# EC2_MODE <- TRUE      (auto-detected)

# Force EC2 mode if needed
EC2_MODE <- TRUE
BATCH_MODE <- TRUE
USE_PARALLEL <- TRUE

################################################################################
### LOGGING AND MONITORING
################################################################################

# Create timestamped log directory
log_timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
log_dir <- file.path("logs", paste0("exhaustive_run_", log_timestamp))
dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)

# Redirect output to log file
log_file <- file.path(log_dir, "exhaustive_analysis.log")
sink(log_file, split = TRUE) # split = TRUE to see output in console too

################################################################################
### SYSTEM INFORMATION
################################################################################

cat("\n")
cat(
  "################################################################################\n"
)
cat("### EXHAUSTIVE SAME-COHORT ANALYSIS - FULL RUN\n")
cat(
  "################################################################################\n"
)
cat("\n")
cat("Start time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("\n")

cat("System Information:\n")
cat("  Hostname:", Sys.info()["nodename"], "\n")
cat("  OS:", Sys.info()["sysname"], Sys.info()["release"], "\n")
cat("  R version:", R.version.string, "\n")
cat("  Cores available:", parallel::detectCores(), "\n")
cat("  Working directory:", getwd(), "\n")
cat("\n")

cat("Analysis Configuration:\n")
cat("  Exhaustive mode: ENABLED\n")
cat("  Test mode: DISABLED (full analysis)\n")
cat("  Datasets:", paste(DATASETS_TO_RUN, collapse = ", "), "\n")
cat("  GoF bootstrap samples:", N_BOOTSTRAP_GOF, "\n")
cat("  SGPc calculation: ENABLED\n")
cat("  Contour plots: ENABLED\n")
cat("  Parallel processing: ENABLED\n")
cat("\n")

cat("Expected Results:\n")
cat("  - Conditions per dataset: ~250-300\n")
cat("  - Total conditions: ~1000-1200\n")
cat("  - Copula families per condition: 6\n")
cat("  - Total copula fits: ~6000-7200\n")
cat("  - Estimated runtime: 8-16 hours\n")
cat("\n")

################################################################################
### RUN ANALYSIS
################################################################################

cat("Starting analysis...\n")
cat("Press Ctrl+C to cancel (30 second warning)\n")
Sys.sleep(30)

start_time <- Sys.time()

# Source the master analysis script
source("master_analysis.R")

end_time <- Sys.time()
duration <- difftime(end_time, start_time, units = "hours")

################################################################################
### COMPLETION REPORT
################################################################################

cat("\n")
cat(
  "################################################################################\n"
)
cat("### ANALYSIS COMPLETE\n")
cat(
  "################################################################################\n"
)
cat("\n")
cat("End time:", format(end_time, "%Y-%m-%d %H:%M:%S"), "\n")
cat("Total duration:", round(duration, 2), "hours\n")
cat("\n")

# Summary statistics
cat("Results Summary:\n")
for (dataset_id in DATASETS_TO_RUN) {
  results_file <- file.path(
    "STEP_1_Family_Selection/results",
    dataset_id,
    "phase1_copula_family_comparison.csv"
  )

  if (file.exists(results_file)) {
    results <- fread(results_file)
    n_conditions <- uniqueN(results$condition_id)
    n_families <- uniqueN(results$family)

    # Count t-copula wins by time span
    winners <- results[,
      .(winner = best_aic[1]),
      by = .(condition_id, year_span)
    ]
    t_wins_by_span <- winners[,
      .(n_wins = sum(winner == "t"), total = .N),
      by = year_span
    ]

    cat("\n", dataset_id, ":\n", sep = "")
    cat("  Conditions:", n_conditions, "\n")
    cat("  T-copula wins by time span:\n")
    for (i in 1:nrow(t_wins_by_span)) {
      span <- t_wins_by_span$year_span[i]
      wins <- t_wins_by_span$n_wins[i]
      total <- t_wins_by_span$total[i]
      pct <- round(100 * wins / total, 1)
      cat(sprintf("    %d-year: %d/%d (%.1f%%)\n", span, wins, total, pct))
    }
  } else {
    cat("\n", dataset_id, ": ✗ Results not found\n", sep = "")
  }
}

cat("\n")
cat("Log file:", log_file, "\n")
cat("Results directory: STEP_1_Family_Selection/results/\n")
cat("\n")

# Close log
sink()

cat("Analysis complete. Log saved to:", log_file, "\n")
