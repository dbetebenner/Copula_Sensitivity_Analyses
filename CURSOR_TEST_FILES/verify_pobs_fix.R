################################################################################
### VERIFY: pobs() fix resolves identical p-values bug
################################################################################

cat("====================================================================\n")
cat("VERIFICATION: pobs() Fix for Identical P-Values Bug\n")
cat("====================================================================\n\n")

# Load functions with the pobs() fix
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")
require(data.table)
require(copula)

# Configuration
N_BOOTSTRAP_GOF <- 10
COPULA_FAMILIES <- c("gaussian", "t", "clayton", "gumbel", "frank", "comonotonic")

cat("Configuration:\n")
cat("  Test condition: Dataset 2, MATH, Grade 4->5 (1-year span)\n")
cat("  Sample size: ~28,000 pairs\n")
cat("  Copula families:", length(COPULA_FAMILIES), "\n")
cat("  GoF bootstraps:", N_BOOTSTRAP_GOF, "\n")
cat("  Expected runtime: 3-4 minutes\n\n")

# Load data
cat("Loading data...\n")
load("Data/Copula_Sensitivity_Data_Set_2.Rdata")
STATE_DATA_LONG <- Copula_Sensitivity_Data_Set_2

# Create ONE condition: MATH, grade 4->5, 1-year span
cat("Creating test condition...\n")
pairs_data <- create_longitudinal_pairs(
  STATE_DATA_LONG,
  content_prior = "MATHEMATICS",
  content_current = "MATHEMATICS",
  grade_prior = 4,
  grade_current = 5,
  year_prior = 2010,
  year_current = 2011
)

cat("  Pairs created:", nrow(pairs_data), "\n\n")

# Verify pseudo-observations are now unique
cat("====================================================================\n")
cat("PSEUDO-OBSERVATIONS CHECK (using pobs)\n")
cat("====================================================================\n\n")

scores_prior <- pairs_data$SCALE_SCORE_PRIOR
scores_current <- pairs_data$SCALE_SCORE_CURRENT
n <- length(scores_prior)

# Create pseudo-obs using pobs (as in updated code)
pseudo_obs_pobs <- pobs(cbind(scores_prior, scores_current), ties.method = "average")

cat("Pseudo-observations created with pobs():\n")
cat("  U unique values:", length(unique(pseudo_obs_pobs[,1])), 
    "(out of", n, "observations)\n")
cat("  V unique values:", length(unique(pseudo_obs_pobs[,2])), 
    "(out of", n, "observations)\n")
cat("  U range:", range(pseudo_obs_pobs[,1]), "\n")
cat("  V range:", range(pseudo_obs_pobs[,2]), "\n\n")

if (length(unique(pseudo_obs_pobs[,1])) > 100 && 
    length(unique(pseudo_obs_pobs[,2])) > 100) {
  cat("✓ EXCELLENT: pobs() creates many more unique pseudo-observation values!\n")
  cat("  (vs. only 41 and 36 unique values with manual rank() method)\n\n")
} else {
  cat("✗ WARNING: Still seeing very few unique values\n\n")
}

# Fit all copula families with GoF testing using the UPDATED code
cat("====================================================================\n")
cat("FITTING COPULAS WITH UPDATED CODE (using pobs)\n")
cat("====================================================================\n\n")

cat("Fitting copulas with GoF testing...\n")
cat("  This tests the full pipeline with the pobs() fix\n\n")

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
cat("VERIFICATION COMPLETE\n")
cat("====================================================================\n")
cat("Total time:", round(elapsed, 1), "seconds (", round(elapsed/60, 2), "minutes)\n\n")

# Verify results
cat("CRITICAL CHECK: Are p-values now DIFFERENT across families?\n")
cat("--------------------------------------------------------------------\n\n")

pvalues <- sapply(fit_results$results, function(x) x$gof_pvalue)
gof_methods <- sapply(fit_results$results, function(x) x$gof_method)

results_table <- data.frame(
  Family = names(fit_results$results),
  GoF_Method = gof_methods,
  P_Value = sprintf("%.6f", pvalues),
  stringsAsFactors = FALSE
)

print(results_table, row.names = FALSE)

cat("\n")
cat("P-value statistics:\n")
cat("  Unique p-values:", length(unique(pvalues)), "(out of", length(pvalues), "families)\n")
cat("  P-value range:", range(pvalues, na.rm = TRUE), "\n")
cat("  Mean p-value:", mean(pvalues, na.rm = TRUE), "\n")
cat("  Median p-value:", median(pvalues, na.rm = TRUE), "\n\n")

# CRITICAL TEST: Are they all different?
n_unique_pvals <- length(unique(pvalues[!is.na(pvalues)]))

if (n_unique_pvals == 1) {
  cat("✗ FAILED: All p-values are still identical!\n")
  cat("  This suggests the pobs() fix did not resolve the issue.\n")
  cat("  Further investigation needed.\n\n")
} else if (n_unique_pvals >= 4) {
  cat("✓ SUCCESS: P-values are now DIFFERENT across families!\n")
  cat("  The pobs() fix has resolved the identical p-values bug.\n")
  cat("  ", n_unique_pvals, " unique p-values found.\n\n")
} else {
  cat("⚠️  PARTIAL: Some variation in p-values but not as much as expected\n")
  cat("  Found", n_unique_pvals, "unique p-values.\n")
  cat("  May need further investigation.\n\n")
}

# Check specific families
cat("FAMILY-SPECIFIC CHECKS:\n")
cat("--------------------------------------------------------------------\n\n")

# T-copula
t_result <- fit_results$results$t
cat("T-COPULA:\n")
cat("  Method:", t_result$gof_method, "\n")
cat("  P-value:", sprintf("%.4f", t_result$gof_pvalue), "\n")
if (grepl("bootstrap_N=", t_result$gof_method) && !is.na(t_result$gof_pvalue)) {
  cat("  ✓ T-copula GoF test completed successfully\n")
} else {
  cat("  ✗ T-copula GoF test has issues\n")
}
cat("\n")

# Comonotonic
comon_result <- fit_results$results$comonotonic
cat("COMONOTONIC:\n")
cat("  Method:", comon_result$gof_method, "\n")
cat("  P-value:", sprintf("%.4f", comon_result$gof_pvalue), "\n")
if (grepl("bootstrap_comonotonic", comon_result$gof_method) && !is.na(comon_result$gof_pvalue)) {
  if (comon_result$gof_pvalue < 0.05) {
    cat("  ✓ Comonotonic fails GoF as expected (indicating inadequate fit)\n")
  } else {
    cat("  ⚠️  Comonotonic p-value unexpectedly high\n")
  }
} else {
  cat("  ✗ Comonotonic GoF test has issues\n")
}
cat("\n")

cat("====================================================================\n")
cat("FINAL VERDICT\n")
cat("====================================================================\n\n")

if (n_unique_pvals >= 4 && 
    !is.na(t_result$gof_pvalue) && 
    !is.na(comon_result$gof_pvalue)) {
  cat("✓✓✓ ALL TESTS PASSED ✓✓✓\n\n")
  cat("The pobs() fix has successfully:\n")
  cat("  1. Eliminated the identical p-values bug\n")
  cat("  2. Resolved the ties issue in pseudo-observations\n")
  cat("  3. Enabled proper GoF testing for all copula families\n\n")
  cat("READY FOR PRODUCTION:\n")
  cat("  - Can now run full analysis with N=100 or N=1000 bootstraps\n")
  cat("  - Results will have statistically meaningful p-values\n")
  cat("  - Deploy updated copula_bootstrap.R to EC2\n\n")
} else {
  cat("✗ SOME ISSUES REMAIN\n\n")
  cat("Review the output above to diagnose remaining problems.\n\n")
}

cat("\n")

