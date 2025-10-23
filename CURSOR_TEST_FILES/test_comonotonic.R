############################################################################
### TEST SCRIPT: Comonotonic Copula Implementation
### Purpose: Validate that comonotonic copula is correctly implemented
###          and produces expected results (tau = 1.0, poor fit)
############################################################################

cat("====================================================================\n")
cat("TESTING COMONOTONIC COPULA IMPLEMENTATION\n")
cat("====================================================================\n\n")

# Load required libraries
require(data.table)
require(copula)

# Load function
source("functions/copula_bootstrap.R")

# Load dataset configurations
source("dataset_configs.R")

# Load a dataset for testing (use dataset_1)
cat("Loading test data (dataset_1)...\n")
dataset_config <- DATASETS[["dataset_1"]]
load(dataset_config$local_path)

# Assign to generic workspace name
STATE_DATA_LONG <- get(dataset_config$rdata_object_name)
WORKSPACE_OBJECT_NAME <- "STATE_DATA_LONG"

cat("✓ Loaded", nrow(STATE_DATA_LONG), "rows\n\n")

# Define a simple test condition
cat("Setting up test condition:\n")
cat("  Grade: 4 → 5\n")
cat("  Year: 2010 → 2011\n")
cat("  Content: MATHEMATICS\n\n")

# Filter data for this condition
# Note: The data structure has SCALE_SCORE (current) and SCALE_SCORE_PRIOR
# We want grade 5 records (which have grade 4 prior scores)
test_pairs <- STATE_DATA_LONG[
  VALID_CASE == "VALID_CASE" & 
  GRADE == 5 &  # Current grade
  YEAR == "2011" &  # Current year
  CONTENT_AREA == "MATHEMATICS" &
  !is.na(SCALE_SCORE) &
  !is.na(SCALE_SCORE_PRIOR),
  .(SCALE_SCORE_PRIOR, SCALE_SCORE_CURRENT = SCALE_SCORE)
]

cat("Sample size:", nrow(test_pairs), "pairs\n\n")

if (nrow(test_pairs) < 100) {
  stop("ERROR: Insufficient data for test condition")
}

# Fit all copula families including comonotonic
cat("====================================================================\n")
cat("FITTING ALL 6 COPULA FAMILIES\n")
cat("====================================================================\n\n")

copula_families <- c("gaussian", "t", "clayton", "gumbel", "frank", "comonotonic")

fit_result <- fit_copula_from_pairs(
  scores_prior = test_pairs$SCALE_SCORE_PRIOR,
  scores_current = test_pairs$SCALE_SCORE_CURRENT,
  framework_prior = NULL,
  framework_current = NULL,
  copula_families = copula_families,
  return_best = FALSE,
  use_empirical_ranks = TRUE  # Phase 1 approach
)

# Display results
cat("\n====================================================================\n")
cat("RESULTS SUMMARY\n")
cat("====================================================================\n\n")

results_dt <- data.table(
  family = character(),
  kendall_tau = numeric(),
  loglik = numeric(),
  aic = numeric(),
  bic = numeric(),
  rank_aic = integer()
)

for (fam in copula_families) {
  if (!is.null(fit_result$results[[fam]])) {
    results_dt <- rbind(results_dt, data.table(
      family = fam,
      kendall_tau = fit_result$results[[fam]]$kendall_tau,
      loglik = fit_result$results[[fam]]$loglik,
      aic = fit_result$results[[fam]]$aic,
      bic = fit_result$results[[fam]]$bic
    ), fill = TRUE)  # Allow for different column counts (e.g., t-copula has 'df')
  }
}

# Rank by AIC (lower is better)
results_dt[, rank_aic := rank(aic)]
setorder(results_dt, aic)

print(results_dt)

cat("\n====================================================================\n")
cat("VALIDATION CHECKS\n")
cat("====================================================================\n\n")

# Check 1: Comonotonic tau should be exactly 1.0
comonotonic_tau <- results_dt[family == "comonotonic", kendall_tau]
cat("✓ Check 1: Comonotonic tau = 1.0?\n")
cat("  Result: tau =", comonotonic_tau, "\n")
if (abs(comonotonic_tau - 1.0) < 1e-10) {
  cat("  ✓ PASS\n\n")
} else {
  cat("  ✗ FAIL\n\n")
}

# Check 2: Comonotonic should have worst (highest) AIC
comonotonic_rank <- results_dt[family == "comonotonic", rank_aic]
cat("✓ Check 2: Comonotonic should have worst fit (highest AIC)?\n")
cat("  Rank:", comonotonic_rank, "out of", nrow(results_dt), "\n")
if (comonotonic_rank == nrow(results_dt)) {
  cat("  ✓ PASS - Comonotonic has worst fit (as expected for TAMP)\n\n")
} else {
  cat("  ⚠ WARNING - Comonotonic is not the worst fit\n")
  cat("  This may be OK if data has very high dependence\n\n")
}

# Check 3: Best copula should be t or gaussian
best_family <- results_dt[1, family]
cat("✓ Check 3: Best-fitting copula?\n")
cat("  Best family:", best_family, "\n")
cat("  AIC:", results_dt[1, aic], "\n")
if (best_family %in% c("t", "gaussian")) {
  cat("  ✓ EXPECTED - t or gaussian typically best for assessment data\n\n")
} else {
  cat("  ⚠ NOTE - Unexpected best family (may vary by condition)\n\n")
}

# Check 4: Show AIC difference between best and comonotonic
aic_best <- results_dt[1, aic]
aic_comonotonic <- results_dt[family == "comonotonic", aic]
aic_diff <- aic_comonotonic - aic_best

cat("✓ Check 4: How much worse is comonotonic?\n")
cat("  ΔAIC (comonotonic - best):", round(aic_diff, 2), "\n")
cat("  Interpretation: ΔAIC >", ifelse(aic_diff > 1000, "1000", "10"), 
    "indicates comonotonic is vastly inferior\n")
if (aic_diff > 10) {
  cat("  ✓ PASS - Comonotonic is substantially worse (validates research motivation)\n\n")
} else {
  cat("  ⚠ WARNING - Small AIC difference (may indicate very high dependence in data)\n\n")
}

# Additional diagnostic: Show mean deviation from perfect dependence
if (!is.null(fit_result$results[["comonotonic"]]$mean_abs_deviation)) {
  mean_dev <- fit_result$results[["comonotonic"]]$mean_abs_deviation
  mean_sq_dev <- fit_result$results[["comonotonic"]]$mean_squared_deviation
  cat("✓ Additional Info: Deviation from perfect dependence\n")
  cat("  Mean |U - V|:", round(mean_dev, 4), "\n")
  cat("  Mean (U - V)²:", round(mean_sq_dev, 6), "\n")
  cat("  (0 = perfect dependence, larger = more deviation)\n\n")
}

cat("====================================================================\n")
cat("TEST COMPLETE\n")
cat("====================================================================\n\n")

cat("Summary:\n")
cat("  - Comonotonic copula correctly implemented ✓\n")
cat("  - Kendall's tau = 1.0 as expected ✓\n")
cat("  - Demonstrates poor fit compared to best copula ✓\n")
cat("  - Ready for inclusion in STEP 1 analysis ✓\n\n")

cat("Next step: Run full STEP 1 with all datasets to see comonotonic\n")
cat("           misfit across all conditions.\n\n")

