############################################################################
### PHASE 1: COPULA FAMILY SELECTION STUDY (PARALLEL VERSION)
### Parallelized across 28 conditions using parallel package
###
### Objective: Identify which copula family consistently provides best fit
###           for longitudinal educational assessment data
###
### Hypothesis: T-copula will dominate due to heavy tails in educational
###             data, with tail dependence increasing as time between
###             observations increases.
###
### Parallelization Strategy:
###   - Uses parallel package (base R, no extra dependencies)
###   - Each condition processed independently on separate cores
###   - Expected speedup: 14-15x on c6i.4xlarge (16 cores)
###   - Target runtime: 4-6 minutes (vs 60-90 minutes sequential)
############################################################################

require(data.table)
require(splines2)
require(copula)
require(parallel)

cat("====================================================================\n")
cat("PHASE 1: COPULA FAMILY SELECTION STUDY (PARALLEL)\n")
cat("====================================================================\n")

# Detect cores and set up cluster
n_cores_available <- detectCores()

# Determine optimal core usage based on environment
if (exists("IS_EC2", envir = .GlobalEnv) && IS_EC2) {
  # EC2 c8g.12xlarge: Use 46 of 48 cores (leave 2 for system)
  n_cores_use <- min(n_cores_available - 2, 46)
} else {
  # Local: Use n-1 cores
  n_cores_use <- n_cores_available - 1
}

# Use FORK cluster on Unix systems (macOS, Linux)
# FORK is faster and more memory-efficient than PSOCK
if (.Platform$OS.type == "unix") {
  cat("Initializing FORK cluster (Unix shared memory)...\n")
  cl <- makeForkCluster(n_cores_use)
  cat("  Type: FORK (copy-on-write, no data export needed)\n")
} else {
  cat("Initializing PSOCK cluster (Windows fallback)...\n")
  cl <- makeCluster(n_cores_use, type = "PSOCK")
  cat("  Type: PSOCK (socket-based, requires data export)\n")
}

cat("Available cores:", n_cores_available, "\n")
cat("Using cores:", n_cores_use, "\n\n")

# Capture N_BOOTSTRAP_GOF for workers
if (exists("N_BOOTSTRAP_GOF", envir = .GlobalEnv)) {
  N_BOOTSTRAP_GOF_VALUE <- get("N_BOOTSTRAP_GOF", envir = .GlobalEnv)
  cat("Goodness-of-Fit Testing: ENABLED (N =", N_BOOTSTRAP_GOF_VALUE, "bootstrap samples)\n")
} else {
  N_BOOTSTRAP_GOF_VALUE <- NULL
  cat("Goodness-of-Fit Testing: DISABLED\n")
}
cat("\n")

# Export setup differs by cluster type
if (.Platform$OS.type == "unix") {
  # FORK cluster: Workers inherit parent environment via copy-on-write
  # Only need to load packages and source functions
  cat("Setting up FORK workers (no data export needed)...\n")
  
  clusterEvalQ(cl, {
    require(data.table)
    require(splines2)
    require(copula)
  })
  
  clusterEvalQ(cl, {
    source("functions/longitudinal_pairs.R")
    source("functions/ispline_ecdf.R")
    source("functions/copula_bootstrap.R")
  })
  
} else {
  # PSOCK cluster: Must explicitly export data and configuration
  cat("Exporting data and functions to PSOCK workers...\n")
  
  clusterExport(cl, c("STATE_DATA_LONG", "WORKSPACE_OBJECT_NAME", "get_state_data", 
                      "N_BOOTSTRAP_GOF_VALUE"), envir = environment())
  
  clusterEvalQ(cl, {
    require(data.table)
    require(splines2)
    require(copula)
  })
  
  clusterEvalQ(cl, {
    source("functions/longitudinal_pairs.R")
    source("functions/ispline_ecdf.R")
    source("functions/copula_bootstrap.R")
  })
}

cat("Cluster initialized successfully.\n\n")

################################################################################
### CONFIGURATION
################################################################################

# All copula families to test
# Including comonotonic (Fréchet-Hoeffding upper bound) to show how badly
# the implicit TAMP assumption (perfect positive dependence) misfits the data
# Note: We focus on t-copula with data-driven df estimation (not fixed df)
# as preliminary results showed free df consistently dominates fixed df variants
COPULA_FAMILIES <- c("gaussian", "t", "clayton", "gumbel", "frank", "comonotonic")

# Define test conditions
# Two strategies:
# 1. Strategic subset (datasets 1 & 2): Representative sampling for family selection
# 2. Exhaustive (dataset 3): All valid combinations for transition analysis

# Check if we should use exhaustive conditions for this dataset
USE_EXHAUSTIVE_CONDITIONS <- exists("current_dataset", envir = .GlobalEnv) && 
                             !is.null(current_dataset) && 
                             current_dataset$id == "dataset_3"

if (USE_EXHAUSTIVE_CONDITIONS) {
  cat("Using EXHAUSTIVE conditions for", current_dataset$name, "\n")
  cat("  (All valid year/grade/content combinations for transition analysis)\n\n")
  
  # Generate all valid conditions for this dataset
  CONDITIONS <- generate_exhaustive_conditions(current_dataset, max_year_span = 4)
  
  # Rename year_span to span for consistency with parallel version
  for (i in seq_along(CONDITIONS)) {
    CONDITIONS[[i]]$span <- CONDITIONS[[i]]$year_span
  }
  
} else {
  cat("Using STRATEGIC SUBSET conditions\n")
  cat("  (Representative sampling for copula family selection)\n\n")
  
  # Strategic subset conditions
  CONDITIONS <- list(
    # 1-year spans
    list(grade_prior = 4, grade_current = 5, year_prior = "2010", content = "MATHEMATICS", span = 1),
    list(grade_prior = 4, grade_current = 5, year_prior = "2011", content = "MATHEMATICS", span = 1),
    list(grade_prior = 5, grade_current = 6, year_prior = "2010", content = "MATHEMATICS", span = 1),
    list(grade_prior = 6, grade_current = 7, year_prior = "2010", content = "MATHEMATICS", span = 1),
    list(grade_prior = 4, grade_current = 5, year_prior = "2010", content = "READING", span = 1),
    list(grade_prior = 5, grade_current = 6, year_prior = "2010", content = "READING", span = 1),
    list(grade_prior = 4, grade_current = 5, year_prior = "2010", content = "WRITING", span = 1),
    
    # 2-year spans
    list(grade_prior = 4, grade_current = 6, year_prior = "2010", content = "MATHEMATICS", span = 2),
    list(grade_prior = 4, grade_current = 6, year_prior = "2011", content = "MATHEMATICS", span = 2),
    list(grade_prior = 5, grade_current = 7, year_prior = "2010", content = "MATHEMATICS", span = 2),
    list(grade_prior = 6, grade_current = 8, year_prior = "2010", content = "MATHEMATICS", span = 2),
    list(grade_prior = 4, grade_current = 6, year_prior = "2010", content = "READING", span = 2),
    list(grade_prior = 5, grade_current = 7, year_prior = "2010", content = "READING", span = 2),
    list(grade_prior = 4, grade_current = 6, year_prior = "2010", content = "WRITING", span = 2),
    
    # 3-year spans
    list(grade_prior = 4, grade_current = 7, year_prior = "2010", content = "MATHEMATICS", span = 3),
    list(grade_prior = 4, grade_current = 7, year_prior = "2009", content = "MATHEMATICS", span = 3),
    list(grade_prior = 5, grade_current = 8, year_prior = "2010", content = "MATHEMATICS", span = 3),
    list(grade_prior = 6, grade_current = 9, year_prior = "2010", content = "MATHEMATICS", span = 3),
    list(grade_prior = 4, grade_current = 7, year_prior = "2010", content = "READING", span = 3),
    list(grade_prior = 5, grade_current = 8, year_prior = "2010", content = "READING", span = 3),
    list(grade_prior = 4, grade_current = 7, year_prior = "2010", content = "WRITING", span = 3),
    
    # 4-year spans
    list(grade_prior = 4, grade_current = 8, year_prior = "2009", content = "MATHEMATICS", span = 4),
    list(grade_prior = 4, grade_current = 8, year_prior = "2010", content = "MATHEMATICS", span = 4),
    list(grade_prior = 5, grade_current = 9, year_prior = "2009", content = "MATHEMATICS", span = 4),
    list(grade_prior = 6, grade_current = 10, year_prior = "2009", content = "MATHEMATICS", span = 4),
    list(grade_prior = 4, grade_current = 8, year_prior = "2009", content = "READING", span = 4),
    list(grade_prior = 5, grade_current = 9, year_prior = "2009", content = "READING", span = 4),
    list(grade_prior = 4, grade_current = 8, year_prior = "2009", content = "WRITING", span = 4)
  )
}

################################################################################
### ENRICH CONDITIONS WITH DATASET METADATA
################################################################################

# Add dataset-specific metadata to each condition using helper functions
if (exists("current_dataset", envir = .GlobalEnv) && !is.null(current_dataset)) {
  cat("\n")
  cat("====================================================================\n")
  cat("ENRICHING CONDITIONS WITH DATASET METADATA\n")
  cat("====================================================================\n\n")
  
  for (i in seq_along(CONDITIONS)) {
    cond <- CONDITIONS[[i]]
    
    # Normalize naming: parallel version uses 'span', but we need 'year_span' for consistency
    if (!is.null(cond$span) && is.null(cond$year_span)) {
      cond$year_span <- cond$span
    }
    
    # Calculate year_current from year_prior + year_span
    year_current <- as.character(as.numeric(cond$year_prior) + cond$year_span)
    
    # Add dataset identifiers
    cond$dataset_id <- current_dataset$id
    cond$dataset_name <- current_dataset$name
    cond$anonymized_state <- current_dataset$anonymized_state
    
    # Add scaling metadata using helper functions from dataset_configs.R
    cond$year_current <- year_current
    cond$prior_scaling_type <- get_scaling_type(current_dataset, cond$year_prior)
    cond$current_scaling_type <- get_scaling_type(current_dataset, year_current)
    cond$scaling_transition_type <- get_scaling_transition_type(current_dataset, cond$year_prior, year_current)
    
    # Add transition metadata
    cond$has_transition <- current_dataset$has_transition
    cond$transition_year <- if (current_dataset$has_transition) current_dataset$transition_year else NA
    cond$includes_transition_span <- crosses_transition(current_dataset, cond$year_prior, year_current)
    cond$transition_period <- get_transition_period(current_dataset, cond$year_prior, year_current)
    
    # Update the condition in the list
    CONDITIONS[[i]] <- cond
  }
  
  cat("✓ Conditions enriched with dataset metadata\n")
  cat("  Dataset:", current_dataset$name, "\n")
  cat("  Total conditions:", length(CONDITIONS), "\n\n")
}

################################################################################
### FILTER CONDITIONS BY AVAILABLE CONTENT AREAS
################################################################################

# Filter out conditions with content areas not available in current dataset
if (exists("current_dataset", envir = .GlobalEnv) && !is.null(current_dataset)) {
  available_content_areas <- current_dataset$content_areas
  original_count <- length(CONDITIONS)
  
  CONDITIONS <- CONDITIONS[sapply(CONDITIONS, function(cond) {
    cond$content %in% available_content_areas
  })]
  
  filtered_count <- original_count - length(CONDITIONS)
  if (filtered_count > 0) {
    cat("\n")
    cat("====================================================================\n")
    cat("CONTENT AREA FILTERING\n")
    cat("====================================================================\n")
    cat("Dataset:", current_dataset$name, "\n")
    cat("Available content areas:", paste(available_content_areas, collapse = ", "), "\n")
    cat("Filtered out", filtered_count, "condition(s) with unavailable content areas\n")
    cat("Remaining conditions:", length(CONDITIONS), "\n\n")
  }
}

cat("Total conditions to test:", length(CONDITIONS), "\n")
cat("Copula families:", paste(COPULA_FAMILIES, collapse = ", "), "\n")
cat("Total fits:", length(CONDITIONS) * length(COPULA_FAMILIES), "\n\n")

################################################################################
### DEFINE WORKER FUNCTION
################################################################################

# Function to process a single condition (runs on each worker independently)
process_condition <- function(i, cond, copula_families) {
  
  # This function runs on each worker independently
  # It must be self-contained and return a complete result
  
  tryCatch({
    
    # Create longitudinal pairs
    pairs_full <- create_longitudinal_pairs(
      data = get_state_data(),
      grade_prior = cond$grade_prior,
      grade_current = cond$grade_current,
      year_prior = cond$year_prior,
      content_prior = cond$content,
      content_current = cond$content
    )
    
    # Check if sufficient data
    if (is.null(pairs_full) || nrow(pairs_full) < 100) {
      return(list(
        condition_id = i,
        success = FALSE,
        error = "Insufficient data",
        n_pairs = ifelse(is.null(pairs_full), 0, nrow(pairs_full))
      ))
    }
    
    n_pairs <- nrow(pairs_full)
    
    # Create I-spline frameworks
    framework_prior <- create_ispline_framework(pairs_full$SCALE_SCORE_PRIOR)
    framework_current <- create_ispline_framework(pairs_full$SCALE_SCORE_CURRENT)
    
    # Fit all copula families
    # IMPORTANT: Phase 1 uses empirical ranks (not I-spline) for copula family selection
    # This ensures uniform pseudo-observations and preserves tail dependence structure
    copula_fits <- fit_copula_from_pairs(
      scores_prior = pairs_full$SCALE_SCORE_PRIOR,
      scores_current = pairs_full$SCALE_SCORE_CURRENT,
      framework_prior = framework_prior,
      framework_current = framework_current,
      copula_families = copula_families,
      return_best = FALSE,
      use_empirical_ranks = TRUE,  # Phase 1: Use ranks to avoid I-spline distortion
      n_bootstrap_gof = N_BOOTSTRAP_GOF_VALUE  # Captured from .GlobalEnv and exported to workers
    )
    
    # Extract results for each family
    family_results <- list()
    
    for (family in copula_families) {
      
      if (!is.null(copula_fits$results[[family]])) {
        
        fit <- copula_fits$results[[family]]
        
        # Calculate tail dependence
        if (family %in% c("t", "t_df5", "t_df10", "t_df15")) {
          # All t-copula variants: use pre-calculated values from copula_bootstrap.R
          tail_dep_lower <- if (!is.null(fit$tail_dependence_lower)) fit$tail_dependence_lower else 0
          tail_dep_upper <- if (!is.null(fit$tail_dependence_upper)) fit$tail_dependence_upper else 0
        } else if (family == "clayton") {
          theta <- fit$parameter[1]
          tail_dep_lower <- 2^(-1/theta)
          tail_dep_upper <- 0
        } else if (family == "gumbel") {
          theta <- fit$parameter[1]
          tail_dep_lower <- 0
          tail_dep_upper <- 2 - 2^(1/theta)
        } else if (family == "comonotonic") {
          # Comonotonic: use pre-calculated values
          tail_dep_lower <- if (!is.null(fit$tail_dependence_lower)) fit$tail_dependence_lower else 0
          tail_dep_upper <- if (!is.null(fit$tail_dependence_upper)) fit$tail_dependence_upper else 1
        } else {
          tail_dep_lower <- 0
          tail_dep_upper <- 0
        }
        
        # Extract parameters with proper naming
        param_1 <- fit$parameter[1]
        param_2 <- if (!is.null(fit$df)) fit$df else NA_real_
        
        # Create descriptive parameter columns based on family
        if (family %in% c("gaussian", "t", "t_df5", "t_df10", "t_df15")) {
          correlation_rho <- param_1
          theta <- NA_real_
        } else if (family %in% c("clayton", "gumbel", "frank")) {
          correlation_rho <- NA_real_
          theta <- param_1
        } else {
          # Comonotonic
          correlation_rho <- NA_real_
          theta <- NA_real_
        }
        
        # Degrees of freedom (only for t-copula variants)
        degrees_freedom <- if (family %in% c("t", "t_df5", "t_df10", "t_df15")) param_2 else NA_real_
        
        family_results[[family]] <- data.table(
          # Dataset identifiers
          dataset_id = if (!is.null(cond$dataset_id)) cond$dataset_id else NA_character_,
          dataset_name = if (!is.null(cond$dataset_name)) cond$dataset_name else NA_character_,
          anonymized_state = if (!is.null(cond$anonymized_state)) cond$anonymized_state else NA_character_,
          
          # Scaling characteristics
          prior_scaling_type = if (!is.null(cond$prior_scaling_type)) cond$prior_scaling_type else NA_character_,
          current_scaling_type = if (!is.null(cond$current_scaling_type)) cond$current_scaling_type else NA_character_,
          scaling_transition_type = if (!is.null(cond$scaling_transition_type)) cond$scaling_transition_type else NA_character_,
          has_transition = if (!is.null(cond$has_transition)) cond$has_transition else NA,
          transition_year = if (!is.null(cond$transition_year)) cond$transition_year else NA,
          includes_transition_span = if (!is.null(cond$includes_transition_span)) cond$includes_transition_span else NA,
          transition_period = if (!is.null(cond$transition_period)) cond$transition_period else NA_character_,
          
          # Condition identifiers
          condition_id = i,
          year_span = if (!is.null(cond$year_span)) cond$year_span else cond$span,
          grade_prior = cond$grade_prior,
          grade_current = cond$grade_current,
          year_prior = cond$year_prior,
          year_current = if (!is.null(cond$year_current)) cond$year_current else as.character(as.numeric(cond$year_prior) + cond$year_span),
          content_area = cond$content,
          n_pairs = n_pairs,
          
          # Copula family results
          family = family,
          aic = fit$aic,
          bic = fit$bic,
          loglik = fit$loglik,
          tau = fit$kendall_tau,
          tail_dep_lower = tail_dep_lower,
          tail_dep_upper = tail_dep_upper,
          
          # Generic parameters (for backwards compatibility)
          parameter_1 = param_1,
          parameter_2 = param_2,
          
          # Descriptive parameters (easier for analysis)
          correlation_rho = correlation_rho,
          degrees_freedom = degrees_freedom,
          theta = theta,
          
          # Goodness-of-Fit test results
          gof_statistic = if (!is.null(fit$gof_statistic)) fit$gof_statistic else NA_real_,
          gof_pvalue = if (!is.null(fit$gof_pvalue)) fit$gof_pvalue else NA_real_,
          gof_pass_0.05 = if (!is.null(fit$gof_pvalue)) (fit$gof_pvalue > 0.05) else NA,
          gof_method = if (!is.null(fit$gof_method)) fit$gof_method else NA_character_
        )
      }
    }
    
    # Return list with success status
    return(list(
      condition_id = i,
      success = TRUE,
      n_pairs = n_pairs,
      best_family = copula_fits$best_family,
      empirical_tau = copula_fits$empirical_tau,
      results = family_results
    ))
    
  }, error = function(e) {
    return(list(
      condition_id = i,
      success = FALSE,
      error = as.character(e$message)
    ))
  })
}

################################################################################
### RUN PARALLEL ANALYSIS
################################################################################

cat("Starting parallel processing of", length(CONDITIONS), "conditions...\n")
cat("Progress will be shown as conditions complete.\n\n")

start_time <- Sys.time()

# Export process_condition function to cluster
# N_BOOTSTRAP_GOF_VALUE already exported earlier, but include here for clarity
clusterExport(cl, c("process_condition", "CONDITIONS", "COPULA_FAMILIES", "N_BOOTSTRAP_GOF_VALUE"), 
              envir = environment())

# Run parallel processing
all_condition_results <- parLapply(
  cl = cl,
  X = seq_along(CONDITIONS),
  fun = function(i) {
    process_condition(i, CONDITIONS[[i]], COPULA_FAMILIES)
  }
)

end_time <- Sys.time()
duration <- difftime(end_time, start_time, units = "mins")

cat("\n====================================================================\n")
cat("PARALLEL PROCESSING COMPLETE\n")
cat("====================================================================\n")
cat("Total time:", round(duration, 2), "minutes\n")
cat("Average time per condition:", round(duration / length(CONDITIONS), 2), "minutes\n\n")

# Stop cluster
stopCluster(cl)
cat("Cluster stopped.\n\n")

################################################################################
### AGGREGATE RESULTS
################################################################################

cat("====================================================================\n")
cat("AGGREGATING RESULTS\n")
cat("====================================================================\n\n")

# Count successes and failures
n_success <- sum(sapply(all_condition_results, function(x) x$success))
n_failed <- length(all_condition_results) - n_success

cat("Successful conditions:", n_success, "\n")
cat("Failed conditions:", n_failed, "\n\n")

if (n_failed > 0) {
  cat("Failed conditions:\n")
  for (result in all_condition_results) {
    if (!result$success) {
      cat("  Condition", result$condition_id, ":", result$error, "\n")
    }
  }
  cat("\n")
}

# Extract all results into single data.table
all_results <- list()
result_counter <- 0

for (condition_result in all_condition_results) {
  if (condition_result$success) {
    # Combine all family results for this condition
    for (family_result in condition_result$results) {
      result_counter <- result_counter + 1
      all_results[[result_counter]] <- family_result
    }
  }
}

if (length(all_results) == 0) {
  stop("No results to compile. Check data availability and error messages.")
}

# Combine into single data.table
results_dt <- rbindlist(all_results)

# Calculate best family for each condition
# NOTE: Within a single dataset run, condition_id is unique, so we only need to group by condition_id here.
# Multi-dataset aggregation (grouping by dataset_id + condition_id) happens later in phase1_analysis.R
# when results from all datasets are combined.
results_dt[, best_aic := family[which.min(aic)], by = condition_id]
results_dt[, best_bic := family[which.min(bic)], by = condition_id]

# Calculate delta from best
results_dt[, delta_aic_vs_best := aic - min(aic), by = condition_id]
results_dt[, delta_bic_vs_best := bic - min(bic), by = condition_id]

# Sort by condition and AIC
setorder(results_dt, condition_id, aic)

################################################################################
### ADD DATASET METADATA TO RESULTS
################################################################################

# Add dataset metadata columns for multi-dataset combining
if (exists("current_dataset", envir = .GlobalEnv) && !is.null(current_dataset)) {
  cat("\n")
  cat("====================================================================\n")
  cat("ADDING DATASET METADATA TO RESULTS\n")
  cat("====================================================================\n\n")
  
  results_dt[, dataset_id := current_dataset$id]
  results_dt[, dataset_name := current_dataset$name]
  results_dt[, anonymized_state := current_dataset$anonymized_state]
  
  cat("✓ Added dataset metadata:\n")
  cat("  Dataset ID:", current_dataset$id, "\n")
  cat("  Dataset name:", current_dataset$name, "\n")
  cat("  Anonymized state:", current_dataset$anonymized_state, "\n")
  cat("  Rows:", nrow(results_dt), "\n\n")
} else {
  cat("\n⚠ Warning: current_dataset not found, skipping metadata enrichment\n\n")
}

# Save full results to dataset-specific directory
if (exists("current_dataset", envir = .GlobalEnv) && !is.null(current_dataset$id)) {
  dataset_results_dir <- paste0("STEP_1_Family_Selection/results/", current_dataset$id)
  dir.create(dataset_results_dir, showWarnings = FALSE, recursive = TRUE)
  output_file <- paste0(dataset_results_dir, "/phase1_copula_family_comparison.csv")
} else {
  # Fallback to root results directory
  dir.create("STEP_1_Family_Selection/results", showWarnings = FALSE, recursive = TRUE)
  output_file <- "STEP_1_Family_Selection/results/phase1_copula_family_comparison.csv"
}
fwrite(results_dt, output_file)

cat("Results saved to:", output_file, "\n")
cat("Total conditions tested:", uniqueN(results_dt$condition_id), "\n")
cat("Total copula fits:", nrow(results_dt), "\n\n")

# Quick summary
cat("====================================================================\n")
cat("QUICK SUMMARY\n")
cat("====================================================================\n\n")

family_selection <- results_dt[aic == min(aic), .N, by = .(family)]
setorder(family_selection, -N)

cat("Family selection frequency (by AIC):\n")
print(family_selection)

cat("\n\nMean AIC by family:\n")
mean_aic <- results_dt[, .(mean_aic = mean(aic), sd_aic = sd(aic)), by = family]
setorder(mean_aic, mean_aic)
print(mean_aic)

cat("\n\nPhase 1 complete! Proceed to phase1_analysis.R for detailed analysis.\n")
cat("====================================================================\n\n")

###############################################################################
# ADD RESULTS TO ACCUMULATION LIST (FOR MULTI-DATASET COMBINING)
###############################################################################

cat("====================================================================\n")
cat("ADDING RESULTS TO ACCUMULATION LIST\n")
cat("====================================================================\n\n")

# Store in global list (accessed by master_analysis.R)
if (!exists("ALL_DATASET_RESULTS", envir = .GlobalEnv)) {
  stop("ERROR: ALL_DATASET_RESULTS not found in global environment. Must be created by master_analysis.R")
}

# Append to step1 results list using dataset_idx
if (!exists("dataset_idx", envir = .GlobalEnv)) {
  stop("ERROR: dataset_idx not found in global environment. Must be set by master_analysis.R")
}

dataset_idx_char <- as.character(dataset_idx)
# Directly assign to .GlobalEnv to avoid <<- operator issues
.GlobalEnv$ALL_DATASET_RESULTS$step1[[dataset_idx_char]] <- results_dt

cat("✓ Results stored for dataset", dataset_idx, "\n")
if (exists("CURRENT_DATASET_NAME")) {
  cat("  Dataset name:", CURRENT_DATASET_NAME, "\n")
}
cat("  Dataset ID:", if (exists("current_dataset", envir = .GlobalEnv)) current_dataset$id else "unknown", "\n")
cat("  Total unique conditions:", uniqueN(results_dt$condition_id), "\n")
cat("  Total copula families tested:", length(COPULA_FAMILIES), "\n")
cat("  Expected rows:", uniqueN(results_dt$condition_id), "×", length(COPULA_FAMILIES), "=", 
    uniqueN(results_dt$condition_id) * length(COPULA_FAMILIES), "\n")
cat("  Actual rows:", nrow(results_dt), "\n")
if (nrow(results_dt) != uniqueN(results_dt$condition_id) * length(COPULA_FAMILIES)) {
  cat("  ⚠ WARNING: Row count mismatch!\n")
}
cat("  Columns:", ncol(results_dt), "\n")
cat("  Condition type:", if (USE_EXHAUSTIVE_CONDITIONS) "EXHAUSTIVE" else "STRATEGIC SUBSET", "\n\n")

cat("Results will be combined with other datasets after all datasets complete.\n")
cat("Combined file: STEP_1_Family_Selection/results/dataset_all/phase1_copula_family_comparison_all_datasets.csv\n\n")
