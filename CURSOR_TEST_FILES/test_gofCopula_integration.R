################################################################################
### TEST: gofCopula Package Integration
### Purpose: Verify the new perform_gof_test() works correctly
################################################################################

cat("====================================================================\n")
cat("TESTING: gofCopula Package Integration\n")
cat("====================================================================\n\n")

# Load functions
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")
require(data.table)
require(copula)

# Check if gofCopula package is installed
if (!requireNamespace("gofCopula", quietly = TRUE)) {
  cat("Installing gofCopula package...\n")
  devtools::install_github("SimonTrimborn/gofCopula", quiet = TRUE)
}

cat("Configuration:\n")
cat("  Test: Single condition from dataset 2\n")
cat("  Copula families: All 6\n")
cat("  GoF bootstraps: 10 (for speed)\n")
cat("  Expected runtime: 3-4 minutes\n\n")

# Load data
cat("Loading data...\n")
load("Data/Copula_Sensitivity_Data_Set_2.Rdata")

# Create ONE condition
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

# Test the updated function
cat("====================================================================\n")
cat("TESTING: Updated perform_gof_test() Function\n")
cat("====================================================================\n\n")

N_BOOTSTRAP_GOF <- 10
COPULA_FAMILIES <- c("gaussian", "t", "clayton", "gumbel", "frank", "comonotonic")

cat("Fitting all copula families with GoF testing...\n\n")

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

results_table <- data.frame(
  Family = names(fit_results$results),
  GoF_Method = gof_methods,
  P_Value = sprintf("%.4f", pvalues),
  Uses_gofCopula_pkg = grepl("gofKendallCvM", gof_methods),
  stringsAsFactors = FALSE
)

print(results_table, row.names = FALSE)

cat("\n====================================================================\n")
cat("VERIFICATION\n")
cat("====================================================================\n\n")

# Check which families used gofCopula package
using_package <- results_table$Uses_gofCopula_pkg
n_using_package <- sum(using_package)

cat("Families using gofCopula package:", n_using_package, "/ 6\n")
cat("  Expected: 4 (gaussian, clayton, gumbel, frank)\n")
if (n_using_package == 4) {
  cat("  ✓ CORRECT\n")
} else {
  cat("  ✗ UNEXPECTED COUNT\n")
}

cat("\n")

# Check p-value variation
n_unique_pvals <- length(unique(pvalues[!is.na(pvalues)]))
cat("Unique p-values:", n_unique_pvals, "/ 6\n")
cat("  Expected: ≥ 4 (all should be different)\n")
if (n_unique_pvals >= 4) {
  cat("  ✓ EXCELLENT - p-values vary across families!\n")
} else {
  cat("  ✗ WARNING - Still seeing duplicate p-values\n")
}

cat("\n")

# Check specific families
cat("Family-specific checks:\n\n")

cat("1. Gaussian:\n")
gaussian_result <- fit_results$results$gaussian
cat("   Method:", gaussian_result$gof_method, "\n")
cat("   Using gofCopula pkg?:", grepl("gofKendallCvM", gaussian_result$gof_method), "\n")
cat("   P-value:", sprintf("%.4f", gaussian_result$gof_pvalue), "\n\n")

cat("2. T-copula:\n")
t_result <- fit_results$results$t
cat("   Method:", t_result$gof_method, "\n")
cat("   Using fallback?:", grepl("df=", t_result$gof_method), "\n")
cat("   P-value:", sprintf("%.4f", t_result$gof_pvalue), "\n\n")

cat("3. Comonotonic:\n")
comon_result <- fit_results$results$comonotonic
cat("   Method:", comon_result$gof_method, "\n")
cat("   Using custom bootstrap?:", grepl("comonotonic", comon_result$gof_method), "\n")
cat("   P-value:", sprintf("%.4f", comon_result$gof_pvalue), "\n\n")

cat("====================================================================\n")
cat("FINAL VERDICT\n")
cat("====================================================================\n\n")

if (n_using_package == 4 && n_unique_pvals >= 4) {
  cat("✓✓✓ SUCCESS! ✓✓✓\n\n")
  cat("The gofCopula package integration works correctly:\n")
  cat("  1. Four families use gofKendallCvM from gofCopula package\n")
  cat("  2. P-values vary appropriately across families\n")
  cat("  3. Fallbacks work for t-copula and comonotonic\n\n")
  cat("READY FOR PRODUCTION:\n")
  cat("  - This solves the identical p-values bug!\n")
  cat("  - Can now run full analysis with confidence\n")
  cat("  - Deploy updated copula_bootstrap.R to EC2\n\n")
} else {
  cat("⚠️  ISSUES DETECTED\n\n")
  cat("Review the results above to diagnose problems.\n\n")
}

cat("\n")

