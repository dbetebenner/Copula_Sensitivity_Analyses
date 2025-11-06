################################################################################
# Test Script: Sourced Parallel gofCopula
################################################################################
#
# Purpose: Verify that sourcing the modified gofCopula.R works correctly
# Expected: Parallel version overrides package version, 8-10x speedup
#
################################################################################

cat("================================================================================\n")
cat("TEST: SOURCED PARALLEL gofCopula()\n")
cat("================================================================================\n\n")

# Load copula package (original version)
cat("1. Loading copula package (original)...\n")
library(copula)
cat("   Package version:", as.character(packageVersion("copula")), "\n\n")

# Source the modified parallel version
cat("2. Sourcing modified gofCopula.R...\n")
source("functions/gofCopula_parallel.R")

# Setup test
cat("3. Setting up test...\n")
set.seed(314159)
n <- 1000
N <- 100
data <- rCopula(n, tCopula(0.75, dim = 2, df = 47, df.fixed = TRUE))
copula <- tCopula(dim = 2, df.fixed = TRUE)
n_cores <- min(parallel::detectCores() - 1, 10)
cat("   Sample size:", n, "\n")
cat("   Bootstrap N:", N, "\n")
cat("   Cores to use:", n_cores, "\n\n")

# Test 1: Sequential (verify backward compatibility)
cat("4. Testing SEQUENTIAL (cores=NULL)...\n")
t1 <- system.time({
  r1 <- gofCopula(copula, data, N=N, method="Sn", 
                  estim.method="mpl", cores=NULL)
})
cat("   Time:", sprintf("%.2f", t1[3]), "sec\n")
cat("   Statistic:", sprintf("%.6f", r1$statistic), "\n")
cat("   P-value:", sprintf("%.4f", r1$p.value), "\n")
cat("   ✓ Sequential works\n\n")

# Test 2: Parallel (new feature)
cat("5. Testing PARALLEL (cores=", n_cores, ")...\n", sep="")
t2 <- system.time({
  r2 <- gofCopula(copula, data, N=N, method="Sn", 
                  estim.method="mpl", cores=n_cores)
})
cat("   Time:", sprintf("%.2f", t2[3]), "sec\n")
cat("   Statistic:", sprintf("%.6f", r2$statistic), "\n")
cat("   P-value:", sprintf("%.4f", r2$p.value), "\n")
cat("   ✓ Parallel works\n\n")

# Validation
cat("6. Validation...\n")
speedup <- t1[3] / t2[3]
stat_diff <- abs(r1$statistic - r2$statistic)

cat("   Speedup:", sprintf("%.2fx", speedup), "\n")
cat("   Stat diff:", sprintf("%.2e", stat_diff), "\n")

if (speedup > 5 && stat_diff < 1e-10) {
  cat("\n✓✓✓ SUCCESS ✓✓✓\n")
  cat("\nThe sourced parallel gofCopula() is working correctly!\n")
  cat("No package rebuild needed - just source this file in your scripts.\n\n")
} else {
  cat("\n✗✗✗ VALIDATION FAILED ✗✗✗\n")
  if (speedup <= 5) cat("  - Speedup too low (", sprintf("%.2f", speedup), "x)\n", sep="")
  if (stat_diff >= 1e-10) cat("  - Statistics don't match (diff=", sprintf("%.2e", stat_diff), ")\n", sep="")
}

cat("================================================================================\n")

