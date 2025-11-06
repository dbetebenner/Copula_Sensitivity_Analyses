# Manual Testing Guide: GoF with M=100

## Purpose
Test realistic production timing (M=100) on a single cohort-pair before running the full analysis.

---

## Quick Start

### Option 1: Run Complete Test Script (Recommended)
```bash
cd ~/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses
Rscript test_manual_M100.R
```

**Expected runtime:** 30-40 minutes  
**Output:** Complete timing analysis and projections for full dataset

---

### Option 2: Manual Interactive Testing

**Step 1: Open R Console**
```bash
cd ~/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses
R
```

**Step 2: Load Functions**
```r
# Check gofCopula version
packageVersion("gofCopula")  # Should be >= 0.4.4

# Load functions
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")
require(data.table)
require(copula)
require(gofCopula)
```

**Step 3: Load Data and Create Test Condition**
```r
# Load dataset 1
load("Data/Copula_Sensitivity_Data_Set_1.Rdata")

# Create single condition: MATH Grade 4->5, 2010->2011
pairs_data <- create_longitudinal_pairs(
  Copula_Sensitivity_Data_Set_1,
  content_prior = "MATHEMATICS",
  content_current = "MATHEMATICS",
  grade_prior = 4,
  grade_current = 5,
  year_prior = 2010,
  year_current = 2011
)

cat("Pairs created:", nrow(pairs_data), "\n")
```

**Step 4: Run GoF Test with M=100**
```r
# Set configuration
M_BOOTSTRAP <- 100
COPULA_FAMILIES <- c("gaussian", "t", "clayton", "gumbel", "frank")

# Start timer
start_time <- Sys.time()

# Fit copulas with GoF testing
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

# Calculate elapsed time
end_time <- Sys.time()
elapsed_mins <- as.numeric(difftime(end_time, start_time, units = "mins"))

cat("\nTotal time:", round(elapsed_mins, 1), "minutes\n")
```

**Step 5: Review Results**
```r
# Display results table
for (fam in names(fit_results$results)) {
  result <- fit_results$results[[fam]]
  cat(sprintf("%-15s | Method: %-30s | p-value: %.4f\n",
              fam, 
              substr(result$gof_method, 1, 30),
              result$gof_pvalue))
}

# Calculate projections
time_per_condition <- elapsed_mins
cat("\nProjected times:\n")
cat("  Dataset 1 (28 conditions, M=100):", 
    round(time_per_condition * 28 / 60, 1), "hours\n")
cat("  All datasets (129 conditions, M=100):", 
    round(time_per_condition * 129 / 60, 1), "hours\n")
cat("  All datasets (129 conditions, M=1000):", 
    round(time_per_condition * 129 * 10 / 60, 1), "hours\n")
```

---

## Expected Results

### Timing (M=100, single condition):
- **Total time:** 30-40 minutes
- **Time per family:** ~6-8 minutes

### GoF Results (all should pass):
```
Family          | Method                         | p-value
----------------|--------------------------------|----------
gaussian        | gofKendallCvM_M=100           | 0.2-0.8
t               | gofKendallCvM_M=100           | 0.5-0.9
clayton         | gofKendallCvM_M=100           | 0.01-0.2
gumbel          | gofKendallCvM_M=100           | 0.01-0.2
frank           | gofKendallCvM_M=100           | 0.1-0.7
```

### Projections for Full Analysis:
- **Dataset 1 (28 conditions, M=100):** ~18-22 hours
- **All datasets (129 conditions, M=100):** ~85 hours (3.5 days)
- **All datasets (129 conditions, M=1000):** ~850 hours (35 days)

---

## Troubleshooting

### "gofCopula version too old" Error
**Solution:** Rebuild the package with fixes:
```bash
cd ~/GitHub/DBetebenner/gofCopula/main
R CMD INSTALL .
```

### T-Copula Still Failing
**Check 1:** Verify gofCopula version
```r
packageVersion("gofCopula")  # Must be >= 0.4.4
```

**Check 2:** Look for error in gof_method
```r
fit_results$results$t$gof_method
# Should be: "gofKendallCvM_M=100"
# NOT: "gofCopula_failed: ..."
```

### Performance Issues (> 40 min per condition)
- **Check:** System activity (other processes running?)
- **Check:** Data size (should be ~25,000-35,000 pairs)
- **Try:** Close other applications
- **Consider:** Using EC2 for production runs

---

## After Manual Testing

### If results look good:
1. ✓ All 5 families complete with p-values
2. ✓ T-copula uses `gofKendallCvM_M=100`
3. ✓ Timing is reasonable (~30-40 min)

**Next steps:**
- Run `run_test_ultrafast_single.R` to verify full pipeline
- Consider starting with M=100 for full dataset (3.5 days)
- Scale up to M=1000 for final publication results (on EC2)

### If issues detected:
- Review error messages carefully
- Check gofCopula package version
- Re-run with M=10 for faster debugging
- Consult `BUGFIX_SUMMARY.md` in gofCopula package

---

## Questions?

See also:
- `test_manual_M100.R` - Automated version of this test
- `run_test_ultrafast_single.R` - Quick M=10 test (3-4 min)
- `BUGFIX_SUMMARY.md` - Details on gofCopula fixes
- `EC2_SETUP.md` - Instructions for production runs

---

**Last updated:** November 4, 2025

