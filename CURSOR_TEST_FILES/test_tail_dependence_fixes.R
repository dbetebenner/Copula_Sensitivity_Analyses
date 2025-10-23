############################################################################
### Quick Test: Tail Dependence Fixes Validation
############################################################################
# This script validates the two critical tail dependence fixes:
# 1. Free t-copula now uses manual calculation (no more NaN)
# 2. Comonotonic copula now has perfect tail dependence in both tails (1.0, 1.0)

require(data.table)
require(copula)

# Load helper functions
source("functions/copula_bootstrap.R")

cat("\n")
cat("="*80, "\n", sep="")
cat("TAIL DEPENDENCE FIXES VALIDATION TEST\n")
cat("="*80, "\n\n", sep="")

# Load a sample dataset
cat("Loading sample data...\n")
load("Data/Copula_Sensitivity_Data_Set_1.Rdata")

# Get a sample pair for testing
test_data <- STATE_DATA_LONG[
  YEAR == "2013" & 
  GRADE == 4 & 
  CONTENT_AREA == "MATHEMATICS" &
  !is.na(SCALE_SCORE_PRIOR) & 
  !is.na(SCALE_SCORE)
]

cat("  Sample size:", nrow(test_data), "\n\n")

# Test all copula families including the problematic ones
families_to_test <- c("gaussian", "t", "t_df5", "t_df10", "t_df15", "frank", "comonotonic")

cat("Fitting copulas (using empirical ranks for Phase 1 comparison)...\n\n")

results <- fit_copula_from_pairs(
  scores_prior = test_data$SCALE_SCORE_PRIOR,
  scores_current = test_data$SCALE_SCORE,
  framework_prior = NULL,
  framework_current = NULL,
  copula_families = families_to_test,
  return_best = FALSE,
  use_empirical_ranks = TRUE
)

# Display results
cat("="*80, "\n", sep="")
cat("TAIL DEPENDENCE RESULTS\n")
cat("="*80, "\n\n", sep="")

results_table <- data.table(
  Family = character(),
  Kendall_Tau = numeric(),
  Lower_Tail = numeric(),
  Upper_Tail = numeric(),
  Parameter_1 = numeric(),
  Parameter_2 = numeric(),
  AIC = numeric()
)

for (fam in families_to_test) {
  if (!is.null(results$results[[fam]])) {
    res <- results$results[[fam]]
    
    lower_tail <- if (!is.null(res$tail_dependence_lower)) res$tail_dependence_lower else 0
    upper_tail <- if (!is.null(res$tail_dependence_upper)) res$tail_dependence_upper else 0
    param_1 <- if (!is.null(res$parameter)) res$parameter else NA
    param_2 <- if (!is.null(res$df)) res$df else NA
    
    results_table <- rbind(results_table, data.table(
      Family = fam,
      Kendall_Tau = round(res$kendall_tau, 4),
      Lower_Tail = round(lower_tail, 4),
      Upper_Tail = round(upper_tail, 4),
      Parameter_1 = round(param_1, 4),
      Parameter_2 = if (!is.na(param_2)) round(param_2, 2) else NA,
      AIC = round(res$aic, 1)
    ))
  }
}

print(results_table)

cat("\n")
cat("="*80, "\n", sep="")
cat("VALIDATION CHECKS\n")
cat("="*80, "\n\n", sep="")

# Check 1: Free t-copula should have NON-NaN tail dependence
free_t <- results_table[Family == "t"]
cat("✓ Check 1: Free t-copula tail dependence\n")
cat("  Lower tail:", free_t$Lower_Tail, "\n")
cat("  Upper tail:", free_t$Upper_Tail, "\n")
if (!is.na(free_t$Lower_Tail) && !is.na(free_t$Upper_Tail)) {
  cat("  ✅ SUCCESS: No NaN values!\n")
} else {
  cat("  ❌ FAILED: Still getting NaN!\n")
}
cat("\n")

# Check 2: Comonotonic should have PERFECT tail dependence (1.0, 1.0)
comono <- results_table[Family == "comonotonic"]
cat("✓ Check 2: Comonotonic copula tail dependence\n")
cat("  Lower tail:", comono$Lower_Tail, "\n")
cat("  Upper tail:", comono$Upper_Tail, "\n")
if (abs(comono$Lower_Tail - 1.0) < 0.001 && abs(comono$Upper_Tail - 1.0) < 0.001) {
  cat("  ✅ SUCCESS: Perfect tail dependence (1.0, 1.0)!\n")
} else {
  cat("  ❌ FAILED: Not showing perfect tail dependence!\n")
}
cat("\n")

# Check 3: Fixed df t-copulas should show INCREASING tail dependence as df DECREASES
cat("✓ Check 3: Fixed df t-copula tail dependence ordering\n")
t_df5 <- results_table[Family == "t_df5"]
t_df10 <- results_table[Family == "t_df10"]
t_df15 <- results_table[Family == "t_df15"]

cat("  t_df5  (strong):        λ =", t_df5$Lower_Tail, "\n")
cat("  t_df10 (moderate-strong): λ =", t_df10$Lower_Tail, "\n")
cat("  t_df15 (moderate-weak): λ =", t_df15$Lower_Tail, "\n")

if (t_df5$Lower_Tail > t_df10$Lower_Tail && t_df10$Lower_Tail > t_df15$Lower_Tail) {
  cat("  ✅ SUCCESS: Correct ordering (df5 > df10 > df15)!\n")
} else {
  cat("  ⚠ WARNING: Unexpected ordering!\n")
}
cat("\n")

# Check 4: Comonotonic should have WORST fit (highest AIC)
cat("✓ Check 4: Comonotonic copula fit quality\n")
cat("  AIC rank (1 = best, higher = worse):\n")
results_table_sorted <- results_table[order(AIC)]
results_table_sorted[, Rank := 1:.N]
print(results_table_sorted[, .(Family, AIC, Rank)])
cat("\n")

comono_rank <- results_table_sorted[Family == "comonotonic", Rank]
if (comono_rank == max(results_table_sorted$Rank)) {
  cat("  ✅ SUCCESS: Comonotonic has worst fit (as expected)!\n")
} else {
  cat("  ⚠ WARNING: Comonotonic not showing worst fit!\n")
}

cat("\n")
cat("="*80, "\n", sep="")
cat("VALIDATION COMPLETE\n")
cat("="*80, "\n\n", sep="")
cat("If all checks passed, you're ready to re-run the full analysis!\n\n")

