################################################################################
### DEEP DIVE: Inspect gofCopula() internal bootstrap behavior
################################################################################

require(copula)

cat("====================================================================\n")
cat("DEEP DIAGNOSTIC: gofCopula() bootstrap mechanism\n")
cat("====================================================================\n\n")

# Simple test data
set.seed(123)
n <- 1000
cop_true <- normalCopula(0.7, dim = 2)
test_data <- rCopula(n, cop_true)

cat("Test setup:\n")
cat("  True copula: Gaussian with rho = 0.7\n")
cat("  Sample size: n =", n, "\n")
cat("  Bootstrap samples: N = 10\n\n")

# Fit different families
families <- list(
  gaussian = normalCopula(dim = 2),
  clayton = claytonCopula(dim = 2),
  frank = frankCopula(dim = 2)
)

cat("====================================================================\n")
cat("TESTING: Do manually-run bootstraps give varying p-values?\n")
cat("====================================================================\n\n")

manual_results <- list()

for (fname in names(families)) {
  cat("Family:", fname, "\n")
  
  # Fit
  fit <- fitCopula(families[[fname]], test_data, method = "ml")
  cat("  Parameter:", coef(fit), "\n")
  
  # Manually compute GoF statistic from data
  obs_stat <- copula:::gofTn(fit@copula, test_data, method = "Sn")
  cat("  Observed statistic:", obs_stat, "\n")
  
  # Manually run bootstrap
  boot_stats <- numeric(10)
  for (b in 1:10) {
    # Generate bootstrap sample from fitted copula
    boot_sample <- rCopula(n, fit@copula)
    # Compute statistic for bootstrap sample
    boot_stats[b] <- copula:::gofTn(fit@copula, boot_sample, method = "Sn")
  }
  
  cat("  Bootstrap statistics:\n")
  print(sort(boot_stats))
  
  # Compute p-value
  pval <- mean(boot_stats >= obs_stat)
  cat("  Manual p-value:", pval, "\n\n")
  
  manual_results[[fname]] <- pval
}

cat("Manual p-values (should vary):\n")
print(unlist(manual_results))
cat("\nAre manual p-values identical?:", length(unique(unlist(manual_results))) == 1, "\n\n")

cat("====================================================================\n")
cat("TESTING: gofCopula() with same data\n")
cat("====================================================================\n\n")

gof_results <- list()

for (fname in names(families)) {
  cat("Family:", fname, "\n")
  
  fit <- fitCopula(families[[fname]], test_data, method = "ml")
  
  gof <- gofCopula(fit@copula, 
                   x = test_data,
                   method = "Sn",
                   simulation = "pb",
                   N = 10,
                   verbose = FALSE)
  
  cat("  gofCopula() p-value:", gof$p.value, "\n\n")
  
  gof_results[[fname]] <- gof$p.value
}

cat("gofCopula() p-values:\n")
print(unlist(gof_results))
cat("\nAre gofCopula() p-values identical?:", length(unique(unlist(gof_results))) == 1, "\n\n")

cat("====================================================================\n")
cat("TESTING: Does the SAME fitted copula give different p-values?\n")
cat("====================================================================\n\n")

# Fit once
fit_gaussian <- fitCopula(normalCopula(dim = 2), test_data, method = "ml")

# Run gofCopula 5 times
repeated_pvals <- numeric(5)
for (i in 1:5) {
  gof <- gofCopula(fit_gaussian@copula, 
                   x = test_data,
                   method = "Sn",
                   simulation = "pb",
                   N = 10,
                   verbose = FALSE)
  repeated_pvals[i] <- gof$p.value
  cat("  Run", i, "p-value:", gof$p.value, "\n")
}

cat("\nAre repeated p-values identical?:", length(unique(repeated_pvals)) == 1, "\n")

if (length(unique(repeated_pvals)) > 1) {
  cat("✓ gofCopula() varies across runs (as expected)\n\n")
} else {
  cat("✗ gofCopula() returns same p-value every time (BUG!)\n\n")
}

cat("====================================================================\n")
cat("HYPOTHESIS: The bug is in our pipeline, not gofCopula()\n")
cat("====================================================================\n\n")

cat("NEXT STEP: Check if pseudo_obs matrix is being modified/reused\n")
cat("between copula fits in fit_copula_from_pairs()\n\n")

cat("Specifically check:\n")
cat("  1. Is pseudo_obs being passed by reference and modified?\n")
cat("  2. Is there a shared state variable being reused?\n")
cat("  3. Are we calling gofCopula() with the wrong copula object?\n\n")

