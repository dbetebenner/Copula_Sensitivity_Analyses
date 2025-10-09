############################################################################
### Experiment 2: Sensitivity to Sample Size
### Question: What minimum (n_prior, n_current) yields stable copulas?
############################################################################

# Load libraries and functions
require(data.table)
require(splines2)
require(copula)

# Load Colorado data
if (!exists("Colorado_Data_LONG")) {
  load("/Users/conet/SGP Dropbox/Damian Betebenner/Colorado/Data/Archive/February_2016/Colorado_Data_LONG.RData")
}

# Source functions
source("../functions/longitudinal_pairs.R")
source("../functions/ispline_ecdf.R")
source("../functions/copula_bootstrap.R")
source("../functions/copula_diagnostics.R")

cat("====================================================================\n")
cat("EXPERIMENT 2: SAMPLE SIZE SENSITIVITY\n")
cat("====================================================================\n\n")

################################################################################
### LOAD PHASE 1 DECISION (if available)
################################################################################

# Check if Phase 1 decision exists
if (file.exists("results/phase1_decision.RData")) {
  load("results/phase1_decision.RData")
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

# Test both symmetric and asymmetric sample sizes
SAMPLE_SIZES_PRIOR <- c(100, 250, 500, 1000, 2000, 4000)
SAMPLE_SIZES_CURRENT <- c(100, 250, 500, 1000, 2000, 4000)

# Test configurations
TEST_CONFIGS <- list(
  # Configuration 1: Grade 4 -> 5 (1 year span, high correlation expected)
  list(
    name = "G4to5_1yr",
    grade_prior = 4,
    grade_current = 5,
    year_prior = "2010",
    content = "MATHEMATICS"
  ),
  
  # Configuration 2: Grade 4 -> 8 (4 year span, moderate correlation expected)
  list(
    name = "G4to8_4yr",
    grade_prior = 4,
    grade_current = 8,
    year_prior = "2009",
    content = "MATHEMATICS"
  )
)

# Bootstrap settings
N_BOOTSTRAP <- 100
COPULA_FAMILIES <- phase2_families

################################################################################
### RUN EXPERIMENTS
################################################################################

for (config in TEST_CONFIGS) {
  
  cat("\n====================================================================\n")
  cat("Testing Configuration:", config$name, "\n")
  cat("Grade", config$grade_prior, "->", config$grade_current, "\n")
  cat("====================================================================\n\n")
  
  # Create longitudinal pairs
  pairs_full <- create_longitudinal_pairs(
    data = Colorado_Data_LONG,
    grade_prior = config$grade_prior,
    grade_current = config$grade_current,
    year_prior = config$year_prior,
    content_prior = config$content,
    content_current = config$content
  )
  
  # Create I-spline frameworks
  framework_prior <- create_ispline_framework(pairs_full$SCALE_SCORE_PRIOR)
  framework_current <- create_ispline_framework(pairs_full$SCALE_SCORE_CURRENT)
  
  # Fit true copula
  cat("Fitting true copula from full data...\n\n")
  true_copula <- fit_copula_from_pairs(
    scores_prior = pairs_full$SCALE_SCORE_PRIOR,
    scores_current = pairs_full$SCALE_SCORE_CURRENT,
    framework_prior = framework_prior,
    framework_current = framework_current,
    copula_families = COPULA_FAMILIES,
    return_best = FALSE
  )
  
  cat("True Kendall's tau:", round(true_copula$empirical_tau, 4), "\n")
  cat("Best family:", true_copula$best_family, "\n\n")
  
  # Test symmetric sample sizes (n_prior = n_current)
  cat("Testing SYMMETRIC sample sizes...\n\n")
  
  results_symmetric <- list()
  
  for (n in SAMPLE_SIZES_PRIOR) {
    
    if (n > nrow(pairs_full)) {
      cat("Skipping n =", n, "(exceeds available pairs)\n")
      next
    }
    
    cat("Testing n =", n, "...\n")
    
    boot_result <- bootstrap_copula_estimation(
      pairs_data = pairs_full,
      n_sample_prior = n,
      n_sample_current = n,
      n_bootstrap = N_BOOTSTRAP,
      framework_prior = framework_prior,
      framework_current = framework_current,
      sampling_method = "paired",
      copula_families = COPULA_FAMILIES,
      with_replacement = TRUE
    )
    
    results_symmetric[[paste0("n", n)]] <- boot_result
    
    # Quick summary
    summary_dt <- summarize_bootstrap_copulas(boot_result, true_copula)
    best_fam_summary <- summary_dt[family == true_copula$best_family]
    
    cat("  tau mean:", round(best_fam_summary$tau_mean, 4),
        "+/- SD:", round(best_fam_summary$tau_sd, 4),
        "CI width:", round(best_fam_summary$ci_width, 4), "\n\n")
  }
  
  # Test asymmetric sample sizes (common in real assessments)
  cat("\nTesting ASYMMETRIC sample sizes...\n\n")
  
  # Test cases where prior has more data than current (or vice versa)
  asymmetric_tests <- list(
    list(n_prior = 1000, n_current = 250),
    list(n_prior = 250, n_current = 1000),
    list(n_prior = 4000, n_current = 500),
    list(n_prior = 500, n_current = 4000)
  )
  
  results_asymmetric <- list()
  
  for (test in asymmetric_tests) {
    
    if (test$n_prior > nrow(pairs_full) || test$n_current > nrow(pairs_full)) {
      cat("Skipping n_prior =", test$n_prior, ", n_current =", test$n_current, 
          "(exceeds available pairs)\n")
      next
    }
    
    cat("Testing n_prior =", test$n_prior, ", n_current =", test$n_current, "...\n")
    
    boot_result <- bootstrap_copula_estimation(
      pairs_data = pairs_full,
      n_sample_prior = test$n_prior,
      n_sample_current = test$n_current,
      n_bootstrap = N_BOOTSTRAP,
      framework_prior = framework_prior,
      framework_current = framework_current,
      sampling_method = "paired",
      copula_families = COPULA_FAMILIES,
      with_replacement = TRUE
    )
    
    test_name <- paste0("n", test$n_prior, "_", test$n_current)
    results_asymmetric[[test_name]] <- boot_result
    
    # Quick summary
    summary_dt <- summarize_bootstrap_copulas(boot_result, true_copula)
    best_fam_summary <- summary_dt[family == true_copula$best_family]
    
    cat("  tau mean:", round(best_fam_summary$tau_mean, 4),
        "+/- SD:", round(best_fam_summary$tau_sd, 4),
        "CI width:", round(best_fam_summary$ci_width, 4), "\n\n")
  }
  
  # Save results for this configuration
  output_dir <- file.path("results", "exp_2_sample_size", config$name)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Create stability plot
  plot_parameter_stability(
    results_by_size = results_symmetric,
    sample_sizes = as.numeric(gsub("n", "", names(results_symmetric))),
    true_value = true_copula$results[[true_copula$best_family]]$kendall_tau,
    family = true_copula$best_family,
    filename = file.path(output_dir, "stability_symmetric.pdf")
  )
  
  # Create comprehensive summary
  symmetric_summary <- rbindlist(lapply(names(results_symmetric), function(size_name) {
    n <- as.numeric(gsub("n", "", size_name))
    dt <- summarize_bootstrap_copulas(results_symmetric[[size_name]], true_copula)
    dt[, `:=`(n_prior = n, n_current = n, config = config$name)]
    return(dt)
  }))
  
  asymmetric_summary <- rbindlist(lapply(names(results_asymmetric), function(test_name) {
    parts <- strsplit(test_name, "_")[[1]]
    n_prior <- as.numeric(gsub("n", "", parts[1]))
    n_current <- as.numeric(parts[2])
    dt <- summarize_bootstrap_copulas(results_asymmetric[[test_name]], true_copula)
    dt[, `:=`(n_prior = n_prior, n_current = n_current, config = config$name)]
    return(dt)
  }))
  
  combined_summary <- rbind(symmetric_summary, asymmetric_summary)
  
  fwrite(combined_summary, 
         file = file.path(output_dir, "sample_size_sensitivity_summary.csv"))
  
  # Save workspace
  save(true_copula, results_symmetric, results_asymmetric, 
       combined_summary, pairs_full,
       file = file.path(output_dir, "sample_size_experiment.RData"))
  
  cat("\nResults saved to:", output_dir, "\n\n")
}

cat("====================================================================\n")
cat("EXPERIMENT 2 COMPLETE\n")
cat("====================================================================\n\n")

cat("Key findings:\n")
cat("- Tested sample sizes from 100 to 4000\n")
cat("- Examined both symmetric and asymmetric configurations\n")
cat("- Compared 1-year vs 4-year grade spans\n")
cat("\nRecommendations for minimum sample sizes:\n")
cat("(Based on achieving tau +/- 0.05 precision with 90% confidence)\n\n")

# Analyze results to give recommendations
for (config in TEST_CONFIGS) {
  output_dir <- file.path("results", "exp_2_sample_size", config$name)
  if (file.exists(file.path(output_dir, "sample_size_sensitivity_summary.csv"))) {
    summary <- fread(file.path(output_dir, "sample_size_sensitivity_summary.csv"))
    
    # Find minimum n where CI width < 0.10 (approximately ± 0.05)
    symmetric_best <- summary[n_prior == n_current & family == "gaussian"]
    min_n <- symmetric_best[ci_width < 0.10, min(n_prior)]
    
    if (!is.infinite(min_n)) {
      cat(config$name, ": Minimum n ≈", min_n, "\n")
    } else {
      cat(config$name, ": Requires n >", max(symmetric_best$n_prior), "\n")
    }
  }
}

cat("\n====================================================================\n\n")
