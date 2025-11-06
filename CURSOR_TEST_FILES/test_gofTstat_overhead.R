################################################################################
### Microbenchmark: gofCopula() vs. manual gofTstat() + Rosenblatt
###
### Purpose: Determine if manual approach adds overhead before implementing
###          full parallel system
################################################################################

require(copula)
require(data.table)

cat("====================================================================\n")
cat("MICROBENCHMARK: gofTstat() Overhead Test\n")
cat("====================================================================\n\n")

# Create test data
set.seed(314159)
n <- 28567  # Realistic sample size
rho <- 0.75
df <- 47

# Generate from t-copula
t_cop <- tCopula(param = rho, dim = 2, df = df, df.fixed = TRUE)
pseudo_obs <- rCopula(n, t_cop)

cat("Test setup:\n")
cat("  Sample size:", n, "\n")
cat("  Copula: t-copula (rho=", rho, ", df=", df, ")\n\n")

################################################################################
### Method 1: gofCopula() - Current approach
################################################################################

cat("Method 1: copula::gofCopula() [CURRENT]\n")
cat("  Approach: Single function call, internal handling\n")

start1 <- Sys.time()
result1 <- copula::gofCopula(
  copula = t_cop,
  x = pseudo_obs,
  N = 1,  # Just get statistic
  method = "Sn",
  estim.method = "mpl",
  simulation = "pb",
  verbose = FALSE
)
end1 <- Sys.time()
time1 <- as.numeric(difftime(end1, start1, units = "secs"))

cat("  Statistic:", result1$statistic, "\n")
cat("  Time:", round(time1, 4), "seconds\n\n")

################################################################################
### Method 2: Manual gofTstat() + Rosenblatt transform
################################################################################

cat("Method 2: Manual gofTstat() + cCopula() [PROPOSED]\n")
cat("  Approach: Explicit Rosenblatt transform + statistic\n")

start2 <- Sys.time()

# Step 2a: Rosenblatt transform
u_rosenblatt <- cCopula(pseudo_obs, copula = t_cop)

# Step 2b: Calculate statistic
stat2 <- gofTstat(u_rosenblatt, method = "Sn", copula = t_cop)

end2 <- Sys.time()
time2 <- as.numeric(difftime(end2, start2, units = "secs"))

cat("  Statistic:", stat2, "\n")
cat("  Time:", round(time2, 4), "seconds\n\n")

################################################################################
### Method 3: Just gofTstat() without Rosenblatt (check if needed)
################################################################################

cat("Method 3: gofTstat() directly on pseudo-obs [TEST]\n")
cat("  Approach: Skip Rosenblatt transform\n")

start3 <- Sys.time()
stat3 <- tryCatch({
  gofTstat(pseudo_obs, method = "Sn", copula = t_cop)
}, error = function(e) {
  cat("  ERROR:", e$message, "\n")
  NA
})
end3 <- Sys.time()
time3 <- as.numeric(difftime(end3, start3, units = "secs"))

if (!is.na(stat3)) {
  cat("  Statistic:", stat3, "\n")
  cat("  Time:", round(time3, 4), "seconds\n\n")
} else {
  cat("  (Rosenblatt transform IS required)\n\n")
}

################################################################################
### Comparison
################################################################################

cat("====================================================================\n")
cat("RESULTS COMPARISON\n")
cat("====================================================================\n\n")

cat("Statistics match:\n")
cat("  Method 1 (gofCopula):", sprintf("%.10f", result1$statistic), "\n")
cat("  Method 2 (manual):   ", sprintf("%.10f", stat2), "\n")
cat("  Difference:          ", sprintf("%.2e", abs(result1$statistic - stat2)), "\n\n")

if (abs(result1$statistic - stat2) < 1e-10) {
  cat("  ✓ Statistics IDENTICAL (difference < 1e-10)\n\n")
} else {
  cat("  ✗ Statistics DIFFER (investigate!)\n\n")
}

cat("Performance:\n")
cat("  Method 1:", sprintf("%6.4f", time1), "sec\n")
cat("  Method 2:", sprintf("%6.4f", time2), "sec\n")
cat("  Ratio:   ", sprintf("%6.2f", time2 / time1), "x\n\n")

if (time2 < time1) {
  cat("  ✓ Manual approach FASTER by", sprintf("%.1f%%", (1 - time2/time1)*100), "\n")
  speedup_potential <- time1 / time2
  cat("  → With parallelization, expect", sprintf("%.1fx", speedup_potential), 
      "base speedup + core multiplier\n\n")
} else {
  cat("  ✗ Manual approach SLOWER by", sprintf("%.1f%%", (time2/time1 - 1)*100), "\n")
  cat("  → May NOT be worth parallelizing if overhead dominates\n\n")
}

cat("====================================================================\n")
cat("BREAKDOWN: Where is the time spent?\n")
cat("====================================================================\n\n")

# Test Rosenblatt transform alone
start_r <- Sys.time()
u_r_test <- cCopula(pseudo_obs, copula = t_cop)
end_r <- Sys.time()
time_rosenblatt <- as.numeric(difftime(end_r, start_r, units = "secs"))

# Test gofTstat alone
start_s <- Sys.time()
stat_test <- gofTstat(u_rosenblatt, method = "Sn", copula = t_cop)
end_s <- Sys.time()
time_statistic <- as.numeric(difftime(end_s, start_s, units = "secs"))

cat("Time breakdown (Method 2):\n")
cat("  Rosenblatt transform:", sprintf("%6.4f", time_rosenblatt), "sec",
    sprintf("(%3.0f%%)", 100 * time_rosenblatt / time2), "\n")
cat("  gofTstat():          ", sprintf("%6.4f", time_statistic), "sec",
    sprintf("(%3.0f%%)", 100 * time_statistic / time2), "\n")
cat("  Total:               ", sprintf("%6.4f", time2), "sec\n\n")

if (time_rosenblatt > time_statistic * 2) {
  cat("  ⚠️  Rosenblatt transform is the bottleneck!\n")
  cat("  → Parallelizing may not help much if transform isn't parallelizable\n\n")
}

cat("====================================================================\n")
cat("CONCLUSION\n")
cat("====================================================================\n\n")

if (abs(result1$statistic - stat2) < 1e-10 && time2 < time1 * 0.9) {
  cat("✓✓✓ PROCEED WITH PARALLEL IMPLEMENTATION ✓✓✓\n\n")
  cat("The manual approach is:\n")
  cat("  - Mathematically equivalent (statistics match)\n")
  cat("  - Faster than gofCopula() (potential for speedup)\n")
  cat("  - Worth parallelizing\n\n")
  cat("Expected speedup with 10 cores:", sprintf("%.1fx", 10 * time1 / time2), "\n")
} else if (abs(result1$statistic - stat2) >= 1e-10) {
  cat("✗✗✗ DO NOT PROCEED ✗✗✗\n\n")
  cat("Statistics don't match - manual approach is incorrect!\n")
  cat("Need to investigate implementation before parallelizing.\n\n")
} else {
  cat("⚠️  CAUTION ⚠️\n\n")
  cat("Manual approach is slower than gofCopula().\n")
  cat("Parallelization may not provide expected speedup.\n")
  cat("Consider:\n")
  cat("  1. Is the overhead from Rosenblatt transform?\n")
  cat("  2. Does gofCopula() have internal optimizations?\n")
  cat("  3. Will parallel gains outweigh overhead?\n\n")
}

cat("====================================================================\n")

