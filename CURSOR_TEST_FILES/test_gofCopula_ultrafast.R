################################################################################
### ULTRA-FAST TEST: gofCopula Package with Single Condition
### Purpose: Verify gofKendallCvM works with M=10 before scaling to M=1000
### Expected runtime: 2-3 minutes
################################################################################

cat("====================================================================\n")
cat("ULTRA-FAST GOF TEST: gofCopula Package (M=10)\n")
cat("====================================================================\n\n")

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
       "Please rebuild the fixed package:\n",
       "  cd ~/GitHub/DBetebenner/gofCopula/main\n",
       "  R CMD INSTALL .\n\n")
}

cat("Package Version Check:\n")
cat("  gofCopula version:", as.character(gofCopula_version), "✓\n")
cat("  Required: >=", required_version, "\n\n")

# Load functions
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")
require(data.table)
require(copula)
library(gofCopula)

cat("Configuration:\n")
cat("  Dataset: Dataset 2 (smallest, 21 conditions)\n")
cat("  Condition: MATH Grade 4->5 (1-year span) - single test\n")
cat("  Sample size: ~28,000 pairs\n")
cat("  Copula families: 5 parametric families\n")
cat("  GoF bootstraps: M=10 (ultra-fast testing)\n")
cat("  Expected runtime: 2-3 minutes\n\n")

# Load data
cat("Loading data...\n")
load("Data/Copula_Sensitivity_Data_Set_2.Rdata")

# Create ONE condition for fast testing
cat("Creating single test condition...\n")
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

# Run with M=10
cat("====================================================================\n")
cat("FITTING COPULAS WITH GoF TESTING (M=10)\n")
cat("====================================================================\n\n")

N_BOOTSTRAP_GOF <- 10
COPULA_FAMILIES <- c("gaussian", "t", "clayton", "gumbel", "frank")

cat("Fitting all families with GoF...\n\n")
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

# Extract and display results
pvalues <- sapply(fit_results$results, function(x) x$gof_pvalue)
gof_methods <- sapply(fit_results$results, function(x) x$gof_method)
gof_stats <- sapply(fit_results$results, function(x) x$gof_statistic)

results_table <- data.frame(
  Family = names(fit_results$results),
  GoF_Method = gof_methods,
  Statistic = sprintf("%.6f", gof_stats),
  P_Value = sprintf("%.4f", pvalues),
  Pass_0.05 = ifelse(pvalues > 0.05, "✓ PASS", "✗ FAIL"),
  stringsAsFactors = FALSE
)

print(results_table, row.names = FALSE)

cat("\n====================================================================\n")
cat("VERIFICATION\n")
cat("====================================================================\n\n")

# Critical checks
n_unique_pvals <- length(unique(pvalues[!is.na(pvalues)]))
all_have_pvals <- all(!is.na(pvalues))
all_use_gofCopula <- all(grepl("gofKendallCvM", gof_methods[!is.na(pvalues)]))

cat("1. P-value variation:\n")
cat("   Unique p-values:", n_unique_pvals, "out of", length(pvalues), "\n")
if (n_unique_pvals >= 4) {
  cat("   ✓ SUCCESS - P-values vary across families!\n")
  cat("   This confirms we've solved the identical p-values bug.\n")
} else if (n_unique_pvals == 1) {
  cat("   ✗ FAILED - All p-values are identical:", unique(pvalues), "\n")
} else {
  cat("   ⚠️  PARTIAL - Some variation but less than expected\n")
}

cat("\n2. Completeness:\n")
cat("   All families have p-values?:", all_have_pvals, "\n")
if (all_have_pvals) {
  cat("   ✓ SUCCESS - No NA values\n")
} else {
  cat("   ✗ FAILED - Some families have NA p-values\n")
}

cat("\n3. Method check:\n")
cat("   All using gofKendallCvM?:", all_use_gofCopula, "\n")
if (all_use_gofCopula) {
  cat("   ✓ SUCCESS - All families using gofCopula package\n")
}

cat("\n====================================================================\n")
cat("PERFORMANCE ESTIMATES\n")
cat("====================================================================\n\n")

time_per_family <- elapsed / length(COPULA_FAMILIES)
cat("Time per family (M=10):", round(time_per_family, 1), "seconds\n\n")

cat("Estimated runtime for full analysis:\n")
cat("  21 conditions (dataset 2) × 5 families:\n")
cat("    M=10:   ", round(elapsed * 21 / 60, 1), "minutes\n")
cat("    M=100:  ", round(elapsed * 21 * 10 / 60, 1), "minutes\n")
cat("    M=1000: ", round(elapsed * 21 * 100 / 60, 1), "minutes (", 
    round(elapsed * 21 * 100 / 3600, 1), "hours)\n\n")

cat("  129 conditions (all datasets) × 5 families:\n")
cat("    M=10:   ", round(elapsed * 129 / 60, 1), "minutes\n")
cat("    M=100:  ", round(elapsed * 129 * 10 / 60, 1), "minutes (", 
    round(elapsed * 129 * 10 / 3600, 1), "hours)\n")
cat("    M=1000: ", round(elapsed * 129 * 100 / 60, 1), "minutes (", 
    round(elapsed * 129 * 100 / 3600, 1), "hours)\n\n")

cat("====================================================================\n")
cat("FINAL VERDICT\n")
cat("====================================================================\n\n")

if (n_unique_pvals >= 4 && all_have_pvals && all_use_gofCopula) {
  cat("✓✓✓ ALL CHECKS PASSED ✓✓✓\n\n")
  cat("The gofCopula package integration is working correctly!\n\n")
  cat("NEXT STEPS:\n")
  cat("1. Scale up to M=1000 for production\n")
  cat("2. Run full analysis on all 129 conditions\n")
  cat("3. Address comonotonic copula separately (if needed for paper)\n")
  cat("4. Expected production runtime: ~", round(elapsed * 129 * 100 / 3600, 1), 
      "hours for M=1000\n\n")
} else {
  cat("✗ ISSUES DETECTED\n\n")
  cat("Review the results above to diagnose problems.\n")
  cat("Do not proceed to M=1000 until these are resolved.\n\n")
}

