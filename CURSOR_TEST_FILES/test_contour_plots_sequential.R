############################################################################
### DIAGNOSTIC TEST: Sequential Bootstrap (Mimics master_analysis.R)
############################################################################
### Purpose: Identify performance bottlenecks in the sequential bootstrap
###          execution pattern used by master_analysis.R parallel workers
###
### Key difference from test_contour_plots.R:
###   - Bootstrap runs SEQUENTIALLY (use_parallel = FALSE, n_cores = 1)
###   - This matches how each worker in phase1_family_selection_parallel.R
###     processes its assigned condition
###
### Usage: Run from project root or CURSOR_TEST_FILES directory
###        source("CURSOR_TEST_FILES/test_contour_plots_sequential.R")
############################################################################

cat("\n")
cat("====================================================================\n")
cat("DIAGNOSTIC: Sequential Bootstrap Performance Test\n")
cat("====================================================================\n")
cat("This script mimics the execution pattern of master_analysis.R workers\n")
cat("to identify where time is being spent during copula analysis.\n")
cat("====================================================================\n")
cat("\n")

############################################################################
### TIMING INFRASTRUCTURE
############################################################################

# Store timing results
timing_results <- list()

# Helper function to record timing
record_time <- function(step_name, start_time, extra_info = NULL) {
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  timing_results[[step_name]] <<- list(
    elapsed_secs = elapsed,
    elapsed_min = elapsed / 60,
    extra_info = extra_info
  )
  cat(sprintf(
    "  [TIMING] %s: %.1f seconds (%.2f min)\n",
    step_name,
    elapsed,
    elapsed / 60
  ))
  if (!is.null(extra_info)) {
    cat(sprintf("           %s\n", extra_info))
  }
  invisible(elapsed)
}

# Overall start time
overall_start <- Sys.time()

############################################################################
### STEP 1: SETUP
############################################################################

cat("\n=== STEP 1: Setup ===\n")
step1_start <- Sys.time()

require(data.table)
require(copula)
require(splines2)
require(ggplot2)
require(viridis)
require(gridExtra)

# Determine project root
if (
  file.exists("functions/copula_contour_plots.R") &&
    file.exists("dataset_configs.R")
) {
  PROJECT_ROOT <- getwd()
  func_prefix <- ""
} else if (
  file.exists("../functions/copula_contour_plots.R") &&
    file.exists("../dataset_configs.R")
) {
  PROJECT_ROOT <- normalizePath("..")
  func_prefix <- "../"
} else {
  stop(
    "Cannot locate project root. Run from project root or CURSOR_TEST_FILES/"
  )
}

cat("Project root:", PROJECT_ROOT, "\n")

# Source functions
source(paste0(func_prefix, "functions/longitudinal_pairs.R"))
source(paste0(func_prefix, "functions/ispline_ecdf.R"))
source(paste0(func_prefix, "functions/copula_bootstrap.R"))
source(paste0(func_prefix, "functions/sgpc_engine.R"))
source(paste0(func_prefix, "functions/copula_contour_plots.R"))
source(paste0(func_prefix, "dataset_configs.R"))

# Load local config if available
local_config <- paste0(func_prefix, "dataset_configs_local.R")
if (file.exists(local_config)) {
  source(local_config)
}

record_time("Step 1 - Setup", step1_start)

############################################################################
### STEP 2: LOAD DATASET 4 AND CREATE PAIRS
############################################################################

cat("\n=== STEP 2: Data Preparation (Dataset 4) ===\n")
step2_start <- Sys.time()

# Use dataset_4 (smaller state with COVID gap)
DATASET_TO_TEST <- "dataset_4"
current_dataset <- DATASETS[[DATASET_TO_TEST]]

cat("Dataset:", current_dataset$name, "\n")
cat("  Description:", current_dataset$description, "\n")
cat(
  "  Years available:",
  paste(current_dataset$years_available, collapse = ", "),
  "\n"
)
cat(
  "  Grades available:",
  paste(current_dataset$grades_available, collapse = ", "),
  "\n"
)
cat(
  "  Content areas:",
  paste(current_dataset$content_areas, collapse = ", "),
  "\n\n"
)

# Load data
data_loading_start <- Sys.time()

# Prefer SGP data file if available
sgp_data_path <- paste0(func_prefix, current_dataset$local_path_sgp)
base_data_path <- paste0(func_prefix, current_dataset$local_path)

if (!is.null(current_dataset$local_path_sgp) && file.exists(sgp_data_path)) {
  cat("Loading SGP data file...\n")
  load(sgp_data_path)
  STATE_DATA_LONG <- get(current_dataset$rdata_object_name_sgp)
  cat("  Loaded:", current_dataset$rdata_object_name_sgp, "\n")
} else if (file.exists(base_data_path)) {
  cat("Loading base data file...\n")
  load(base_data_path)
  STATE_DATA_LONG <- get(current_dataset$rdata_object_name)
  cat("  Loaded:", current_dataset$rdata_object_name, "\n")
} else {
  stop("Data file not found at: ", base_data_path)
}

cat("  Total rows:", format(nrow(STATE_DATA_LONG), big.mark = ","), "\n")
data_loading_elapsed <- as.numeric(difftime(
  Sys.time(),
  data_loading_start,
  units = "secs"
))
cat(sprintf("  Data loading: %.1f seconds\n", data_loading_elapsed))

# Define test condition: Post-COVID, 1-year span
# Using 2021->2022 to test post-pandemic period
test_condition <- list(
  grade_prior = 3,
  grade_current = 4,
  year_prior = "2021",
  year_current = "2022",
  year_span = 1,
  content = "MATHEMATICS",
  dataset_id = current_dataset$id,
  dataset_name = current_dataset$name,
  anonymized_state = current_dataset$anonymized_state
)

cat("\nTest Condition:\n")
cat(
  "  Grade:",
  test_condition$grade_prior,
  "->",
  test_condition$grade_current,
  "\n"
)
cat(
  "  Year:",
  test_condition$year_prior,
  "->",
  test_condition$year_current,
  "\n"
)
cat("  Content:", test_condition$content, "\n")

# Create longitudinal pairs
pairs_creation_start <- Sys.time()
pairs_full <- create_longitudinal_pairs(
  data = STATE_DATA_LONG,
  grade_prior = test_condition$grade_prior,
  grade_current = test_condition$grade_current,
  year_prior = test_condition$year_prior,
  content_prior = test_condition$content,
  content_current = test_condition$content
)

if (is.null(pairs_full) || nrow(pairs_full) < 100) {
  stop(
    "Insufficient data for test condition. Got ",
    ifelse(is.null(pairs_full), 0, nrow(pairs_full)),
    " pairs."
  )
}

n_pairs <- nrow(pairs_full)
pairs_creation_elapsed <- as.numeric(difftime(
  Sys.time(),
  pairs_creation_start,
  units = "secs"
))
cat(sprintf("\n  Pairs creation: %.1f seconds\n", pairs_creation_elapsed))
cat("  Number of longitudinal pairs:", format(n_pairs, big.mark = ","), "\n")

# Create I-spline frameworks
framework_start <- Sys.time()
framework_prior <- create_ispline_framework(pairs_full$SCALE_SCORE_PRIOR)
framework_current <- create_ispline_framework(pairs_full$SCALE_SCORE_CURRENT)
framework_elapsed <- as.numeric(difftime(
  Sys.time(),
  framework_start,
  units = "secs"
))
cat(sprintf("  I-spline frameworks: %.1f seconds\n", framework_elapsed))

record_time(
  "Step 2 - Data prep",
  step2_start,
  sprintf("n_pairs = %s", format(n_pairs, big.mark = ","))
)

############################################################################
### STEP 3: COPULA FITTING WITH GOF TESTING
############################################################################

cat("\n=== STEP 3: Copula Fitting + GoF Testing ===\n")
step3_start <- Sys.time()

# Configuration matching master_analysis.R
COPULA_FAMILIES <- c(
  "gaussian",
  "t",
  "clayton",
  "gumbel",
  "frank",
  "comonotonic"
)
N_BOOTSTRAP_GOF <- 100 # Matches master_analysis.R default

cat("Copula families:", paste(COPULA_FAMILIES, collapse = ", "), "\n")
cat("GoF bootstrap samples:", N_BOOTSTRAP_GOF, "\n")
cat(
  "(This is",
  length(COPULA_FAMILIES),
  "families ×",
  N_BOOTSTRAP_GOF,
  "bootstraps =",
  length(COPULA_FAMILIES) * N_BOOTSTRAP_GOF,
  "fits for GoF)\n\n"
)

# Set up output directory
output_dir <- file.path(
  PROJECT_ROOT,
  "STEP_1_Family_Selection/results/test_sequential",
  sprintf(
    "%s_G%d_G%d_%s",
    test_condition$year_prior,
    test_condition$grade_prior,
    test_condition$grade_current,
    test_condition$content
  )
)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
cat("Output directory:", output_dir, "\n\n")

# Fit copulas
cat("Fitting copulas with GoF testing...\n")
copula_fits <- fit_copula_from_pairs(
  scores_prior = pairs_full$SCALE_SCORE_PRIOR,
  scores_current = pairs_full$SCALE_SCORE_CURRENT,
  framework_prior = framework_prior,
  framework_current = framework_current,
  copula_families = COPULA_FAMILIES,
  return_best = FALSE,
  use_empirical_ranks = TRUE, # Phase 1 approach
  n_bootstrap_gof = N_BOOTSTRAP_GOF,
  save_copula_data = TRUE,
  output_dir = output_dir
)

cat("\nCopula fitting results:\n")
cat("  Best family:", copula_fits$best_family, "\n")
cat("  Empirical Kendall's tau:", round(copula_fits$empirical_tau, 3), "\n")

# Display AIC comparison
aic_values <- sapply(copula_fits$results, function(x) {
  if (!is.null(x)) x$aic else NA
})
comparison_df <- data.frame(
  Family = names(aic_values),
  AIC = round(aic_values, 1),
  Delta_AIC = round(aic_values - min(aic_values, na.rm = TRUE), 1)
)
comparison_df <- comparison_df[order(comparison_df$AIC), ]
cat("\nModel comparison:\n")
print(comparison_df)

record_time(
  "Step 3 - Copula + GoF",
  step3_start,
  sprintf("Best family: %s", copula_fits$best_family)
)

############################################################################
### STEP 4: SEQUENTIAL BOOTSTRAP UNCERTAINTY (BOTTLENECK SUSPECT)
############################################################################

cat("\n=== STEP 4: Sequential Bootstrap Uncertainty ===\n")
cat("*** THIS IS THE SUSPECTED BOTTLENECK ***\n")
cat(
  "*** Running SEQUENTIALLY to match master_analysis.R worker pattern ***\n\n"
)
step4_start <- Sys.time()

# Configuration matching master_analysis.R
N_BOOTSTRAP_UNCERTAINTY <- 100
BOOTSTRAP_ALL_FAMILIES <- TRUE

# Exclude comonotonic (deterministic, no parameters)
bootstrap_families <- setdiff(COPULA_FAMILIES, "comonotonic")

cat("Bootstrap configuration:\n")
cat("  use_parallel: FALSE (sequential - matches worker pattern)\n")
cat("  n_cores: 1\n")
cat("  n_bootstrap:", N_BOOTSTRAP_UNCERTAINTY, "\n")
cat("  Families:", paste(bootstrap_families, collapse = ", "), "\n")
cat(
  "  Total copula fits:",
  N_BOOTSTRAP_UNCERTAINTY,
  "×",
  length(bootstrap_families),
  "=",
  N_BOOTSTRAP_UNCERTAINTY * length(bootstrap_families),
  "\n\n"
)

cat("Running sequential bootstrap (this may take a while)...\n")
cat("Progress will be shown below:\n\n")

# Optional: Per-iteration timing for deeper diagnostics
TRACK_PER_ITERATION <- TRUE
iteration_times <- numeric(0)

if (TRACK_PER_ITERATION) {
  cat("(Per-iteration timing enabled for diagnostics)\n\n")
}

bootstrap_results <- tryCatch(
  {
    bootstrap_copula_estimation(
      pairs_data = pairs_full,
      n_sample_prior = nrow(pairs_full),
      n_sample_current = nrow(pairs_full),
      n_bootstrap = N_BOOTSTRAP_UNCERTAINTY,
      framework_prior = framework_prior,
      framework_current = framework_current,
      sampling_method = "paired",
      copula_families = bootstrap_families,
      with_replacement = TRUE,
      use_empirical_ranks = TRUE,
      use_parallel = FALSE, # CRITICAL: Sequential to match worker pattern
      n_cores = 1
    )
  },
  error = function(e) {
    cat("ERROR in bootstrap:", e$message, "\n")
    NULL
  }
)

if (!is.null(bootstrap_results)) {
  cat("\nBootstrap completed successfully!\n")
  cat(
    "  Successful samples:",
    bootstrap_results$n_success,
    "of",
    N_BOOTSTRAP_UNCERTAINTY,
    "\n"
  )
}

record_time(
  "Step 4 - Bootstrap",
  step4_start,
  sprintf(
    "%d samples × %d families = %d fits (SEQUENTIAL)",
    N_BOOTSTRAP_UNCERTAINTY,
    length(bootstrap_families),
    N_BOOTSTRAP_UNCERTAINTY * length(bootstrap_families)
  )
)

############################################################################
### STEP 5: PLOT GENERATION
############################################################################

cat("\n=== STEP 5: Plot Generation ===\n")
step5_start <- Sys.time()

# Prepare condition info
condition_info <- list(
  dataset_id = test_condition$dataset_id,
  dataset_number = gsub("dataset_", "", test_condition$dataset_id),
  year_prior = test_condition$year_prior,
  year_current = test_condition$year_current,
  grade_prior = test_condition$grade_prior,
  grade_current = test_condition$grade_current,
  content = test_condition$content,
  year_span = test_condition$year_span,
  scaling_type = current_dataset$scaling_by_year$scaling_type[1],
  is_cross_content = FALSE
)

# Load empirical copulas if available
empirical_copulas_file <- file.path(output_dir, "empirical_copulas.rds")
empirical_copulas <- NULL
if (file.exists(empirical_copulas_file)) {
  empirical_copulas <- tryCatch(
    readRDS(empirical_copulas_file),
    error = function(e) NULL
  )
}

cat("Generating condition plots...\n")
cat("  Grid size: 300×300\n")
cat("  Export formats: pdf, svg, png\n\n")

EXPORT_FORMATS <- c("pdf", "svg", "png")
EXPORT_DPI <- 300
EXPORT_VERBOSE <- FALSE

plots <- tryCatch(
  {
    generate_condition_plots(
      pseudo_obs = copula_fits$pseudo_obs,
      original_scores = pairs_full[,
        .SD,
        .SDcols = intersect(
          names(pairs_full),
          c("SCALE_SCORE_PRIOR", "SCALE_SCORE_CURRENT", "SGP_ORDER_1", "SGP")
        )
      ],
      copula_results = copula_fits$results,
      best_family = copula_fits$best_family,
      output_dir = output_dir,
      condition_info = condition_info,
      bootstrap_results = bootstrap_results,
      empirical_copulas = empirical_copulas,
      save_plots = TRUE,
      grid_size = 300,
      export_formats = EXPORT_FORMATS,
      export_dpi = EXPORT_DPI,
      export_verbose = EXPORT_VERBOSE
    )
  },
  error = function(e) {
    cat("ERROR in plot generation:", e$message, "\n")
    NULL
  }
)

record_time("Step 5 - Plot gen", step5_start)

############################################################################
### STEP 6: SUMMARY GRID LATEX
############################################################################

cat("\n=== STEP 6: Summary Grid LaTeX ===\n")
step6_start <- Sys.time()

cat("Generating LaTeX summary grid...\n")

latex_result <- tryCatch(
  {
    generate_summary_grid_latex(
      output_dir = output_dir,
      condition_info = condition_info,
      best_family = copula_fits$best_family,
      copula_results = copula_fits$results,
      compile_pdf = TRUE,
      keep_tex = TRUE
    )
  },
  error = function(e) {
    cat("ERROR in LaTeX generation:", e$message, "\n")
    cat(
      "(This may indicate missing LaTeX packages - see earlier diagnostics)\n"
    )
    NULL
  }
)

record_time("Step 6 - LaTeX", step6_start)

############################################################################
### TIMING SUMMARY
############################################################################

overall_elapsed <- as.numeric(difftime(
  Sys.time(),
  overall_start,
  units = "secs"
))

cat("\n")
cat("====================================================================\n")
cat("TIMING SUMMARY\n")
cat("====================================================================\n")
cat("\n")

# Print each step's timing
total_accounted <- 0
for (step_name in names(timing_results)) {
  result <- timing_results[[step_name]]
  pct <- (result$elapsed_secs / overall_elapsed) * 100

  # Format output
  if (result$elapsed_secs > 60) {
    time_str <- sprintf(
      "%8.1f sec (%5.1f min)",
      result$elapsed_secs,
      result$elapsed_min
    )
  } else {
    time_str <- sprintf("%8.1f sec           ", result$elapsed_secs)
  }

  # Mark bottleneck
  bottleneck_marker <- if (pct > 50) " <-- BOTTLENECK" else ""

  cat(sprintf(
    "%-25s %s  [%5.1f%%]%s\n",
    paste0(step_name, ":"),
    time_str,
    pct,
    bottleneck_marker
  ))

  if (!is.null(result$extra_info)) {
    cat(sprintf("%-25s (%s)\n", "", result$extra_info))
  }

  total_accounted <- total_accounted + result$elapsed_secs
}

cat("--------------------------------------------------------------------\n")
cat(sprintf(
  "%-25s %8.1f sec (%5.1f min)\n",
  "TOTAL:",
  overall_elapsed,
  overall_elapsed / 60
))
cat("====================================================================\n")

# Analysis
cat("\n")
cat("ANALYSIS:\n")
cat("---------\n")

# Find bottleneck
bottleneck_step <- names(which.max(sapply(timing_results, function(x) {
  x$elapsed_secs
})))
bottleneck_pct <- (timing_results[[bottleneck_step]]$elapsed_secs /
  overall_elapsed) *
  100

cat(sprintf(
  "Bottleneck: %s (%.1f%% of total time)\n",
  bottleneck_step,
  bottleneck_pct
))
cat(sprintf("Dataset size: %s pairs\n", format(n_pairs, big.mark = ",")))
cat(sprintf(
  "Time per 1000 pairs: %.1f seconds\n",
  overall_elapsed / (n_pairs / 1000)
))

# Project full dataset time
cat("\n")
cat("PROJECTION FOR LARGER DATASETS:\n")
cat("-------------------------------\n")
# Assuming linear scaling (conservative - may be worse for larger n)
for (multiplier in c(5, 10, 20)) {
  projected_pairs <- n_pairs * multiplier
  projected_time_min <- (overall_elapsed * multiplier) / 60
  projected_time_hr <- projected_time_min / 60
  cat(sprintf(
    "  %s pairs: ~%.1f hours\n",
    format(projected_pairs, big.mark = ","),
    projected_time_hr
  ))
}

cat("\n")
cat("OUTPUT LOCATION:\n")
cat(output_dir, "\n")
cat("\n")
cat("====================================================================\n")
cat("Diagnostic test complete.\n")
cat("====================================================================\n")
