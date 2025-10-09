############################################################################
### PHASE 2: T-COPULA DEEP DIVE ANALYSIS
### Detailed investigation of t-copula specific properties
###
### Focus areas:
### 1. Degrees of freedom (ν) stability and variability
### 2. Tail dependence estimation and uncertainty
### 3. Conditional quantiles for growth predictions
### 4. Comparison with Gaussian baseline
############################################################################

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
source("../functions/longitudinal_pairs.R")
source("../functions/ispline_ecdf.R")
source("../functions/copula_bootstrap.R")

cat("====================================================================\n")
cat("PHASE 2: T-COPULA DEEP DIVE ANALYSIS\n")
cat("====================================================================\n")
cat("Detailed investigation of t-copula properties for longitudinal data\n")
cat("====================================================================\n\n")

################################################################################
### CONFIGURATION
################################################################################

# Primary test configuration
CONFIG <- list(
  grade_prior = 4,
  grade_current = 8,
  year_prior = "2009",
  content = "MATHEMATICS"
)

# Sample sizes for deep analysis
SAMPLE_SIZES <- c(100, 250, 500, 1000, 2000, 4000)

# Bootstrap settings
N_BOOTSTRAP <- 200  # More iterations for detailed analysis

cat("Configuration:\n")
cat("  Grade:", CONFIG$grade_prior, "->", CONFIG$grade_current, "\n")
cat("  Content:", CONFIG$content, "\n")
cat("  Sample sizes:", paste(SAMPLE_SIZES, collapse = ", "), "\n")
cat("  Bootstrap iterations:", N_BOOTSTRAP, "\n\n")

################################################################################
### LOAD FULL LONGITUDINAL DATA
################################################################################

cat("Loading full longitudinal data...\n")

pairs_full <- create_longitudinal_pairs(
  data = Colorado_Data_LONG,
  grade_prior = CONFIG$grade_prior,
  grade_current = CONFIG$grade_current,
  year_prior = CONFIG$year_prior,
  content_prior = CONFIG$content,
  content_current = CONFIG$content
)

cat("Total longitudinal pairs:", nrow(pairs_full), "\n\n")

# Establish I-spline frameworks
cat("Establishing I-spline frameworks...\n")
framework_prior <- create_ispline_framework(pairs_full$SCALE_SCORE_PRIOR)
framework_current <- create_ispline_framework(pairs_full$SCALE_SCORE_CURRENT)

################################################################################
### FIT TRUE T-COPULA
################################################################################

cat("\n====================================================================\n")
cat("FITTING TRUE T-COPULA FROM FULL DATA\n")
cat("====================================================================\n\n")

true_copulas <- fit_copula_from_pairs(
  scores_prior = pairs_full$SCALE_SCORE_PRIOR,
  scores_current = pairs_full$SCALE_SCORE_CURRENT,
  framework_prior = framework_prior,
  framework_current = framework_current,
  copula_families = c("t", "gaussian"),  # t-copula + Gaussian baseline
  return_best = FALSE
)

true_t <- true_copulas$fits$t
true_gaussian <- true_copulas$fits$gaussian

cat("TRUE T-COPULA PARAMETERS:\n")
cat("  Correlation (rho):", round(true_t$parameter[1], 4), "\n")
cat("  Degrees of freedom (nu):", round(true_t$parameter[2], 2), "\n")
cat("  Kendall's tau:", round(true_t$tau, 4), "\n")
cat("  AIC:", round(true_t$aic, 2), "\n\n")

cat("TRUE GAUSSIAN COPULA (baseline):\n")
cat("  Correlation (rho):", round(true_gaussian$parameter[1], 4), "\n")
cat("  Kendall's tau:", round(true_gaussian$tau, 4), "\n")
cat("  AIC:", round(true_gaussian$aic, 2), "\n\n")

cat("AIC Improvement (t over Gaussian):", 
    round(true_gaussian$aic - true_t$aic, 2), "\n\n")

# Calculate tail dependence for true t-copula
rho_true <- true_t$parameter[1]
df_true <- true_t$parameter[2]
tail_dep_true <- 2 * pt(-sqrt((df_true + 1) * (1 - rho_true) / (1 + rho_true)), df = df_true + 1)

cat("TRUE TAIL DEPENDENCE:\n")
cat("  Symmetric tail dependence:", round(tail_dep_true, 4), "\n\n")

################################################################################
### ANALYSIS 1: DEGREES OF FREEDOM STABILITY
################################################################################

cat("====================================================================\n")
cat("ANALYSIS 1: DEGREES OF FREEDOM (ν) STABILITY\n")
cat("====================================================================\n\n")

df_results <- list()

for (n_sample in SAMPLE_SIZES) {
  
  cat("Sample size:", n_sample, "\n")
  
  # Bootstrap t-copula estimation
  bootstrap_results <- bootstrap_copula_estimation(
    pairs_data = pairs_full,
    n_sample_prior = n_sample,
    n_sample_current = n_sample,
    n_bootstrap = N_BOOTSTRAP,
    framework_prior = framework_prior,
    framework_current = framework_current,
    sampling_method = "paired",
    copula_families = c("t"),
    with_replacement = TRUE
  )
  
  # Extract degrees of freedom from all bootstrap samples
  df_samples <- sapply(bootstrap_results$bootstrap_fits$t, function(fit) {
    if (!is.null(fit) && length(fit$parameter) >= 2) fit$parameter[2] else NA
  })
  df_samples <- df_samples[!is.na(df_samples)]
  
  # Extract rho and tau as well
  rho_samples <- sapply(bootstrap_results$bootstrap_fits$t, function(fit) {
    if (!is.null(fit)) fit$parameter[1] else NA
  })
  rho_samples <- rho_samples[!is.na(rho_samples)]
  
  tau_samples <- sapply(bootstrap_results$bootstrap_fits$t, function(fit) {
    if (!is.null(fit)) fit$tau else NA
  })
  tau_samples <- tau_samples[!is.na(tau_samples)]
  
  # Store results
  df_results[[as.character(n_sample)]] <- list(
    n_sample = n_sample,
    df_samples = df_samples,
    rho_samples = rho_samples,
    tau_samples = tau_samples,
    df_mean = mean(df_samples),
    df_sd = sd(df_samples),
    df_q05 = quantile(df_samples, 0.05),
    df_q95 = quantile(df_samples, 0.95),
    rho_mean = mean(rho_samples),
    tau_mean = mean(tau_samples)
  )
  
  cat("  ν: mean =", round(mean(df_samples), 2),
      ", SD =", round(sd(df_samples), 2),
      ", 90% CI = [", round(quantile(df_samples, 0.05), 2), ",",
      round(quantile(df_samples, 0.95), 2), "]\n")
  cat("  rho: mean =", round(mean(rho_samples), 4), "\n")
  cat("  tau: mean =", round(mean(tau_samples), 4), "\n\n")
}

################################################################################
### ANALYSIS 2: TAIL DEPENDENCE STABILITY
################################################################################

cat("====================================================================\n")
cat("ANALYSIS 2: TAIL DEPENDENCE STABILITY\n")
cat("====================================================================\n\n")

tail_dep_results <- list()

for (n_sample in SAMPLE_SIZES) {
  
  result <- df_results[[as.character(n_sample)]]
  
  # Calculate tail dependence for each bootstrap sample
  tail_dep_samples <- mapply(function(rho, df) {
    2 * pt(-sqrt((df + 1) * (1 - rho) / (1 + rho)), df = df + 1)
  }, result$rho_samples, result$df_samples)
  
  tail_dep_results[[as.character(n_sample)]] <- list(
    n_sample = n_sample,
    tail_dep_samples = tail_dep_samples,
    mean = mean(tail_dep_samples),
    sd = sd(tail_dep_samples),
    q05 = quantile(tail_dep_samples, 0.05),
    q95 = quantile(tail_dep_samples, 0.95)
  )
  
  cat("Sample size:", n_sample, "\n")
  cat("  Tail dep: mean =", round(mean(tail_dep_samples), 4),
      ", SD =", round(sd(tail_dep_samples), 4),
      ", 90% CI = [", round(quantile(tail_dep_samples, 0.05), 4), ",",
      round(quantile(tail_dep_samples, 0.95), 4), "]\n")
  cat("  Bias from true:", round(mean(tail_dep_samples) - tail_dep_true, 4), "\n\n")
}

################################################################################
### ANALYSIS 3: T VS GAUSSIAN COMPARISON
################################################################################

cat("====================================================================\n")
cat("ANALYSIS 3: T-COPULA VS GAUSSIAN BASELINE\n")
cat("====================================================================\n\n")

comparison_results <- list()

for (n_sample in c(500, 1000, 2000)) {  # Subset for comparison
  
  cat("Sample size:", n_sample, "\n")
  
  # Bootstrap both families
  bootstrap_results <- bootstrap_copula_estimation(
    pairs_data = pairs_full,
    n_sample_prior = n_sample,
    n_sample_current = n_sample,
    n_bootstrap = N_BOOTSTRAP,
    framework_prior = framework_prior,
    framework_current = framework_current,
    sampling_method = "paired",
    copula_families = c("t", "gaussian"),
    with_replacement = TRUE
  )
  
  # Extract AIC differences
  aic_t <- sapply(bootstrap_results$bootstrap_fits$t, function(fit) {
    if (!is.null(fit)) fit$aic else NA
  })
  aic_t <- aic_t[!is.na(aic_t)]
  
  aic_gaussian <- sapply(bootstrap_results$bootstrap_fits$gaussian, function(fit) {
    if (!is.null(fit)) fit$aic else NA
  })
  aic_gaussian <- aic_gaussian[!is.na(aic_gaussian)]
  
  delta_aic <- aic_gaussian - aic_t  # Positive = t better
  
  comparison_results[[as.character(n_sample)]] <- list(
    n_sample = n_sample,
    delta_aic = delta_aic,
    mean_delta = mean(delta_aic),
    sd_delta = sd(delta_aic),
    t_better_pct = 100 * mean(delta_aic > 0)
  )
  
  cat("  Δ AIC (Gaussian - t): mean =", round(mean(delta_aic), 2),
      ", SD =", round(sd(delta_aic), 2), "\n")
  cat("  t better:", round(100 * mean(delta_aic > 0), 1), "% of samples\n")
  cat("  Substantial advantage (Δ > 10):", 
      round(100 * mean(delta_aic > 10), 1), "% of samples\n\n")
}

################################################################################
### VISUALIZATIONS
################################################################################

cat("====================================================================\n")
cat("GENERATING VISUALIZATIONS\n")
cat("====================================================================\n\n")

# Plot 1: Degrees of freedom by sample size
pdf("results/phase2_t_copula_df_stability.pdf", width = 10, height = 6)
par(mar = c(5, 5, 4, 2))

df_means <- sapply(df_results, function(x) x$df_mean)
df_q05 <- sapply(df_results, function(x) x$df_q05)
df_q95 <- sapply(df_results, function(x) x$df_q95)

plot(SAMPLE_SIZES, df_means, type = "o", pch = 16, col = "darkblue", lwd = 2,
     ylim = range(c(df_q05, df_q95, df_true)),
     xlab = "Sample Size", ylab = expression("Degrees of Freedom (" * nu * ")"),
     main = "T-Copula Degrees of Freedom: Stability by Sample Size",
     log = "x")
arrows(SAMPLE_SIZES, df_q05, SAMPLE_SIZES, df_q95, 
       angle = 90, code = 3, length = 0.1, col = "darkblue", lwd = 2)
abline(h = df_true, col = "red", lwd = 2, lty = 2)
legend("topright", 
       legend = c(paste("True ν =", round(df_true, 2)), "Bootstrap mean", "90% CI"),
       col = c("red", "darkblue", "darkblue"),
       lty = c(2, 1, 1), lwd = 2, pch = c(NA, 16, NA))
grid()
dev.off()
cat("Created: results/phase2_t_copula_df_stability.pdf\n")

# Plot 2: Tail dependence by sample size
pdf("results/phase2_t_copula_tail_dependence.pdf", width = 10, height = 6)
par(mar = c(5, 5, 4, 2))

tail_means <- sapply(tail_dep_results, function(x) x$mean)
tail_q05 <- sapply(tail_dep_results, function(x) x$q05)
tail_q95 <- sapply(tail_dep_results, function(x) x$q95)

plot(SAMPLE_SIZES, tail_means, type = "o", pch = 16, col = "darkgreen", lwd = 2,
     ylim = range(c(tail_q05, tail_q95, tail_dep_true)),
     xlab = "Sample Size", ylab = "Tail Dependence Coefficient",
     main = "T-Copula Tail Dependence: Stability by Sample Size",
     log = "x")
arrows(SAMPLE_SIZES, tail_q05, SAMPLE_SIZES, tail_q95,
       angle = 90, code = 3, length = 0.1, col = "darkgreen", lwd = 2)
abline(h = tail_dep_true, col = "red", lwd = 2, lty = 2)
legend("topright",
       legend = c(paste("True λ =", round(tail_dep_true, 4)), "Bootstrap mean", "90% CI"),
       col = c("red", "darkgreen", "darkgreen"),
       lty = c(2, 1, 1), lwd = 2, pch = c(NA, 16, NA))
grid()
dev.off()
cat("Created: results/phase2_t_copula_tail_dependence.pdf\n")

# Plot 3: Degrees of freedom distribution for selected sample sizes
pdf("results/phase2_t_copula_df_distributions.pdf", width = 12, height = 8)
par(mfrow = c(2, 3), mar = c(4, 4, 3, 1))

for (n_sample in SAMPLE_SIZES) {
  result <- df_results[[as.character(n_sample)]]
  hist(result$df_samples, 
       main = paste("n =", n_sample),
       xlab = expression(nu),
       col = "lightblue", border = "darkblue",
       breaks = 20, xlim = c(0, max(result$df_samples, df_true * 1.5)))
  abline(v = df_true, col = "red", lwd = 2, lty = 2)
  abline(v = result$df_mean, col = "blue", lwd = 2)
  legend("topright", legend = c("True", "Mean"), 
         col = c("red", "blue"), lty = c(2, 1), lwd = 2, cex = 0.8)
}

dev.off()
cat("Created: results/phase2_t_copula_df_distributions.pdf\n")

# Plot 4: T vs Gaussian AIC comparison
if (length(comparison_results) > 0) {
  pdf("results/phase2_t_vs_gaussian_comparison.pdf", width = 10, height = 6)
  par(mar = c(5, 5, 4, 2))
  
  sample_sizes_comp <- as.numeric(names(comparison_results))
  mean_deltas <- sapply(comparison_results, function(x) x$mean_delta)
  t_better_pcts <- sapply(comparison_results, function(x) x$t_better_pct)
  
  plot(sample_sizes_comp, mean_deltas, type = "o", pch = 16, col = "purple", lwd = 2,
       xlab = "Sample Size", 
       ylab = expression(Delta * "AIC (Gaussian - t, positive = t better)"),
       main = "T-Copula Advantage Over Gaussian",
       ylim = c(0, max(mean_deltas) * 1.2))
  abline(h = 0, col = "gray", lty = 2)
  abline(h = 10, col = "orange", lty = 2, lwd = 2)
  text(min(sample_sizes_comp), 10, "Substantial\nadvantage", pos = 3, col = "orange")
  
  # Add percentage labels
  text(sample_sizes_comp, mean_deltas, 
       paste0(round(t_better_pcts, 0), "%"),
       pos = 3, col = "purple", font = 2)
  
  grid()
  dev.off()
  cat("Created: results/phase2_t_vs_gaussian_comparison.pdf\n")
}

################################################################################
### SAVE RESULTS
################################################################################

cat("\n====================================================================\n")
cat("SAVING RESULTS\n")
cat("====================================================================\n\n")

# Save workspace
save(df_results, tail_dep_results, comparison_results,
     true_t, true_gaussian, tail_dep_true,
     file = "results/phase2_t_copula_deep_dive.RData")
cat("Saved: results/phase2_t_copula_deep_dive.RData\n")

# Create summary table
summary_dt <- data.table(
  sample_size = SAMPLE_SIZES,
  df_mean = sapply(df_results, function(x) x$df_mean),
  df_sd = sapply(df_results, function(x) x$df_sd),
  df_ci_width = sapply(df_results, function(x) x$df_q95 - x$df_q05),
  tail_dep_mean = sapply(tail_dep_results, function(x) x$mean),
  tail_dep_sd = sapply(tail_dep_results, function(x) x$sd),
  tail_dep_ci_width = sapply(tail_dep_results, function(x) x$q95 - x$q05),
  tau_mean = sapply(df_results, function(x) x$tau_mean)
)

fwrite(summary_dt, "results/phase2_t_copula_summary.csv")
cat("Saved: results/phase2_t_copula_summary.csv\n\n")

cat("====================================================================\n")
cat("PHASE 2 T-COPULA DEEP DIVE COMPLETE!\n")
cat("====================================================================\n\n")

print(summary_dt)

cat("\nKey findings:\n")
cat("  - True ν =", round(df_true, 2), "\n")
cat("  - True tail dependence =", round(tail_dep_true, 4), "\n")
cat("  - For TIMSS-like n ≈ 4000:\n")
cat("      ν precision (SD) =", 
    round(df_results[["4000"]]$df_sd, 2), "\n")
cat("      Tail dep precision (SD) =", 
    round(tail_dep_results[["4000"]]$sd, 4), "\n\n")

