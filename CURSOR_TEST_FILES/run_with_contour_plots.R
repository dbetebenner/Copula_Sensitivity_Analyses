############################################################################
### RUN PHASE 1 WITH CONTOUR PLOT GENERATION
############################################################################
### Purpose: Wrapper script to run Phase 1 copula family selection
###          with contour plot visualization enabled
############################################################################

cat("\n")
cat("====================================================================\n")
cat("PHASE 1 WITH CONTOUR PLOT VISUALIZATION\n")
cat("====================================================================\n")
cat("\n")

# Enable contour plot generation
GENERATE_CONTOUR_PLOTS <- TRUE

cat("CONFIGURATION:\n")
cat("  Contour plot generation: ENABLED\n")
cat("  Output directory: STEP_1_Family_Selection/contour_plots/\n")
cat("\n")

# Check if visualization functions exist
if (!file.exists("functions/copula_contour_plots.R")) {
  stop("Visualization functions not found. Please ensure copula_contour_plots.R exists.")
}

# Optional: Set number of conditions to process (for testing)
# Uncomment and modify to limit the number of conditions
# MAX_CONDITIONS <- 5  # Process only first 5 conditions

# Optional: Set GoF bootstrap samples (reduce for faster testing with plots)
N_BOOTSTRAP_GOF <- 100  # Reduce from default for faster processing with plots

cat("SETTINGS:\n")
cat("  GoF bootstrap samples:", N_BOOTSTRAP_GOF, "\n")
if (exists("MAX_CONDITIONS")) {
  cat("  Maximum conditions:", MAX_CONDITIONS, "\n")
}
cat("\n")

# Source and run the main Phase 1 script
cat("Starting Phase 1 analysis with visualization...\n")
cat("--------------------------------------------------------------------\n\n")

source("STEP_1_Family_Selection/phase1_family_selection_parallel.R")

# After completion, check if plots were generated
plot_dir <- "STEP_1_Family_Selection/contour_plots"
if (dir.exists(plot_dir)) {
  cat("\n")
  cat("====================================================================\n")
  cat("CONTOUR PLOT GENERATION COMPLETE\n")
  cat("====================================================================\n")
  
  # Count generated plots
  all_pdfs <- list.files(plot_dir, pattern = "\\.pdf$", recursive = TRUE)
  n_plots <- length(all_pdfs)
  
  cat("\n")
  cat("Generated", n_plots, "PDF files\n")
  
  # List datasets with plots
  dataset_dirs <- list.dirs(plot_dir, recursive = FALSE, full.names = FALSE)
  dataset_dirs <- dataset_dirs[!grepl("dataset_all|test", dataset_dirs)]
  
  if (length(dataset_dirs) > 0) {
    cat("\nDatasets with plots:\n")
    for (ds in dataset_dirs) {
      ds_pdfs <- list.files(file.path(plot_dir, ds), pattern = "\\.pdf$", recursive = TRUE)
      cat("  -", ds, ":", length(ds_pdfs), "plots\n")
    }
  }
  
  cat("\n")
  cat("To view plots, navigate to:", plot_dir, "\n")
  cat("\n")
  
  # Suggest next steps
  cat("NEXT STEPS:\n")
  cat("-----------\n")
  cat("1. Review generated plots in:", plot_dir, "\n")
  cat("2. Run summary script to create comparison figures:\n")
  cat("   source('STEP_1_Family_Selection/create_contour_plot_summary.R')\n")
  cat("3. Select representative plots for paper\n")
  cat("\n")
  
} else {
  cat("\n")
  cat("WARNING: No plots were generated.\n")
  cat("Check that GENERATE_CONTOUR_PLOTS was properly set.\n")
}

cat("Script completed.\n")