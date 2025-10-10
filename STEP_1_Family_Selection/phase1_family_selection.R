############################################################################
### PHASE 1: COPULA FAMILY SELECTION STUDY
### Objective: Identify which copula family consistently provides best fit
###           for longitudinal educational assessment data
###
### Hypothesis: T-copula will dominate due to heavy tails in educational
###             data, with tail dependence increasing as time between
###             observations increases.
############################################################################

# Load libraries
require(data.table)
require(splines2)
require(copula)

# Data is loaded centrally by master_analysis.R
# STATE_DATA_LONG should already be available (generic name for state data)

# Functions are loaded centrally by master_analysis.R
# No need to source them individually

cat("====================================================================\n")
cat("PHASE 1: COPULA FAMILY SELECTION STUDY\n")
cat("====================================================================\n")
cat("Testing all 5 copula families across diverse conditions\n")
cat("to identify which family consistently provides best fit.\n")
cat("====================================================================\n\n")

################################################################################
### CONFIGURATION
################################################################################

# All copula families to test
COPULA_FAMILIES <- c("gaussian", "t", "clayton", "gumbel", "frank")

# Define test conditions (full factorial design)
# Grade spans: 1, 2, 3, 4 years
# Content areas: MATHEMATICS, READING, WRITING
# Cohorts: Multiple starting years

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
### RUN FAMILY SELECTION STUDY
################################################################################

# Storage for all results
all_results <- list()
result_counter <- 0

for (i in seq_along(CONDITIONS)) {
  
  cond <- CONDITIONS[[i]]
  
  cat("\n====================================================================\n")
  cat("Condition", i, "of", length(CONDITIONS), "\n")
  cat("Grade span:", cond$span, "year(s) |",
      "G", cond$grade_prior, "->", cond$grade_current, "\n")
  cat("Content:", cond$content, "| Cohort:", cond$year_prior, "\n")
  cat("====================================================================\n\n")
  
  # Create longitudinal pairs
  pairs_full <- tryCatch({
    create_longitudinal_pairs(
      data = get_state_data(),
      grade_prior = cond$grade_prior,
      grade_current = cond$grade_current,
      year_prior = cond$year_prior,
      content_prior = cond$content,
      content_current = cond$content
    )
  }, error = function(e) {
    cat("Error creating pairs:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(pairs_full) || nrow(pairs_full) < 100) {
    cat("Insufficient data for this configuration (N =", 
        ifelse(is.null(pairs_full), 0, nrow(pairs_full)), "). Skipping.\n")
    next
  }
  
  n_pairs <- nrow(pairs_full)
  cat("Longitudinal pairs:", n_pairs, "\n\n")
  
  # Create I-spline frameworks
  cat("Establishing I-spline frameworks...\n")
  framework_prior <- create_ispline_framework(pairs_full$SCALE_SCORE_PRIOR)
  framework_current <- create_ispline_framework(pairs_full$SCALE_SCORE_CURRENT)
  
  # Fit all copula families
  # IMPORTANT: Phase 1 uses empirical ranks (not I-spline) for copula family selection
  # This ensures uniform pseudo-observations and preserves tail dependence structure
  # (See debug_frank_dominance.R for validation showing I-spline with 4 knots distorted results)
  cat("Fitting all copula families...\n")
  cat("  Using empirical ranks for family selection (ensures uniform U,V)\n\n")
  
  copula_fits <- fit_copula_from_pairs(
    scores_prior = pairs_full$SCALE_SCORE_PRIOR,
    scores_current = pairs_full$SCALE_SCORE_CURRENT,
    framework_prior = framework_prior,  # Still create for reference, but not used with ranks
    framework_current = framework_current,
    copula_families = COPULA_FAMILIES,
    return_best = FALSE,
    use_empirical_ranks = TRUE  # Phase 1: Use ranks to avoid I-spline distortion
  )
  
  # Extract results for each family
  for (family in COPULA_FAMILIES) {
    
    if (!is.null(copula_fits$results[[family]])) {
      
      result_counter <- result_counter + 1
      
      fit <- copula_fits$results[[family]]
      
      # Extract tail dependence coefficients
      if (family == "t" && length(fit$parameter) >= 2) {
        # For t-copula, calculate tail dependence from rho and df
        rho <- fit$parameter[1]
        df <- fit$parameter[2]
        # Symmetric tail dependence for t-copula
        tail_dep <- 2 * pt(-sqrt((df + 1) * (1 - rho) / (1 + rho)), df = df + 1)
        tail_dep_lower <- tail_dep
        tail_dep_upper <- tail_dep
      } else if (family == "clayton") {
        # Clayton has lower tail dependence only
        theta <- fit$parameter[1]
        tail_dep_lower <- 2^(-1/theta)
        tail_dep_upper <- 0
      } else if (family == "gumbel") {
        # Gumbel has upper tail dependence only
        theta <- fit$parameter[1]
        tail_dep_lower <- 0
        tail_dep_upper <- 2 - 2^(1/theta)
      } else {
        # Gaussian and Frank have no tail dependence
        tail_dep_lower <- 0
        tail_dep_upper <- 0
      }
      
      all_results[[result_counter]] <- data.table(
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
      
      cat(sprintf("  %-10s: AIC = %8.2f, BIC = %8.2f, tau = %.4f\n",
                  family, fit$aic, fit$bic, fit$kendall_tau))
    } else {
      cat(sprintf("  %-10s: FAILED to fit\n", family))
    }
  }
  
  # Show best family for this condition
  cat("\nBest family (AIC):", copula_fits$best_family, "\n")
  cat("Empirical tau:", round(copula_fits$empirical_tau, 4), "\n")
}

################################################################################
### COMPILE AND SAVE RESULTS
################################################################################

cat("\n\n====================================================================\n")
cat("COMPILING RESULTS\n")
cat("====================================================================\n\n")

if (length(all_results) == 0) {
  stop("No results to compile. Check data availability.")
}

# Combine all results
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

