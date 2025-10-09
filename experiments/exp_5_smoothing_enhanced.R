############################################################################
### EXPERIMENT 5: SMOOTHING METHOD SENSITIVITY (ENHANCED)
### Enhanced version incorporating Q-splines, PIT-based selection,
### tail-aware knots, and comprehensive diagnostics
###
### Based on ChatGPT discussion in SPLINE_CONVERSATION_ChatGPT.md
############################################################################

# Load libraries and functions
require(data.table)
require(splines2)
require(copula)
require(grid)

# Load Colorado data
if (!exists("Colorado_Data_LONG")) {
  load("/Users/conet/SGP Dropbox/Damian Betebenner/Colorado/Data/Archive/February_2016/Colorado_Data_LONG.RData")
  Colorado_Data_LONG <- as.data.table(Colorado_Data_LONG)
}

# Source functions
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")
source("functions/copula_diagnostics.R")

cat("====================================================================\n")
cat("EXPERIMENT 5: SMOOTHING METHOD SENSITIVITY (ENHANCED)\n")
cat("Testing 9 smoothing approaches for ECDF transformation\n")
cat("====================================================================\n\n")

################################################################################
### LOAD PHASE 1 DECISION (if available)
################################################################################

if (file.exists("results/phase1_decision.RData")) {
  load("results/phase1_decision.RData")
  cat("====================================================================\n")
  cat("PHASE 2: Using families selected in Phase 1\n")
  cat("Families:", paste(phase2_families, collapse = ", "), "\n")
  cat("====================================================================\n\n")
  USE_PHASE2_FAMILIES <- TRUE
} else {
  cat("Note: Phase 1 decision not found. Using all copula families.\n\n")
  USE_PHASE2_FAMILIES <- FALSE
  phase2_families <- c("gaussian", "t", "clayton", "gumbel", "frank")
}

################################################################################
### CONFIGURATION
################################################################################

CONFIG <- list(
  grade_prior = 4,
  grade_current = 8,
  year_prior = "2009",
  content = "MATHEMATICS"
)

# 9 smoothing methods to test
SMOOTHING_METHODS <- list(
  # Original I-spline methods
  list(name = "ispline_4knots", label = "I-spline (4 knots)", type = "ispline"),
  list(name = "ispline_9knots", label = "I-spline (9 knots)", type = "ispline_more"),
  
  # NEW: Enhanced methods from ChatGPT discussion
  list(name = "qspline", label = "Q-spline (Quantile Function)", type = "qspline"),
  list(name = "ispline_pit_optimal", label = "I-spline (PIT-optimized)", type = "ispline_pit"),
  list(name = "ispline_tail_aware", label = "I-spline (Tail-aware)", type = "ispline_tail"),
  list(name = "no_smoothing", label = "No Smoothing (Mid-Ranks)", type = "ranks"),
  
  # Comparison methods
  list(name = "hyman", label = "Hyman Monotone Cubic", type = "hyman"),
  list(name = "kernel", label = "Kernel Smoothing", type = "kernel"),
  list(name = "parametric", label = "Normal Approximation", type = "parametric")
)

SAMPLE_SIZES <- c(500, 1000, 2000)
N_BOOTSTRAP <- 100
COPULA_FAMILIES <- phase2_families

cat("Testing", length(SMOOTHING_METHODS), "smoothing methods:\n")
for (method in SMOOTHING_METHODS) {
  cat("  -", method$label, "\n")
}
cat("\n")

################################################################################
### HELPER FUNCTIONS FOR ENHANCED METHODS
################################################################################

#' Compute PIT Uniformity Diagnostics
compute_pit_diagnostics <- function(pit_values) {
  n <- length(pit_values)
  pit_sorted <- sort(pit_values)
  i <- 1:n
  
  # Cramér-von Mises
  cvm <- (1/(12*n)) + sum((pit_sorted - (2*i - 1)/(2*n))^2)
  
  # Anderson-Darling
  ad <- -n - sum((2*i - 1) * (log(pit_sorted) + log(1 - rev(pit_sorted)))) / n
  
  # Kolmogorov-Smirnov
  ks_result <- ks.test(pit_values, "punif", 0, 1)
  
  return(list(
    cvm = cvm,
    ad = ad,
    ks_stat = ks_result$statistic,
    ks_pval = ks_result$p.value
  ))
}

################################################################################
### LOAD LONGITUDINAL DATA
################################################################################

cat("Loading longitudinal data...\n")

pairs_full <- create_longitudinal_pairs(
  data = Colorado_Data_LONG,
  grade_prior = CONFIG$grade_prior,
  grade_current = CONFIG$grade_current,
  year_prior = CONFIG$year_prior,
  content_prior = CONFIG$content,
  content_current = CONFIG$content
)

cat("Total pairs:", nrow(pairs_full), "\n\n")

if (nrow(pairs_full) < 500) {
  stop("Insufficient data for analysis")
}

################################################################################
### ESTABLISH SMOOTHING-SPECIFIC FRAMEWORKS
################################################################################

cat("====================================================================\n")
cat("ESTABLISHING FRAMEWORKS FOR EACH SMOOTHING METHOD\n")
cat("====================================================================\n\n")

# Common evaluation grid
x_min_prior <- min(pairs_full$SCALE_SCORE_PRIOR)
x_max_prior <- max(pairs_full$SCALE_SCORE_PRIOR)
x_min_current <- min(pairs_full$SCALE_SCORE_CURRENT)
x_max_current <- max(pairs_full$SCALE_SCORE_CURRENT)

x_eval_prior <- seq(x_min_prior, x_max_prior, length.out = 500)
x_eval_current <- seq(x_min_current, x_max_current, length.out = 500)

# Store frameworks for each method
frameworks <- list()

for (method in SMOOTHING_METHODS) {
  
  cat("Method:", method$label, "\n")
  
  if (method$type == "ispline") {
    # Standard I-spline with 4 knots
    framework_prior <- create_ispline_framework(
      pairs_full$SCALE_SCORE_PRIOR,
      knot_percentiles = c(0.2, 0.4, 0.6, 0.8)
    )
    framework_current <- create_ispline_framework(
      pairs_full$SCALE_SCORE_CURRENT,
      knot_percentiles = c(0.2, 0.4, 0.6, 0.8)
    )
    
  } else if (method$type == "ispline_more") {
    # I-spline with 9 knots
    framework_prior <- create_ispline_framework(
      pairs_full$SCALE_SCORE_PRIOR,
      knot_percentiles = seq(0.1, 0.9, 0.1)
    )
    framework_current <- create_ispline_framework(
      pairs_full$SCALE_SCORE_CURRENT,
      knot_percentiles = seq(0.1, 0.9, 0.1)
    )
    
  } else if (method$type == "qspline") {
    # Q-spline (quantile function)
    framework_prior <- fit_qspline(
      pairs_full$SCALE_SCORE_PRIOR,
      knot_probs = seq(0.1, 0.9, 0.1)
    )
    framework_current <- fit_qspline(
      pairs_full$SCALE_SCORE_CURRENT,
      knot_probs = seq(0.1, 0.9, 0.1)
    )
    
  } else if (method$type == "ispline_pit") {
    # PIT-optimized knot placement
    cat("  Selecting optimal knots by PIT uniformity...\n")
    sel_prior <- select_smoothing_by_pit(pairs_full$SCALE_SCORE_PRIOR)
    sel_current <- select_smoothing_by_pit(pairs_full$SCALE_SCORE_CURRENT)
    
    framework_prior <- sel_prior$best$framework
    framework_current <- sel_current$best$framework
    
    cat("  Prior: ", length(sel_prior$best$knots), " knots selected (CvM =", 
        round(sel_prior$best$cvm, 6), ")\n")
    cat("  Current:", length(sel_current$best$knots), " knots selected (CvM =", 
        round(sel_current$best$cvm, 6), ")\n")
    
  } else if (method$type == "ispline_tail") {
    # Tail-aware I-spline
    framework_prior <- create_ispline_framework_enhanced(
      pairs_full$SCALE_SCORE_PRIOR,
      knot_percentiles = c(0.2, 0.4, 0.6, 0.8),
      tail_aware = TRUE
    )
    framework_current <- create_ispline_framework_enhanced(
      pairs_full$SCALE_SCORE_CURRENT,
      knot_percentiles = c(0.2, 0.4, 0.6, 0.8),
      tail_aware = TRUE
    )
    
  } else if (method$type == "ranks") {
    # No smoothing - mid-ranks
    framework_prior <- fit_midrank_pit(
      pairs_full$SCALE_SCORE_PRIOR,
      x_eval = x_eval_prior
    )
    framework_current <- fit_midrank_pit(
      pairs_full$SCALE_SCORE_CURRENT,
      x_eval = x_eval_current
    )
    
  } else if (method$type == "hyman") {
    # Hyman monotone cubic
    ecdf_prior <- ecdf(pairs_full$SCALE_SCORE_PRIOR)
    x_unique_prior <- sort(unique(pairs_full$SCALE_SCORE_PRIOR))
    y_prior <- ecdf_prior(x_unique_prior)
    smooth_prior <- splinefun(x_unique_prior, y_prior, method = "hyman")
    
    ecdf_current <- ecdf(pairs_full$SCALE_SCORE_CURRENT)
    x_unique_current <- sort(unique(pairs_full$SCALE_SCORE_CURRENT))
    y_current <- ecdf_current(x_unique_current)
    smooth_current <- splinefun(x_unique_current, y_current, method = "hyman")
    
    framework_prior <- list(smooth_ecdf_full = smooth_prior, method = "hyman")
    framework_current <- list(smooth_ecdf_full = smooth_current, method = "hyman")
    
  } else if (method$type == "kernel") {
    # Kernel smoothing
    bw_prior <- 1.06 * sd(pairs_full$SCALE_SCORE_PRIOR) * 
                length(pairs_full$SCALE_SCORE_PRIOR)^(-1/5)
    bw_current <- 1.06 * sd(pairs_full$SCALE_SCORE_CURRENT) * 
                  length(pairs_full$SCALE_SCORE_CURRENT)^(-1/5)
    
    scores_prior <- pairs_full$SCALE_SCORE_PRIOR
    scores_current <- pairs_full$SCALE_SCORE_CURRENT
    
    smooth_prior <- function(x) {
      sapply(x, function(xi) mean(pnorm((xi - scores_prior) / bw_prior)))
    }
    smooth_current <- function(x) {
      sapply(x, function(xi) mean(pnorm((xi - scores_current) / bw_current)))
    }
    
    framework_prior <- list(smooth_ecdf_full = smooth_prior, method = "kernel")
    framework_current <- list(smooth_ecdf_full = smooth_current, method = "kernel")
    
  } else if (method$type == "parametric") {
    # Parametric (Normal)
    mu_prior <- mean(pairs_full$SCALE_SCORE_PRIOR)
    sigma_prior <- sd(pairs_full$SCALE_SCORE_PRIOR)
    mu_current <- mean(pairs_full$SCALE_SCORE_CURRENT)
    sigma_current <- sd(pairs_full$SCALE_SCORE_CURRENT)
    
    smooth_prior <- function(x) pnorm(x, mean = mu_prior, sd = sigma_prior)
    smooth_current <- function(x) pnorm(x, mean = mu_current, sd = sigma_current)
    
    framework_prior <- list(smooth_ecdf_full = smooth_prior, method = "parametric")
    framework_current <- list(smooth_ecdf_full = smooth_current, method = "parametric")
  }
  
  frameworks[[method$name]] <- list(
    prior = framework_prior,
    current = framework_current
  )
  
  cat("  Framework established\n\n")
}

################################################################################
### FIT TRUE COPULAS FOR EACH SMOOTHING METHOD
################################################################################

cat("====================================================================\n")
cat("FITTING TRUE COPULAS WITH EACH SMOOTHING METHOD\n")
cat("====================================================================\n\n")

true_copulas_by_method <- list()

for (method in SMOOTHING_METHODS) {
  
  cat("Method:", method$label, "\n")
  
  framework_prior <- frameworks[[method$name]]$prior
  framework_current <- frameworks[[method$name]]$current
  
  # Transform to pseudo-observations
  if (method$type == "qspline") {
    U <- framework_prior$cdf_function(pairs_full$SCALE_SCORE_PRIOR)
    V <- framework_current$cdf_function(pairs_full$SCALE_SCORE_CURRENT)
  } else if (method$type == "ranks") {
    U <- framework_prior$pit_function(pairs_full$SCALE_SCORE_PRIOR)
    V <- framework_current$pit_function(pairs_full$SCALE_SCORE_CURRENT)
  } else {
    U <- framework_prior$smooth_ecdf_full(pairs_full$SCALE_SCORE_PRIOR)
    V <- framework_current$smooth_ecdf_full(pairs_full$SCALE_SCORE_CURRENT)
  }
  
  # Constrain to (0, 1)
  U <- pmax(1e-10, pmin(1 - 1e-10, U))
  V <- pmax(1e-10, pmin(1 - 1e-10, V))
  
  # Compute PIT diagnostics
  pit_diag_prior <- compute_pit_diagnostics(U)
  pit_diag_current <- compute_pit_diagnostics(V)
  
  cat("  PIT Diagnostics (Prior)  - CvM:", round(pit_diag_prior$cvm, 6),
      ", KS p-value:", round(pit_diag_prior$ks_pval, 4), "\n")
  cat("  PIT Diagnostics (Current) - CvM:", round(pit_diag_current$cvm, 6),
      ", KS p-value:", round(pit_diag_current$ks_pval, 4), "\n")
  
  # Fit copulas
  pseudo_obs <- cbind(U, V)
  empirical_tau <- cor(U, V, method = "kendall")
  
  results_list <- list()
  
  for (family in COPULA_FAMILIES) {
    
    fit_result <- tryCatch({
      if (family == "gaussian") {
        cop <- normalCopula(dim = 2)
        fit <- fitCopula(cop, pseudo_obs, method = "ml")
        list(
          parameter = fit@estimate,
          loglik = fit@loglik,
          aic = -2 * fit@loglik + 2 * length(fit@estimate),
          tau = sin(pi/2 * fit@estimate)
        )
      } else if (family == "t") {
        cop <- tCopula(dim = 2, df.fixed = FALSE)
        fit <- fitCopula(cop, pseudo_obs, method = "ml")
        rho <- fit@estimate[1]
        df <- fit@estimate[2]
        list(
          parameter = c(rho, df),
          loglik = fit@loglik,
          aic = -2 * fit@loglik + 2 * length(fit@estimate),
          tau = sin(pi/2 * rho)
        )
      } else if (family == "clayton") {
        cop <- claytonCopula(dim = 2)
        fit <- fitCopula(cop, pseudo_obs, method = "ml")
        list(
          parameter = fit@estimate,
          loglik = fit@loglik,
          aic = -2 * fit@loglik + 2 * length(fit@estimate),
          tau = fit@estimate / (fit@estimate + 2)
        )
      } else if (family == "gumbel") {
        cop <- gumbelCopula(dim = 2)
        fit <- fitCopula(cop, pseudo_obs, method = "ml")
        list(
          parameter = fit@estimate,
          loglik = fit@loglik,
          aic = -2 * fit@loglik + 2 * length(fit@estimate),
          tau = (fit@estimate - 1) / fit@estimate
        )
      } else if (family == "frank") {
        cop <- frankCopula(dim = 2)
        fit <- fitCopula(cop, pseudo_obs, method = "ml")
        list(
          parameter = fit@estimate,
          loglik = fit@loglik,
          aic = -2 * fit@loglik + 2 * length(fit@estimate),
          tau = 1 - 4/fit@estimate * (1 - debye1(fit@estimate))
        )
      }
    }, error = function(e) NULL)
    
    if (!is.null(fit_result)) {
      results_list[[family]] <- fit_result
    }
  }
  
  # Find best family
  aics <- sapply(results_list, function(x) x$aic)
  best_family <- names(which.min(aics))
  
  true_copulas_by_method[[method$name]] <- list(
    results = results_list,
    best_family = best_family,
    empirical_tau = empirical_tau,
    pit_diagnostics = list(
      prior = pit_diag_prior,
      current = pit_diag_current
    )
  )
  
  cat("  Best family:", best_family, "| tau:", round(empirical_tau, 4), "\n\n")
}

################################################################################
### SAVE RESULTS AND GENERATE REPORT
################################################################################

cat("====================================================================\n")
cat("GENERATING SUMMARY REPORT\n")
cat("====================================================================\n\n")

# Create summary table
summary_table <- data.table()

for (method in SMOOTHING_METHODS) {
  
  true_cop <- true_copulas_by_method[[method$name]]
  
  for (family in names(true_cop$results)) {
    
    fit <- true_cop$results[[family]]
    
    row <- data.table(
      method = method$name,
      method_label = method$label,
      method_type = method$type,
      family = family,
      best_family = (family == true_cop$best_family),
      empirical_tau = true_cop$empirical_tau,
      fitted_tau = fit$tau,
      aic = fit$aic,
      parameter_1 = fit$parameter[1],
      parameter_2 = ifelse(length(fit$parameter) > 1, fit$parameter[2], NA),
      pit_cvm_prior = true_cop$pit_diagnostics$prior$cvm,
      pit_cvm_current = true_cop$pit_diagnostics$current$cvm,
      pit_ks_pval_prior = true_cop$pit_diagnostics$prior$ks_pval,
      pit_ks_pval_current = true_cop$pit_diagnostics$current$ks_pval
    )
    
    summary_table <- rbind(summary_table, row)
  }
}

# Save results
output_dir <- "results/exp_smoothing_enhanced"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

fwrite(summary_table, file.path(output_dir, "smoothing_comparison_summary.csv"))

cat("Results saved to:", output_dir, "\n\n")

# Print key findings
cat("====================================================================\n")
cat("KEY FINDINGS\n")
cat("====================================================================\n\n")

cat("1. COPULA FAMILY SELECTION BY SMOOTHING METHOD:\n")
best_families <- summary_table[best_family == TRUE, .(method_label, family)]
print(best_families)

cat("\n2. PIT UNIFORMITY BY METHOD:\n")
pit_summary <- summary_table[, .(
  mean_cvm_prior = mean(pit_cvm_prior),
  mean_cvm_current = mean(pit_cvm_current)
), by = .(method_label)]
setorder(pit_summary, mean_cvm_prior)
print(pit_summary)

cat("\n3. KENDALL'S TAU VARIABILITY ACROSS METHODS:\n")
tau_summary <- summary_table[, .(
  mean_tau = mean(empirical_tau),
  sd_tau = sd(empirical_tau)
), by = method_label]
print(tau_summary)

cat("\n====================================================================\n")
cat("EXPERIMENT 5 (ENHANCED) COMPLETE!\n")
cat("====================================================================\n\n")

cat("Review results in:", output_dir, "\n")
cat("Summary table saved: smoothing_comparison_summary.csv\n\n")
