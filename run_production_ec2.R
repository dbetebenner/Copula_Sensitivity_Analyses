################################################################################
### PRODUCTION RUN: EC2 with High-Precision Bootstrap (N=1000)
### Purpose: Generate final publication-quality results with rigorous GoF testing
### Expected runtime: 8-10 hours on c8g.12xlarge (~$16-21)
################################################################################

cat("====================================================================\n")
cat("PRODUCTION RUN: HIGH-PRECISION BOOTSTRAP (N=1000)\n")
cat("====================================================================\n\n")

# Production configuration
DATASETS_TO_RUN <- c("dataset_1", "dataset_2", "dataset_3")
STEPS_TO_RUN <- 1
BATCH_MODE <- TRUE
SKIP_COMPLETED <- FALSE
N_BOOTSTRAP_GOF <- 1000  # High-precision bootstrap for publication

cat("Configuration:\n")
cat("  Datasets:", paste(DATASETS_TO_RUN, collapse = ", "), "\n")
cat("  Steps:", paste(STEPS_TO_RUN, collapse = ", "), "\n")
cat("  Bootstrap samples:", N_BOOTSTRAP_GOF, "\n\n")

cat("Performance expectations:\n")
cat("  Recommended instance: c8g.12xlarge (48 vCPUs, 96 GB RAM)\n")
cat("  Expected runtime: 8-10 hours\n")
cat("  Expected cost: ~$16-21 (on-demand), ~$7-9 (spot)\n")
cat("  Output: 774 copula fits with rigorous GoF testing\n\n")

cat("Quality metrics:\n")
cat("  Bootstrap precision: High (N=1000 per fit)\n")
cat("  GoF p-value precision: ±0.001\n")
cat("  Suitable for: Final paper submission, peer review\n\n")

# Confirm production mode (safety check)
cat("====================================================================\n")
cat("WARNING: This is a PRODUCTION run with N=1000 bootstraps.\n")
cat("It will take 8-10 hours and cost ~$16-21 on c8g.12xlarge.\n")
cat("====================================================================\n\n")

# Timestamp for tracking
start_time <- Sys.time()
cat("Production run started:", format(start_time, "%Y-%m-%d %H:%M:%S %Z"), "\n\n")

# Run the master analysis
source("master_analysis.R")

# End timestamp
end_time <- Sys.time()
elapsed <- difftime(end_time, start_time, units = "hours")

cat("\n====================================================================\n")
cat("PRODUCTION RUN COMPLETE\n")
cat("====================================================================\n\n")

cat("Timing summary:\n")
cat("  Started:", format(start_time, "%Y-%m-%d %H:%M:%S %Z"), "\n")
cat("  Ended:", format(end_time, "%Y-%m-%d %H:%M:%S %Z"), "\n")
cat("  Total runtime:", round(elapsed, 2), "hours\n\n")

# Cost estimate (assuming on-demand c8g.12xlarge at $2.07/hour)
cost_estimate <- as.numeric(elapsed) * 2.07
cat("  Estimated cost: $", round(cost_estimate, 2), " (on-demand)\n\n", sep = "")

cat("Results location:\n")
cat("  Individual datasets: STEP_1_Family_Selection/results/dataset_*/\n")
cat("  Combined results: STEP_1_Family_Selection/results/dataset_all/\n")
cat("  Main CSV: phase1_copula_family_comparison_all_datasets.csv\n\n")

cat("Next steps:\n")
cat("1. Download results from EC2 to local machine\n")
cat("2. Run phase1_analysis.R to generate summary plots and tables\n")
cat("3. Review GoF pass rates by family\n")
cat("4. Add GoF analysis sections to paper\n\n")

cat("Verification:\n")
cat("  Total fits: 774 (129 conditions × 6 families)\n")
cat("  Check all gof_pvalue columns are populated (not NA)\n")
cat("  Check gof_method shows 'bootstrap_gofTstat_N=1000' for t-copula\n\n")

