############################################################################
### EXPERIMENT 6: OPERATIONAL FITNESS TESTING
### Tests computational performance and inversion accuracy of transformation
### methods that pass statistical validation
###
### USAGE: source("STEP_2_Transformation_Validation/exp_6_operational_fitness.R")
###        (from workspace root)
############################################################################

require(data.table)
require(microbenchmark)

# Determine if we're in workspace root or STEP_2 directory
if (file.exists("functions/transformation_diagnostics.R")) {
  # We're in workspace root
  source("functions/transformation_diagnostics.R")
  source("functions/ispline_ecdf.R")
} else if (file.exists("../functions/transformation_diagnostics.R")) {
  # We're in STEP_2_Transformation_Validation directory
  source("../functions/transformation_diagnostics.R")
  source("../functions/ispline_ecdf.R")
} else {
  stop("Cannot find functions directory. Please run from workspace root or STEP_2_Transformation_Validation directory.")
}

cat("====================================================================\n")
cat("EXPERIMENT 6: OPERATIONAL FITNESS TESTING (Step 2.5)\n")
cat("Testing computational performance and robustness\n")
cat("====================================================================\n\n")

################################################################################
### OPERATIONAL FITNESS FUNCTIONS
################################################################################

#' Test operational fitness of transformation methods
#' 
#' Evaluates:
#' 1. Forward evaluation speed (F(x))
#' 2. Inverse evaluation speed (F^{-1}(p))
#' 3. Inversion accuracy (round-trip error)
#' 4. Robustness (failure rate on edge cases)
#' 5. Memory footprint
#' 
#' @param method_fits List of fitted transformation methods
#' @param test_scores Sample scores for testing
#' @param n_calls_forward Number of forward evaluations for timing (default: 1e5)
#' @param n_calls_inverse Number of inverse evaluations for timing (default: 1e5)
#' @param n_roundtrip Number of round-trip tests (default: 1000)
#' 
#' @return data.table with performance metrics
test_operational_fitness <- function(method_fits, 
                                     test_scores,
                                     n_calls_forward = 1e5,
                                     n_calls_inverse = 1e5,
                                     n_roundtrip = 1000) {
  
  results_list <- list()
  
  for (method_name in names(method_fits)) {
    
    cat("\n----------------------------------------------------------\n")
    cat("Testing:", method_name, "\n")
    cat("----------------------------------------------------------\n")
    
    method_fit <- method_fits[[method_name]]
    
    # Extract F and F_inv functions (method-specific)
    if ("F" %in% names(method_fit)) {
      F_fun <- method_fit$F
      F_inv_fun <- method_fit$F_inv
    } else if ("cdf_function" %in% names(method_fit)) {
      F_fun <- method_fit$cdf_function
      F_inv_fun <- method_fit$quantile_function
    } else if ("smooth_ecdf_full" %in% names(method_fit)) {
      F_fun <- method_fit$smooth_ecdf_full
      F_inv_fun <- method_fit$smooth_quantile_full
    } else {
      cat("  WARNING: Cannot extract F/F_inv functions, skipping\n")
      next
    }
    
    # 1. FORWARD EVALUATION SPEED
    cat("  Testing forward speed...\n")
    test_x <- sample(test_scores, size = min(n_calls_forward, length(test_scores)), replace = TRUE)
    
    time_forward <- tryCatch({
      system.time({
        U <- F_fun(test_x)
      })[3]  # Elapsed time
    }, error = function(e) {
      cat("    ERROR in forward evaluation:", e$message, "\n")
      NA
    })
    
    speed_forward <- if (!is.na(time_forward) && time_forward > 0) {
      length(test_x) / time_forward
    } else {
      NA
    }
    
    cat(sprintf("    Forward: %.0f calls/sec\n", speed_forward))
    
    # 2. INVERSE EVALUATION SPEED
    cat("  Testing inverse speed...\n")
    test_p <- runif(min(n_calls_inverse, 1e5))
    
    time_inverse <- tryCatch({
      system.time({
        X <- F_inv_fun(test_p)
      })[3]
    }, error = function(e) {
      cat("    ERROR in inverse evaluation:", e$message, "\n")
      NA
    })
    
    speed_inverse <- if (!is.na(time_inverse) && time_inverse > 0) {
      length(test_p) / time_inverse
    } else {
      NA
    }
    
    cat(sprintf("    Inverse: %.0f calls/sec\n", speed_inverse))
    
    # 3. INVERSION ACCURACY (round-trip error)
    cat("  Testing inversion accuracy...\n")
    test_sample <- sample(test_scores, size = min(n_roundtrip, length(test_scores)))
    
    roundtrip_results <- tryCatch({
      # Forward: x -> p
      U_forward <- F_fun(test_sample)
      
      # Inverse: p -> x
      X_roundtrip <- F_inv_fun(U_forward)
      
      # Compute errors
      errors <- abs(X_roundtrip - test_sample)
      list(
        mae = mean(errors, na.rm = TRUE),
        rmse = sqrt(mean(errors^2, na.rm = TRUE)),
        max_error = max(errors, na.rm = TRUE),
        failures = sum(is.na(X_roundtrip) | is.infinite(X_roundtrip)),
        success_rate = sum(!is.na(X_roundtrip) & !is.infinite(X_roundtrip)) / length(X_roundtrip)
      )
    }, error = function(e) {
      cat("    ERROR in round-trip test:", e$message, "\n")
      list(mae = NA, rmse = NA, max_error = NA, failures = NA, success_rate = 0)
    })
    
    cat(sprintf("    MAE: %.6f\n", roundtrip_results$mae))
    cat(sprintf("    RMSE: %.6f\n", roundtrip_results$rmse))
    cat(sprintf("    Max error: %.6f\n", roundtrip_results$max_error))
    cat(sprintf("    Failures: %d / %d (%.1f%%)\n", 
                roundtrip_results$failures, 
                n_roundtrip,
                (roundtrip_results$failures / n_roundtrip) * 100))
    
    # 4. EDGE CASE ROBUSTNESS
    cat("  Testing edge cases...\n")
    edge_cases <- c(
      min(test_scores),
      max(test_scores),
      quantile(test_scores, probs = c(0.001, 0.01, 0.5, 0.99, 0.999))
    )
    
    edge_results <- tryCatch({
      U_edge <- F_fun(edge_cases)
      X_edge <- F_inv_fun(U_edge)
      
      list(
        boundary_ok = all(!is.na(U_edge)) && 
                     all(U_edge >= 0) && 
                     all(U_edge <= 1) &&
                     all(!is.na(X_edge)),
        min_F = min(U_edge, na.rm = TRUE),
        max_F = max(U_edge, na.rm = TRUE)
      )
    }, error = function(e) {
      cat("    ERROR in edge case test:", e$message, "\n")
      list(boundary_ok = FALSE, min_F = NA, max_F = NA)
    })
    
    cat(sprintf("    Edge cases: %s\n", 
                ifelse(edge_results$boundary_ok, "PASS", "FAIL")))
    
    # 5. MEMORY FOOTPRINT
    memory_bytes <- object.size(method_fit)
    memory_mb <- as.numeric(memory_bytes) / 1024^2
    
    cat(sprintf("    Memory: %.2f MB\n", memory_mb))
    
    # Store results
    results_list[[method_name]] <- data.table(
      method = method_name,
      speed_forward_per_sec = speed_forward,
      speed_inverse_per_sec = speed_inverse,
      inversion_mae = roundtrip_results$mae,
      inversion_rmse = roundtrip_results$rmse,
      inversion_max_error = roundtrip_results$max_error,
      inversion_failures = roundtrip_results$failures,
      inversion_success_rate = roundtrip_results$success_rate,
      edge_cases_ok = edge_results$boundary_ok,
      memory_mb = memory_mb
    )
  }
  
  # Combine results
  results_dt <- rbindlist(results_list)
  
  return(results_dt)
}


#' Grade operational fitness (Pass/Warning/Fail)
#' 
#' Criteria:
#' - Forward speed > 10k/sec (typical simulation needs)
#' - Inverse speed > 1k/sec
#' - Inversion MAE < 0.01 × score_range
#' - Inversion failures = 0
#' - Memory < 100 MB
#' - Edge cases pass
#' 
#' @param fitness_results data.table from test_operational_fitness()
#' @param score_range Range of scores (max - min)
#' 
#' @return data.table with grades added
grade_operational_fitness <- function(fitness_results, score_range = 1000) {
  
  fitness_results[, grade := "PASS"]
  
  # Speed criteria
  fitness_results[speed_forward_per_sec < 10000, grade := "WARNING"]
  fitness_results[speed_inverse_per_sec < 1000, grade := "WARNING"]
  fitness_results[is.na(speed_forward_per_sec) | is.na(speed_inverse_per_sec), grade := "FAIL"]
  
  # Accuracy criteria (MAE < 1% of score range)
  mae_threshold <- 0.01 * score_range
  fitness_results[inversion_mae > mae_threshold, grade := "FAIL"]
  fitness_results[is.na(inversion_mae), grade := "FAIL"]
  
  # Robustness criteria
  fitness_results[inversion_failures > 0, grade := "FAIL"]
  fitness_results[!edge_cases_ok, grade := "FAIL"]
  fitness_results[inversion_success_rate < 0.99, grade := "FAIL"]
  
  # Memory criteria (warning only)
  fitness_results[memory_mb > 100, 
                 grade := ifelse(grade == "PASS", "WARNING", grade)]
  
  # Add detailed flags
  fitness_results[, `:=`(
    flag_slow_forward = speed_forward_per_sec < 10000,
    flag_slow_inverse = speed_inverse_per_sec < 1000,
    flag_inaccurate = inversion_mae > mae_threshold,
    flag_failures = inversion_failures > 0,
    flag_edge_cases = !edge_cases_ok,
    flag_memory = memory_mb > 100
  )]
  
  return(fitness_results)
}


#' Create summary report
#' 
#' @param fitness_graded data.table with grades
#' 
#' @return Character vector with formatted report
create_fitness_report <- function(fitness_graded) {
  
  report <- c(
    "====================================================================",
    "OPERATIONAL FITNESS TEST RESULTS",
    "====================================================================",
    "",
    "SUMMARY BY GRADE:",
    sprintf("  PASS:    %d methods", sum(fitness_graded$grade == "PASS")),
    sprintf("  WARNING: %d methods", sum(fitness_graded$grade == "WARNING")),
    sprintf("  FAIL:    %d methods", sum(fitness_graded$grade == "FAIL")),
    "",
    "====================================================================",
    ""
  )
  
  # Detail for each method
  for (i in 1:nrow(fitness_graded)) {
    method <- fitness_graded[i, ]
    
    report <- c(report,
      sprintf("METHOD: %s", method$method),
      sprintf("  Grade: %s", method$grade),
      "",
      "  Performance:",
      sprintf("    Forward:  %s calls/sec %s",
              format(method$speed_forward_per_sec, big.mark = ",", scientific = FALSE),
              ifelse(method$flag_slow_forward, "[SLOW]", "")),
      sprintf("    Inverse:  %s calls/sec %s",
              format(method$speed_inverse_per_sec, big.mark = ",", scientific = FALSE),
              ifelse(method$flag_slow_inverse, "[SLOW]", "")),
      "",
      "  Accuracy:",
      sprintf("    MAE:      %.6f %s", 
              method$inversion_mae,
              ifelse(method$flag_inaccurate, "[INACCURATE]", "")),
      sprintf("    RMSE:     %.6f", method$inversion_rmse),
      sprintf("    Max err:  %.6f", method$inversion_max_error),
      "",
      "  Robustness:",
      sprintf("    Failures: %d %s", 
              method$inversion_failures,
              ifelse(method$flag_failures, "[FAILURES DETECTED]", "")),
      sprintf("    Success:  %.1f%%", method$inversion_success_rate * 100),
      sprintf("    Edges:    %s %s",
              ifelse(method$edge_cases_ok, "PASS", "FAIL"),
              ifelse(method$flag_edge_cases, "[EDGE CASE FAILURES]", "")),
      "",
      "  Memory:",
      sprintf("    %.2f MB %s", 
              method$memory_mb,
              ifelse(method$flag_memory, "[LARGE]", "")),
      "",
      "--------------------------------------------------------------------",
      ""
    )
  }
  
  return(report)
}


################################################################################
### MAIN EXECUTION
################################################################################

if (interactive() || !exists("SKIP_EXP6_EXECUTION")) {
  
  cat("\n")
  cat("Loading data...\n")
  
  # Load sample data for testing
  # In production, this would come from master_analysis.R
  if (!exists("STATE_DATA_LONG")) {
    if (file.exists("../data/anonymized_sample_data.RData")) {
      load("../data/anonymized_sample_data.RData")
    } else {
      cat("WARNING: No data found. Using simulated data for demonstration.\n")
      set.seed(42)
      STATE_DATA_LONG <- data.table(
        CONTENT = rep("MATHEMATICS", 2000),
        YEAR = rep("2010", 2000),
        GRADE_PRIOR = rep(4, 2000),
        GRADE_CURRENT = rep(5, 2000),
        SCALE_SCORE_PRIOR = rnorm(2000, mean = 500, sd = 100),
        SCALE_SCORE_CURRENT = rnorm(2000, mean = 510, sd = 100)
      )
    }
  }
  
  # Extract test case
  test_data <- STATE_DATA_LONG[
    CONTENT == "MATHEMATICS" & 
    YEAR == "2010" &
    GRADE_PRIOR == 4 &
    GRADE_CURRENT == 5
  ]
  
  test_scores_prior <- test_data$SCALE_SCORE_PRIOR[!is.na(test_data$SCALE_SCORE_PRIOR)]
  test_scores_current <- test_data$SCALE_SCORE_CURRENT[!is.na(test_data$SCALE_SCORE_CURRENT)]
  
  score_range <- max(test_scores_prior) - min(test_scores_prior)
  
  cat(sprintf("Test data: n = %d pairs\n", length(test_scores_prior)))
  cat(sprintf("Score range: [%.1f, %.1f] (range = %.1f)\n",
              min(test_scores_prior), max(test_scores_prior), score_range))
  
  # Fit candidate methods
  cat("\n")
  cat("Fitting transformation methods...\n")
  
  method_fits <- list()
  
  # I-spline (19 knots) - current best performer
  cat("  I-spline (19 knots)...\n")
  method_fits$ispline_19knots <- create_ispline_framework(
    test_scores_prior,
    knot_percentiles = seq(0.05, 0.95, 0.05)
  )
  
  # I-spline (49 knots) - high flexibility
  cat("  I-spline (49 knots)...\n")
  method_fits$ispline_49knots <- create_ispline_framework(
    test_scores_prior,
    knot_percentiles = seq(0.02, 0.98, 0.02)
  )
  
  # Q-spline
  cat("  Q-spline...\n")
  method_fits$qspline <- fit_qspline(
    test_scores_prior,
    knot_probs = seq(0.1, 0.9, 0.1)
  )
  
  # Bernstein CDF
  cat("  Bernstein CDF...\n")
  if (file.exists("STEP_2_Transformation_Validation/methods/bernstein_cdf.R")) {
    source("STEP_2_Transformation_Validation/methods/bernstein_cdf.R")
  } else {
    source("methods/bernstein_cdf.R")
  }
  method_fits$bernstein <- fit_bernstein_cdf(
    test_scores_prior,
    degree = NULL,  # Auto-tune
    tune_by_cv = TRUE
  )
  
  # Kernel smoothing
  cat("  Kernel (Gaussian)...\n")
  bw <- bw.nrd0(test_scores_prior)
  kernel_cdf <- function(x, data = test_scores_prior, bandwidth = bw) {
    sapply(x, function(xi) mean(pnorm((xi - data) / bandwidth)))
  }
  kernel_quantile <- function(p, data = test_scores_prior, bandwidth = bw) {
    sapply(p, function(pi) {
      uniroot(function(x) kernel_cdf(x, data, bandwidth) - pi,
              interval = range(data) + c(-3*bandwidth, 3*bandwidth),
              tol = 1e-6)$root
    })
  }
  method_fits$kernel <- list(
    method = "kernel",
    F = kernel_cdf,
    F_inv = kernel_quantile,
    bandwidth = bw
  )
  
  cat("\n")
  cat("====================================================================\n")
  cat("RUNNING OPERATIONAL FITNESS TESTS\n")
  cat("====================================================================\n")
  
  # Test operational fitness
  fitness_results <- test_operational_fitness(
    method_fits = method_fits,
    test_scores = test_scores_prior,
    n_calls_forward = 1e5,
    n_calls_inverse = 1e5,
    n_roundtrip = 1000
  )
  
  # Grade results
  fitness_graded <- grade_operational_fitness(fitness_results, score_range)
  
  # Create report
  cat("\n\n")
  fitness_report <- create_fitness_report(fitness_graded)
  cat(paste(fitness_report, collapse = "\n"))
  
  # Save results
  cat("\n")
  cat("Saving results...\n")
  
  if (!dir.exists("results")) dir.create("results")
  
  fwrite(fitness_graded, "results/exp6_operational_fitness.csv")
  writeLines(fitness_report, "results/exp6_operational_fitness_report.txt")
  save(fitness_results, fitness_graded, fitness_report,
       file = "results/exp6_operational_fitness.RData")
  
  cat("  CSV:    results/exp6_operational_fitness.csv\n")
  cat("  Report: results/exp6_operational_fitness_report.txt\n")
  cat("  RData:  results/exp6_operational_fitness.RData\n")
  
  cat("\n")
  cat("====================================================================\n")
  cat("OPERATIONAL FITNESS TESTING COMPLETE\n")
  cat("====================================================================\n")
}
