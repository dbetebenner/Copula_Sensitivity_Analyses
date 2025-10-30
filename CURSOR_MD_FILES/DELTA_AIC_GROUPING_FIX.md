# Delta AIC Grouping Fix: Statistical Correction for Multi-Dataset Analysis

**Date:** 2025-10-24  
**Status:** ✅ COMPLETE (with follow-up sequencing fix)  
**Impact:** CRITICAL - Corrects model comparison statistics across datasets

**Update:** Fixed sequencing bug where dataset_id was referenced before it was added to results_dt.

## Problem

### Statistical Issue
When calculating `delta_aic_vs_best` (the difference between each model's AIC and the best model's AIC for that condition), the code was grouping only by `condition_id`:

```r
# INCORRECT:
results_dt[, delta_aic_vs_best := aic - min(aic), by = condition_id]
```

**Why This is Wrong:**
- `condition_id` is **NOT unique across datasets**
- Dataset 1 has conditions 1-28
- Dataset 2 has conditions 1-21  
- Dataset 3 has conditions 1-80

This caused the code to find the minimum AIC across **all datasets** for conditions sharing the same ID number:
- Dataset 1's condition 5 and Dataset 2's condition 5 shared the same minimum
- Dataset 1's condition 10, Dataset 2's condition 10, and Dataset 3's condition 10 shared the same minimum
- Etc.

**Result:** Delta AIC values were incorrect, mixing model comparisons across completely different datasets and longitudinal spans.

## Solution

Add `dataset_id` to the grouping to ensure uniqueness:

```r
# CORRECT:
results_dt[, delta_aic_vs_best := aic - min(aic), by = .(dataset_id, condition_id)]
```

Now each dataset's conditions are grouped independently, ensuring the minimum AIC is found within the correct condition only.

## Changes Made

### 1. **phase1_analysis.R** (Lines 26-33)
**Impact:** Immediate fix for current analysis without re-running computation

Added recalculation of delta AIC after loading the CSV:
```r
# CRITICAL FIX: Recalculate delta_aic_vs_best with correct grouping
# Must group by (dataset_id, condition_id) to ensure uniqueness across datasets
# Without dataset_id, conditions with the same ID across different datasets 
# would incorrectly share the same minimum AIC
cat("Recalculating delta AIC with proper dataset grouping...\n")
results[, delta_aic_vs_best := aic - min(aic), by = .(dataset_id, condition_id)]
results[, delta_bic_vs_best := bic - min(bic), by = .(dataset_id, condition_id)]
cat("Delta AIC range:", range(results$delta_aic_vs_best), "\n\n")
```

This allows the analysis to proceed with corrected statistics **without re-running the expensive copula fitting**.

### 2. **phase1_family_selection.R** (Lines 381-387)
**Impact:** Future runs will have correct calculation from the start

Fixed all grouping operations:
```r
# Calculate best family for each condition (group by dataset_id + condition_id for uniqueness)
results_dt[, best_aic := family[which.min(aic)], by = .(dataset_id, condition_id)]
results_dt[, best_bic := family[which.min(bic)], by = .(dataset_id, condition_id)]

# Calculate delta from best (group by dataset_id + condition_id for uniqueness)
results_dt[, delta_aic_vs_best := aic - min(aic), by = .(dataset_id, condition_id)]
results_dt[, delta_bic_vs_best := bic - min(bic), by = .(dataset_id, condition_id)]
```

### 3. **phase1_family_selection_parallel.R** (Lines 395-401)
**Impact:** Future parallel runs will have correct calculation from the start

Applied identical fixes to the parallel version.

## Statistical Context: Why This Matters

### AIC and Sample Size
- **AIC Formula:** \( \text{AIC} = -2\log(L) + 2k \)
- Log-likelihood \( \log(L) \) scales with sample size \( n \)
- **Raw AIC values are NOT comparable across different sample sizes**

### Valid Comparisons
✅ **VALID:** Delta AIC within the same condition (same data, same n)
```r
# Comparing t-copula vs Gaussian for condition X in dataset Y
delta_aic = aic_gaussian - aic_t  # Valid!
```

❌ **INVALID:** Mixing minimum AIC across conditions with different data
```r
# Finding min(AIC) across dataset_1's condition_5 AND dataset_2's condition_5
# These are COMPLETELY DIFFERENT datasets with different n!
```

### Implications
**Before the fix:**
- "Best model" for a condition might actually be from a different dataset
- Delta AIC values were contaminated by cross-dataset comparisons
- Model selection frequencies and mean delta AIC statistics were incorrect

**After the fix:**
- Each condition's "best model" is correctly identified within its own dataset
- Delta AIC properly measures model improvement within each condition
- Statistical summaries (mean delta AIC, selection frequencies) are now valid

## How to Use

### For Current Results (No Re-computation Needed)
Simply re-run the analysis script:
```r
source("STEP_1_Family_Selection/phase1_analysis.R")
```

This will:
1. Load existing CSV results
2. Recalculate delta AIC correctly
3. Regenerate all plots and summaries with corrected statistics
4. **Takes only seconds**, not hours!

### For Future Runs
The fix is now embedded in both:
- `phase1_family_selection.R` (sequential)
- `phase1_family_selection_parallel.R` (parallel)

All future runs will automatically calculate delta AIC correctly from the start.

## Verification

After re-running the analysis, check:

1. **Delta AIC Distribution:** 
   - Should see a cleaner distribution centered at 0 for the winning family
   - No artificially inflated or deflated values from cross-dataset contamination

2. **Selection Frequencies:**
   - May change slightly as "best model" is now correctly identified per condition
   - Should reflect true model preference within each dataset

3. **Mean Delta AIC:**
   - Will be more accurate for assessing model improvement
   - Can now confidently apply Burnham & Anderson thresholds:
     - Δ AIC < 2: Substantial support
     - Δ AIC 4-7: Considerably less support
     - Δ AIC > 10: Essentially no support

## Related Fixes

This completes the multi-dataset statistical integrity checks:

1. ✅ Unique composite keys: `(dataset_id, condition_id)` for joins
2. ✅ Proper grouping for delta AIC calculations
3. ✅ Dataset-specific result directories
4. ✅ Combined results with dataset metadata
5. ✅ Correct handling of condition_id reuse across datasets

## Key Lesson

**In multi-dataset analyses:**
- Never assume IDs are globally unique
- Always use composite keys that include the dataset identifier
- Validate that statistical comparisons are within the appropriate scope
- AIC/BIC comparisons are only valid within the same data/sample

---

## Follow-up Fix: Sequencing Bug (2025-10-24)

### The Issue
After implementing the `(dataset_id, condition_id)` composite key fix, a sequencing bug was introduced:

**In `phase1_family_selection.R` and `phase1_family_selection_parallel.R`:**
- Lines ~395-401 tried to group by `.(dataset_id, condition_id)`
- But `dataset_id` column wasn't added until lines ~417-419
- Result: data.table found scalar variable `dataset_id` from environment (length 1) instead of the column
- Error: "items in the 'by' list have lengths [1, 252]"

### The Solution
Reverted to grouping by `condition_id` alone in the individual dataset scripts:

```r
# Calculate best family for each condition
# NOTE: Within a single dataset run, condition_id is unique, so we only need to group by condition_id here.
# Multi-dataset aggregation (grouping by dataset_id + condition_id) happens later in phase1_analysis.R
# when results from all datasets are combined.
results_dt[, best_aic := family[which.min(aic)], by = condition_id]
results_dt[, best_bic := family[which.min(bic)], by = condition_id]
results_dt[, delta_aic_vs_best := aic - min(aic), by = condition_id]
results_dt[, delta_bic_vs_best := bic - min(bic), by = condition_id]
```

### Why This Works
1. **Each script processes ONE dataset at a time** → `condition_id` IS unique within that run
2. **The composite key is only needed when combining datasets** → handled in `phase1_analysis.R`
3. **Separation of concerns**: Individual scripts calculate within-dataset metrics; analysis script handles cross-dataset aggregation

### Files Fixed
- `STEP_1_Family_Selection/phase1_family_selection.R` (lines 381-390)
- `STEP_1_Family_Selection/phase1_family_selection_parallel.R` (lines 395-404)

---

**Status**: All fixes complete and tested. Ready for full 3-dataset run.  
**Computation time**: Seconds (analysis only), not hours (no copula refitting needed).

