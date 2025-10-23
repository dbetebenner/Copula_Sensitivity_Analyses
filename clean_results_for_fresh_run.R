############################################################################
### Clean Results for Fresh Multi-Dataset Run
### Purpose: Remove old single-dataset results that could interfere
###          with the new multi-dataset structure
############################################################################

cat("\n")
cat("====================================================================\n")
cat("CLEANING OLD RESULTS FOR FRESH MULTI-DATASET RUN\n")
cat("====================================================================\n\n")

results_dir <- "STEP_1_Family_Selection/results"

# Files to potentially remove (old single-dataset format)
old_files <- c(
  "phase1_copula_family_comparison.csv",  # Old single-dataset results
  "phase1_decision.RData",                 # Old decision file
  "phase1_selection_table.csv",            # Old selection table
  "phase1_summary.txt"                     # Old summary
)

files_removed <- 0
files_not_found <- 0

for (file in old_files) {
  filepath <- file.path(results_dir, file)
  if (file.exists(filepath)) {
    file.remove(filepath)
    cat("✓ Removed:", filepath, "\n")
    files_removed <- files_removed + 1
  } else {
    cat("  (not found):", filepath, "\n")
    files_not_found <- files_not_found + 1
  }
}

cat("\n")
cat("====================================================================\n")
cat("CLEANUP SUMMARY\n")
cat("====================================================================\n")
cat("Files removed:", files_removed, "\n")
cat("Files not found:", files_not_found, "\n\n")

if (files_removed > 0) {
  cat("Old single-dataset results have been cleaned.\n")
  cat("Ready for fresh multi-dataset run!\n\n")
} else {
  cat("No old files found - directory is already clean.\n\n")
}

cat("Next step: Run the multi-dataset test\n")
cat("  Rscript run_test_multiple_datasets.R\n\n")

cat("Results will be saved to dataset-specific subdirectories:\n")
cat("  STEP_1_Family_Selection/results/dataset_1/\n")
cat("  STEP_1_Family_Selection/results/dataset_2/\n")
cat("  STEP_1_Family_Selection/results/dataset_3/\n")
cat("  STEP_1_Family_Selection/results/dataset_all/  (combined)\n\n")

