################################################################################
# Force Re-Run of STEP 2
# 
# Purpose: Delete STEP 2 results to force master_analysis.R to re-run the
#          transformation validation (testing parallel implementation)
################################################################################

cat("====================================================================\n")
cat("FORCE RE-RUN OF STEP 2\n")
cat("====================================================================\n\n")

# Define STEP 2 results files
step2_results_dir <- "STEP_2_Transformation_Validation/results"
step2_files <- c(
  "exp5_transformation_validation_summary.csv",
  "exp5_transformation_validation_full.RData"
)

# Show current state
cat("Current STEP 2 results:\n")
for (f in step2_files) {
  full_path <- file.path(step2_results_dir, f)
  if (file.exists(full_path)) {
    file_info <- file.info(full_path)
    cat("  ✓", f, "-", round(file_info$size / 1024, 1), "KB",
        "(modified:", format(file_info$mtime, "%Y-%m-%d %H:%M:%S"), ")\n")
  } else {
    cat("  ✗", f, "- NOT FOUND\n")
  }
}
cat("\n")

# Ask for confirmation (unless in batch mode)
if (!exists("BATCH_MODE") || !BATCH_MODE) {
  cat("This will delete the above files and force STEP 2 to re-run.\n")
  cat("Continue? (y/n): ")
  response <- tolower(trimws(readline()))
  
  if (response != "y") {
    cat("\nAborted. No files deleted.\n")
    quit(save = "no")
  }
  cat("\n")
}

# Delete files
cat("Deleting STEP 2 results...\n")
deleted_count <- 0
for (f in step2_files) {
  full_path <- file.path(step2_results_dir, f)
  if (file.exists(full_path)) {
    file.remove(full_path)
    cat("  ✓ Deleted:", f, "\n")
    deleted_count <- deleted_count + 1
  }
}

if (deleted_count > 0) {
  cat("\n✓ Deleted", deleted_count, "files\n\n")
} else {
  cat("\n✓ No files to delete (already clean)\n\n")
}

# Also delete figures if requested
figures_dir <- file.path(step2_results_dir, "figures/exp5_transformation_validation")
if (dir.exists(figures_dir)) {
  n_figures <- length(list.files(figures_dir, pattern = "\\.pdf$"))
  if (n_figures > 0) {
    cat("Found", n_figures, "PDF figures in", figures_dir, "\n")
    
    if (!exists("BATCH_MODE") || !BATCH_MODE) {
      cat("Delete figures too? (y/n): ")
      response <- tolower(trimws(readline()))
      
      if (response == "y") {
        unlink(figures_dir, recursive = TRUE)
        cat("✓ Deleted figures directory\n\n")
      } else {
        cat("Kept existing figures\n\n")
      }
    }
  }
}

cat("====================================================================\n")
cat("READY TO RE-RUN STEP 2\n")
cat("====================================================================\n\n")
cat("Now run:\n")
cat("  STEPS_TO_RUN <- 2\n")
cat("  source(\"master_analysis.R\")\n\n")
cat("Expected result:\n")
cat("  ✓ STEP 2 will execute (not skip)\n")
if (exists("USE_PARALLEL") && USE_PARALLEL) {
  cat("  ✓ Parallel mode: ~4-6 minutes\n")
} else {
  cat("  ✓ Check if parallel mode enabled for your machine\n")
}
cat("\n")
