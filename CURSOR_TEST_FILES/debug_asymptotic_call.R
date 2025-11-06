################################################################################
### DEBUG: Direct call to gofCopula with N=0
################################################################################

require(copula)

cat("Testing direct gofCopula() calls with N=0...\n\n")

# Simple test data
set.seed(123)
n <- 1000
cop_true <- normalCopula(0.7, dim = 2)
test_data <- rCopula(n, cop_true)

# Fit Gaussian copula
cop_fit <- normalCopula(dim = 2)
fit <- fitCopula(cop_fit, test_data, method = "ml")

cat("Fitted Gaussian copula, rho =", coef(fit), "\n\n")

cat("====================================================================\n")
cat("TEST 1: gofCopula with N=0, no simulation parameter\n")
cat("====================================================================\n")

tryCatch({
  gof1 <- gofCopula(fit@copula, 
                    x = test_data,
                    method = "Sn",
                    N = 0,
                    verbose = TRUE)
  cat("SUCCESS!\n")
  cat("  Statistic:", gof1$statistic, "\n")
  cat("  P-value:", gof1$p.value, "\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n")
})

cat("\n====================================================================\n")
cat("TEST 2: gofCopula with N=0, simulation='mult'\n")
cat("====================================================================\n")

tryCatch({
  gof2 <- gofCopula(fit@copula, 
                    x = test_data,
                    method = "Sn",
                    simulation = "mult",
                    N = 0,
                    verbose = TRUE)
  cat("SUCCESS!\n")
  cat("  Statistic:", gof2$statistic, "\n")
  cat("  P-value:", gof2$p.value, "\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n")
})

cat("\n====================================================================\n")
cat("TEST 3: Check gofCopula help documentation\n")
cat("====================================================================\n")

cat("\nFrom ?gofCopula:\n")
cat("  N: number of bootstrap or multiplier samples\n")
cat("     If N=0, asymptotic p-values are computed (if available)\n\n")

cat("====================================================================\n")
cat("TEST 4: Try without specifying N at all\n")
cat("====================================================================\n")

tryCatch({
  gof4 <- gofCopula(fit@copula, 
                    x = test_data,
                    method = "Sn",
                    verbose = TRUE)
  cat("SUCCESS!\n")
  cat("  Statistic:", gof4$statistic, "\n")
  cat("  P-value:", gof4$p.value, "\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n")
})

cat("\n====================================================================\n")
cat("TEST 5: Try with N=100 to verify bootstrap works\n")
cat("====================================================================\n")

tryCatch({
  gof5 <- gofCopula(fit@copula, 
                    x = test_data,
                    method = "Sn",
                    simulation = "pb",
                    N = 100,
                    verbose = TRUE)
  cat("SUCCESS!\n")
  cat("  Statistic:", gof5$statistic, "\n")
  cat("  P-value:", gof5$p.value, "\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n")
})

cat("\n")

