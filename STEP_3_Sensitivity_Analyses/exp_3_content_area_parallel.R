############################################################################
### Experiment 3: Sensitivity to Content Area (PARALLEL VERSION)
### Question: Does dependence structure vary by subject?
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
cat("EXPERIMENT 3: CONTENT AREA SENSITIVITY (PARALLEL VERSION)\n")
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

# Test configurations: Within-content and cross-content
TEST_CONFIGS <- list(
  # Within-content (same subject, prior and current)
  list(
    name = "Math_G4to8",
    grade_prior = 4,
    grade_current = 8,
    year_prior = "2009",
    content_prior = "MATHEMATICS",
    content_current = "MATHEMATICS",
    type = "within"
  ),
  list(
    name = "Reading_G4to8",
    grade_prior = 4,
    grade_current = 8,
    year_prior = "2009",
    content_prior = "READING",
    content_current = "READING",
    type = "within"
  ),
  list(
    name = "Writing_G4to8",
    grade_prior = 4,
    grade_current = 8,
    year_prior = "2009",
    content_prior = "WRITING",
    content_current = "WRITING",
    type = "within"
  ),
  
  # Cross-content (different subjects)
  list(
    name = "MathToReading_G4to8",
    grade_prior = 4,
    grade_current = 8,
    year_prior = "2009",
    content_prior = "MATHEMATICS",
    content_current = "READING",
    type = "cross"
  ),
  list(
    name = "ReadingToMath_G4to8",
    grade_prior = 4,
    grade_current = 8,
    year_prior = "2009",
    content_prior = "READING",
    content_current = "MATHEMATICS",
    type = "cross"
  ),
  list(
    name = "MathToWriting_G4to8",
    grade_prior = 4,
    grade_current = 8,
    year_prior = "2009",
    content_prior = "MATHEMATICS",
    content_current = "WRITING",
    type = "cross"
  )
)

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

process_content_area_condition <- function(config) {
  
  tryCatch({
    
    # Create longitudinal pairs
    pairs_full <- create_longitudinal_pairs(
      data = STATE_DATA_LONG,
      grade_prior = config$grade_prior,
      grade_current = config$grade_current,
      year_prior = config$year_prior,
      content_prior = config$content_prior,
      content_current = config$content_current
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
      return_best = FALSE
    )
    
    # Test each sample size
    content_results <- list()
    
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
      
      content_results[[paste0("n", n)]] <- boot_result
    }
    
    # Return complete results
    return(list(
      config = config,
      true_copula = true_copula,
      bootstrap_results = content_results,
      n_pairs = nrow(pairs_full),
      frameworks = list(prior = framework_prior, current = framework_current),
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
  cat("Processing", length(TEST_CONFIGS), "conditions in parallel...\n\n")
  start_time <- Sys.time()
  
  all_results_raw <- parLapply(cl, TEST_CONFIGS, process_content_area_condition)
  
  end_time <- Sys.time()
  runtime <- difftime(end_time, start_time, units = "mins")
  
  stopCluster(cl)
  
  cat("✓ Parallel processing complete\n")
  cat("  Runtime:", round(runtime, 2), "minutes\n\n")
  
} else {
  # Sequential fallback
  cat("Processing", length(TEST_CONFIGS), "conditions sequentially...\n\n")
  start_time <- Sys.time()
  
  all_results_raw <- lapply(TEST_CONFIGS, process_content_area_condition)
  
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
    all_results[[result$config$name]] <- result
    
    # Print summary for this condition
    cat("\n====================================================================\n")
    cat("Processed:", result$config$name, "\n")
    cat("Type:", result$config$type, "\n")
    cat("Prior:", result$config$content_prior, "Grade", result$config$grade_prior, "\n")
    cat("Current:", result$config$content_current, "Grade", result$config$grade_current, "\n")
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
cat("Successfully processed:", length(all_results), "conditions\n")
cat("Failed:", length(failed_conditions), "conditions\n\n")

################################################################################
### SAVE INDIVIDUAL RESULTS AND CREATE REPORTS
################################################################################

cat("Creating individual reports...\n\n")

for (config_name in names(all_results)) {
  
  result <- all_results[[config_name]]
  
  # Save individual content results
  output_dir <- file.path("STEP_3_Sensitivity_Analyses/results", "exp_3_content_area", config_name)
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
### CROSS-CONTENT COMPARISON
################################################################################

cat("\n====================================================================\n")
cat("CROSS-CONTENT COMPARISON\n")
cat("====================================================================\n\n")

# Create comprehensive comparison table
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
      type = config$type,
      content_prior = config$content_prior,
      content_current = config$content_current,
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
output_dir <- "STEP_3_Sensitivity_Analyses/results/exp_3_content_area"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

fwrite(comparison_table,
       file = file.path(output_dir, "content_area_comparison.csv"))

cat("Content Area Comparison Summary:\n\n")
print(comparison_table[, .(configuration, type, sample_size, 
                           true_tau, tau_mean, tau_sd, ci_width)])

# Separate within-content and cross-content
within_content <- comparison_table[type == "within"]
cross_content <- comparison_table[type == "cross"]

cat("\n\nWithin-Content Analysis (Same Subject):\n")
print(within_content[, .(content_prior, sample_size, true_tau, 
                         tau_mean, tau_sd, ci_width)])

cat("\n\nCross-Content Analysis (Different Subjects):\n")
print(cross_content[, .(content_prior, content_current, sample_size, 
                        true_tau, tau_mean, tau_sd, ci_width)])

# Create comparison plots
pdf(file.path(output_dir, "content_area_comparison.pdf"), width = 14, height = 10)

par(mfrow = c(2, 2))

# Plot 1: True tau by content area (within-content only)
if (nrow(within_content) > 0) {
  within_summary <- within_content[, .(true_tau = mean(true_tau)), by = content_prior]
  barplot(within_summary$true_tau,
          names.arg = within_summary$content_prior,
          col = rainbow(nrow(within_summary)),
          main = "True Copula Strength by Content Area",
          ylab = expression("True Kendall's" ~ tau),
          ylim = c(0, 1))
  grid()
}

# Plot 2: CI width comparison (within vs cross)
boxplot(ci_width ~ type, data = comparison_table,
        col = c("lightblue", "lightcoral"),
        main = "Estimation Precision: Within vs Cross-Content",
        ylab = "90% CI Width",
        xlab = "Analysis Type")
grid()

# Plot 3: True tau for all configurations
config_taus <- comparison_table[, .(true_tau = mean(true_tau)), by = configuration]
par(mar = c(10, 4, 4, 2))
barplot(config_taus$true_tau,
        names.arg = config_taus$configuration,
        las = 2,
        col = rainbow(nrow(config_taus)),
        main = "True Copula Strength: All Configurations",
        ylab = expression("True Kendall's" ~ tau))
grid()

# Plot 4: Precision by sample size and content type
par(mar = c(5, 4, 4, 2))
plot(0, type = "n",
     xlim = range(comparison_table$sample_size),
     ylim = range(comparison_table$ci_width),
     xlab = "Sample Size",
     ylab = "90% CI Width",
     main = "Precision by Sample Size and Content Type",
     log = "x")

# Within-content lines
if (nrow(within_content) > 0) {
  for (content in unique(within_content$content_prior)) {
    subset_data <- within_content[content_prior == content]
    lines(subset_data$sample_size, subset_data$ci_width,
          type = "b", pch = 19, lwd = 2, col = "blue")
  }
}

# Cross-content lines
if (nrow(cross_content) > 0) {
  for (config in unique(cross_content$configuration)) {
    subset_data <- cross_content[configuration == config]
    lines(subset_data$sample_size, subset_data$ci_width,
          type = "b", pch = 17, lwd = 2, col = "red", lty = 2)
  }
}

legend("topright",
       legend = c("Within-content", "Cross-content"),
       col = c("blue", "red"),
       lty = c(1, 2),
       pch = c(19, 17),
       lwd = 2,
       bg = "white")
grid()

dev.off()

cat("\n====================================================================\n")
cat("EXPERIMENT 3 COMPLETE\n")
cat("====================================================================\n\n")

cat("Key Findings:\n\n")

# Compare within-content correlations
if (nrow(within_content) > 0) {
  within_by_content <- within_content[sample_size == max(sample_size),
                                      .(true_tau = mean(true_tau)),
                                      by = content_prior]
  cat("Within-Content Correlations (Grade 4->8):\n")
  for (i in 1:nrow(within_by_content)) {
    cat("  ", within_by_content$content_prior[i], ": tau =",
        round(within_by_content$true_tau[i], 4), "\n")
  }
  cat("\n")
}

# Compare cross-content correlations
if (nrow(cross_content) > 0) {
  cross_summary <- cross_content[sample_size == max(sample_size),
                                 .(true_tau = mean(true_tau)),
                                 by = .(content_prior, content_current)]
  cat("Cross-Content Correlations (Grade 4->8):\n")
  for (i in 1:nrow(cross_summary)) {
    cat("  ", cross_summary$content_prior[i], "->", 
        cross_summary$content_current[i], ": tau =",
        round(cross_summary$true_tau[i], 4), "\n")
  }
  cat("\n")
}

# Precision comparison
avg_ci_within <- mean(within_content[sample_size == max(SAMPLE_SIZES)]$ci_width, na.rm = TRUE)
avg_ci_cross <- mean(cross_content[sample_size == max(SAMPLE_SIZES)]$ci_width, na.rm = TRUE)

cat("Average CI Width (n =", max(SAMPLE_SIZES), "):\n")
cat("  Within-content:", round(avg_ci_within, 4), "\n")
cat("  Cross-content:", round(avg_ci_cross, 4), "\n\n")

if (avg_ci_cross > avg_ci_within * 1.2) {
  cat("FINDING: Cross-content analysis shows substantially lower precision.\n")
  cat("         Within-content copulas recommended when possible.\n")
} else {
  cat("FINDING: Precision is similar for within- and cross-content analysis.\n")
  cat("         Cross-content copulas may be viable for growth modeling.\n")
}

cat("\n- Results saved to: STEP_3_Sensitivity_Analyses/results/exp_3_content_area/\n\n")

# Save complete workspace
save(all_results, comparison_table, within_content, cross_content,
     file = file.path(output_dir, "content_area_experiment.RData"))

cat("Workspace saved for further analysis.\n\n")
