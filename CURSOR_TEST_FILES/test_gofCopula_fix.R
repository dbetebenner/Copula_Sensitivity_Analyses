################################################################################
### Test Script: Verify gofCopula Package Fix for T-Copula
### Purpose: Confirm the bug fix in internal_est_margin_param.R works
################################################################################

cat("====================================================================\n")
cat("TESTING FIXED gofCopula PACKAGE\n")
cat("====================================================================\n\n")

cat("FIXES APPLIED:\n")
cat("  1. internal_est_margin_param.R (line 355-356)\n")
cat("  2. internal_param_est.R (line 312-313)\n")
cat("  Bug: 'length = 2' in coercion to 'logical(1)' for t-copulas\n")
cat("  Fix: Wrap each comparison in any() before || operator\n\n")

cat("IMPORTANT: Before running this script, rebuild the package:\n")
cat("  1. In RStudio: Open gofCopula.Rproj\n")
cat("  2. Build > Install and Restart\n")
cat("  OR from terminal:\n")
cat("  cd ~/GitHub/DBetebenner/gofCopula/main\n")
cat("  R CMD INSTALL .\n\n")

# Check gofCopula package version
if (!requireNamespace("gofCopula", quietly = TRUE)) {
  stop("\n\nERROR: gofCopula package not installed!\n",
       "Please install from your local fork:\n",
       "  devtools::install('~/GitHub/DBetebenner/gofCopula/main')\n\n")
}

gofCopula_version <- packageVersion("gofCopula")
required_version <- "0.4.4"

if (gofCopula_version < required_version) {
  stop("\n\nERROR: gofCopula version too old!\n",
       "  Found: ", as.character(gofCopula_version), "\n",
       "  Required: >= ", required_version, "\n",
       "  This version has the t-copula parameter boundary bug.\n\n",
       "Please rebuild the fixed package (see instructions above).\n\n")
}

cat("Package version check:\n")
cat("  gofCopula:", as.character(gofCopula_version), "✓\n\n")

cat("Loading packages...\n")
library(gofCopula)
library(copula)

cat("Loading toy data...\n")
data("IndexReturns2D", package = "gofCopula")
cat("  Data dimensions:", dim(IndexReturns2D), "\n\n")

# Test 1: gofKendallCvM with t-copula (param.est = TRUE)
cat("====================================================================\n")
cat("TEST 1: gofKendallCvM with t-copula (param.est = TRUE)\n")
cat("====================================================================\n\n")

cat("This should now WORK (previously failed with 'length = 2' error)...\n\n")

test1_result <- tryCatch({
  result <- gofKendallCvM(
    copula = "t",
    x = IndexReturns2D,
    M = 10,  # Small M for quick test
    param.est = TRUE,
    margins = "ranks",
    seed.active = 1
  )
  
  cat("✓ SUCCESS! gofKendallCvM completed without error\n\n")
  
  # Extract results
  pvalue <- result$t$res.tests[1, "p.value"]
  statistic <- result$t$res.tests[1, "test statistic"]
  
  cat("Results:\n")
  cat("  Test statistic:", round(statistic, 6), "\n")
  cat("  P-value:", round(pvalue, 4), "\n")
  cat("  Pass (p > 0.05)?", ifelse(pvalue > 0.05, "YES", "NO"), "\n\n")
  
  list(success = TRUE, pvalue = pvalue, statistic = statistic, error = NULL)
  
}, error = function(e) {
  cat("✗ FAILED with error:", e$message, "\n\n")
  list(success = FALSE, pvalue = NA, statistic = NA, error = e$message)
})

# Test 2: gof() wrapper with t-copula
cat("====================================================================\n")
cat("TEST 2: gof() wrapper with t-copula\n")
cat("====================================================================\n\n")

cat("The high-level gof() function should also work now...\n\n")

test2_result <- tryCatch({
  result <- gof(
    x = IndexReturns2D,
    M = 10,
    copula = "t",
    seed.active = 1
  )
  
  cat("✓ SUCCESS! gof() completed without error\n\n")
  
  # The gof() function returns results in a different structure
  cat("Results summary available\n\n")
  
  list(success = TRUE, error = NULL)
  
}, error = function(e) {
  cat("✗ FAILED with error:", e$message, "\n\n")
  list(success = FALSE, error = e$message)
})

# Test 3: Compare all parametric families
cat("====================================================================\n")
cat("TEST 3: All 5 Parametric Families\n")
cat("====================================================================\n\n")

families <- c("normal", "t", "clayton", "gumbel", "frank")
results_all <- list()

for (fam in families) {
  cat("Testing", fam, "copula...\n")
  
  result <- tryCatch({
    gof_result <- gofKendallCvM(
      copula = fam,
      x = IndexReturns2D,
      M = 10,
      param.est = TRUE,
      margins = "ranks",
      seed.active = 1
    )
    
    pval <- gof_result[[fam]]$res.tests[1, "p.value"]
    stat <- gof_result[[fam]]$res.tests[1, "test statistic"]
    
    cat("  ✓ Completed: p =", round(pval, 4), "\n")
    list(success = TRUE, pvalue = pval, statistic = stat)
    
  }, error = function(e) {
    cat("  ✗ Failed:", e$message, "\n")
    list(success = FALSE, pvalue = NA, statistic = NA, error = e$message)
  })
  
  results_all[[fam]] <- result
}

cat("\n====================================================================\n")
cat("SUMMARY\n")
cat("====================================================================\n\n")

# Summary table
cat("Family-by-family results:\n\n")
for (fam in names(results_all)) {
  r <- results_all[[fam]]
  status <- ifelse(r$success, "✓ PASS", "✗ FAIL")
  pval_str <- ifelse(is.na(r$pvalue), "NA", sprintf("%.4f", r$pvalue))
  cat(sprintf("  %-10s %s  (p = %s)\n", fam, status, pval_str))
}

cat("\n")

# Overall assessment
all_success <- all(sapply(results_all, function(x) x$success))

if (all_success && test1_result$success && test2_result$success) {
  cat("═══════════════════════════════════════════════════════════════════\n")
  cat("✓✓✓ ALL TESTS PASSED ✓✓✓\n")
  cat("═══════════════════════════════════════════════════════════════════\n\n")
  cat("The gofCopula package fix is working correctly!\n\n")
  cat("NEXT STEPS:\n")
  cat("1. Update perform_gof_test() in copula_bootstrap.R to use gofCopula\n")
  cat("2. Run test_gofCopula_ultrafast.R to verify integration\n")
  cat("3. Scale to M=1000 for production analysis\n\n")
} else {
  cat("═══════════════════════════════════════════════════════════════════\n")
  cat("✗ SOME TESTS FAILED\n")
  cat("═══════════════════════════════════════════════════════════════════\n\n")
  cat("Please review the errors above.\n")
  cat("The package may need to be rebuilt.\n\n")
}

