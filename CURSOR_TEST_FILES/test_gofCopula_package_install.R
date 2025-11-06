################################################################################
### TEST: Install and verify gofCopula package functionality
################################################################################

cat("====================================================================\n")
cat("STEP 1: Installing gofCopula package from GitHub\n")
cat("====================================================================\n\n")

# Check if devtools is available
if (!require("devtools", quietly = TRUE)) {
  cat("Installing devtools...\n")
  install.packages("devtools")
}

# Install gofCopula package
cat("Installing gofCopula package from GitHub...\n")
tryCatch({
  devtools::install_github("SimonTrimborn/gofCopula", quiet = FALSE)
  cat("\n✓ gofCopula package installed successfully!\n\n")
}, error = function(e) {
  cat("\n✗ Installation failed:", e$message, "\n")
  stop("Cannot proceed without gofCopula package")
})

cat("====================================================================\n")
cat("STEP 2: Verify package loads correctly\n")
cat("====================================================================\n\n")

library(gofCopula)
library(copula)

cat("Loaded packages:\n")
cat("  - gofCopula (GitHub package)\n")
cat("  - copula (CRAN package)\n\n")

cat("====================================================================\n")
cat("STEP 3: Test with simple data\n")
cat("====================================================================\n\n")

# Create simple test data
set.seed(123)
n <- 1000
cop_true <- normalCopula(0.7, dim = 2)
test_data <- rCopula(n, cop_true)

cat("Test data created: n =", n, "\n")
cat("  True copula: Gaussian with rho = 0.7\n\n")

cat("====================================================================\n")
cat("STEP 4: Test gofKendallCvM() function for each family\n")
cat("====================================================================\n\n")

# Map to gofCopula naming conventions
families_map <- list(
  gaussian = "normal",
  t = "t",
  clayton = "clayton",
  gumbel = "gumbel",
  frank = "frank"
)

results <- data.frame(
  Our_Name = character(),
  Package_Name = character(),
  Status = character(),
  P_Value = numeric(),
  Error = character(),
  stringsAsFactors = FALSE
)

for (our_name in names(families_map)) {
  pkg_name <- families_map[[our_name]]
  
  cat("Testing:", our_name, "(gofCopula name:", pkg_name, ")\n")
  
  result <- tryCatch({
    # Use gofCopula package's gofKendallCvM function
    gof_result <- gofCopula::gofKendallCvM(
      copula = pkg_name,
      x = test_data,
      M = 10,  # Small M for speed
      param.est = TRUE,
      margins = "ranks"
    )
    
    cat("  ✓ SUCCESS\n")
    cat("    Statistic:", gof_result$statistic, "\n")
    cat("    P-value:", gof_result$p.value, "\n\n")
    
    data.frame(
      Our_Name = our_name,
      Package_Name = pkg_name,
      Status = "SUCCESS",
      P_Value = gof_result$p.value,
      Error = NA_character_
    )
    
  }, error = function(e) {
    cat("  ✗ FAILED:", e$message, "\n\n")
    
    data.frame(
      Our_Name = our_name,
      Package_Name = pkg_name,
      Status = "FAILED",
      P_Value = NA_real_,
      Error = e$message
    )
  })
  
  results <- rbind(results, result)
}

cat("====================================================================\n")
cat("STEP 5: Test comonotonic (special case)\n")
cat("====================================================================\n\n")

cat("Testing: comonotonic\n")

comon_result <- tryCatch({
  # Try with gofCopula package
  gof_result <- gofCopula::gofKendallCvM(
    copula = "comonotonic",
    x = test_data,
    M = 10,
    param.est = TRUE,
    margins = "ranks"
  )
  
  cat("  ✓ SUCCESS with gofCopula package!\n")
  cat("    P-value:", gof_result$p.value, "\n\n")
  
  data.frame(
    Our_Name = "comonotonic",
    Package_Name = "comonotonic",
    Status = "SUCCESS",
    P_Value = gof_result$p.value,
    Error = NA_character_
  )
  
}, error = function(e) {
  cat("  ✗ FAILED:", e$message, "\n")
  cat("  → Will need custom implementation\n\n")
  
  data.frame(
    Our_Name = "comonotonic",
    Package_Name = "comonotonic",
    Status = "NEEDS_CUSTOM",
    P_Value = NA_real_,
    Error = e$message
  )
})

results <- rbind(results, comon_result)

cat("====================================================================\n")
cat("SUMMARY\n")
cat("====================================================================\n\n")

print(results, row.names = FALSE)

cat("\n")
cat("Success rate:", sum(results$Status == "SUCCESS"), "/", nrow(results), "\n")

if (sum(results$Status == "SUCCESS") >= 5) {
  cat("\n✓✓✓ EXCELLENT: gofCopula package works for all standard families!\n")
  cat("Ready to integrate into copula_bootstrap.R\n\n")
} else {
  cat("\n⚠️  PARTIAL: Some families need custom implementation\n\n")
}

cat("====================================================================\n")
cat("STEP 6: Compare gofCopula vs copula package\n")
cat("====================================================================\n\n")

cat("Testing same data with both packages to verify different implementations:\n\n")

# Test Gaussian with both packages
cat("Gaussian copula:\n")

# Fit copula first
fit_gauss <- fitCopula(normalCopula(dim = 2), test_data, method = "ml")

# Method 1: gofCopula package
gof1 <- gofCopula::gofKendallCvM(
  copula = "normal",
  x = test_data,
  M = 10,
  param.est = TRUE,
  margins = "ranks"
)
cat("  gofCopula package p-value:", gof1$p.value, "\n")

# Method 2: copula package (for comparison)
gof2 <- copula::gofCopula(
  fit_gauss@copula,
  x = test_data,
  method = "Sn",
  simulation = "pb",
  N = 10,
  verbose = FALSE
)
cat("  copula package p-value:", gof2$p.value, "\n")

cat("\nNote: P-values will differ due to different tests and random bootstrap\n")
cat("      gofCopula uses Kendall's CvM test\n")
cat("      copula uses standard CvM test\n")

cat("\n====================================================================\n")
cat("TEST COMPLETE - Ready to implement in production code\n")
cat("====================================================================\n\n")

