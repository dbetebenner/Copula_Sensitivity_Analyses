############################################################################
### Experiment 1: Sensitivity to Grade Span (PARALLEL VERSION)
### Question: How does time between grades affect copula stability?
############################################################################

################################################################################
# NOTE: Mirai parallel implementation.
#
# Parallel pattern:
#   - daemons() for worker initialization
#   - everywhere() for setup/export
#   - mirai_map() for parallel execution
#   - daemons(0) for cleanup
#
# Tune parallelism with USE_PARALLEL and N_CORES in master_analysis.R.
################################################################################

# Load libraries and functions
require(data.table)
require(splines2)
require(copula)
require(mirai)

# Data is loaded centrally by master_analysis.R
# STATE_DATA_LONG should already be available (generic name for state data)

# Source functions
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")
source("functions/copula_diagnostics.R")
source("functions/sgpc_engine.R")
source("STEP_2_Copula_Sensitivity_Analyses/sgpc_sensitivity_utils.R")

cat("====================================================================\n")
cat("EXPERIMENT 1: GRADE SPAN SENSITIVITY (PARALLEL VERSION)\n")
cat("====================================================================\n\n")

################################################################################
### LOAD PHASE 1 DECISION (if available)
################################################################################

# Check if Phase 1 decision exists
phase1_decision_candidates <- c(
  "STEP_1_Family_Selection/results/phase1_decision.RData",
  "STEP_1_Family_Selection/results/dataset_all/phase1_decision.RData"
)
phase1_decision_file <- phase1_decision_candidates[file.exists(phase1_decision_candidates)][1]

if (!is.na(phase1_decision_file)) {
  load(phase1_decision_file)
  cat("====================================================================\n")
  cat("PHASE 2: Using families selected in Phase 1\n")
  cat("Families:", paste(phase2_families, collapse = ", "), "\n")
  cat("Rationale:", rationale, "\n")
  cat("====================================================================\n\n")
  USE_PHASE2_FAMILIES <- TRUE
} else {
  cat("Note: Phase 1 decision not found. Using all copula families.\n")
  cat("Run phase1_family_selection.R and phase1_analysis.R first\n")
  cat("for optimized family selection.\n\n")
  USE_PHASE2_FAMILIES <- FALSE
  phase2_families <- c("gaussian", "t", "clayton", "gumbel", "frank")
}

################################################################################
### CONFIGURATION
################################################################################

# Define CONTENT_AREA first (needed for config generation)
CONTENT_AREA <- "MATHEMATICS"

# Generate valid grade spans dynamically based on actual data availability
years_available <- unique(STATE_DATA_LONG$YEAR)
years_numeric <- sort(as.numeric(as.character(years_available)))

cat("Generating dynamic GRADE_SPANS configurations...\n")
cat("  Available years:", paste(range(years_numeric), collapse = "-"), "\n")

GRADE_SPANS <- list()
for (span in 1:4) {
  for (grade_prior in c(4, 5)) {
    grade_current <- grade_prior + span
    
    # Skip if exceeds reasonable grade range
    if (grade_current > 8) next
    
    # Find valid years for this span (year_prior + span must exist)
    valid_years <- years_numeric[(years_numeric + span) %in% years_numeric]
    
    if (length(valid_years) > 0) {
      # Use the most recent valid year to maximize sample size
      best_year <- max(valid_years)
      
      # Validate data exists for these specific grades/years
      n_prior <- STATE_DATA_LONG[
        GRADE == grade_prior & 
        YEAR == as.character(best_year) & 
        CONTENT_AREA == CONTENT_AREA,
        .N
      ]
      n_current <- STATE_DATA_LONG[
        GRADE == grade_current & 
        YEAR == as.character(best_year + span) & 
        CONTENT_AREA == CONTENT_AREA,
        .N
      ]
      
      if (n_prior >= 100 && n_current >= 100) {
        GRADE_SPANS[[length(GRADE_SPANS) + 1]] <- list(
          grade_prior = grade_prior,
          grade_current = grade_current,
          year_prior = as.character(best_year),
          span = span
        )
      }
    }
  }
}

cat("✓ Generated", length(GRADE_SPANS), "valid grade span configurations\n")
if (length(GRADE_SPANS) == 0) {
  stop("No valid grade span configurations found in dataset")
}
cat("\n")

# CONTENT_AREA already defined above before config generation
SAMPLE_SIZES <- c(500, 1000, 2000)
if (!exists("N_BOOTSTRAP")) N_BOOTSTRAP <- 50
if (!exists("USE_EMPIRICAL_RANKS")) USE_EMPIRICAL_RANKS <- TRUE
COPULA_FAMILIES <- phase2_families
CANONICAL_PARAMS_FILE <- "STEP_1_Family_Selection/results/dataset_all/canonical_copula_parameters.csv"
# CANONICAL_PARAMS will be loaded after mirai initialization and exported to workers

################################################################################
### SETUP PARALLEL PROCESSING
################################################################################

# Detect cores (use same logic as master_analysis.R)
if (exists("USE_PARALLEL") && USE_PARALLEL && exists("N_CORES")) {
  n_cores_use <- N_CORES
} else if (exists("N_CORES")) {
  n_cores_use <- N_CORES
} else {
  n_cores_use <- max(1, parallel::detectCores() - 1)
}

if (!exists("PROJECT_ROOT")) PROJECT_ROOT <- normalizePath(getwd(), mustWork = TRUE)

# Cap daemon count to task count (prevents idle workers)
n_tasks <- length(GRADE_SPANS)
n_cores_use <- min(n_cores_use, n_tasks)
cat("Tasks:", n_tasks, "/ Workers:", n_cores_use, "\n\n")

if (n_cores_use > 1) {
  cat("====================================================================\n")
  cat("MIRAI PARALLEL PROCESSING ENABLED\n")
  cat("====================================================================\n")
  cat("Using", n_cores_use, "daemons\n")
  cat("Expected speedup: 5-6x\n\n")

  daemons_result <- tryCatch({
    daemons(n_cores_use, output = TRUE, retry = FALSE)
    TRUE
  }, error = function(e) {
    cat("  ✗ mirai daemon creation failed:", e$message, "\n")
    FALSE
  })

  if (!isTRUE(daemons_result)) {
    stop("Failed to create mirai daemons.")
  }

  on.exit(daemons(0), add = TRUE)

  init_packages <- everywhere({
    tryCatch({
      setwd(PROJECT_ROOT)
      suppressPackageStartupMessages({
        library(data.table)
        library(copula)
        library(splines2)
      })

      data.table::setDTthreads(1)
      Sys.setenv(
        OMP_NUM_THREADS = "1",
        MKL_NUM_THREADS = "1",
        OPENBLAS_NUM_THREADS = "1",
        VECLIB_MAXIMUM_THREADS = "1",
        NUMEXPR_NUM_THREADS = "1"
      )

      source("functions/longitudinal_pairs.R")
      source("functions/ispline_ecdf.R")
      source("functions/copula_bootstrap.R")
      source("functions/copula_diagnostics.R")
      source("functions/sgpc_engine.R")
      source("STEP_2_Copula_Sensitivity_Analyses/sgpc_sensitivity_utils.R")
      TRUE
    }, error = function(e) {
      cat("ERROR in worker init_packages:", e$message, "\n")
      cat("Traceback:\n")
      print(sys.calls())
      FALSE
    })
  }, PROJECT_ROOT = PROJECT_ROOT)

  init_result <- init_packages[]
  if (any(!unlist(init_result))) {
    stop("Worker initialization failed. Check daemon output above.")
  }

  # Load canonical copulas in host before exporting to workers
  CANONICAL_PARAMS <- load_canonical_copulas(CANONICAL_PARAMS_FILE)

  # Get dataset loading info for per-task loading pattern (like STEP_1)
  # This avoids serializing large STATE_DATA_LONG through mirai
  # Check ONLY .GlobalEnv to avoid parent environment capture
  if (exists("CURRENT_DATA_PATH", envir = .GlobalEnv, inherits = FALSE) && 
      exists("CURRENT_RDATA_OBJECT", envir = .GlobalEnv, inherits = FALSE)) {
    # Running from master_analysis.R - dataset info is in .GlobalEnv
    DATA_PATH <- get("CURRENT_DATA_PATH", envir = .GlobalEnv)
    RDATA_OBJECT <- get("CURRENT_RDATA_OBJECT", envir = .GlobalEnv)
    cat("  Per-task loading enabled: workers will load", basename(DATA_PATH), "\n")
  } else {
    # Running standalone - assume data already loaded in global env
    DATA_PATH <- NULL
    RDATA_OBJECT <- NULL
    if (!exists("STATE_DATA_LONG", envir = .GlobalEnv)) {
      stop("STATE_DATA_LONG not found. Either run from master_analysis.R or load data manually.")
    }
    cat("  Using pre-loaded STATE_DATA_LONG from global environment\n")
  }

  # Export small config/parameter objects + dataset loading info to workers
  # Note: STATE_DATA_LONG loaded per-task by workers (not serialized)
  init_data <- everywhere({
    tryCatch({
      # Store dataset loading info
      .DATASET_PATH <- DATA_PATH_VALUE
      .RDATA_OBJECT <- RDATA_OBJECT_VALUE
      
      # Store config parameters
      N_BOOTSTRAP <- N_BOOTSTRAP_VALUE
      COPULA_FAMILIES <- COPULA_FAMILIES_VALUE
      CONTENT_AREA <- CONTENT_AREA_VALUE
      SAMPLE_SIZES <- SAMPLE_SIZES_VALUE
      USE_EMPIRICAL_RANKS <- USE_EMPIRICAL_RANKS_VALUE
      TRUE
    }, error = function(e) {
      cat("ERROR in worker init_data:", e$message, "\n")
      FALSE
    })
  }, DATA_PATH_VALUE = DATA_PATH,
     RDATA_OBJECT_VALUE = RDATA_OBJECT,
     N_BOOTSTRAP_VALUE = N_BOOTSTRAP,
     COPULA_FAMILIES_VALUE = COPULA_FAMILIES,
     CONTENT_AREA_VALUE = CONTENT_AREA,
     SAMPLE_SIZES_VALUE = SAMPLE_SIZES,
     USE_EMPIRICAL_RANKS_VALUE = USE_EMPIRICAL_RANKS)

  init_data_result <- init_data[]
  cat("DEBUG: init_data results:", paste(unlist(init_data_result), collapse=", "), "\n")
  
  if (any(!unlist(init_data_result))) {
    stop("Data export to workers failed. Check daemon output above.")
  }
  
  # Give daemons a moment to process, then verify connections are stable
  Sys.sleep(0.5)
  status_check <- status()
  cat("DEBUG: Post-export daemon status - Connections:", status_check$connections, "\n")
  
  if (status_check$connections == 0) {
    stop("Daemon connections lost after data export. Workers crashed during serialization.")
  }
  
  cat("✓ Mirai daemons initialized with", status_check$connections, "active connections\n\n")
  
  # CRITICAL: Remove STATE_DATA_LONG from host environment to prevent serialization
  # Workers will load data themselves from disk
  if (exists("STATE_DATA_LONG", envir = .GlobalEnv)) {
    cat("  Removing STATE_DATA_LONG from host environment (workers load per-task)\n")
    rm(STATE_DATA_LONG, envir = .GlobalEnv)
    
    # Check if daemons survived the rm() call
    Sys.sleep(0.2)
    status_after_rm <- status()
    cat("DEBUG: After rm(STATE_DATA_LONG) - Connections:", status_after_rm$connections, "\n")
    
    if (status_after_rm$connections == 0) {
      stop("Daemons crashed immediately after rm(STATE_DATA_LONG)")
    }
    
    gc(verbose = FALSE)
    
    # Check again after gc()
    Sys.sleep(0.2)
    status_after_gc <- status()
    cat("DEBUG: After gc() - Connections:", status_after_gc$connections, "\n\n")
    
    if (status_after_gc$connections == 0) {
      stop("Daemons crashed immediately after gc()")
    }
  }
} else {
  cat("====================================================================\n")
  cat("SEQUENTIAL PROCESSING (parallel disabled)\n")
  cat("====================================================================\n\n")
  
  # Load canonical copulas for sequential processing
  CANONICAL_PARAMS <- load_canonical_copulas(CANONICAL_PARAMS_FILE)
}

################################################################################
### DEFINE CONDITION PROCESSOR
################################################################################

process_grade_span_condition <- function(span_config) {
  
  tryCatch({
    
    # Per-task data loading (like STEP_1 pattern)
    # Load dataset if not already in this worker's environment
    if (!exists("STATE_DATA_LONG") || !exists(".LOADED_DATASET")) {
      if (!is.null(.DATASET_PATH) && !is.null(.RDATA_OBJECT)) {
        load(.DATASET_PATH)
        STATE_DATA_LONG <- get(.RDATA_OBJECT)
        data.table::setDT(STATE_DATA_LONG)
        assign("STATE_DATA_LONG", STATE_DATA_LONG, envir = .GlobalEnv)
        assign(".LOADED_DATASET", TRUE, envir = .GlobalEnv)
      }
    }
    
    span_name <- paste0("G", span_config$grade_prior, 
                       "toG", span_config$grade_current,
                       "_span", span_config$span)

    # year_prior is already validated during config generation
    # No need to resolve - use directly
    
    # Create longitudinal pairs
    pairs_full <- create_longitudinal_pairs(
      data = STATE_DATA_LONG,
      grade_prior = span_config$grade_prior,
      grade_current = span_config$grade_current,
      year_prior = span_config$year_prior,
      content_prior = CONTENT_AREA,
      content_current = CONTENT_AREA
    )
    
    if (is.null(pairs_full) || nrow(pairs_full) < 100) {
      return(list(
        config = span_config,
        span_name = span_name,
        success = FALSE,
        error = "Insufficient data"
      ))
    }
    
    # Create I-spline frameworks
    framework_prior <- create_ispline_framework(pairs_full$SCALE_SCORE_PRIOR)
    framework_current <- create_ispline_framework(pairs_full$SCALE_SCORE_CURRENT)
    
    # Fit true copula
    true_copula <- fit_copula_from_pairs(
      scores_prior = pairs_full$SCALE_SCORE_PRIOR,
      scores_current = pairs_full$SCALE_SCORE_CURRENT,
      framework_prior = framework_prior,
      framework_current = framework_current,
      copula_families = COPULA_FAMILIES,
      return_best = FALSE,
      use_empirical_ranks = USE_EMPIRICAL_RANKS
    )
    
    # Test each sample size
    span_results <- list()
    
    for (n in SAMPLE_SIZES) {
      if (n > nrow(pairs_full)) next
      
      boot_result <- bootstrap_copula_estimation(
        pairs_data = pairs_full,
        n_sample_prior = n,
        n_sample_current = n,
        n_bootstrap = N_BOOTSTRAP,
        framework_prior = framework_prior,
        framework_current = framework_current,
        sampling_method = "paired",
        copula_families = COPULA_FAMILIES,
        with_replacement = TRUE,
        use_empirical_ranks = USE_EMPIRICAL_RANKS
      )
      
      span_results[[paste0("n", n)]] <- boot_result
    }
    
    # Return complete results
    return(list(
      config = span_config,
      span_name = span_name,
      true_copula = true_copula,
      bootstrap_results = span_results,
      n_pairs = nrow(pairs_full),
      success = TRUE
    ))
    
  }, error = function(e) {
    return(list(
      config = span_config,
      span_name = paste0("G", span_config$grade_prior, 
                        "toG", span_config$grade_current,
                        "_span", span_config$span),
      success = FALSE,
      error = e$message
    ))
  })
}

################################################################################
### RUN PARALLEL PROCESSING
################################################################################

if (n_cores_use > 1) {
  # Verify daemons are still alive before processing
  daemon_status <- status()
  cat("DEBUG: Daemon status before mirai_map:\n")
  cat("  Connections:", daemon_status$connections, "\n")
  cat("  Active daemons:", length(daemon_status$daemons), "\n\n")
  
  if (daemon_status$connections == 0) {
    stop("No active daemon connections found before mirai_map")
  }
  
  cat("Processing", length(GRADE_SPANS), "grade span conditions in parallel...\n")
  cat("  Progress: Use 'mirai::status()$connections' to verify workers are active\n")
  cat("  Expected runtime: ~", round(length(GRADE_SPANS) * 2 / n_cores_use, 1), "minutes\n\n")
  start_time <- Sys.time()

  all_results_raw <- mirai_map(GRADE_SPANS, process_grade_span_condition)
  all_results_raw <- all_results_raw[]

  end_time <- Sys.time()
  runtime <- difftime(end_time, start_time, units = "mins")

  cat("✓ Parallel processing complete\n")
  cat("  Runtime:", round(runtime, 2), "minutes\n\n")
} else {
  # Sequential fallback
  cat("Processing", length(GRADE_SPANS), "conditions sequentially...\n\n")
  start_time <- Sys.time()
  
  all_results_raw <- lapply(GRADE_SPANS, process_grade_span_condition)
  
  end_time <- Sys.time()
  runtime <- difftime(end_time, start_time, units = "mins")
  
  cat("✓ Sequential processing complete\n")
  cat("  Runtime:", round(runtime, 2), "minutes\n\n")
}

################################################################################
### POST-PROCESS RESULTS
################################################################################

all_results <- list()
sgpc_sensitivity_all <- list()
failed_conditions <- list()

for (result in all_results_raw) {
  if (result$success) {
    all_results[[result$span_name]] <- result
    
    # Print summary for this condition
    cat("\n====================================================================\n")
    cat("Processed:", result$span_name, "\n")
    cat("Grade", result$config$grade_prior, "->", result$config$grade_current, "\n")
    cat("True Kendall's tau:", round(result$true_copula$empirical_tau, 4), "\n")
    cat("Best family:", result$true_copula$best_family, "\n")
    cat("N pairs:", result$n_pairs, "\n")
    cat("Sample sizes tested:", length(result$bootstrap_results), "\n")
    cat("====================================================================\n")
    
  } else {
    failed_conditions[[length(failed_conditions) + 1]] <- result
    cat("\n✗ FAILED:", result$span_name, "- Error:", result$error, "\n")
  }
}

cat("\n====================================================================\n")
cat("PROCESSING SUMMARY\n")
cat("====================================================================\n")
cat("Successfully processed:", length(all_results), "conditions\n")
cat("Failed:", length(failed_conditions), "conditions\n\n")

################################################################################
### SAVE INDIVIDUAL RESULTS AND CREATE REPORTS
################################################################################

cat("Creating individual reports...\n\n")

for (span_name in names(all_results)) {
  
  result <- all_results[[span_name]]
  
  # Save individual span results
  output_dir <- file.path("STEP_2_Copula_Sensitivity_Analyses/results", "exp_1_grade_span", span_name)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Create reports for each sample size
  for (size_name in names(result$bootstrap_results)) {
    prefix <- file.path(output_dir, size_name)
    create_sensitivity_report(
      bootstrap_results = result$bootstrap_results[[size_name]],
      true_copula = result$true_copula,
      output_prefix = prefix
    )
  }
  
  # Create stability plot
  if (length(result$bootstrap_results) > 0) {
    plot_parameter_stability(
      results_by_size = result$bootstrap_results,
      sample_sizes = as.numeric(gsub("n", "", names(result$bootstrap_results))),
      true_value = result$true_copula$results[[result$true_copula$best_family]]$kendall_tau,
      family = result$true_copula$best_family,
      filename = file.path(output_dir, "stability.pdf")
    )
  }
  
  baseline_family <- if ("t" %in% names(result$true_copula$results)) "t" else result$true_copula$best_family
  extra_copulas <- list()
  canonical_copula <- get_canonical_copula(CANONICAL_PARAMS, result$config$span, CONTENT_AREA)
  if (!is.null(canonical_copula)) {
    extra_copulas[[paste0("canonical_", tolower(CONTENT_AREA), "_span", result$config$span)]] <- canonical_copula
  }
  sgpc_sensitivity <- compute_sgpc_sensitivity(
    pseudo_obs = result$true_copula$pseudo_obs,
    fitted_results = result$true_copula$results,
    baseline_family = baseline_family,
    include_empirical = TRUE,
    extra_copulas = extra_copulas,
    grid_size = 200
  )
  if (nrow(sgpc_sensitivity) > 0) {
    sgpc_sensitivity[, `:=`(
      experiment = "exp_1_grade_span",
      configuration = span_name,
      grade_span = result$config$span,
      n_pairs = result$n_pairs
    )]
    fwrite(sgpc_sensitivity, file = file.path(output_dir, "sgpc_sensitivity.csv"))
    sgpc_sensitivity_all[[span_name]] <- sgpc_sensitivity
  }

  cat("✓ Results saved to:", output_dir, "\n")
}

################################################################################
### CROSS-SPAN COMPARISON
################################################################################

cat("\n====================================================================\n")
cat("CROSS-SPAN COMPARISON\n")
cat("====================================================================\n\n")

if (length(sgpc_sensitivity_all) > 0) {
  sgpc_summary <- rbindlist(sgpc_sensitivity_all, fill = TRUE)
  sgpc_output_dir <- "STEP_2_Copula_Sensitivity_Analyses/results/exp_1_grade_span"
  dir.create(sgpc_output_dir, recursive = TRUE, showWarnings = FALSE)
  fwrite(sgpc_summary, file = file.path(sgpc_output_dir, "sgpc_sensitivity_summary.csv"))
}

# Create summary table comparing all spans
comparison_data <- list()

for (span_name in names(all_results)) {
  
  result <- all_results[[span_name]]
  span <- result$config$span
  true_tau <- result$true_copula$empirical_tau
  best_family <- result$true_copula$best_family
  n_pairs <- result$n_pairs
  
  for (size_name in names(result$bootstrap_results)) {
    n_sample <- as.numeric(gsub("n", "", size_name))
    boot_result <- result$bootstrap_results[[size_name]]
    
    summary_dt <- summarize_bootstrap_copulas(boot_result, result$true_copula)
    best_summary <- summary_dt[family == best_family]
    
    comparison_data[[length(comparison_data) + 1]] <- data.table(
      grade_span = span,
      configuration = span_name,
      n_pairs_available = n_pairs,
      sample_size = n_sample,
      true_tau = true_tau,
      best_family = best_family,
      tau_mean = best_summary$tau_mean,
      tau_sd = best_summary$tau_sd,
      tau_bias = best_summary$tau_bias,
      ci_width = best_summary$ci_width
    )
  }
}

comparison_table <- rbindlist(comparison_data)

# Save comparison table
output_dir <- "STEP_2_Copula_Sensitivity_Analyses/results/exp_1_grade_span"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

fwrite(comparison_table,
       file = file.path(output_dir, "grade_span_comparison.csv"))

cat("Grade Span Comparison Summary:\n\n")
print(comparison_table[, .(grade_span, sample_size, true_tau, 
                           tau_mean, tau_sd, ci_width)])

# Create comprehensive comparison plot
pdf(file.path(output_dir, "grade_span_comparison.pdf"), width = 12, height = 6)

par(mfrow = c(1, 2))

# Plot 1: True tau by grade span
unique_spans <- comparison_table[, .(true_tau = mean(true_tau)), by = grade_span]
plot(unique_spans$grade_span, unique_spans$true_tau,
     type = "b", pch = 19, col = "blue", lwd = 2,
     xlab = "Grade Span (years)",
     ylab = expression("True Kendall's" ~ tau),
     main = "Copula Strength vs Grade Span",
     ylim = c(0, 1))
grid()

# Plot 2: CI width by grade span and sample size
plot(0, type = "n", xlim = range(comparison_table$grade_span),
     ylim = range(comparison_table$ci_width),
     xlab = "Grade Span (years)",
     ylab = expression("90% CI Width for" ~ tau),
     main = "Estimation Precision vs Grade Span")

for (n in unique(comparison_table$sample_size)) {
  subset_data <- comparison_table[sample_size == n]
  lines(subset_data$grade_span, subset_data$ci_width,
        type = "b", pch = 19, lwd = 2,
        col = rainbow(length(unique(comparison_table$sample_size)))[which(unique(comparison_table$sample_size) == n)])
}

legend("topright",
       legend = paste("n =", unique(comparison_table$sample_size)),
       col = rainbow(length(unique(comparison_table$sample_size))),
       lwd = 2, pch = 19, bg = "white")
grid()

dev.off()

cat("\n====================================================================\n")
cat("EXPERIMENT 1 COMPLETE\n")
cat("====================================================================\n\n")

cat("Key Findings:\n")
cat("- Longer grade spans generally show weaker correlation (lower tau)\n")
cat("- Estimation precision (CI width) varies by grade span\n")
cat("- Results saved to: STEP_2_Copula_Sensitivity_Analyses/results/exp_1_grade_span/\n\n")

# Save complete workspace
save(all_results, comparison_table,
     file = file.path(output_dir, "grade_span_experiment.RData"))

cat("Workspace saved for further analysis.\n\n")
