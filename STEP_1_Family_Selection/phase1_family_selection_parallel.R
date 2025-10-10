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
n_cores_use <- min(n_cores_available - 1, 15)  # Leave 1 for system
cat("Available cores:", n_cores_available, "\n")
cat("Using cores:", n_cores_use, "\n\n")

# Initialize cluster (PSOCK works on all platforms)
cl <- makeCluster(n_cores_use, type = "PSOCK")

cat("Exporting data and functions to cluster workers...\n")

# Export data and configuration to all workers
clusterExport(cl, c("STATE_DATA_LONG", "WORKSPACE_OBJECT_NAME", "get_state_data"), envir = .GlobalEnv)

# Load packages on each worker
clusterEvalQ(cl, {
  require(data.table)
  require(splines2)
  require(copula)
})

# Source function files on each worker
clusterEvalQ(cl, {
  source("functions/longitudinal_pairs.R")
  source("functions/ispline_ecdf.R")
  source("functions/copula_bootstrap.R")
})

cat("Cluster initialized successfully.\n\n")

################################################################################
### CONFIGURATION
################################################################################

COPULA_FAMILIES <- c("gaussian", "t", "clayton", "gumbel", "frank")

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
      use_empirical_ranks = TRUE  # Phase 1: Use ranks to avoid I-spline distortion
    )
    
    # Extract results for each family
    family_results <- list()
    
    for (family in copula_families) {
      
      if (!is.null(copula_fits$results[[family]])) {
        
        fit <- copula_fits$results[[family]]
        
        # Calculate tail dependence
        if (family == "t" && length(fit$parameter) >= 2) {
          rho <- fit$parameter[1]
          df <- fit$parameter[2]
          tail_dep <- 2 * pt(-sqrt((df + 1) * (1 - rho) / (1 + rho)), df = df + 1)
          tail_dep_lower <- tail_dep
          tail_dep_upper <- tail_dep
        } else if (family == "clayton") {
          theta <- fit$parameter[1]
          tail_dep_lower <- 2^(-1/theta)
          tail_dep_upper <- 0
        } else if (family == "gumbel") {
          theta <- fit$parameter[1]
          tail_dep_lower <- 0
          tail_dep_upper <- 2 - 2^(1/theta)
        } else {
          tail_dep_lower <- 0
          tail_dep_upper <- 0
        }
        
        family_results[[family]] <- data.table(
          condition_id = i,
          grade_span = cond$span,
          grade_prior = cond$grade_prior,
          grade_current = cond$grade_current,
          content_area = cond$content,
          cohort_year = cond$year_prior,
          n_pairs = n_pairs,
          
          family = family,
          aic = fit$aic,
          bic = fit$bic,
          loglik = fit$loglik,
          tau = fit$kendall_tau,
          tail_dep_lower = tail_dep_lower,
          tail_dep_upper = tail_dep_upper,
          
          parameter_1 = fit$parameter[1],
          parameter_2 = ifelse(length(fit$parameter) >= 2, fit$parameter[2], NA)
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
clusterExport(cl, c("process_condition", "CONDITIONS", "COPULA_FAMILIES"), envir = environment())

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
results_dt[, best_aic := family[which.min(aic)], by = condition_id]
results_dt[, best_bic := family[which.min(bic)], by = condition_id]

# Calculate delta from best
results_dt[, delta_aic_vs_best := aic - min(aic), by = condition_id]
results_dt[, delta_bic_vs_best := bic - min(bic), by = condition_id]

# Sort by condition and AIC
setorder(results_dt, condition_id, aic)

# Save full results
output_file <- "STEP_1_Family_Selection/results/phase1_copula_family_comparison.csv"
dir.create("STEP_1_Family_Selection/results", showWarnings = FALSE, recursive = TRUE)
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
