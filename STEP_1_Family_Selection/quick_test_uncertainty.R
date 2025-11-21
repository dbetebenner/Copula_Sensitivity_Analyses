################################################################################
### Quick Test: Verify Uncertainty Ribbon Plots Are Created
################################################################################
### Purpose: Minimal test to verify the bootstrap uncertainty plots work
### Run this to test the fix without full 45-minute run
################################################################################

# Setup
setwd("/Users/conet/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses")
source("functions/copula_bootstrap.R")
source("functions/copula_contour_plots.R")
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")

# Multi-format export configuration
# Note: copula_contour_plots.R already sources export_plot_utils.R
EXPORT_FORMATS <- c("pdf", "svg", "png")  # Export to all formats for testing
EXPORT_DPI <- 300
EXPORT_VERBOSE <- TRUE  # Show export messages in test mode

################################################################################
### LOAD DATA (Same as test_contour_plots.R)
################################################################################

# Load dataset configuration
source("dataset_configs.R")

# Set which dataset to test
# Use dataset_1 (same as main test script for consistency)
DATASET_TO_TEST <- "dataset_1"

if (!DATASET_TO_TEST %in% names(DATASETS)) {
  stop("Dataset '", DATASET_TO_TEST, "' not found. Available: ", 
       paste(names(DATASETS), collapse = ", "))
}

current_dataset <- DATASETS[[DATASET_TO_TEST]]

cat("Testing with dataset:", current_dataset$name, "\n")
cat("  Description:", current_dataset$description, "\n\n")

# Load the .Rdata file from local path
data_path <- current_dataset$local_path

cat("Loading data from:", data_path, "\n")

if (!file.exists(data_path)) {
  stop("Data file not found at: ", data_path,
       "\nPlease ensure data is available or update path in dataset_configs.R")
}

load(data_path)

# Check if the expected object was loaded
if (exists(current_dataset$rdata_object_name)) {
  STATE_DATA_LONG <- get(current_dataset$rdata_object_name)
  WORKSPACE_OBJECT_NAME <- "STATE_DATA_LONG"
  cat("  Loaded:", current_dataset$rdata_object_name, "\n")
  cat("  Rows:", nrow(STATE_DATA_LONG), "\n\n")
} else {
  stop("Expected object '", current_dataset$rdata_object_name, "' not found in .Rdata file")
}

# Helper function
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

# Auto-select test condition from available data
available_years <- sort(unique(as.character(get_state_data()$YEAR)))
available_grades <- sort(unique(as.numeric(get_state_data()$GRADE)))

if (length(available_grades) < 2) {
  stop("Dataset must have at least 2 grades available")
}

# Use second and third available grades
grade_idx <- min(2, length(available_grades) - 1)

test_condition <- list(
  grade_prior = as.numeric(available_grades[grade_idx]),
  grade_current = as.numeric(available_grades[grade_idx + 1]),
  year_prior = as.character(available_years[1]),
  year_span = 1,
  content = current_dataset$content_areas[1]
)

test_condition$year_current <- as.character(as.numeric(test_condition$year_prior) + test_condition$year_span)

cat("Test Condition:\n")
cat("  Grade:", test_condition$grade_prior, "->", test_condition$grade_current, "\n")
cat("  Year:", test_condition$year_prior, "->", test_condition$year_current, "\n")
cat("  Content:", test_condition$content, "\n\n")

################################################################################
### CREATE PAIRS
################################################################################

cat("Creating test pairs...\n")
pairs_test <- create_longitudinal_pairs(
  data = get_state_data(),
  grade_prior = test_condition$grade_prior,
  grade_current = test_condition$grade_current,
  year_prior = test_condition$year_prior,
  content_prior = test_condition$content,
  content_current = test_condition$content
)

if (is.null(pairs_test) || nrow(pairs_test) < 100) {
  stop("Insufficient data for test condition")
}

cat("  Pairs created:", nrow(pairs_test), "\n\n")

################################################################################
### FIT COPULAS
################################################################################

cat("Fitting copulas (fast, no GoF)...\n")
framework_prior <- create_ispline_framework(pairs_test$SCALE_SCORE_PRIOR)
framework_current <- create_ispline_framework(pairs_test$SCALE_SCORE_CURRENT)

copula_fits <- fit_copula_from_pairs(
  scores_prior = pairs_test$SCALE_SCORE_PRIOR,
  scores_current = pairs_test$SCALE_SCORE_CURRENT,
  framework_prior = framework_prior,
  framework_current = framework_current,
  copula_families = c("gaussian", "t", "clayton", "frank", "gumbel", "comonotonic"),
  return_best = FALSE,
  use_empirical_ranks = TRUE,
  n_bootstrap_gof = NULL  # Skip GoF for speed
)

cat("  Best family:", copula_fits$best_family, "\n\n")

################################################################################
### BOOTSTRAP
################################################################################

cat("Running quick bootstrap (100 samples, 5 families)...\n")
bootstrap_start <- Sys.time()

bootstrap_results <- bootstrap_copula_estimation(
  pairs_data = pairs_test,
  n_sample_prior = nrow(pairs_test),
  n_sample_current = nrow(pairs_test),
  n_bootstrap = 100,  # 100 iterations for testing
  framework_prior = framework_prior,
  framework_current = framework_current,
  sampling_method = "paired",
  copula_families = c("gaussian", "t", "clayton", "frank", "gumbel"),  # 5 Archimedean families
  with_replacement = TRUE,
  use_empirical_ranks = TRUE,
  use_parallel = TRUE
)

cat("Bootstrap completed in", round(difftime(Sys.time(), bootstrap_start, units = "secs"), 1), "seconds\n\n")

################################################################################
### TEST UNCERTAINTY CALCULATION
################################################################################

cat("====================================================================\n")
cat("TESTING UNCERTAINTY CALCULATION\n")
cat("====================================================================\n\n")

cat("Checking bootstrap structure...\n")
cat("  bootstrap_results$bootstrap_results length:", length(bootstrap_results$bootstrap_results), "\n")
cat("  First result exists:", !is.null(bootstrap_results$bootstrap_results[[1]]), "\n")

if (!is.null(bootstrap_results$bootstrap_results[[1]])) {
  cat("  Has $results:", !is.null(bootstrap_results$bootstrap_results[[1]]$results), "\n")
  if (!is.null(bootstrap_results$bootstrap_results[[1]]$results)) {
    cat("  Families in results:", paste(names(bootstrap_results$bootstrap_results[[1]]$results), collapse=", "), "\n")
  }
}
cat("\n")

# Test gaussian
cat("Attempting to calculate uncertainty for GAUSSIAN...\n")
uncertainty_gaussian <- calculate_bootstrap_uncertainty(
  bootstrap_results = bootstrap_results,
  family = "gaussian",
  grid_size = 50,  # Smaller grid for speed
  method = "cdf"
)

if (!is.null(uncertainty_gaussian)) {
  cat("  ✓ SUCCESS! Uncertainty calculation worked\n")
  cat("    Point estimate dimensions:", paste(dim(uncertainty_gaussian$point_estimate), collapse="x"), "\n")
  cat("    N bootstrap samples used:", uncertainty_gaussian$n_bootstrap, "\n\n")
} else {
  cat("  ✗ FAILED! Uncertainty calculation returned NULL\n\n")
}

# Test t
cat("Attempting to calculate uncertainty for T...\n")
uncertainty_t <- calculate_bootstrap_uncertainty(
  bootstrap_results = bootstrap_results,
  family = "t",
  grid_size = 50,
  method = "cdf"
)

if (!is.null(uncertainty_t)) {
  cat("  ✓ SUCCESS! Uncertainty calculation worked\n")
  cat("    Point estimate dimensions:", paste(dim(uncertainty_t$point_estimate), collapse="x"), "\n")
  cat("    N bootstrap samples used:", uncertainty_t$n_bootstrap, "\n\n")
} else {
  cat("  ✗ FAILED! Uncertainty calculation returned NULL\n\n")
}

# Test Clayton
cat("Attempting to calculate uncertainty for CLAYTON...\n")
uncertainty_clayton <- calculate_bootstrap_uncertainty(
  bootstrap_results = bootstrap_results,
  family = "clayton",
  grid_size = 50,
  method = "cdf"
)

if (!is.null(uncertainty_clayton)) {
  cat("  ✓ SUCCESS! Uncertainty calculation worked\n")
  cat("    Point estimate dimensions:", paste(dim(uncertainty_clayton$point_estimate), collapse="x"), "\n")
  cat("    N bootstrap samples used:", uncertainty_clayton$n_bootstrap, "\n\n")
} else {
  cat("  ✗ FAILED! Uncertainty calculation returned NULL\n\n")
}

# Test Frank
cat("Attempting to calculate uncertainty for FRANK...\n")
uncertainty_frank <- calculate_bootstrap_uncertainty(
  bootstrap_results = bootstrap_results,
  family = "frank",
  grid_size = 50,
  method = "cdf"
)

if (!is.null(uncertainty_frank)) {
  cat("  ✓ SUCCESS! Uncertainty calculation worked\n")
  cat("    Point estimate dimensions:", paste(dim(uncertainty_frank$point_estimate), collapse="x"), "\n")
  cat("    N bootstrap samples used:", uncertainty_frank$n_bootstrap, "\n\n")
} else {
  cat("  ✗ FAILED! Uncertainty calculation returned NULL\n\n")
}

# Test Gumbel
cat("Attempting to calculate uncertainty for GUMBEL...\n")
uncertainty_gumbel <- calculate_bootstrap_uncertainty(
  bootstrap_results = bootstrap_results,
  family = "gumbel",
  grid_size = 50,
  method = "cdf"
)

if (!is.null(uncertainty_gumbel)) {
  cat("  ✓ SUCCESS! Uncertainty calculation worked\n")
  cat("    Point estimate dimensions:", paste(dim(uncertainty_gumbel$point_estimate), collapse="x"), "\n")
  cat("    N bootstrap samples used:", uncertainty_gumbel$n_bootstrap, "\n\n")
} else {
  cat("  ✗ FAILED! Uncertainty calculation returned NULL\n\n")
}

################################################################################
### CREATE TEST PLOTS
################################################################################

cat("====================================================================\n")
cat("CREATING TEST PLOTS\n")
cat("====================================================================\n\n")

output_dir <- "quick_test_output"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Empirical grid
cat("Computing empirical copula grid...\n")
empirical_grid_cdf <- calculate_empirical_copula_grid(
  copula_fits$pseudo_obs, 
  grid_size = 50,
  method = "ecdf"
)

# Get sample size for titles
n_pairs <- nrow(pairs_test)

# Plot gaussian
if (!is.null(uncertainty_gaussian)) {
  cat("Creating gaussian ribbon plot...\n")
  p_gaussian <- plot_copula_with_uncertainty_ribbons(
    empirical_grid = empirical_grid_cdf,
    uncertainty_results = uncertainty_gaussian,
    family = "gaussian",
    plot_type = "cdf",
    n_gradient_levels = 5,  # Fewer for speed
    sample_size = n_pairs
  )
  
  export_ggplot_multi_format(
    plot_obj = p_gaussian,
    base_filename = file.path(output_dir, "gaussian_test"),
    width = 7, height = 7,  # No legend (square for coord_equal)
    formats = EXPORT_FORMATS,
    dpi = EXPORT_DPI,
    verbose = EXPORT_VERBOSE
  )
  cat("  ✓ Saved: quick_test_output/gaussian_test (multi-format)\n\n")
}

# Plot t
if (!is.null(uncertainty_t)) {
  cat("Creating t-copula ribbon plot...\n")
  p_t <- plot_copula_with_uncertainty_ribbons(
    empirical_grid = empirical_grid_cdf,
    uncertainty_results = uncertainty_t,
    family = "t",
    plot_type = "cdf",
    n_gradient_levels = 5,
    sample_size = n_pairs
  )
  
  export_ggplot_multi_format(
    plot_obj = p_t,
    base_filename = file.path(output_dir, "t_test"),
    width = 7, height = 7,  # No legend (square for coord_equal)
    formats = EXPORT_FORMATS,
    dpi = EXPORT_DPI,
    verbose = EXPORT_VERBOSE
  )
  cat("  ✓ Saved: quick_test_output/t_test (multi-format)\n\n")
}

# Plot Clayton
if (!is.null(uncertainty_clayton)) {
  cat("Creating Clayton copula ribbon plot...\n")
  p_clayton <- plot_copula_with_uncertainty_ribbons(
    empirical_grid = empirical_grid_cdf,
    uncertainty_results = uncertainty_clayton,
    family = "clayton",
    plot_type = "cdf",
    n_gradient_levels = 5,
    sample_size = n_pairs
  )
  
  export_ggplot_multi_format(
    plot_obj = p_clayton,
    base_filename = file.path(output_dir, "clayton_test"),
    width = 7, height = 7,  # No legend (square for coord_equal)
    formats = EXPORT_FORMATS,
    dpi = EXPORT_DPI,
    verbose = EXPORT_VERBOSE
  )
  cat("  ✓ Saved: quick_test_output/clayton_test (multi-format)\n\n")
}

# Plot Frank
if (!is.null(uncertainty_frank)) {
  cat("Creating Frank copula ribbon plot...\n")
  p_frank <- plot_copula_with_uncertainty_ribbons(
    empirical_grid = empirical_grid_cdf,
    uncertainty_results = uncertainty_frank,
    family = "frank",
    plot_type = "cdf",
    n_gradient_levels = 5,
    sample_size = n_pairs
  )
  
  export_ggplot_multi_format(
    plot_obj = p_frank,
    base_filename = file.path(output_dir, "frank_test"),
    width = 7, height = 7,  # No legend (square for coord_equal)
    formats = EXPORT_FORMATS,
    dpi = EXPORT_DPI,
    verbose = EXPORT_VERBOSE
  )
  cat("  ✓ Saved: quick_test_output/frank_test (multi-format)\n\n")
}

# Plot Gumbel
if (!is.null(uncertainty_gumbel)) {
  cat("Creating Gumbel copula ribbon plot...\n")
  p_gumbel <- plot_copula_with_uncertainty_ribbons(
    empirical_grid = empirical_grid_cdf,
    uncertainty_results = uncertainty_gumbel,
    family = "gumbel",
    plot_type = "cdf",
    n_gradient_levels = 5,
    sample_size = n_pairs
  )
  
  export_ggplot_multi_format(
    plot_obj = p_gumbel,
    base_filename = file.path(output_dir, "gumbel_test"),
    width = 7, height = 7,  # No legend (square for coord_equal)
    formats = EXPORT_FORMATS,
    dpi = EXPORT_DPI,
    verbose = EXPORT_VERBOSE
  )
  cat("  ✓ Saved: quick_test_output/gumbel_test (multi-format)\n\n")
}

# Plot Comonotonic (no uncertainty - special handling)
cat("Creating Comonotonic copula plot (no uncertainty ribbons)...\n")
p_comonotonic <- plot_parametric_copula_contour(
  fitted_copula = NULL,
  family = "comonotonic",
  plot_type = "cdf",
  title = "Comonotonic Copula (No Bootstrap)",
  sample_size = n_pairs
)

export_ggplot_multi_format(
  plot_obj = p_comonotonic,
  base_filename = file.path(output_dir, "comonotonic_test"),
  width = 7, height = 7,  # No legend (square for coord_equal)
  formats = EXPORT_FORMATS,
  dpi = EXPORT_DPI,
  verbose = EXPORT_VERBOSE
)
cat("  ✓ Saved: quick_test_output/comonotonic_test (multi-format)\n\n")

################################################################################
### SUMMARY
################################################################################

cat("====================================================================\n")
cat("QUICK TEST COMPLETE\n")
cat("====================================================================\n\n")

# Count successful tests
n_tests <- 0
n_success <- 0

families_tested <- c("gaussian", "t", "clayton", "frank", "gumbel")
for (fam in families_tested) {
  n_tests <- n_tests + 1
  unc_var <- get(paste0("uncertainty_", fam))
  if (!is.null(unc_var)) {
    n_success <- n_success + 1
  }
}

if (n_success == n_tests) {
  cat("✓✓✓ ALL TESTS PASSED! ✓✓✓\n\n")
  cat("The uncertainty ribbon visualization is working correctly.\n")
  cat("Check the test plots in: quick_test_output/\n\n")
  cat("You should see:\n")
  cat("  - Zissou1 background colors (parametric CDF)\n")
  cat("  - Grey gradient ribbons around contours (uncertainty)\n")
  cat("  - Magenta empirical contour lines overlaid\n")
  cat("  - Black dotted parametric contours\n\n")
  cat("Plots created:\n")
  cat("  • gaussian_test.pdf\n")
  cat("  • t_test.pdf\n")
  cat("  • clayton_test.pdf\n")
  cat("  • frank_test.pdf\n")
  cat("  • gumbel_test.pdf\n")
  cat("  • comonotonic_test.pdf (no uncertainty ribbons)\n\n")
  cat("Ready to run the full analysis:\n")
  cat("  source('STEP_1_Family_Selection/test_contour_plots.R')\n\n")
} else {
  cat(sprintf("✗✗✗ PARTIAL SUCCESS: %d/%d tests passed ✗✗✗\n\n", n_success, n_tests))
  cat("Some uncertainty calculations returned NULL.\n")
  cat("Check the error messages above.\n\n")
}
