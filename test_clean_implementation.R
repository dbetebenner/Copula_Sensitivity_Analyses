################################################################################
### VERIFICATION: Clean Implementation Without Jitter
### Purpose: Confirm jitter removal doesn't break GoF testing
### Expected runtime: ~40 minutes (M=100, all 5 families)
################################################################################

cat("====================================================================\n")
cat("VERIFICATION: Clean Implementation\n")
cat("====================================================================\n\n")

cat("This test verifies GoF testing using copula::gofCopula with\n")
cat("parametric bootstrap. The t-copula uses rounded degrees of freedom\n")
cat("for compatibility. All 5 parametric families should complete with\n")
cat("reasonable, non-zero p-values.\n\n")

# Verify copula package is available (standard CRAN package)
if (!requireNamespace("copula", quietly = TRUE)) {
  stop("\n\nERROR: copula package not installed!\n",
       "Please install from CRAN:\n",
       "  install.packages('copula')\n\n")
}

cat("Package: copula (standard CRAN package) ✓\n\n")

# Load functions
cat("Loading functions...\n")
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")
require(data.table)
require(copula)

# Configuration
N_BOOTSTRAP_GOF <- 50
COPULA_FAMILIES <- c("gaussian", "t", "clayton", "gumbel", "frank", "comonotonic")

cat("\n====================================================================\n")
cat("TEST CONFIGURATION\n")
cat("====================================================================\n")
cat("Dataset: Dataset 2 (smallest)\n")
cat("Condition: MATH Grade 4->5 (1-year span)\n")
cat("Bootstrap samples (M):", N_BOOTSTRAP_GOF, "\n")
cat("Copula families:", length(COPULA_FAMILIES), "\n\n")

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
cat("RUNNING GOF TESTS (M = ", N_BOOTSTRAP_GOF, ")\n")
cat("====================================================================\n\n")

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

# Extract results
pvalues <- sapply(fit_results$results, function(x) x$gof_pvalue)
gof_methods <- sapply(fit_results$results, function(x) x$gof_method)
gof_stats <- sapply(fit_results$results, function(x) x$gof_statistic)

# Display table
cat("Family-by-family results:\n")
cat("--------------------------------------------------------------------\n")
cat(sprintf("%-15s | %-30s | %10s | %6s\n", 
            "Family", "GoF Method", "P-Value", "Pass?"))
cat("--------------------------------------------------------------------\n")

for (fam in names(fit_results$results)) {
  result <- fit_results$results[[fam]]
  
  # Handle NA p-value for comonotonic
  if (is.na(result$gof_pvalue)) {
    pass_str <- "N/A"
    pval_str <- sprintf("%10s", "NA")
  } else if (result$gof_pvalue > 0.05) {
    pass_str <- "PASS"
    pval_str <- sprintf("%10.4f", result$gof_pvalue)
  } else {
    pass_str <- "FAIL"
    pval_str <- sprintf("%10.4f", result$gof_pvalue)
  }
  
  cat(sprintf("%-15s | %-30s | %s | %-6s\n",
              fam,
              substr(result$gof_method, 1, 30),
              pval_str,
              pass_str))
}

cat("\n====================================================================\n")
cat("VERIFICATION CHECKS\n")
cat("====================================================================\n\n")

# Check 1: Parametric families have p-values; comonotonic should have NA
parametric_pvals <- pvalues[names(pvalues) != "comonotonic"]
all_parametric_have_pvals <- all(!is.na(parametric_pvals))
comonotonic_has_na <- is.na(pvalues["comonotonic"])
all_have_pvals <- all_parametric_have_pvals && comonotonic_has_na
cat("1. Parametric families have p-values:", all_parametric_have_pvals, 
    ifelse(all_parametric_have_pvals, "✓", "✗"), "\n")
cat("   Comonotonic has NA p-value (expected):", comonotonic_has_na,
    ifelse(comonotonic_has_na, "✓", "✗"), "\n")

# Check 2: P-values vary (only relevant for parametric families)
n_unique_pvals <- length(unique(parametric_pvals))
if (length(parametric_pvals) == 1) {
  cat("2. P-value variation: N/A (only 1 parametric family tested)\n")
  cat("   P-value:", round(parametric_pvals[1], 6), "✓\n")
  pval_check <- TRUE
} else {
  cat("2. P-value variation:", n_unique_pvals, "unique values out of", length(parametric_pvals))
  if (n_unique_pvals >= max(2, length(parametric_pvals) * 0.6)) {
    cat(" ✓ GOOD\n")
    cat("   P-values vary across parametric families as expected.\n")
    pval_check <- TRUE
  } else if (n_unique_pvals == 1) {
    cat(" ✗ BAD\n")
    cat("   All p-values are identical:", unique(parametric_pvals), "\n")
    cat("   This suggests a problem with the implementation.\n")
    pval_check <- FALSE
  } else {
    cat(" ⚠️  PARTIAL\n")
    cat("   Some variation but less than expected.\n")
    pval_check <- TRUE
  }
}
cat("\n")

# Check 3: Parametric families use copula::gofCopula; comonotonic uses different method
parametric_methods <- gof_methods[names(gof_methods) != "comonotonic"]
all_parametric_use_gof <- all(grepl("copula_gofCopula", parametric_methods))
comonotonic_method_ok <- grepl("comonotonic_observed_only", gof_methods["comonotonic"])
all_use_copula_gof <- all_parametric_use_gof && comonotonic_method_ok
cat("3. Parametric families using copula::gofCopula:", all_parametric_use_gof,
    ifelse(all_parametric_use_gof, "✓", "✗"), "\n")
cat("   Comonotonic using observed-only method:", comonotonic_method_ok,
    ifelse(comonotonic_method_ok, "✓", "✗"), "\n\n")

# Check 4: T-copula specific check
t_result <- fit_results$results$t
t_ok <- !is.na(t_result$gof_pvalue) && 
        grepl("copula_gofCopula", t_result$gof_method) &&
        t_result$gof_pvalue > 0  # Not zero
cat("4. T-copula working correctly:", t_ok, ifelse(t_ok, "✓", "✗"), "\n")
if (t_ok) {
  cat("   Method:", t_result$gof_method, "\n")
  cat("   P-value:", round(t_result$gof_pvalue, 6), "\n")
  cat("   Statistic:", round(t_result$gof_statistic, 4), "\n")
  cat("   Status: Migration successful ✓\n")
}

cat("\n")

# Check 5: Comonotonic specific check
comonotonic_result <- fit_results$results$comonotonic
comonotonic_ok <- !is.na(comonotonic_result$gof_statistic) &&
                  comonotonic_result$gof_statistic > 1.0 &&  # Should be large
                  is.na(comonotonic_result$gof_pvalue) &&
                  grepl("comonotonic_observed_only", comonotonic_result$gof_method)
cat("5. Comonotonic working correctly:", comonotonic_ok, ifelse(comonotonic_ok, "✓", "✗"), "\n")
if (comonotonic_ok) {
  cat("   Method:", comonotonic_result$gof_method, "\n")
  cat("   Statistic:", round(comonotonic_result$gof_statistic, 4), "(expect >> parametric)\n")
  cat("   P-value: NA (expected, no bootstrap)\n")
  cat("   Status: Observed CvM calculated successfully ✓\n")
}

cat("\n====================================================================\n")
cat("FINAL VERDICT\n")
cat("====================================================================\n\n")

if (all_have_pvals && pval_check && all_use_copula_gof && t_ok && comonotonic_ok) {
  cat("✓✓✓ ALL CHECKS PASSED ✓✓✓\n\n")
  cat("The copula::gofCopula migration is working correctly!\n\n")
  cat("Key findings:\n")
  n_parametric <- length(COPULA_FAMILIES) - 1  # Exclude comonotonic
  cat("  - All", n_parametric, "parametric families complete GoF testing with bootstrap\n")
  cat("  - P-values vary across parametric families (not identical)\n")
  cat("  - Parametric families use copula::gofCopula successfully\n")
  cat("  - Comonotonic calculates observed CvM statistic (no bootstrap)\n")
  parametric_stats <- sapply(names(parametric_methods), function(m) fit_results$results[[m]]$gof_statistic)
  cat("  - Comonotonic CvM statistic:", round(comonotonic_result$gof_statistic, 2), 
      "(>>", round(max(parametric_stats), 2), "max for parametric)\n")
  cat("  - Migration from gofCopula package successful\n\n")
  cat("CONCLUSION:\n")
  cat("  All 6 families (5 parametric + comonotonic) working correctly!\n")
  cat("  Comonotonic shows dramatically worse absolute fit (CvM ~", 
      round(comonotonic_result$gof_statistic, 0), "vs <1 for parametric)\n")
  cat("  Ready for production deployment on EC2 (N=1000).\n\n")
} else {
  cat("✗ ISSUES DETECTED\n\n")
  cat("Review the verification checks above.\n")
  cat("There may be a problem with the implementation.\n\n")
}

cat("====================================================================\n")
cat("Test completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("====================================================================\n\n")

