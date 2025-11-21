############################################################################
### TEST SCRIPT: Copula Contour Plot Visualization for Single Condition
############################################################################
### Purpose: Test the contour plot visualization pipeline on a single 
###          condition before running the full parallel analysis
###
### Usage:
###   1. Ensure data files are available (see dataset_configs.R for paths)
###   2. Optionally edit DATASET_TO_TEST below to select which dataset
###   3. Run from project root: source("STEP_1_Family_Selection/test_contour_plots.R")
###   4. Review generated plots in: STEP_1_Family_Selection/contour_plots/test/
###
### This script runs STANDALONE - no need to run master_analysis.R first
############################################################################

require(data.table)
require(copula)
require(splines2)
require(ggplot2)
require(viridis)
require(gridExtra)

cat("\n")
cat("====================================================================\n")
cat("TEST: COPULA CONTOUR PLOT VISUALIZATION\n")
cat("====================================================================\n")
cat("\n")

# Determine project root and set up path prefix
if (file.exists("functions/longitudinal_pairs.R") && file.exists("dataset_configs.R")) {
  PROJECT_ROOT <- getwd()
  cat("Working directory:", PROJECT_ROOT, "\n")
} else if (file.exists("../functions/longitudinal_pairs.R") && file.exists("../dataset_configs.R")) {
  PROJECT_ROOT <- normalizePath("..")
  cat("Detected project root:", PROJECT_ROOT, "\n")
  cat("Current working directory:", getwd(), "\n")
  cat("Note: Script will use relative paths from project root\n")
} else {
  stop("Cannot locate project root. Please run from project root or STEP_1_Family_Selection directory.")
}

# Source required functions
cat("Loading functions...\n")

# Build paths relative to project root
if (PROJECT_ROOT == getwd()) {
  func_prefix <- ""
} else {
  func_prefix <- "../"
}

source(paste0(func_prefix, "functions/longitudinal_pairs.R"))
source(paste0(func_prefix, "functions/ispline_ecdf.R"))
source(paste0(func_prefix, "functions/copula_bootstrap.R"))
source(paste0(func_prefix, "functions/copula_contour_plots.R"))
source(paste0(func_prefix, "dataset_configs.R"))

################################################################################
### CONFIGURATION
################################################################################

# Configuration for multi-format export (used throughout script)
EXPORT_FORMATS <- c("pdf", "svg", "png")  # Export to all three formats
# Options:
#   c("pdf")                 - PDF only (smallest storage)
#   c("pdf", "svg")          - PDF + web-optimized vector graphics
#   c("pdf", "svg", "png")   - All formats (recommended for publications)
EXPORT_DPI <- 300             # DPI for PNG exports (300 = publication quality)
EXPORT_VERBOSE <- FALSE       # Set TRUE to see export messages

################################################################################
### DATASET SELECTION
################################################################################

# Select which dataset to use for testing
# Options: "dataset_1", "dataset_2", or "dataset_3"
DATASET_TO_TEST <- "dataset_1"  # Change this to test different datasets

if (!DATASET_TO_TEST %in% names(DATASETS)) {
  stop("Invalid dataset selection. Choose from: ", paste(names(DATASETS), collapse = ", "))
}

current_dataset <- DATASETS[[DATASET_TO_TEST]]
cat("Dataset:", current_dataset$name, "\n")
cat("  Description:", current_dataset$description, "\n\n")

################################################################################
### DATA LOADING
################################################################################

# Load the actual data from .Rdata file
if (!exists("STATE_DATA_LONG")) {
  cat("Loading state data from file...\n")
  
  # Try local path first
  data_path <- current_dataset$local_path
  
  if (!file.exists(data_path)) {
    stop("Data file not found at: ", data_path,
         "\nPlease ensure data is available or update path in dataset_configs.R")
  }
  
  load(data_path)
  
  # Rename the loaded object to STATE_DATA_LONG
  if (exists(current_dataset$rdata_object_name)) {
    STATE_DATA_LONG <- get(current_dataset$rdata_object_name)
    WORKSPACE_OBJECT_NAME <- "STATE_DATA_LONG"
    cat("  Loaded:", current_dataset$rdata_object_name, "\n")
    cat("  Rows:", nrow(STATE_DATA_LONG), "\n\n")
  } else {
    stop("Expected object '", current_dataset$rdata_object_name, "' not found in .Rdata file")
  }
}

################################################################################
### HELPER FUNCTIONS
################################################################################

# Define get_state_data() helper function (normally defined in master_analysis.R)
get_state_data <- function() {
  if (!exists("WORKSPACE_OBJECT_NAME")) {
    stop("ERROR: WORKSPACE_OBJECT_NAME not defined")
  }
  if (!exists(WORKSPACE_OBJECT_NAME)) {
    stop("ERROR: State data not loaded. Variable '", WORKSPACE_OBJECT_NAME, "' not found.")
  }
  return(get(WORKSPACE_OBJECT_NAME))
}

################################################################################
### DEFINE TEST CONDITION
################################################################################

# Test with a single representative condition (automatically selected from dataset)
# Uses the first available year and content area, with consecutive grades

# Ensure we have valid grades for a 1-year span
available_grades <- current_dataset$grades_available
if (length(available_grades) < 2) {
  stop("Dataset must have at least 2 grades available")
}

# Use second and third available grades (e.g., if grades are 3:10, use 4 and 5)
grade_idx <- min(2, length(available_grades) - 1)

test_condition <- list(
  grade_prior = available_grades[grade_idx],
  grade_current = available_grades[grade_idx + 1],
  year_prior = as.character(current_dataset$years_available[1]),
  year_span = 1,
  content = current_dataset$content_areas[1]
)

# Calculate year_current
test_condition$year_current <- as.character(as.numeric(test_condition$year_prior) + test_condition$year_span)

# Add dataset metadata
test_condition$dataset_id <- current_dataset$id
test_condition$dataset_name <- current_dataset$name
test_condition$anonymized_state <- current_dataset$anonymized_state

cat("Test Condition:\n")
cat("  Grade:", test_condition$grade_prior, "->", test_condition$grade_current, "\n")
cat("  Year:", test_condition$year_prior, "->", test_condition$year_current, "\n")
cat("  Content:", test_condition$content, "\n")
cat("\n")

################################################################################
### CREATE LONGITUDINAL PAIRS
################################################################################

cat("Creating longitudinal pairs...\n")
pairs_full <- create_longitudinal_pairs(
  data = get_state_data(),
  grade_prior = test_condition$grade_prior,
  grade_current = test_condition$grade_current,
  year_prior = test_condition$year_prior,
  content_prior = test_condition$content,
  content_current = test_condition$content
)

if (is.null(pairs_full) || nrow(pairs_full) < 100) {
  stop("Insufficient data for test condition")
}

cat("  Number of pairs:", nrow(pairs_full), "\n\n")

################################################################################
### FIT COPULAS WITH VISUALIZATION DATA
################################################################################

cat("Fitting copulas...\n")

# Create I-spline frameworks (though we'll use empirical ranks for Phase 1)
framework_prior <- create_ispline_framework(pairs_full$SCALE_SCORE_PRIOR)
framework_current <- create_ispline_framework(pairs_full$SCALE_SCORE_CURRENT)

# Define copula families to test
copula_families <- c("gaussian", "t", "clayton", "gumbel", "frank", "comonotonic")

# Set up output directory (relative to project root)
if (PROJECT_ROOT == getwd()) {
  output_dir <- file.path("STEP_1_Family_Selection/results/test/contour_plots",
                          sprintf("%s_G%d_G%d_%s", 
                                 test_condition$year_prior, 
                                 test_condition$grade_prior, 
                                 test_condition$grade_current, 
                                 test_condition$content))
} else {
  output_dir <- file.path("results/test/contour_plots",
                          sprintf("%s_G%d_G%d_%s", 
                                 test_condition$year_prior, 
                                 test_condition$grade_prior, 
                                 test_condition$grade_current, 
                                 test_condition$content))
}

# Fit copulas with data saving enabled
copula_fits <- fit_copula_from_pairs(
  scores_prior = pairs_full$SCALE_SCORE_PRIOR,
  scores_current = pairs_full$SCALE_SCORE_CURRENT,
  framework_prior = framework_prior,
  framework_current = framework_current,
  copula_families = copula_families,
  return_best = FALSE,
  use_empirical_ranks = TRUE,  # Phase 1: Use empirical ranks
  n_bootstrap_gof = NULL,
  save_copula_data = TRUE,
  output_dir = output_dir
)

cat("\nCopula fitting results:\n")
cat("  Best family:", copula_fits$best_family, "\n")
cat("  Empirical Kendall's tau:", round(copula_fits$empirical_tau, 3), "\n")

# Display AIC/BIC comparison
aic_values <- sapply(copula_fits$results, function(x) if (!is.null(x)) x$aic else NA)
bic_values <- sapply(copula_fits$results, function(x) if (!is.null(x)) x$bic else NA)

comparison_df <- data.frame(
  Family = names(aic_values),
  AIC = round(aic_values, 1),
  BIC = round(bic_values, 1),
  Delta_AIC = round(aic_values - min(aic_values, na.rm = TRUE), 1)
)
comparison_df <- comparison_df[order(comparison_df$AIC),]

cat("\nModel comparison:\n")
print(comparison_df)
cat("\n")

################################################################################
### GENERATE VISUALIZATION PLOTS
################################################################################

cat("Generating visualization plots...\n")

# Prepare condition info for plotting
condition_info <- list(
  dataset_id = test_condition$dataset_id,
  dataset_number = {
    # Extract number from dataset_id (e.g., "dataset_1" -> "1")
    parts <- strsplit(test_condition$dataset_id, "_")[[1]]
    if (length(parts) >= 2) {
      parts[2]
    } else {
      test_condition$dataset_id  # Fallback to full ID
    }
  },
  year_prior = test_condition$year_prior,
  year_current = test_condition$year_current,
  grade_prior = test_condition$grade_prior,
  grade_current = test_condition$grade_current,
  content = test_condition$content
)

# NOTE: Initial plots generated without bootstrap uncertainty
# Bootstrap is run afterwards and uncertainty plots added separately
# To integrate bootstrap into all plots, move bootstrap section before this call
plots <- generate_condition_plots(
  pseudo_obs = copula_fits$pseudo_obs,
  original_scores = pairs_full[, .(SCALE_SCORE_PRIOR, SCALE_SCORE_CURRENT)],
  copula_results = copula_fits$results,
  best_family = copula_fits$best_family,
  output_dir = output_dir,
  condition_info = condition_info,
  bootstrap_results = NULL,  # Will be added after bootstrap section
  save_plots = TRUE,
  grid_size = 300,  # High resolution for smooth contours
  export_formats = EXPORT_FORMATS,
  export_dpi = EXPORT_DPI,
  export_verbose = EXPORT_VERBOSE
)

################################################################################
### BOOTSTRAP UNCERTAINTY QUANTIFICATION
################################################################################

cat("\n")
cat("====================================================================\n")
cat("BOOTSTRAP UNCERTAINTY QUANTIFICATION\n")
cat("====================================================================\n")
cat("\n")

# Configuration for bootstrap
N_BOOTSTRAP <- 100  # 200-500 recommended; 100 for testing
USE_PARALLEL <- TRUE  # Set to FALSE if you want sequential processing
N_CORES <- NULL  # NULL = use detectCores() - 1
BOOTSTRAP_ALL_FAMILIES <- TRUE  # Set FALSE to only bootstrap best family

cat("Running parametric bootstrap to quantify parameter uncertainty...\n")
cat("  Number of bootstrap samples:", N_BOOTSTRAP, "\n")
cat("  Parallel processing:", USE_PARALLEL, "\n")
if (USE_PARALLEL && .Platform$OS.type == "unix") {
  require(parallel)
  if (is.null(N_CORES)) {
    N_CORES <- detectCores() - 1
  }
  cat("  Cores to use:", N_CORES, "\n")
}
cat("\n")

# Determine which families to bootstrap
best_family <- copula_fits$best_family
if (BOOTSTRAP_ALL_FAMILIES) {
  # Exclude comonotonic (deterministic, no parameters to bootstrap)
  bootstrap_families <- setdiff(copula_families, "comonotonic")
  cat("Running bootstrap on ALL parametric copula families for complete uncertainty visualization...\n")
  cat("  Families:", paste(bootstrap_families, collapse = ", "), "\n")
  cat("  (Excludes comonotonic - deterministic with no parameters)\n")
  cat("  (This provides uncertainty overlays for all parametric plots)\n\n")
} else {
  bootstrap_families <- best_family
  cat("Running bootstrap on BEST family only:", best_family, "\n")
  cat("  (Set BOOTSTRAP_ALL_FAMILIES=TRUE for complete visualization)\n\n")
}

bootstrap_start_time <- Sys.time()

bootstrap_results <- bootstrap_copula_estimation(
  pairs_data = pairs_full,
  n_sample_prior = nrow(pairs_full),
  n_sample_current = nrow(pairs_full),
  n_bootstrap = N_BOOTSTRAP,
  framework_prior = framework_prior,
  framework_current = framework_current,
  sampling_method = "paired",  # Preserves within-student correlation
  copula_families = bootstrap_families,  # Selected families
  with_replacement = TRUE,
  use_empirical_ranks = TRUE,  # Match Phase 1 approach
  use_parallel = USE_PARALLEL,
  n_cores = N_CORES
)

bootstrap_elapsed <- difftime(Sys.time(), bootstrap_start_time, units = "secs")
cat("Bootstrap completed in", round(bootstrap_elapsed, 1), "seconds\n\n")

################################################################################
### GENERATE UNCERTAINTY OVERLAY PLOTS (NEW INTEGRATED APPROACH)
################################################################################

cat("\n")
cat("====================================================================\n")
cat("GENERATING UNCERTAINTY OVERLAY PLOTS\n")
cat("====================================================================\n")
cat("\n")

cat("Creating gradient uncertainty visualizations for each copula family...\n")
cat("  (Zissou1 background + black gradient uncertainty + empirical overlay)\n\n")

# Call the modified generate_condition_plots with bootstrap_results
# This will create the new uncertainty overlay plots in each family subdirectory
uncertainty_plots <- generate_condition_plots(
  pseudo_obs = copula_fits$pseudo_obs,
  original_scores = pairs_full[, .(SCALE_SCORE_PRIOR, SCALE_SCORE_CURRENT)],
  copula_results = copula_fits$results,
  best_family = copula_fits$best_family,
  output_dir = output_dir,
  condition_info = condition_info,
  bootstrap_results = bootstrap_results,  # NOW with bootstrap results!
  save_plots = TRUE,
  grid_size = 300,  # High resolution for smooth contours
  export_formats = EXPORT_FORMATS,
  export_dpi = EXPORT_DPI,
  export_verbose = EXPORT_VERBOSE
)

cat("\n")
cat("Uncertainty overlay plots saved to family subdirectories:\n")
for (family in names(copula_fits$results)) {
  if (!is.null(copula_fits$results[[family]]) && family != "comonotonic") {
    family_dir <- toupper(family)
    cat(sprintf("  %s/%s_copula_with_uncertainty_CDF.pdf\n", family_dir, family))
  }
}
cat("\n")
cat("Note: PDF uncertainty plots are not created - the uncertainty ribbon\n")
cat("      visualization is designed for CDFs only.\n")
cat("\n")

# Legacy uncertainty plots removed - now using integrated uncertainty ribbon plots
# located in family-specific subdirectories (e.g., T/t_copula_with_uncertainty_CDF.pdf)
cat("====================================================================\n")
cat("VISUALIZATION TEST COMPLETE\n")
cat("====================================================================\n")
cat("\n")
cat("Generated plots have been saved to:\n")
cat("  ", output_dir, "\n")
cat("\n")
cat("Files created:\n")
plot_files <- list.files(output_dir, pattern = "\\.pdf$", full.names = FALSE)
for (f in plot_files) {
  cat("  -", f, "\n")
}

cat("\n")
cat("Key plots to review:\n")
cat("  MAIN DIRECTORY PLOTS:\n")
cat("    1. empirical_copula_CDF.pdf / empirical_copula_PDF.pdf\n")
cat("    2. bivariate_density_original.pdf - Original score distribution\n")
cat("    3. summary_grid.pdf - All key plots in one figure\n")
cat("\n")
cat("  FAMILY SUBDIRECTORIES (e.g., GAUSSIAN/, T/, CLAYTON/, etc.):\n")
cat("    4. [family]_copula_CDF.pdf - Parametric copula (with sample size)\n")
cat("    5. [family]_copula_PDF.pdf - Copula density function\n")
cat("    6. [family]_copula_with_uncertainty_CDF.pdf - WITH bootstrap ribbons\n")
cat("    7. comparison_empirical_vs_[family]_CDF.pdf - Difference heatmap\n")
cat("\n")
cat("  Note: Inline contour labels (0.1-0.9) replace legends on uncertainty plots\n")
cat("  Note: PDF uncertainty plots not created (ribbon method for CDFs only)\n")
cat("\n")
cat("Bootstrap summary:\n")
cat("  Successful samples:", bootstrap_results$n_success, "of", N_BOOTSTRAP, "\n")
cat("  Elapsed time:", round(bootstrap_elapsed, 1), "seconds\n")
if (USE_PARALLEL) {
  cat("  Speedup from parallelization: ~", round(N_CORES * 0.7, 1), "x\n")
}
cat("\n")

################################################################################
### OPTIONAL: TEST WITH DIFFERENT CONDITIONS
################################################################################

# To test with different conditions, modify the test_condition above
# Examples of other conditions to try:

# # 2-year span
# test_condition <- list(
#   grade_prior = 3,
#   grade_current = 5,
#   year_prior = "2010",
#   year_span = 2,
#   content = "READING"
# )

# # 3-year span
# test_condition <- list(
#   grade_prior = 5,
#   grade_current = 8,
#   year_prior = "2010",
#   year_span = 3,
#   content = "MATHEMATICS"
# )

################################################################################
### DIAGNOSTIC CHECKS
################################################################################

cat("Diagnostic Information:\n")
cat("----------------------------\n")

# Check if ks package is available for kernel density
if (requireNamespace("ks", quietly = TRUE)) {
  cat("✓ 'ks' package available for kernel density estimation\n")
} else {
  cat("⚠ 'ks' package not found - using simpler density methods\n")
  cat("  Install with: install.packages('ks')\n")
}

# Check if ggdensity package is available
if (requireNamespace("ggdensity", quietly = TRUE)) {
  cat("✓ 'ggdensity' package available for enhanced visualizations\n")
} else {
  cat("⚠ 'ggdensity' package not found - using standard ggplot2\n")
  cat("  Install with: install.packages('ggdensity')\n")
}

cat("\n")

# Memory usage
mem_used <- as.numeric(object.size(plots)) / 1024^2
cat("Memory used by plots:", round(mem_used, 1), "MB\n")

# Timing information
if (exists("start_time")) {
  elapsed_time <- difftime(Sys.time(), start_time, units = "secs")
  cat("Total execution time:", round(elapsed_time, 1), "seconds\n")
}

cat("\nTest script completed successfully!\n")
