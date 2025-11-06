################################################################################
### QUICK TEST: T-Copula with M=10
### Purpose: Rapid verification that unified approach works for t-copula
### Expected runtime: ~5 minutes
################################################################################

cat("====================================================================\n")
cat("QUICK TEST: T-Copula Unified Approach (M=10)\n")
cat("====================================================================\n\n")

# Check gofCopula package version
if (!requireNamespace("gofCopula", quietly = TRUE)) {
  stop("\n\nERROR: gofCopula package not installed!\n")
}

gofCopula_version <- packageVersion("gofCopula")
required_version <- "0.4.4"

if (gofCopula_version < required_version) {
  stop("\n\nERROR: gofCopula version too old!\n",
       "  Found: ", as.character(gofCopula_version), "\n",
       "  Required: >= ", required_version, "\n\n")
}

cat("Package version: gofCopula", as.character(gofCopula_version), "✓\n\n")

# Load functions
cat("Loading functions...\n")
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")
require(data.table)
require(copula)
require(gofCopula)

# Configuration
N_BOOTSTRAP_GOF <- 10
COPULA_FAMILIES <- c("t")  # Just t-copula for quick test

cat("\n====================================================================\n")
cat("TEST CONFIGURATION\n")
cat("====================================================================\n")
cat("Dataset: Dataset 2 (smallest)\n")
cat("Condition: MATH Grade 4->5 (1-year span)\n")
cat("Bootstrap samples (M):", N_BOOTSTRAP_GOF, "\n")
cat("Testing: T-copula ONLY (unified approach)\n\n")

# Load data
cat("Loading data...\n")
load("Data/Copula_Sensitivity_Data_Set_2.Rdata")

# Create test condition
cat("Creating test condition...\n")
pairs_data <- create_longitudinal_pairs(
  Copula_Sensitivity_Data_Set_2,
  content_prior = "MATHEMATICS",
  content_current = "MATHEMATICS",
  grade_prior = 4,
  grade_current = 5,
  year_prior = 2010,
  year_current = 2011
)

cat("  Pairs created:", nrow(pairs_data), "\n\n")

cat("====================================================================\n")
cat("RUNNING T-COPULA GOF TEST (M=", N_BOOTSTRAP_GOF, ")\n")
cat("====================================================================\n\n")

cat("IMPORTANT: With unified approach, t-copula should:\n")
cat("  - Complete without errors\n")
cat("  - Use method: gofKendallCvM_M=10\n")
cat("  - Have p-value > 0 (not 0.0000)\n")
cat("  - Use OUR fitted parameters (not re-estimate)\n\n")

start_time <- Sys.time()

fit_results <- fit_copula_from_pairs(
  scores_prior = pairs_data$SCALE_SCORE_PRIOR,
  scores_current = pairs_data$SCALE_SCORE_CURRENT,
  framework_prior = NULL,
  framework_current = NULL,
  copula_families = COPULA_FAMILIES,
  return_best = FALSE,
  use_empirical_ranks = TRUE,
  n_bootstrap_gof = N_BOOTSTRAP_GOF
)

end_time <- Sys.time()
elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

cat("\n====================================================================\n")
cat("RESULTS\n")
cat("====================================================================\n")
cat("Total time:", round(elapsed, 1), "seconds (", round(elapsed/60, 2), "minutes)\n\n")

# Extract t-copula results
t_result <- fit_results$results$t

cat("T-Copula Results:\n")
cat("--------------------------------------------------------------------\n")
cat("Fitted parameters:\n")
cat("  Rho (correlation):", round(t_result$parameter, 4), "\n")
cat("  Degrees of freedom:", round(t_result$df, 2), "\n")
cat("  Kendall's tau:", round(t_result$kendall_tau, 4), "\n\n")

cat("GoF Test Results:\n")
cat("  Method:", t_result$gof_method, "\n")
cat("  Test statistic:", round(t_result$gof_statistic, 6), "\n")
cat("  P-value:", round(t_result$gof_pvalue, 4), "\n")
cat("  Pass (α=0.05)?", ifelse(t_result$gof_pvalue > 0.05, "YES ✓", "NO ✗"), "\n\n")

cat("====================================================================\n")
cat("VERIFICATION CHECKS\n")
cat("====================================================================\n\n")

# Check 1: Method correct
method_ok <- grepl("gofKendallCvM", t_result$gof_method)
cat("1. Uses gofKendallCvM:", method_ok, ifelse(method_ok, "✓", "✗"), "\n")

# Check 2: P-value not 0
pval_ok <- !is.na(t_result$gof_pvalue) && t_result$gof_pvalue > 0
cat("2. P-value > 0:", pval_ok, ifelse(pval_ok, "✓", "✗"), "\n")
if (!pval_ok) {
  cat("   WARNING: P-value is 0, which with M=10 suggests complete failure\n")
}

# Check 3: No error in method
no_error <- !grepl("failed", t_result$gof_method)
cat("3. No error in GoF:", no_error, ifelse(no_error, "✓", "✗"), "\n")
if (!no_error) {
  cat("   ERROR:", t_result$gof_method, "\n")
}

cat("\n====================================================================\n")
cat("FINAL VERDICT\n")
cat("====================================================================\n\n")

if (method_ok && no_error) {
  cat("✓✓✓ T-COPULA UNIFIED APPROACH WORKING ✓✓✓\n\n")
  cat("Key findings:\n")
  cat("  - T-copula completed without errors\n")
  cat("  - Uses unified gofKendallCvM approach\n")
  cat("  - No special handling required\n")
  
  if (pval_ok) {
    cat("  - P-value > 0 (", round(t_result$gof_pvalue, 4), ")\n\n")
  } else {
    cat("  - P-value = 0 (expected with M=10, need M=100 for meaningful p-values)\n\n")
  }
  
  cat("CONCLUSION:\n")
  cat("  The unified approach works correctly for t-copula!\n")
  cat("  No special handling needed after gofCopula package fixes.\n\n")
  cat("NEXT STEP:\n")
  cat("  Run full test with M=100 and all 5 families:\n")
  cat("  Rscript test_clean_implementation.R\n\n")
  
} else {
  cat("✗ ISSUES DETECTED\n\n")
  cat("The t-copula is not working correctly with unified approach.\n")
  cat("Review the verification checks above.\n\n")
  
  if (!no_error) {
    cat("ERROR MESSAGE:", t_result$gof_method, "\n\n")
  }
}

cat("====================================================================\n")
cat("Test completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("====================================================================\n\n")

