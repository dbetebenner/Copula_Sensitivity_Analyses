################################################################################
### MANUAL TIMING TEST: N=100 with Single Cohort-Pair
### Purpose: Test realistic production speed (expected: 30-40 minutes)
################################################################################

# Verify copula package is available (standard CRAN package)
if (!requireNamespace("copula", quietly = TRUE)) {
  stop("\n\nERROR: copula package not installed!\n",
       "Please install from CRAN:\n",
       "  install.packages('copula')\n\n")
}

cat("====================================================================\n")
cat("MANUAL TIMING TEST: M=100 BOOTSTRAPS\n")
cat("====================================================================\n\n")

cat("Package Version:\n")
cat("  gofCopula:", as.character(gofCopula_version), "✓\n\n")

# Load functions
cat("Loading functions...\n")
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")
require(data.table)
require(copula)
require(gofCopula)

# Configuration
M_BOOTSTRAP <- 100  # Realistic production value
COPULA_FAMILIES <- c("gaussian", "t", "clayton", "gumbel", "frank")

cat("\n====================================================================\n")
cat("CONFIGURATION\n")
cat("====================================================================\n")
cat("Dataset: dataset_1\n")
cat("Test Condition: MATH Grade 4->5 (1-year span)\n")
cat("Bootstrap samples (M):", M_BOOTSTRAP, "\n")
cat("Copula families:", length(COPULA_FAMILIES), "\n")
cat("Expected runtime: 30-40 minutes\n\n")

# Load data
cat("Loading data...\n")
load("Data/Copula_Sensitivity_Data_Set_1.Rdata")
cat("  Data loaded: n =", nrow(Copula_Sensitivity_Data_Set_1), "students\n\n")

# Create test condition: MATH Grade 4->5, 2010->2011
cat("Creating test condition...\n")
pairs_data <- create_longitudinal_pairs(
  Copula_Sensitivity_Data_Set_1,
  content_prior = "MATHEMATICS",
  content_current = "MATHEMATICS",
  grade_prior = 4,
  grade_current = 5,
  year_prior = 2010,
  year_current = 2011
)

cat("  Pairs created:", nrow(pairs_data), "\n")
cat("  Content: MATH -> MATH\n")
cat("  Grades: 4 -> 5\n")
cat("  Years: 2010 -> 2011\n\n")

cat("====================================================================\n")
cat("FITTING COPULAS WITH GoF TESTING (M=", M_BOOTSTRAP, ")\n")
cat("====================================================================\n\n")

cat("Starting timer...\n\n")
start_time <- Sys.time()

# Fit all copula families with GoF testing
fit_results <- fit_copula_from_pairs(
  scores_prior = pairs_data$SCALE_SCORE_PRIOR,
  scores_current = pairs_data$SCALE_SCORE_CURRENT,
  framework_prior = NULL,
  framework_current = NULL,
  copula_families = COPULA_FAMILIES,
  return_best = FALSE,
  use_empirical_ranks = TRUE,
  n_bootstrap_gof = M_BOOTSTRAP
)

end_time <- Sys.time()
elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

cat("\n====================================================================\n")
cat("RESULTS: M=", M_BOOTSTRAP, "\n")
cat("====================================================================\n")
cat("Total time:", round(elapsed, 1), "seconds (", 
    round(elapsed/60, 2), "minutes)\n\n")

# Display results table
cat("Family-by-family results:\n")
cat("--------------------------------------------------------------------\n")
cat(sprintf("%-15s | %-30s | %-10s | %-6s\n", 
            "Family", "GoF Method", "p-value", "Pass?"))
cat("--------------------------------------------------------------------\n")

for (fam in names(fit_results$results)) {
  result <- fit_results$results[[fam]]
  pass_str <- ifelse(result$gof_pvalue > 0.05, "PASS", "FAIL")
  
  cat(sprintf("%-15s | %-30s | %10.4f | %-6s\n",
              fam,
              substr(result$gof_method, 1, 30),
              result$gof_pvalue,
              pass_str))
}

cat("\n====================================================================\n")
cat("TIMING ANALYSIS\n")
cat("====================================================================\n\n")

time_per_family <- elapsed / length(COPULA_FAMILIES)
cat("Time per family:", round(time_per_family, 1), "seconds (",
    round(time_per_family/60, 2), "minutes)\n\n")

# Estimate for full analysis
cat("PROJECTED TIMES FOR FULL ANALYSIS:\n\n")

# Dataset 1: 28 conditions
cat("Dataset 1 (28 conditions):\n")
cat("  M=100:  ", round(elapsed * 28 / 3600, 1), "hours\n")
cat("  M=1000: ", round(elapsed * 28 * 10 / 3600, 1), "hours\n\n")

# All datasets: 129 conditions
cat("All datasets (129 conditions):\n")
cat("  M=100:  ", round(elapsed * 129 / 3600, 1), "hours\n")
cat("  M=1000: ", round(elapsed * 129 * 10 / 3600, 1), "hours (", 
    round(elapsed * 129 * 10 / (3600 * 24), 1), "days)\n\n")

cat("====================================================================\n")
cat("RECOMMENDATIONS\n")
cat("====================================================================\n\n")

if (elapsed < 2400) {  # Less than 40 minutes
  cat("✓ Performance is good!\n\n")
  cat("Recommendations:\n")
  cat("  1. M=100 is feasible for full analysis (~", 
      round(elapsed * 129 / 3600, 1), "hours)\n")
  cat("  2. M=1000 should run on EC2 overnight (~", 
      round(elapsed * 129 * 10 / 3600, 1), "hours)\n")
  cat("  3. Consider starting with M=100 to verify all conditions\n")
  cat("  4. Then scale up to M=1000 for final publication results\n\n")
} else {
  cat("⚠️  Runtime is longer than expected\n\n")
  cat("Suggestions:\n")
  cat("  1. Check gofCopula package version (should be >= 0.4.4)\n")
  cat("  2. Verify fixed t-copula code is in place\n")
  cat("  3. Consider using EC2 with more cores for parallelization\n\n")
}

cat("====================================================================\n")
cat("VERIFICATION CHECKLIST\n")
cat("====================================================================\n\n")

all_have_pvals <- all(!is.na(sapply(fit_results$results, function(x) x$gof_pvalue)))
all_use_gofCopula <- all(grepl("gofKendallCvM", 
                               sapply(fit_results$results, function(x) x$gof_method)))

cat("1. All families have p-values:", all_have_pvals, 
    ifelse(all_have_pvals, "✓", "✗"), "\n")
cat("2. All using gofKendallCvM:", all_use_gofCopula,
    ifelse(all_use_gofCopula, "✓", "✗"), "\n")

# Check specific families
t_result <- fit_results$results$t
t_ok <- !is.na(t_result$gof_pvalue) && grepl("gofKendallCvM", t_result$gof_method)
cat("3. T-copula working:", t_ok, ifelse(t_ok, "✓", "✗"), "\n")

if (all_have_pvals && all_use_gofCopula && t_ok) {
  cat("\n✓✓✓ ALL CHECKS PASSED ✓✓✓\n\n")
  cat("Ready for production runs!\n\n")
} else {
  cat("\n✗ ISSUES DETECTED\n\n")
  cat("Please review results above before proceeding.\n\n")
}

cat("Test completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

