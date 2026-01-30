############################################################################
### Experiment 3: Sensitivity to Content Area (PARALLEL VERSION)
### Question: Does dependence structure vary by subject?
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
cat("EXPERIMENT 3: CONTENT AREA SENSITIVITY (PARALLEL VERSION)\n")
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

# Generate valid test configurations dynamically based on actual data availability
years_available <- unique(STATE_DATA_LONG$YEAR)
years_numeric <- sort(as.numeric(as.character(years_available)))
content_areas_available <- unique(STATE_DATA_LONG$CONTENT_AREA)

cat("Generating dynamic TEST_CONFIGS configurations...\n")
cat("  Available years:", paste(range(years_numeric), collapse = "-"), "\n")
cat("  Available content areas:", paste(content_areas_available, collapse = ", "), "\n")

TEST_CONFIGS <- list()

# Standard 4-year span (G4 to G8)
grade_prior <- 4
grade_current <- 8
span <- grade_current - grade_prior

# Find valid years for this span
valid_years <- years_numeric[(years_numeric + span) %in% years_numeric]

if (length(valid_years) > 0) {
  best_year <- max(valid_years)  # Use most recent
  
  # Within-content configurations (same subject prior and current)
  for (content in content_areas_available) {
    n_prior <- STATE_DATA_LONG[
      GRADE == grade_prior & 
      YEAR == as.character(best_year) & 
      CONTENT_AREA == content,
      .N
    ]
    n_current <- STATE_DATA_LONG[
      GRADE == grade_current & 
      YEAR == as.character(best_year + span) & 
      CONTENT_AREA == content,
      .N
    ]
    
    if (n_prior >= 100 && n_current >= 100) {
      TEST_CONFIGS[[length(TEST_CONFIGS) + 1]] <- list(
        name = paste0(content, "_G", grade_prior, "to", grade_current),
        grade_prior = grade_prior,
        grade_current = grade_current,
        year_prior = as.character(best_year),
        content_prior = content,
        content_current = content,
        type = "within"
      )
    }
  }
  
  # Cross-content configurations (different subjects)
  if (length(content_areas_available) >= 2) {
    for (i in 1:(length(content_areas_available) - 1)) {
      for (j in (i + 1):length(content_areas_available)) {
        content_prior <- content_areas_available[i]
        content_current <- content_areas_available[j]
        
        n_prior <- STATE_DATA_LONG[
          GRADE == grade_prior & 
          YEAR == as.character(best_year) & 
          CONTENT_AREA == content_prior,
          .N
        ]
        n_current <- STATE_DATA_LONG[
          GRADE == grade_current & 
          YEAR == as.character(best_year + span) & 
          CONTENT_AREA == content_current,
          .N
        ]
        
        if (n_prior >= 100 && n_current >= 100) {
          TEST_CONFIGS[[length(TEST_CONFIGS) + 1]] <- list(
            name = paste0(content_prior, "To", content_current, "_G", grade_prior, "to", grade_current),
            grade_prior = grade_prior,
            grade_current = grade_current,
            year_prior = as.character(best_year),
            content_prior = content_prior,
            content_current = content_current,
            type = "cross"
          )
        }
      }
    }
  }
}

cat("✓ Generated", length(TEST_CONFIGS), "valid content area configurations\n")
if (length(TEST_CONFIGS) == 0) {
  stop("No valid content area configurations found in dataset")
}
cat("\n")

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
n_tasks <- length(TEST_CONFIGS)
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
  init_data <- everywhere({
    tryCatch({
      .DATASET_PATH <- DATA_PATH_VALUE
      .RDATA_OBJECT <- RDATA_OBJECT_VALUE
      N_BOOTSTRAP <- N_BOOTSTRAP_VALUE
      COPULA_FAMILIES <- COPULA_FAMILIES_VALUE
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
    gc(verbose = FALSE)
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

process_content_area_condition <- function(config) {
  
  tryCatch({
    
    # Per-task data loading (like STEP_1 pattern)
    if (!exists("STATE_DATA_LONG") || !exists(".LOADED_DATASET")) {
      if (!is.null(.DATASET_PATH) && !is.null(.RDATA_OBJECT)) {
        load(.DATASET_PATH)
        STATE_DATA_LONG <- get(.RDATA_OBJECT)
        data.table::setDT(STATE_DATA_LONG)
        assign("STATE_DATA_LONG", STATE_DATA_LONG, envir = .GlobalEnv)
        assign(".LOADED_DATASET", TRUE, envir = .GlobalEnv)
      }
    }
    
    # year_prior is already validated during config generation
    # No need to resolve - use directly
    
    # Create longitudinal pairs
    pairs_full <- create_longitudinal_pairs(
      data = STATE_DATA_LONG,
      grade_prior = config$grade_prior,
      grade_current = config$grade_current,
      year_prior = config$year_prior,
      content_prior = config$content_prior,
      content_current = config$content_current
    )
    
    if (is.null(pairs_full) || nrow(pairs_full) < 100) {
      return(list(
        config = config,
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
    content_results <- list()
    
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
      
      content_results[[paste0("n", n)]] <- boot_result
    }
    
    # Return complete results
    return(list(
      config = config,
      true_copula = true_copula,
      bootstrap_results = content_results,
      n_pairs = nrow(pairs_full),
      frameworks = list(prior = framework_prior, current = framework_current),
      success = TRUE
    ))
    
  }, error = function(e) {
    return(list(
      config = config,
      success = FALSE,
      error = e$message
    ))
  })
}

################################################################################
### RUN PARALLEL PROCESSING
################################################################################

if (n_cores_use > 1) {
  cat("Processing", length(TEST_CONFIGS), "content area conditions in parallel...\n")
  cat("  Progress: Use 'mirai::status()$connections' to verify workers are active\n")
  cat("  Expected runtime: ~", round(length(TEST_CONFIGS) * 2 / n_cores_use, 1), "minutes\n\n")
  start_time <- Sys.time()

  all_results_raw <- mirai_map(TEST_CONFIGS, process_content_area_condition)
  all_results_raw <- all_results_raw[]

  end_time <- Sys.time()
  runtime <- difftime(end_time, start_time, units = "mins")

  cat("✓ Parallel processing complete\n")
  cat("  Runtime:", round(runtime, 2), "minutes\n\n")
} else {
  # Sequential fallback
  cat("Processing", length(TEST_CONFIGS), "conditions sequentially...\n\n")
  start_time <- Sys.time()
  
  all_results_raw <- lapply(TEST_CONFIGS, process_content_area_condition)
  
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
    all_results[[result$config$name]] <- result
    
    # Print summary for this condition
    cat("\n====================================================================\n")
    cat("Processed:", result$config$name, "\n")
    cat("Type:", result$config$type, "\n")
    cat("Prior:", result$config$content_prior, "Grade", result$config$grade_prior, "\n")
    cat("Current:", result$config$content_current, "Grade", result$config$grade_current, "\n")
    cat("True Kendall's tau:", round(result$true_copula$empirical_tau, 4), "\n")
    cat("Best family:", result$true_copula$best_family, "\n")
    cat("N pairs:", result$n_pairs, "\n")
    cat("Sample sizes tested:", length(result$bootstrap_results), "\n")
    cat("====================================================================\n")
    
  } else {
    failed_conditions[[length(failed_conditions) + 1]] <- result
    cat("\n✗ FAILED:", result$config$name, "- Error:", result$error, "\n")
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

for (config_name in names(all_results)) {
  
  result <- all_results[[config_name]]
  
  # Save individual content results
  output_dir <- file.path("STEP_2_Copula_Sensitivity_Analyses/results", "exp_3_content_area", config_name)
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
  
  year_span <- result$config$grade_current - result$config$grade_prior
  canonical_content <- if (result$config$content_prior == result$config$content_current) {
    result$config$content_current
  } else {
    NA
  }
  baseline_family <- if ("t" %in% names(result$true_copula$results)) "t" else result$true_copula$best_family
  extra_copulas <- list()
  if (!is.na(canonical_content)) {
    canonical_copula <- get_canonical_copula(CANONICAL_PARAMS, year_span, canonical_content)
    if (!is.null(canonical_copula)) {
      extra_copulas[[paste0("canonical_", tolower(canonical_content), "_span", year_span)]] <- canonical_copula
    }
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
      experiment = "exp_3_content_area",
      configuration = config_name,
      type = result$config$type,
      content_prior = result$config$content_prior,
      content_current = result$config$content_current,
      n_pairs = result$n_pairs
    )]
    fwrite(sgpc_sensitivity, file = file.path(output_dir, "sgpc_sensitivity.csv"))
    sgpc_sensitivity_all[[config_name]] <- sgpc_sensitivity
  }

  cat("✓ Results saved to:", output_dir, "\n")
}

################################################################################
### CROSS-CONTENT COMPARISON
################################################################################

cat("\n====================================================================\n")
cat("CROSS-CONTENT COMPARISON\n")
cat("====================================================================\n\n")

if (length(sgpc_sensitivity_all) > 0) {
  sgpc_summary <- rbindlist(sgpc_sensitivity_all, fill = TRUE)
  sgpc_output_dir <- "STEP_2_Copula_Sensitivity_Analyses/results/exp_3_content_area"
  dir.create(sgpc_output_dir, recursive = TRUE, showWarnings = FALSE)
  fwrite(sgpc_summary, file = file.path(sgpc_output_dir, "sgpc_sensitivity_summary.csv"))
}

# Create comprehensive comparison table
comparison_data <- list()

for (config_name in names(all_results)) {
  
  result <- all_results[[config_name]]
  config <- result$config
  true_tau <- result$true_copula$empirical_tau
  best_family <- result$true_copula$best_family
  n_pairs <- result$n_pairs
  
  for (size_name in names(result$bootstrap_results)) {
    n_sample <- as.numeric(gsub("n", "", size_name))
    boot_result <- result$bootstrap_results[[size_name]]
    
    summary_dt <- summarize_bootstrap_copulas(boot_result, result$true_copula)
    best_summary <- summary_dt[family == best_family]
    
    comparison_data[[length(comparison_data) + 1]] <- data.table(
      configuration = config_name,
      type = config$type,
      content_prior = config$content_prior,
      content_current = config$content_current,
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
output_dir <- "STEP_2_Copula_Sensitivity_Analyses/results/exp_3_content_area"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

fwrite(comparison_table,
       file = file.path(output_dir, "content_area_comparison.csv"))

cat("Content Area Comparison Summary:\n\n")
print(comparison_table[, .(configuration, type, sample_size, 
                           true_tau, tau_mean, tau_sd, ci_width)])

# Separate within-content and cross-content
within_content <- comparison_table[type == "within"]
cross_content <- comparison_table[type == "cross"]

cat("\n\nWithin-Content Analysis (Same Subject):\n")
print(within_content[, .(content_prior, sample_size, true_tau, 
                         tau_mean, tau_sd, ci_width)])

cat("\n\nCross-Content Analysis (Different Subjects):\n")
print(cross_content[, .(content_prior, content_current, sample_size, 
                        true_tau, tau_mean, tau_sd, ci_width)])

# Create comparison plots
pdf(file.path(output_dir, "content_area_comparison.pdf"), width = 14, height = 10)

par(mfrow = c(2, 2))

# Plot 1: True tau by content area (within-content only)
if (nrow(within_content) > 0) {
  within_summary <- within_content[, .(true_tau = mean(true_tau)), by = content_prior]
  barplot(within_summary$true_tau,
          names.arg = within_summary$content_prior,
          col = rainbow(nrow(within_summary)),
          main = "True Copula Strength by Content Area",
          ylab = expression("True Kendall's" ~ tau),
          ylim = c(0, 1))
  grid()
}

# Plot 2: CI width comparison (within vs cross)
boxplot(ci_width ~ type, data = comparison_table,
        col = c("lightblue", "lightcoral"),
        main = "Estimation Precision: Within vs Cross-Content",
        ylab = "90% CI Width",
        xlab = "Analysis Type")
grid()

# Plot 3: True tau for all configurations
config_taus <- comparison_table[, .(true_tau = mean(true_tau)), by = configuration]
par(mar = c(10, 4, 4, 2))
barplot(config_taus$true_tau,
        names.arg = config_taus$configuration,
        las = 2,
        col = rainbow(nrow(config_taus)),
        main = "True Copula Strength: All Configurations",
        ylab = expression("True Kendall's" ~ tau))
grid()

# Plot 4: Precision by sample size and content type
par(mar = c(5, 4, 4, 2))
plot(0, type = "n",
     xlim = range(comparison_table$sample_size),
     ylim = range(comparison_table$ci_width),
     xlab = "Sample Size",
     ylab = "90% CI Width",
     main = "Precision by Sample Size and Content Type",
     log = "x")

# Within-content lines
if (nrow(within_content) > 0) {
  for (content in unique(within_content$content_prior)) {
    subset_data <- within_content[content_prior == content]
    lines(subset_data$sample_size, subset_data$ci_width,
          type = "b", pch = 19, lwd = 2, col = "blue")
  }
}

# Cross-content lines
if (nrow(cross_content) > 0) {
  for (config in unique(cross_content$configuration)) {
    subset_data <- cross_content[configuration == config]
    lines(subset_data$sample_size, subset_data$ci_width,
          type = "b", pch = 17, lwd = 2, col = "red", lty = 2)
  }
}

legend("topright",
       legend = c("Within-content", "Cross-content"),
       col = c("blue", "red"),
       lty = c(1, 2),
       pch = c(19, 17),
       lwd = 2,
       bg = "white")
grid()

dev.off()

cat("\n====================================================================\n")
cat("EXPERIMENT 3 COMPLETE\n")
cat("====================================================================\n\n")

cat("Key Findings:\n\n")

# Compare within-content correlations
if (nrow(within_content) > 0) {
  within_by_content <- within_content[sample_size == max(sample_size),
                                      .(true_tau = mean(true_tau)),
                                      by = content_prior]
  cat("Within-Content Correlations (Grade 4->8):\n")
  for (i in 1:nrow(within_by_content)) {
    cat("  ", within_by_content$content_prior[i], ": tau =",
        round(within_by_content$true_tau[i], 4), "\n")
  }
  cat("\n")
}

# Compare cross-content correlations
if (nrow(cross_content) > 0) {
  cross_summary <- cross_content[sample_size == max(sample_size),
                                 .(true_tau = mean(true_tau)),
                                 by = .(content_prior, content_current)]
  cat("Cross-Content Correlations (Grade 4->8):\n")
  for (i in 1:nrow(cross_summary)) {
    cat("  ", cross_summary$content_prior[i], "->", 
        cross_summary$content_current[i], ": tau =",
        round(cross_summary$true_tau[i], 4), "\n")
  }
  cat("\n")
}

# Precision comparison
avg_ci_within <- mean(within_content[sample_size == max(SAMPLE_SIZES)]$ci_width, na.rm = TRUE)
avg_ci_cross <- mean(cross_content[sample_size == max(SAMPLE_SIZES)]$ci_width, na.rm = TRUE)

cat("Average CI Width (n =", max(SAMPLE_SIZES), "):\n")
cat("  Within-content:", round(avg_ci_within, 4), "\n")
cat("  Cross-content:", round(avg_ci_cross, 4), "\n\n")

if (avg_ci_cross > avg_ci_within * 1.2) {
  cat("FINDING: Cross-content analysis shows substantially lower precision.\n")
  cat("         Within-content copulas recommended when possible.\n")
} else {
  cat("FINDING: Precision is similar for within- and cross-content analysis.\n")
  cat("         Cross-content copulas may be viable for growth modeling.\n")
}

cat("\n- Results saved to: STEP_2_Copula_Sensitivity_Analyses/results/exp_3_content_area/\n\n")

# Save complete workspace
save(all_results, comparison_table, within_content, cross_content,
     file = file.path(output_dir, "content_area_experiment.RData"))

cat("Workspace saved for further analysis.\n\n")
