################################################################################
### QUICK TEST: Does gofKendallCvM() work with correct parameters?
################################################################################

library(gofCopula)
library(copula)

cat("====================================================================\n")
cat("QUICK TEST: gofKendallCvM() with correct parameters\n")
cat("====================================================================\n\n")

# Create small test data
set.seed(123)
n <- 500
cop <- normalCopula(0.7, dim = 2)
test_data <- rCopula(n, cop)

cat("Test data: n =", n, "\n\n")

# Test each family we care about
families <- c("normal", "clayton", "gumbel", "frank")

for (fam in families) {
  cat("Testing:", fam, "... ")
  
  start_time <- Sys.time()
  
  result <- try({
    gof <- gofKendallCvM(
      copula = fam,
      x = test_data,
      M = 10,
      param.est = TRUE,
      margins = "ranks"
    )
    
    end_time <- Sys.time()
    elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))
    
    cat("✓ WORKS\n")
    cat("  Statistic:", round(gof$statistic, 6), "\n")
    cat("  P-value:", round(gof$p.value, 4), "\n")
    cat("  Time:", round(elapsed, 1), "seconds\n\n")
  }, silent = TRUE)
  
  if (inherits(result, "try-error")) {
    cat("✗ FAILED\n")
    cat("  Error:", attr(result, "condition")$message, "\n\n")
  }
}

cat("====================================================================\n")
cat("If all tests passed, the gofCopula package integration should work!\n")
cat("====================================================================\n\n")

