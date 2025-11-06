################################################################################
### Test Comonotonic GoF Implementation
################################################################################

source("functions/copula_bootstrap.R")
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
require(copula)
require(data.table)

cat("================================================================================\n")
cat("TESTING COMONOTONIC GOF IMPLEMENTATION\n")
cat("================================================================================\n\n")

# Load data
load("Data/Copula_Sensitivity_Data_Set_2.Rdata")

# Create test condition
pairs_data <- create_longitudinal_pairs(
  Copula_Sensitivity_Data_Set_2,
  content_prior = "MATHEMATICS",
  content_current = "MATHEMATICS",
  grade_prior = 4,
  grade_current = 5,
  year_prior = 2010,
  year_current = 2011
)

cat("Sample size:", nrow(pairs_data), "\n\n")

# Create pseudo-observations
set.seed(314159)
pseudo_obs <- pobs(cbind(pairs_data$SCALE_SCORE_PRIOR, 
                         pairs_data$SCALE_SCORE_CURRENT), 
                   ties.method = "random")
pseudo_obs <- as.matrix(pseudo_obs)

cat("Testing comonotonic GoF calculation...\n")
result <- perform_gof_test(
  fitted_copula = NULL, 
  pseudo_obs = pseudo_obs,
  n_bootstrap = 0,  # Not used for comonotonic
  family = "comonotonic"
)

cat("\n--- RESULTS ---\n")
cat("CvM Statistic:", result$gof_statistic, "\n")
cat("P-value:      ", result$gof_pvalue, "\n")
cat("Method:       ", result$gof_method, "\n\n")

# Verify results
if (!is.na(result$gof_statistic) && result$gof_statistic > 0) {
  cat("✓ SUCCESS: Comonotonic CvM statistic calculated correctly!\n")
  cat("  Statistic =", sprintf("%.4f", result$gof_statistic), 
      "(expect large value, >> 1.0)\n")
} else {
  cat("✗ FAILED: CvM statistic is NA or invalid\n")
}

if (is.na(result$gof_pvalue)) {
  cat("✓ SUCCESS: P-value correctly set to NA (no bootstrap)\n")
} else {
  cat("✗ WARNING: P-value should be NA for comonotonic\n")
}

if (result$gof_method == "comonotonic_observed_only") {
  cat("✓ SUCCESS: Method label correct\n")
} else {
  cat("✗ WARNING: Method label unexpected:", result$gof_method, "\n")
}

cat("\n================================================================================\n")
cat("For comparison, let's also test a parametric family (t-copula)\n")
cat("================================================================================\n\n")

# Fit t-copula for comparison
t_cop <- tCopula(dim = 2, dispstr = "un")
t_fit <- fitCopula(t_cop, pseudo_obs, method = "mpl")

cat("Fitted t-copula:\n")
cat("  rho:", sprintf("%.4f", t_fit@estimate[1]), "\n")
cat("  df: ", sprintf("%.2f", t_fit@estimate[2]), "\n\n")

# GoF test for t-copula (using small N for speed)
cat("Running t-copula GoF test (N=20 for speed)...\n")
t_result <- perform_gof_test(
  fitted_copula = t_fit@copula,
  pseudo_obs = pseudo_obs,
  n_bootstrap = 20,
  family = "t"
)

cat("\n--- T-COPULA RESULTS ---\n")
cat("CvM Statistic:", t_result$gof_statistic, "\n")
cat("P-value:      ", t_result$gof_pvalue, "\n")
cat("Method:       ", t_result$gof_method, "\n\n")

# Compare
cat("================================================================================\n")
cat("COMPARISON\n")
cat("================================================================================\n\n")
cat("Comonotonic CvM:", sprintf("%10.4f", result$gof_statistic), 
    "(observed only, no p-value)\n")
cat("T-copula CvM:   ", sprintf("%10.4f", t_result$gof_statistic), 
    "(p =", sprintf("%.4f", t_result$gof_pvalue), ")\n\n")

if (result$gof_statistic > t_result$gof_statistic) {
  cat("✓ EXPECTED: Comonotonic has worse fit (higher CvM) than t-copula\n")
  cat("  Ratio:", sprintf("%.1f", result$gof_statistic / t_result$gof_statistic), "x worse\n")
} else {
  cat("✗ UNEXPECTED: Comonotonic CvM should be higher than t-copula\n")
}

cat("\n================================================================================\n")
cat("TEST COMPLETE\n")
cat("================================================================================\n")

