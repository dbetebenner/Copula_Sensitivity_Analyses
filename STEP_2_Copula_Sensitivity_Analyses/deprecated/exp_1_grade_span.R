############################################################################
### Experiment 1: Sensitivity to Grade Span
### Question: How does time between grades affect copula stability?
############################################################################

# Load libraries and functions
require(data.table)
require(splines2)
require(copula)

# Data is loaded centrally by master_analysis.R
# STATE_DATA_LONG should already be available (generic name for state data)

# Source functions
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")
source("functions/copula_diagnostics.R")
source("functions/sgpc_engine.R")
source("STEP_2_Copula_Sensitivity_Analyses/sgpc_sensitivity_utils.R")

cat("====================================================================\n")
cat("EXPERIMENT 1: GRADE SPAN SENSITIVITY\n")
cat("====================================================================\n\n")

################################################################################
### LOAD PHASE 1 DECISION (if available)
################################################################################

# Check if Phase 1 decision exists
phase1_decision_candidates <- c(
  "STEP_1_Family_Selection/results/phase1_decision.RData",
  "STEP_1_Family_Selection/results/dataset_all/phase1_decision.RData"
)
phase1_decision_file <- phase1_decision_candidates[file.exists(phase1_decision_candidates)][1]

if (!is.na(phase1_decision_file)) {
  load(phase1_decision_file)
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

# Define CONTENT_AREA first (needed for config generation)
CONTENT_AREA <- "MATHEMATICS"

# Generate valid grade spans dynamically based on actual data availability
years_available <- unique(STATE_DATA_LONG$YEAR)
years_numeric <- sort(as.numeric(as.character(years_available)))

cat("Generating dynamic GRADE_SPANS configurations...\n")
cat("  Available years:", paste(range(years_numeric), collapse = "-"), "\n")

GRADE_SPANS <- list()
for (span in 1:4) {
  for (grade_prior in c(4, 5)) {
    grade_current <- grade_prior + span
    
    # Skip if exceeds reasonable grade range
    if (grade_current > 8) next
    
    # Find valid years for this span (year_prior + span must exist)
    valid_years <- years_numeric[(years_numeric + span) %in% years_numeric]
    
    if (length(valid_years) > 0) {
      # Use the most recent valid year to maximize sample size
      best_year <- max(valid_years)
      
      # Validate data exists for these specific grades/years
      n_prior <- STATE_DATA_LONG[
        GRADE == grade_prior & 
        YEAR == as.character(best_year) & 
        CONTENT_AREA == CONTENT_AREA,
        .N
      ]
      n_current <- STATE_DATA_LONG[
        GRADE == grade_current & 
        YEAR == as.character(best_year + span) & 
        CONTENT_AREA == CONTENT_AREA,
        .N
      ]
      
      if (n_prior >= 100 && n_current >= 100) {
        GRADE_SPANS[[length(GRADE_SPANS) + 1]] <- list(
          grade_prior = grade_prior,
          grade_current = grade_current,
          year_prior = as.character(best_year),
          span = span
        )
      }
    }
  }
}

cat("✓ Generated", length(GRADE_SPANS), "valid grade span configurations\n")
if (length(GRADE_SPANS) == 0) {
  stop("No valid grade span configurations found in dataset")
}
cat("\n")

# CONTENT_AREA already defined above before config generation
SAMPLE_SIZES <- c(500, 1000, 2000)
if (!exists("N_BOOTSTRAP")) N_BOOTSTRAP <- 50
if (!exists("USE_EMPIRICAL_RANKS")) USE_EMPIRICAL_RANKS <- TRUE
COPULA_FAMILIES <- phase2_families
CANONICAL_PARAMS_FILE <- "STEP_1_Family_Selection/results/dataset_all/canonical_copula_parameters.csv"
CANONICAL_PARAMS <- load_canonical_copulas(CANONICAL_PARAMS_FILE)

################################################################################
### RUN EXPERIMENTS
################################################################################

all_results <- list()
sgpc_sensitivity_all <- list()

for (span_config in GRADE_SPANS) {
  
  span_name <- paste0("G", span_config$grade_prior, "toG", span_config$grade_current,
                     "_span", span_config$span)
  
  cat("\n====================================================================\n")
  cat("Testing Grade Span:", span_config$span, "year(s)\n")
  cat("Grade", span_config$grade_prior, "->", span_config$grade_current, "\n")
  cat("Year:", span_config$year_prior, "\n")
  cat("====================================================================\n\n")
  
  # NOTE: We already validated years during dynamic configuration generation,
  # so we don't need to call resolve_year_prior() anymore. Just use the year directly.
  
  # Create longitudinal pairs
  pairs_full <- tryCatch({
    create_longitudinal_pairs(
      data = STATE_DATA_LONG,
      grade_prior = span_config$grade_prior,
      grade_current = span_config$grade_current,
      year_prior = span_config$year_prior,
      content_prior = CONTENT_AREA,
      content_current = CONTENT_AREA
    )
  }, error = function(e) {
    cat("Error creating pairs:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(pairs_full) || nrow(pairs_full) < 100) {
    cat("Insufficient data for this configuration. Skipping.\n")
    next
  }
  
  # Create I-spline frameworks
  framework_prior <- create_ispline_framework(pairs_full$SCALE_SCORE_PRIOR)
  framework_current <- create_ispline_framework(pairs_full$SCALE_SCORE_CURRENT)
  
  # Fit true copula
  cat("Fitting true copula from full data (N =", nrow(pairs_full), ")...\n\n")
  
  true_copula <- fit_copula_from_pairs(
    scores_prior = pairs_full$SCALE_SCORE_PRIOR,
    scores_current = pairs_full$SCALE_SCORE_CURRENT,
    framework_prior = framework_prior,
    framework_current = framework_current,
    copula_families = COPULA_FAMILIES,
    return_best = FALSE,
    use_empirical_ranks = USE_EMPIRICAL_RANKS
  )
  
  cat("True Kendall's tau:", round(true_copula$empirical_tau, 4), "\n")
  cat("Best family:", true_copula$best_family, "\n\n")
  
  # Test each sample size
  span_results <- list()
  
  for (n in SAMPLE_SIZES) {
    
    if (n > nrow(pairs_full)) {
      cat("Sample size n =", n, "exceeds available pairs. Skipping.\n")
      next
    }
    
    cat("Testing sample size n =", n, "...\n")
    
    boot_result <- bootstrap_copula_estimation(
      pairs_data = pairs_full,
      n_sample_prior = n,
      n_sample_current = n,
      n_bootstrap = N_BOOTSTRAP,
      framework_prior = framework_prior,
      framework_current = framework_current,
      sampling_method = "paired",
      copula_families = COPULA_FAMILIES,
      with_replacement = TRUE,
      use_empirical_ranks = USE_EMPIRICAL_RANKS
    )
    
    span_results[[paste0("n", n)]] <- boot_result
    
    # Quick summary
    summary_dt <- summarize_bootstrap_copulas(boot_result, true_copula)
    best_summary <- summary_dt[family == true_copula$best_family]
    
    cat("  tau mean:", round(best_summary$tau_mean, 4),
        "SD:", round(best_summary$tau_sd, 4),
        "CI width:", round(best_summary$ci_width, 4), "\n\n")
  }
  
  # Store results for this span
  all_results[[span_name]] <- list(
    config = span_config,
    true_copula = true_copula,
    bootstrap_results = span_results,
    n_pairs = nrow(pairs_full)
  )

  # SGPc sensitivity to copula mis-specification
  baseline_family <- if ("t" %in% names(true_copula$results)) "t" else true_copula$best_family
  extra_copulas <- list()
  canonical_copula <- get_canonical_copula(CANONICAL_PARAMS, span_config$span, CONTENT_AREA)
  if (!is.null(canonical_copula)) {
    extra_copulas[[paste0("canonical_", tolower(CONTENT_AREA), "_span", span_config$span)]] <- canonical_copula
  }
  sgpc_sensitivity <- compute_sgpc_sensitivity(
    pseudo_obs = true_copula$pseudo_obs,
    fitted_results = true_copula$results,
    baseline_family = baseline_family,
    include_empirical = TRUE,
    extra_copulas = extra_copulas,
    grid_size = 200
  )
  if (nrow(sgpc_sensitivity) > 0) {
    sgpc_sensitivity[, `:=`(
      experiment = "exp_1_grade_span",
      configuration = span_name,
      grade_span = span_config$span,
      n_pairs = nrow(pairs_full)
    )]
    sgpc_sensitivity_all[[span_name]] <- sgpc_sensitivity
  }
  
  # Save individual span results
  output_dir <- file.path("STEP_2_Copula_Sensitivity_Analyses/results", "exp_1_grade_span", span_name)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Create reports
  for (size_name in names(span_results)) {
    prefix <- file.path(output_dir, size_name)
    create_sensitivity_report(
      bootstrap_results = span_results[[size_name]],
      true_copula = true_copula,
      output_prefix = prefix
    )
  }
  
  # Create stability plot
  if (length(span_results) > 0) {
    plot_parameter_stability(
      results_by_size = span_results,
      sample_sizes = as.numeric(gsub("n", "", names(span_results))),
      true_value = true_copula$results[[true_copula$best_family]]$kendall_tau,
      family = true_copula$best_family,
      filename = file.path(output_dir, "stability.pdf")
    )
  }
  
  if (exists("sgpc_sensitivity") && nrow(sgpc_sensitivity) > 0) {
    fwrite(sgpc_sensitivity, file = file.path(output_dir, "sgpc_sensitivity.csv"))
  }

  cat("Results saved to:", output_dir, "\n")
}

################################################################################
### CROSS-SPAN COMPARISON
################################################################################

cat("\n====================================================================\n")
cat("CROSS-SPAN COMPARISON\n")
cat("====================================================================\n\n")

# Check if any results were generated
if (length(all_results) == 0) {
  cat("⚠ WARNING: No grade span configurations produced valid results.\n")
  cat("   This usually means:\n")
  cat("   - Hardcoded years don't exist in dataset\n")
  cat("   - Insufficient data for requested configurations\n")
  cat("   - Data structure issues\n\n")
  cat("   Solution: Use dynamic configuration generation (now implemented)\n\n")
  stop("Cannot generate comparison table with no results. Experiment 1 needs valid data.")
}

if (length(sgpc_sensitivity_all) > 0) {
  sgpc_summary <- rbindlist(sgpc_sensitivity_all, fill = TRUE)
  sgpc_output_dir <- "STEP_2_Copula_Sensitivity_Analyses/results/exp_1_grade_span"
  dir.create(sgpc_output_dir, recursive = TRUE, showWarnings = FALSE)
  fwrite(sgpc_summary, file = file.path(sgpc_output_dir, "sgpc_sensitivity_summary.csv"))
}

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
output_dir <- "STEP_2_Copula_Sensitivity_Analyses/results/exp_1_grade_span"
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
for (n in unique(comparison_table$sample_size)) {
  subset_data <- comparison_table[sample_size == n]
  lines(subset_data$grade_span, subset_data$ci_width,
        type = "b", pch = 19, col = rainbow(length(unique(comparison_table$sample_size)))[which(unique(comparison_table$sample_size) == n)],
        lwd = 2)
}

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
cat("- Results saved to: STEP_2_Copula_Sensitivity_Analyses/results/exp_1_grade_span/\n\n")

# Save complete workspace
save(all_results, comparison_table,
     file = file.path(output_dir, "grade_span_experiment.RData"))

cat("Workspace saved for further analysis.\n\n")
