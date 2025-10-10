############################################################################
### EXPERIMENT 5: TRANSFORMATION METHOD VALIDATION (PARALLEL VERSION)
### Parallelized evaluation of marginal transformation methods
###
### This is the METHODOLOGICAL CENTERPIECE of the investigation
###
### Parallelization Strategy:
###   - Uses parallel package (base R, no extra dependencies)
###   - Each transformation method processed independently on separate cores
###   - Expected speedup: 8-10x on high-performance machines
###   - Target runtime: 4-6 minutes (vs 40-60 minutes sequential)
############################################################################

# Load libraries
require(data.table)
require(splines2)
require(copula)
require(grid)
require(parallel)

cat("====================================================================\n")
cat("EXPERIMENT 5: TRANSFORMATION METHOD VALIDATION (PARALLEL)\n")
cat("====================================================================\n")

# Detect cores and set up cluster
n_cores_available <- detectCores()
n_cores_use <- if (exists("N_CORES")) {
  min(N_CORES, 15)  # Use global N_CORES if available, cap at 15
} else {
  min(n_cores_available - 2, 15)  # Otherwise leave 2 for system
}

cat("Using", n_cores_use, "of", n_cores_available, "cores\n")
cat("Expected runtime: 4-6 minutes (vs 40-60 min sequential)\n\n")

# Initialize cluster (PSOCK works on all platforms)
cl <- makeCluster(n_cores_use, type = "PSOCK")

cat("Cluster initialized successfully.\n\n")

################################################################################
### CONFIGURATION
################################################################################

CONFIG <- list(
  # Primary test case
  grade_prior = 4,
  grade_current = 5,
  year_prior = "2010",
  content = "MATHEMATICS"
)

# All transformation methods to test
TRANSFORMATION_METHODS <- list(
  
  # GROUP A: EMPIRICAL BASELINE (GOLD STANDARD)
  list(name = "empirical_n_plus_1", 
       label = "Empirical Ranks (n+1)", 
       type = "empirical",
       params = list(denominator = "n_plus_1")),
  
  list(name = "empirical_n", 
       label = "Empirical Ranks (n)", 
       type = "empirical",
       params = list(denominator = "n")),
  
  list(name = "mid_ranks", 
       label = "Mid-Ranks", 
       type = "midrank",
       params = list()),
  
  # GROUP B: I-SPLINE VARIATIONS (FIND BREAKING POINT)
  list(name = "ispline_4knots", 
       label = "I-spline (4 knots) [KNOWN BAD]", 
       type = "ispline",
       params = list(knot_percentiles = c(0.20, 0.40, 0.60, 0.80))),
  
  list(name = "ispline_9knots", 
       label = "I-spline (9 knots) [Current Default]", 
       type = "ispline",
       params = list(knot_percentiles = seq(0.1, 0.9, 0.1))),
  
  list(name = "ispline_19knots", 
       label = "I-spline (19 knots)", 
       type = "ispline",
       params = list(knot_percentiles = seq(0.05, 0.95, 0.05))),
  
  list(name = "ispline_49knots", 
       label = "I-spline (49 knots)", 
       type = "ispline",
       params = list(knot_percentiles = seq(0.02, 0.98, 0.02))),
  
  list(name = "ispline_tail_aware_4core", 
       label = "I-spline (Tail-Aware, 4 core + 6 tail)", 
       type = "ispline_tail",
       params = list(knot_percentiles = c(0.20, 0.40, 0.60, 0.80), 
                    tail_aware = TRUE)),
  
  list(name = "ispline_tail_aware_9core", 
       label = "I-spline (Tail-Aware, 9 core + 6 tail)", 
       type = "ispline_tail",
       params = list(knot_percentiles = seq(0.1, 0.9, 0.1), 
                    tail_aware = TRUE)),
  
  # GROUP C: ALTERNATIVE SPLINE METHODS
  list(name = "qspline", 
       label = "Q-spline (Quantile Function)", 
       type = "qspline",
       params = list(knot_probs = seq(0.1, 0.9, 0.1))),
  
  list(name = "hyman", 
       label = "Hyman Monotone Cubic", 
       type = "hyman",
       params = list()),
  
  # GROUP D: NON-PARAMETRIC METHODS
  list(name = "kernel_gaussian", 
       label = "Kernel (Gaussian, rule-of-thumb)", 
       type = "kernel",
       params = list(kernel = "gaussian", bandwidth = "nrd0")),
  
  # GROUP E: PARAMETRIC BENCHMARKS (EXPECTED TO FAIL)
  list(name = "normal", 
       label = "Normal CDF [Benchmark]", 
       type = "parametric",
       params = list(distribution = "normal")),
  
  list(name = "logistic", 
       label = "Logistic CDF [Benchmark]", 
       type = "parametric",
       params = list(distribution = "logistic"))
)

COPULA_FAMILIES <- c("gaussian", "t", "clayton", "gumbel", "frank")

cat("Testing", length(TRANSFORMATION_METHODS), "transformation methods\n")
cat("Copula families:", paste(COPULA_FAMILIES, collapse = ", "), "\n\n")

################################################################################
### LOAD DATA AND FIT EMPIRICAL BASELINE (SEQUENTIAL - FAST)
################################################################################

cat("====================================================================\n")
cat("LOADING DATA\n")
cat("====================================================================\n\n")

# Create longitudinal pairs
pairs_full <- create_longitudinal_pairs(
  data = get_state_data(),
  grade_prior = CONFIG$grade_prior,
  grade_current = CONFIG$grade_current,
  year_prior = CONFIG$year_prior,
  content_prior = CONFIG$content,
  content_current = CONFIG$content
)

n_pairs <- nrow(pairs_full)
cat("Configuration:", CONFIG$content, "Grade", CONFIG$grade_prior, 
    "->", CONFIG$grade_current, "Cohort", CONFIG$year_prior, "\n")
cat("Longitudinal pairs:", n_pairs, "\n\n")

cat("====================================================================\n")
cat("FITTING EMPIRICAL BASELINE (GOLD STANDARD)\n")
cat("====================================================================\n\n")

# Empirical ranks (n+1 denominator) - GOLD STANDARD
U_empirical <- rank(pairs_full$SCALE_SCORE_PRIOR) / (n_pairs + 1)
V_empirical <- rank(pairs_full$SCALE_SCORE_CURRENT) / (n_pairs + 1)

# Compute all diagnostics for empirical
empirical_uniformity <- compute_uniformity_diagnostics(U_empirical, V_empirical)
empirical_dependence <- compute_dependence_diagnostics(U_empirical, V_empirical)
empirical_tail <- compute_tail_diagnostics(U_empirical, V_empirical)

cat("Empirical Baseline Diagnostics:\n")
cat(sprintf("  K-S test U: stat=%.4f, p=%.4f\n", 
            empirical_uniformity$ks_U_stat, empirical_uniformity$ks_U_pval))
cat(sprintf("  K-S test V: stat=%.4f, p=%.4f\n", 
            empirical_uniformity$ks_V_stat, empirical_uniformity$ks_V_pval))
cat(sprintf("  Kendall tau: %.4f\n", empirical_dependence$kendall_tau))
cat(sprintf("  Lower tail (10%%): %.4f\n", empirical_tail$lower_10))
cat(sprintf("  Upper tail (90%%): %.4f\n\n", empirical_tail$upper_90))

# Fit copulas to empirical ranks
cat("Fitting copulas to empirical ranks...\n")
empirical_copula_fits <- fit_copula_from_pairs(
  scores_prior = pairs_full$SCALE_SCORE_PRIOR,
  scores_current = pairs_full$SCALE_SCORE_CURRENT,
  framework_prior = NULL,
  framework_current = NULL,
  copula_families = COPULA_FAMILIES,
  return_best = FALSE,
  use_empirical_ranks = TRUE
)

empirical_best_family <- empirical_copula_fits$best_family
cat("Best copula family (empirical):", empirical_best_family, "\n")
cat("  AIC =", empirical_copula_fits$results[[empirical_best_family]]$aic, "\n\n")

# Store empirical baseline results
empirical_baseline <- list(
  uniformity = empirical_uniformity,
  dependence = empirical_dependence,
  tail = empirical_tail,
  copula_fits = empirical_copula_fits,
  best_family = empirical_best_family
)

################################################################################
### EXPORT DATA AND FUNCTIONS TO WORKERS
################################################################################

cat("====================================================================\n")
cat("PREPARING PARALLEL WORKERS\n")
cat("====================================================================\n\n")

cat("Exporting data and functions to cluster workers...\n")

# Export data to all workers
clusterExport(cl, c(
  "pairs_full", "n_pairs", "empirical_baseline", 
  "COPULA_FAMILIES", "CONFIG"
), envir = environment())

# Load packages and source functions on each worker
cat("Loading packages and functions on each worker...\n")
clusterEvalQ(cl, {
  require(data.table)
  require(splines2)
  require(copula)
  
  # Source all required function files (from project root)
  # Note: master_analysis.R sets working directory to project root
  source("functions/longitudinal_pairs.R")
  source("functions/ispline_ecdf.R")
  source("functions/copula_bootstrap.R")
  source("functions/transformation_diagnostics.R")
})

cat("Workers prepared successfully.\n")
cat("  ✓ Packages loaded on all workers\n")
cat("  ✓ Functions sourced on all workers\n\n")

################################################################################
### DEFINE WORKER FUNCTION
################################################################################

# Function to process a single transformation method (runs on each worker independently)
process_transformation_method <- function(method) {
  
  # This function runs on each worker independently
  # It must be self-contained and return a complete result
  
  tryCatch({
    
    ##########################################################################
    ### STEP 1: FIT TRANSFORMATION
    ##########################################################################
    
    if (method$type == "empirical") {
      # Empirical ranks
      if (method$params$denominator == "n_plus_1") {
        U <- rank(pairs_full$SCALE_SCORE_PRIOR) / (n_pairs + 1)
        V <- rank(pairs_full$SCALE_SCORE_CURRENT) / (n_pairs + 1)
      } else {
        U <- rank(pairs_full$SCALE_SCORE_PRIOR) / n_pairs
        V <- rank(pairs_full$SCALE_SCORE_CURRENT) / n_pairs
      }
      framework <- list(method = method$type)
      
    } else if (method$type == "midrank") {
      # Mid-ranks
      U <- (rank(pairs_full$SCALE_SCORE_PRIOR) - 0.5) / n_pairs
      V <- (rank(pairs_full$SCALE_SCORE_CURRENT) - 0.5) / n_pairs
      framework <- list(method = method$type)
      
    } else if (method$type == "ispline") {
      # Standard I-spline
      framework_prior <- create_ispline_framework(
        pairs_full$SCALE_SCORE_PRIOR,
        knot_percentiles = method$params$knot_percentiles
      )
      framework_current <- create_ispline_framework(
        pairs_full$SCALE_SCORE_CURRENT,
        knot_percentiles = method$params$knot_percentiles
      )
      U <- framework_prior$smooth_ecdf_full(pairs_full$SCALE_SCORE_PRIOR)
      V <- framework_current$smooth_ecdf_full(pairs_full$SCALE_SCORE_CURRENT)
      U <- pmax(1e-6, pmin(1 - 1e-6, U))
      V <- pmax(1e-6, pmin(1 - 1e-6, V))
      framework <- framework_prior
      
    } else if (method$type == "ispline_tail") {
      # Tail-aware I-spline
      framework_prior <- create_ispline_framework_enhanced(
        pairs_full$SCALE_SCORE_PRIOR,
        knot_percentiles = method$params$knot_percentiles,
        tail_aware = method$params$tail_aware
      )
      framework_current <- create_ispline_framework_enhanced(
        pairs_full$SCALE_SCORE_CURRENT,
        knot_percentiles = method$params$knot_percentiles,
        tail_aware = method$params$tail_aware
      )
      U <- framework_prior$smooth_ecdf_full(pairs_full$SCALE_SCORE_PRIOR)
      V <- framework_current$smooth_ecdf_full(pairs_full$SCALE_SCORE_CURRENT)
      U <- pmax(1e-6, pmin(1 - 1e-6, U))
      V <- pmax(1e-6, pmin(1 - 1e-6, V))
      framework <- framework_prior
      
    } else if (method$type == "qspline") {
      # Q-spline (quantile function)
      qspline_prior <- fit_qspline(
        pairs_full$SCALE_SCORE_PRIOR,
        knot_probs = method$params$knot_probs
      )
      qspline_current <- fit_qspline(
        pairs_full$SCALE_SCORE_CURRENT,
        knot_probs = method$params$knot_probs
      )
      U <- qspline_prior$cdf_function(pairs_full$SCALE_SCORE_PRIOR)
      V <- qspline_current$cdf_function(pairs_full$SCALE_SCORE_CURRENT)
      U <- pmax(1e-6, pmin(1 - 1e-6, U))
      V <- pmax(1e-6, pmin(1 - 1e-6, V))
      framework <- qspline_prior
      
    } else if (method$type == "hyman") {
      # Hyman monotone spline
      ecdf_prior <- ecdf(pairs_full$SCALE_SCORE_PRIOR)
      ecdf_current <- ecdf(pairs_full$SCALE_SCORE_CURRENT)
      x_prior <- sort(unique(pairs_full$SCALE_SCORE_PRIOR))
      x_current <- sort(unique(pairs_full$SCALE_SCORE_CURRENT))
      y_prior <- ecdf_prior(x_prior)
      y_current <- ecdf_current(x_current)
      
      spline_prior <- splinefun(x_prior, y_prior, method = "hyman")
      spline_current <- splinefun(x_current, y_current, method = "hyman")
      
      U <- spline_prior(pairs_full$SCALE_SCORE_PRIOR)
      V <- spline_current(pairs_full$SCALE_SCORE_CURRENT)
      U <- pmax(1e-6, pmin(1 - 1e-6, U))
      V <- pmax(1e-6, pmin(1 - 1e-6, V))
      framework <- list(method = "hyman")
      
    } else if (method$type == "kernel") {
      # Kernel smoothing
      kernel_cdf <- function(x, data, bw) {
        sapply(x, function(xi) mean(pnorm((xi - data) / bw)))
      }
      
      # Rule-of-thumb bandwidth
      bw_prior <- bw.nrd0(pairs_full$SCALE_SCORE_PRIOR)
      bw_current <- bw.nrd0(pairs_full$SCALE_SCORE_CURRENT)
      
      U <- kernel_cdf(pairs_full$SCALE_SCORE_PRIOR, 
                     pairs_full$SCALE_SCORE_PRIOR, bw_prior)
      V <- kernel_cdf(pairs_full$SCALE_SCORE_CURRENT, 
                     pairs_full$SCALE_SCORE_CURRENT, bw_current)
      U <- pmax(1e-6, pmin(1 - 1e-6, U))
      V <- pmax(1e-6, pmin(1 - 1e-6, V))
      framework <- list(method = "kernel")
      
    } else if (method$type == "parametric") {
      # Parametric CDF
      if (method$params$distribution == "normal") {
        mu_prior <- mean(pairs_full$SCALE_SCORE_PRIOR)
        sigma_prior <- sd(pairs_full$SCALE_SCORE_PRIOR)
        mu_current <- mean(pairs_full$SCALE_SCORE_CURRENT)
        sigma_current <- sd(pairs_full$SCALE_SCORE_CURRENT)
        
        U <- pnorm(pairs_full$SCALE_SCORE_PRIOR, mu_prior, sigma_prior)
        V <- pnorm(pairs_full$SCALE_SCORE_CURRENT, mu_current, sigma_current)
      } else if (method$params$distribution == "logistic") {
        mu_prior <- mean(pairs_full$SCALE_SCORE_PRIOR)
        s_prior <- sd(pairs_full$SCALE_SCORE_PRIOR) * sqrt(3) / pi
        mu_current <- mean(pairs_full$SCALE_SCORE_CURRENT)
        s_current <- sd(pairs_full$SCALE_SCORE_CURRENT) * sqrt(3) / pi
        
        U <- plogis(pairs_full$SCALE_SCORE_PRIOR, mu_prior, s_prior)
        V <- plogis(pairs_full$SCALE_SCORE_CURRENT, mu_current, s_current)
      }
      U <- pmax(1e-6, pmin(1 - 1e-6, U))
      V <- pmax(1e-6, pmin(1 - 1e-6, V))
      framework <- list(method = method$type)
      
    } else {
      stop("Unknown transformation type:", method$type)
    }
    
    ##########################################################################
    ### STEP 2: COMPUTE DIAGNOSTICS
    ##########################################################################
    
    uniformity <- compute_uniformity_diagnostics(U, V)
    dependence <- compute_dependence_diagnostics(U, V, empirical_baseline$dependence)
    tail <- compute_tail_diagnostics(U, V, empirical_baseline$tail)
    
    ##########################################################################
    ### STEP 3: FIT COPULAS
    ##########################################################################
    
    pseudo_obs <- cbind(U, V)
    
    copula_results <- list()
    for (fam in COPULA_FAMILIES) {
      fit_result <- tryCatch({
        if (fam == "gaussian") {
          cop <- normalCopula(dim = 2)
          fit <- fitCopula(cop, pseudo_obs, method = "ml")
          list(family = fam, aic = -2*fit@loglik + 2, 
               bic = -2*fit@loglik + log(n_pairs),
               loglik = fit@loglik)
        } else if (fam == "t") {
          cop <- tCopula(dim = 2, dispstr = "un")
          fit <- fitCopula(cop, pseudo_obs, method = "ml")
          list(family = fam, aic = -2*fit@loglik + 4, 
               bic = -2*fit@loglik + 2*log(n_pairs),
               loglik = fit@loglik)
        } else if (fam == "clayton") {
          cop <- claytonCopula(dim = 2)
          fit <- fitCopula(cop, pseudo_obs, method = "ml")
          list(family = fam, aic = -2*fit@loglik + 2, 
               bic = -2*fit@loglik + log(n_pairs),
               loglik = fit@loglik)
        } else if (fam == "gumbel") {
          cop <- gumbelCopula(dim = 2)
          fit <- fitCopula(cop, pseudo_obs, method = "ml")
          list(family = fam, aic = -2*fit@loglik + 2, 
               bic = -2*fit@loglik + log(n_pairs),
               loglik = fit@loglik)
        } else if (fam == "frank") {
          cop <- frankCopula(dim = 2)
          fit <- fitCopula(cop, pseudo_obs, method = "ml")
          list(family = fam, aic = -2*fit@loglik + 2, 
               bic = -2*fit@loglik + log(n_pairs),
               loglik = fit@loglik)
        }
      }, error = function(e) {
        list(family = fam, aic = NA, bic = NA, loglik = NA, error = e$message)
      })
      
      copula_results[[fam]] <- fit_result
    }
    
    # Find best copula by AIC
    aic_values <- sapply(copula_results, function(x) x$aic)
    best_copula_family <- names(which.min(aic_values))
    
    ##########################################################################
    ### STEP 4: CLASSIFY METHOD
    ##########################################################################
    
    # Build copula_results object in expected format for classification
    copula_summary <- list(
      best_family = best_copula_family,
      results = copula_results,
      aic_delta_from_empirical = aic_values[best_copula_family] - 
        empirical_baseline$copula_fits$results[[empirical_baseline$best_family]]$aic
    )
    
    classification_result <- classify_transformation_method(
      uniformity = uniformity,
      dependence = dependence,
      tail = tail,
      copula_results = copula_summary,
      empirical_best_family = empirical_baseline$best_family
    )
    
    ##########################################################################
    ### RETURN COMPLETE RESULTS
    ##########################################################################
    
    # Return structure matching sequential version for visualization compatibility
    return(list(
      method = method,
      uniformity = uniformity,
      dependence = dependence,
      tail = tail,
      copula_results = copula_summary,  # Use copula_summary (with best_family) not raw results
      classification = classification_result,  # Full classification object
      U = U,  # Include pseudo-observations for visualization
      V = V,
      success = TRUE
    ))
    
  }, error = function(e) {
    # Return error information
    return(list(
      method = method,
      error = e$message,
      success = FALSE
    ))
  })
}

################################################################################
### RUN PARALLEL PROCESSING
################################################################################

cat("====================================================================\n")
cat("TESTING ALL TRANSFORMATION METHODS (PARALLEL)\n")
cat("====================================================================\n\n")

cat("Processing", length(TRANSFORMATION_METHODS), "methods across", 
    n_cores_use, "cores...\n\n")

# Process all methods in parallel
start_time <- Sys.time()

all_results_raw <- parLapply(cl, TRANSFORMATION_METHODS, process_transformation_method)

end_time <- Sys.time()
runtime <- difftime(end_time, start_time, units = "mins")

# Stop cluster
stopCluster(cl)

cat("\n====================================================================\n")
cat("PARALLEL PROCESSING COMPLETE\n")
cat("====================================================================\n")
cat("Runtime:", round(runtime, 2), "minutes\n")
cat("Methods per minute:", round(length(TRANSFORMATION_METHODS) / as.numeric(runtime), 1), "\n\n")

################################################################################
### POST-PROCESSING RESULTS
################################################################################

cat("====================================================================\n")
cat("POST-PROCESSING RESULTS\n")
cat("====================================================================\n\n")

# Organize results
all_results <- list()
failed_methods <- character()

for (result in all_results_raw) {
  if (result$success) {
    all_results[[result$method$name]] <- result
  } else {
    failed_methods <- c(failed_methods, result$method$name)
    cat("Method", result$method$name, "failed:", result$error, "\n")
  }
}

cat("\nSuccessfully processed:", length(all_results), "methods\n")
cat("Failed:", length(failed_methods), "methods\n\n")

if (length(failed_methods) > 0) {
  cat("Failed methods:\n")
  for (m in failed_methods) {
    cat("  -", m, "\n")
  }
  cat("\n")
}

################################################################################
### SAVE RESULTS (SAME FORMAT AS SEQUENTIAL VERSION)
################################################################################

# Create summary table
summary_table <- rbindlist(lapply(names(all_results), function(method_name) {
  res <- all_results[[method_name]]
  data.table(
    method = res$method$name,
    label = res$method$label,
    type = res$method$type,
    classification = res$classification$classification,
    use_in_phase2 = res$classification$use_in_phase2,
    ks_pvalue = min(res$uniformity$ks_U_pval, res$uniformity$ks_V_pval),
    cvm_U = res$uniformity$cvm_U,
    cvm_V = res$uniformity$cvm_V,
    tau = res$dependence$kendall_tau,
    tau_bias = res$dependence$tau_bias,
    lower_10 = res$tail$lower_10,
    upper_90 = res$tail$upper_90,
    tail_dist_lower = res$tail$tail_distortion_lower,
    tail_dist_upper = res$tail$tail_distortion_upper,
    best_copula = res$copula_results$best_family,
    copula_correct = (res$copula_results$best_family == empirical_baseline$best_family),
    aic_delta = res$copula_results$aic_delta_from_empirical
  )
}))

# Save summary table (use full path from project root)
results_dir <- "STEP_2_Transformation_Validation/results"
if (!dir.exists(results_dir)) dir.create(results_dir, recursive = TRUE)

fwrite(summary_table, file.path(results_dir, "exp5_transformation_validation_summary.csv"))

# Save full results
save(
  all_results, 
  empirical_baseline, 
  summary_table,
  CONFIG,
  TRANSFORMATION_METHODS,
  COPULA_FAMILIES,
  n_pairs,
  runtime,
  file = file.path(results_dir, "exp5_transformation_validation_full.RData")
)

cat("Results saved to:\n")
cat("  -", file.path(results_dir, "exp5_transformation_validation_summary.csv"), "\n")
cat("  -", file.path(results_dir, "exp5_transformation_validation_full.RData"), "\n\n")

################################################################################
### PRINT SUMMARY
################################################################################

cat("====================================================================\n")
cat("RESULTS SUMMARY\n")
cat("====================================================================\n\n")

for (class in c("EXCELLENT", "ACCEPTABLE", "MARGINAL", "UNACCEPTABLE")) {
  methods_in_class <- summary_table[classification == class, label]
  if (length(methods_in_class) > 0) {
    cat(class, ":", length(methods_in_class), "methods\n")
    for (m in methods_in_class) {
      cat("  -", m, "\n")
    }
    cat("\n")
  }
}

# Phase 2 recommendations
cat("====================================================================\n")
cat("PHASE 2 RECOMMENDATIONS\n")
cat("====================================================================\n\n")

phase2_methods <- summary_table[use_in_phase2 == TRUE, label]
cat("The following", length(phase2_methods), "methods are SUITABLE for Phase 2:\n\n")
for (m in phase2_methods) {
  cat("  -", m, "\n")
}

if (length(phase2_methods) == 0) {
  cat("  WARNING: No methods passed all criteria!\n")
  cat("  Recommend using empirical ranks for all Phase 2+ analyses.\n")
}

cat("\n====================================================================\n")
cat("TRANSFORMATION VALIDATION COMPLETE\n")
cat("====================================================================\n\n")
