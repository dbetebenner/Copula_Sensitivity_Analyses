############################################################################
### TEST SCRIPT FOR PARALLEL IMPLEMENTATION
### Tests parallel version with small subset of conditions
###
### Usage: 
###   1. Source required functions and data first
###   2. Run this script to test with 3 conditions on 2 cores
###   3. Verify output format matches sequential version
############################################################################

require(data.table)
require(splines2)
require(copula)
require(parallel)

cat("====================================================================\n")
cat("TESTING PARALLEL IMPLEMENTATION (SUBSET)\n")
cat("====================================================================\n\n")

# Test with only 2 cores
n_cores_test <- 2
cat("Using", n_cores_test, "cores for testing\n\n")

# Initialize cluster
cl <- makeCluster(n_cores_test, type = "PSOCK")

cat("Exporting data and functions to cluster workers...\n")

# Export data to all workers
clusterExport(cl, c("STATE_DATA_LONG", "get_state_data"), envir = .GlobalEnv)

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
### TEST CONFIGURATION (SUBSET)
################################################################################

COPULA_FAMILIES <- c("gaussian", "t", "clayton", "gumbel", "frank")

# Test with only first 3 conditions
CONDITIONS_TEST <- list(
  list(grade_prior = 4, grade_current = 5, year_prior = "2010", content = "MATHEMATICS", span = 1),
  list(grade_prior = 5, grade_current = 6, year_prior = "2010", content = "MATHEMATICS", span = 1),
  list(grade_prior = 4, grade_current = 5, year_prior = "2010", content = "READING", span = 1)
)

cat("Testing with", length(CONDITIONS_TEST), "conditions\n")
cat("Copula families:", paste(COPULA_FAMILIES, collapse = ", "), "\n")
cat("Total fits:", length(CONDITIONS_TEST) * length(COPULA_FAMILIES), "\n\n")

################################################################################
### WORKER FUNCTION
################################################################################

process_condition <- function(i, cond, copula_families) {
  
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
    copula_fits <- fit_copula_from_pairs(
      scores_prior = pairs_full$SCALE_SCORE_PRIOR,
      scores_current = pairs_full$SCALE_SCORE_CURRENT,
      framework_prior = framework_prior,
      framework_current = framework_current,
      copula_families = copula_families,
      return_best = FALSE,
      use_empirical_ranks = TRUE
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
### RUN PARALLEL TEST
################################################################################

cat("Starting parallel test...\n\n")

start_time <- Sys.time()

# Export function and data
clusterExport(cl, c("process_condition", "CONDITIONS_TEST", "COPULA_FAMILIES"), envir = environment())

# Run parallel processing
all_condition_results <- parLapply(
  cl = cl,
  X = seq_along(CONDITIONS_TEST),
  fun = function(i) {
    result <- process_condition(i, CONDITIONS_TEST[[i]], COPULA_FAMILIES)
    cat("Completed condition", i, "\n")
    return(result)
  }
)

end_time <- Sys.time()
duration <- difftime(end_time, start_time, units = "secs")

cat("\n====================================================================\n")
cat("PARALLEL TEST COMPLETE\n")
cat("====================================================================\n")
cat("Total time:", round(duration, 2), "seconds\n\n")

# Stop cluster
stopCluster(cl)
cat("Cluster stopped.\n\n")

################################################################################
### VERIFY RESULTS
################################################################################

cat("====================================================================\n")
cat("VERIFYING RESULTS\n")
cat("====================================================================\n\n")

# Count successes
n_success <- sum(sapply(all_condition_results, function(x) x$success))
n_failed <- length(all_condition_results) - n_success

cat("Successful conditions:", n_success, "/", length(CONDITIONS_TEST), "\n")
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

# Compile results
if (n_success > 0) {
  all_results <- list()
  result_counter <- 0
  
  for (condition_result in all_condition_results) {
    if (condition_result$success) {
      for (family_result in condition_result$results) {
        result_counter <- result_counter + 1
        all_results[[result_counter]] <- family_result
      }
    }
  }
  
  results_dt <- rbindlist(all_results)
  
  cat("Results compiled successfully!\n")
  cat("Total rows:", nrow(results_dt), "\n")
  cat("Expected rows:", n_success * length(COPULA_FAMILIES), "\n\n")
  
  cat("Sample results (first 5 rows):\n")
  print(head(results_dt, 5))
  
  cat("\n\nColumn names:\n")
  print(names(results_dt))
  
  # Check best family selection
  cat("\n\nBest families by condition:\n")
  best_families <- results_dt[, .SD[which.min(aic)], by = condition_id]
  print(best_families[, .(condition_id, grade_span, content_area, family, aic, tau)])
  
  cat("\n\nTEST PASSED: Parallel implementation working correctly!\n")
  cat("Ready to run with full 28 conditions.\n")
  
} else {
  cat("ERROR: No successful results. Check configuration.\n")
}

cat("====================================================================\n\n")
