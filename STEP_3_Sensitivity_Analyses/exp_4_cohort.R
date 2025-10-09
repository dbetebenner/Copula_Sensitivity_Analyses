############################################################################
### Experiment 4: Sensitivity to Cohort/Year
### Question: Does cohort effect matter? Do copulas differ across years?
############################################################################

# Load libraries and functions
require(data.table)
require(splines2)
require(copula)

# Data is loaded centrally by master_analysis.R
# STATE_DATA_LONG should already be available (generic name for state data)

# Source functions
source("../functions/longitudinal_pairs.R")
source("../functions/ispline_ecdf.R")
source("../functions/copula_bootstrap.R")
source("../functions/copula_diagnostics.R")

cat("====================================================================\n")
cat("EXPERIMENT 4: COHORT/YEAR SENSITIVITY\n")
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

# Test same grade transition across different cohorts
COHORT_CONFIGS <- list(
  # Grade 4 -> 5 transitions across consecutive years
  list(name = "G4to5_2007to2008", grade_prior = 4, grade_current = 5, 
       year_prior = "2007", content = "MATHEMATICS", cohort = "2007"),
  list(name = "G4to5_2008to2009", grade_prior = 4, grade_current = 5, 
       year_prior = "2008", content = "MATHEMATICS", cohort = "2008"),
  list(name = "G4to5_2009to2010", grade_prior = 4, grade_current = 5, 
       year_prior = "2009", content = "MATHEMATICS", cohort = "2009"),
  list(name = "G4to5_2010to2011", grade_prior = 4, grade_current = 5, 
       year_prior = "2010", content = "MATHEMATICS", cohort = "2010"),
  list(name = "G4to5_2011to2012", grade_prior = 4, grade_current = 5, 
       year_prior = "2011", content = "MATHEMATICS", cohort = "2011"),
  list(name = "G4to5_2012to2013", grade_prior = 4, grade_current = 5, 
       year_prior = "2012", content = "MATHEMATICS", cohort = "2012"),
  
  # Grade 5 -> 6 transitions for comparison
  list(name = "G5to6_2009to2010", grade_prior = 5, grade_current = 6, 
       year_prior = "2009", content = "MATHEMATICS", cohort = "2009"),
  list(name = "G5to6_2010to2011", grade_prior = 5, grade_current = 6, 
       year_prior = "2010", content = "MATHEMATICS", cohort = "2010"),
  list(name = "G5to6_2011to2012", grade_prior = 5, grade_current = 6, 
       year_prior = "2011", content = "MATHEMATICS", cohort = "2011"),
  list(name = "G5to6_2012to2013", grade_prior = 5, grade_current = 6, 
       year_prior = "2012", content = "MATHEMATICS", cohort = "2012")
)

SAMPLE_SIZES <- c(500, 1000, 2000)
N_BOOTSTRAP <- 100
COPULA_FAMILIES <- phase2_families

################################################################################
### RUN EXPERIMENTS
################################################################################

all_results <- list()

for (config in COHORT_CONFIGS) {
  
  cat("\n====================================================================\n")
  cat("Testing Cohort:", config$cohort, "\n")
  cat("Grade", config$grade_prior, "->", config$grade_current, "\n")
  cat("Year:", config$year_prior, "->", as.numeric(config$year_prior) + 1, "\n")
  cat("====================================================================\n\n")
  
  # Create longitudinal pairs
  pairs_full <- tryCatch({
    create_longitudinal_pairs(
      data = get_state_data(),
      grade_prior = config$grade_prior,
      grade_current = config$grade_current,
      year_prior = config$year_prior,
      content_prior = config$content,
      content_current = config$content
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
    return_best = FALSE
  )
  
  cat("True Kendall's tau:", round(true_copula$empirical_tau, 4), "\n")
  cat("Best family:", true_copula$best_family, "\n\n")
  
  # Test each sample size
  cohort_results <- list()
  
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
      with_replacement = TRUE
    )
    
    cohort_results[[paste0("n", n)]] <- boot_result
    
    # Quick summary
    summary_dt <- summarize_bootstrap_copulas(boot_result, true_copula)
    best_summary <- summary_dt[family == true_copula$best_family]
    
    cat("  tau mean:", round(best_summary$tau_mean, 4),
        "SD:", round(best_summary$tau_sd, 4),
        "CI width:", round(best_summary$ci_width, 4), "\n\n")
  }
  
  # Store results for this cohort
  all_results[[config$name]] <- list(
    config = config,
    true_copula = true_copula,
    bootstrap_results = cohort_results,
    n_pairs = nrow(pairs_full)
  )
  
  # Save individual cohort results
  output_dir <- file.path("results", "exp_4_cohort", config$name)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Create reports
  for (size_name in names(cohort_results)) {
    prefix <- file.path(output_dir, size_name)
    create_sensitivity_report(
      bootstrap_results = cohort_results[[size_name]],
      true_copula = true_copula,
      output_prefix = prefix
    )
  }
  
  cat("Results saved to:", output_dir, "\n")
}

################################################################################
### CROSS-COHORT COMPARISON
################################################################################

cat("\n====================================================================\n")
cat("CROSS-COHORT COMPARISON\n")
cat("====================================================================\n\n")

# Create comparison table
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
      cohort = config$cohort,
      grade_transition = paste0(config$grade_prior, "->", config$grade_current),
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
output_dir <- "results/exp_4_cohort"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

fwrite(comparison_table,
       file = file.path(output_dir, "cohort_comparison.csv"))

cat("Cohort Comparison Summary:\n\n")
print(comparison_table[, .(cohort, grade_transition, sample_size, 
                           true_tau, tau_mean, tau_sd, ci_width)])

# Separate by grade transition
g4to5_data <- comparison_table[grade_transition == "4->5"]
g5to6_data <- comparison_table[grade_transition == "5->6"]

# Create comparison plots
pdf(file.path(output_dir, "cohort_comparison.pdf"), width = 14, height = 10)

par(mfrow = c(2, 2))

# Plot 1: True tau by cohort for Grade 4->5
if (nrow(g4to5_data) > 0) {
  cohort_taus_g4to5 <- g4to5_data[, .(true_tau = mean(true_tau)), by = cohort]
  plot(as.numeric(cohort_taus_g4to5$cohort), cohort_taus_g4to5$true_tau,
       type = "b", pch = 19, col = "blue", lwd = 2,
       xlab = "Cohort Year",
       ylab = expression("True Kendall's" ~ tau),
       main = "Grade 4->5: Copula Strength by Cohort",
       ylim = c(0.5, 1))
  grid()
}

# Plot 2: True tau by cohort for Grade 5->6
if (nrow(g5to6_data) > 0) {
  cohort_taus_g5to6 <- g5to6_data[, .(true_tau = mean(true_tau)), by = cohort]
  plot(as.numeric(cohort_taus_g5to6$cohort), cohort_taus_g5to6$true_tau,
       type = "b", pch = 19, col = "darkgreen", lwd = 2,
       xlab = "Cohort Year",
       ylab = expression("True Kendall's" ~ tau),
       main = "Grade 5->6: Copula Strength by Cohort",
       ylim = c(0.5, 1))
  grid()
}

# Plot 3: CI width by cohort and sample size (Grade 4->5)
if (nrow(g4to5_data) > 0) {
  plot(0, type = "n",
       xlim = range(as.numeric(g4to5_data$cohort)),
       ylim = range(g4to5_data$ci_width),
       xlab = "Cohort Year",
       ylab = "90% CI Width",
       main = "Grade 4->5: Precision by Cohort and Sample Size")
  
  for (n in unique(g4to5_data$sample_size)) {
    subset_data <- g4to5_data[sample_size == n]
    lines(as.numeric(subset_data$cohort), subset_data$ci_width,
          type = "b", pch = 19, lwd = 2,
          col = rainbow(length(unique(g4to5_data$sample_size)))[which(unique(g4to5_data$sample_size) == n)])
  }
  
  legend("topright",
         legend = paste("n =", unique(g4to5_data$sample_size)),
         col = rainbow(length(unique(g4to5_data$sample_size))),
         lwd = 2, pch = 19, bg = "white")
  grid()
}

# Plot 4: Standard deviation of true taus across cohorts
if (nrow(g4to5_data) > 0 && nrow(g5to6_data) > 0) {
  sd_g4to5 <- sd(g4to5_data[sample_size == max(SAMPLE_SIZES)]$true_tau)
  sd_g5to6 <- sd(g5to6_data[sample_size == max(SAMPLE_SIZES)]$true_tau)
  
  barplot(c(sd_g4to5, sd_g5to6),
          names.arg = c("Grade 4->5", "Grade 5->6"),
          col = c("lightblue", "lightgreen"),
          main = "Cohort Variability in True Copula Strength",
          ylab = expression("SD of Kendall's" ~ tau ~ "across cohorts"))
  grid()
}

dev.off()

# Statistical test for cohort differences
cat("\n====================================================================\n")
cat("STATISTICAL ANALYSIS OF COHORT EFFECTS\n")
cat("====================================================================\n\n")

# For Grade 4->5, test if true taus differ significantly across cohorts
if (nrow(g4to5_data) > 0) {
  cat("Grade 4->5 Cohort Analysis:\n")
  
  cohort_taus <- g4to5_data[sample_size == max(SAMPLE_SIZES), 
                             .(true_tau = mean(true_tau)), 
                             by = cohort]
  
  cat("  Mean tau across cohorts:", round(mean(cohort_taus$true_tau), 4), "\n")
  cat("  SD of tau across cohorts:", round(sd(cohort_taus$true_tau), 4), "\n")
  cat("  Range:", round(min(cohort_taus$true_tau), 4), "to", 
      round(max(cohort_taus$true_tau), 4), "\n")
  cat("  Coefficient of variation:", 
      round(sd(cohort_taus$true_tau) / mean(cohort_taus$true_tau) * 100, 2), "%\n\n")
  
  # Compare to bootstrap variability
  typical_bootstrap_sd <- mean(g4to5_data[sample_size == max(SAMPLE_SIZES)]$tau_sd)
  cat("  Typical bootstrap SD:", round(typical_bootstrap_sd, 4), "\n")
  
  if (sd(cohort_taus$true_tau) > typical_bootstrap_sd) {
    cat("  FINDING: Cohort variability EXCEEDS bootstrap variability\n")
    cat("           Cohort effects are meaningful and should be considered.\n\n")
  } else {
    cat("  FINDING: Cohort variability is within bootstrap variability\n")
    cat("           Cohort effects are negligible relative to sampling error.\n\n")
  }
}

# For Grade 5->6
if (nrow(g5to6_data) > 0) {
  cat("Grade 5->6 Cohort Analysis:\n")
  
  cohort_taus <- g5to6_data[sample_size == max(SAMPLE_SIZES), 
                             .(true_tau = mean(true_tau)), 
                             by = cohort]
  
  cat("  Mean tau across cohorts:", round(mean(cohort_taus$true_tau), 4), "\n")
  cat("  SD of tau across cohorts:", round(sd(cohort_taus$true_tau), 4), "\n")
  cat("  Range:", round(min(cohort_taus$true_tau), 4), "to", 
      round(max(cohort_taus$true_tau), 4), "\n")
  cat("  Coefficient of variation:", 
      round(sd(cohort_taus$true_tau) / mean(cohort_taus$true_tau) * 100, 2), "%\n\n")
  
  typical_bootstrap_sd <- mean(g5to6_data[sample_size == max(SAMPLE_SIZES)]$tau_sd)
  cat("  Typical bootstrap SD:", round(typical_bootstrap_sd, 4), "\n")
  
  if (sd(cohort_taus$true_tau) > typical_bootstrap_sd) {
    cat("  FINDING: Cohort variability EXCEEDS bootstrap variability\n")
    cat("           Cohort effects are meaningful.\n\n")
  } else {
    cat("  FINDING: Cohort variability is within bootstrap variability\n")
    cat("           Cohort effects are negligible.\n\n")
  }
}

cat("====================================================================\n")
cat("EXPERIMENT 4 COMPLETE\n")
cat("====================================================================\n\n")

cat("Key Findings:\n")
cat("- Tested copula stability across", length(unique(comparison_table$cohort)), 
    "different cohorts\n")
cat("- Examined Grade 4->5 and Grade 5->6 transitions\n")
cat("- Results saved to: results/exp_4_cohort/\n\n")

cat("Implications for TIMSS-like Cross-Sectional Analysis:\n")
cat("- If cohort effects are negligible: Can pool data across years\n")
cat("- If cohort effects are substantial: Need cohort-specific copulas\n")
cat("- Consider temporal trends in assessment difficulty or curriculum\n\n")

# Save complete workspace
save(all_results, comparison_table, g4to5_data, g5to6_data,
     file = file.path(output_dir, "cohort_experiment.RData"))

cat("Workspace saved for further analysis.\n\n")
