################################################################################
### DIAGNOSTIC: Sample Size Effect on GoF Testing
###
### Tests how observed vs bootstrap CvM statistics change with sample size.
### Theory: With smaller n, sampling variability increases, leading to more
### overlap between observed and bootstrap distributions (higher p-values).
################################################################################

source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
require(copula)
require(data.table)

# Load full data
load("Data/Copula_Sensitivity_Data_Set_2.Rdata")

# Create full test condition
pairs_data_full <- create_longitudinal_pairs(
  Copula_Sensitivity_Data_Set_2,
  content_prior = "MATHEMATICS",
  content_current = "MATHEMATICS",
  grade_prior = 4,
  grade_current = 5,
  year_prior = 2010,
  year_current = 2011
)

cat("Full dataset size:", nrow(pairs_data_full), "\n\n")

# Sample sizes to test
sample_sizes <- c(500, 1000, 2500, 5000, nrow(pairs_data_full))
N_BOOTSTRAP <- 50  # Bootstrap samples per sample size

# Storage for results
results_list <- list()

cat("================================================================================\n")
cat("SAMPLE SIZE EXPERIMENT: Effect on GoF Testing\n")
cat("================================================================================\n")
cat("Testing", length(sample_sizes), "sample sizes with", N_BOOTSTRAP, "bootstrap samples each\n")
cat("Sample sizes:", paste(sample_sizes, collapse = ", "), "\n")
cat("================================================================================\n\n")

# Loop over sample sizes
for (i in seq_along(sample_sizes)) {
  n <- sample_sizes[i]
  
  cat("\n")
  cat("################################################################################\n")
  cat("## SAMPLE SIZE:", n, "\n")
  cat("################################################################################\n\n")
  
  # Subsample data
  set.seed(314159 + i)  # Different seed per subsample for variety
  if (n < nrow(pairs_data_full)) {
    idx <- sample(nrow(pairs_data_full), n, replace = FALSE)
    pairs_data <- pairs_data_full[idx, ]
  } else {
    pairs_data <- pairs_data_full
  }
  
  # Create pseudo-observations
  set.seed(314159)  # Same seed for pobs to ensure comparability
  pseudo_obs <- pobs(cbind(pairs_data$SCALE_SCORE_PRIOR, 
                           pairs_data$SCALE_SCORE_CURRENT), 
                     ties.method = "random")
  pseudo_obs <- as.matrix(pseudo_obs)
  
  # Fit t-copula
  cat("Fitting t-copula...\n")
  t_cop <- tCopula(dim = 2, dispstr = "un")
  t_fit <- fitCopula(t_cop, pseudo_obs, method = "mpl")
  
  cat("  rho:", sprintf("%.4f", t_fit@estimate[1]), "\n")
  cat("  df: ", sprintf("%.2f", t_fit@estimate[2]), "\n")
  
  # Create fixed-df copula for GoF
  df_rounded <- round(t_fit@estimate[2])
  t_cop_fixed <- tCopula(param = t_fit@estimate[1], dim = 2, 
                         df = df_rounded, df.fixed = TRUE)
  
  # Calculate observed statistic
  cat("\nCalculating observed statistic...\n")
  temp_result <- copula::gofCopula(
    copula = t_cop_fixed,
    x = pseudo_obs,
    N = 1,
    method = "Sn",
    estim.method = "mpl",
    simulation = "pb",
    verbose = FALSE
  )
  
  observed_stat <- temp_result$statistic
  cat("  Observed CvM:", sprintf("%.6f", observed_stat), "\n\n")
  
  # Run bootstrap loop
  cat("Running", N_BOOTSTRAP, "bootstrap samples...\n")
  bootstrap_stats <- numeric(N_BOOTSTRAP)
  
  for (b in 1:N_BOOTSTRAP) {
    if (b %% 10 == 1) cat("  Bootstrap", b, "-", min(b+9, N_BOOTSTRAP), "...\n")
    
    # Generate from fitted copula
    boot_data <- rCopula(nrow(pseudo_obs), t_cop_fixed)
    
    # Fit to bootstrap data
    boot_fit <- suppressWarnings(
      fitCopula(t_cop, boot_data, method = "mpl")
    )
    boot_cop_fixed <- tCopula(param = boot_fit@estimate[1], dim = 2,
                             df = round(boot_fit@estimate[2]), df.fixed = TRUE)
    
    # Calculate statistic for bootstrap sample
    boot_result <- copula::gofCopula(
      copula = boot_cop_fixed,
      x = boot_data,
      N = 1,
      method = "Sn",
      estim.method = "mpl",
      simulation = "pb",
      verbose = FALSE
    )
    
    bootstrap_stats[b] <- boot_result$statistic
  }
  
  # Calculate summary statistics
  n_exceeding <- sum(bootstrap_stats >= observed_stat)
  p_val <- (n_exceeding + 0.5) / (N_BOOTSTRAP + 1)
  
  # Store results
  results_list[[i]] <- list(
    n = n,
    observed = observed_stat,
    bootstrap_stats = bootstrap_stats,
    bootstrap_mean = mean(bootstrap_stats),
    bootstrap_sd = sd(bootstrap_stats),
    bootstrap_min = min(bootstrap_stats),
    bootstrap_max = max(bootstrap_stats),
    n_exceeding = n_exceeding,
    p_value = p_val,
    ratio_mean = observed_stat / mean(bootstrap_stats),
    ratio_max = observed_stat / max(bootstrap_stats)
  )
  
  # Print summary
  cat("\n--- SUMMARY for n =", n, "---\n")
  cat("Observed:          ", sprintf("%10.6f", observed_stat), "\n")
  cat("Bootstrap mean:    ", sprintf("%10.6f", mean(bootstrap_stats)), "\n")
  cat("Bootstrap SD:      ", sprintf("%10.6f", sd(bootstrap_stats)), "\n")
  cat("Bootstrap range:   ", sprintf("%10.6f", min(bootstrap_stats)), 
      "-", sprintf("%10.6f", max(bootstrap_stats)), "\n")
  cat("N exceeding obs:   ", n_exceeding, "out of", N_BOOTSTRAP, "\n")
  cat("P-value:           ", sprintf("%10.6f", p_val), "\n")
  cat("Obs/Boot mean:     ", sprintf("%.2f", observed_stat / mean(bootstrap_stats)), "x\n")
  cat("Obs/Boot max:      ", sprintf("%.2f", observed_stat / max(bootstrap_stats)), "x\n")
}

cat("\n")
cat("================================================================================\n")
cat("COMPARATIVE SUMMARY: Sample Size Effects\n")
cat("================================================================================\n\n")

# Create summary table
summary_dt <- data.table(
  n = sapply(results_list, function(x) x$n),
  observed = sapply(results_list, function(x) x$observed),
  boot_mean = sapply(results_list, function(x) x$bootstrap_mean),
  boot_sd = sapply(results_list, function(x) x$bootstrap_sd),
  p_value = sapply(results_list, function(x) x$p_value),
  ratio = sapply(results_list, function(x) x$ratio_mean),
  n_exceeding = sapply(results_list, function(x) x$n_exceeding)
)

print(summary_dt, digits = 4)

cat("\n")
cat("KEY FINDINGS:\n")
cat("1. Observed CvM scales with n (compare n=500 vs n=28,567)\n")
cat("2. Bootstrap mean also scales with n\n")
cat("3. P-value changes reflect power (higher p = lower power at small n)\n")
cat("4. Ratio (Obs/Boot mean) shows strength of evidence\n")
cat("\n")

################################################################################
# VISUALIZATIONS
################################################################################

# Set up multi-panel plot
pdf("sample_size_effect_on_gof.pdf", width = 14, height = 10)
par(mfrow = c(3, 2), mar = c(4, 4, 3, 1))

# Plot 1-5: Histograms for each sample size
for (i in seq_along(results_list)) {
  res <- results_list[[i]]
  
  hist(res$bootstrap_stats, 
       breaks = 20,
       main = paste0("n = ", res$n, " (p = ", sprintf("%.4f", res$p_value), ")"),
       xlab = "CvM Statistic",
       col = "lightblue",
       xlim = c(0, max(res$observed, max(res$bootstrap_stats)) * 1.1))
  
  abline(v = res$observed, col = "red", lwd = 3, lty = 1)
  abline(v = res$bootstrap_mean, col = "blue", lwd = 2, lty = 2)
  
  legend("topright",
         legend = c(
           sprintf("Obs: %.3f", res$observed),
           sprintf("Boot: %.3f ± %.3f", res$bootstrap_mean, res$bootstrap_sd),
           sprintf("Ratio: %.1fx", res$ratio_mean)
         ),
         col = c("red", "blue", NA),
         lty = c(1, 2, NA),
         lwd = c(3, 2, NA),
         bty = "n",
         cex = 0.8)
}

# Plot 6: Summary comparison
plot(NULL, xlim = c(0.5, length(sample_sizes) + 0.5), 
     ylim = c(0, max(sapply(results_list, function(x) x$observed)) * 1.1),
     xaxt = "n",
     xlab = "Sample Size",
     ylab = "CvM Statistic",
     main = "Observed vs Bootstrap Statistics by Sample Size")

axis(1, at = 1:length(sample_sizes), 
     labels = sample_sizes, las = 2, cex.axis = 0.8)

# Add bootstrap mean with error bars (SD)
for (i in seq_along(results_list)) {
  res <- results_list[[i]]
  
  # Bootstrap mean and range
  points(i, res$bootstrap_mean, pch = 19, col = "blue", cex = 1.5)
  arrows(i, res$bootstrap_min, i, res$bootstrap_max, 
         angle = 90, code = 3, length = 0.1, col = "blue", lwd = 2)
  
  # Observed
  points(i, res$observed, pch = 17, col = "red", cex = 2)
}

legend("topleft",
       legend = c("Observed", "Bootstrap Mean", "Bootstrap Range"),
       col = c("red", "blue", "blue"),
       pch = c(17, 19, NA),
       lty = c(NA, NA, 1),
       lwd = c(NA, NA, 2),
       bty = "n",
       cex = 0.9)

par(mfrow = c(1, 1))
dev.off()

cat("\nPlot saved to: sample_size_effect_on_gof.pdf\n")

# Additional plot: P-value vs n
pdf("pvalue_vs_sample_size.pdf", width = 10, height = 6)
par(mar = c(5, 4, 3, 1))

plot(summary_dt$n, summary_dt$p_value,
     type = "b",
     pch = 19,
     col = "darkblue",
     lwd = 2,
     log = "x",
     xlab = "Sample Size (n)",
     ylab = "P-value",
     main = "Statistical Power: P-value vs Sample Size",
     ylim = c(0, max(summary_dt$p_value) * 1.1))

abline(h = 0.05, col = "red", lty = 2, lwd = 2)
text(min(summary_dt$n) * 1.2, 0.05, "α = 0.05", pos = 3, col = "red")

# Add text annotations
for (i in 1:nrow(summary_dt)) {
  text(summary_dt$n[i], summary_dt$p_value[i],
       sprintf("%.3f", summary_dt$p_value[i]),
       pos = 3, cex = 0.8, offset = 0.5)
}

dev.off()

cat("Plot saved to: pvalue_vs_sample_size.pdf\n\n")

cat("================================================================================\n")
cat("EXPERIMENT COMPLETE\n")
cat("================================================================================\n")