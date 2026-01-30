############################################################################
### Experiment 4: Sensitivity to Cohort/Year (PARALLEL VERSION)
### Question: Does cohort effect matter? Do copulas differ across years?
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
cat("EXPERIMENT 4: COHORT/YEAR SENSITIVITY (PARALLEL VERSION)\n")
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

# Generate cohort configurations dynamically based on actual data availability
cohort_content <- "MATHEMATICS"
years_available <- sort(unique(as.numeric(as.character(STATE_DATA_LONG$YEAR))))

cat("Generating dynamic COHORT_CONFIGS...\n")
cat("  Available years:", paste(range(years_available), collapse = "-"), "\n")
cat("  Content area:", cohort_content, "\n")

COHORT_CONFIGS <- list()

# Test 1-year transitions (G4->G5, G5->G6) across all available consecutive years
grade_pairs <- list(
  list(grade_prior = 4, grade_current = 5, label = "G4to5"),
  list(grade_prior = 5, grade_current = 6, label = "G5to6")
)

for (pair in grade_pairs) {
  for (year_prior in years_available) {
    year_current <- year_prior + 1
    
    # Check if both years exist in dataset
    if (!year_current %in% years_available) next
    
    # Validate sufficient data exists for these grades/years
    n_prior <- STATE_DATA_LONG[
      GRADE == pair$grade_prior &
      YEAR == as.character(year_prior) &
      CONTENT_AREA == cohort_content,
      .N
    ]
    n_current <- STATE_DATA_LONG[
      GRADE == pair$grade_current &
      YEAR == as.character(year_current) &
      CONTENT_AREA == cohort_content,
      .N
    ]
    
    # Require at least 100 students in each year for meaningful analysis
    if (n_prior >= 100 && n_current >= 100) {
      COHORT_CONFIGS[[length(COHORT_CONFIGS) + 1]] <- list(
        name = paste0(pair$label, "_", year_prior, "to", year_current),
        grade_prior = pair$grade_prior,
        grade_current = pair$grade_current,
        year_prior = as.character(year_prior),
        content = cohort_content,
        cohort = as.character(year_prior)
      )
    }
  }
}

cat("✓ Generated", length(COHORT_CONFIGS), "valid cohort configurations\n")
if (length(COHORT_CONFIGS) == 0) {
  stop("No valid cohort configurations found in dataset. Need consecutive years with >= 100 students per grade.")
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
n_tasks <- length(COHORT_CONFIGS)
n_cores_use <- min(n_cores_use, n_tasks)
cat("Tasks:", n_tasks, "/ Workers:", n_cores_use, "\n\n")

if (n_cores_use > 1) {
  cat("====================================================================\n")
  cat("MIRAI PARALLEL PROCESSING ENABLED\n")
  cat("====================================================================\n")
  cat("Using", n_cores_use, "daemons\n")
  cat("Expected speedup: 8-10x\n\n")

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
      CANONICAL_PARAMS <- CANONICAL_PARAMS_VALUE
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

process_cohort_condition <- function(config) {
  
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
      content_prior = config$content,
      content_current = config$content
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
    cohort_results <- list()
    
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
      
      cohort_results[[paste0("n", n)]] <- boot_result
    }
    
    # Return complete results
    return(list(
      config = config,
      true_copula = true_copula,
      bootstrap_results = cohort_results,
      n_pairs = nrow(pairs_full),
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
  cat("Processing", length(COHORT_CONFIGS), "cohort conditions in parallel...\n")
  cat("  Progress: Use 'mirai::status()$connections' to verify workers are active\n")
  cat("  Expected runtime: ~", round(length(COHORT_CONFIGS) * 2 / n_cores_use, 1), "minutes\n\n")
  start_time <- Sys.time()

  all_results_raw <- mirai_map(COHORT_CONFIGS, process_cohort_condition)
  all_results_raw <- all_results_raw[]

  end_time <- Sys.time()
  runtime <- difftime(end_time, start_time, units = "mins")

  cat("✓ Parallel processing complete\n")
  cat("  Runtime:", round(runtime, 2), "minutes\n\n")
} else {
  # Sequential fallback
  cat("Processing", length(COHORT_CONFIGS), "cohorts sequentially...\n\n")
  start_time <- Sys.time()
  
  all_results_raw <- lapply(COHORT_CONFIGS, process_cohort_condition)
  
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
    cat("Cohort:", result$config$cohort, "\n")
    cat("Grade", result$config$grade_prior, "->", result$config$grade_current, "\n")
    cat("Year:", result$config$year_prior, "->", as.numeric(result$config$year_prior) + 1, "\n")
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
cat("Successfully processed:", length(all_results), "cohorts\n")
cat("Failed:", length(failed_conditions), "cohorts\n\n")

################################################################################
### SAVE INDIVIDUAL RESULTS AND CREATE REPORTS
################################################################################

cat("Creating individual reports...\n\n")

for (config_name in names(all_results)) {
  
  result <- all_results[[config_name]]
  
  # Save individual cohort results
  output_dir <- file.path("STEP_2_Copula_Sensitivity_Analyses/results", "exp_4_cohort", config_name)
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
  
  year_span <- result$config$grade_current - result$config$grade_prior
  baseline_family <- if ("t" %in% names(result$true_copula$results)) "t" else result$true_copula$best_family
  extra_copulas <- list()
  canonical_copula <- get_canonical_copula(CANONICAL_PARAMS, year_span, result$config$content)
  if (!is.null(canonical_copula)) {
    extra_copulas[[paste0("canonical_", tolower(result$config$content), "_span", year_span)]] <- canonical_copula
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
      experiment = "exp_4_cohort",
      configuration = config_name,
      cohort = result$config$cohort,
      grade_transition = paste0(result$config$grade_prior, "->", result$config$grade_current),
      n_pairs = result$n_pairs
    )]
    fwrite(sgpc_sensitivity, file = file.path(output_dir, "sgpc_sensitivity.csv"))
    sgpc_sensitivity_all[[config_name]] <- sgpc_sensitivity
  }

  cat("✓ Results saved to:", output_dir, "\n")
}

################################################################################
### CROSS-COHORT COMPARISON
################################################################################

cat("\n====================================================================\n")
cat("CROSS-COHORT COMPARISON\n")
cat("====================================================================\n\n")

if (length(sgpc_sensitivity_all) > 0) {
  sgpc_summary <- rbindlist(sgpc_sensitivity_all, fill = TRUE)
  sgpc_output_dir <- "STEP_2_Copula_Sensitivity_Analyses/results/exp_4_cohort"
  dir.create(sgpc_output_dir, recursive = TRUE, showWarnings = FALSE)
  fwrite(sgpc_summary, file = file.path(sgpc_output_dir, "sgpc_sensitivity_summary.csv"))
}

# Create comparison table
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
      cohort = config$cohort,
      grade_transition = paste0(config$grade_prior, "->", config$grade_current),
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
output_dir <- "STEP_2_Copula_Sensitivity_Analyses/results/exp_4_cohort"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

fwrite(comparison_table,
       file = file.path(output_dir, "cohort_comparison.csv"))

cat("Cohort Comparison Summary:\n\n")
print(comparison_table[, .(cohort, grade_transition, sample_size, 
                           true_tau, tau_mean, tau_sd, ci_width)])

# Separate by grade transition
g4to5_data <- comparison_table[grade_transition == "4->5"]
g5to6_data <- comparison_table[grade_transition == "5->6"]

# Create comparison plots
pdf(file.path(output_dir, "cohort_comparison.pdf"), width = 14, height = 10)

par(mfrow = c(2, 2))

# Plot 1: True tau by cohort for Grade 4->5
if (nrow(g4to5_data) > 0) {
  cohort_taus_g4to5 <- g4to5_data[, .(true_tau = mean(true_tau)), by = cohort]
  plot(as.numeric(cohort_taus_g4to5$cohort), cohort_taus_g4to5$true_tau,
       type = "b", pch = 19, col = "blue", lwd = 2,
       xlab = "Cohort Year",
       ylab = expression("True Kendall's" ~ tau),
       main = "Grade 4->5: Copula Strength by Cohort",
       ylim = c(0.5, 1))
  grid()
}

# Plot 2: True tau by cohort for Grade 5->6
if (nrow(g5to6_data) > 0) {
  cohort_taus_g5to6 <- g5to6_data[, .(true_tau = mean(true_tau)), by = cohort]
  plot(as.numeric(cohort_taus_g5to6$cohort), cohort_taus_g5to6$true_tau,
       type = "b", pch = 19, col = "darkgreen", lwd = 2,
       xlab = "Cohort Year",
       ylab = expression("True Kendall's" ~ tau),
       main = "Grade 5->6: Copula Strength by Cohort",
       ylim = c(0.5, 1))
  grid()
}

# Plot 3: CI width by cohort and sample size (Grade 4->5)
if (nrow(g4to5_data) > 0) {
  plot(0, type = "n",
       xlim = range(as.numeric(g4to5_data$cohort)),
       ylim = range(g4to5_data$ci_width),
       xlab = "Cohort Year",
       ylab = "90% CI Width",
       main = "Grade 4->5: Precision by Cohort and Sample Size")
  
  for (n in unique(g4to5_data$sample_size)) {
    subset_data <- g4to5_data[sample_size == n]
    lines(as.numeric(subset_data$cohort), subset_data$ci_width,
          type = "b", pch = 19, lwd = 2,
          col = rainbow(length(unique(g4to5_data$sample_size)))[which(unique(g4to5_data$sample_size) == n)])
  }
  
  legend("topright",
         legend = paste("n =", unique(g4to5_data$sample_size)),
         col = rainbow(length(unique(g4to5_data$sample_size))),
         lwd = 2, pch = 19, bg = "white")
  grid()
}

# Plot 4: Standard deviation of true taus across cohorts
if (nrow(g4to5_data) > 0 && nrow(g5to6_data) > 0) {
  sd_g4to5 <- sd(g4to5_data[sample_size == max(SAMPLE_SIZES)]$true_tau)
  sd_g5to6 <- sd(g5to6_data[sample_size == max(SAMPLE_SIZES)]$true_tau)
  
  barplot(c(sd_g4to5, sd_g5to6),
          names.arg = c("Grade 4->5", "Grade 5->6"),
          col = c("lightblue", "lightgreen"),
          main = "Cohort Variability in True Copula Strength",
          ylab = expression("SD of Kendall's" ~ tau ~ "across cohorts"))
  grid()
}

dev.off()

# Statistical test for cohort differences
cat("\n====================================================================\n")
cat("STATISTICAL ANALYSIS OF COHORT EFFECTS\n")
cat("====================================================================\n\n")

# For Grade 4->5, test if true taus differ significantly across cohorts
if (nrow(g4to5_data) > 0) {
  cat("Grade 4->5 Cohort Analysis:\n")
  
  cohort_taus <- g4to5_data[sample_size == max(SAMPLE_SIZES), 
                             .(true_tau = mean(true_tau)), 
                             by = cohort]
  
  cat("  Mean tau across cohorts:", round(mean(cohort_taus$true_tau), 4), "\n")
  cat("  SD of tau across cohorts:", round(sd(cohort_taus$true_tau), 4), "\n")
  cat("  Range:", round(min(cohort_taus$true_tau), 4), "to", 
      round(max(cohort_taus$true_tau), 4), "\n")
  cat("  Coefficient of variation:", 
      round(sd(cohort_taus$true_tau) / mean(cohort_taus$true_tau) * 100, 2), "%\n\n")
  
  # Compare to bootstrap variability
  typical_bootstrap_sd <- mean(g4to5_data[sample_size == max(SAMPLE_SIZES)]$tau_sd)
  cat("  Typical bootstrap SD:", round(typical_bootstrap_sd, 4), "\n")
  
  if (sd(cohort_taus$true_tau) > typical_bootstrap_sd) {
    cat("  FINDING: Cohort variability EXCEEDS bootstrap variability\n")
    cat("           Cohort effects are meaningful and should be considered.\n\n")
  } else {
    cat("  FINDING: Cohort variability is within bootstrap variability\n")
    cat("           Cohort effects are negligible relative to sampling error.\n\n")
  }
}

# For Grade 5->6
if (nrow(g5to6_data) > 0) {
  cat("Grade 5->6 Cohort Analysis:\n")
  
  cohort_taus <- g5to6_data[sample_size == max(SAMPLE_SIZES), 
                             .(true_tau = mean(true_tau)), 
                             by = cohort]
  
  cat("  Mean tau across cohorts:", round(mean(cohort_taus$true_tau), 4), "\n")
  cat("  SD of tau across cohorts:", round(sd(cohort_taus$true_tau), 4), "\n")
  cat("  Range:", round(min(cohort_taus$true_tau), 4), "to", 
      round(max(cohort_taus$true_tau), 4), "\n")
  cat("  Coefficient of variation:", 
      round(sd(cohort_taus$true_tau) / mean(cohort_taus$true_tau) * 100, 2), "%\n\n")
  
  typical_bootstrap_sd <- mean(g5to6_data[sample_size == max(SAMPLE_SIZES)]$tau_sd)
  cat("  Typical bootstrap SD:", round(typical_bootstrap_sd, 4), "\n")
  
  if (sd(cohort_taus$true_tau) > typical_bootstrap_sd) {
    cat("  FINDING: Cohort variability EXCEEDS bootstrap variability\n")
    cat("           Cohort effects are meaningful.\n\n")
  } else {
    cat("  FINDING: Cohort variability is within bootstrap variability\n")
    cat("           Cohort effects are negligible.\n\n")
  }
}

cat("====================================================================\n")
cat("EXPERIMENT 4 COMPLETE\n")
cat("====================================================================\n\n")

cat("Key Findings:\n")
cat("- Tested copula stability across", length(unique(comparison_table$cohort)), 
    "different cohorts\n")
cat("- Examined Grade 4->5 and Grade 5->6 transitions\n")
cat("- Results saved to: STEP_2_Copula_Sensitivity_Analyses/results/exp_4_cohort/\n\n")

cat("Implications for TIMSS-like Cross-Sectional Analysis:\n")
cat("- If cohort effects are negligible: Can pool data across years\n")
cat("- If cohort effects are substantial: Need cohort-specific copulas\n")
cat("- Consider temporal trends in assessment difficulty or curriculum\n\n")

# Save complete workspace
save(all_results, comparison_table, g4to5_data, g5to6_data,
     file = file.path(output_dir, "cohort_experiment.RData"))

cat("Workspace saved for further analysis.\n\n")
