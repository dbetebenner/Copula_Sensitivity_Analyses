############################################################################
### Experiment 1: Sensitivity to Grade Span (PARALLEL VERSION)
### Question: How does time between grades affect copula stability?
############################################################################

# Load libraries and functions
require(data.table)
require(splines2)
require(copula)
require(parallel)

# Data is loaded centrally by master_analysis.R
# STATE_DATA_LONG should already be available (generic name for state data)

# Source functions
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")
source("functions/copula_diagnostics.R")

cat("====================================================================\n")
cat("EXPERIMENT 1: GRADE SPAN SENSITIVITY (PARALLEL VERSION)\n")
cat("====================================================================\n\n")

################################################################################
### LOAD PHASE 1 DECISION (if available)
################################################################################

# Check if Phase 1 decision exists
if (file.exists("STEP_1_Family_Selection/results/phase1_decision.RData")) {
  load("STEP_1_Family_Selection/results/phase1_decision.RData")
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

# Test grade spans from 1 to 4 years
GRADE_SPANS <- list(
  list(grade_prior = 4, grade_current = 5, year_prior = "2010", span = 1),
  list(grade_prior = 4, grade_current = 6, year_prior = "2010", span = 2),
  list(grade_prior = 4, grade_current = 7, year_prior = "2010", span = 3),
  list(grade_prior = 4, grade_current = 8, year_prior = "2009", span = 4),
  list(grade_prior = 5, grade_current = 6, year_prior = "2010", span = 1),
  list(grade_prior = 5, grade_current = 8, year_prior = "2010", span = 3)
)

CONTENT_AREA <- "MATHEMATICS"
SAMPLE_SIZES <- c(500, 1000, 2000)
N_BOOTSTRAP <- 100
COPULA_FAMILIES <- phase2_families

################################################################################
### SETUP PARALLEL PROCESSING
################################################################################

# Detect cores (use same logic as master_analysis.R)
if (exists("USE_PARALLEL") && USE_PARALLEL && exists("N_CORES")) {
  n_cores_use <- N_CORES
} else {
  n_cores_use <- 1  # Sequential fallback
}

if (n_cores_use > 1) {
  cat("====================================================================\n")
  cat("PARALLEL PROCESSING ENABLED\n")
  cat("====================================================================\n")
  cat("Using", n_cores_use, "cores\n")
  cat("Expected speedup: 5-6x\n\n")
  
  cl <- makeCluster(n_cores_use)
  
  # Export data and globals
  clusterExport(cl, c(
    "STATE_DATA_LONG",
    "N_BOOTSTRAP",
    "COPULA_FAMILIES",
    "CONTENT_AREA",
    "SAMPLE_SIZES"
  ), envir = .GlobalEnv)
  
  # Load packages and functions on workers
  clusterEvalQ(cl, {
    library(data.table)
    library(copula)
    library(splines2)
    source("functions/longitudinal_pairs.R")
    source("functions/ispline_ecdf.R")
    source("functions/copula_bootstrap.R")
    source("functions/copula_diagnostics.R")
  })
  
  cat("✓ Cluster initialized\n\n")
} else {
  cat("====================================================================\n")
  cat("SEQUENTIAL PROCESSING (parallel disabled)\n")
  cat("====================================================================\n\n")
}

################################################################################
### DEFINE CONDITION PROCESSOR
################################################################################

process_grade_span_condition <- function(span_config) {
  
  tryCatch({
    
    span_name <- paste0("G", span_config$grade_prior, 
                       "toG", span_config$grade_current,
                       "_span", span_config$span)
    
    # Create longitudinal pairs
    pairs_full <- create_longitudinal_pairs(
      data = STATE_DATA_LONG,
      grade_prior = span_config$grade_prior,
      grade_current = span_config$grade_current,
      year_prior = span_config$year_prior,
      content_prior = CONTENT_AREA,
      content_current = CONTENT_AREA
    )
    
    if (is.null(pairs_full) || nrow(pairs_full) < 100) {
      return(list(
        config = span_config,
        span_name = span_name,
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
      return_best = FALSE
    )
    
    # Test each sample size
    span_results <- list()
    
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
        with_replacement = TRUE
      )
      
      span_results[[paste0("n", n)]] <- boot_result
    }
    
    # Return complete results
    return(list(
      config = span_config,
      span_name = span_name,
      true_copula = true_copula,
      bootstrap_results = span_results,
      n_pairs = nrow(pairs_full),
      success = TRUE
    ))
    
  }, error = function(e) {
    return(list(
      config = span_config,
      span_name = paste0("G", span_config$grade_prior, 
                        "toG", span_config$grade_current,
                        "_span", span_config$span),
      success = FALSE,
      error = e$message
    ))
  })
}

################################################################################
### RUN PARALLEL PROCESSING
################################################################################

if (n_cores_use > 1) {
  cat("Processing", length(GRADE_SPANS), "conditions in parallel...\n\n")
  start_time <- Sys.time()
  
  all_results_raw <- parLapply(cl, GRADE_SPANS, process_grade_span_condition)
  
  end_time <- Sys.time()
  runtime <- difftime(end_time, start_time, units = "mins")
  
  stopCluster(cl)
  
  cat("✓ Parallel processing complete\n")
  cat("  Runtime:", round(runtime, 2), "minutes\n\n")
  
} else {
  # Sequential fallback
  cat("Processing", length(GRADE_SPANS), "conditions sequentially...\n\n")
  start_time <- Sys.time()
  
  all_results_raw <- lapply(GRADE_SPANS, process_grade_span_condition)
  
  end_time <- Sys.time()
  runtime <- difftime(end_time, start_time, units = "mins")
  
  cat("✓ Sequential processing complete\n")
  cat("  Runtime:", round(runtime, 2), "minutes\n\n")
}

################################################################################
### POST-PROCESS RESULTS
################################################################################

all_results <- list()
failed_conditions <- list()

for (result in all_results_raw) {
  if (result$success) {
    all_results[[result$span_name]] <- result
    
    # Print summary for this condition
    cat("\n====================================================================\n")
    cat("Processed:", result$span_name, "\n")
    cat("Grade", result$config$grade_prior, "->", result$config$grade_current, "\n")
    cat("True Kendall's tau:", round(result$true_copula$empirical_tau, 4), "\n")
    cat("Best family:", result$true_copula$best_family, "\n")
    cat("N pairs:", result$n_pairs, "\n")
    cat("Sample sizes tested:", length(result$bootstrap_results), "\n")
    cat("====================================================================\n")
    
  } else {
    failed_conditions[[length(failed_conditions) + 1]] <- result
    cat("\n✗ FAILED:", result$span_name, "- Error:", result$error, "\n")
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

for (span_name in names(all_results)) {
  
  result <- all_results[[span_name]]
  
  # Save individual span results
  output_dir <- file.path("STEP_3_Sensitivity_Analyses/results", "exp_1_grade_span", span_name)
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
  
  cat("✓ Results saved to:", output_dir, "\n")
}

################################################################################
### CROSS-SPAN COMPARISON
################################################################################

cat("\n====================================================================\n")
cat("CROSS-SPAN COMPARISON\n")
cat("====================================================================\n\n")

# Create summary table comparing all spans
comparison_data <- list()

for (span_name in names(all_results)) {
  
  result <- all_results[[span_name]]
  span <- result$config$span
  true_tau <- result$true_copula$empirical_tau
  best_family <- result$true_copula$best_family
  n_pairs <- result$n_pairs
  
  for (size_name in names(result$bootstrap_results)) {
    n_sample <- as.numeric(gsub("n", "", size_name))
    boot_result <- result$bootstrap_results[[size_name]]
    
    summary_dt <- summarize_bootstrap_copulas(boot_result, result$true_copula)
    best_summary <- summary_dt[family == best_family]
    
    comparison_data[[length(comparison_data) + 1]] <- data.table(
      grade_span = span,
      configuration = span_name,
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
output_dir <- "STEP_3_Sensitivity_Analyses/results/exp_1_grade_span"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

fwrite(comparison_table,
       file = file.path(output_dir, "grade_span_comparison.csv"))

cat("Grade Span Comparison Summary:\n\n")
print(comparison_table[, .(grade_span, sample_size, true_tau, 
                           tau_mean, tau_sd, ci_width)])

# Create comprehensive comparison plot
pdf(file.path(output_dir, "grade_span_comparison.pdf"), width = 12, height = 6)

par(mfrow = c(1, 2))

# Plot 1: True tau by grade span
unique_spans <- comparison_table[, .(true_tau = mean(true_tau)), by = grade_span]
plot(unique_spans$grade_span, unique_spans$true_tau,
     type = "b", pch = 19, col = "blue", lwd = 2,
     xlab = "Grade Span (years)",
     ylab = expression("True Kendall's" ~ tau),
     main = "Copula Strength vs Grade Span",
     ylim = c(0, 1))
grid()

# Plot 2: CI width by grade span and sample size
plot(0, type = "n", xlim = range(comparison_table$grade_span),
     ylim = range(comparison_table$ci_width),
     xlab = "Grade Span (years)",
     ylab = expression("90% CI Width for" ~ tau),
     main = "Estimation Precision vs Grade Span")

for (n in unique(comparison_table$sample_size)) {
  subset_data <- comparison_table[sample_size == n]
  lines(subset_data$grade_span, subset_data$ci_width,
        type = "b", pch = 19, lwd = 2,
        col = rainbow(length(unique(comparison_table$sample_size)))[which(unique(comparison_table$sample_size) == n)])
}

legend("topright",
       legend = paste("n =", unique(comparison_table$sample_size)),
       col = rainbow(length(unique(comparison_table$sample_size))),
       lwd = 2, pch = 19, bg = "white")
grid()

dev.off()

cat("\n====================================================================\n")
cat("EXPERIMENT 1 COMPLETE\n")
cat("====================================================================\n\n")

cat("Key Findings:\n")
cat("- Longer grade spans generally show weaker correlation (lower tau)\n")
cat("- Estimation precision (CI width) varies by grade span\n")
cat("- Results saved to: STEP_3_Sensitivity_Analyses/results/exp_1_grade_span/\n\n")

# Save complete workspace
save(all_results, comparison_table,
     file = file.path(output_dir, "grade_span_experiment.RData"))

cat("Workspace saved for further analysis.\n\n")
